#include "yt_resolver.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <curl/curl.h>

#include "cJSON.h"
#include "yt_http.h"

#define YT_PLAYER_ENDPOINT                                                   \
  "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
#define YT_CLIENT_NAME "ANDROID_VR"
#define YT_CLIENT_NAME_ID "28"
#define YT_CLIENT_VERSION "1.65.10"
#define YT_USER_AGENT                                                       \
  "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android "   \
  "12L; eureka-user Build/SQ3A.220605.009.A1) gzip"

static char *copy_string(const char *value) {
  size_t length;
  char *copy;

  if (value == NULL)
    return NULL;
  length = strlen(value);
  copy = (char *)malloc(length + 1);
  if (copy != NULL)
    memcpy(copy, value, length + 1);
  return copy;
}

static int is_video_id_character(char value) {
  return isalnum((unsigned char)value) || value == '-' || value == '_';
}

static int copy_candidate(const char *candidate, char video_id[12]) {
  size_t index;

  if (candidate == NULL)
    return 0;
  for (index = 0; index < 11; ++index) {
    if (candidate[index] == '\0' || !is_video_id_character(candidate[index]))
      return 0;
    video_id[index] = candidate[index];
  }
  if (is_video_id_character(candidate[11]))
    return 0;
  video_id[11] = '\0';
  return 1;
}

static int host_equals(const char *host, size_t host_length,
                       const char *expected) {
  size_t expected_length;

  expected_length = strlen(expected);
  return host_length == expected_length &&
         strncasecmp(host, expected, host_length) == 0;
}

static int is_youtube_host(const char *host, size_t host_length) {
  static const char suffix[] = ".youtube.com";
  size_t suffix_length;

  if (host_equals(host, host_length, "youtube.com") ||
      host_equals(host, host_length, "youtube-nocookie.com") ||
      host_equals(host, host_length, "www.youtube-nocookie.com"))
    return 1;
  suffix_length = sizeof(suffix) - 1;
  return host_length > suffix_length &&
         strncasecmp(host + host_length - suffix_length, suffix,
                     suffix_length) == 0;
}

static int copy_query_video_id(const char *query, char video_id[12]) {
  const char *candidate;

  while (query != NULL && *query != '\0' && *query != '#') {
    if ((query[0] == '?' || query[0] == '&') && query[1] == 'v' &&
        query[2] == '=' && copy_candidate(query + 3, video_id))
      return 1;
    candidate = strchr(query + 1, '&');
    query = candidate;
  }
  return 0;
}

YTStatus yt_extract_video_id(const char *input, char video_id[12]) {
  const char *authority;
  const char *host_end;
  const char *path;
  const char *port;
  size_t host_length;

  if (input == NULL || video_id == NULL)
    return YT_ERR_INVALID_VIDEO_ID;
  if (copy_candidate(input, video_id))
    return YT_OK;

  if (strncmp(input, "https://", 8) == 0)
    authority = input + 8;
  else if (strncmp(input, "http://", 7) == 0)
    authority = input + 7;
  else
    return YT_ERR_INVALID_VIDEO_ID;

  path = strpbrk(authority, "/?#");
  if (path == NULL || path == authority || memchr(authority, '@',
                                                   (size_t)(path - authority)))
    return YT_ERR_INVALID_VIDEO_ID;
  host_end = path;
  port = (const char *)memchr(authority, ':', (size_t)(path - authority));
  if (port != NULL)
    host_end = port;
  host_length = (size_t)(host_end - authority);

  if (host_equals(authority, host_length, "youtu.be") && path[0] == '/' &&
      copy_candidate(path + 1, video_id))
    return YT_OK;
  if (!is_youtube_host(authority, host_length))
    return YT_ERR_INVALID_VIDEO_ID;
  if (strncmp(path, "/shorts/", 8) == 0 &&
      copy_candidate(path + 8, video_id))
    return YT_OK;
  if (strncmp(path, "/embed/", 7) == 0 && copy_candidate(path + 7, video_id))
    return YT_OK;
  if (copy_query_video_id(strchr(path, '?'), video_id))
    return YT_OK;
  return YT_ERR_INVALID_VIDEO_ID;
}

