#include "yt_resolver.h"

#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>

#include <curl/curl.h>

#include "cJSON.h"
#include "yt_cache.h"
#include "yt_cookies.h"
#include "yt_ejs.h"
#include "yt_http.h"

#define YT_PLAYER_ENDPOINT                                                   \
  "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
#define YT_CLIENT_NAME "MWEB"
#define YT_CLIENT_NAME_ID "2"
#define YT_CLIENT_VERSION "2.20260708.05.00"
#define YT_USER_AGENT                                                       \
  "Mozilla/5.0 (iPad; CPU OS 16_7_10 like Mac OS X) AppleWebKit/605.1.15 "  \
  "(KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1,gzip(gfe)"
#define YT_CLIENT_MANIFEST_KEY "builtin-v2"
#define YT_CLIENT_MANIFEST_TTL (30LL * 24LL * 60LL * 60LL)
#define YT_SUCCESSFUL_CLIENT_TTL (24LL * 60LL * 60LL)
#define YT_PLAYER_JAVASCRIPT_TTL (7LL * 24LL * 60LL * 60LL)

static const char builtin_client_manifest[] =
    "{\"version\":1,\"clients\":[{\"name\":\"" YT_CLIENT_NAME
    "\",\"id\":\"" YT_CLIENT_NAME_ID "\",\"version\":\""
    YT_CLIENT_VERSION "\",\"userAgent\":\"" YT_USER_AGENT "\"}]}";

const char *yt_resolver_user_agent(void) { return YT_USER_AGENT; }

typedef struct {
  char name[32];
  char id[16];
  char version[32];
  char user_agent[256];
} YTClient;

typedef struct {
  const char *url;
  const char *mime_type;
  char *owned_url;
  char *signature;
  char *signature_parameter;
  char *n_challenge;
  int itag;
  int width;
  int height;
  int fps;
  int bitrate;
  int audio_channels;
  int64_t content_length;
} YTFormatCandidate;

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

static int copy_field(char *destination, size_t capacity, const char *value) {
  size_t length;
  if (destination == NULL || capacity == 0 || value == NULL)
    return 0;
  length = strlen(value);
  if (length >= capacity)
    return 0;
  memcpy(destination, value, length + 1);
  return 1;
}

static int64_t current_time(void) {
  time_t now = time(NULL);
  return now == (time_t)-1 ? 0 : (int64_t)now;
}

static int parse_client_manifest(const char *json, size_t length,
                                 YTClient *client) {
  cJSON *document;
  cJSON *clients;
  cJSON *entry;
  cJSON *version;
  cJSON *name;
  cJSON *id;
  cJSON *client_version;
  cJSON *user_agent;
  int valid;

  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return 0;
  version = cJSON_GetObjectItemCaseSensitive(document, "version");
  clients = cJSON_GetObjectItemCaseSensitive(document, "clients");
  entry = cJSON_IsArray(clients) ? cJSON_GetArrayItem(clients, 0) : NULL;
  name = cJSON_GetObjectItemCaseSensitive(entry, "name");
  id = cJSON_GetObjectItemCaseSensitive(entry, "id");
  client_version = cJSON_GetObjectItemCaseSensitive(entry, "version");
  user_agent = cJSON_GetObjectItemCaseSensitive(entry, "userAgent");
  valid = cJSON_IsNumber(version) && version->valueint == 1 &&
          cJSON_IsString(name) && cJSON_IsString(id) &&
          cJSON_IsString(client_version) && cJSON_IsString(user_agent) &&
          copy_field(client->name, sizeof(client->name), name->valuestring) &&
          copy_field(client->id, sizeof(client->id), id->valuestring) &&
          copy_field(client->version, sizeof(client->version),
                     client_version->valuestring) &&
          copy_field(client->user_agent, sizeof(client->user_agent),
                     user_agent->valuestring);
  cJSON_Delete(document);
  return valid;
}

