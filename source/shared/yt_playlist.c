#include "yt_playlist.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "cJSON.h"
#include "yt_cookies.h"
#include "yt_http.h"

#define YT_PLAYLIST_PAGE_MAX_RESPONSE (8U * 1024U * 1024U)
#define YT_PLAYLIST_ID_MAX 128
#define YT_PLAYLIST_MAX_ENTRIES 10000U
#define YT_PLAYLIST_MAX_PAGES 100U
#define YT_PLAYLIST_ORIGIN "https://www.youtube.com"
#define YT_PLAYLIST_USER_AGENT                                                \
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "                        \
  "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 "                  \
  "Safari/605.1.15,gzip(gfe)"

typedef struct {
  YTAuthCookies cookies;
  char *delegated_session_id;
  char *user_session_id;
  int authenticated;
  int logged_in;
  int session_index;
  int has_session_index;
} YTPlaylistAccount;

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

static const char *json_string(cJSON *object, const char *name) {
  cJSON *value = cJSON_GetObjectItemCaseSensitive(object, name);
  return cJSON_IsString(value) ? value->valuestring : NULL;
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

static int json_integer_after_marker(const char *text, const char *marker,
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
  if (end == start || value < 0 || value > 0x7fffffffL)
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

static cJSON *embedded_json_object(const char *page, const char *marker) {
  const char *cursor;
  const char *start;
  size_t depth;
  int in_string;
  int escaped;
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

static int valid_playlist_id(const char *value, size_t length) {
  size_t index;
  if (length < 2 || length >= YT_PLAYLIST_ID_MAX)
    return 0;
  for (index = 0; index < length; ++index) {
    unsigned char byte = (unsigned char)value[index];
    if (!isalnum(byte) && byte != '-' && byte != '_')
      return 0;
  }
  return 1;
}

YTStatus yt_extract_playlist_id(const char *input, char *playlist_id,
                                size_t playlist_id_size) {
  const char *scheme;
  const char *authority;
  const char *authority_end;
  const char *host_end;
  const char *query;
  const char *start;
  const char *end;
  size_t length;
  size_t host_length;
  if (input == NULL || playlist_id == NULL || playlist_id_size == 0)
    return YT_ERR_INVALID_PLAYLIST;
  scheme = strstr(input, "://");
  if (scheme == NULL ||
      !((scheme - input == 5 && strncmp(input, "https", 5) == 0) ||
        (scheme - input == 4 && strncmp(input, "http", 4) == 0)))
    return YT_ERR_INVALID_PLAYLIST;
  authority = scheme + 3;
  authority_end = strpbrk(authority, "/?#");
  if (authority_end == NULL)
    authority_end = authority + strlen(authority);
  if (memchr(authority, '@', (size_t)(authority_end - authority)) != NULL)
    return YT_ERR_INVALID_PLAYLIST;
  host_end = memchr(authority, ':', (size_t)(authority_end - authority));
  if (host_end == NULL)
    host_end = authority_end;
  host_length = (size_t)(host_end - authority);
  if (!((host_length == 11 && strncmp(authority, "youtube.com", 11) == 0) ||
        (host_length > 12 &&
         strncmp(authority + host_length - 12, ".youtube.com", 12) == 0)))
    return YT_ERR_INVALID_PLAYLIST;
  query = strchr(authority_end, '?');
  if (query == NULL)
    return YT_ERR_INVALID_PLAYLIST;
  start = query + 1;
  while (*start != '\0' && *start != '#') {
    end = start;
    while (*end != '\0' && *end != '&' && *end != '#')
      ++end;
    if ((size_t)(end - start) > 5 && strncmp(start, "list=", 5) == 0) {
      start += 5;
      break;
    }
    start = *end == '&' ? end + 1 : end;
  }
  if (*start == '\0' || *start == '#')
    return YT_ERR_INVALID_PLAYLIST;
  end = start;
  while (*end != '\0' && *end != '&' && *end != '#')
    ++end;
  length = (size_t)(end - start);
  if (!valid_playlist_id(start, length) || length >= playlist_id_size)
    return YT_ERR_INVALID_PLAYLIST;
  memcpy(playlist_id, start, length);
  playlist_id[length] = '\0';
  return YT_OK;
}

static void account_free(YTPlaylistAccount *account) {
  if (account == NULL)
    return;
  yt_auth_cookies_free(&account->cookies);
  free(account->delegated_session_id);
  free(account->user_session_id);
  memset(account, 0, sizeof(*account));
}

static void account_load_page(YTPlaylistAccount *account, const char *page) {
  char *data_sync_id;
  char *separator;
  account->logged_in = json_true_after_marker(page, "\"LOGGED_IN\"");
  account->session_index = json_integer_after_marker(
      page, "\"SESSION_INDEX\"", &account->has_session_index);
  account->delegated_session_id =
      json_string_after_marker(page, "\"DELEGATED_SESSION_ID\"");
  account->user_session_id =
      json_string_after_marker(page, "\"USER_SESSION_ID\"");
  data_sync_id = json_string_after_marker(page, "\"DATASYNC_ID\"");
  if (data_sync_id != NULL && account->user_session_id == NULL) {
    separator = strstr(data_sync_id, "||");
    if (separator != NULL && separator[2] != '\0') {
      account->user_session_id = copy_string(separator + 2);
      if (separator != data_sync_id && account->delegated_session_id == NULL) {
        *separator = '\0';
        account->delegated_session_id = copy_string(data_sync_id);
      }
    } else if (separator != NULL) {
      *separator = '\0';
      account->user_session_id = copy_string(data_sync_id);
    }
  }
  free(data_sync_id);
}

static cJSON *find_named_object(cJSON *node, const char *name) {
  cJSON *child;
  cJSON *found;
  if (node == NULL)
    return NULL;
  if (cJSON_IsObject(node)) {
    child = cJSON_GetObjectItemCaseSensitive(node, name);
    if (cJSON_IsObject(child))
      return child;
  }
  cJSON_ArrayForEach(child, node) {
    found = find_named_object(child, name);
    if (found != NULL)
      return found;
  }
  return NULL;
}

static const char *lockup_title(cJSON *lockup) {
  cJSON *metadata;
  cJSON *view_model;
  cJSON *title;
  metadata = cJSON_GetObjectItemCaseSensitive(lockup, "metadata");
  view_model = cJSON_GetObjectItemCaseSensitive(
      metadata, "lockupMetadataViewModel");
  title = cJSON_GetObjectItemCaseSensitive(view_model, "title");
  return json_string(title, "content");
}

static const char *renderer_text(cJSON *renderer, const char *name) {
  cJSON *text;
  cJSON *runs;
  cJSON *first;
  text = cJSON_GetObjectItemCaseSensitive(renderer, name);
  if (!cJSON_IsObject(text))
    return NULL;
  if (json_string(text, "simpleText") != NULL)
    return json_string(text, "simpleText");
  runs = cJSON_GetObjectItemCaseSensitive(text, "runs");
  first = cJSON_IsArray(runs) ? cJSON_GetArrayItem(runs, 0) : NULL;
  return json_string(first, "text");
}

static YTStatus append_entry(YTPlaylist *playlist, const char *video_id,
                             const char *title) {
  YTPlaylistEntry *grown;
  YTPlaylistEntry *entry;
  size_t capacity;
  if (video_id == NULL || strlen(video_id) != 11 ||
      playlist->entry_count >= YT_PLAYLIST_MAX_ENTRIES)
    return playlist->entry_count >= YT_PLAYLIST_MAX_ENTRIES
               ? YT_ERR_INVALID_RESPONSE
               : YT_OK;
  capacity = playlist->entry_count + 1;
  grown = (YTPlaylistEntry *)realloc(
      playlist->entries, capacity * sizeof(*playlist->entries));
  if (grown == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  playlist->entries = grown;
  entry = &playlist->entries[playlist->entry_count];
  memset(entry, 0, sizeof(*entry));
  entry->video_id = copy_string(video_id);
  entry->title = copy_string(title == NULL ? "[Unavailable video]" : title);
  if (entry->video_id == NULL || entry->title == NULL) {
    free(entry->video_id);
    free(entry->title);
    return YT_ERR_OUT_OF_MEMORY;
  }
  entry->index = playlist->entry_count + 1;
  ++playlist->entry_count;
  return YT_OK;
}

static YTStatus collect_entries(cJSON *node, YTPlaylist *playlist) {
  cJSON *child;
  cJSON *lockup;
  cJSON *renderer;
  const char *type;
  YTStatus status;
  if (node == NULL)
    return YT_OK;
  if (cJSON_IsObject(node)) {
    lockup = cJSON_GetObjectItemCaseSensitive(node, "lockupViewModel");
    if (cJSON_IsObject(lockup)) {
      type = json_string(lockup, "contentType");
      if (type != NULL && strcmp(type, "LOCKUP_CONTENT_TYPE_VIDEO") == 0)
        return append_entry(playlist, json_string(lockup, "contentId"),
                            lockup_title(lockup));
    }
    renderer = cJSON_GetObjectItemCaseSensitive(node,
                                                 "playlistVideoRenderer");
    if (cJSON_IsObject(renderer))
      return append_entry(playlist, json_string(renderer, "videoId"),
                          renderer_text(renderer, "title"));
  }
  cJSON_ArrayForEach(child, node) {
    status = collect_entries(child, playlist);
    if (status != YT_OK)
      return status;
  }
  return YT_OK;
}

static const char *continuation_in_node(cJSON *node) {
  cJSON *command;
  cJSON *child;
  const char *token;
  if (node == NULL)
    return NULL;
  if (cJSON_IsObject(node)) {
    command = cJSON_GetObjectItemCaseSensitive(node, "continuationCommand");
    if (cJSON_IsObject(command) && json_string(command, "token") != NULL)
      return json_string(command, "token");
  }
  cJSON_ArrayForEach(child, node) {
    token = continuation_in_node(child);
    if (token != NULL)
      return token;
  }
  return NULL;
}

static int contains_direct_video(cJSON *array) {
  cJSON *child;
  cJSON *lockup;
  cJSON *renderer;
  if (!cJSON_IsArray(array))
    return 0;
  cJSON_ArrayForEach(child, array) {
    lockup = cJSON_GetObjectItemCaseSensitive(child, "lockupViewModel");
    renderer = cJSON_GetObjectItemCaseSensitive(child,
                                                 "playlistVideoRenderer");
    if (cJSON_IsObject(lockup) || cJSON_IsObject(renderer))
      return 1;
  }
  return 0;
}

static const char *find_entry_continuation(cJSON *node) {
  cJSON *child;
  const char *token;
  if (cJSON_IsArray(node) && contains_direct_video(node))
    return continuation_in_node(node);
  cJSON_ArrayForEach(child, node) {
    token = find_entry_continuation(child);
    if (token != NULL)
      return token;
  }
  return NULL;
}

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

static YTStatus call_browse(YTHttpSession *session,
                            const YTPlaylistAccount *account,
                            const char *api_key, const char *client_version,
                            const char *visitor_data,
                            const char *continuation, const char *playlist_id,
                            cJSON **document_out) {
  char endpoint[512];
  char client_version_header[96];
  char visitor_header[1024];
  char authorization_value[1024];
  char authorization_header[1100];
  char auth_user_header[64];
  char page_id_header[1024];
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
  authorization_value[0] = '\0';
  authorization_header[0] = '\0';
  if (account->authenticated) {
    status = yt_auth_cookies_make_authorization(
        &account->cookies, YT_PLAYLIST_ORIGIN, account->user_session_id,
        (int64_t)time(NULL), authorization_value, sizeof(authorization_value));
    if (status != YT_OK ||
        snprintf(authorization_header, sizeof(authorization_header),
                 "Authorization: %s", authorization_value) >=
            (int)sizeof(authorization_header)) {
      free(json);
      memset(authorization_value, 0, sizeof(authorization_value));
      return status == YT_OK ? YT_ERR_INVALID_RESPONSE : status;
    }
    headers[header_count++] = authorization_header;
    headers[header_count++] = "X-Origin: " YT_PLAYLIST_ORIGIN;
    if (account->has_session_index || account->delegated_session_id != NULL) {
      snprintf(auth_user_header, sizeof(auth_user_header),
               "X-Goog-AuthUser: %d",
               account->has_session_index ? account->session_index : 0);
      headers[header_count++] = auth_user_header;
    }
    if (account->delegated_session_id != NULL) {
      if (snprintf(page_id_header, sizeof(page_id_header),
                   "X-Goog-PageId: %s", account->delegated_session_id) >=
          (int)sizeof(page_id_header)) {
        free(json);
        return YT_ERR_INVALID_RESPONSE;
      }
      headers[header_count++] = page_id_header;
    }
    if (account->logged_in)
      headers[header_count++] = "X-Youtube-Bootstrap-Logged-In: true";
  }
  status = yt_http_session_post_json(session, endpoint, json, headers,
                                     header_count, &response);
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

YTStatus yt_list_playlist(YTHttpSession *session, const char *input,
                          const char *cookie_file, YTPlaylist *playlist,
                          YTProgressCallback progress, void *progress_opaque) {
  char playlist_id[YT_PLAYLIST_ID_MAX];
  char url[256];
  YTHttpResponse response;
  YTPlaylistAccount account;
  cJSON *document;
  cJSON *metadata;
  const char *title;
  const char *token;
  char *continuation;
  char *next_continuation;
  char *api_key;
  char *client_version;
  char *visitor_data;
  char *updated_visitor;
  cJSON *reloaded_document;
  YTStatus reload_status;
  size_t page;
  YTStatus status;
  if (session == NULL || input == NULL || playlist == NULL)
    return YT_ERR_INVALID_PLAYLIST;
  memset(playlist, 0, sizeof(*playlist));
  memset(&account, 0, sizeof(account));
  status = yt_extract_playlist_id(input, playlist_id, sizeof(playlist_id));
  if (status != YT_OK)
    return status;
  if (cookie_file != NULL) {
    status = yt_auth_cookies_load(cookie_file, (int64_t)time(NULL),
                                  &account.cookies);
    if (status != YT_OK)
      return status;
    account.authenticated = 1;
  }
  if (snprintf(url, sizeof(url),
               YT_PLAYLIST_ORIGIN "/playlist?list=%s&hl=en", playlist_id) >=
      (int)sizeof(url)) {
    account_free(&account);
    return YT_ERR_INVALID_PLAYLIST;
  }
  if (progress != NULL)
    progress("fetching playlist webpage", progress_opaque);
  status = yt_http_session_get_with_user_agent(
      session, url, YT_PLAYLIST_PAGE_MAX_RESPONSE, YT_PLAYLIST_USER_AGENT,
      &response);
  if (status != YT_OK)
    goto finished;
  if (response.status < 200 || response.status >= 300) {
    status = YT_ERR_HTTP;
    yt_http_response_free(&response);
    goto finished;
  }
  if (account.authenticated)
    account_load_page(&account, response.data);
  api_key = json_string_after_marker(response.data, "\"INNERTUBE_API_KEY\"");
  client_version = json_string_after_marker(
      response.data, "\"INNERTUBE_CONTEXT_CLIENT_VERSION\"");
  visitor_data = json_string_after_marker(response.data, "\"VISITOR_DATA\"");
  document = embedded_json_object(response.data, "ytInitialData");
  yt_http_response_free(&response);
  if (api_key == NULL || client_version == NULL || document == NULL) {
    free(api_key);
    free(client_version);
    free(visitor_data);
    cJSON_Delete(document);
    status = YT_ERR_INVALID_RESPONSE;
    goto finished;
  }
  playlist->playlist_id = copy_string(playlist_id);
  metadata = find_named_object(document, "playlistMetadataRenderer");
  title = json_string(metadata, "title");
  playlist->title = copy_string(title == NULL ? playlist_id : title);
  if (playlist->playlist_id == NULL || playlist->title == NULL) {
    status = YT_ERR_OUT_OF_MEMORY;
    goto pagination_finished;
  }
  reloaded_document = NULL;
  reload_status = call_browse(session, &account, api_key, client_version,
                              visitor_data, NULL, playlist_id,
                              &reloaded_document);
  if (reload_status == YT_OK) {
    cJSON_Delete(document);
    document = reloaded_document;
  }
  status = collect_entries(document, playlist);
  token = find_entry_continuation(document);
  continuation = copy_string(token);
  cJSON_Delete(document);
  document = NULL;
  if (status != YT_OK)
    goto pagination_finished;
  for (page = 1; continuation != NULL && page <= YT_PLAYLIST_MAX_PAGES;
       ++page) {
    if (progress != NULL)
      progress("fetching playlist continuation", progress_opaque);
    status = call_browse(session, &account, api_key, client_version,
                         visitor_data, continuation, NULL, &document);
    free(continuation);
    continuation = NULL;
    if (status != YT_OK)
      break;
    status = collect_entries(document, playlist);
    if (status != YT_OK)
      break;
    token = find_entry_continuation(document);
    next_continuation = copy_string(token);
    if (token != NULL && next_continuation == NULL) {
      status = YT_ERR_OUT_OF_MEMORY;
      break;
    }
    continuation = next_continuation;
    metadata = cJSON_GetObjectItemCaseSensitive(document, "responseContext");
    updated_visitor = copy_string(json_string(metadata, "visitorData"));
    if (updated_visitor != NULL) {
      free(visitor_data);
      visitor_data = updated_visitor;
    }
    cJSON_Delete(document);
    document = NULL;
  }
  if (continuation != NULL)
    status = YT_ERR_INVALID_RESPONSE;
  free(continuation);
  continuation = NULL;
  cJSON_Delete(document);
  document = NULL;
  if (status == YT_OK && playlist->entry_count == 0)
    status = YT_ERR_INVALID_RESPONSE;

pagination_finished:
  free(api_key);
  free(client_version);
  free(visitor_data);
  cJSON_Delete(document);

finished:
  account_free(&account);
  if (status != YT_OK)
    yt_playlist_free(playlist);
  return status;
}

void yt_playlist_free(YTPlaylist *playlist) {
  size_t index;
  if (playlist == NULL)
    return;
  for (index = 0; index < playlist->entry_count; ++index) {
    free(playlist->entries[index].video_id);
    free(playlist->entries[index].title);
  }
  free(playlist->entries);
  free(playlist->playlist_id);
  free(playlist->title);
  memset(playlist, 0, sizeof(*playlist));
}
