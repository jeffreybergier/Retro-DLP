#include "yt_innertube.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "yt_http.h"
#include "yt_util.h"

#define YT_PLAYER_ENDPOINT                                                   \
  "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
#define YT_CLIENT_NAME "MWEB"
#define YT_CLIENT_NAME_ID "2"
#define YT_CLIENT_VERSION "2.20260708.05.00"
#define YT_USER_AGENT YT_INNERTUBE_DEFAULT_USER_AGENT
YTStatus yt_innertube_load_client(YTInnertubeClient *client) {
  if (client == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(client, 0, sizeof(*client));
  if (!yt_copy_field(client->name, sizeof(client->name), YT_CLIENT_NAME) ||
      !yt_copy_field(client->id, sizeof(client->id), YT_CLIENT_NAME_ID) ||
      !yt_copy_field(client->version, sizeof(client->version),
                     YT_CLIENT_VERSION) ||
      !yt_copy_field(client->user_agent, sizeof(client->user_agent),
                     YT_USER_AGENT))
    return YT_ERR_INVALID_RESPONSE;
  return YT_OK;
}

static cJSON *create_player_request(const char *video_id,
                                    const char *visitor_data,
                                    const YTInnertubeClient *configured_client,
                                    int signature_timestamp) {
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

  if (!cJSON_AddStringToObject(client, "clientName", configured_client->name) ||
      !cJSON_AddStringToObject(client, "clientVersion",
                              configured_client->version) ||
      !cJSON_AddStringToObject(client, "userAgent",
                              configured_client->user_agent) ||
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
  if (signature_timestamp > 0 &&
      !cJSON_AddNumberToObject(content_playback_context, "signatureTimestamp",
                              signature_timestamp))
    goto failed;
  return root;

failed:
  cJSON_Delete(root);
  return NULL;
}

YTStatus yt_innertube_call_player(YTHttpSession *session,
                                  const YTAccountContext *account,
                                  const char *video_id,
                                  const char *visitor_data,
                                  const YTInnertubeClient *client,
                                  int signature_timestamp,
                                  cJSON **document_out) {
  static const char *const fixed_headers[] = {
      "Content-Type: application/json", "Origin: https://www.youtube.com"};
  char client_name_header[64];
  char client_version_header[96];
  char user_agent_header[320];
  char visitor_header[1024];
  YTAuthHeaderStorage auth_storage;
  const char *headers[12];
  size_t header_count;
  cJSON *request;
  char *json;
  YTHttpResponse response;
  YTStatus status;

  request = create_player_request(video_id, visitor_data, client,
                                  signature_timestamp);
  if (request == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  json = cJSON_PrintUnformatted(request);
  cJSON_Delete(request);
  if (json == NULL)
    return YT_ERR_OUT_OF_MEMORY;

  memcpy(headers, fixed_headers, sizeof(fixed_headers));
  header_count = sizeof(fixed_headers) / sizeof(fixed_headers[0]);
  if (snprintf(client_name_header, sizeof(client_name_header),
               "X-YouTube-Client-Name: %s", client->id) >=
          (int)sizeof(client_name_header) ||
      snprintf(client_version_header, sizeof(client_version_header),
               "X-YouTube-Client-Version: %s", client->version) >=
          (int)sizeof(client_version_header) ||
      snprintf(user_agent_header, sizeof(user_agent_header), "User-Agent: %s",
               client->user_agent) >= (int)sizeof(user_agent_header)) {
    free(json);
    return YT_ERR_INVALID_RESPONSE;
  }
  headers[header_count++] = client_name_header;
  headers[header_count++] = client_version_header;
  headers[header_count++] = user_agent_header;
  if (visitor_data != NULL) {
    if (snprintf(visitor_header, sizeof(visitor_header),
                 "X-Goog-Visitor-Id: %s", visitor_data) >=
        (int)sizeof(visitor_header)) {
      free(json);
      return YT_ERR_INVALID_RESPONSE;
    }
    headers[header_count++] = visitor_header;
  }

  status = yt_account_append_auth_headers(
      session, account, "https://www.youtube.com", headers,
      sizeof(headers) / sizeof(headers[0]), &header_count, &auth_storage);
  if (status != YT_OK) {
    yt_auth_header_storage_clear(&auth_storage);
    free(json);
    return status;
  }

  status = yt_http_session_post_json(session, YT_PLAYER_ENDPOINT, json,
                                     headers, header_count, &response);
  yt_auth_header_storage_clear(&auth_storage);
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

#define YT_PLAYLIST_ID_MAX 128
#define YT_PLAYLIST_ORIGIN "https://www.youtube.com"
#define YT_PLAYLIST_USER_AGENT                                              \
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "                       \
  "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 "                 \
  "Safari/605.1.15,gzip(gfe)"


static cJSON *create_browse_request(const char *continuation,
                                    const char *playlist_id,
                                    const char *client_version,
                                    const char *visitor_data) {
  cJSON *root;
  cJSON *context;
  cJSON *client;
  root = cJSON_CreateObject();
  if (root == NULL)
    return NULL;
  context = cJSON_AddObjectToObject(root, "context");
  client = cJSON_AddObjectToObject(context, "client");
  if (root == NULL || context == NULL || client == NULL ||
      !cJSON_AddStringToObject(client, "clientName", "WEB") ||
      !cJSON_AddStringToObject(client, "clientVersion", client_version) ||
      !cJSON_AddStringToObject(client, "hl", "en") ||
      !cJSON_AddStringToObject(client, "timeZone", "UTC") ||
      !cJSON_AddNumberToObject(client, "utcOffsetMinutes", 0) ||
      (visitor_data != NULL &&
       !cJSON_AddStringToObject(client, "visitorData", visitor_data)) ||
      (continuation != NULL &&
       !cJSON_AddStringToObject(root, "continuation", continuation))) {
    cJSON_Delete(root);
    return NULL;
  }
  if (playlist_id != NULL) {
    char browse_id[YT_PLAYLIST_ID_MAX + 3];
    if (snprintf(browse_id, sizeof(browse_id), "VL%s", playlist_id) >=
            (int)sizeof(browse_id) ||
        !cJSON_AddStringToObject(root, "browseId", browse_id) ||
        !cJSON_AddStringToObject(root, "params", "wgYCCAA=")) {
      cJSON_Delete(root);
      return NULL;
    }
  }
  return root;
}

YTStatus yt_innertube_call_browse(
    YTHttpSession *session, const YTAccountContext *account,
    const char *api_key, const char *client_version, const char *visitor_data,
    const char *continuation, const char *playlist_id, cJSON **document_out) {
  char endpoint[512];
  char client_version_header[96];
  char visitor_header[1024];
  YTAuthHeaderStorage auth_storage;
  const char *headers[12];
  size_t header_count = 0;
  cJSON *request;
  char *json;
  YTHttpResponse response;
  YTStatus status;
  if (snprintf(endpoint, sizeof(endpoint),
               YT_PLAYLIST_ORIGIN "/youtubei/v1/browse?key=%s&prettyPrint=false",
               api_key) >= (int)sizeof(endpoint) ||
      snprintf(client_version_header, sizeof(client_version_header),
               "X-YouTube-Client-Version: %s", client_version) >=
          (int)sizeof(client_version_header))
    return YT_ERR_INVALID_RESPONSE;
  request = create_browse_request(continuation, playlist_id, client_version,
                                  visitor_data);
  if (request == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  json = cJSON_PrintUnformatted(request);
  cJSON_Delete(request);
  if (json == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  headers[header_count++] = "Content-Type: application/json";
  headers[header_count++] = "Origin: " YT_PLAYLIST_ORIGIN;
  headers[header_count++] = "X-YouTube-Client-Name: 1";
  headers[header_count++] = client_version_header;
  headers[header_count++] = "User-Agent: " YT_PLAYLIST_USER_AGENT;
  if (visitor_data != NULL) {
    if (snprintf(visitor_header, sizeof(visitor_header),
                 "X-Goog-Visitor-Id: %s", visitor_data) >=
        (int)sizeof(visitor_header)) {
      free(json);
      return YT_ERR_INVALID_RESPONSE;
    }
    headers[header_count++] = visitor_header;
  }
  status = yt_account_append_auth_headers(
      session, account, YT_PLAYLIST_ORIGIN, headers,
      sizeof(headers) / sizeof(headers[0]), &header_count, &auth_storage);
  if (status != YT_OK) {
    yt_auth_header_storage_clear(&auth_storage);
    free(json);
    return status;
  }
  status = yt_http_session_post_json(session, endpoint, json, headers,
                                     header_count, &response);
  yt_auth_header_storage_clear(&auth_storage);
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
