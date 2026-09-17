#include "yt_playlist.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "cJSON.h"
#include "yt_http.h"
#include "yt_innertube.h"
#include "yt_playlist_internal.h"
#include "yt_session.h"
#include "yt_util.h"
#include "yt_webpage.h"

#define YT_PLAYLIST_PAGE_MAX_RESPONSE (8U * 1024U * 1024U)
#define YT_PLAYLIST_ID_MAX 128
#define YT_PLAYLIST_MAX_ENTRIES 10000U
#define YT_PLAYLIST_MAX_PAGES 100U
#define YT_PLAYLIST_ORIGIN "https://www.youtube.com"
#define YT_PLAYLIST_USER_AGENT                                                \
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "                        \
  "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 "                  \
  "Safari/605.1.15,gzip(gfe)"

YTStatus yt_playlist_parse_bootstrap_page(const char *page,
                                          YTPlaylistBootstrap *bootstrap) {
  if (page == NULL || bootstrap == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(bootstrap, 0, sizeof(*bootstrap));
  bootstrap->api_key =
      yt_webpage_string_after_marker(page, "\"INNERTUBE_API_KEY\"");
  bootstrap->client_version = yt_webpage_string_after_marker(
      page, "\"INNERTUBE_CONTEXT_CLIENT_VERSION\"");
  bootstrap->visitor_data =
      yt_webpage_string_after_marker(page, "\"VISITOR_DATA\"");
  bootstrap->document = yt_webpage_embedded_json(page, "ytInitialData");
  if (bootstrap->api_key == NULL || bootstrap->client_version == NULL ||
      bootstrap->document == NULL) {
    yt_playlist_bootstrap_free(bootstrap);
    return YT_ERR_INVALID_RESPONSE;
  }
  return YT_OK;
}

void yt_playlist_bootstrap_free(YTPlaylistBootstrap *bootstrap) {
  if (bootstrap == NULL)
    return;
  free(bootstrap->api_key);
  free(bootstrap->client_version);
  free(bootstrap->visitor_data);
  cJSON_Delete(bootstrap->document);
  memset(bootstrap, 0, sizeof(*bootstrap));
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

static int valid_raw_playlist_id(const char *value, size_t length) {
  static const char *const prefixes[] = {"PL", "UU", "FL", "OL", "RD"};
  size_t index;
  if (!valid_playlist_id(value, length))
    return 0;
  for (index = 0; index < sizeof(prefixes) / sizeof(prefixes[0]); ++index) {
    if (strncmp(value, prefixes[index], 2) == 0)
      return 1;
  }
  return 0;
}

static int youtube_url_path(const char *input, const char **path_out) {
  const char *scheme;
  const char *authority;
  const char *authority_end;
  const char *host_end;
  size_t host_length;
  if (input == NULL)
    return 0;
  scheme = strstr(input, "://");
  if (scheme == NULL ||
      !((scheme - input == 5 && strncmp(input, "https", 5) == 0) ||
        (scheme - input == 4 && strncmp(input, "http", 4) == 0)))
    return 0;
  authority = scheme + 3;
  authority_end = strpbrk(authority, "/?#");
  if (authority_end == NULL)
    authority_end = authority + strlen(authority);
  if (memchr(authority, '@', (size_t)(authority_end - authority)) != NULL)
    return 0;
  host_end = memchr(authority, ':', (size_t)(authority_end - authority));
  if (host_end == NULL)
    host_end = authority_end;
  host_length = (size_t)(host_end - authority);
  if (!((host_length == 11 && strncasecmp(authority, "youtube.com", 11) == 0) ||
        (host_length > 12 &&
         strncasecmp(authority + host_length - 12, ".youtube.com", 12) == 0)))
    return 0;
  *path_out = authority_end;
  return 1;
}

int yt_is_playlist_collection_url(const char *input) {
  const char *path;
  const char *end;
  size_t length;
  if (!youtube_url_path(input, &path))
    return 0;
  end = strpbrk(path, "?#");
  if (end == NULL)
    end = path + strlen(path);
  while (end > path + 1 && end[-1] == '/')
    --end;
  length = (size_t)(end - path);
  return (length == 15 && strncmp(path, "/feed/playlists", 15) == 0) ||
         (length == 9 && strncmp(path, "/feed/you", 9) == 0) ||
         (length == 13 && strncmp(path, "/feed/library", 13) == 0);
}

YTStatus yt_extract_playlist_id(const char *input, char *playlist_id,
                                size_t playlist_id_size) {
  const char *path;
  const char *query;
  const char *start;
  const char *end;
  size_t length;
  if (input == NULL || playlist_id == NULL || playlist_id_size == 0)
    return YT_ERR_INVALID_PLAYLIST;
  length = strlen(input);
  if (length > 2 && valid_raw_playlist_id(input, length)) {
    if (length >= playlist_id_size)
      return YT_ERR_INVALID_PLAYLIST;
    memcpy(playlist_id, input, length + 1);
    return YT_OK;
  }
  if (!youtube_url_path(input, &path))
    return YT_ERR_INVALID_PLAYLIST;
  query = strchr(path, '?');
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
  return yt_json_string(title, "content");
}

static const char *renderer_text(cJSON *renderer, const char *name) {
  cJSON *text;
  cJSON *runs;
  cJSON *first;
  text = cJSON_GetObjectItemCaseSensitive(renderer, name);
  if (!cJSON_IsObject(text))
    return NULL;
  if (yt_json_string(text, "simpleText") != NULL)
    return yt_json_string(text, "simpleText");
  runs = cJSON_GetObjectItemCaseSensitive(text, "runs");
  first = cJSON_IsArray(runs) ? cJSON_GetArrayItem(runs, 0) : NULL;
  return yt_json_string(first, "text");
}

/* Metadata is copied only from the renderer already being enumerated. */
static YTStatus copy_optional(char **out, const char *text) {
  if (*out != NULL || text == NULL || text[0] == '\0')
    return YT_OK;
  *out = yt_copy_string(text);
  return *out == NULL ? YT_ERR_OUT_OF_MEMORY : YT_OK;
}

static YTStatus copy_text(char **out, cJSON *node) {
  const char *text;
  cJSON *run;
  cJSON *runs;
  size_t length = 0;
  size_t offset = 0;
  if (*out != NULL || !cJSON_IsObject(node))
    return YT_OK;
  text = yt_json_string(node, "simpleText");
  if (text == NULL)
    text = yt_json_string(node, "content");
  if (text != NULL && text[0] != '\0')
    return copy_optional(out, text);
  runs = cJSON_GetObjectItemCaseSensitive(node, "runs");
  if (!cJSON_IsArray(runs))
    return YT_OK;
  cJSON_ArrayForEach(run, runs) {
    text = yt_json_string(run, "text");
    if (text != NULL) {
      size_t part = strlen(text);
      if (part > (size_t)-1 - length - 1)
        return YT_ERR_OUT_OF_MEMORY;
      length += part;
    }
  }
  if (length == 0)
    return YT_OK;
  *out = (char *)malloc(length + 1);
  if (*out == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  cJSON_ArrayForEach(run, runs) {
    text = yt_json_string(run, "text");
    if (text != NULL) {
      size_t part = strlen(text);
      memcpy(*out + offset, text, part);
      offset += part;
    }
  }
  (*out)[length] = '\0';
  return YT_OK;
}

/* JSON numbers must remain exact when serialized by cJSON (IEEE doubles). */
#define YT_METADATA_INTEGER_MAX UINT64_C(9007199254740991)
static int parse_unsigned(const char *text, uint64_t *value) {
  uint64_t number = 0;
  if (text == NULL || *text == '\0')
    return 0;
  for (; *text != '\0'; ++text) {
    unsigned digit = (unsigned char)*text - '0';
    if (digit > 9 || number > (YT_METADATA_INTEGER_MAX - digit) / 10)
      return 0;
    number = number * 10 + digit;
  }
  *value = number;
  return 1;
}

static int parse_number(cJSON *node, uint64_t *value) {
  double number;
  if (cJSON_IsString(node))
    return parse_unsigned(node->valuestring, value);
  if (!cJSON_IsNumber(node))
    return 0;
  number = node->valuedouble;
  if (!(number >= 0 && number <= (double)YT_METADATA_INTEGER_MAX))
    return 0;
  *value = (uint64_t)number;
  return (double)*value == number;
}

static int parse_duration(const char *text, uint64_t *value) {
  uint64_t total = 0;
  uint64_t part = 0;
  unsigned digits = 0;
  unsigned groups = 0;
  const char *cursor;
  if (text == NULL)
    return 0;
  for (cursor = text;; ++cursor) {
    if (*cursor >= '0' && *cursor <= '9') {
      if (part > (YT_METADATA_INTEGER_MAX - 9) / 10)
        return 0;
      part = part * 10 + (unsigned)(*cursor - '0');
      ++digits;
    } else if (*cursor == ':' || *cursor == '\0') {
      if (digits == 0 || (groups != 0 && (part >= 60 || digits != 2)) ||
          groups >= 3 || total > (YT_METADATA_INTEGER_MAX - part) / 60)
        return 0;
      total = total * 60 + part;
      ++groups;
      if (*cursor == '\0')
        break;
      part = 0;
      digits = 0;
    } else {
      return 0;
    }
  }
  if (groups < 2)
    return 0;
  *value = total;
  return 1;
}

/* Only unabridged English labels are numeric. Keep all labels as text. */
static int parse_views(const char *text, uint64_t *value) {
  char digits[32];
  size_t count = 0;
  unsigned group = 0;
  int comma = 0;
  if (text == NULL)
    return 0;
  if (strcasecmp(text, "No views") == 0) {
    *value = 0;
    return 1;
  }
  while ((*text >= '0' && *text <= '9') || *text == ',') {
    if (*text == ',') {
      if (group == 0 || (comma ? group != 3 : group > 3))
        return 0;
      comma = 1;
      group = 0;
    } else {
      if (count + 1 >= sizeof(digits))
        return 0;
      digits[count++] = *text;
      ++group;
    }
    ++text;
  }
  if ((comma && group != 3) ||
      (strcmp(text, " views") != 0 && strcmp(text, " view") != 0))
    return 0;
  digits[count] = '\0';
  return parse_unsigned(digits, value);
}

static void free_entry(YTPlaylistEntry *entry) {
  size_t index;
  free(entry->video_id);
  free(entry->title);
  free(entry->channel);
  free(entry->channel_id);
  for (index = 0; index < entry->thumbnail_count; ++index)
    free(entry->thumbnail_urls[index]);
  free(entry->thumbnail_urls);
  free(entry->view_count_text);
  free(entry->published_text);
  free(entry->description_snippet);
  memset(entry, 0, sizeof(*entry));
}

static YTStatus copy_thumbnails(YTPlaylistEntry *entry, cJSON *sources) {
  cJSON *source;
  if (!cJSON_IsArray(sources))
    return YT_OK;
  cJSON_ArrayForEach(source, sources) {
    const char *url = yt_json_string(source, "url");
    char **grown;
    if (url == NULL || url[0] == '\0')
      continue;
    grown = (char **)realloc(entry->thumbnail_urls,
                            (entry->thumbnail_count + 1) * sizeof(*grown));
    if (grown == NULL)
      return YT_ERR_OUT_OF_MEMORY;
    entry->thumbnail_urls = grown;
    grown[entry->thumbnail_count] = yt_copy_string(url);
    if (grown[entry->thumbnail_count] == NULL)
      return YT_ERR_OUT_OF_MEMORY;
    ++entry->thumbnail_count;
  }
  return YT_OK;
}

static YTStatus copy_channel(YTPlaylistEntry *entry, cJSON *text) {
  cJSON *endpoint = find_named_object(text, "browseEndpoint");
  const char *id = yt_json_string(endpoint, "browseId");
  YTStatus status = copy_text(&entry->channel, text);
  if (status != YT_OK)
    return status;
  if (id != NULL && strncmp(id, "UC", 2) == 0)
    return copy_optional(&entry->channel_id, id);
  return YT_OK;
}

static YTStatus copy_video_info(YTPlaylistEntry *entry, cJSON *node) {
  char *text = NULL;
  char *separator;
  YTStatus status = copy_text(&text, node);
  if (status != YT_OK || text == NULL)
    return status;
  separator = strstr(text, " • ");
  if (separator == NULL)
    separator = strstr(text, " · ");
  if (separator != NULL) {
    size_t width = strstr(separator, " • ") == separator ? 5 : 4;
    *separator = '\0';
    /* Do not mistake unrelated combined metadata for view/publication text. */
    if (strstr(text, " view") != NULL) {
      status = copy_optional(&entry->view_count_text, text);
      if (status == YT_OK)
        status = copy_optional(&entry->published_text, separator + width);
    }
  }
  free(text);
  return status;
}

static int has_live_or_upcoming_badge(cJSON *node) {
  cJSON *child;
  const char *style;
  if (node == NULL)
    return 0;
  child = cJSON_GetObjectItemCaseSensitive(node, "thumbnailBadgeViewModel");
  style = yt_json_string(child, "text");
  if (style != NULL && (strcasecmp(style, "LIVE") == 0 ||
                        strcasecmp(style, "UPCOMING") == 0))
    return 1;
  style = yt_json_string(node, "style");
  if (style != NULL && (strcmp(style, "LIVE") == 0 ||
                        strcmp(style, "BADGE_STYLE_TYPE_LIVE_NOW") == 0))
    return 1;
  style = yt_json_string(node, "badgeStyle");
  if (style != NULL && (strcmp(style, "THUMBNAIL_OVERLAY_BADGE_STYLE_LIVE") == 0 ||
                        strcmp(style, "BADGE_STYLE_TYPE_LIVE_NOW") == 0))
    return 1;
  cJSON_ArrayForEach(child, node) {
    if (has_live_or_upcoming_badge(child))
      return 1;
  }
  return 0;
}

static int thumbnail_badge_duration(cJSON *node, uint64_t *duration) {
  cJSON *child;
  cJSON *badge;
  if (node == NULL)
    return 0;
  badge = cJSON_GetObjectItemCaseSensitive(node, "thumbnailBadgeViewModel");
  if (parse_duration(yt_json_string(badge, "text"), duration))
    return 1;
  cJSON_ArrayForEach(child, node) {
    if (thumbnail_badge_duration(child, duration))
      return 1;
  }
  return 0;
}

static YTStatus parse_entry_metadata(YTPlaylistEntry *entry, cJSON *renderer,
                                    int lockup) {
  cJSON *node;
  cJSON *child;
  cJSON *image;
  char *duration_text = NULL;
  YTStatus status = YT_OK;
#define COPY_TEXT(field, object, name) do { \
  status = copy_text(&entry->field, cJSON_GetObjectItemCaseSensitive(object, name)); \
  if (status != YT_OK) goto finished; \
} while (0)
  if (!lockup) {
    COPY_TEXT(title, renderer, "title");
    node = cJSON_GetObjectItemCaseSensitive(renderer, "lengthSeconds");
    entry->has_duration = parse_number(node, &entry->duration);
    status = copy_text(&duration_text,
                      cJSON_GetObjectItemCaseSensitive(renderer, "lengthText"));
    if (status != YT_OK)
      goto finished;
    if (!entry->has_duration)
      entry->has_duration = parse_duration(duration_text, &entry->duration);
    free(duration_text);
    duration_text = NULL;
    node = find_named_object(
        cJSON_GetObjectItemCaseSensitive(renderer, "thumbnailOverlays"),
        "thumbnailOverlayTimeStatusRenderer");
    status = copy_text(&duration_text,
                      cJSON_GetObjectItemCaseSensitive(node, "text"));
    if (status != YT_OK)
      goto finished;
    node = cJSON_GetObjectItemCaseSensitive(renderer, "shortBylineText");
    status = copy_channel(entry, node);
    if (status == YT_OK)
      status = copy_channel(entry, cJSON_GetObjectItemCaseSensitive(renderer, "ownerText"));
    if (status != YT_OK)
      goto finished;
    image = cJSON_GetObjectItemCaseSensitive(renderer, "thumbnail");
    status = copy_thumbnails(entry, cJSON_GetObjectItemCaseSensitive(image, "thumbnails"));
    if (status != YT_OK)
      goto finished;
    COPY_TEXT(view_count_text, renderer, "viewCountText");
    COPY_TEXT(view_count_text, renderer, "shortViewCountText");
    COPY_TEXT(published_text, renderer, "publishedTimeText");
    COPY_TEXT(description_snippet, renderer, "descriptionSnippet");
    node = cJSON_GetObjectItemCaseSensitive(renderer, "detailedMetadataSnippets");
    if (cJSON_IsArray(node)) {
      cJSON_ArrayForEach(child, node) {
        COPY_TEXT(description_snippet, child, "snippetText");
      }
    }
    status = copy_video_info(entry, cJSON_GetObjectItemCaseSensitive(renderer, "videoInfo"));
  } else {
    node = find_named_object(cJSON_GetObjectItemCaseSensitive(renderer, "metadata"),
                             "lockupMetadataViewModel");
    COPY_TEXT(title, node, "title");
    image = cJSON_GetObjectItemCaseSensitive(
        cJSON_GetObjectItemCaseSensitive(renderer, "contentImage"), "thumbnailViewModel");
    status = copy_thumbnails(entry, cJSON_GetObjectItemCaseSensitive(
        cJSON_GetObjectItemCaseSensitive(image, "image"), "sources"));
    if (status != YT_OK)
      goto finished;
    entry->has_duration = thumbnail_badge_duration(
        cJSON_GetObjectItemCaseSensitive(image, "overlays"), &entry->duration);
    node = find_named_object(node, "contentMetadataViewModel");
    node = cJSON_GetObjectItemCaseSensitive(node, "metadataRows");
    if (cJSON_IsArray(node)) {
      cJSON_ArrayForEach(child, node) {
        cJSON *parts = cJSON_GetObjectItemCaseSensitive(child, "metadataParts");
        cJSON *part;
        cJSON *first;
        cJSON *last;
        if (!cJSON_IsArray(parts))
          continue;
        cJSON_ArrayForEach(part, parts) {
          cJSON *text = cJSON_GetObjectItemCaseSensitive(part, "text");
          cJSON *endpoint = find_named_object(text, "browseEndpoint");
          const char *id = yt_json_string(endpoint, "browseId");
          if (id != NULL && strncmp(id, "UC", 2) == 0 && entry->channel == NULL) {
            status = copy_channel(entry, text);
            if (status != YT_OK)
              goto finished;
          }
        }
        first = cJSON_GetArrayItem(parts, 0);
        last = cJSON_GetArrayItem(parts, cJSON_GetArraySize(parts) - 1);
        /* YouTube marks the view/time row with an accessibility label. */
        if (cJSON_IsString(cJSON_GetObjectItemCaseSensitive(last, "accessibilityLabel")) &&
            cJSON_GetArraySize(parts) == 2) {
          COPY_TEXT(view_count_text, first, "text");
          COPY_TEXT(published_text, last, "text");
        }
      }
    }
  }
  if (!entry->has_duration)
    entry->has_duration = parse_duration(duration_text, &entry->duration);
  entry->has_view_count =
      !has_live_or_upcoming_badge(renderer) &&
      !cJSON_IsObject(cJSON_GetObjectItemCaseSensitive(renderer, "upcomingEventData")) &&
      (duration_text == NULL || (strcasecmp(duration_text, "UPCOMING") != 0 &&
                                 strcasecmp(duration_text, "LIVE") != 0)) &&
      parse_views(entry->view_count_text, &entry->view_count);
finished:
  free(duration_text);
#undef COPY_TEXT
  return status;
}

static YTStatus append_entry(YTPlaylist *playlist, cJSON *renderer, int lockup) {
  const char *video_id = yt_json_string(renderer, lockup ? "contentId" : "videoId");
  YTPlaylistEntry *grown;
  YTPlaylistEntry entry;
  YTStatus status;
  if (video_id == NULL || strlen(video_id) != 11 ||
      playlist->entry_count >= YT_PLAYLIST_MAX_ENTRIES)
    return playlist->entry_count >= YT_PLAYLIST_MAX_ENTRIES
               ? YT_ERR_INVALID_RESPONSE : YT_OK;
  memset(&entry, 0, sizeof(entry));
  status = copy_optional(&entry.video_id, video_id);
  if (status == YT_OK)
    status = parse_entry_metadata(&entry, renderer, lockup);
  if (status == YT_OK && entry.title == NULL)
    status = copy_optional(&entry.title, "[Unavailable video]");
  if (status != YT_OK) {
    free_entry(&entry);
    return status;
  }
  grown = (YTPlaylistEntry *)realloc(playlist->entries,
      (playlist->entry_count + 1) * sizeof(*grown));
  if (grown == NULL) {
    free_entry(&entry);
    return YT_ERR_OUT_OF_MEMORY;
  }
  playlist->entries = grown;
  entry.index = playlist->entry_count + 1;
  playlist->entries[playlist->entry_count++] = entry;
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
      type = yt_json_string(lockup, "contentType");
      if (type != NULL && strcmp(type, "LOCKUP_CONTENT_TYPE_VIDEO") == 0)
        return append_entry(playlist, lockup, 1);
    }
    renderer = cJSON_GetObjectItemCaseSensitive(node,
                                                 "playlistVideoRenderer");
    if (cJSON_IsObject(renderer))
      return append_entry(playlist, renderer, 0);
  }
  cJSON_ArrayForEach(child, node) {
    status = collect_entries(child, playlist);
    if (status != YT_OK)
      return status;
  }
  return YT_OK;
}

