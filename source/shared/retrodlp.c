#include "retrodlp/retrodlp.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <curl/curl.h>
#include <pthread.h>

#include "yt_http.h"
#include "yt_playlist.h"
#include "yt_resolver.h"

#define RDLP_DEFAULT_TIMEOUT_MILLISECONDS 20000UL
#define HAS_FIELD(value, type, field)                                           \
  ((value)->struct_size >= offsetof(type, field) + sizeof((value)->field))

static pthread_mutex_t curl_lifecycle_mutex = PTHREAD_MUTEX_INITIALIZER;
static size_t curl_context_count;

static int acquire_default_transport(void) {
  int initialized = 1;
  pthread_mutex_lock(&curl_lifecycle_mutex);
  if (curl_context_count == 0 &&
      curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK)
    initialized = 0;
  if (initialized)
    ++curl_context_count;
  pthread_mutex_unlock(&curl_lifecycle_mutex);
  return initialized;
}

static void release_default_transport(void) {
  pthread_mutex_lock(&curl_lifecycle_mutex);
  if (curl_context_count != 0 && --curl_context_count == 0)
    curl_global_cleanup();
  pthread_mutex_unlock(&curl_lifecycle_mutex);
}

struct rdlp_context {
  rdlp_transport transport;
  int has_transport;
  int owns_default_transport;
  YTHttpSession *http_session;
  char *cache_directory;
  char *ca_bundle_path;
  char *ejs_asset_directory;
  unsigned long timeout_milliseconds;
  size_t ejs_memory_limit_bytes;
  size_t ejs_stack_limit_bytes;
  rdlp_event_callback event_callback;
  rdlp_cancel_callback cancel_callback;
  void *callback_context;
  rdlp_clock_callback clock_callback;
  void *clock_context;
  pthread_mutex_t operation_mutex;
  int operating;
};

struct rdlp_selection {
  YTMediaSelection value;
  rdlp_http_header headers[2];
  size_t header_counts[2];
};

struct rdlp_playlist {
  YTPlaylist value;
};

static void publish_error(rdlp_error *error, rdlp_status status,
                          const char *message) {
  rdlp_error value;
  size_t size;
  if (error == NULL)
    return;
  size = error->struct_size;
  if (size == 0 || size > sizeof(value))
    size = sizeof(value);
  memset(&value, 0, sizeof(value));
  value.struct_size = sizeof(value);
  value.status = status;
  value.retryable = status == RDLP_STATUS_NETWORK || status == RDLP_STATUS_HTTP;
  if (message != NULL)
    snprintf(value.message, sizeof(value.message), "%s", message);
  memcpy(error, &value, size);
}

static rdlp_status public_status(YTStatus status) {
  switch (status) {
  case YT_OK:
    return RDLP_STATUS_OK;
  case YT_ERR_INVALID_VIDEO_ID:
  case YT_ERR_INVALID_PLAYLIST:
  case YT_ERR_INVALID_FORMAT:
    return RDLP_STATUS_INVALID_ARGUMENT;
  case YT_ERR_OUT_OF_MEMORY:
    return RDLP_STATUS_OUT_OF_MEMORY;
  case YT_ERR_NETWORK:
    return RDLP_STATUS_NETWORK;
  case YT_ERR_CERTIFICATE_BUNDLE:
    return RDLP_STATUS_CERTIFICATE_BUNDLE;
  case YT_ERR_HTTP:
    return RDLP_STATUS_HTTP;
  case YT_ERR_INVALID_RESPONSE:
    return RDLP_STATUS_INVALID_RESPONSE;
  case YT_ERR_UNAVAILABLE:
    return RDLP_STATUS_UNAVAILABLE;
  case YT_ERR_NO_PROGRESSIVE_MP4:
  case YT_ERR_FORMAT_UNAVAILABLE:
    return RDLP_STATUS_FORMAT_UNAVAILABLE;
  case YT_ERR_EJS_ASSETS_MISSING:
    return RDLP_STATUS_EJS_ASSETS_MISSING;
  case YT_ERR_JS_CHALLENGE:
    return RDLP_STATUS_JS_CHALLENGE;
  case YT_ERR_PO_TOKEN_REQUIRED:
  case YT_ERR_AUTH_COOKIES_INVALID:
    return RDLP_STATUS_AUTHENTICATION_REQUIRED;
  case YT_ERR_COOKIE_FILE:
    return RDLP_STATUS_COOKIE;
  case YT_ERR_CANCELLED:
    return RDLP_STATUS_CANCELLED;
  case YT_ERR_FILE_EXISTS:
  case YT_ERR_STORAGE:
    return RDLP_STATUS_STORAGE;
  default:
    return RDLP_STATUS_INTERNAL;
  }
}

