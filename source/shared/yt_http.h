#ifndef RETRO_DLP_YT_HTTP_H
#define RETRO_DLP_YT_HTTP_H

#include <stddef.h>

#include "yt_resolver.h"

typedef struct {
  char *data;
  size_t length;
  long status;
} YTHttpResponse;

typedef struct rdlp_transport rdlp_transport;
typedef int (*YTHttpCancelCallback)(void *opaque);

YTStatus yt_http_session_create(const char *cookie_file,
                                YTHttpSession **session);
YTStatus yt_http_session_create_with_transport(
    const char *cookie_file, const rdlp_transport *transport,
    unsigned long timeout_milliseconds, YTHttpCancelCallback cancel_callback,
    void *cancel_opaque, YTHttpSession **session);
void yt_http_session_destroy(YTHttpSession *session);

YTStatus yt_http_post_json(const char *url, const char *json,
                           const char *const *headers, size_t header_count,
                           YTHttpResponse *response);
YTStatus yt_http_get(const char *url, size_t maximum_size,
                     YTHttpResponse *response);
YTStatus yt_http_get_range(const char *url, size_t length,
                           YTHttpResponse *response);
YTStatus yt_http_head(const char *url, const char *user_agent,
                      long *http_status);
YTStatus yt_http_download(const char *url, const char *destination,
                          const char *user_agent, long *http_status,
                          int64_t *bytes_written);
YTStatus yt_http_session_post_json(YTHttpSession *session, const char *url,
                                   const char *json,
                                   const char *const *headers,
                                   size_t header_count,
                                   YTHttpResponse *response);
YTStatus yt_http_session_get(YTHttpSession *session, const char *url,
                             size_t maximum_size, YTHttpResponse *response);
YTStatus yt_http_session_get_with_user_agent(
    YTHttpSession *session, const char *url, size_t maximum_size,
    const char *user_agent, YTHttpResponse *response);
YTStatus yt_http_session_get_range(YTHttpSession *session, const char *url,
                                   size_t length, YTHttpResponse *response);
YTStatus yt_http_session_head(YTHttpSession *session, const char *url,
                              const char *user_agent, long *http_status);
YTStatus yt_http_session_download(YTHttpSession *session, const char *url,
                                  const char *destination,
                                  const char *user_agent, long *http_status,
                                  int64_t *bytes_written);
int yt_http_has_mp4_ftyp(const unsigned char *prefix, size_t length);
void yt_http_response_free(YTHttpResponse *response);

#endif
