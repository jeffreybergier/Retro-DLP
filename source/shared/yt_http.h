#ifndef RETRO_DLP_YT_HTTP_H
#define RETRO_DLP_YT_HTTP_H

#include <stddef.h>
#include <stdint.h>

#include "yt_cache.h"
#include "yt_ejs.h"
#include "yt_resolver.h"

typedef struct {
  char *data;
  size_t length;
  long status;
} YTHttpResponse;

typedef struct rdlp_transport rdlp_transport;
typedef struct YTAuthCookies YTAuthCookies;
typedef int (*YTHttpCancelCallback)(void *opaque);
typedef int64_t (*YTHttpClockCallback)(void *opaque);

typedef struct {
  const char *cookie_file;
  const void *cookie_data;
  size_t cookie_data_length;
  const rdlp_transport *transport;
  unsigned long timeout_milliseconds;
  const char *cache_directory;
  const char *ca_bundle_path;
  const char *ejs_asset_directory;
  size_t ejs_memory_limit_bytes;
  size_t ejs_stack_limit_bytes;
  YTHttpCancelCallback cancel_callback;
  void *cancel_opaque;
  YTHttpClockCallback clock_callback;
  void *clock_opaque;
} YTHttpSessionConfig;

typedef struct {
  long http_status;
  int transport_code;
  char message[256];
} YTHttpDiagnostic;

YTStatus yt_http_session_create(const char *cookie_file,
                                YTHttpSession **session);
YTStatus yt_http_session_create_with_transport(
    const char *cookie_file, const rdlp_transport *transport,
    unsigned long timeout_milliseconds, YTHttpCancelCallback cancel_callback,
    void *cancel_opaque, YTHttpSession **session);
YTStatus yt_http_session_create_with_config(const YTHttpSessionConfig *config,
                                            YTHttpSession **session);
void yt_http_session_destroy(YTHttpSession *session);
YTStatus yt_http_session_set_cookies(YTHttpSession *session,
                                     const char *cookie_file,
                                     const void *cookie_data,
                                     size_t cookie_data_length);
int64_t yt_http_session_now(YTHttpSession *session);
int yt_http_session_has_cookies(const YTHttpSession *session);
YTStatus yt_http_session_load_auth_cookies(YTHttpSession *session,
                                           int64_t now_unix,
                                           YTAuthCookies *cookies);
YTCacheStatus yt_http_session_cache_get(YTHttpSession *session,
                                        YTCacheKind kind, const char *key,
                                        int64_t now_unix, char **data,
                                        size_t *length);
YTCacheStatus yt_http_session_cache_put(YTHttpSession *session,
                                        YTCacheKind kind, const char *key,
                                        const void *data, size_t length,
                                        int64_t expires_unix);
YTCacheStatus yt_http_session_cache_remove(YTHttpSession *session,
                                           YTCacheKind kind,
                                           const char *key);
const char *yt_http_session_ejs_asset_directory(
    const YTHttpSession *session);
YTEJSConfig yt_http_session_ejs_config(const YTHttpSession *session);
int yt_http_session_cancelled(const YTHttpSession *session);
void yt_http_session_diagnostic(const YTHttpSession *session,
                                YTHttpDiagnostic *diagnostic);

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
