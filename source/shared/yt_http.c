#if !defined(__APPLE__)
#define _POSIX_C_SOURCE 200112L
#endif

#include "yt_http.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <curl/curl.h>

#include "retrodlp/retrodlp.h"
#include "platform.h"
#include "yt_cookies.h"

#define YT_HTTP_MAX_RESPONSE (8U * 1024U * 1024U)
#define YT_HTTP_TIMEOUT_SECONDS 20L

typedef struct {
  char *data;
  size_t length;
  size_t maximum_size;
  int failed;
  int too_large;
} YTWriteBuffer;

struct YTHttpSession {
  CURLSH *share;
  char *cookie_file;
  char *cookie_data;
  size_t cookie_data_length;
  char *cache_directory;
  char *ca_bundle_path;
  char *ejs_asset_directory;
  rdlp_transport transport;
  unsigned long timeout_milliseconds;
  size_t ejs_memory_limit_bytes;
  size_t ejs_stack_limit_bytes;
  YTHttpCancelCallback cancel_callback;
  void *cancel_opaque;
  YTHttpClockCallback clock_callback;
  void *clock_opaque;
  YTHttpDiagnostic diagnostic;
};

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

YTStatus yt_http_session_create_with_config(const YTHttpSessionConfig *config,
                                            YTHttpSession **session) {
  YTHttpSession *created;
  YTStatus cookie_status;
  if (session == NULL)
    return YT_ERR_INVALID_RESPONSE;
  *session = NULL;
  created = (YTHttpSession *)calloc(1, sizeof(*created));
  if (created == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  if (config != NULL && config->transport != NULL) {
    if (config->transport->struct_size < sizeof(*config->transport) ||
        config->transport->send == NULL) {
      free(created);
      return YT_ERR_INVALID_RESPONSE;
    }
    created->transport = *config->transport;
  } else {
    created->share = curl_share_init();
    if (created->share == NULL ||
        curl_share_setopt(created->share, CURLSHOPT_SHARE,
                          CURL_LOCK_DATA_COOKIE) != CURLSHE_OK) {
      if (created->share != NULL)
        curl_share_cleanup(created->share);
      free(created);
      return YT_ERR_NETWORK;
    }
  }
  if (config != NULL) {
    created->timeout_milliseconds = config->timeout_milliseconds;
    created->ejs_memory_limit_bytes = config->ejs_memory_limit_bytes;
    created->ejs_stack_limit_bytes = config->ejs_stack_limit_bytes;
    created->cancel_callback = config->cancel_callback;
    created->cancel_opaque = config->cancel_opaque;
    created->clock_callback = config->clock_callback;
    created->clock_opaque = config->clock_opaque;
    created->cache_directory = copy_string(config->cache_directory);
    created->ca_bundle_path = copy_string(config->ca_bundle_path);
    created->ejs_asset_directory = copy_string(config->ejs_asset_directory);
    if ((config->cache_directory != NULL && created->cache_directory == NULL) ||
        (config->ca_bundle_path != NULL && created->ca_bundle_path == NULL) ||
        (config->ejs_asset_directory != NULL &&
         created->ejs_asset_directory == NULL))
      goto out_of_memory;
    cookie_status = yt_http_session_set_cookies(
        created, config->cookie_file, config->cookie_data,
        config->cookie_data_length);
    if (cookie_status != YT_OK) {
      yt_http_session_destroy(created);
      return cookie_status;
    }
  }
  *session = created;
  return YT_OK;

out_of_memory:
  yt_http_session_destroy(created);
  return YT_ERR_OUT_OF_MEMORY;
}

static YTStatus transport_status(rdlp_status status) {
  switch (status) {
  case RDLP_STATUS_OK:
    return YT_OK;
  case RDLP_STATUS_OUT_OF_MEMORY:
    return YT_ERR_OUT_OF_MEMORY;
  case RDLP_STATUS_CERTIFICATE_BUNDLE:
    return YT_ERR_CERTIFICATE_BUNDLE;
  case RDLP_STATUS_HTTP:
    return YT_ERR_HTTP;
  case RDLP_STATUS_CANCELLED:
    return YT_ERR_CANCELLED;
  case RDLP_STATUS_INVALID_RESPONSE:
  case RDLP_STATUS_INVALID_ARGUMENT:
    return YT_ERR_INVALID_RESPONSE;
  default:
    return YT_ERR_NETWORK;
  }
}

static int split_header(const char *header, rdlp_http_header *result,
                        char **storage) {
  const char *separator;
  size_t name_length;
  size_t value_length;
  char *copy;
  separator = strchr(header, ':');
  if (separator == NULL)
    return 0;
  name_length = (size_t)(separator - header);
  while (separator[1] == ' ' || separator[1] == '\t')
    ++separator;
  value_length = strlen(separator + 1);
  copy = (char *)malloc(name_length + 1 + value_length + 1);
  if (copy == NULL)
    return 0;
  memcpy(copy, header, name_length);
  copy[name_length] = '\0';
  memcpy(copy + name_length + 1, separator + 1, value_length + 1);
  result->name = copy;
  result->value = copy + name_length + 1;
  *storage = copy;
  return 1;
}

static YTStatus custom_request(YTHttpSession *session, rdlp_http_method method,
                               const char *url, const void *body,
                               size_t body_length,
                               const char *const *headers,
                               size_t header_count, size_t maximum_size,
                               YTHttpResponse *response) {
  rdlp_transport_request request;
  rdlp_transport_response transported;
  rdlp_error error;
  rdlp_http_header *converted;
  char **storage;
  rdlp_status sent;
  size_t index;
  char *copy;
  if (session == NULL || session->transport.send == NULL || response == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(response, 0, sizeof(*response));
  converted = NULL;
  storage = NULL;
  if (header_count != 0) {
    converted = (rdlp_http_header *)calloc(header_count, sizeof(*converted));
    storage = (char **)calloc(header_count, sizeof(*storage));
    if (converted == NULL || storage == NULL) {
      free(converted);
      free(storage);
      return YT_ERR_OUT_OF_MEMORY;
    }
    for (index = 0; index < header_count; ++index) {
      if (!split_header(headers[index], &converted[index], &storage[index])) {
        while (index != 0)
          free(storage[--index]);
        free(converted);
        free(storage);
        return YT_ERR_OUT_OF_MEMORY;
      }
    }
  }
  memset(&request, 0, sizeof(request));
  memset(&transported, 0, sizeof(transported));
  memset(&error, 0, sizeof(error));
  memset(&session->diagnostic, 0, sizeof(session->diagnostic));
  request.struct_size = sizeof(request);
  request.method = method;
  request.url = url;
  request.headers = converted;
  request.header_count = header_count;
  request.body = body;
  request.body_length = body_length;
  request.maximum_response_bytes = maximum_size;
  request.timeout_milliseconds = session->timeout_milliseconds;
  request.cancel_callback = session->cancel_callback;
  request.cancel_context = session->cancel_opaque;
  transported.struct_size = sizeof(transported);
  error.struct_size = sizeof(error);
  if (session->cancel_callback != NULL &&
      session->cancel_callback(session->cancel_opaque))
    sent = RDLP_STATUS_CANCELLED;
  else
    sent = session->transport.send(session->transport.context, &request,
                                   &transported, &error);
  session->diagnostic.http_status = transported.http_status;
  session->diagnostic.transport_code =
      error.transport_code != 0 ? error.transport_code
                                : transported.transport_code;
  if (error.message[0] != '\0')
    snprintf(session->diagnostic.message,
             sizeof(session->diagnostic.message), "%s", error.message);
  for (index = 0; index < header_count; ++index)
    free(storage[index]);
  free(converted);
  free(storage);
  if (sent != RDLP_STATUS_OK)
    return transport_status(sent);
  if (transported.data_length > maximum_size ||
      (transported.data_length != 0 && transported.data == NULL))
    return YT_ERR_INVALID_RESPONSE;
  copy = (char *)malloc(transported.data_length + 1);
  if (copy == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  if (transported.data_length != 0)
    memcpy(copy, transported.data, transported.data_length);
  copy[transported.data_length] = '\0';
  response->data = copy;
  response->length = transported.data_length;
  response->status = transported.http_status;
  return YT_OK;
}

void yt_http_session_destroy(YTHttpSession *session) {
  if (session == NULL)
    return;
  if (session->cookie_file != NULL) {
    memset(session->cookie_file, 0, strlen(session->cookie_file));
    free(session->cookie_file);
  }
  if (session->cookie_data != NULL) {
    memset(session->cookie_data, 0, session->cookie_data_length);
    free(session->cookie_data);
  }
  free(session->cache_directory);
  free(session->ca_bundle_path);
  free(session->ejs_asset_directory);
  if (session->share != NULL)
    curl_share_cleanup(session->share);
  free(session);
}

YTStatus yt_http_session_set_cookies(YTHttpSession *session,
                                     const char *cookie_file,
                                     const void *cookie_data,
                                     size_t cookie_data_length) {
  char *file_copy;
  char *data_copy;
  CURL *curl;
  if (session == NULL || (cookie_data == NULL) != (cookie_data_length == 0) ||
      (cookie_file != NULL && cookie_data != NULL))
    return YT_ERR_INVALID_RESPONSE;
  file_copy = copy_string(cookie_file);
  if (cookie_file != NULL && file_copy == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  data_copy = NULL;
  if (cookie_data_length != 0) {
    data_copy = (char *)malloc(cookie_data_length);
    if (data_copy == NULL) {
      free(file_copy);
      return YT_ERR_OUT_OF_MEMORY;
    }
    memcpy(data_copy, cookie_data, cookie_data_length);
  }
  if (session->cookie_file != NULL) {
    memset(session->cookie_file, 0, strlen(session->cookie_file));
    free(session->cookie_file);
  }
  if (session->cookie_data != NULL) {
    memset(session->cookie_data, 0, session->cookie_data_length);
    free(session->cookie_data);
  }
  session->cookie_file = file_copy;
  session->cookie_data = data_copy;
  session->cookie_data_length = cookie_data_length;
  if (session->share != NULL) {
    curl = curl_easy_init();
    if (curl == NULL)
      return YT_ERR_NETWORK;
    curl_easy_setopt(curl, CURLOPT_SHARE, session->share);
    curl_easy_setopt(curl, CURLOPT_COOKIELIST, "ALL");
    curl_easy_cleanup(curl);
  }
  return YT_OK;
}

int64_t yt_http_session_now(YTHttpSession *session) {
  time_t now;
  if (session != NULL && session->clock_callback != NULL)
    return session->clock_callback(session->clock_opaque);
  now = time(NULL);
  return now == (time_t)-1 ? 0 : (int64_t)now;
}

int yt_http_session_has_cookies(const YTHttpSession *session) {
  return session != NULL &&
         ((session->cookie_file != NULL && session->cookie_file[0] != '\0') ||
          session->cookie_data_length != 0);
}

YTStatus yt_http_session_load_auth_cookies(YTHttpSession *session,
                                           int64_t now_unix,
                                           YTAuthCookies *cookies) {
  if (session == NULL || cookies == NULL)
    return YT_ERR_COOKIE_FILE;
  if (session->cookie_data_length != 0)
    return yt_auth_cookies_parse(session->cookie_data,
                                 session->cookie_data_length, now_unix,
                                 cookies);
  return yt_auth_cookies_load(session->cookie_file, now_unix, cookies);
}

YTCacheStatus yt_http_session_cache_get(YTHttpSession *session,
                                        YTCacheKind kind, const char *key,
                                        int64_t now_unix, char **data,
                                        size_t *length) {
  if (session == NULL)
    return yt_cache_get(kind, key, now_unix, data, length);
  return yt_cache_get_at(session->cache_directory, kind, key, now_unix, data,
                         length);
}

YTCacheStatus yt_http_session_cache_put(YTHttpSession *session,
                                        YTCacheKind kind, const char *key,
                                        const void *data, size_t length,
                                        int64_t expires_unix) {
  if (session == NULL)
    return yt_cache_put(kind, key, data, length, expires_unix);
  return yt_cache_put_at(session->cache_directory, kind, key, data, length,
                         expires_unix);
}

YTCacheStatus yt_http_session_cache_remove(YTHttpSession *session,
                                           YTCacheKind kind,
                                           const char *key) {
  if (session == NULL)
    return yt_cache_remove(kind, key);
  return yt_cache_remove_at(session->cache_directory, kind, key);
}

const char *yt_http_session_ejs_asset_directory(
    const YTHttpSession *session) {
  return session == NULL ? NULL : session->ejs_asset_directory;
}

YTEJSConfig yt_http_session_ejs_config(const YTHttpSession *session) {
  YTEJSConfig config = yt_ejs_default_config();
  if (session != NULL) {
    if (session->ejs_memory_limit_bytes != 0)
      config.memory_limit_bytes = session->ejs_memory_limit_bytes;
    if (session->ejs_stack_limit_bytes != 0)
      config.stack_limit_bytes = session->ejs_stack_limit_bytes;
    if (session->timeout_milliseconds != 0)
      config.timeout_milliseconds = session->timeout_milliseconds;
  }
  return config;
}

int yt_http_session_cancelled(const YTHttpSession *session) {
  return session != NULL && session->cancel_callback != NULL &&
         session->cancel_callback(session->cancel_opaque);
}

void yt_http_session_diagnostic(const YTHttpSession *session,
                                YTHttpDiagnostic *diagnostic) {
  if (diagnostic == NULL)
    return;
  memset(diagnostic, 0, sizeof(*diagnostic));
  if (session != NULL)
    *diagnostic = session->diagnostic;
}

static size_t write_response(void *contents, size_t size, size_t count,
                             void *opaque) {
  YTWriteBuffer *buffer;
  size_t incoming;
  char *grown;

  buffer = (YTWriteBuffer *)opaque;
  if (count != 0 && size > ((size_t)-1) / count) {
    buffer->failed = 1;
    return 0;
  }
  incoming = size * count;
  if (incoming > buffer->maximum_size ||
      buffer->length > buffer->maximum_size - incoming) {
    buffer->failed = 1;
    buffer->too_large = 1;
    return 0;
  }

  grown = (char *)realloc(buffer->data, buffer->length + incoming + 1);
  if (grown == NULL) {
    buffer->failed = 1;
    return 0;
  }
  buffer->data = grown;
  memcpy(buffer->data + buffer->length, contents, incoming);
  buffer->length += incoming;
  buffer->data[buffer->length] = '\0';
  return incoming;
}

#if LIBCURL_VERSION_NUM >= 0x072000
static int transfer_progress(void *opaque, curl_off_t download_total,
                             curl_off_t download_now, curl_off_t upload_total,
                             curl_off_t upload_now) {
  YTHttpSession *session = (YTHttpSession *)opaque;
  (void)download_total;
  (void)download_now;
  (void)upload_total;
  (void)upload_now;
  return yt_http_session_cancelled(session);
}
#else
static int transfer_progress(void *opaque, double download_total,
                             double download_now, double upload_total,
                             double upload_now) {
  YTHttpSession *session = (YTHttpSession *)opaque;
  (void)download_total;
  (void)download_now;
  (void)upload_total;
  (void)upload_now;
  return yt_http_session_cancelled(session);
}
#endif

static int configure_memory_cookies(CURL *curl, const YTHttpSession *session) {
  char *copy;
  char *line;
  char *next;
  if (session == NULL || session->cookie_data_length == 0)
    return 1;
  copy = (char *)malloc(session->cookie_data_length + 1);
  if (copy == NULL)
    return 0;
  memcpy(copy, session->cookie_data, session->cookie_data_length);
  copy[session->cookie_data_length] = '\0';
  line = copy;
  while (line != NULL) {
    size_t length;
    next = strchr(line, '\n');
    if (next != NULL)
      *next++ = '\0';
    length = strlen(line);
    if (length != 0 && line[length - 1] == '\r')
      line[length - 1] = '\0';
    if (line[0] != '\0' && line[0] != '#' &&
        curl_easy_setopt(curl, CURLOPT_COOKIELIST, line) != CURLE_OK) {
      free(copy);
      return 0;
    }
    line = next;
  }
  memset(copy, 0, session->cookie_data_length);
  free(copy);
  return 1;
}

static YTStatus configure_common(CURL *curl, YTHttpSession *session,
                                 const char *url, const char *user_agent) {
  if (session != NULL) {
    if (session->ca_bundle_path != NULL &&
        curl_easy_setopt(curl, CURLOPT_CAINFO, session->ca_bundle_path) !=
            CURLE_OK)
      return YT_ERR_CERTIFICATE_BUNDLE;
  } else if (retro_dlp_configure_curl(curl) != 0) {
    return YT_ERR_CERTIFICATE_BUNDLE;
  }
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_USERAGENT,
                   user_agent == NULL ? yt_resolver_user_agent() : user_agent);
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 5L);
#if LIBCURL_VERSION_NUM >= 0x075500
  curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "https");
  curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS_STR, "https");
#else
  curl_easy_setopt(curl, CURLOPT_PROTOCOLS, (long)CURLPROTO_HTTPS);
  curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS, (long)CURLPROTO_HTTPS);
