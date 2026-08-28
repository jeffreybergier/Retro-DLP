#if !defined(__APPLE__)
#define _POSIX_C_SOURCE 200112L
#endif

#include "yt_http.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <curl/curl.h>

#include "platform.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define YT_HTTP_MAX_RESPONSE (8U * 1024U * 1024U)
#define YT_HTTP_TIMEOUT_SECONDS 20L

typedef struct {
  char *data;
  size_t length;
  size_t maximum_size;
  int failed;
  int too_large;
} YTWriteBuffer;

typedef struct {
  FILE *file;
  unsigned char prefix[16];
  size_t prefix_length;
  int failed;
  int64_t bytes_written;
} YTDownloadWriter;

struct YTHttpSession {
  CURLSH *share;
  char *cookie_file;
};

YTStatus yt_http_session_create(const char *cookie_file,
                                YTHttpSession **session) {
  YTHttpSession *created;
  if (session == NULL)
    return YT_ERR_INVALID_RESPONSE;
  *session = NULL;
  created = (YTHttpSession *)calloc(1, sizeof(*created));
  if (created == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  created->share = curl_share_init();
  if (created->share == NULL ||
      curl_share_setopt(created->share, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE) !=
          CURLSHE_OK) {
    if (created->share != NULL)
      curl_share_cleanup(created->share);
    free(created);
    return YT_ERR_NETWORK;
  }
  if (cookie_file != NULL) {
    size_t cookie_file_length = strlen(cookie_file);
    created->cookie_file = (char *)malloc(cookie_file_length + 1);
    if (created->cookie_file == NULL) {
      curl_share_cleanup(created->share);
      free(created);
      return YT_ERR_OUT_OF_MEMORY;
    }
    memcpy(created->cookie_file, cookie_file, cookie_file_length + 1);
  }
  *session = created;
  return YT_OK;
}

void yt_http_session_destroy(YTHttpSession *session) {
  if (session == NULL)
    return;
  if (session->cookie_file != NULL) {
    memset(session->cookie_file, 0, strlen(session->cookie_file));
    free(session->cookie_file);
  }
  if (session->share != NULL)
    curl_share_cleanup(session->share);
  free(session);
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

static size_t write_download(void *contents, size_t size, size_t count,
                             void *opaque) {
  YTDownloadWriter *writer;
  size_t incoming;
  size_t copy_length;
  size_t written;
  writer = (YTDownloadWriter *)opaque;
  if (count != 0 && size > ((size_t)-1) / count) {
    writer->failed = 1;
    return 0;
  }
  incoming = size * count;
  copy_length = sizeof(writer->prefix) - writer->prefix_length;
  if (copy_length > incoming)
    copy_length = incoming;
  if (copy_length != 0) {
    memcpy(writer->prefix + writer->prefix_length, contents, copy_length);
    writer->prefix_length += copy_length;
  }
  written = fwrite(contents, 1, incoming, writer->file);
  if (written != incoming) {
    writer->failed = 1;
    return written;
  }
  if (incoming > (size_t)(INT64_MAX - writer->bytes_written)) {
    writer->failed = 1;
    return 0;
  }
  writer->bytes_written += (int64_t)incoming;
  return incoming;
}

int yt_http_has_mp4_ftyp(const unsigned char *prefix, size_t length) {
  return prefix != NULL && length >= 8 && memcmp(prefix + 4, "ftyp", 4) == 0;
}

static YTStatus configure_common(CURL *curl, YTHttpSession *session,
                                 const char *url) {
  if (retro_dlp_configure_curl(curl) != 0)
    return YT_ERR_CERTIFICATE_BUNDLE;
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_USERAGENT, yt_resolver_user_agent());
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 5L);
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, YT_HTTP_TIMEOUT_SECONDS);
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, YT_HTTP_TIMEOUT_SECONDS);
  curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
  if (session != NULL) {
    curl_easy_setopt(curl, CURLOPT_SHARE, session->share);
    if (session->cookie_file != NULL)
      curl_easy_setopt(curl, CURLOPT_COOKIEFILE, session->cookie_file);
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

  status = configure_common(curl, session, url);
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

YTStatus yt_http_post_json(const char *url, const char *json,
                           const char *const *headers, size_t header_count,
                           YTHttpResponse *response) {
  return yt_http_session_post_json(NULL, url, json, headers, header_count,
                                   response);
}

static YTStatus http_get(YTHttpSession *session, const char *url,
                         size_t maximum_size,
                         const char *range, const char *user_agent,
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
  status = configure_common(curl, session, url);
  if (status != YT_OK) {
    curl_easy_cleanup(curl);
    return status;
  }
  if (user_agent != NULL)
    curl_easy_setopt(curl, CURLOPT_USERAGENT, user_agent);
#if LIBCURL_VERSION_NUM >= 0x075500
  curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "https");
  curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS_STR, "https");
#else
  curl_easy_setopt(curl, CURLOPT_PROTOCOLS, (long)CURLPROTO_HTTPS);
  curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS, (long)CURLPROTO_HTTPS);
#endif
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_response);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buffer);
  if (range != NULL)
    curl_easy_setopt(curl, CURLOPT_RANGE, range);
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

YTStatus yt_http_get(const char *url, size_t maximum_size,
                     YTHttpResponse *response) {
  return http_get(NULL, url, maximum_size, NULL, NULL, response);
}

