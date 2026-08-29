#include "cli_render.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"

#define PRESET_LOW_FORMAT "18"
#define PRESET_MED_FORMAT "135+140/134+140"
#define PRESET_HIGH_FORMAT "137+599/137+140/136+599/136+140"

void cli_render_usage(FILE *stream) {
  fprintf(stream,
          "Usage: retro-dlp [OPTIONS] VIDEO_ID_OR_URL\n"
          "       retro-dlp assets {status|install|remove}\n\n"
          "Retro-DLP command line tool.\n\n"
          "Options:\n"
          "  -h, --help       Show this help.\n"
          "  -V, --version    Show version and build platform.\n"
          "  -f, --format FORMAT\n"
          "                   Select exact itags, combinations such as 136+140,\n"
          "                   or explicit fallbacks such as 136+140/22/18.\n"
          "                   Default: 22/18.\n"
          "  -t, --preset-alias PRESET\n"
          "                   Select a built-in exact-format preset:\n"
          "                   low=" PRESET_LOW_FORMAT "\n"
          "                   med=" PRESET_MED_FORMAT "\n"
          "                   high=" PRESET_HIGH_FORMAT "\n"
          "  -F, --list-formats\n"
          "                   List formats advertised by YouTube and exit.\n"
          "      --flat-playlist\n"
          "                   List playlist entries without downloading them.\n"
          "  -o, --output FILE Write the final MP4 to FILE.\n"
          "                   Default: sanitized video title plus .mp4.\n"
          "  -s, --simulate    Resolve without downloading or writing files.\n"
          "  -j, --dump-json   Print normalized JSON and imply --simulate.\n"
          "      --cookies FILE\n"
          "                   Read YouTube login cookies in Netscape format.\n"
          "      --cookies-default\n"
          "                   Read ~/.retro-dlp/cookies.txt.\n\n"
          "Asset commands:\n"
          "  assets status    Show EJS asset state.\n"
          "  assets install   Download and verify the pinned EJS assets.\n"
          "  assets remove    Remove the installed EJS assets.\n");
}

static const char *format_ext(const char *mime_type) {
  if (mime_type == NULL)
    return "unknown";
  if (strncmp(mime_type, "audio/mp4", 9) == 0)
    return "m4a";
  if (strncmp(mime_type, "video/mp4", 9) == 0)
    return "mp4";
  if (strncmp(mime_type, "audio/webm", 10) == 0 ||
      strncmp(mime_type, "video/webm", 10) == 0)
    return "webm";
  return "unknown";
}

static void codec_name(const char *mime_type, int audio, char output[64]) {
  const char *start;
  const char *end;
  const char *comma;
  size_t length;
  strcpy(output, "none");
  if (mime_type == NULL || (start = strstr(mime_type, "codecs=\"")) == NULL)
    return;
  start += 8;
  end = strchr(start, '"');
  if (end == NULL)
    return;
  comma = memchr(start, ',', (size_t)(end - start));
  if (audio) {
    if (comma == NULL && strncmp(mime_type, "audio/", 6) != 0)
      return;
    if (comma != NULL) {
      start = comma + 1;
      while (start < end && *start == ' ')
        ++start;
    }
  } else if (strncmp(mime_type, "audio/", 6) == 0) {
    return;
  } else if (comma != NULL) {
    end = comma;
  }
  length = (size_t)(end - start);
  if (length == 0 || length >= 64)
    return;
  memcpy(output, start, length);
  output[length] = '\0';
}

