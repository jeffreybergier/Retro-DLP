#ifndef RETRO_DLP_YT_COOKIES_H
#define RETRO_DLP_YT_COOKIES_H

#include <stddef.h>
#include <stdint.h>

#include "yt_resolver.h"

#ifndef YT_AUTH_COOKIES_TYPE_DEFINED
#define YT_AUTH_COOKIES_TYPE_DEFINED
typedef struct YTAuthCookies YTAuthCookies;
#endif

struct YTAuthCookies {
  char *sapisid;
  char *sapisid_1p;
  char *sapisid_3p;
  int has_login_info;
};

YTStatus yt_auth_cookies_load(const char *path, int64_t now_unix,
                              YTAuthCookies *cookies);
YTStatus yt_auth_cookies_parse(const void *data, size_t length,
                               int64_t now_unix, YTAuthCookies *cookies);
int yt_auth_cookies_is_authenticated(const YTAuthCookies *cookies);
YTStatus yt_auth_cookies_make_authorization(
    const YTAuthCookies *cookies, const char *origin,
    const char *user_session_id, int64_t now_unix, char *buffer,
    size_t buffer_size);
void yt_auth_cookies_free(YTAuthCookies *cookies);

#endif
