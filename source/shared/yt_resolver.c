#include "yt_resolver.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>

#include <curl/curl.h>

#include "cJSON.h"
#include "yt_cache.h"
#include "yt_ejs.h"
#include "yt_http.h"

#define YT_PLAYER_ENDPOINT                                                   \
  "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
#define YT_CLIENT_NAME "ANDROID_VR"
#define YT_CLIENT_NAME_ID "28"
#define YT_CLIENT_VERSION "1.65.10"
#define YT_USER_AGENT                                                       \
  "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android "   \
  "12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
#define YT_CLIENT_MANIFEST_KEY "builtin-v1"
#define YT_CLIENT_MANIFEST_TTL (30LL * 24LL * 60LL * 60LL)
#define YT_SUCCESSFUL_CLIENT_TTL (24LL * 60LL * 60LL)
#define YT_PLAYER_JAVASCRIPT_TTL (7LL * 24LL * 60LL * 60LL)

static const char builtin_client_manifest[] =
    "{\"version\":1,\"clients\":[{\"name\":\"" YT_CLIENT_NAME
    "\",\"id\":\"" YT_CLIENT_NAME_ID "\",\"version\":\""
    YT_CLIENT_VERSION "\",\"userAgent\":\"" YT_USER_AGENT "\"}]}";

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
  int width;
  int height;
  int64_t content_length;
} YTFormatCandidate;

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

static void prefer_recent_client(YTClient *client) {
  char *cached;
  size_t length;
  cached = NULL;
  length = 0;
  if (yt_cache_get(YT_CACHE_SUCCESSFUL_CLIENT, "last", current_time(), &cached,
                   &length) == YT_CACHE_OK) {
    /* There is currently one client. Validate the cache now so adding more
     * clients later cannot select an unknown or stale definition. */
    if (length != strlen(client->name) ||
        memcmp(cached, client->name, length) != 0)
      yt_cache_remove(YT_CACHE_SUCCESSFUL_CLIENT, "last");
    free(cached);
  }
}