static cJSON *media_request_json(const rdlp_selection *selection,
                                 size_t media_index) {
  cJSON *document = cJSON_CreateObject();
  cJSON *headers;
  char format_id[32];
  char resolution[32];
  char vcodec[64];
  char acodec[64];
  char format_note[32];
  char format_description[128];
  const char *mime = rdlp_selection_media_mime_type(selection, media_index);
  int itag = rdlp_selection_media_itag(selection, media_index);
  int width = rdlp_selection_media_width(selection, media_index);
  int height = rdlp_selection_media_height(selection, media_index);
  int fps = rdlp_selection_media_fps(selection, media_index);
  int channels = rdlp_selection_media_audio_channels(selection, media_index);
  int64_t length =
      rdlp_selection_media_content_length(selection, media_index);
  size_t index;
  if (document == NULL)
    return NULL;
  snprintf(format_id, sizeof(format_id), "%d", itag);
  if (height > 0)
    snprintf(resolution, sizeof(resolution), "%dx%d", width, height);
  else
    strcpy(resolution, "audio only");
  codec_name(mime, 0, vcodec);
  codec_name(mime, 1, acodec);
  if (height > 0) {
    snprintf(format_note, sizeof(format_note), "%dp", height);
    snprintf(format_description, sizeof(format_description), "%s - %s (%s)",
             format_id, resolution, format_note);
  } else {
    strcpy(format_note, "audio only");
    snprintf(format_description, sizeof(format_description),
             "%s - audio only", format_id);
  }
  if (!cJSON_AddStringToObject(document, "url",
                              rdlp_selection_media_url(selection, media_index)) ||
      !cJSON_AddStringToObject(document, "format_id", format_id) ||
      !cJSON_AddStringToObject(document, "format", format_description) ||
      !cJSON_AddStringToObject(document, "format_note", format_note) ||
      !cJSON_AddNumberToObject(document, "itag", itag) ||
      !cJSON_AddStringToObject(document, "ext", format_ext(mime)) ||
      !cJSON_AddStringToObject(document, "resolution", resolution) ||
      !cJSON_AddStringToObject(document, "vcodec", vcodec) ||
      !cJSON_AddStringToObject(document, "acodec", acodec) ||
      !cJSON_AddStringToObject(document, "protocol", "https") ||
      (width > 0 && !cJSON_AddNumberToObject(document, "width", width)) ||
      (height > 0 && !cJSON_AddNumberToObject(document, "height", height)) ||
      (fps > 0 && !cJSON_AddNumberToObject(document, "fps", fps)) ||
      (channels > 0 &&
       !cJSON_AddNumberToObject(document, "audio_channels", channels)) ||
      (length > 0 &&
       !cJSON_AddNumberToObject(document, "filesize", (double)length))) {
    cJSON_Delete(document);
    return NULL;
  }
  headers = cJSON_AddObjectToObject(document, "http_headers");
  if (headers == NULL) {
    cJSON_Delete(document);
    return NULL;
  }
  for (index = 0;
       index < rdlp_selection_media_header_count(selection, media_index);
       ++index) {
    const rdlp_http_header *header =
        rdlp_selection_media_header(selection, media_index, index);
    if (header == NULL ||
        !cJSON_AddStringToObject(headers, header->name, header->value)) {
      cJSON_Delete(document);
      return NULL;
    }
  }
  return document;
}

