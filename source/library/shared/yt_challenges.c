#include "yt_challenges.h"

#include <stdlib.h>

#include "yt_cache.h"
#include "yt_http.h"

#define YT_PLAYER_JAVASCRIPT_TTL (7LL * 24LL * 60LL * 60LL)

YTStatus yt_challenges_load_player(YTHttpSession *session,
                                   const char *player_url, char **source) {
  char key[65];
  char *cached;
  size_t cached_length;
  YTHttpResponse response;
  YTStatus status;
  int64_t now;
  if (player_url == NULL || source == NULL)
    return YT_ERR_INVALID_RESPONSE;
  *source = NULL;
  yt_cache_key_for_string(player_url, key);
  if (key[0] == '\0')
    return YT_ERR_INVALID_RESPONSE;
  cached = NULL;
  cached_length = 0;
  now = yt_http_session_now(session);
  if (yt_http_session_cache_get(session, YT_CACHE_PLAYER_JAVASCRIPT, key, now,
                                &cached, &cached_length) == YT_CACHE_OK) {
    if (cached_length != 0) {
      *source = cached;
      return YT_OK;
    }
    free(cached);
    yt_http_session_cache_remove(session, YT_CACHE_PLAYER_JAVASCRIPT, key);
  }
  status = yt_http_session_get(session, player_url, 8U * 1024U * 1024U,
                               &response);
  if (status != YT_OK)
    return status;
  if (response.status != 200 || response.length == 0) {
    status = response.status == 200 ? YT_ERR_INVALID_RESPONSE : YT_ERR_HTTP;
    yt_http_response_free(&response);
    return status;
  }
  yt_http_session_cache_put(session, YT_CACHE_PLAYER_JAVASCRIPT, key,
                            response.data, response.length,
                            now == 0 ? 0 : now + YT_PLAYER_JAVASCRIPT_TTL);
  *source = response.data;
  response.data = NULL;
  yt_http_response_free(&response);
  return YT_OK;
}

YTStatus yt_challenges_solve(YTHttpSession *session,
                             const char *player_source,
                             const YTEJSRequest *requests,
                             size_t request_count, YTEJSResult *result) {
  YTEJSConfig config;
  YTEJSStatus status;
  if (player_source == NULL || requests == NULL || request_count == 0 ||
      result == NULL)
    return YT_ERR_INVALID_RESPONSE;
  config = yt_http_session_ejs_config(session);
  status = yt_ejs_solve_with_session(session, YT_EJS_SOURCE_PLAYER,
                                     player_source, requests, request_count,
                                     &config, result);
  if (status == YT_EJS_ERR_ASSETS_MISSING)
    return YT_ERR_EJS_ASSETS_MISSING;
  if (status == YT_EJS_ERR_ASSETS_INVALID)
    return YT_ERR_EJS_ASSETS_CORRUPT;
  if (status == YT_EJS_ERR_OUT_OF_MEMORY)
    return YT_ERR_OUT_OF_MEMORY;
  if (status == YT_EJS_ERR_CANCELLED)
    return YT_ERR_CANCELLED;
  if (status == YT_EJS_ERR_TIMEOUT)
    return YT_ERR_EJS_TIMEOUT;
  if (status == YT_EJS_ERR_INVALID_RESULT ||
      status == YT_EJS_ERR_INVALID_ARGUMENT)
    return YT_ERR_EJS_INVALID_RESULT;
  return status == YT_EJS_OK ? YT_OK : YT_ERR_EJS_EXCEPTION;
}

void yt_challenges_result_free(YTEJSResult *result) {
  yt_ejs_result_free(result);
}
