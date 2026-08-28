#ifndef RETRO_DLP_YT_SESSION_H
#define RETRO_DLP_YT_SESSION_H

#include <stddef.h>

#include "yt_cookies.h"
#include "yt_resolver.h"

typedef struct {
  YTAuthCookies cookies;
  char *data_sync_id;
  char *delegated_session_id;
  char *user_session_id;
  int authenticated;
  int logged_in;
  int has_session_index;
  int session_index;
} YTAccountContext;

typedef struct {
  char authorization_value[1024];
  char authorization_header[1100];
  char auth_user_header[64];
  char page_id_header[1024];
} YTAuthHeaderStorage;

void yt_account_context_free(YTAccountContext *account);
YTStatus yt_account_context_load_page(YTAccountContext *account,
                                      const char *page);
YTStatus yt_account_context_load_cookies(YTHttpSession *session,
                                         const char *cookie_file,
                                         YTAccountContext *account);
YTStatus yt_account_append_auth_headers(
    YTHttpSession *session, const YTAccountContext *account,
    const char *origin, const char **headers, size_t capacity,
    size_t *header_count, YTAuthHeaderStorage *storage);
void yt_auth_header_storage_clear(YTAuthHeaderStorage *storage);

#endif
