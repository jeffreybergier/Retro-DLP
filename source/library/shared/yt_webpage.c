#include "yt_webpage.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "yt_http.h"
#include "yt_util.h"

#define YT_WEBPAGE_MAX_RESPONSE (8U * 1024U * 1024U)

char *yt_webpage_string_after_marker(const char *text, const char *marker) {
  const char *start;
  const char *cursor;
  cJSON *value;
  char *result;
  if (text == NULL || marker == NULL)
    return NULL;
  start = strstr(text, marker);
  if (start == NULL)
    return NULL;
  start += strlen(marker);
  while (*start == ' ' || *start == '\t' || *start == ':')
    ++start;
  if (*start != '"')
    return NULL;
  cursor = start + 1;
  while (*cursor != '\0') {
    if (*cursor == '\\' && cursor[1] != '\0') {
      cursor += 2;
      continue;
    }
    if (*cursor == '"')
      break;
    ++cursor;
  }
  if (*cursor != '"')
    return NULL;
  value = cJSON_ParseWithLength(start, (size_t)(cursor - start + 1));
  if (!cJSON_IsString(value)) {
    cJSON_Delete(value);
    return NULL;
  }
  result = yt_copy_string(value->valuestring);
  cJSON_Delete(value);
  return result;
}

int yt_webpage_integer_after_marker(const char *text, const char *marker,
                                    int allow_zero, int *found) {
  const char *start;
  char *end;
  long value;
  if (found != NULL)
    *found = 0;
  if (text == NULL || marker == NULL)
    return 0;
  start = strstr(text, marker);
  if (start == NULL)
    return 0;
  start += strlen(marker);
  while (*start == ' ' || *start == '\t' || *start == ':')
    ++start;
  value = strtol(start, &end, 10);
  if (end == start || value < (allow_zero ? 0 : 1) || value > INT_MAX)
    return 0;
  if (found != NULL)
    *found = 1;
  return (int)value;
}

int yt_webpage_true_after_marker(const char *text, const char *marker) {
  const char *start;
  if (text == NULL || marker == NULL)
    return 0;
  start = strstr(text, marker);
  if (start == NULL)
    return 0;
  start += strlen(marker);
  while (*start == ' ' || *start == '\t' || *start == ':')
    ++start;
  return strncmp(start, "true", 4) == 0;
}

cJSON *yt_webpage_embedded_json(const char *page, const char *marker) {
  const char *cursor;
  const char *start;
  size_t depth;
  int in_string;
  int escaped;
  if (page == NULL || marker == NULL)
    return NULL;
  cursor = strstr(page, marker);
  if (cursor == NULL)
    return NULL;
  cursor += strlen(marker);
  while (*cursor != '\0' && *cursor != '{')
    ++cursor;
  if (*cursor != '{')
    return NULL;
  start = cursor;
  depth = 0;
  in_string = 0;
  escaped = 0;
  do {
    char byte = *cursor++;
    if (byte == '\0')
      return NULL;
    if (in_string) {
      if (escaped)
        escaped = 0;
      else if (byte == '\\')
        escaped = 1;
      else if (byte == '"')
        in_string = 0;
      continue;
    }
    if (byte == '"')
      in_string = 1;
    else if (byte == '{' || byte == '[')
      ++depth;
    else if (byte == '}' || byte == ']') {
      if (depth == 0)
        return NULL;
      --depth;
    }
  } while (depth != 0);
  return cJSON_ParseWithLength(start, (size_t)(cursor - start));
}

char *yt_webpage_absolute_player_url(const char *value) {
  static const char origin[] = "https://www.youtube.com";
  char *result;
  if (value == NULL)
    return NULL;
  if (strncmp(value, "/s/player/", 10) == 0) {
    size_t length = sizeof(origin) - 1 + strlen(value) + 1;
    result = (char *)malloc(length);
    if (result != NULL)
      snprintf(result, length, "%s%s", origin, value);
    return result;
  }
  if (strncmp(value, "https://www.youtube.com/s/player/", 33) == 0)
    return yt_copy_string(value);
  return NULL;
}