static rdlp_status finish_status(YTStatus status, rdlp_error *error) {
  rdlp_status result = public_status(status);
  publish_error(error, result, yt_status_string(status));
  return result;
}

static rdlp_status finish_session_status(YTStatus status,
                                         YTHttpSession *session,
                                         rdlp_error *error) {
  YTHttpDiagnostic diagnostic;
  rdlp_status result = finish_status(status, error);
  yt_http_session_diagnostic(session, &diagnostic);
  if (error != NULL) {
    if (HAS_FIELD(error, rdlp_error, http_status))
      error->http_status = diagnostic.http_status;
    if (HAS_FIELD(error, rdlp_error, transport_code))
      error->transport_code = diagnostic.transport_code;
    if (diagnostic.message[0] != '\0' &&
        HAS_FIELD(error, rdlp_error, message))
      snprintf(error->message, sizeof(error->message), "%s",
               diagnostic.message);
  }
  return result;
}

static char *copy_string(const char *value) {
  size_t length;
  char *copy;
  if (value == NULL)
    return NULL;
  length = strlen(value);
  copy = (char *)malloc(length + 1);
  if (copy != NULL)
    memcpy(copy, value, length + 1);
  return copy;
}

static int context_cancelled(void *opaque);

static void fill_session_config(rdlp_context *context,
                                YTHttpSessionConfig *config) {
  memset(config, 0, sizeof(*config));
  config->transport = context->has_transport ? &context->transport : NULL;
  config->timeout_milliseconds = context->timeout_milliseconds;
  config->cache_directory = context->cache_directory;
  config->ca_bundle_path = context->ca_bundle_path;
  config->ejs_asset_directory = context->ejs_asset_directory;
  config->ejs_memory_limit_bytes = context->ejs_memory_limit_bytes;
  config->ejs_stack_limit_bytes = context->ejs_stack_limit_bytes;
  config->cancel_callback = context_cancelled;
  config->cancel_opaque = context;
  config->clock_callback = context->clock_callback;
  config->clock_opaque = context->clock_context;
}

const char *rdlp_version_string(void) { return RDLP_VERSION_STRING; }

const char *rdlp_status_string(rdlp_status status) {
  switch (status) {
  case RDLP_STATUS_OK:
    return "success";
  case RDLP_STATUS_INVALID_ARGUMENT:
    return "invalid argument";
  case RDLP_STATUS_OUT_OF_MEMORY:
    return "out of memory";
  case RDLP_STATUS_NETWORK:
    return "network request failed";
  case RDLP_STATUS_CERTIFICATE_BUNDLE:
    return "CA certificate bundle unavailable";
  case RDLP_STATUS_HTTP:
    return "HTTP request failed";
  case RDLP_STATUS_INVALID_RESPONSE:
    return "invalid service response";
  case RDLP_STATUS_UNAVAILABLE:
    return "media unavailable";
  case RDLP_STATUS_FORMAT_UNAVAILABLE:
    return "requested format unavailable";
  case RDLP_STATUS_EJS_ASSETS_MISSING:
    return "EJS assets unavailable";
  case RDLP_STATUS_JS_CHALLENGE:
    return "JavaScript challenge failed";
  case RDLP_STATUS_AUTHENTICATION_REQUIRED:
    return "authentication required";
  case RDLP_STATUS_COOKIE:
    return "invalid cookie data";
  case RDLP_STATUS_CANCELLED:
    return "operation cancelled";
  case RDLP_STATUS_BUSY:
    return "context is busy";
  case RDLP_STATUS_STORAGE:
    return "storage error";
  case RDLP_STATUS_INTERNAL:
    return "internal error";
  }
  return "unknown error";
}