#endif
  if (session != NULL && session->timeout_milliseconds != 0) {
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS,
                     (long)session->timeout_milliseconds);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS,
                     (long)session->timeout_milliseconds);
  } else {
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, YT_HTTP_TIMEOUT_SECONDS);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, YT_HTTP_TIMEOUT_SECONDS);
  }
  curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
  if (session != NULL) {
    curl_easy_setopt(curl, CURLOPT_SHARE, session->share);
    if (session->cookie_file != NULL)
      curl_easy_setopt(curl, CURLOPT_COOKIEFILE, session->cookie_file);
    if (!configure_memory_cookies(curl, session))
      return YT_ERR_OUT_OF_MEMORY;
    if (session->cancel_callback != NULL) {
      curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
#if LIBCURL_VERSION_NUM >= 0x072000
      curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, transfer_progress);
      curl_easy_setopt(curl, CURLOPT_XFERINFODATA, session);
#else
      curl_easy_setopt(curl, CURLOPT_PROGRESSFUNCTION, transfer_progress);
      curl_easy_setopt(curl, CURLOPT_PROGRESSDATA, session);
#endif
    }
  }
  return YT_OK;
}

YTStatus yt_http_session_post_json(YTHttpSession *session, const char *url,
                                   const char *json,
                                   const char *const *headers,
                                   size_t header_count,
                                   YTHttpResponse *response) {
  CURL *curl;
  CURLcode code;
  struct curl_slist *header_list;
  YTWriteBuffer buffer;
  YTStatus status;
  size_t index;

  if (url == NULL || json == NULL || response == NULL)
    return YT_ERR_INVALID_RESPONSE;
  if (session != NULL && session->transport.send != NULL)
    return custom_request(session, RDLP_HTTP_POST, url, json, strlen(json),
                          headers, header_count, YT_HTTP_MAX_RESPONSE,
                          response);
  memset(response, 0, sizeof(*response));
  memset(&buffer, 0, sizeof(buffer));
  buffer.maximum_size = YT_HTTP_MAX_RESPONSE;

  curl = curl_easy_init();
  if (curl == NULL)
    return YT_ERR_NETWORK;

  header_list = NULL;
  for (index = 0; index < header_count; ++index) {
    struct curl_slist *grown;
    grown = curl_slist_append(header_list, headers[index]);
    if (grown == NULL) {
      curl_slist_free_all(header_list);
      curl_easy_cleanup(curl);
      return YT_ERR_OUT_OF_MEMORY;
    }
    header_list = grown;
  }

  status = configure_common(curl, session, url, NULL);
  if (status != YT_OK) {
    curl_slist_free_all(header_list);
    curl_easy_cleanup(curl);
    return status;
  }
  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);
  curl_easy_setopt(curl, CURLOPT_POSTFIELDS, json);
  curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)strlen(json));
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_response);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buffer);

  code = curl_easy_perform(curl);
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response->status);
  if (session != NULL) {
    session->diagnostic.http_status = response->status;
    session->diagnostic.transport_code = (int)code;
  }
  curl_slist_free_all(header_list);
  curl_easy_cleanup(curl);

  if (code != CURLE_OK) {
    free(buffer.data);
    if (code == CURLE_ABORTED_BY_CALLBACK && yt_http_session_cancelled(session))
      return YT_ERR_CANCELLED;
    return buffer.failed ? YT_ERR_OUT_OF_MEMORY : YT_ERR_NETWORK;
  }
  response->data = buffer.data;
  response->length = buffer.length;
  if (response->data == NULL) {
    response->data = (char *)malloc(1);
    if (response->data == NULL)
      return YT_ERR_OUT_OF_MEMORY;
    response->data[0] = '\0';
  }
  return YT_OK;
}

