#include "retrodlp/retrodlp.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <curl/curl.h>
#include <pthread.h>

#include "rdlp_curl.h"
#include "yt_http.h"
#include "yt_playlist.h"
#include "yt_resolver.h"

#define RDLP_DEFAULT_TIMEOUT_MILLISECONDS 60000UL
#define HAS_FIELD(value, type, field)                                           \
  ((value)->struct_size >= offsetof(type, field) + sizeof((value)->field))

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

struct rdlp_playlist_collection {
  YTPlaylistCollection value;
};

static void publish_error(rdlp_error *error, rdlp_error_code code,
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
  value.code = code;
  value.retryable = rdlp_error_is_retryable(code);
  if (message != NULL)
    snprintf(value.message, sizeof(value.message), "%s", message);
  memcpy(error, &value, size);
}

static rdlp_error_code public_error(YTStatus status) {
  switch (status) {
  case YT_OK:
    return RDLP_OK;
  case YT_ERR_INVALID_VIDEO_ID:
    return RDLP_ERROR_INVALID_VIDEO_ID;
  case YT_ERR_INVALID_PLAYLIST:
    return RDLP_ERROR_INVALID_PLAYLIST;
  case YT_ERR_INVALID_FORMAT:
    return RDLP_ERROR_INVALID_FORMAT_EXPRESSION;
  case YT_ERR_OUT_OF_MEMORY:
    return RDLP_ERROR_OUT_OF_MEMORY;
  case YT_ERR_NETWORK:
    return RDLP_ERROR_TRANSPORT_REQUEST_FAILED;
  case YT_ERR_TRANSPORT_TIMEOUT:
    return RDLP_ERROR_TRANSPORT_TIMEOUT;
  case YT_ERR_CERTIFICATE_BUNDLE:
    return RDLP_ERROR_CERTIFICATE_BUNDLE;
  case YT_ERR_HTTP:
    return RDLP_ERROR_HTTP_STATUS;
  case YT_ERR_INVALID_RESPONSE:
    return RDLP_ERROR_RESPONSE_MALFORMED;
  case YT_ERR_RESPONSE_TOO_LARGE:
    return RDLP_ERROR_RESPONSE_TOO_LARGE;
  case YT_ERR_UNAVAILABLE:
    return RDLP_ERROR_VIDEO_UNAVAILABLE;
  case YT_ERR_NO_PROGRESSIVE_MP4:
  case YT_ERR_FORMAT_UNAVAILABLE:
    return RDLP_ERROR_FORMAT_UNAVAILABLE;
  case YT_ERR_EJS_ASSETS_MISSING:
    return RDLP_ERROR_EJS_ASSETS_MISSING;
  case YT_ERR_EJS_ASSETS_CORRUPT:
    return RDLP_ERROR_EJS_ASSETS_CORRUPT;
  case YT_ERR_EJS_TIMEOUT:
    return RDLP_ERROR_EJS_TIMEOUT;
  case YT_ERR_EJS_EXCEPTION:
  case YT_ERR_JS_CHALLENGE:
    return RDLP_ERROR_EJS_EXCEPTION;
  case YT_ERR_EJS_INVALID_RESULT:
    return RDLP_ERROR_EJS_INVALID_RESULT;
  case YT_ERR_EJS_SIGNATURE_FAILED:
    return RDLP_ERROR_EJS_SIGNATURE_FAILED;
  case YT_ERR_EJS_N_TRANSFORM_FAILED:
    return RDLP_ERROR_EJS_N_TRANSFORM_FAILED;
  case YT_ERR_PO_TOKEN_REQUIRED:
    return RDLP_ERROR_AUTHENTICATION_REQUIRED;
  case YT_ERR_AUTH_COOKIES_INVALID:
    return RDLP_ERROR_COOKIES_REJECTED;
  case YT_ERR_COOKIE_FILE:
    return RDLP_ERROR_COOKIES_UNREADABLE;
  case YT_ERR_CANCELLED:
    return RDLP_ERROR_CANCELLED;
  case YT_ERR_FILE_EXISTS:
    return RDLP_ERROR_DESTINATION_EXISTS;
  case YT_ERR_STORAGE:
    return RDLP_ERROR_STORAGE_IO;
  case YT_ERR_INVALID_MEDIA:
    return RDLP_ERROR_MEDIA_NOT_MP4;
  case YT_ERR_MUX:
    return RDLP_ERROR_MUX_FAILED;
  default:
    return RDLP_ERROR_INTERNAL;
  }
}

static rdlp_error_code finish_status(YTStatus status, rdlp_error *error) {
  rdlp_error_code result = public_error(status);
  publish_error(error, result, yt_status_string(status));
  return result;
}