rdlp_status rdlp_context_create(const rdlp_config *config,
                                rdlp_context **context, rdlp_error *error) {
  rdlp_context *created;
  YTHttpSessionConfig session_config;
  YTStatus session_status;
  if (context == NULL) {
    publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                  "context output pointer is required");
    return RDLP_STATUS_INVALID_ARGUMENT;
  }
  *context = NULL;
  if (config != NULL && config->struct_size < sizeof(config->struct_size)) {
    publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                  "configuration structure is too small");
    return RDLP_STATUS_INVALID_ARGUMENT;
  }
  created = (rdlp_context *)calloc(1, sizeof(*created));
  if (created == NULL) {
    publish_error(error, RDLP_STATUS_OUT_OF_MEMORY, "out of memory");
    return RDLP_STATUS_OUT_OF_MEMORY;
  }
  if (pthread_mutex_init(&created->operation_mutex, NULL) != 0) {
    free(created);
    publish_error(error, RDLP_STATUS_INTERNAL,
                  "could not initialize context synchronization");
    return RDLP_STATUS_INTERNAL;
  }
  created->timeout_milliseconds = RDLP_DEFAULT_TIMEOUT_MILLISECONDS;
  if (config != NULL) {
    if (HAS_FIELD(config, rdlp_config, network_timeout_milliseconds) &&
        config->network_timeout_milliseconds != 0)
      created->timeout_milliseconds = config->network_timeout_milliseconds;
    if (HAS_FIELD(config, rdlp_config, event_callback))
      created->event_callback = config->event_callback;
    if (HAS_FIELD(config, rdlp_config, cancel_callback))
      created->cancel_callback = config->cancel_callback;
    if (HAS_FIELD(config, rdlp_config, callback_context))
      created->callback_context = config->callback_context;
    if (HAS_FIELD(config, rdlp_config, cache_directory) &&
        config->cache_directory != NULL)
      created->cache_directory = copy_string(config->cache_directory);
    if (HAS_FIELD(config, rdlp_config, ca_bundle_path) &&
        config->ca_bundle_path != NULL)
      created->ca_bundle_path = copy_string(config->ca_bundle_path);
    if (HAS_FIELD(config, rdlp_config, ejs_asset_directory) &&
        config->ejs_asset_directory != NULL)
      created->ejs_asset_directory = copy_string(config->ejs_asset_directory);
    if ((HAS_FIELD(config, rdlp_config, cache_directory) &&
         config->cache_directory != NULL &&
         created->cache_directory == NULL) ||
        (HAS_FIELD(config, rdlp_config, ca_bundle_path) &&
         config->ca_bundle_path != NULL && created->ca_bundle_path == NULL) ||
        (HAS_FIELD(config, rdlp_config, ejs_asset_directory) &&
         config->ejs_asset_directory != NULL &&
         created->ejs_asset_directory == NULL)) {
      rdlp_context_destroy(created);
      publish_error(error, RDLP_STATUS_OUT_OF_MEMORY, "out of memory");
      return RDLP_STATUS_OUT_OF_MEMORY;
    }
    if ((created->cache_directory != NULL &&
         created->cache_directory[0] != '/') ||
        (created->ca_bundle_path != NULL &&
         created->ca_bundle_path[0] != '/') ||
        (created->ejs_asset_directory != NULL &&
         created->ejs_asset_directory[0] != '/')) {
      rdlp_context_destroy(created);
      publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                    "configured paths must be absolute");
      return RDLP_STATUS_INVALID_ARGUMENT;
    }
    if (HAS_FIELD(config, rdlp_config, ejs_memory_limit_bytes))
      created->ejs_memory_limit_bytes = config->ejs_memory_limit_bytes;
    if (HAS_FIELD(config, rdlp_config, ejs_stack_limit_bytes))
      created->ejs_stack_limit_bytes = config->ejs_stack_limit_bytes;
    if (HAS_FIELD(config, rdlp_config, transport) &&
        config->transport != NULL) {
      if (config->transport->struct_size < sizeof(*config->transport) ||
          config->transport->send == NULL) {
        rdlp_context_destroy(created);
        publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                      "transport structure is invalid");
        return RDLP_STATUS_INVALID_ARGUMENT;
      }
      created->transport = *config->transport;
      created->has_transport = 1;
    }
    if (HAS_FIELD(config, rdlp_config, clock_callback))
      created->clock_callback = config->clock_callback;
    if (HAS_FIELD(config, rdlp_config, clock_context))
      created->clock_context = config->clock_context;
  }
  if (!created->has_transport && !acquire_default_transport()) {
    rdlp_context_destroy(created);
    publish_error(error, RDLP_STATUS_NETWORK,
                  "could not initialize default HTTP transport");
    return RDLP_STATUS_NETWORK;
  }
  if (!created->has_transport)
    created->owns_default_transport = 1;
  fill_session_config(created, &session_config);
  session_status =
      yt_http_session_create_with_config(&session_config,
                                         &created->http_session);
  if (session_status != YT_OK) {
    rdlp_context_destroy(created);
    return finish_status(session_status, error);
  }
  *context = created;
  publish_error(error, RDLP_STATUS_OK, "success");
  return RDLP_STATUS_OK;
}

