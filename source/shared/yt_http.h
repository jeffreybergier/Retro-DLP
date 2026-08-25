#ifndef RETRO_DLP_YT_HTTP_H
#define RETRO_DLP_YT_HTTP_H

#include <stddef.h>

#include "yt_resolver.h"

typedef struct {
  char *data;
  size_t length;
  long status;
} YTHttpResponse;

YTStatus yt_http_post_json(const char *url, const char *json,
                           const char *const *headers, size_t header_count,
                           YTHttpResponse *response);
YTStatus yt_http_get(const char *url, size_t maximum_size,
                     YTHttpResponse *response);
YTStatus yt_http_head(const char *url, const char *user_agent,
                      long *http_status);
void yt_http_response_free(YTHttpResponse *response);

#endif