int cli_render_selection_json(const rdlp_selection *selection,
                              const char *input) {
  cJSON *document = cJSON_CreateObject();
  cJSON *video = media_request_json(selection, 0);
  cJSON *audio = rdlp_selection_is_adaptive(selection)
                     ? media_request_json(selection, 1)
                     : NULL;
  cJSON *requested;
  char *json;
  char webpage_url[128];
  char resolution[32];
  char vcodec[64];
  char acodec[64];
  char format_description[224];
  int adaptive = rdlp_selection_is_adaptive(selection);
  int video_itag = rdlp_selection_media_itag(selection, 0);
  int width = rdlp_selection_media_width(selection, 0);
  int height = rdlp_selection_media_height(selection, 0);
  int fps = rdlp_selection_media_fps(selection, 0);
  int64_t total_size = rdlp_selection_media_content_length(selection, 0);
  snprintf(webpage_url, sizeof(webpage_url),
           "https://www.youtube.com/watch?v=%s",
           rdlp_selection_video_id(selection));
  snprintf(resolution, sizeof(resolution), "%dx%d", width, height);
  codec_name(rdlp_selection_media_mime_type(selection, 0), 0, vcodec);
  codec_name(rdlp_selection_media_mime_type(selection, adaptive ? 1U : 0U),
             1, acodec);
  if (adaptive) {
    total_size += rdlp_selection_media_content_length(selection, 1);
    snprintf(format_description, sizeof(format_description),
             "%d - %s (%dp)+%d - audio only", video_itag, resolution, height,
             rdlp_selection_media_itag(selection, 1));
  } else {
    snprintf(format_description, sizeof(format_description), "%d - %s (%dp)",
             video_itag, resolution, height);
  }
  if (document == NULL || video == NULL || (adaptive && audio == NULL) ||
      !cJSON_AddStringToObject(document, "id",
                              rdlp_selection_video_id(selection)) ||
      !cJSON_AddStringToObject(document, "title",
                              rdlp_selection_title(selection)) ||
      !cJSON_AddStringToObject(document, "webpage_url", webpage_url) ||
      !cJSON_AddStringToObject(document, "original_url", input) ||
      !cJSON_AddStringToObject(document, "extractor", "youtube") ||
      !cJSON_AddStringToObject(document, "extractor_key", "Youtube") ||
      !cJSON_AddStringToObject(document, "format_id",
                              rdlp_selection_format_id(selection)) ||
      !cJSON_AddStringToObject(document, "format", format_description) ||
      !cJSON_AddStringToObject(document, "ext", "mp4") ||
      !cJSON_AddNumberToObject(document, "width", width) ||
      !cJSON_AddNumberToObject(document, "height", height) ||
      !cJSON_AddStringToObject(document, "resolution", resolution) ||
      !cJSON_AddStringToObject(document, "vcodec", vcodec) ||
      !cJSON_AddStringToObject(document, "acodec", acodec) ||
      !cJSON_AddStringToObject(document, "protocol",
                              adaptive ? "https+https" : "https") ||
      (fps > 0 && !cJSON_AddNumberToObject(document, "fps", fps)) ||
      (total_size > 0 && !cJSON_AddNumberToObject(
                             document, "filesize_approx", (double)total_size))) {
    cJSON_Delete(document);
    cJSON_Delete(video);
    cJSON_Delete(audio);
    return 1;
  }
  if (adaptive) {
    requested = cJSON_AddArrayToObject(document, "requested_formats");
    if (requested == NULL) {
      cJSON_Delete(document);
      cJSON_Delete(video);
      cJSON_Delete(audio);
      return 1;
    }
    cJSON_AddItemToArray(requested, video);
    cJSON_AddItemToArray(requested, audio);
  } else {
    cJSON *headers = cJSON_DetachItemFromObject(video, "http_headers");
    if (!cJSON_AddStringToObject(document, "url",
                                rdlp_selection_media_url(selection, 0)) ||
        !cJSON_AddNumberToObject(document, "itag", video_itag) ||
        (total_size > 0 && !cJSON_AddNumberToObject(
                               document, "filesize", (double)total_size)) ||
        headers == NULL) {
      cJSON_Delete(headers);
      cJSON_Delete(video);
      cJSON_Delete(document);
      return 1;
    }
    cJSON_AddItemToObject(document, "http_headers", headers);
    cJSON_Delete(video);
  }
  json = cJSON_Print(document);
  cJSON_Delete(document);
  if (json == NULL)
    return 1;
  printf("%s\n", json);
  free(json);
  return 0;
}

static size_t maximum_width(size_t current, const char *value) {
  size_t length = strlen(value);
  return current > length ? current : length;
}

static void format_resolution(const rdlp_selection *selection, size_t index,
                              char output[32]) {
  int height = rdlp_selection_format_height(selection, index);
  if (height > 0)
    snprintf(output, 32, "%dx%d",
             rdlp_selection_format_width(selection, index), height);
  else
    strcpy(output, "audio only");
}

static const char *format_type_name(const rdlp_selection *selection,
                                    size_t index) {
  if (rdlp_selection_format_has_video(selection, index) &&
      rdlp_selection_format_has_audio(selection, index))
    return "video+audio";
  if (rdlp_selection_format_has_video(selection, index))
    return "video only";
  return "audio only";
}