void rdlp_context_destroy(rdlp_context *context) {
  if (context == NULL)
    return;
  yt_http_session_destroy(context->http_session);
  if (context->owns_default_transport)
    release_default_transport();
  pthread_mutex_destroy(&context->operation_mutex);
  free(context->cache_directory);
  free(context->ca_bundle_path);
  free(context->ejs_asset_directory);
  free(context);
}

rdlp_status rdlp_parse_video_id(const char *input, char video_id[12],
                                rdlp_error *error) {
  YTStatus status;
  if (video_id != NULL)
    video_id[0] = '\0';
  if (input == NULL || video_id == NULL) {
    publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                  "input and video ID output are required");
    return RDLP_STATUS_INVALID_ARGUMENT;
  }
  status = yt_extract_video_id(input, video_id);
  return finish_status(status, error);
}

rdlp_status rdlp_parse_playlist_id(const char *input, char *playlist_id,
                                   size_t playlist_id_size,
                                   rdlp_error *error) {
  YTStatus status;
  if (playlist_id != NULL && playlist_id_size != 0)
    playlist_id[0] = '\0';
  if (input == NULL || playlist_id == NULL || playlist_id_size == 0) {
    publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                  "input and playlist ID output are required");
    return RDLP_STATUS_INVALID_ARGUMENT;
  }
  status = yt_extract_playlist_id(input, playlist_id, playlist_id_size);
  return finish_status(status, error);
}

static int context_cancelled(void *opaque) {
  rdlp_context *context = (rdlp_context *)opaque;
  return context->cancel_callback != NULL &&
         context->cancel_callback(context->callback_context);
}