static YTStatus http_get(YTHttpSession *session, const char *url,
                         size_t maximum_size, const char *user_agent,
                         YTHttpResponse *response) {
  CURL *curl;
  CURLcode code;
  YTWriteBuffer buffer;
  YTStatus status;
  char user_agent_header[512];
  const char *custom_headers[1];

  if (url == NULL || response == NULL || maximum_size == 0)
    return YT_ERR_INVALID_RESPONSE;
  if (session != NULL && session->transport.send != NULL) {
    if (user_agent != NULL) {
      if (snprintf(user_agent_header, sizeof(user_agent_header),
                   "User-Agent: %s", user_agent) >=
          (int)sizeof(user_agent_header))
        return YT_ERR_INVALID_RESPONSE;
      custom_headers[0] = user_agent_header;
      return custom_request(session, RDLP_HTTP_GET, url, NULL, 0,
                            custom_headers, 1, maximum_size, response);
    }
    return custom_request(session, RDLP_HTTP_GET, url, NULL, 0, NULL, 0,
                          maximum_size, response);
  }
  memset(response, 0, sizeof(*response));
  memset(&buffer, 0, sizeof(buffer));
  buffer.maximum_size = maximum_size;
  curl = curl_easy_init();
  if (curl == NULL)
    return YT_ERR_NETWORK;
  status = configure_common(curl, session, url, user_agent);
  if (status != YT_OK) {
    curl_easy_cleanup(curl);
    return status;
  }
#if LIBCURL_VERSION_NUM >= 0x075500
  curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "https");
  curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS_STR, "https");