static YTStatus load_client(YTClient *client) {
  char *cached;
  size_t cached_length;
  int64_t now;

  if (client == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(client, 0, sizeof(*client));
  cached = NULL;
  cached_length = 0;
  now = current_time();
  if (yt_cache_get(YT_CACHE_CLIENT_MANIFEST, YT_CLIENT_MANIFEST_KEY, now,
                   &cached, &cached_length) == YT_CACHE_OK) {
    if (parse_client_manifest(cached, cached_length, client)) {
      free(cached);
      return YT_OK;
    }
    free(cached);
    yt_cache_remove(YT_CACHE_CLIENT_MANIFEST, YT_CLIENT_MANIFEST_KEY);
  }
  if (!parse_client_manifest(builtin_client_manifest,
                             sizeof(builtin_client_manifest) - 1, client))
    return YT_ERR_INVALID_RESPONSE;
  yt_cache_put(YT_CACHE_CLIENT_MANIFEST, YT_CLIENT_MANIFEST_KEY,
               builtin_client_manifest, sizeof(builtin_client_manifest) - 1,
               now == 0 ? 0 : now + YT_CLIENT_MANIFEST_TTL);
  return YT_OK;
}

static const char *successful_client_key(int authenticated) {
  return authenticated ? "last-authenticated" : "last-anonymous";
}

static void prefer_recent_client(YTClient *client, int authenticated) {
  char *cached;
  size_t length;
  const char *key = successful_client_key(authenticated);
  cached = NULL;
  length = 0;
  if (yt_cache_get(YT_CACHE_SUCCESSFUL_CLIENT, key, current_time(), &cached,
                   &length) == YT_CACHE_OK) {
    /* There is currently one client. Validate the cache now so adding more
     * clients later cannot select an unknown or stale definition. */
    if (length != strlen(client->name) ||
        memcmp(cached, client->name, length) != 0)
      yt_cache_remove(YT_CACHE_SUCCESSFUL_CLIENT, key);
    free(cached);
  }
}

static void remember_successful_client(const YTClient *client,
                                       int authenticated) {
  int64_t now = current_time();
  yt_cache_put(YT_CACHE_SUCCESSFUL_CLIENT,
               successful_client_key(authenticated), client->name,
               strlen(client->name),
               now == 0 ? 0 : now + YT_SUCCESSFUL_CLIENT_TTL);
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

static void failure_cache_key(const char *video_id, const YTClient *client,
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

int yt_load_cached_failure(const char *key, YTStatus *status) {
  char *value;
  size_t length;
  char *end;
  long parsed;
  value = NULL;
  length = 0;
  if (key == NULL || status == NULL || key[0] == '\0' ||
      yt_cache_get(YT_CACHE_FAILURE, key, current_time(), &value, &length) !=
          YT_CACHE_OK)
    return 0;
  parsed = strtol(value, &end, 10);
  if (end != value + length || parsed <= YT_OK ||
      parsed > YT_ERR_AUTH_COOKIES_INVALID ||
      yt_failure_cache_ttl((YTStatus)parsed) == 0) {
    free(value);
    yt_cache_remove(YT_CACHE_FAILURE, key);
    return 0;
  }
  free(value);
  *status = (YTStatus)parsed;
  return 1;
}

void yt_remember_failure(const char *key, YTStatus status) {
  char value[16];
  int length;
  int ttl = yt_failure_cache_ttl(status);
  int64_t now;
  if (key == NULL || key[0] == '\0' || ttl == 0)
    return;
  length = snprintf(value, sizeof(value), "%d", (int)status);
  now = current_time();
  if (length > 0 && length < (int)sizeof(value))
    yt_cache_put(YT_CACHE_FAILURE, key, value, (size_t)length,
                 now == 0 ? 0 : now + ttl);
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
  if (strncmp(path, "/v/", 3) == 0 && copy_candidate(path + 3, video_id))
    return YT_OK;
  if (copy_query_video_id(strchr(path, '?'), video_id))
    return YT_OK;
  return YT_ERR_INVALID_VIDEO_ID;
}

static cJSON *create_player_request(const char *video_id,
                                    const char *visitor_data,
                                    const YTClient *configured_client,
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

static YTStatus call_player(YTHttpSession *session,
                            const YTAccountContext *account,
                            const char *video_id, const char *visitor_data,
                            const YTClient *client, int signature_timestamp,
                            cJSON **document_out) {
  static const char *const fixed_headers[] = {
      "Content-Type: application/json", "Origin: https://www.youtube.com"};
  char client_name_header[64];
  char client_version_header[96];
  char user_agent_header[320];
  char visitor_header[1024];
  char authorization_value[1024];
  char authorization_header[1100];
  char auth_user_header[64];
  char page_id_header[1024];
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

  if (account != NULL && account->authenticated) {
    status = yt_auth_cookies_make_authorization(
        &account->cookies, "https://www.youtube.com",
        account->user_session_id, current_time(), authorization_value,
        sizeof(authorization_value));
    if (status != YT_OK ||
        snprintf(authorization_header, sizeof(authorization_header),
                 "Authorization: %s", authorization_value) >=
            (int)sizeof(authorization_header)) {
      free(json);
      memset(authorization_value, 0, sizeof(authorization_value));
      return status == YT_OK ? YT_ERR_INVALID_RESPONSE : status;
    }
    headers[header_count++] = authorization_header;
    headers[header_count++] = "X-Origin: https://www.youtube.com";
    if (account->has_session_index || account->delegated_session_id != NULL) {
      if (snprintf(auth_user_header, sizeof(auth_user_header),
                   "X-Goog-AuthUser: %d",
                   account->has_session_index ? account->session_index : 0) >=
          (int)sizeof(auth_user_header)) {
        free(json);
        memset(authorization_value, 0, sizeof(authorization_value));
        return YT_ERR_INVALID_RESPONSE;
      }
      headers[header_count++] = auth_user_header;
    }
    if (account->delegated_session_id != NULL) {
      if (snprintf(page_id_header, sizeof(page_id_header),
                   "X-Goog-PageId: %s", account->delegated_session_id) >=
          (int)sizeof(page_id_header)) {
        free(json);
        memset(authorization_value, 0, sizeof(authorization_value));
        return YT_ERR_INVALID_RESPONSE;
      }
      headers[header_count++] = page_id_header;
    }
    if (account->logged_in)
      headers[header_count++] = "X-Youtube-Bootstrap-Logged-In: true";
  }

  status = yt_http_session_post_json(session, YT_PLAYER_ENDPOINT, json,
                                     headers, header_count, &response);
  memset(authorization_value, 0, sizeof(authorization_value));
  memset(authorization_header, 0, sizeof(authorization_header));
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

static int hexadecimal_value(char value) {
  if (value >= '0' && value <= '9')
    return value - '0';
  if (value >= 'a' && value <= 'f')
    return value - 'a' + 10;
  if (value >= 'A' && value <= 'F')
    return value - 'A' + 10;
  return -1;
}

static char *percent_decode(const char *value, size_t length) {
  char *decoded;
  size_t source;
  size_t destination;
  decoded = (char *)malloc(length + 1);
  if (decoded == NULL)
    return NULL;
  destination = 0;
  for (source = 0; source < length; ++source) {
    if (value[source] == '%' && source + 2 < length) {
      int high = hexadecimal_value(value[source + 1]);
      int low = hexadecimal_value(value[source + 2]);
      if (high >= 0 && low >= 0) {
        decoded[destination++] = (char)((high << 4) | low);
        source += 2;
        continue;
      }
    }
    decoded[destination++] = value[source] == '+' ? ' ' : value[source];
  }
  decoded[destination] = '\0';
  return decoded;
}

static char *query_value(const char *query, const char *name) {
  size_t name_length;
  const char *cursor;
  const char *end;
  name_length = strlen(name);
  cursor = query;
  while (cursor != NULL && *cursor != '\0') {
    if (strncmp(cursor, name, name_length) == 0 && cursor[name_length] == '=') {
      cursor += name_length + 1;
      end = strchr(cursor, '&');
      if (end == NULL)
        end = cursor + strlen(cursor);
      return percent_decode(cursor, (size_t)(end - cursor));
    }
    cursor = strchr(cursor, '&');
    if (cursor != NULL)
      ++cursor;
  }
  return NULL;
}

static int query_safe_character(unsigned char value) {
  return isalnum(value) || value == '-' || value == '_' || value == '.' ||
         value == '~';
}

static char *percent_encode(const char *value) {
  static const char digits[] = "0123456789ABCDEF";
  size_t length;
  size_t index;
  size_t output_length;
  char *encoded;
  char *cursor;
  length = strlen(value);
  output_length = 0;
  for (index = 0; index < length; ++index)
    output_length += query_safe_character((unsigned char)value[index]) ? 1 : 3;
  encoded = (char *)malloc(output_length + 1);
  if (encoded == NULL)
    return NULL;
  cursor = encoded;
  for (index = 0; index < length; ++index) {
    unsigned char character = (unsigned char)value[index];
    if (query_safe_character(character)) {
      *cursor++ = (char)character;
    } else {
      *cursor++ = '%';
      *cursor++ = digits[character >> 4];
      *cursor++ = digits[character & 15];
    }
  }
  *cursor = '\0';
  return encoded;
}

static char *set_query_parameter(const char *url, const char *name,
                                 const char *value) {
  const char *query;
  const char *cursor;
  const char *parameter_start;
  const char *parameter_end;
  size_t name_length;
  char *encoded;
  char *result;
  size_t prefix_length;
  size_t suffix_length;
  size_t result_length;

  encoded = percent_encode(value);
  if (encoded == NULL)
    return NULL;
  query = strchr(url, '?');
  cursor = query == NULL ? NULL : query + 1;
  parameter_start = NULL;
  parameter_end = NULL;
  name_length = strlen(name);
  while (cursor != NULL && *cursor != '\0') {
    const char *end = strchr(cursor, '&');
    if (end == NULL)
      end = cursor + strlen(cursor);
    if ((size_t)(end - cursor) > name_length &&
        strncmp(cursor, name, name_length) == 0 && cursor[name_length] == '=') {
      parameter_start = cursor;
      parameter_end = end;
      break;
    }
    cursor = *end == '&' ? end + 1 : NULL;
  }
  if (parameter_start != NULL) {
    prefix_length = (size_t)(parameter_start - url) + name_length + 1;
    suffix_length = strlen(parameter_end);
    result_length = prefix_length + strlen(encoded) + suffix_length;
    result = (char *)malloc(result_length + 1);
    if (result != NULL) {
      memcpy(result, url, prefix_length);
      memcpy(result + prefix_length, encoded, strlen(encoded));
      memcpy(result + prefix_length + strlen(encoded), parameter_end,
             suffix_length + 1);
    }
  } else {
    prefix_length = strlen(url);
    result_length = prefix_length + 1 + name_length + 1 + strlen(encoded);
    result = (char *)malloc(result_length + 1);
    if (result != NULL)
      snprintf(result, result_length + 1, "%s%c%s=%s", url,
               query == NULL ? '?' : '&', name, encoded);
  }
  free(encoded);
  return result;
}

static void format_candidate_free(YTFormatCandidate *candidate) {
  free(candidate->owned_url);
  free(candidate->signature);
  free(candidate->signature_parameter);
  free(candidate->n_challenge);
  memset(candidate, 0, sizeof(*candidate));
}

static int candidate_is_better(const YTFormatCandidate *current,
                               const YTFormatCandidate *candidate) {
  int current_is_direct;
  int candidate_is_direct;
  if (candidate->url == NULL || current->height > candidate->height)
    return 1;
  if (current->height != candidate->height)
    return 0;
  current_is_direct = current->signature == NULL &&
                      current->n_challenge == NULL;
  candidate_is_direct = candidate->signature == NULL &&
                        candidate->n_challenge == NULL;
  return current_is_direct && !candidate_is_direct;
}

static int read_format_candidate(cJSON *format, YTFormatCandidate *candidate) {
  const char *cipher;
  const char *url;
  const char *content_length;

  memset(candidate, 0, sizeof(*candidate));
  candidate->itag = json_integer(format, "itag");
  candidate->mime_type = json_string(format, "mimeType");
  if (candidate->itag <= 0 || candidate->mime_type == NULL)
    return 0;
  url = json_string(format, "url");
  cipher = json_string(format, "signatureCipher");
  candidate->signature = query_value(cipher, "s");
  candidate->signature_parameter = query_value(cipher, "sp");
  candidate->owned_url = query_value(cipher, "url");
  if (cipher != NULL && candidate->signature == NULL) {
    format_candidate_free(candidate);
    return 0;
  }
  if (candidate->owned_url != NULL)
    url = candidate->owned_url;
  if (url == NULL) {
    format_candidate_free(candidate);
    return 0;
  }
  candidate->n_challenge = query_value(
      strchr(url, '?') == NULL ? "" : strchr(url, '?') + 1, "n");
  candidate->url = url;
  candidate->width = json_integer(format, "width");
  candidate->height = json_integer(format, "height");
  candidate->fps = json_integer(format, "fps");
  candidate->bitrate = json_integer(format, "bitrate");
  candidate->audio_channels = json_integer(format, "audioChannels");
  content_length = json_string(format, "contentLength");
  candidate->content_length = parse_decimal(content_length);
  return 1;
}

static YTStatus inspect_progressive_mp4(cJSON *document, int max_height,
                                        YTFormatCandidate *candidate) {
  cJSON *streaming_data;
  cJSON *formats;
  cJSON *format;
  YTFormatCandidate current;

  if (max_height <= 0)
    return YT_ERR_INVALID_RESPONSE;
  memset(candidate, 0, sizeof(*candidate));
  streaming_data = cJSON_GetObjectItemCaseSensitive(document, "streamingData");
  formats = cJSON_GetObjectItemCaseSensitive(streaming_data, "formats");
  if (!cJSON_IsArray(formats))
    return YT_ERR_NO_PROGRESSIVE_MP4;

  cJSON_ArrayForEach(format, formats) {
    if (!read_format_candidate(format, &current) ||
        strncmp(current.mime_type, "video/mp4", 9) != 0) {
      format_candidate_free(&current);
      continue;
    }
    if (current.height <= 0 || current.height > max_height) {
      format_candidate_free(&current);
      continue;
    }
    if (candidate_is_better(&current, candidate)) {
      format_candidate_free(candidate);
      *candidate = current;
    } else {
      format_candidate_free(&current);
    }
  }
  return candidate->url == NULL ? YT_ERR_NO_PROGRESSIVE_MP4 : YT_OK;
}

static int mime_has_codec(const char *mime_type, const char *codec) {
  const char *codecs;
  if (mime_type == NULL || codec == NULL)
    return 0;
  codecs = strstr(mime_type, "codecs=\"");
  return codecs != NULL && strstr(codecs + 8, codec) != NULL;
}

static int adaptive_video_is_better(const YTFormatCandidate *candidate,
                                    const YTFormatCandidate *selected) {
  if (selected->url == NULL || candidate->height != selected->height)
    return selected->url == NULL || candidate->height > selected->height;
  if (candidate->width != selected->width)
    return candidate->width > selected->width;
  return candidate->bitrate > selected->bitrate;
}

static int adaptive_audio_is_better(const YTFormatCandidate *candidate,
                                    const YTFormatCandidate *selected) {
  return selected->url == NULL || candidate->bitrate > selected->bitrate;
}

static YTStatus inspect_adaptive_mp4(cJSON *document, int max_height,
                                     YTFormatCandidate *video,
                                     YTFormatCandidate *audio) {
  cJSON *streaming_data;
  cJSON *formats;
  cJSON *format;
  YTFormatCandidate current;

  if (max_height != 720 && max_height != 1080)
    return YT_ERR_INVALID_RESPONSE;
  memset(video, 0, sizeof(*video));
  memset(audio, 0, sizeof(*audio));
  streaming_data = cJSON_GetObjectItemCaseSensitive(document, "streamingData");
  formats = cJSON_GetObjectItemCaseSensitive(streaming_data, "adaptiveFormats");
  if (!cJSON_IsArray(formats))
    return YT_ERR_NO_PROGRESSIVE_MP4;

  cJSON_ArrayForEach(format, formats) {
    if (!read_format_candidate(format, &current))
      continue;
    if (strncmp(current.mime_type, "video/mp4", 9) == 0 &&
        mime_has_codec(current.mime_type, "avc1.") && current.height > 0 &&
        current.height <= max_height && current.fps <= 30) {
      if (adaptive_video_is_better(&current, video)) {
        format_candidate_free(video);
        *video = current;
      } else {
        format_candidate_free(&current);
      }
    } else if (strncmp(current.mime_type, "audio/mp4", 9) == 0 &&
               mime_has_codec(current.mime_type, "mp4a.40.2") &&
               current.audio_channels <= 2) {
      if (adaptive_audio_is_better(&current, audio)) {
        format_candidate_free(audio);
        *audio = current;
      } else {
        format_candidate_free(&current);
      }
    } else {
      format_candidate_free(&current);
    }
  }
  if (video->url != NULL && audio->url != NULL)
    return YT_OK;
  format_candidate_free(video);
  format_candidate_free(audio);
  return YT_ERR_NO_PROGRESSIVE_MP4;
}

static YTStatus finish_candidate(const YTFormatCandidate *candidate,
                                 const char *url, const YTClient *client,
                                 YTMediaRequest *result) {
  result->url = copy_string(url);
  result->mime_type = copy_string(candidate->mime_type);
  result->user_agent = copy_string(client == NULL ? YT_USER_AGENT :
                                                    client->user_agent);
  if (result->url == NULL || result->mime_type == NULL ||
      result->user_agent == NULL) {
    yt_media_request_free(result);
    return YT_ERR_OUT_OF_MEMORY;
  }
  result->itag = candidate->itag;
  result->width = candidate->width;
  result->height = candidate->height;
  result->expires_unix = url_query_integer(url, "expire");
  result->content_length = candidate->content_length;
  return YT_OK;
}

static YTStatus solve_candidates(YTFormatCandidate *candidates,
                                 size_t candidate_count,
                                 const char *player_source,
                                 const YTClient *client,
                                 YTMediaRequest *results) {
  const char *signature_challenges[2];
  const char *n_challenges[2];
  size_t signature_solutions[2];
  size_t n_solutions[2];
  YTEJSRequest requests[2];
  size_t request_count;
  size_t signature_index;
  size_t n_index;
  size_t signature_count;
  size_t n_count;
  size_t index;
  YTEJSResult solved;
  YTEJSStatus ejs_status;
  YTStatus status;

  if (candidate_count == 0 || candidate_count > 2)
    return YT_ERR_INVALID_RESPONSE;
  signature_count = 0;
  n_count = 0;
  for (index = 0; index < candidate_count; ++index) {
    memset(&results[index], 0, sizeof(results[index]));
    signature_solutions[index] = (size_t)-1;
    n_solutions[index] = (size_t)-1;
    if (candidates[index].signature != NULL) {
      signature_solutions[index] = signature_count;
      signature_challenges[signature_count++] = candidates[index].signature;
    }
    if (candidates[index].n_challenge != NULL) {
      n_solutions[index] = n_count;
      n_challenges[n_count++] = candidates[index].n_challenge;
    }
  }
  if (signature_count == 0 && n_count == 0) {
    for (index = 0; index < candidate_count; ++index) {
      status = finish_candidate(&candidates[index], candidates[index].url,
                                client, &results[index]);
      if (status != YT_OK)
        goto failed_results;
    }
    return YT_OK;
  }
  if (player_source == NULL)
    return YT_ERR_JS_CHALLENGE;
  request_count = 0;
  signature_index = (size_t)-1;
  n_index = (size_t)-1;
  if (signature_count != 0) {
    signature_index = request_count;
    requests[request_count].type = YT_EJS_CHALLENGE_SIGNATURE;
    requests[request_count].challenges = signature_challenges;
    requests[request_count].challenge_count = signature_count;
    ++request_count;
  }
  if (n_count != 0) {
    n_index = request_count;
    requests[request_count].type = YT_EJS_CHALLENGE_N;
    requests[request_count].challenges = n_challenges;
    requests[request_count].challenge_count = n_count;
    ++request_count;
  }
  ejs_status = yt_ejs_solve(YT_EJS_SOURCE_PLAYER, player_source, requests,
                            request_count, NULL, &solved);
  if (ejs_status == YT_EJS_ERR_ASSETS_MISSING)
    return YT_ERR_EJS_ASSETS_MISSING;
  if (ejs_status == YT_EJS_ERR_OUT_OF_MEMORY)
    return YT_ERR_OUT_OF_MEMORY;
  if (ejs_status != YT_EJS_OK)
    return YT_ERR_JS_CHALLENGE;
  status = YT_OK;
  if (solved.responses == NULL || solved.response_count != request_count ||
      (signature_index != (size_t)-1 &&
       (solved.responses[signature_index].error != NULL ||
        solved.responses[signature_index].solution_count != signature_count)) ||
      (n_index != (size_t)-1 &&
       (solved.responses[n_index].error != NULL ||
        solved.responses[n_index].solution_count != n_count)))
    status = YT_ERR_JS_CHALLENGE;
  for (index = 0; status == YT_OK && index < candidate_count; ++index) {
    YTFormatCandidate *candidate = &candidates[index];
    char *url = copy_string(candidate->url);
    char *updated;
    char *remaining_n;
    if (url == NULL) {
      status = YT_ERR_OUT_OF_MEMORY;
      break;
    }
    if (signature_solutions[index] != (size_t)-1) {
      updated = set_query_parameter(
          url,
          candidate->signature_parameter == NULL ||
                  candidate->signature_parameter[0] == '\0'
              ? "signature"
              : candidate->signature_parameter,
          solved.responses[signature_index]
              .solutions[signature_solutions[index]]);
      free(url);
      url = updated;
    }
    if (url != NULL && n_solutions[index] != (size_t)-1) {
      updated = set_query_parameter(
          url, "n", solved.responses[n_index].solutions[n_solutions[index]]);
      free(url);
      url = updated;
    }
    if (url == NULL) {
      status = YT_ERR_OUT_OF_MEMORY;
      break;
    }
    remaining_n = query_value(
        strchr(url, '?') == NULL ? "" : strchr(url, '?') + 1, "n");
    if (url_has_query_parameter(url, "s") ||
        (candidate->n_challenge != NULL && remaining_n != NULL &&
         strcmp(remaining_n, candidate->n_challenge) == 0))
      status = YT_ERR_JS_CHALLENGE;
    free(remaining_n);
    if (status == YT_OK)
      status = finish_candidate(candidate, url, client, &results[index]);
    free(url);
  }
  yt_ejs_result_free(&solved);
  if (status != YT_OK)
    goto failed_results;
  return status;

failed_results:
  for (index = 0; index < candidate_count; ++index)
    yt_media_request_free(&results[index]);
  return status;
}

static YTStatus solve_candidate(YTFormatCandidate *candidate,
                                const char *player_source,
                                const YTClient *client,
                                YTMediaRequest *result) {
  return solve_candidates(candidate, 1, player_source, client, result);
}

static YTStatus parse_player_document(cJSON *document, const char *player_source,
                                      const YTClient *client, int max_height,
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
  {
    YTFormatCandidate candidate;
    YTStatus status = inspect_progressive_mp4(document, max_height, &candidate);
    if (status != YT_OK)
      return status;
    status = solve_candidate(&candidate, player_source, client, result);
    format_candidate_free(&candidate);
    return status;
  }
}

static YTStatus parse_player_selection_document(
    cJSON *document, const char *player_source, const YTClient *client,
    int max_height, int try_adaptive, YTMediaSelection *result) {
  cJSON *playability;
  const char *playability_status;
  YTStatus status;

  if (document == NULL || result == NULL ||
      (try_adaptive && max_height != 720 && max_height != 1080))
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  playability = cJSON_GetObjectItemCaseSensitive(document,
                                                 "playabilityStatus");
  playability_status = json_string(playability, "status");
  if (playability_status == NULL || strcmp(playability_status, "OK") != 0)
    return YT_ERR_UNAVAILABLE;

  if (try_adaptive) {
    YTFormatCandidate candidates[2];
    YTMediaRequest solved[2];
    status = inspect_adaptive_mp4(document, max_height, &candidates[0],
                                  &candidates[1]);
    if (status == YT_OK) {
      memset(solved, 0, sizeof(solved));
      status = solve_candidates(candidates, 2, player_source, client, solved);
      format_candidate_free(&candidates[0]);
      format_candidate_free(&candidates[1]);
      if (status == YT_OK) {
        result->video = solved[0];
        result->audio = solved[1];
        result->adaptive = 1;
        return YT_OK;
      }
      if (status == YT_ERR_JS_CHALLENGE && player_source == NULL)
        return status;
      if (status == YT_ERR_OUT_OF_MEMORY)
        return status;
    }
  }

  status = parse_player_document(document, player_source, client, max_height,
                                 &result->video);
  return status;
}

YTStatus yt_parse_player_response(const char *json, size_t length,
                                  YTMediaRequest *result) {
  return yt_parse_player_response_with_max_height(
      json, length, YT_DEFAULT_MAX_HEIGHT, result);
}

YTStatus yt_parse_player_response_with_max_height(const char *json,
                                                  size_t length,
                                                  int max_height,
                                                  YTMediaRequest *result) {
  cJSON *document;
  YTStatus status;

  if (json == NULL || result == NULL || max_height <= 0)
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  status = parse_player_document(document, NULL, NULL, max_height, result);
  if (status == YT_ERR_JS_CHALLENGE)
    status = YT_ERR_NO_PROGRESSIVE_MP4;
  cJSON_Delete(document);
  return status;
}

YTStatus yt_parse_player_response_with_adaptive_size(
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
  status = parse_player_selection_document(document, NULL, NULL, max_height,
                                           1, result);
  if (status == YT_ERR_JS_CHALLENGE)
    status = YT_ERR_NO_PROGRESSIVE_MP4;
  cJSON_Delete(document);
  return status;
}

YTStatus yt_parse_player_response_with_javascript(const char *json,
                                                  size_t length,
                                                  const char *player_source,
                                                  YTMediaRequest *result) {
  cJSON *document;
  YTStatus status;
  if (json == NULL || player_source == NULL || result == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  status = parse_player_document(document, player_source, NULL,
                                 YT_DEFAULT_MAX_HEIGHT, result);
  cJSON_Delete(document);
  return status;
}

static char *absolute_player_url(const char *value) {
  static const char origin[] = "https://www.youtube.com";
  char *result;
  if (value == NULL)
    return NULL;
  if (strncmp(value, "/s/player/", 10) == 0) {
    result = (char *)malloc(sizeof(origin) - 1 + strlen(value) + 1);
    if (result != NULL)
      sprintf(result, "%s%s", origin, value);
    return result;
  }
  if (strncmp(value, "https://www.youtube.com/s/player/", 33) == 0)
    return copy_string(value);
  return NULL;
}

static char *player_url_from_document(cJSON *document) {
  cJSON *assets = cJSON_GetObjectItemCaseSensitive(document, "assets");
  return absolute_player_url(json_string(assets, "js"));
}

static char *json_string_after_marker(const char *text, const char *marker) {
  const char *start;
  const char *cursor;
  cJSON *value;
  char *result;
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
  result = copy_string(value->valuestring);
  cJSON_Delete(value);
  return result;
}

static int json_integer_after_marker(const char *text, const char *marker) {
  const char *start;
  char *end;
  long value;
  start = strstr(text, marker);
  if (start == NULL)
    return 0;
  start += strlen(marker);
  while (*start == ' ' || *start == '\t' || *start == ':')
    ++start;
  value = strtol(start, &end, 10);
  return end != start && value > 0 && value <= INT_MAX ? (int)value : 0;
}

static int json_nonnegative_integer_after_marker(const char *text,
                                                 const char *marker,
                                                 int *found) {
  const char *start;
  char *end;
  long value;
  *found = 0;
  start = strstr(text, marker);
  if (start == NULL)
    return 0;
  start += strlen(marker);
  while (*start == ' ' || *start == '\t' || *start == ':')
    ++start;
  value = strtol(start, &end, 10);
  if (end == start || value < 0 || value > INT_MAX)
    return 0;
  *found = 1;
  return (int)value;
}

static int json_true_after_marker(const char *text, const char *marker) {
  const char *start = strstr(text, marker);
  if (start == NULL)
    return 0;
  start += strlen(marker);
  while (*start == ' ' || *start == '\t' || *start == ':')
    ++start;
  return strncmp(start, "true", 4) == 0;
}

static void account_context_free(YTAccountContext *account) {
  if (account == NULL)
    return;
  yt_auth_cookies_free(&account->cookies);
  free(account->data_sync_id);
  free(account->delegated_session_id);
  free(account->user_session_id);
  memset(account, 0, sizeof(*account));
}

static int account_context_load_page(YTAccountContext *account,
                                     const char *page) {
  char *data_sync_id;
  char *delegated_session_id;
  char *user_session_id;
  int has_session_index;

  if (account == NULL || page == NULL)
    return 0;
  account->logged_in = json_true_after_marker(page, "\"LOGGED_IN\"");
  account->session_index = json_nonnegative_integer_after_marker(
      page, "\"SESSION_INDEX\"", &has_session_index);
  account->has_session_index = has_session_index;
  data_sync_id = json_string_after_marker(page, "\"DATASYNC_ID\"");
  delegated_session_id =
      json_string_after_marker(page, "\"DELEGATED_SESSION_ID\"");
  user_session_id =
      json_string_after_marker(page, "\"USER_SESSION_ID\"");
  if (data_sync_id != NULL && user_session_id == NULL) {
    char *separator = strstr(data_sync_id, "||");
    if (separator != NULL) {
      if (separator[2] != '\0') {
        user_session_id = copy_string(separator + 2);
        if (separator != data_sync_id && delegated_session_id == NULL) {
          *separator = '\0';
          delegated_session_id = copy_string(data_sync_id);
          *separator = '|';
        }
      } else {
        *separator = '\0';
        user_session_id = copy_string(data_sync_id);
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
  return 1;
}

static YTStatus load_mweb_bootstrap(YTHttpSession *session,
                                    YTAccountContext *account,
                                    const char *video_id, YTClient *client,
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
  status = yt_http_session_get(session, watch_url, 2U * 1024U * 1024U,
                               &response);
  if (status != YT_OK)
    return status;
  if (response.status < 200 || response.status >= 300) {
    yt_http_response_free(&response);
    return YT_ERR_HTTP;
  }

  client_version = json_string_after_marker(
      response.data, "\"INNERTUBE_CONTEXT_CLIENT_VERSION\"");
  *signature_timestamp =
      json_integer_after_marker(response.data, "\"STS\"");
  relative_player_url = json_string_after_marker(response.data, "\"jsUrl\"");
  if (relative_player_url == NULL)
    relative_player_url =
        json_string_after_marker(response.data, "\"PLAYER_JS_URL\"");
  *player_url = absolute_player_url(relative_player_url);
  free(relative_player_url);

  if (account != NULL && account->authenticated &&
      !account_context_load_page(account, response.data)) {
    free(client_version);
    free(*player_url);
    *player_url = NULL;
    yt_http_response_free(&response);
    return YT_ERR_OUT_OF_MEMORY;
  }

  if (client_version == NULL ||
      !copy_field(client->version, sizeof(client->version), client_version) ||
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

static YTStatus player_url_from_watch_page(YTHttpSession *session,
                                           const char *video_id,
                                           char **player_url) {
  char watch_url[96];
  YTHttpResponse response;
  YTStatus status;
  char *relative;
  if (snprintf(watch_url, sizeof(watch_url),
               "https://www.youtube.com/watch?v=%s", video_id) >=
      (int)sizeof(watch_url))
    return YT_ERR_INVALID_RESPONSE;
  status = yt_http_session_get(session, watch_url, 2U * 1024U * 1024U,
                               &response);
  if (status != YT_OK)
    return status;
  if (response.status < 200 || response.status >= 300) {
    yt_http_response_free(&response);
    return YT_ERR_HTTP;
  }
  relative = json_string_after_marker(response.data, "\"jsUrl\"");
  if (relative == NULL)
    relative = json_string_after_marker(response.data, "\"PLAYER_JS_URL\"");
  *player_url = absolute_player_url(relative);
  free(relative);
  yt_http_response_free(&response);
  return *player_url == NULL ? YT_ERR_JS_CHALLENGE : YT_OK;
}

static YTStatus load_player_javascript(YTHttpSession *session,
                                       const char *player_url,
                                       char **source) {
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
  now = current_time();
  if (yt_cache_get(YT_CACHE_PLAYER_JAVASCRIPT, key, now, &cached,
                   &cached_length) == YT_CACHE_OK) {
    if (cached_length != 0) {
      *source = cached;
      return YT_OK;
    }
    free(cached);
    yt_cache_remove(YT_CACHE_PLAYER_JAVASCRIPT, key);
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
  yt_cache_put(YT_CACHE_PLAYER_JAVASCRIPT, key, response.data, response.length,
               now == 0 ? 0 : now + YT_PLAYER_JAVASCRIPT_TTL);
  *source = response.data;
  response.data = NULL;
  yt_http_response_free(&response);
  return YT_OK;
}

YTStatus yt_load_player_javascript(const char *player_url, char **source) {
  return load_player_javascript(NULL, player_url, source);
}

static void report_progress(YTProgressCallback progress, void *opaque,
                            const char *message) {
  if (progress != NULL)
    progress(message, opaque);
}

static YTStatus resolve_player_selection_document(
    YTHttpSession *session, cJSON *document, const char *video_id,
    const char *bootstrap_player_url, const YTClient *client, int max_height,
    int try_adaptive, YTMediaSelection *result, YTProgressCallback progress,
    void *progress_opaque) {
  YTStatus status;
  char *player_url;
  char *player_source;

  status = parse_player_selection_document(document, NULL, client, max_height,
                                           try_adaptive, result);
  if (status != YT_ERR_JS_CHALLENGE)
    return status;
  player_url = player_url_from_document(document);
  if (player_url == NULL)
    player_url = copy_string(bootstrap_player_url);
  if (player_url == NULL) {
    report_progress(progress, progress_opaque,
                    "fetching fallback player information");
    status = player_url_from_watch_page(session, video_id, &player_url);
    if (status != YT_OK)
      return status;
  }
  player_source = NULL;
  report_progress(progress, progress_opaque,
                  "loading player JavaScript for URL challenges");
  status = load_player_javascript(session, player_url, &player_source);
  free(player_url);
  if (status != YT_OK)
    return status;
  report_progress(progress, progress_opaque, "solving media URL challenges");
  status = parse_player_selection_document(document, player_source, client,
                                           max_height, try_adaptive, result);
  free(player_source);
  return status;
}

static YTStatus resolve_video(YTHttpSession *provided_session,
                              const char *input, const char *cookie_file,
                              int max_height, int try_adaptive,
                              YTMediaSelection *result,
                              YTProgressCallback progress,
                              void *progress_opaque) {
  char video_id[12];
  char failure_key[65];
  YTClient client;
  cJSON *document;
  cJSON *response_context;
  const char *visitor_data;
  char *visitor_copy;
  char *bootstrap_player_url;
  int signature_timestamp;
  YTStatus status;
  YTHttpSession *session;
  YTAccountContext account;
  int owns_session;

  if (result == NULL || max_height <= 0 ||
      (try_adaptive && max_height != 720 && max_height != 1080))
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  memset(&account, 0, sizeof(account));
  session = provided_session;
  owns_session = provided_session == NULL;
  document = NULL;
  bootstrap_player_url = NULL;
  status = yt_extract_video_id(input, video_id);
  if (status != YT_OK)
    return status;
  if (cookie_file != NULL) {
    status = yt_auth_cookies_load(cookie_file, current_time(),
                                  &account.cookies);
    if (status != YT_OK)
      return status;
    account.authenticated = 1;
    report_progress(progress, progress_opaque,
                    "using authenticated YouTube cookies");
  }
  if (owns_session) {
    status = yt_http_session_create(cookie_file, &session);
    if (status != YT_OK)
      goto finished;
  }
  report_progress(progress, progress_opaque, "loading client configuration");
  status = load_client(&client);
  if (status != YT_OK)
    goto finished;
  signature_timestamp = 0;
  report_progress(progress, progress_opaque,
                  "fetching web player configuration");
  status = load_mweb_bootstrap(session, &account, video_id, &client,
                               &signature_timestamp, &bootstrap_player_url);
  if (status != YT_OK)
    goto finished;
  prefer_recent_client(&client, account.authenticated);
  failure_cache_key(video_id, &client, account.authenticated, max_height,
                    try_adaptive, failure_key);
  if (yt_load_cached_failure(failure_key, &status))
    goto finished;

  report_progress(progress, progress_opaque, "requesting video metadata");
  status = call_player(session, &account, video_id, NULL, &client,
                       signature_timestamp, &document);
  if (status != YT_OK) {
    yt_remember_failure(failure_key, status);
    goto finished;
  }

  response_context = cJSON_GetObjectItemCaseSensitive(document,
                                                       "responseContext");
  visitor_data = json_string(response_context, "visitorData");
  visitor_copy = copy_string(visitor_data);
  if (visitor_data != NULL && visitor_copy == NULL) {
    status = YT_ERR_OUT_OF_MEMORY;
    goto finished;
  }

  if (visitor_copy != NULL) {
    cJSON_Delete(document);
    document = NULL;
    report_progress(progress, progress_opaque,
                    "refreshing video metadata with visitor data");
    status = call_player(session, &account, video_id, visitor_copy, &client,
                         signature_timestamp, &document);
    free(visitor_copy);
    if (status != YT_OK) {
      yt_remember_failure(failure_key, status);
      goto finished;
    }
  }

  report_progress(progress, progress_opaque,
                  try_adaptive ? "selecting adaptive H.264 and AAC streams"
                               : "selecting a progressive MP4 stream");
  status = resolve_player_selection_document(
      session, document, video_id, bootstrap_player_url, &client, max_height,
      try_adaptive, result, progress, progress_opaque);
  if (status == YT_OK) {
    remember_successful_client(&client, account.authenticated);
    yt_cache_remove(YT_CACHE_FAILURE, failure_key);
  } else {
    yt_remember_failure(failure_key, status);
  }

finished:
  cJSON_Delete(document);
  free(bootstrap_player_url);
  if (owns_session)
    yt_http_session_destroy(session);
  account_context_free(&account);
  return status;
}

YTStatus yt_resolve_video_with_progress(const char *input,
                                        YTMediaRequest *result,
                                        YTProgressCallback progress,
                                        void *progress_opaque) {
  YTMediaSelection selection;
  if (result == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(&selection, 0, sizeof(selection));
  YTStatus status = resolve_video(NULL, input, NULL, YT_DEFAULT_MAX_HEIGHT, 0,
                                  &selection, progress, progress_opaque);
  if (status == YT_OK) {
    *result = selection.video;
    memset(&selection.video, 0, sizeof(selection.video));
  }
  yt_media_selection_free(&selection);
  return status;
}

YTStatus yt_resolve_video_with_cookies_and_progress(
    const char *input, const char *cookie_file, YTMediaRequest *result,
    YTProgressCallback progress, void *progress_opaque) {
  if (cookie_file == NULL || cookie_file[0] == '\0')
    return YT_ERR_COOKIE_FILE;
  {
    YTMediaSelection selection;
    YTStatus status;
    if (result == NULL)
      return YT_ERR_INVALID_RESPONSE;
    memset(&selection, 0, sizeof(selection));
    status = resolve_video(NULL, input, cookie_file, YT_DEFAULT_MAX_HEIGHT, 0,
                           &selection, progress, progress_opaque);
    if (status == YT_OK) {
      *result = selection.video;
      memset(&selection.video, 0, sizeof(selection.video));
    }
    yt_media_selection_free(&selection);
    return status;
  }
}

YTStatus yt_resolve_video_with_http_session_and_progress(
    YTHttpSession *session, const char *input, const char *cookie_file,
    YTMediaRequest *result, YTProgressCallback progress,
    void *progress_opaque) {
  if (session == NULL || (cookie_file != NULL && cookie_file[0] == '\0'))
    return YT_ERR_INVALID_RESPONSE;
  return yt_resolve_video_with_http_session_and_max_height_and_progress(
      session, input, cookie_file, YT_DEFAULT_MAX_HEIGHT, result, progress,
      progress_opaque);
}

YTStatus yt_resolve_video_with_http_session_and_max_height_and_progress(
    YTHttpSession *session, const char *input, const char *cookie_file,
    int max_height, YTMediaRequest *result, YTProgressCallback progress,
    void *progress_opaque) {
  if (session == NULL || (cookie_file != NULL && cookie_file[0] == '\0'))
    return YT_ERR_INVALID_RESPONSE;
  {
    YTMediaSelection selection;
    YTStatus status;
    if (result == NULL)
      return YT_ERR_INVALID_RESPONSE;
    memset(&selection, 0, sizeof(selection));
    status = resolve_video(session, input, cookie_file, max_height, 0,
                           &selection, progress, progress_opaque);
    if (status == YT_OK) {
      *result = selection.video;
      memset(&selection.video, 0, sizeof(selection.video));
    }
    yt_media_selection_free(&selection);
    return status;
  }
}

YTStatus yt_resolve_video_with_http_session_and_size_and_progress(
    YTHttpSession *session, const char *input, const char *cookie_file,
    int max_height, int try_adaptive, YTMediaSelection *result,
    YTProgressCallback progress, void *progress_opaque) {
  if (session == NULL || (cookie_file != NULL && cookie_file[0] == '\0'))
    return YT_ERR_INVALID_RESPONSE;
  return resolve_video(session, input, cookie_file, max_height, try_adaptive,
                       result, progress, progress_opaque);
}

YTStatus yt_resolve_video(const char *input, YTMediaRequest *result) {
  return yt_resolve_video_with_progress(input, result, NULL, NULL);
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
  status = yt_http_head(media->url, http_status);
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

void yt_media_selection_free(YTMediaSelection *selection) {
  if (selection == NULL)
    return;
  yt_media_request_free(&selection->video);
  yt_media_request_free(&selection->audio);
  memset(selection, 0, sizeof(*selection));
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
  case YT_ERR_EJS_ASSETS_MISSING:
    return "EJS assets missing; run: retro-dlp assets install";
  case YT_ERR_JS_CHALLENGE:
    return "JavaScript challenge resolution failed";
  case YT_ERR_FILE_EXISTS:
    return "destination or partial download already exists";
  case YT_ERR_STORAGE:
    return "download storage error";
  case YT_ERR_INVALID_MEDIA:
    return "download response is not an MP4 file";
  case YT_ERR_PO_TOKEN_REQUIRED:
    return "PO token required";
  case YT_ERR_COOKIE_FILE:
    return "invalid or unreadable Netscape cookie file";
  case YT_ERR_AUTH_COOKIES_INVALID:
    return "YouTube authentication cookies are missing, expired, or invalid";
  case YT_ERR_MUX:
    return "MP4 muxing failed";
  }
  return "unknown error";
}
