#include "yt_http.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include <curl/curl.h>

#include "platform.h"

#define YT_HTTP_MAX_RESPONSE (8U * 1024U * 1024U)
#define YT_HTTP_TIMEOUT_SECONDS 20L

typedef struct {
  char *data;
  size_t length;
  size_t maximum_size;
  int failed;
  int too_large;
} YTWriteBuffer;

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

static YTStatus configure_common(CURL *curl, const char *url) {
  if (retro_dlp_configure_curl(curl) != 0)
    return YT_ERR_CERTIFICATE_BUNDLE;
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 5L);
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, YT_HTTP_TIMEOUT_SECONDS);
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, YT_HTTP_TIMEOUT_SECONDS);
  curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
  return YT_OK;
}

YTStatus yt_http_post_json(const char *url, const char *json,
                           const char *const *headers, size_t header_count,
                           YTHttpResponse *response) {
  CURL *curl;
  CURLcode code;
  struct curl_slist *header_list;
  YTWriteBuffer buffer;
  YTStatus status;
  size_t index;

  if (url == NULL || json == NULL || response == NULL)
    return YT_ERR_INVALID_RESPONSE;
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

  status = configure_common(curl, url);
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
  curl_slist_free_all(header_list);
  curl_easy_cleanup(curl);

  if (code != CURLE_OK) {
    free(buffer.data);
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

YTStatus yt_http_get(const char *url, size_t maximum_size,
                     YTHttpResponse *response) {
  CURL *curl;
  CURLcode code;
  YTWriteBuffer buffer;
  YTStatus status;

  if (url == NULL || response == NULL || maximum_size == 0)
    return YT_ERR_INVALID_RESPONSE;
  memset(response, 0, sizeof(*response));
  memset(&buffer, 0, sizeof(buffer));
  buffer.maximum_size = maximum_size;
  curl = curl_easy_init();
  if (curl == NULL)
    return YT_ERR_NETWORK;
  status = configure_common(curl, url);
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
  curl_easy_setopt(curl, CURLOPT_USERAGENT, "retro-dlp/" RETRO_DLP_VERSION);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_response);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buffer);
  code = curl_easy_perform(curl);
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response->status);
  curl_easy_cleanup(curl);
  if (code != CURLE_OK) {
    free(buffer.data);
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

YTStatus yt_http_head(const char *url, const char *user_agent,
                      long *http_status) {
  CURL *curl;
  CURLcode code;
  long status;
  YTStatus configure_status;

  if (url == NULL || http_status == NULL)
    return YT_ERR_INVALID_RESPONSE;
  *http_status = 0;
  curl = curl_easy_init();
  if (curl == NULL)
    return YT_ERR_NETWORK;

  configure_status = configure_common(curl, url);
  if (configure_status != YT_OK) {
    curl_easy_cleanup(curl);
    return configure_status;
  }
  curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
  if (user_agent != NULL)
    curl_easy_setopt(curl, CURLOPT_USERAGENT, user_agent);
  code = curl_easy_perform(curl);
  status = 0;
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
  curl_easy_cleanup(curl);
  *http_status = status;

  if (code != CURLE_OK)
    return YT_ERR_NETWORK;
  return YT_OK;
}

void yt_http_response_free(YTHttpResponse *response) {
  if (response == NULL)
    return;
  free(response->data);
  memset(response, 0, sizeof(*response));
}