static void remember_successful_client(const YTClient *client) {
  int64_t now = current_time();
  yt_cache_put(YT_CACHE_SUCCESSFUL_CLIENT, "last", client->name,
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

static void failure_cache_key(const char *video_id, const YTClient *client,
                              char key[65]) {
  char material[128];
  if (snprintf(material, sizeof(material), "%s:%s:%s", video_id, client->name,
               client->version) >= (int)sizeof(material)) {
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
      parsed > YT_ERR_PO_TOKEN_REQUIRED ||
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
  if (copy_query_video_id(strchr(path, '?'), video_id))
    return YT_OK;
  return YT_ERR_INVALID_VIDEO_ID;
}

static cJSON *create_player_request(const char *video_id,
                                    const char *visitor_data,
                                    const YTClient *configured_client) {
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
      !cJSON_AddStringToObject(client, "deviceMake", "Oculus") ||
      !cJSON_AddStringToObject(client, "deviceModel", "Quest 3") ||
      !cJSON_AddNumberToObject(client, "androidSdkVersion", 32) ||
      !cJSON_AddStringToObject(client, "userAgent",
                              configured_client->user_agent) ||
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
                            const YTClient *client, cJSON **document_out) {
  static const char *const fixed_headers[] = {
      "Content-Type: application/json", "Origin: https://www.youtube.com"};
  char client_name_header[64];
  char client_version_header[96];
  char user_agent_header[320];
  char visitor_header[1024];
  const char *headers[6];
  size_t header_count;
  cJSON *request;
  char *json;
  YTHttpResponse response;
  YTStatus status;

  request = create_player_request(video_id, visitor_data, client);
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

static YTStatus inspect_itag_18(cJSON *document, YTFormatCandidate *candidate) {
  cJSON *streaming_data;
  cJSON *formats;
  cJSON *format;
  const char *url;
  const char *mime_type;
  const char *content_length;
  const char *cipher;
  YTFormatCandidate current;

  memset(candidate, 0, sizeof(*candidate));
  streaming_data = cJSON_GetObjectItemCaseSensitive(document, "streamingData");
  formats = cJSON_GetObjectItemCaseSensitive(streaming_data, "formats");
  if (!cJSON_IsArray(formats))
    return YT_ERR_NO_PROGRESSIVE_MP4;

  cJSON_ArrayForEach(format, formats) {
    if (json_integer(format, "itag") != 18)
      continue;
    url = json_string(format, "url");
    mime_type = json_string(format, "mimeType");
    if (mime_type == NULL || strncmp(mime_type, "video/mp4", 9) != 0)
      continue;
    memset(&current, 0, sizeof(current));
    cipher = json_string(format, "signatureCipher");
    current.signature = query_value(cipher, "s");
    current.signature_parameter = query_value(cipher, "sp");
    current.owned_url = query_value(cipher, "url");
    if (cipher != NULL && current.signature == NULL) {
      format_candidate_free(&current);
      continue;
    }
    if (current.owned_url != NULL)
      url = current.owned_url;
    if (url == NULL) {
      format_candidate_free(&current);
      continue;
    }
    current.n_challenge = query_value(strchr(url, '?') == NULL ? "" :
                                                            strchr(url, '?') + 1,
                                      "n");
    current.url = url;
    current.mime_type = mime_type;
    current.width = json_integer(format, "width");
    current.height = json_integer(format, "height");
    content_length = json_string(format, "contentLength");
    current.content_length = parse_decimal(content_length);
    if (current.signature == NULL && current.n_challenge == NULL) {
      format_candidate_free(candidate);
      *candidate = current;
      return YT_OK;
    }
    if (candidate->url == NULL)
      *candidate = current;
    else
      format_candidate_free(&current);
  }
  return candidate->url == NULL ? YT_ERR_NO_PROGRESSIVE_MP4 : YT_OK;
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
  result->itag = 18;
  result->width = candidate->width;
  result->height = candidate->height;
  result->expires_unix = url_query_integer(url, "expire");
  result->content_length = candidate->content_length;
  return YT_OK;
}

static YTStatus solve_candidate(YTFormatCandidate *candidate,
                                const char *player_source,
                                const YTClient *client,
                                YTMediaRequest *result) {
  const char *signature_challenges[1];
  const char *n_challenges[1];
  YTEJSRequest requests[2];
  size_t request_count;
  size_t signature_index;
  size_t n_index;
  YTEJSResult solved;
  YTEJSStatus ejs_status;
  char *url;
  char *updated;
  YTStatus status;

  if (candidate->signature == NULL && candidate->n_challenge == NULL)
    return finish_candidate(candidate, candidate->url, client, result);
  if (player_source == NULL)
    return YT_ERR_JS_CHALLENGE;
  request_count = 0;
  signature_index = (size_t)-1;
  n_index = (size_t)-1;
  if (candidate->signature != NULL) {
    signature_challenges[0] = candidate->signature;
    signature_index = request_count;
    requests[request_count].type = YT_EJS_CHALLENGE_SIGNATURE;
    requests[request_count].challenges = signature_challenges;
    requests[request_count].challenge_count = 1;
    ++request_count;
  }
  if (candidate->n_challenge != NULL) {
    n_challenges[0] = candidate->n_challenge;
    n_index = request_count;
    requests[request_count].type = YT_EJS_CHALLENGE_N;
    requests[request_count].challenges = n_challenges;
    requests[request_count].challenge_count = 1;
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
  url = copy_string(candidate->url);
  if (url == NULL) {
    yt_ejs_result_free(&solved);
    return YT_ERR_OUT_OF_MEMORY;
  }
  status = YT_OK;
  if (signature_index != (size_t)-1) {
    const YTEJSResponse *response = &solved.responses[signature_index];
    if (response->error != NULL || response->solution_count != 1) {
      status = YT_ERR_JS_CHALLENGE;
    } else {
      updated = set_query_parameter(
          url,
          candidate->signature_parameter == NULL ||
                  candidate->signature_parameter[0] == '\0'
              ? "signature"
              : candidate->signature_parameter,
          response->solutions[0]);
      free(url);
      url = updated;
      if (url == NULL)
        status = YT_ERR_OUT_OF_MEMORY;
    }
  }
  if (status == YT_OK && n_index != (size_t)-1) {
    const YTEJSResponse *response = &solved.responses[n_index];
    if (response->error != NULL || response->solution_count != 1) {
      status = YT_ERR_JS_CHALLENGE;
    } else {
      updated = set_query_parameter(url, "n", response->solutions[0]);
      free(url);
      url = updated;
      if (url == NULL)
        status = YT_ERR_OUT_OF_MEMORY;
    }
  }
  if (status == YT_OK) {
    char *remaining_n = query_value(strchr(url, '?') == NULL ? "" :
                                                          strchr(url, '?') + 1,
                                    "n");
    if (url_has_query_parameter(url, "s") ||
        (candidate->n_challenge != NULL && remaining_n != NULL &&
         strcmp(remaining_n, candidate->n_challenge) == 0))
      status = YT_ERR_JS_CHALLENGE;
    free(remaining_n);
  }
  if (status == YT_OK)
    status = finish_candidate(candidate, url, client, result);
  free(url);
  yt_ejs_result_free(&solved);
  return status;
}

static YTStatus parse_player_document(cJSON *document, const char *player_source,
                                      const YTClient *client,
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
    YTStatus status = inspect_itag_18(document, &candidate);
    if (status != YT_OK)
      return status;
    status = solve_candidate(&candidate, player_source, client, result);
    format_candidate_free(&candidate);
    return status;
  }
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
  status = parse_player_document(document, NULL, NULL, result);
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
  status = parse_player_document(document, player_source, NULL, result);
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

static YTStatus player_url_from_watch_page(const char *video_id,
                                           char **player_url) {
  char watch_url[96];
  YTHttpResponse response;
  YTStatus status;
  char *relative;
  if (snprintf(watch_url, sizeof(watch_url),
               "https://www.youtube.com/watch?v=%s", video_id) >=
      (int)sizeof(watch_url))
    return YT_ERR_INVALID_RESPONSE;
  status = yt_http_get(watch_url, 2U * 1024U * 1024U, &response);
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

YTStatus yt_load_player_javascript(const char *player_url, char **source) {
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
  status = yt_http_get(player_url, 8U * 1024U * 1024U, &response);
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

static YTStatus resolve_player_document(cJSON *document, const char *video_id,
                                        const YTClient *client,
                                        YTMediaRequest *result) {
  YTStatus status;
  char *player_url;
  char *player_source;
  status = parse_player_document(document, NULL, client, result);
  if (status != YT_ERR_JS_CHALLENGE)
    return status;
  player_url = player_url_from_document(document);
  if (player_url == NULL) {
    status = player_url_from_watch_page(video_id, &player_url);
    if (status != YT_OK)
      return status;
  }
  player_source = NULL;
  status = yt_load_player_javascript(player_url, &player_source);
  free(player_url);
  if (status != YT_OK)
    return status;
  status = parse_player_document(document, player_source, client, result);
  free(player_source);
  return status;
}

YTStatus yt_resolve_video(const char *input, YTMediaRequest *result) {
  char video_id[12];
  char failure_key[65];
  YTClient client;
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
  status = load_client(&client);
  if (status != YT_OK)
    return status;
  prefer_recent_client(&client);
  failure_cache_key(video_id, &client, failure_key);
  if (yt_load_cached_failure(failure_key, &status))
    return status;

  document = NULL;
  status = call_player(video_id, NULL, &client, &document);
  if (status != YT_OK) {
    yt_remember_failure(failure_key, status);
    return status;
  }

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
    status = call_player(video_id, visitor_copy, &client, &document);
    free(visitor_copy);
    if (status != YT_OK) {
      yt_remember_failure(failure_key, status);
      return status;
    }
  }

  status = resolve_player_document(document, video_id, &client, result);
  cJSON_Delete(document);
  if (status == YT_OK) {
    remember_successful_client(&client);
    yt_cache_remove(YT_CACHE_FAILURE, failure_key);
  } else {
    yt_remember_failure(failure_key, status);
  }
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
  }
  return "unknown error";
}