static void print_table_rule(FILE *stream, const size_t widths[8]) {
  size_t column;
  size_t index;
  for (column = 0; column < 8; ++column) {
    if (column != 0)
      fputs("  ", stream);
    for (index = 0; index < widths[column]; ++index)
      fputc('-', stream);
  }
  fputc('\n', stream);
}

void cli_render_formats(FILE *stream, const rdlp_selection *selection) {
  size_t index;
  size_t widths[8];
  char id[32], resolution[32], vcodec[64], acodec[64], fps[16];
  const char *type;
  const char *support;
  static const char *headings[8] = {"ID",    "EXT",    "RESOLUTION", "FPS",
                                    "TYPE",  "VCODEC", "ACODEC",     "SUPPORT"};
  for (index = 0; index < 8; ++index)
    widths[index] = strlen(headings[index]);
  for (index = 0; index < rdlp_selection_format_count(selection); ++index) {
    snprintf(id, sizeof(id), "%d", rdlp_selection_format_itag(selection, index));
    format_resolution(selection, index, resolution);
    codec_name(rdlp_selection_format_mime_type(selection, index), 0, vcodec);
    codec_name(rdlp_selection_format_mime_type(selection, index), 1, acodec);
    type = format_type_name(selection, index);
    if (rdlp_selection_format_fps(selection, index) > 0)
      snprintf(fps, sizeof(fps), "%d", rdlp_selection_format_fps(selection, index));
    else
      strcpy(fps, "-");
    support = rdlp_selection_format_is_supported(selection, index) ? "Yes" : "No";
    widths[0] = maximum_width(widths[0], id);
    widths[1] = maximum_width(widths[1], format_ext(rdlp_selection_format_mime_type(selection, index)));
    widths[2] = maximum_width(widths[2], resolution);
    widths[3] = maximum_width(widths[3], fps);
    widths[4] = maximum_width(widths[4], type);
    widths[5] = maximum_width(widths[5], vcodec);
    widths[6] = maximum_width(widths[6], acodec);
    widths[7] = maximum_width(widths[7], support);
  }
  fprintf(stream, "%-*s  %-*s  %-*s  %*s  %-*s  %-*s  %-*s  %-*s\n",
          (int)widths[0], headings[0], (int)widths[1], headings[1],
          (int)widths[2], headings[2], (int)widths[3], headings[3],
          (int)widths[4], headings[4], (int)widths[5], headings[5],
          (int)widths[6], headings[6], (int)widths[7], headings[7]);
  print_table_rule(stream, widths);
  for (index = 0; index < rdlp_selection_format_count(selection); ++index) {
    snprintf(id, sizeof(id), "%d", rdlp_selection_format_itag(selection, index));
    format_resolution(selection, index, resolution);
    codec_name(rdlp_selection_format_mime_type(selection, index), 0, vcodec);
    codec_name(rdlp_selection_format_mime_type(selection, index), 1, acodec);
    type = format_type_name(selection, index);
    if (rdlp_selection_format_fps(selection, index) > 0)
      snprintf(fps, sizeof(fps), "%d", rdlp_selection_format_fps(selection, index));
    else
      strcpy(fps, "-");
    support = rdlp_selection_format_is_supported(selection, index) ? "Yes" : "No";
    fprintf(stream, "%-*s  %-*s  %-*s  %*s  %-*s  %-*s  %-*s  %-*s\n",
            (int)widths[0], id, (int)widths[1],
            format_ext(rdlp_selection_format_mime_type(selection, index)),
            (int)widths[2], resolution, (int)widths[3], fps,
            (int)widths[4], type, (int)widths[5], vcodec,
            (int)widths[6], acodec, (int)widths[7], support);
  }
}