YTStatus yt_http_session_get(YTHttpSession *session, const char *url,
                             size_t maximum_size, YTHttpResponse *response) {
  return http_get(session, url, maximum_size, NULL, NULL, response);
}

YTStatus yt_http_session_get_with_user_agent(
    YTHttpSession *session, const char *url, size_t maximum_size,
    const char *user_agent, YTHttpResponse *response) {
  return http_get(session, url, maximum_size, NULL, user_agent, response);
}

YTStatus yt_http_get_range(const char *url, size_t length,
                           YTHttpResponse *response) {
  char range[64];

  if (length == 0 || length > (size_t)ULONG_MAX ||
      snprintf(range, sizeof(range), "0-%lu", (unsigned long)(length - 1)) >=
          (int)sizeof(range))
    return YT_ERR_INVALID_RESPONSE;
  return http_get(NULL, url, length, range, NULL, response);
}

YTStatus yt_http_session_get_range(YTHttpSession *session, const char *url,
                                   size_t length, YTHttpResponse *response) {
  char range[64];
  if (length == 0 || length > (size_t)ULONG_MAX ||
      snprintf(range, sizeof(range), "0-%lu", (unsigned long)(length - 1)) >=
          (int)sizeof(range))
    return YT_ERR_INVALID_RESPONSE;
  return http_get(session, url, length, range, NULL, response);
}

YTStatus yt_http_session_head(YTHttpSession *session, const char *url,
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

  configure_status = configure_common(curl, session, url);
  if (configure_status != YT_OK) {
    curl_easy_cleanup(curl);
    return configure_status;
  }
  curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
  code = curl_easy_perform(curl);
  status = 0;
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
  curl_easy_cleanup(curl);
  *http_status = status;

  if (code != CURLE_OK)
    return YT_ERR_NETWORK;
  return YT_OK;
}

YTStatus yt_http_head(const char *url, long *http_status) {
  return yt_http_session_head(NULL, url, http_status);
}

YTStatus yt_http_session_download(YTHttpSession *session, const char *url,
                                  const char *destination, long *http_status,
                                  int64_t *bytes_written) {
  char temporary[PATH_MAX];
  struct stat information;
  int descriptor;
  CURL *curl;
  CURLcode code;
  YTStatus status;
  YTDownloadWriter writer;
  long response_status;
  int close_failed;

  if (url == NULL || destination == NULL || destination[0] == '\0' ||
      http_status == NULL || bytes_written == NULL)
    return YT_ERR_INVALID_RESPONSE;
  *http_status = 0;
  *bytes_written = 0;
  if (lstat(destination, &information) == 0)
    return YT_ERR_FILE_EXISTS;
  if (errno != ENOENT)
    return YT_ERR_STORAGE;
  if (snprintf(temporary, sizeof(temporary), "%s.part", destination) >=
      (int)sizeof(temporary))
    return YT_ERR_STORAGE;
  descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (descriptor < 0)
    return errno == EEXIST ? YT_ERR_FILE_EXISTS : YT_ERR_STORAGE;
  memset(&writer, 0, sizeof(writer));
  writer.file = fdopen(descriptor, "wb");
  if (writer.file == NULL) {
    close(descriptor);
    unlink(temporary);
    return YT_ERR_STORAGE;
  }
  curl = curl_easy_init();
  if (curl == NULL) {
    fclose(writer.file);
    unlink(temporary);
    return YT_ERR_NETWORK;
  }
  status = configure_common(curl, session, url);
  if (status != YT_OK) {
    curl_easy_cleanup(curl);
    fclose(writer.file);
    unlink(temporary);
    return status;
  }
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, 0L);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_download);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &writer);
  /* With no custom callback, libcurl supplies its built-in transfer meter. */
  curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
  curl_easy_setopt(curl, CURLOPT_STDERR, stderr);
  code = curl_easy_perform(curl);
  response_status = 0;
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_status);
  curl_easy_cleanup(curl);
  *http_status = response_status;
  *bytes_written = writer.bytes_written;
  close_failed = fflush(writer.file) != 0 || fsync(descriptor) != 0;
  if (fclose(writer.file) != 0)
    close_failed = 1;
  if (code != CURLE_OK || writer.failed || close_failed) {
    unlink(temporary);
    return writer.failed || close_failed ? YT_ERR_STORAGE : YT_ERR_NETWORK;
  }
  if (response_status == 403) {
    unlink(temporary);
    return YT_ERR_PO_TOKEN_REQUIRED;
  }
  if (response_status < 200 || response_status >= 300) {
    unlink(temporary);
    return YT_ERR_HTTP;
  }
  if (!yt_http_has_mp4_ftyp(writer.prefix, writer.prefix_length)) {
    unlink(temporary);
    return YT_ERR_INVALID_MEDIA;
  }
  if (link(temporary, destination) != 0) {
    int link_error = errno;
    unlink(temporary);
    return link_error == EEXIST ? YT_ERR_FILE_EXISTS : YT_ERR_STORAGE;
  }
  if (unlink(temporary) != 0)
    return YT_ERR_STORAGE;
  return YT_OK;
}

YTStatus yt_http_download(const char *url, const char *destination,
                          long *http_status, int64_t *bytes_written) {
  return yt_http_session_download(NULL, url, destination, http_status,
                                  bytes_written);
}

void yt_http_response_free(YTHttpResponse *response) {
  if (response == NULL)
    return;
  free(response->data);
  memset(response, 0, sizeof(*response));
}