static rdlp_error_code finish_session_status(YTStatus status,
                                         YTHttpSession *session,
                                         rdlp_error *error) {
  YTHttpDiagnostic diagnostic;
  rdlp_error_code result = finish_status(status, error);
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

const char *rdlp_error_name(rdlp_error_code code) {
#define RDLP_ERROR_NAME(value) case value: return #value
  switch (code) {
    RDLP_ERROR_NAME(RDLP_OK);
    RDLP_ERROR_NAME(RDLP_ERROR_INVALID_ARGUMENT);
    RDLP_ERROR_NAME(RDLP_ERROR_INVALID_VIDEO_ID);
    RDLP_ERROR_NAME(RDLP_ERROR_INVALID_PLAYLIST);
    RDLP_ERROR_NAME(RDLP_ERROR_INVALID_FORMAT_EXPRESSION);
    RDLP_ERROR_NAME(RDLP_ERROR_INVALID_PATH);
    RDLP_ERROR_NAME(RDLP_ERROR_OUT_OF_MEMORY);
    RDLP_ERROR_NAME(RDLP_ERROR_TRANSPORT_INITIALIZATION_FAILED);
    RDLP_ERROR_NAME(RDLP_ERROR_TRANSPORT_TIMEOUT);
    RDLP_ERROR_NAME(RDLP_ERROR_TRANSPORT_REQUEST_FAILED);
    RDLP_ERROR_NAME(RDLP_ERROR_CERTIFICATE_BUNDLE);
    RDLP_ERROR_NAME(RDLP_ERROR_HTTP_STATUS);
    RDLP_ERROR_NAME(RDLP_ERROR_RESPONSE_TOO_LARGE);
    RDLP_ERROR_NAME(RDLP_ERROR_RESPONSE_MALFORMED);
    RDLP_ERROR_NAME(RDLP_ERROR_VIDEO_UNAVAILABLE);
    RDLP_ERROR_NAME(RDLP_ERROR_FORMAT_UNAVAILABLE);
    RDLP_ERROR_NAME(RDLP_ERROR_AUTHENTICATION_REQUIRED);
    RDLP_ERROR_NAME(RDLP_ERROR_COOKIES_UNREADABLE);
    RDLP_ERROR_NAME(RDLP_ERROR_COOKIES_REJECTED);
    RDLP_ERROR_NAME(RDLP_ERROR_EJS_ASSETS_MISSING);
    RDLP_ERROR_NAME(RDLP_ERROR_EJS_ASSETS_CORRUPT);
    RDLP_ERROR_NAME(RDLP_ERROR_EJS_TIMEOUT);
    RDLP_ERROR_NAME(RDLP_ERROR_EJS_EXCEPTION);
    RDLP_ERROR_NAME(RDLP_ERROR_EJS_INVALID_RESULT);
    RDLP_ERROR_NAME(RDLP_ERROR_EJS_SIGNATURE_FAILED);
    RDLP_ERROR_NAME(RDLP_ERROR_EJS_N_TRANSFORM_FAILED);
    RDLP_ERROR_NAME(RDLP_ERROR_DESTINATION_EXISTS);
    RDLP_ERROR_NAME(RDLP_ERROR_STORAGE_IO);
    RDLP_ERROR_NAME(RDLP_ERROR_MEDIA_NOT_MP4);
    RDLP_ERROR_NAME(RDLP_ERROR_MUX_INVALID_INPUT);
    RDLP_ERROR_NAME(RDLP_ERROR_MUX_FAILED);
    RDLP_ERROR_NAME(RDLP_ERROR_CLEANUP_FAILED);
    RDLP_ERROR_NAME(RDLP_ERROR_CANCELLED);
    RDLP_ERROR_NAME(RDLP_ERROR_CONTEXT_BUSY);
    RDLP_ERROR_NAME(RDLP_ERROR_INTERNAL);
  }
#undef RDLP_ERROR_NAME
  return "RDLP_ERROR_UNKNOWN";
}

rdlp_error_category_code rdlp_error_category(rdlp_error_code code) {
  int category;
  if (code >= 0)
    return RDLP_ERROR_CATEGORY_NONE;
  category = -(int)code / 100;
  switch (category) {
  case 1: return RDLP_ERROR_CATEGORY_INPUT;
  case 2: return RDLP_ERROR_CATEGORY_RESOURCE;
  case 3: return RDLP_ERROR_CATEGORY_TRANSPORT;
  case 4: return RDLP_ERROR_CATEGORY_SERVICE;
  case 5: return RDLP_ERROR_CATEGORY_EJS;
  case 6: return RDLP_ERROR_CATEGORY_MEDIA;
  case 7: return RDLP_ERROR_CATEGORY_OPERATION;
  case 9: return RDLP_ERROR_CATEGORY_INTERNAL;
  default: return RDLP_ERROR_CATEGORY_NONE;
  }
}

int rdlp_error_is_retryable(rdlp_error_code code) {
  return code == RDLP_ERROR_TRANSPORT_TIMEOUT ||
         code == RDLP_ERROR_TRANSPORT_REQUEST_FAILED ||
         code == RDLP_ERROR_HTTP_STATUS;
}

rdlp_error_code rdlp_context_create(const rdlp_config *config,
                                rdlp_context **context, rdlp_error *error) {
  rdlp_context *created;
  YTHttpSessionConfig session_config;
  YTStatus session_status;
  if (context == NULL) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  "context output pointer is required");
    return RDLP_ERROR_INVALID_ARGUMENT;
  }
  *context = NULL;
  if (config != NULL && config->struct_size < sizeof(config->struct_size)) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  "configuration structure is too small");
    return RDLP_ERROR_INVALID_ARGUMENT;
  }
  created = (rdlp_context *)calloc(1, sizeof(*created));
  if (created == NULL) {
    publish_error(error, RDLP_ERROR_OUT_OF_MEMORY, "out of memory");
    return RDLP_ERROR_OUT_OF_MEMORY;
  }
  if (pthread_mutex_init(&created->operation_mutex, NULL) != 0) {
    free(created);
    publish_error(error, RDLP_ERROR_INTERNAL,
                  "could not initialize context synchronization");
    return RDLP_ERROR_INTERNAL;
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
      publish_error(error, RDLP_ERROR_OUT_OF_MEMORY, "out of memory");
      return RDLP_ERROR_OUT_OF_MEMORY;
    }
    if ((created->cache_directory != NULL &&
         created->cache_directory[0] != '/') ||
        (created->ca_bundle_path != NULL &&
         created->ca_bundle_path[0] != '/') ||
        (created->ejs_asset_directory != NULL &&
         created->ejs_asset_directory[0] != '/')) {
      rdlp_context_destroy(created);
      publish_error(error, RDLP_ERROR_INVALID_PATH,
                    "configured paths must be absolute");
      return RDLP_ERROR_INVALID_PATH;
    }
    if (HAS_FIELD(config, rdlp_config, ejs_memory_limit_bytes))
      created->ejs_memory_limit_bytes = config->ejs_memory_limit_bytes;
    if (HAS_FIELD(config, rdlp_config, ejs_stack_limit_bytes))
      created->ejs_stack_limit_bytes = config->ejs_stack_limit_bytes;
    if (HAS_FIELD(config, rdlp_config, transport) &&
        config->transport != NULL) {
      if (!HAS_FIELD(config->transport, rdlp_transport, send) ||
          config->transport->send == NULL) {
        rdlp_context_destroy(created);
        publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                      "transport structure is invalid");
        return RDLP_ERROR_INVALID_ARGUMENT;
      }
      memset(&created->transport, 0, sizeof(created->transport));
      created->transport.struct_size = sizeof(created->transport);
      created->transport.send = config->transport->send;
      if (HAS_FIELD(config->transport, rdlp_transport, context))
        created->transport.context = config->transport->context;
      created->has_transport = 1;
    }
    if (HAS_FIELD(config, rdlp_config, clock_callback))
      created->clock_callback = config->clock_callback;
    if (HAS_FIELD(config, rdlp_config, clock_context))
      created->clock_context = config->clock_context;
  }
  if (!created->has_transport && !rdlp_curl_acquire()) {
    rdlp_context_destroy(created);
    publish_error(error, RDLP_ERROR_TRANSPORT_INITIALIZATION_FAILED,
                  "could not initialize default HTTP transport");
    return RDLP_ERROR_TRANSPORT_INITIALIZATION_FAILED;
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
  publish_error(error, RDLP_OK, "success");
  return RDLP_OK;
}