static rdlp_event_type event_type(const char *message) {
  if (strstr(message, "configuration") != NULL)
    return RDLP_EVENT_LOADING_CONFIGURATION;
  if (strstr(message, "web player") != NULL ||
      strstr(message, "webpage") != NULL)
    return RDLP_EVENT_FETCHING_BOOTSTRAP;
  if (strstr(message, "metadata") != NULL)
    return RDLP_EVENT_REQUESTING_METADATA;
  if (strstr(message, "JavaScript") != NULL)
    return RDLP_EVENT_LOADING_PLAYER_JAVASCRIPT;
  if (strstr(message, "challenges") != NULL)
    return RDLP_EVENT_SOLVING_CHALLENGES;
  if (strstr(message, "selecting") != NULL)
    return RDLP_EVENT_SELECTING_FORMATS;
  if (strstr(message, "playlist") != NULL)
    return RDLP_EVENT_ENUMERATING_PLAYLIST;
  return RDLP_EVENT_OTHER;
}

static void facade_progress(const char *message, void *opaque) {
  rdlp_context *context = (rdlp_context *)opaque;
  rdlp_event event;
  if (context->event_callback == NULL)
    return;
  memset(&event, 0, sizeof(event));
  event.struct_size = sizeof(event);
  event.type = event_type(message);
  context->event_callback(&event, context->callback_context);
}

static rdlp_status begin_operation(rdlp_context *context, rdlp_error *error) {
  if (context == NULL) {
    publish_error(error, RDLP_STATUS_INVALID_ARGUMENT, "context is required");
    return RDLP_STATUS_INVALID_ARGUMENT;
  }
  pthread_mutex_lock(&context->operation_mutex);
  if (context->operating) {
    pthread_mutex_unlock(&context->operation_mutex);
    publish_error(error, RDLP_STATUS_BUSY, "context is already in use");
    return RDLP_STATUS_BUSY;
  }
  if (context_cancelled(context)) {
    pthread_mutex_unlock(&context->operation_mutex);
    publish_error(error, RDLP_STATUS_CANCELLED, "operation cancelled");
    return RDLP_STATUS_CANCELLED;
  }
  context->operating = 1;
  pthread_mutex_unlock(&context->operation_mutex);
  return RDLP_STATUS_OK;
}

static void end_operation(rdlp_context *context) {
  pthread_mutex_lock(&context->operation_mutex);
  context->operating = 0;
  pthread_mutex_unlock(&context->operation_mutex);
}

static YTStatus operation_session(rdlp_context *context,
                                  const char *cookie_file,
                                  const void *cookie_data,
                                  size_t cookie_data_length,
                                  YTHttpSession **session) {
  YTStatus status = yt_http_session_set_cookies(
      context->http_session, cookie_file, cookie_data, cookie_data_length);
  *session = status == YT_OK ? context->http_session : NULL;
  return status;
}