#else
  curl_easy_setopt(curl, CURLOPT_PROTOCOLS, (long)CURLPROTO_HTTPS);
  curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS, (long)CURLPROTO_HTTPS);
#endif
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_response);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buffer);
  code = curl_easy_perform(curl);
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response->status);
  if (session != NULL) {
    session->diagnostic.http_status = response->status;
    session->diagnostic.transport_code = (int)code;
  }
  curl_easy_cleanup(curl);
  if (code != CURLE_OK) {
    free(buffer.data);
    if (code == CURLE_ABORTED_BY_CALLBACK && yt_http_session_cancelled(session))
      return YT_ERR_CANCELLED;
    return buffer.too_large ? YT_ERR_INVALID_RESPONSE
                            : (buffer.failed ? YT_ERR_OUT_OF_MEMORY
                                             : YT_ERR_NETWORK);
  }
  response->data = buffer.data;
  response->length = buffer.length;
  if (response->data == NULL) {
    response->data = (char *)malloc(1);
    if (response->data == NULL)
      return YT_ERR_OUT_OF_MEMORY;
    response->data[0] = '\0';
  }
  return YT_OK;
}

YTStatus yt_http_get(const char *url, size_t maximum_size,
                     YTHttpResponse *response) {
  return http_get(NULL, url, maximum_size, NULL, response);
}

YTStatus yt_http_session_get(YTHttpSession *session, const char *url,
                             size_t maximum_size, YTHttpResponse *response) {
  return http_get(session, url, maximum_size, NULL, response);
}

YTStatus yt_http_session_get_with_user_agent(
    YTHttpSession *session, const char *url, size_t maximum_size,
    const char *user_agent, YTHttpResponse *response) {
  return http_get(session, url, maximum_size, user_agent, response);
}

void yt_http_response_free(YTHttpResponse *response) {
  if (response == NULL)
    return;
  free(response->data);
  memset(response, 0, sizeof(*response));
}