void rdlp_context_destroy(rdlp_context *context) {
  if (context == NULL)
    return;
  yt_http_session_destroy(context->http_session);
  if (context->owns_default_transport)
    rdlp_curl_release();
  pthread_mutex_destroy(&context->operation_mutex);
  free(context->cache_directory);
  free(context->ca_bundle_path);
  free(context->ejs_asset_directory);
  free(context);
}

rdlp_error_code rdlp_parse_video_id(const char *input, char video_id[12],
                                rdlp_error *error) {
  YTStatus status;
  if (video_id != NULL)
    video_id[0] = '\0';
  if (input == NULL || video_id == NULL) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  "input and video ID output are required");
    return RDLP_ERROR_INVALID_ARGUMENT;
  }
  status = yt_extract_video_id(input, video_id);
  return finish_status(status, error);
}

rdlp_error_code rdlp_parse_playlist_id(const char *input, char *playlist_id,
                                   size_t playlist_id_size,
                                   rdlp_error *error) {
  YTStatus status;
  if (playlist_id != NULL && playlist_id_size != 0)
    playlist_id[0] = '\0';
  if (input == NULL || playlist_id == NULL || playlist_id_size == 0) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  "input and playlist ID output are required");
    return RDLP_ERROR_INVALID_ARGUMENT;
  }
  status = yt_extract_playlist_id(input, playlist_id, playlist_id_size);
  return finish_status(status, error);
}