rdlp_status rdlp_resolve_video(rdlp_context *context, const char *input,
                               const rdlp_resolve_options *options,
                               rdlp_selection **selection,
                               rdlp_error *error) {
  rdlp_selection *created;
  YTHttpSession *session;
  YTStatus status;
  rdlp_status started;
  const char *cookie_file = NULL;
  const void *cookie_data = NULL;
  size_t cookie_data_length = 0;
  const char *format_expression = NULL;
  int maximum_height = YT_DEFAULT_MAX_HEIGHT;
  int prefer_adaptive = 0;
  int include_format_inventory = 0;
  if (selection == NULL) {
    publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                  "selection output pointer is required");
    return RDLP_STATUS_INVALID_ARGUMENT;
  }
  *selection = NULL;
  if (input == NULL ||
      (options != NULL &&
       options->struct_size < sizeof(options->struct_size))) {
    publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                  "input or resolve options are invalid");
    return RDLP_STATUS_INVALID_ARGUMENT;
  }
  if (options != NULL) {
    if (HAS_FIELD(options, rdlp_resolve_options, cookie_file))
      cookie_file = options->cookie_file;
    if (HAS_FIELD(options, rdlp_resolve_options, cookie_data))
      cookie_data = options->cookie_data;
    if (HAS_FIELD(options, rdlp_resolve_options, cookie_data_length))
      cookie_data_length = options->cookie_data_length;
    if ((cookie_data == NULL) != (cookie_data_length == 0) ||
        (cookie_file != NULL && cookie_data != NULL)) {
      publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                    "cookie file and cookie data options are invalid");
      return RDLP_STATUS_INVALID_ARGUMENT;
    }
    if (HAS_FIELD(options, rdlp_resolve_options, format_expression))
      format_expression = options->format_expression;
    if (HAS_FIELD(options, rdlp_resolve_options, maximum_height) &&
        options->maximum_height != 0)
      maximum_height = options->maximum_height;
    if (HAS_FIELD(options, rdlp_resolve_options, prefer_adaptive))
      prefer_adaptive = options->prefer_adaptive != 0;
    if (HAS_FIELD(options, rdlp_resolve_options, include_format_inventory))
      include_format_inventory = options->include_format_inventory != 0;
  }
  started = begin_operation(context, error);
  if (started != RDLP_STATUS_OK)
    return started;
  created = (rdlp_selection *)calloc(1, sizeof(*created));
  session = NULL;
  status = created == NULL
               ? YT_ERR_OUT_OF_MEMORY
               : operation_session(context, cookie_file, cookie_data,
                                   cookie_data_length, &session);
  if (status == YT_OK) {
    if (format_expression != NULL)
      status = yt_resolve_video_with_http_session_and_format_and_progress(
          session, input, cookie_file, format_expression, 0, &created->value,
          facade_progress, context);
    else
      status = yt_resolve_video_with_http_session_and_size_and_progress(
          session, input, cookie_file, maximum_height, prefer_adaptive,
          &created->value, facade_progress, context);
  }
  if (session != NULL)
    yt_http_session_set_cookies(session, NULL, NULL, 0);
  if (status == YT_OK && context_cancelled(context))
    status = YT_ERR_CANCELLED;
  end_operation(context);
  if (status != YT_OK) {
    rdlp_selection_destroy(created);
    return finish_session_status(status, context->http_session, error);
  }
  if (!include_format_inventory) {
    size_t index;
    for (index = 0; index < created->value.format_count; ++index)
      yt_format_info_free(&created->value.formats[index]);
    free(created->value.formats);
    created->value.formats = NULL;
    created->value.format_count = 0;
  }
  created->headers[0].name = "User-Agent";
  created->headers[0].value = created->value.video.user_agent;
  created->header_counts[0] = created->value.video.user_agent != NULL ? 1 : 0;
  created->headers[1].name = "User-Agent";
  created->headers[1].value = created->value.audio.user_agent;
  created->header_counts[1] = created->value.audio.user_agent != NULL ? 1 : 0;
  *selection = created;
  publish_error(error, RDLP_STATUS_OK, "success");
  return RDLP_STATUS_OK;
}