static cJSON *create_player_request(const char *video_id,
                                    const char *visitor_data) {
  cJSON *root;
  cJSON *context;
  cJSON *client;
  cJSON *playback_context;
  cJSON *content_playback_context;

  root = cJSON_CreateObject();
  if (root == NULL)
    return NULL;
  context = cJSON_AddObjectToObject(root, "context");
  client = cJSON_AddObjectToObject(context, "client");
  playback_context = cJSON_AddObjectToObject(root, "playbackContext");
  content_playback_context =
      cJSON_AddObjectToObject(playback_context, "contentPlaybackContext");
  if (context == NULL || client == NULL || playback_context == NULL ||
      content_playback_context == NULL)
    goto failed;

  if (!cJSON_AddStringToObject(client, "clientName", YT_CLIENT_NAME) ||
      !cJSON_AddStringToObject(client, "clientVersion", YT_CLIENT_VERSION) ||
      !cJSON_AddStringToObject(client, "deviceMake", "Oculus") ||
      !cJSON_AddStringToObject(client, "deviceModel", "Quest 3") ||
      !cJSON_AddNumberToObject(client, "androidSdkVersion", 32) ||
      !cJSON_AddStringToObject(client, "userAgent", YT_USER_AGENT) ||
      !cJSON_AddStringToObject(client, "osName", "Android") ||
      !cJSON_AddStringToObject(client, "osVersion", "12L") ||
      !cJSON_AddStringToObject(client, "hl", "en") ||
      !cJSON_AddStringToObject(client, "timeZone", "UTC") ||
      !cJSON_AddNumberToObject(client, "utcOffsetMinutes", 0) ||
      (visitor_data != NULL &&
       !cJSON_AddStringToObject(client, "visitorData", visitor_data)) ||
      !cJSON_AddStringToObject(root, "videoId", video_id) ||
      !cJSON_AddBoolToObject(root, "contentCheckOk", 1) ||
      !cJSON_AddBoolToObject(root, "racyCheckOk", 1))
    goto failed;

  if (!cJSON_AddStringToObject(content_playback_context, "html5Preference",
                               "HTML5_PREF_WANTS"))
    goto failed;
  return root;

failed:
  cJSON_Delete(root);
  return NULL;
}