int cli_render_download_result(const char *path, int64_t bytes_written) {
  cJSON *document = cJSON_CreateObject();
  char *json;
  if (document == NULL ||
      !cJSON_AddStringToObject(document, "status", "downloaded") ||
      !cJSON_AddStringToObject(document, "path", path) ||
      !cJSON_AddNumberToObject(document, "bytes", (double)bytes_written)) {
    cJSON_Delete(document);
    return 1;
  }
  json = cJSON_Print(document);
  cJSON_Delete(document);
  if (json == NULL)
    return 1;
  printf("%s\n", json);
  free(json);
  return 0;
}

int cli_render_playlist_json(const rdlp_playlist *playlist) {
  size_t index;
  for (index = 0; index < rdlp_playlist_entry_count(playlist); ++index) {
    cJSON *document = cJSON_CreateObject();
    char url[128];
    char *json;
    const char *id = rdlp_playlist_entry_video_id(playlist, index);
    if (document == NULL ||
        snprintf(url, sizeof(url), "https://www.youtube.com/watch?v=%s", id) >=
            (int)sizeof(url) ||
        !cJSON_AddStringToObject(document, "id", id) ||
        !cJSON_AddStringToObject(document, "title", rdlp_playlist_entry_title(playlist, index)) ||
        !cJSON_AddStringToObject(document, "url", url) ||
        !cJSON_AddStringToObject(document, "webpage_url", url) ||
        !cJSON_AddStringToObject(document, "playlist_id", rdlp_playlist_id(playlist)) ||
        !cJSON_AddStringToObject(document, "playlist_title", rdlp_playlist_title(playlist)) ||
        !cJSON_AddNumberToObject(document, "playlist_index", (double)rdlp_playlist_entry_index(playlist, index)) ||
        !cJSON_AddStringToObject(document, "_type", "url") ||
        !cJSON_AddStringToObject(document, "extractor_key", "Youtube")) {
      cJSON_Delete(document);
      return 1;
    }
    json = cJSON_PrintUnformatted(document);
    cJSON_Delete(document);
    if (json == NULL)
      return 1;
    printf("%s\n", json);
    free(json);
  }
  return 0;
}

void cli_render_playlist_table(const rdlp_playlist *playlist) {
  size_t index;
  size_t index_width = strlen("INDEX");
  char number[32];
  for (index = 0; index < rdlp_playlist_entry_count(playlist); ++index) {
    size_t width;
    snprintf(number, sizeof(number), "%lu", (unsigned long)rdlp_playlist_entry_index(playlist, index));
    width = strlen(number);
    if (width > index_width)
      index_width = width;
  }
  printf("Playlist: %s (%s)\n", rdlp_playlist_title(playlist), rdlp_playlist_id(playlist));
  printf("%-*s  %-11s  %s\n", (int)index_width, "INDEX", "ID", "TITLE");
  printf("%-*s  %-11s  %s\n", (int)index_width, "-----", "-----------", "-----");
  for (index = 0; index < rdlp_playlist_entry_count(playlist); ++index)
    printf("%*lu  %-11s  %s\n", (int)index_width,
           (unsigned long)rdlp_playlist_entry_index(playlist, index),
           rdlp_playlist_entry_video_id(playlist, index),
           rdlp_playlist_entry_title(playlist, index));
}

int cli_render_playlist_collection_json(const rdlp_playlist_collection *collection) {
  size_t index;
  for (index = 0; index < rdlp_playlist_collection_count(collection); ++index) {
    cJSON *document = cJSON_CreateObject();
    char url[256];
    char *json;
    const char *id = rdlp_playlist_collection_id(collection, index);
    if (document == NULL ||
        snprintf(url, sizeof(url), "https://www.youtube.com/playlist?list=%s", id) >= (int)sizeof(url) ||
        !cJSON_AddStringToObject(document, "id", id) ||
        !cJSON_AddStringToObject(document, "title", rdlp_playlist_collection_title(collection, index)) ||
        !cJSON_AddStringToObject(document, "url", url) ||
        !cJSON_AddStringToObject(document, "webpage_url", url) ||
        !cJSON_AddNumberToObject(document, "playlist_index", (double)rdlp_playlist_collection_index(collection, index)) ||
        !cJSON_AddStringToObject(document, "_type", "url") ||
        !cJSON_AddStringToObject(document, "extractor_key", "YoutubeTab")) {
      cJSON_Delete(document);
      return 1;
    }
    json = cJSON_PrintUnformatted(document);
    cJSON_Delete(document);
    if (json == NULL)
      return 1;
    printf("%s\n", json);
    free(json);
  }
  return 0;
}