rdlp_status rdlp_list_playlist(rdlp_context *context, const char *input,
                               const rdlp_playlist_options *options,
                               rdlp_playlist **playlist, rdlp_error *error) {
  rdlp_playlist *created;
  YTHttpSession *session;
  YTStatus status;
  rdlp_status started;
  const char *cookie_file = NULL;
  const void *cookie_data = NULL;
  size_t cookie_data_length = 0;
  if (playlist == NULL) {
    publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                  "playlist output pointer is required");
    return RDLP_STATUS_INVALID_ARGUMENT;
  }
  *playlist = NULL;
  if (input == NULL ||
      (options != NULL && options->struct_size < sizeof(options->struct_size))) {
    publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                  "input or playlist options are invalid");
    return RDLP_STATUS_INVALID_ARGUMENT;
  }
  if (options != NULL) {
    if (HAS_FIELD(options, rdlp_playlist_options, cookie_file))
      cookie_file = options->cookie_file;
    if (HAS_FIELD(options, rdlp_playlist_options, cookie_data))
      cookie_data = options->cookie_data;
    if (HAS_FIELD(options, rdlp_playlist_options, cookie_data_length))
      cookie_data_length = options->cookie_data_length;
    if ((cookie_data == NULL) != (cookie_data_length == 0) ||
        (cookie_file != NULL && cookie_data != NULL)) {
      publish_error(error, RDLP_STATUS_INVALID_ARGUMENT,
                    "cookie file and cookie data options are invalid");
      return RDLP_STATUS_INVALID_ARGUMENT;
    }
  }
  started = begin_operation(context, error);
  if (started != RDLP_STATUS_OK)
    return started;
  created = (rdlp_playlist *)calloc(1, sizeof(*created));
  session = NULL;
  status = created == NULL
               ? YT_ERR_OUT_OF_MEMORY
               : operation_session(context, cookie_file, cookie_data,
                                   cookie_data_length, &session);
  if (status == YT_OK)
    status = yt_list_playlist(session, input, cookie_file, &created->value,
                              facade_progress, context);
  if (session != NULL)
    yt_http_session_set_cookies(session, NULL, NULL, 0);
  if (status == YT_OK && context_cancelled(context))
    status = YT_ERR_CANCELLED;
  end_operation(context);
  if (status != YT_OK) {
    rdlp_playlist_destroy(created);
    return finish_session_status(status, context->http_session, error);
  }
  *playlist = created;
  publish_error(error, RDLP_STATUS_OK, "success");
  return RDLP_STATUS_OK;
}

void rdlp_selection_destroy(rdlp_selection *selection) {
  if (selection == NULL)
    return;
  yt_media_selection_free(&selection->value);
  free(selection);
}

static const YTMediaRequest *media_at(const rdlp_selection *selection,
                                      size_t index) {
  if (selection == NULL || index >= (selection->value.adaptive ? 2U : 1U))
    return NULL;
  return index == 0 ? &selection->value.video : &selection->value.audio;
}

const char *rdlp_selection_video_id(const rdlp_selection *selection) {
  return selection == NULL ? NULL : selection->value.video_id;
}
const char *rdlp_selection_title(const rdlp_selection *selection) {
  return selection == NULL ? NULL : selection->value.title;
}
const char *rdlp_selection_format_id(const rdlp_selection *selection) {
  return selection == NULL ? NULL : selection->value.format_id;
}
int rdlp_selection_is_adaptive(const rdlp_selection *selection) {
  return selection != NULL && selection->value.adaptive;
}
size_t rdlp_selection_media_count(const rdlp_selection *selection) {
  return selection == NULL ? 0U : (selection->value.adaptive ? 2U : 1U);
}
const char *rdlp_selection_media_url(const rdlp_selection *selection,
                                     size_t media_index) {
  const YTMediaRequest *media = media_at(selection, media_index);
  return media == NULL ? NULL : media->url;
}
const char *rdlp_selection_media_mime_type(const rdlp_selection *selection,
                                           size_t media_index) {
  const YTMediaRequest *media = media_at(selection, media_index);
  return media == NULL ? NULL : media->mime_type;
}
int rdlp_selection_media_itag(const rdlp_selection *selection,
                              size_t media_index) {
  const YTMediaRequest *media = media_at(selection, media_index);
  return media == NULL ? 0 : media->itag;
}
int rdlp_selection_media_width(const rdlp_selection *selection,
                               size_t media_index) {
  const YTMediaRequest *media = media_at(selection, media_index);
  return media == NULL ? 0 : media->width;
}
int rdlp_selection_media_height(const rdlp_selection *selection,
                                size_t media_index) {
  const YTMediaRequest *media = media_at(selection, media_index);
  return media == NULL ? 0 : media->height;
}
int64_t rdlp_selection_media_content_length(const rdlp_selection *selection,
                                            size_t media_index) {
  const YTMediaRequest *media = media_at(selection, media_index);
  return media == NULL ? 0 : media->content_length;
}
size_t rdlp_selection_media_header_count(const rdlp_selection *selection,
                                         size_t media_index) {
  return media_at(selection, media_index) == NULL
             ? 0U
             : selection->header_counts[media_index];
}
const rdlp_http_header *rdlp_selection_media_header(
    const rdlp_selection *selection, size_t media_index, size_t header_index) {
  if (media_at(selection, media_index) == NULL ||
      header_index >= selection->header_counts[media_index])
    return NULL;
  return &selection->headers[media_index];
}