static YTStatus call_player(const char *video_id, const char *visitor_data,
                            cJSON **document_out) {
  static const char *const base_headers[] = {
      "Content-Type: application/json",
      "Origin: https://www.youtube.com",
      "X-YouTube-Client-Name: " YT_CLIENT_NAME_ID,
      "X-YouTube-Client-Version: " YT_CLIENT_VERSION,
      "User-Agent: " YT_USER_AGENT};
  char visitor_header[1024];
  const char *headers[6];
  size_t header_count;
  cJSON *request;
  char *json;
  YTHttpResponse response;
  YTStatus status;

  request = create_player_request(video_id, visitor_data);
  if (request == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  json = cJSON_PrintUnformatted(request);
  cJSON_Delete(request);
  if (json == NULL)
    return YT_ERR_OUT_OF_MEMORY;

  memcpy(headers, base_headers, sizeof(base_headers));
  header_count = sizeof(base_headers) / sizeof(base_headers[0]);
  if (visitor_data != NULL) {
    if (snprintf(visitor_header, sizeof(visitor_header),
                 "X-Goog-Visitor-Id: %s", visitor_data) >=
        (int)sizeof(visitor_header)) {
      free(json);
      return YT_ERR_INVALID_RESPONSE;
    }
    headers[header_count++] = visitor_header;
  }

  status = yt_http_post_json(YT_PLAYER_ENDPOINT, json, headers, header_count,
                             &response);
  free(json);
  if (status != YT_OK)
    return status;
  if (response.status < 200 || response.status >= 300) {
    yt_http_response_free(&response);
    return YT_ERR_HTTP;
  }
  *document_out = cJSON_ParseWithLength(response.data, response.length);
  yt_http_response_free(&response);
  return *document_out == NULL ? YT_ERR_INVALID_RESPONSE : YT_OK;
}

static const char *json_string(cJSON *object, const char *name) {
  cJSON *value;
  value = cJSON_GetObjectItemCaseSensitive(object, name);
  return cJSON_IsString(value) ? value->valuestring : NULL;
}

static int json_integer(cJSON *object, const char *name) {
  cJSON *value;
  value = cJSON_GetObjectItemCaseSensitive(object, name);
  return cJSON_IsNumber(value) ? value->valueint : 0;
}

static int64_t parse_decimal(const char *value) {
  int64_t result;
  if (value == NULL)
    return 0;
  result = 0;
  while (*value >= '0' && *value <= '9') {
    result = result * 10 + (*value - '0');
    ++value;
  }
  return result;
}

static int64_t url_query_integer(const char *url, const char *name) {
  size_t name_length;
  const char *cursor;

  name_length = strlen(name);
  cursor = strchr(url, '?');
  while (cursor != NULL) {
    ++cursor;
    if (strncmp(cursor, name, name_length) == 0 && cursor[name_length] == '=')
      return parse_decimal(cursor + name_length + 1);
    cursor = strchr(cursor, '&');
  }
  return 0;
}

static int url_has_query_parameter(const char *url, const char *name) {
  size_t name_length;
  const char *cursor;

  if (url == NULL || name == NULL)
    return 0;
  name_length = strlen(name);
  cursor = strchr(url, '?');
  while (cursor != NULL) {
    ++cursor;
    if (strncmp(cursor, name, name_length) == 0 && cursor[name_length] == '=')
      return 1;
    cursor = strchr(cursor, '&');
  }
  return 0;
}

static YTStatus select_itag_18(cJSON *document, YTMediaRequest *result) {
  cJSON *streaming_data;
  cJSON *formats;
  cJSON *format;
  const char *url;
  const char *mime_type;
  const char *content_length;

  streaming_data = cJSON_GetObjectItemCaseSensitive(document, "streamingData");
  formats = cJSON_GetObjectItemCaseSensitive(streaming_data, "formats");
  if (!cJSON_IsArray(formats))
    return YT_ERR_NO_PROGRESSIVE_MP4;

  cJSON_ArrayForEach(format, formats) {
    if (json_integer(format, "itag") != 18)
      continue;
    url = json_string(format, "url");
    mime_type = json_string(format, "mimeType");
    if (url == NULL || mime_type == NULL || url_has_query_parameter(url, "n") ||
        strncmp(mime_type, "video/mp4", 9) != 0)
      continue;
    result->url = copy_string(url);
    result->mime_type = copy_string(mime_type);
    result->user_agent = copy_string(YT_USER_AGENT);
    if (result->url == NULL || result->mime_type == NULL ||
        result->user_agent == NULL) {
      yt_media_request_free(result);
      return YT_ERR_OUT_OF_MEMORY;
    }
    result->itag = 18;
    result->width = json_integer(format, "width");
    result->height = json_integer(format, "height");
    result->expires_unix = url_query_integer(url, "expire");
    content_length = json_string(format, "contentLength");
    result->content_length = parse_decimal(content_length);
    return YT_OK;
  }
  return YT_ERR_NO_PROGRESSIVE_MP4;
}

static YTStatus parse_player_document(cJSON *document,
                                      YTMediaRequest *result) {
  cJSON *playability;
  const char *playability_status;

  if (document == NULL || result == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  playability = cJSON_GetObjectItemCaseSensitive(document,
                                                 "playabilityStatus");
  playability_status = json_string(playability, "status");
  if (playability_status == NULL || strcmp(playability_status, "OK") != 0)
    return YT_ERR_UNAVAILABLE;
  return select_itag_18(document, result);
}

YTStatus yt_parse_player_response(const char *json, size_t length,
                                  YTMediaRequest *result) {
  cJSON *document;
  YTStatus status;

  if (json == NULL || result == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  status = parse_player_document(document, result);
  cJSON_Delete(document);
  return status;
}

YTStatus yt_resolve_video(const char *input, YTMediaRequest *result) {
  char video_id[12];
  cJSON *document;
  cJSON *response_context;
  const char *visitor_data;
  char *visitor_copy;
  YTStatus status;

  if (result == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  status = yt_extract_video_id(input, video_id);
  if (status != YT_OK)
    return status;

  document = NULL;
  status = call_player(video_id, NULL, &document);
  if (status != YT_OK)
    return status;

  response_context = cJSON_GetObjectItemCaseSensitive(document,
                                                       "responseContext");
  visitor_data = json_string(response_context, "visitorData");
  visitor_copy = copy_string(visitor_data);
  if (visitor_data != NULL && visitor_copy == NULL) {
    cJSON_Delete(document);
    return YT_ERR_OUT_OF_MEMORY;
  }

  if (visitor_copy != NULL) {
    cJSON_Delete(document);
    document = NULL;
    status = call_player(video_id, visitor_copy, &document);
    free(visitor_copy);
    if (status != YT_OK)
      return status;
  }

  status = parse_player_document(document, result);
  cJSON_Delete(document);
  return status;
}

YTStatus yt_classify_media_http_status(long http_status) {
  if (http_status == 403)
    return YT_ERR_PO_TOKEN_REQUIRED;
  if (http_status >= 200 && http_status < 400)
    return YT_OK;
  return YT_ERR_HTTP;
}

YTStatus yt_probe_media_head(const YTMediaRequest *media, long *http_status) {
  YTStatus status;

  if (media == NULL || media->url == NULL)
    return YT_ERR_INVALID_RESPONSE;
  status = yt_http_head(media->url, media->user_agent, http_status);
  if (status != YT_OK)
    return status;
  return yt_classify_media_http_status(*http_status);
}

void yt_media_request_free(YTMediaRequest *media) {
  if (media == NULL)
    return;
  free(media->url);
  free(media->mime_type);
  free(media->user_agent);
  memset(media, 0, sizeof(*media));
}

const char *yt_status_string(YTStatus status) {
  switch (status) {
  case YT_OK:
    return "success";
  case YT_ERR_INVALID_VIDEO_ID:
    return "invalid YouTube video ID";
  case YT_ERR_OUT_OF_MEMORY:
    return "out of memory";
  case YT_ERR_NETWORK:
    return "network request failed";
  case YT_ERR_CERTIFICATE_BUNDLE:
    return "CA certificate bundle is missing beside the executable";
  case YT_ERR_HTTP:
    return "HTTP request failed";
  case YT_ERR_INVALID_RESPONSE:
    return "invalid YouTube response";
  case YT_ERR_UNAVAILABLE:
    return "video unavailable";
  case YT_ERR_NO_PROGRESSIVE_MP4:
    return "no direct progressive MP4 available";
  case YT_ERR_PO_TOKEN_REQUIRED:
    return "PO token required";
  }
  return "unknown error";
}