char *yt_webpage_player_url_from_document(cJSON *document) {
  cJSON *assets = cJSON_GetObjectItemCaseSensitive(document, "assets");
  return yt_webpage_absolute_player_url(yt_json_string(assets, "js"));
}

YTStatus yt_webpage_load_mweb_bootstrap(YTHttpSession *session,
                                        YTAccountContext *account,
                                        const char *video_id,
                                        YTInnertubeClient *client,
                                        int *signature_timestamp,
                                        char **player_url) {
  char watch_url[96];
  YTHttpResponse response;
  YTStatus status;
  char *client_version;
  char *relative_player_url;

  *signature_timestamp = 0;
  *player_url = NULL;
  if (snprintf(watch_url, sizeof(watch_url),
               "https://m.youtube.com/watch?v=%s", video_id) >=
      (int)sizeof(watch_url))
    return YT_ERR_INVALID_RESPONSE;
  status = yt_http_session_get(session, watch_url, YT_WEBPAGE_MAX_RESPONSE,
                               &response);
  if (status != YT_OK)
    return status;
  if (response.status < 200 || response.status >= 300) {
    yt_http_response_free(&response);
    return YT_ERR_HTTP;
  }

  client_version = yt_webpage_string_after_marker(
      response.data, "\"INNERTUBE_CONTEXT_CLIENT_VERSION\"");
  *signature_timestamp = yt_webpage_integer_after_marker(
      response.data, "\"STS\"", 0, NULL);
  relative_player_url =
      yt_webpage_string_after_marker(response.data, "\"jsUrl\"");
  if (relative_player_url == NULL)
    relative_player_url =
        yt_webpage_string_after_marker(response.data, "\"PLAYER_JS_URL\"");
  *player_url = yt_webpage_absolute_player_url(relative_player_url);
  free(relative_player_url);

  if (account != NULL && account->authenticated &&
      yt_account_context_load_page(account, response.data) != YT_OK) {
    free(client_version);
    free(*player_url);
    *player_url = NULL;
    yt_http_response_free(&response);
    return YT_ERR_OUT_OF_MEMORY;
  }

  if (client_version == NULL ||
      !yt_copy_field(client->version, sizeof(client->version), client_version) ||
      *signature_timestamp == 0 || *player_url == NULL) {
    free(client_version);
    free(*player_url);
    *player_url = NULL;
    yt_http_response_free(&response);
    return YT_ERR_INVALID_RESPONSE;
  }
  free(client_version);
  yt_http_response_free(&response);
  return YT_OK;
}

YTStatus yt_webpage_load_player_url(YTHttpSession *session,
                                    const char *video_id, char **player_url) {
  char watch_url[96];
  YTHttpResponse response;
  YTStatus status;
  char *relative;
  if (snprintf(watch_url, sizeof(watch_url),
               "https://www.youtube.com/watch?v=%s", video_id) >=
      (int)sizeof(watch_url))
    return YT_ERR_INVALID_RESPONSE;
  status = yt_http_session_get(session, watch_url, YT_WEBPAGE_MAX_RESPONSE,
                               &response);
  if (status != YT_OK)
    return status;
  if (response.status < 200 || response.status >= 300) {
    yt_http_response_free(&response);
    return YT_ERR_HTTP;
  }
  relative = yt_webpage_string_after_marker(response.data, "\"jsUrl\"");
  if (relative == NULL)
    relative = yt_webpage_string_after_marker(response.data, "\"PLAYER_JS_URL\"");
  *player_url = yt_webpage_absolute_player_url(relative);
  free(relative);
  yt_http_response_free(&response);
  return *player_url == NULL ? YT_ERR_JS_CHALLENGE : YT_OK;
}