static YTStatus append_playlist_reference(YTPlaylistCollection *collection,
                                          const char *playlist_id,
                                          const char *title) {
  YTPlaylistReference *grown;
  YTPlaylistReference *reference;
  size_t index;
  size_t length;
  if (playlist_id == NULL)
    return YT_OK;
  length = strlen(playlist_id);
  if (!valid_playlist_id(playlist_id, length))
    return YT_OK;
  for (index = 0; index < collection->playlist_count; ++index) {
    if (strcmp(collection->playlists[index].playlist_id, playlist_id) == 0)
      return YT_OK;
  }
  if (collection->playlist_count >= YT_PLAYLIST_MAX_ENTRIES)
    return YT_ERR_INVALID_RESPONSE;
  grown = (YTPlaylistReference *)realloc(
      collection->playlists,
      (collection->playlist_count + 1) * sizeof(*collection->playlists));
  if (grown == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  collection->playlists = grown;
  reference = &collection->playlists[collection->playlist_count];
  memset(reference, 0, sizeof(*reference));
  reference->playlist_id = yt_copy_string(playlist_id);
  reference->title = yt_copy_string(title == NULL ? playlist_id : title);
  if (reference->playlist_id == NULL || reference->title == NULL) {
    free(reference->playlist_id);
    free(reference->title);
    memset(reference, 0, sizeof(*reference));
    return YT_ERR_OUT_OF_MEMORY;
  }
  reference->index = collection->playlist_count + 1;
  ++collection->playlist_count;
  return YT_OK;
}

static YTStatus collect_playlist_references(cJSON *node,
                                            YTPlaylistCollection *collection) {
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
      type = yt_json_string(lockup, "contentType");
      if (type != NULL && strcmp(type, "LOCKUP_CONTENT_TYPE_PLAYLIST") == 0)
        return append_playlist_reference(collection,
                                         yt_json_string(lockup, "contentId"),
                                         lockup_title(lockup));
    }
    renderer = cJSON_GetObjectItemCaseSensitive(node, "playlistRenderer");
    if (!cJSON_IsObject(renderer))
      renderer = cJSON_GetObjectItemCaseSensitive(node,
                                                   "gridPlaylistRenderer");
    if (cJSON_IsObject(renderer))
      return append_playlist_reference(collection,
                                       yt_json_string(renderer, "playlistId"),
                                       renderer_text(renderer, "title"));
  }
  cJSON_ArrayForEach(child, node) {
    status = collect_playlist_references(child, collection);
    if (status != YT_OK)
      return status;
  }
  return YT_OK;
}

