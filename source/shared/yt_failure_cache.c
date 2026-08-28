#include "yt_failure_cache.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "yt_cache.h"
#include "yt_http.h"

static int64_t current_time(YTHttpSession *session) {
  return yt_http_session_now(session);
}

int yt_failure_cache_ttl(YTStatus status) {
  switch (status) {
    case YT_ERR_UNAVAILABLE:
      return 5 * 60;
    case YT_ERR_NO_PROGRESSIVE_MP4:
      return 2 * 60;
    case YT_ERR_INVALID_RESPONSE:
    case YT_ERR_JS_CHALLENGE:
      return 30;
    case YT_ERR_HTTP:
      return 15;
    default:
      return 0;
  }
}

void yt_failure_cache_key_for_session(const char *video_id,
                                      const char *client_name,
                                      const char *client_version,
                                      int authenticated, char key[65]) {
  char material[128];
  if (video_id == NULL || client_name == NULL || client_version == NULL ||
      key == NULL) {
    if (key != NULL)
      key[0] = '\0';
    return;
  }
  if (snprintf(material, sizeof(material), "%s:%s:%s:%s", video_id,
               client_name, client_version,
               authenticated ? "authenticated" : "anonymous") >=
      (int)sizeof(material)) {
    key[0] = '\0';
    return;
  }
  yt_cache_key_for_string(material, key);
}

void yt_failure_cache_key(const char *video_id, const YTInnertubeClient *client,
                              int authenticated, int max_height,
                              int try_adaptive, char key[65]) {
  char session_key[65];
  char material[96];
  yt_failure_cache_key_for_session(video_id, client->name, client->version,
                                   authenticated, session_key);
  if (session_key[0] == '\0' ||
      snprintf(material, sizeof(material), "%s:%s:%d", session_key,
               try_adaptive ? "adaptive" : "progressive", max_height) >=
          (int)sizeof(material)) {
    key[0] = '\0';
    return;
  }
  yt_cache_key_for_string(material, key);
}

void yt_failure_cache_exact_key(const char *video_id,
                                    const YTInnertubeClient *client,
                                    int authenticated,
                                    const char *format_expression,
                                    char key[65]) {
  char session_key[65];
  char format_key[65];
  char material[132];
  yt_failure_cache_key_for_session(video_id, client->name, client->version,
                                   authenticated, session_key);
  yt_cache_key_for_string(format_expression, format_key);
  if (session_key[0] == '\0' || format_key[0] == '\0' ||
      snprintf(material, sizeof(material), "%s:%s", session_key, format_key) >=
          (int)sizeof(material)) {
    key[0] = '\0';
    return;
  }
  yt_cache_key_for_string(material, key);
}

int yt_failure_cache_load(YTHttpSession *session, const char *key,
                               YTStatus *status) {
  char *value;
  size_t length;
  char *end;
  long parsed;
  value = NULL;
  length = 0;
  if (key == NULL || status == NULL || key[0] == '\0' ||
      yt_http_session_cache_get(session, YT_CACHE_FAILURE, key,
                                current_time(session), &value, &length) !=
          YT_CACHE_OK)
    return 0;
  parsed = strtol(value, &end, 10);
  if (end != value + length || parsed <= YT_OK ||
      parsed > YT_ERR_AUTH_COOKIES_INVALID ||
      yt_failure_cache_ttl((YTStatus)parsed) == 0) {
    free(value);
    yt_http_session_cache_remove(session, YT_CACHE_FAILURE, key);
    return 0;
  }
  free(value);
  *status = (YTStatus)parsed;
  return 1;
}

void yt_failure_cache_remember(YTHttpSession *session, const char *key,
                               YTStatus status) {
  char value[16];
  int length;
  int ttl = yt_failure_cache_ttl(status);
  int64_t now;
  if (key == NULL || key[0] == '\0' || ttl == 0)
    return;
  length = snprintf(value, sizeof(value), "%d", (int)status);
  now = current_time(session);
  if (length > 0 && length < (int)sizeof(value))
    yt_http_session_cache_put(session, YT_CACHE_FAILURE, key, value,
                              (size_t)length, now == 0 ? 0 : now + ttl);
}

void yt_failure_cache_clear(YTHttpSession *session, const char *key) {
  if (key != NULL && key[0] != '\0')
    yt_http_session_cache_remove(session, YT_CACHE_FAILURE, key);
}

int yt_load_cached_failure(const char *key, YTStatus *status) {
  return yt_failure_cache_load(NULL, key, status);
}

void yt_remember_failure(const char *key, YTStatus status) {
  yt_failure_cache_remember(NULL, key, status);
}
