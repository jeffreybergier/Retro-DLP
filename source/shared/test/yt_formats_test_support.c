#include "yt_formats_test_support.h"

#include <string.h>

#include "cJSON.h"
#include "yt_formats.h"
#include "yt_util.h"

static YTStatus normalize_challenge_status(YTStatus status) {
  return status == YT_ERR_JS_CHALLENGE ? YT_ERR_NO_PROGRESSIVE_MP4 : status;
}

YTStatus yt_test_parse_player_response_with_max_height(
    const char *json, size_t length, int max_height, YTMediaRequest *result) {
  cJSON *document;
  YTMediaSelection selection;
  YTStatus status;

  if (json == NULL || result == NULL || max_height <= 0)
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  memset(&selection, 0, sizeof(selection));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  status = normalize_challenge_status(
      yt_formats_select(NULL, document, NULL, NULL, max_height, 0,
                        &selection));
  if (status == YT_OK) {
    *result = selection.video;
    memset(&selection.video, 0, sizeof(selection.video));
  }
  yt_media_selection_free(&selection);
  cJSON_Delete(document);
  return status;
}

YTStatus yt_test_parse_player_response(const char *json, size_t length,
                                       YTMediaRequest *result) {
  return yt_test_parse_player_response_with_max_height(
      json, length, YT_DEFAULT_MAX_HEIGHT, result);
}

YTStatus yt_test_parse_player_response_with_adaptive_size(
    const char *json, size_t length, int max_height,
    YTMediaSelection *result) {
  cJSON *document;
  YTStatus status;

  if (json == NULL || result == NULL ||
      (max_height != 720 && max_height != 1080))
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  status = normalize_challenge_status(
      yt_formats_select(NULL, document, NULL, NULL, max_height, 1, result));
  cJSON_Delete(document);
  return status;
}

YTStatus yt_test_parse_player_response_with_format(
    const char *json, size_t length, const char *format_expression,
    YTMediaSelection *result) {
  cJSON *document;
  cJSON *details;
  const char *video_id;
  YTStatus status;

  if (json == NULL || result == NULL ||
      !yt_format_expression_valid(format_expression))
    return YT_ERR_INVALID_FORMAT;
  memset(result, 0, sizeof(*result));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  details = cJSON_GetObjectItemCaseSensitive(document, "videoDetails");
  video_id = yt_json_string(details, "videoId");
  status = yt_formats_attach_metadata(document,
                                      video_id == NULL ? "" : video_id,
                                      result);
  if (status == YT_OK)
    status = yt_formats_select_exact(NULL, document, NULL, NULL,
                                     format_expression, result);
  cJSON_Delete(document);
  return status;
}

YTStatus yt_test_parse_player_response_with_javascript(
    const char *json, size_t length, const char *player_source,
    YTHttpSession *session, YTMediaRequest *result) {
  cJSON *document;
  YTMediaSelection selection;
  YTStatus status;

  if (json == NULL || player_source == NULL || result == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  memset(&selection, 0, sizeof(selection));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  status = yt_formats_select(session, document, player_source, NULL,
                             YT_DEFAULT_MAX_HEIGHT, 0, &selection);
  if (status == YT_OK) {
    *result = selection.video;
    memset(&selection.video, 0, sizeof(selection.video));
  }
  yt_media_selection_free(&selection);
  cJSON_Delete(document);
  return status;
}
