#ifndef RETRO_DLP_YT_HTTP_H
#define RETRO_DLP_YT_HTTP_H

#include <stddef.h>
#include <stdint.h>

#include "retrodlp/retrodlp.h"
#include "yt_cache.h"
#include "yt_ejs.h"
#include "yt_resolver.h"

typedef struct {
  char *data;
  size_t length;
  long status;
} YTHttpResponse;

#ifndef YT_AUTH_COOKIES_TYPE_DEFINED
#define YT_AUTH_COOKIES_TYPE_DEFINED
typedef struct YTAuthCookies YTAuthCookies;
#endif
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
void yt_http_response_free(YTHttpResponse *response);

#endif