int rdlp_format_expression_valid(const char *expression) {
  return yt_format_expression_valid(expression);
}

int rdlp_is_playlist_collection_input(const char *input) {
  return input != NULL && yt_is_playlist_collection_url(input);
}

static int context_cancelled(void *opaque) {
  rdlp_context *context = (rdlp_context *)opaque;
  return context->cancel_callback != NULL &&
         context->cancel_callback(context->callback_context);
}

static rdlp_event_type event_type(const char *message) {
  if (strstr(message, "authenticated YouTube cookies") != NULL)
    return RDLP_EVENT_AUTHENTICATING;
  if (strstr(message, "refreshing video metadata") != NULL)
    return RDLP_EVENT_REFRESHING_METADATA;
  if (strstr(message, "web player") != NULL ||
      strstr(message, "webpage") != NULL)
    return RDLP_EVENT_FETCHING_BOOTSTRAP;
  if (strstr(message, "configuration") != NULL)
    return RDLP_EVENT_LOADING_CONFIGURATION;
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

static void end_operation(rdlp_context *context);

static rdlp_error_code begin_operation(rdlp_context *context, rdlp_error *error) {
  if (context == NULL) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT, "context is required");
    return RDLP_ERROR_INVALID_ARGUMENT;
  }
  pthread_mutex_lock(&context->operation_mutex);
  if (context->operating) {
    pthread_mutex_unlock(&context->operation_mutex);
    publish_error(error, RDLP_ERROR_CONTEXT_BUSY, "context is already in use");
    return RDLP_ERROR_CONTEXT_BUSY;
  }
  context->operating = 1;
  pthread_mutex_unlock(&context->operation_mutex);
  if (context_cancelled(context)) {
    end_operation(context);
    publish_error(error, RDLP_ERROR_CANCELLED, "operation cancelled");
    return RDLP_ERROR_CANCELLED;
  }
  return RDLP_OK;
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

rdlp_error_code rdlp_resolve_video(rdlp_context *context, const char *input,
                               const rdlp_resolve_options *options,
                               rdlp_selection **selection,
                               rdlp_error *error) {
  rdlp_selection *created;
  YTHttpSession *session;
  YTStatus status;
  rdlp_error_code started;
  const char *cookie_file = NULL;
  const void *cookie_data = NULL;
  size_t cookie_data_length = 0;
  const char *format_expression = NULL;
  int maximum_height = YT_DEFAULT_MAX_HEIGHT;
  int prefer_adaptive = 0;
  int include_format_inventory = 0;
  if (selection == NULL) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  "selection output pointer is required");
    return RDLP_ERROR_INVALID_ARGUMENT;
  }
  *selection = NULL;
  if (input == NULL ||
      (options != NULL &&
       options->struct_size < sizeof(options->struct_size))) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  "input or resolve options are invalid");
    return RDLP_ERROR_INVALID_ARGUMENT;
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
      publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                    "cookie file and cookie data options are invalid");
      return RDLP_ERROR_INVALID_ARGUMENT;
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
  if (started != RDLP_OK)
    return started;
  created = (rdlp_selection *)calloc(1, sizeof(*created));
  session = NULL;
  status = created == NULL
               ? YT_ERR_OUT_OF_MEMORY
               : operation_session(context, cookie_file, cookie_data,
                                   cookie_data_length, &session);
  if (status == YT_OK) {
    status = yt_resolver_resolve(
        session, input, cookie_file, maximum_height, prefer_adaptive,
        &created->value, format_expression, 0, facade_progress, context);
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
  publish_error(error, RDLP_OK, "success");
  return RDLP_OK;
}