void cli_render_playlist_collection_table(const rdlp_playlist_collection *collection) {
  size_t index;
  size_t index_width = strlen("INDEX");
  char number[32];
  for (index = 0; index < rdlp_playlist_collection_count(collection); ++index) {
    size_t width;
    snprintf(number, sizeof(number), "%lu", (unsigned long)rdlp_playlist_collection_index(collection, index));
    width = strlen(number);
    if (width > index_width)
      index_width = width;
  }
  printf("%-*s  %-34s  %s\n", (int)index_width, "INDEX", "ID", "TITLE");
  printf("%-*s  %-34s  %s\n", (int)index_width, "-----", "----------------------------------", "-----");
  for (index = 0; index < rdlp_playlist_collection_count(collection); ++index)
    printf("%*lu  %-34s  %s\n", (int)index_width,
           (unsigned long)rdlp_playlist_collection_index(collection, index),
           rdlp_playlist_collection_id(collection, index),
           rdlp_playlist_collection_title(collection, index));
}

static size_t utf8_character_size(const unsigned char *text) {
  size_t size;
  size_t index;
  if (text[0] < 0x80)
    return 1;
  if (text[0] >= 0xc2 && text[0] <= 0xdf)
    size = 2;
  else if (text[0] >= 0xe0 && text[0] <= 0xef)
    size = 3;
  else if (text[0] >= 0xf0 && text[0] <= 0xf4)
    size = 4;
  else
    return 0;
  for (index = 1; index < size; ++index)
    if (text[index] == '\0' || (text[index] & 0xc0) != 0x80)
      return 0;
  if ((text[0] == 0xe0 && text[1] < 0xa0) ||
      (text[0] == 0xed && text[1] >= 0xa0) ||
      (text[0] == 0xf0 && text[1] < 0x90) ||
      (text[0] == 0xf4 && text[1] >= 0x90))
    return 0;
  return size;
}

int retro_dlp_default_output_path(const char *title, const char *video_id,
                                  char *buffer, size_t buffer_size) {
  const unsigned char *source;
  size_t source_index = 0;
  size_t written = 0;
  size_t character_size;
  size_t maximum_base;
  size_t index;
  unsigned char byte;
  if (buffer == NULL || buffer_size < 6 || video_id == NULL || video_id[0] == '\0')
    return 0;
  source = (const unsigned char *)((title != NULL && title[0] != '\0') ? title : video_id);
  maximum_base = buffer_size - 5;
  if (maximum_base > 240)
    maximum_base = 240;
  while (source[source_index] != '\0') {
    byte = source[source_index];
    character_size = utf8_character_size(source + source_index);
    if (character_size == 0) {
      byte = '_';
      character_size = 1;
    }
    if (written + character_size > maximum_base)
      break;
    if (byte < 0x80)
      buffer[written++] = byte < 0x20 || byte == 0x7f || byte == '/' || byte == '\\' || byte == ':' ? '_' : (char)byte;
    else {
      memcpy(buffer + written, source + source_index, character_size);
      written += character_size;
    }
    source_index += character_size;
  }
  while (written > 0 && (buffer[written - 1] == ' ' || buffer[written - 1] == '.'))
    --written;
  for (index = 0; index < written && buffer[index] == '.'; ++index)
    buffer[index] = '_';
  if (written == 0) {
    written = strlen(video_id);
    if (written > maximum_base)
      written = maximum_base;
    memcpy(buffer, video_id, written);
  }
  memcpy(buffer + written, ".mp4", 5);
  return 1;
}