YTStatus yt_parse_playlist_collection_json(const char *json, size_t length,
                                           YTPlaylistCollection *collection) {
  cJSON *document;
  YTStatus status;
  if (json == NULL || collection == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(collection, 0, sizeof(*collection));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  status = collect_playlist_references(document, collection);
  cJSON_Delete(document);
  if (status == YT_OK && collection->playlist_count == 0)
    status = YT_ERR_INVALID_RESPONSE;
  if (status != YT_OK)
    yt_playlist_collection_free(collection);
  return status;
}

static const char *continuation_in_node(cJSON *node, int *malformed) {
  cJSON *command;
  cJSON *child;
  const char *token;
  if (node == NULL)
    return NULL;
  if (cJSON_IsObject(node)) {
    command = cJSON_GetObjectItemCaseSensitive(node, "continuationCommand");
    if (cJSON_IsObject(command)) {
      token = yt_json_string(command, "token");
      if (token != NULL && token[0] != '\0')
        return token;
      *malformed = 1;
      return NULL;
    }
  }
  cJSON_ArrayForEach(child, node) {
    token = continuation_in_node(child, malformed);
    if (token != NULL || *malformed)
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

static int contains_direct_playlist(cJSON *array) {
  cJSON *child;
  cJSON *lockup;
  cJSON *renderer;
  const char *type;
  if (!cJSON_IsArray(array))
    return 0;
  cJSON_ArrayForEach(child, array) {
    lockup = cJSON_GetObjectItemCaseSensitive(child, "lockupViewModel");
    if (cJSON_IsObject(lockup)) {
      type = yt_json_string(lockup, "contentType");
      if (type != NULL && strcmp(type, "LOCKUP_CONTENT_TYPE_PLAYLIST") == 0)
        return 1;
    }
    renderer = cJSON_GetObjectItemCaseSensitive(child, "playlistRenderer");
    if (!cJSON_IsObject(renderer))
      renderer = cJSON_GetObjectItemCaseSensitive(child,
                                                   "gridPlaylistRenderer");
    if (cJSON_IsObject(renderer))
      return 1;
  }
  return 0;
}

static const char *find_entry_continuation(cJSON *node, int *malformed) {
  cJSON *child;
  const char *token;
  if (cJSON_IsArray(node) && contains_direct_video(node))
    return continuation_in_node(node, malformed);
  cJSON_ArrayForEach(child, node) {
    token = find_entry_continuation(child, malformed);
    if (token != NULL || *malformed)
      return token;
  }
  return NULL;
}

static const char *find_playlist_continuation(cJSON *node) {
  cJSON *child;
  const char *token;
  int malformed = 0;
  if (cJSON_IsArray(node) && contains_direct_playlist(node))
    return continuation_in_node(node, &malformed);
  cJSON_ArrayForEach(child, node) {
    token = find_playlist_continuation(child);
    if (token != NULL)
      return token;
  }
  return NULL;
}

YTStatus yt_playlist_collect_entries(cJSON *document, YTPlaylist *playlist,
                                     char **continuation) {
  const char *token;
  YTStatus status;
  int malformed;
  if (document == NULL || playlist == NULL || continuation == NULL)
    return YT_ERR_INVALID_RESPONSE;
  *continuation = NULL;
  status = collect_entries(document, playlist);
  if (status != YT_OK)
    return status;
  malformed = 0;
  token = find_entry_continuation(document, &malformed);
  if (malformed)
    return YT_ERR_INVALID_RESPONSE;
  *continuation = yt_copy_string(token);
  if (token != NULL && *continuation == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  return YT_OK;
}

YTStatus yt_list_playlist(YTHttpSession *session, const char *input,
                          const char *cookie_file, YTPlaylist *playlist,
                          YTProgressCallback progress, void *progress_opaque) {
  char playlist_id[YT_PLAYLIST_ID_MAX];
  char url[256];
  YTHttpResponse response;
  YTAccountContext account;
  YTPlaylistBootstrap bootstrap;
  cJSON *document;
  cJSON *metadata;
  const char *title;
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
  memset(&bootstrap, 0, sizeof(bootstrap));
  status = yt_extract_playlist_id(input, playlist_id, sizeof(playlist_id));
  if (status != YT_OK)
    return status;
  status = yt_account_context_load_cookies(session, cookie_file, &account);
  if (status != YT_OK)
    return status;
  if (snprintf(url, sizeof(url),
               YT_PLAYLIST_ORIGIN "/playlist?list=%s&hl=en", playlist_id) >=
      (int)sizeof(url)) {
    yt_account_context_free(&account);
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
    yt_account_context_load_page(&account, response.data);
  status = yt_playlist_parse_bootstrap_page(response.data, &bootstrap);
  yt_http_response_free(&response);
  if (status != YT_OK)
    goto finished;
  api_key = bootstrap.api_key;
  client_version = bootstrap.client_version;
  visitor_data = bootstrap.visitor_data;
  document = bootstrap.document;
  memset(&bootstrap, 0, sizeof(bootstrap));
  playlist->playlist_id = yt_copy_string(playlist_id);
  metadata = find_named_object(document, "playlistMetadataRenderer");
  title = yt_json_string(metadata, "title");
  playlist->title = yt_copy_string(title == NULL ? playlist_id : title);
  if (playlist->playlist_id == NULL || playlist->title == NULL) {
    status = YT_ERR_OUT_OF_MEMORY;
    goto pagination_finished;
  }
  reloaded_document = NULL;
  reload_status = yt_innertube_call_browse(
      session, &account, api_key, client_version, visitor_data, NULL,
      playlist_id, &reloaded_document);
  if (reload_status == YT_OK) {
    cJSON_Delete(document);
    document = reloaded_document;
  }
  continuation = NULL;
  status = yt_playlist_collect_entries(document, playlist, &continuation);
  cJSON_Delete(document);
  document = NULL;
  if (status != YT_OK)
    goto pagination_finished;
  for (page = 1; continuation != NULL && page <= YT_PLAYLIST_MAX_PAGES;
       ++page) {
    if (yt_http_session_cancelled(session)) {
      status = YT_ERR_CANCELLED;
      break;
    }
    if (progress != NULL)
      progress("fetching playlist continuation", progress_opaque);
    status = yt_innertube_call_browse(
        session, &account, api_key, client_version, visitor_data, continuation,
        NULL, &document);
    free(continuation);
    continuation = NULL;
    if (status != YT_OK)
      break;
    next_continuation = NULL;
    status = yt_playlist_collect_entries(document, playlist,
                                         &next_continuation);
    if (status != YT_OK)
      break;
    continuation = next_continuation;
    metadata = cJSON_GetObjectItemCaseSensitive(document, "responseContext");
    updated_visitor = yt_copy_string(yt_json_string(metadata, "visitorData"));
    if (updated_visitor != NULL) {
      free(visitor_data);
      visitor_data = updated_visitor;
    }
    cJSON_Delete(document);
    document = NULL;
  }
  if (status == YT_OK && continuation != NULL)
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
  yt_playlist_bootstrap_free(&bootstrap);
  yt_account_context_free(&account);
  if (status != YT_OK)
    yt_playlist_free(playlist);
  return status;
}

YTStatus yt_list_account_playlists(
    YTHttpSession *session, const char *input, const char *cookie_file,
    YTPlaylistCollection *collection, YTProgressCallback progress,
    void *progress_opaque) {
  const char *path;
  const char *path_end;
  char url[256];
  YTHttpResponse response;
  YTAccountContext account;
  cJSON *document = NULL;
  cJSON *context;
  const char *token;
  char *continuation = NULL;
  char *next_continuation;
  char *api_key = NULL;
  char *client_version = NULL;
  char *visitor_data = NULL;
  char *updated_visitor;
  size_t page;
  YTStatus status;
  if (session == NULL || input == NULL || collection == NULL ||
      !yt_is_playlist_collection_url(input))
    return YT_ERR_INVALID_PLAYLIST;
  memset(collection, 0, sizeof(*collection));
  memset(&account, 0, sizeof(account));
  if (cookie_file == NULL && !yt_http_session_has_cookies(session))
    return YT_ERR_AUTH_COOKIES_INVALID;
  status = yt_account_context_load_cookies(session, cookie_file, &account);
  if (status != YT_OK)
    return status;
  if (!youtube_url_path(input, &path)) {
    status = YT_ERR_INVALID_PLAYLIST;
    goto finished;
  }
  path_end = strpbrk(path, "?#");
  if (path_end == NULL)
    path_end = path + strlen(path);
  while (path_end > path + 1 && path_end[-1] == '/')
    --path_end;
  if (snprintf(url, sizeof(url), YT_PLAYLIST_ORIGIN "%.*s?hl=en",
               (int)(path_end - path), path) >= (int)sizeof(url)) {
    status = YT_ERR_INVALID_PLAYLIST;
    goto finished;
  }
  if (progress != NULL)
    progress("fetching account playlists", progress_opaque);
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
  yt_account_context_load_page(&account, response.data);
  api_key = yt_webpage_string_after_marker(response.data, "\"INNERTUBE_API_KEY\"");
  client_version = yt_webpage_string_after_marker(
      response.data, "\"INNERTUBE_CONTEXT_CLIENT_VERSION\"");
  visitor_data = yt_webpage_string_after_marker(response.data, "\"VISITOR_DATA\"");
  document = yt_webpage_embedded_json(response.data, "ytInitialData");
  yt_http_response_free(&response);
  if (api_key == NULL || client_version == NULL || document == NULL ||
      !account.logged_in) {
    status = YT_ERR_AUTH_COOKIES_INVALID;
    goto pagination_finished;
  }
  status = collect_playlist_references(document, collection);
  token = find_playlist_continuation(document);
  continuation = yt_copy_string(token);
  if (token != NULL && continuation == NULL)
    status = YT_ERR_OUT_OF_MEMORY;
  cJSON_Delete(document);
  document = NULL;
  if (status != YT_OK)
    goto pagination_finished;
  for (page = 1; continuation != NULL && page <= YT_PLAYLIST_MAX_PAGES;
       ++page) {
    if (yt_http_session_cancelled(session)) {
      status = YT_ERR_CANCELLED;
      break;
    }
    if (progress != NULL)
      progress("fetching account playlist continuation", progress_opaque);
    status = yt_innertube_call_browse(
        session, &account, api_key, client_version, visitor_data, continuation,
        NULL, &document);
    free(continuation);
    continuation = NULL;
    if (status != YT_OK)
      break;
    status = collect_playlist_references(document, collection);
    if (status != YT_OK)
      break;
    token = find_playlist_continuation(document);
    next_continuation = yt_copy_string(token);
    if (token != NULL && next_continuation == NULL) {
      status = YT_ERR_OUT_OF_MEMORY;
      break;
    }
    continuation = next_continuation;
    context = cJSON_GetObjectItemCaseSensitive(document, "responseContext");
    updated_visitor = yt_copy_string(yt_json_string(context, "visitorData"));
    if (updated_visitor != NULL) {
      free(visitor_data);
      visitor_data = updated_visitor;
    }
    cJSON_Delete(document);
    document = NULL;
  }
  if (status == YT_OK && continuation != NULL)
    status = YT_ERR_INVALID_RESPONSE;
  if (status == YT_OK && collection->playlist_count == 0)
    status = YT_ERR_INVALID_RESPONSE;

pagination_finished:
  free(continuation);
  free(api_key);
  free(client_version);
  free(visitor_data);
  cJSON_Delete(document);

finished:
  yt_account_context_free(&account);
  if (status != YT_OK)
    yt_playlist_collection_free(collection);
  return status;
}

void yt_playlist_free(YTPlaylist *playlist) {
  size_t index;
  if (playlist == NULL)
    return;
  for (index = 0; index < playlist->entry_count; ++index) {
    free_entry(&playlist->entries[index]);
  }
  free(playlist->entries);
  free(playlist->playlist_id);
  free(playlist->title);
  memset(playlist, 0, sizeof(*playlist));
}

void yt_playlist_collection_free(YTPlaylistCollection *collection) {
  size_t index;
  if (collection == NULL)
    return;
  for (index = 0; index < collection->playlist_count; ++index) {
    free(collection->playlists[index].playlist_id);
    free(collection->playlists[index].title);
  }
  free(collection->playlists);
  memset(collection, 0, sizeof(*collection));
}