rdlp_error_code rdlp_list_playlist(rdlp_context *context, const char *input,
                               const rdlp_playlist_options *options,
                               rdlp_playlist **playlist, rdlp_error *error) {
  rdlp_playlist *created;
  YTHttpSession *session;
  YTStatus status;
  rdlp_error_code started;
  const char *cookie_file = NULL;
  const void *cookie_data = NULL;
  size_t cookie_data_length = 0;
  if (playlist == NULL) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  "playlist output pointer is required");
    return RDLP_ERROR_INVALID_ARGUMENT;
  }
  *playlist = NULL;
  if (input == NULL ||
      (options != NULL && options->struct_size < sizeof(options->struct_size))) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  "input or playlist options are invalid");
    return RDLP_ERROR_INVALID_ARGUMENT;
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
      publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                    "cookie file and cookie data options are invalid");
      return RDLP_ERROR_INVALID_ARGUMENT;
    }
  }
  started = begin_operation(context, error);
  if (started != RDLP_OK)
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
  publish_error(error, RDLP_OK, "success");
  return RDLP_OK;
}

rdlp_error_code rdlp_list_playlist_collection(
    rdlp_context *context, const char *input,
    const rdlp_playlist_options *options,
    rdlp_playlist_collection **collection, rdlp_error *error) {
  rdlp_playlist_collection *created;
  YTHttpSession *session;
  YTStatus status;
  rdlp_error_code started;
  const char *cookie_file = NULL;
  const void *cookie_data = NULL;
  size_t cookie_data_length = 0;
  if (collection == NULL) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  "playlist collection output pointer is required");
    return RDLP_ERROR_INVALID_ARGUMENT;
  }
  *collection = NULL;
  if (input == NULL || !yt_is_playlist_collection_url(input) ||
      (options != NULL && options->struct_size < sizeof(options->struct_size))) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  "input or playlist options are invalid");
    return RDLP_ERROR_INVALID_ARGUMENT;
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
      publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                    "cookie file and cookie data options are invalid");
      return RDLP_ERROR_INVALID_ARGUMENT;
    }
  }
  started = begin_operation(context, error);
  if (started != RDLP_OK)
    return started;
  created = (rdlp_playlist_collection *)calloc(1, sizeof(*created));
  session = NULL;
  status = created == NULL
               ? YT_ERR_OUT_OF_MEMORY
               : operation_session(context, cookie_file, cookie_data,
                                   cookie_data_length, &session);
  if (status == YT_OK)
    status = yt_list_account_playlists(session, input, cookie_file,
                                       &created->value, facade_progress,
                                       context);
  if (session != NULL)
    yt_http_session_set_cookies(session, NULL, NULL, 0);
  if (status == YT_OK && context_cancelled(context))
    status = YT_ERR_CANCELLED;
  end_operation(context);
  if (status != YT_OK) {
    rdlp_playlist_collection_destroy(created);
    return finish_session_status(status, context->http_session, error);
  }
  *collection = created;
  publish_error(error, RDLP_OK, "success");
  return RDLP_OK;
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
int rdlp_selection_media_fps(const rdlp_selection *selection,
                             size_t media_index) {
  const YTMediaRequest *media = media_at(selection, media_index);
  return media == NULL ? 0 : media->fps;
}
int rdlp_selection_media_audio_channels(const rdlp_selection *selection,
                                        size_t media_index) {
  const YTMediaRequest *media = media_at(selection, media_index);
  return media == NULL ? 0 : media->audio_channels;
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
int rdlp_selection_format_fps(const rdlp_selection *selection,
                              size_t format_index) {
  const YTFormatInfo *format = format_at(selection, format_index);
  return format == NULL ? 0 : format->fps;
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

void rdlp_playlist_collection_destroy(rdlp_playlist_collection *collection) {
  if (collection == NULL)
    return;
  yt_playlist_collection_free(&collection->value);
  free(collection);
}
size_t rdlp_playlist_collection_count(
    const rdlp_playlist_collection *collection) {
  return collection == NULL ? 0U : collection->value.playlist_count;
}
const char *rdlp_playlist_collection_id(
    const rdlp_playlist_collection *collection, size_t playlist_index) {
  return collection == NULL || playlist_index >= collection->value.playlist_count
             ? NULL
             : collection->value.playlists[playlist_index].playlist_id;
}
const char *rdlp_playlist_collection_title(
    const rdlp_playlist_collection *collection, size_t playlist_index) {
  return collection == NULL || playlist_index >= collection->value.playlist_count
             ? NULL
             : collection->value.playlists[playlist_index].title;
}
size_t rdlp_playlist_collection_index(
    const rdlp_playlist_collection *collection, size_t playlist_index) {
  return collection == NULL || playlist_index >= collection->value.playlist_count
             ? 0U
             : collection->value.playlists[playlist_index].index;
}
