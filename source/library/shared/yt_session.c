#include "yt_session.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "yt_http.h"
#include "yt_util.h"
#include "yt_webpage.h"

void yt_account_context_free(YTAccountContext *account) {
  if (account == NULL)
    return;
  yt_auth_cookies_free(&account->cookies);
  free(account->data_sync_id);
  free(account->delegated_session_id);
  free(account->user_session_id);
  memset(account, 0, sizeof(*account));
}

YTStatus yt_account_context_load_page(YTAccountContext *account,
                                      const char *page) {
  char *data_sync_id;
  char *delegated_session_id;
  char *user_session_id;
  int has_session_index;
  if (account == NULL || page == NULL)
    return YT_ERR_INVALID_RESPONSE;
  account->logged_in =
      yt_webpage_true_after_marker(page, "\"LOGGED_IN\"");
  account->session_index = yt_webpage_integer_after_marker(
      page, "\"SESSION_INDEX\"", 1, &has_session_index);
  account->has_session_index = has_session_index;
  data_sync_id =
      yt_webpage_string_after_marker(page, "\"DATASYNC_ID\"");
  delegated_session_id = yt_webpage_string_after_marker(
      page, "\"DELEGATED_SESSION_ID\"");
  user_session_id = yt_webpage_string_after_marker(
      page, "\"USER_SESSION_ID\"");
  if (data_sync_id != NULL && user_session_id == NULL) {
    char *separator = strstr(data_sync_id, "||");
    if (separator != NULL) {
      if (separator[2] != '\0') {
        user_session_id = yt_copy_string(separator + 2);
        if (separator != data_sync_id && delegated_session_id == NULL) {
          *separator = '\0';
          delegated_session_id = yt_copy_string(data_sync_id);
          *separator = '|';
        }
      } else {
        *separator = '\0';
        user_session_id = yt_copy_string(data_sync_id);
        *separator = '|';
      }
    }
  }
  free(account->data_sync_id);
  free(account->delegated_session_id);
  free(account->user_session_id);
  account->data_sync_id = data_sync_id;
  account->delegated_session_id = delegated_session_id;
  account->user_session_id = user_session_id;
  return YT_OK;
}

YTStatus yt_account_context_load_cookies(YTHttpSession *session,
                                         const char *cookie_file,
                                         YTAccountContext *account) {
  YTStatus status;
  if (account == NULL)
    return YT_ERR_INVALID_RESPONSE;
  if (cookie_file == NULL && !yt_http_session_has_cookies(session))
    return YT_OK;
  status = session != NULL
               ? yt_http_session_load_auth_cookies(
                     session, yt_http_session_now(session), &account->cookies)
               : yt_auth_cookies_load(cookie_file, yt_http_session_now(NULL),
                                      &account->cookies);
  if (status == YT_OK)
    account->authenticated = 1;
  return status;
}

YTStatus yt_account_append_auth_headers(
    YTHttpSession *session, const YTAccountContext *account,
    const char *origin, const char **headers, size_t capacity,
    size_t *header_count, YTAuthHeaderStorage *storage) {
  YTStatus status;
#define YT_APPEND_HEADER(value)                                               \
  do {                                                                        \
    if (*header_count >= capacity)                                            \
      return YT_ERR_INVALID_RESPONSE;                                         \
    headers[(*header_count)++] = (value);                                     \
  } while (0)
  if (account == NULL || !account->authenticated)
    return YT_OK;
  memset(storage, 0, sizeof(*storage));
  status = yt_auth_cookies_make_authorization(
      &account->cookies, origin, account->user_session_id,
      yt_http_session_now(session), storage->authorization_value,
      sizeof(storage->authorization_value));
  if (status != YT_OK)
    return status;
  if (snprintf(storage->authorization_header,
               sizeof(storage->authorization_header), "Authorization: %s",
               storage->authorization_value) >=
      (int)sizeof(storage->authorization_header))
    return YT_ERR_INVALID_RESPONSE;
  YT_APPEND_HEADER(storage->authorization_header);
  if (strcmp(origin, "https://www.youtube.com") == 0)
    YT_APPEND_HEADER("X-Origin: https://www.youtube.com");
  else
    return YT_ERR_INVALID_RESPONSE;
  if (account->has_session_index || account->delegated_session_id != NULL) {
    if (snprintf(storage->auth_user_header,
                 sizeof(storage->auth_user_header), "X-Goog-AuthUser: %d",
                 account->has_session_index ? account->session_index : 0) >=
        (int)sizeof(storage->auth_user_header))
      return YT_ERR_INVALID_RESPONSE;
    YT_APPEND_HEADER(storage->auth_user_header);
  }
  if (account->delegated_session_id != NULL) {
    if (snprintf(storage->page_id_header, sizeof(storage->page_id_header),
                 "X-Goog-PageId: %s", account->delegated_session_id) >=
        (int)sizeof(storage->page_id_header))
      return YT_ERR_INVALID_RESPONSE;
    YT_APPEND_HEADER(storage->page_id_header);
  }
  if (account->logged_in)
    YT_APPEND_HEADER("X-Youtube-Bootstrap-Logged-In: true");
  return YT_OK;
#undef YT_APPEND_HEADER
}

void yt_auth_header_storage_clear(YTAuthHeaderStorage *storage) {
  if (storage != NULL)
    memset(storage, 0, sizeof(*storage));
}