static const YTFormatInfo *format_at(const rdlp_selection *selection,
                                     size_t index) {
  return selection == NULL || index >= selection->value.format_count
             ? NULL
             : &selection->value.formats[index];
}
size_t rdlp_selection_format_count(const rdlp_selection *selection) {
  return selection == NULL ? 0U : selection->value.format_count;
}
int rdlp_selection_format_itag(const rdlp_selection *selection,
                               size_t format_index) {
  const YTFormatInfo *format = format_at(selection, format_index);
  return format == NULL ? 0 : format->itag;
}
const char *rdlp_selection_format_mime_type(const rdlp_selection *selection,
                                            size_t format_index) {
  const YTFormatInfo *format = format_at(selection, format_index);
  return format == NULL ? NULL : format->mime_type;
}
int rdlp_selection_format_width(const rdlp_selection *selection,
                                size_t format_index) {
  const YTFormatInfo *format = format_at(selection, format_index);
  return format == NULL ? 0 : format->width;
}
int rdlp_selection_format_height(const rdlp_selection *selection,
                                 size_t format_index) {
  const YTFormatInfo *format = format_at(selection, format_index);
  return format == NULL ? 0 : format->height;
}
int rdlp_selection_format_has_video(const rdlp_selection *selection,
                                    size_t format_index) {
  const YTFormatInfo *format = format_at(selection, format_index);
  return format != NULL && format->has_video;
}
int rdlp_selection_format_has_audio(const rdlp_selection *selection,
                                    size_t format_index) {
  const YTFormatInfo *format = format_at(selection, format_index);
  return format != NULL && format->has_audio;
}
int rdlp_selection_format_is_supported(const rdlp_selection *selection,
                                       size_t format_index) {
  const YTFormatInfo *format = format_at(selection, format_index);
  return format != NULL && format->supported;
}

void rdlp_playlist_destroy(rdlp_playlist *playlist) {
  if (playlist == NULL)
    return;
  yt_playlist_free(&playlist->value);
  free(playlist);
}
const char *rdlp_playlist_id(const rdlp_playlist *playlist) {
  return playlist == NULL ? NULL : playlist->value.playlist_id;
}
const char *rdlp_playlist_title(const rdlp_playlist *playlist) {
  return playlist == NULL ? NULL : playlist->value.title;
}
size_t rdlp_playlist_entry_count(const rdlp_playlist *playlist) {
  return playlist == NULL ? 0U : playlist->value.entry_count;
}
const char *rdlp_playlist_entry_video_id(const rdlp_playlist *playlist,
                                         size_t entry_index) {
  return playlist == NULL || entry_index >= playlist->value.entry_count
             ? NULL
             : playlist->value.entries[entry_index].video_id;
}
const char *rdlp_playlist_entry_title(const rdlp_playlist *playlist,
                                      size_t entry_index) {
  return playlist == NULL || entry_index >= playlist->value.entry_count
             ? NULL
             : playlist->value.entries[entry_index].title;
}
size_t rdlp_playlist_entry_index(const rdlp_playlist *playlist,
                                 size_t entry_index) {
  return playlist == NULL || entry_index >= playlist->value.entry_count
             ? 0U
             : playlist->value.entries[entry_index].index;
}
