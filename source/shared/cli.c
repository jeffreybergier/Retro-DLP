#include "cli.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <curl/curl.h>

#include "cJSON.h"
#include "platform.h"
#include "yt_ejs_assets.h"
#include "yt_http.h"
#include "yt_mux.h"
#include "yt_playlist.h"
#include "yt_resolver.h"

#ifndef RETRO_DLP_VERSION
#define RETRO_DLP_VERSION "development"
#endif

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define PRESET_LOW_FORMAT "18"
#define PRESET_MED_FORMAT "135+140/134+140"
#define PRESET_HIGH_FORMAT "137+599/137+140/136+599/136+140"

static const char *preset_format_expression(const char *preset) {
  if (strcmp(preset, "low") == 0)
    return PRESET_LOW_FORMAT;
  if (strcmp(preset, "med") == 0)
    return PRESET_MED_FORMAT;
  if (strcmp(preset, "high") == 0)
    return PRESET_HIGH_FORMAT;
  return NULL;
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
  for (index = 1; index < size; ++index) {
    if (text[index] == '\0' || (text[index] & 0xc0) != 0x80)
      return 0;
  }
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
  size_t source_index;
  size_t written;
  size_t character_size;
  size_t maximum_base;
  size_t index;
  unsigned char byte;
  if (buffer == NULL || buffer_size < 6 || video_id == NULL ||
      video_id[0] == '\0')
    return 0;
  source = (const unsigned char *)
      (title != NULL && title[0] != '\0' ? title : video_id);
  maximum_base = buffer_size - 5;
  if (maximum_base > 240)
    maximum_base = 240;
  source_index = 0;
  written = 0;
  while (source[source_index] != '\0') {
    byte = source[source_index];
    character_size = utf8_character_size(source + source_index);
    if (character_size == 0) {
      byte = '_';
      character_size = 1;
    }
    if (written + character_size > maximum_base)
      break;
    if (byte < 0x80) {
      buffer[written++] = byte < 0x20 || byte == 0x7f || byte == '/' ||
                                  byte == '\\' || byte == ':'
                              ? '_'
                              : (char)byte;
    } else {
      memcpy(buffer + written, source + source_index, character_size);
      written += character_size;
    }
    source_index += character_size;
  }
  while (written > 0 &&
         (buffer[written - 1] == ' ' || buffer[written - 1] == '.'))
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

static void print_usage(FILE *stream) {
  fprintf(stream,
          "Usage: retro-dlp [OPTIONS] VIDEO_ID_OR_URL\n"
          "       retro-dlp assets {status|install|remove}\n"
          "\n"
          "Retro-DLP command line tool.\n"
          "\n"
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
          "                   Read ~/.retro-dlp/cookies.txt.\n");
  fprintf(stream,
          "\n"
          "Asset commands:\n"
          "  assets status    Show EJS asset state.\n"
          "  assets install   Download and verify the pinned EJS assets.\n"
          "  assets remove    Remove the installed EJS assets.\n");
}

static int print_asset_result(const char *action, YTEJSAssetsStatus status) {
  YTEJSAssetsInfo info;
  YTEJSAssetsStatus inspect_status;
  cJSON *document;
  char *json;

  inspect_status = yt_ejs_assets_inspect(&info);
  document = cJSON_CreateObject();
  if (document == NULL)
    return 1;
  if (!cJSON_AddStringToObject(document, "action", action) ||
      !cJSON_AddStringToObject(document, "status",
                              yt_ejs_assets_status_string(status)) ||
      !cJSON_AddStringToObject(document, "version", YT_EJS_ASSET_VERSION) ||
      !cJSON_AddBoolToObject(document, "installed", info.installed) ||
      !cJSON_AddBoolToObject(document, "coreValid", info.core_valid) ||
      !cJSON_AddBoolToObject(document, "libValid", info.lib_valid) ||
      !cJSON_AddStringToObject(document, "root", info.root[0] == '\0' ? "" :
                                                               info.root) ||
      !cJSON_AddStringToObject(document, "inspection",
                              yt_ejs_assets_status_string(inspect_status))) {
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

static int run_asset_command(const char *command) {
  YTEJSAssetsStatus status;
  YTEJSAssetsInfo info;
  int failed;

  if (strcmp(command, "status") == 0) {
    status = yt_ejs_assets_inspect(&info);
    return print_asset_result("status", status);
  }
  if (strcmp(command, "remove") == 0) {
    status = yt_ejs_assets_remove();
    failed = print_asset_result("remove", status);
    return failed || status != YT_EJS_ASSETS_OK;
  }
  if (strcmp(command, "install") == 0) {
    if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
      fprintf(stderr, "retro-dlp: could not initialize libcurl\n");
      return 1;
    }
    status = yt_ejs_assets_install();
    curl_global_cleanup();
    failed = print_asset_result("install", status);
    return failed || status != YT_EJS_ASSETS_OK;
  }
  fprintf(stderr, "retro-dlp: unsupported asset command\n");
  return 2;
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
  if (mime_type == NULL)
    return;
  start = strstr(mime_type, "codecs=\"");
  if (start == NULL)
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

static cJSON *media_request_json(const YTMediaRequest *media) {
  cJSON *document;
  cJSON *headers;
  char format_id[32];
  char resolution[32];
  char vcodec[64];
  char acodec[64];
  char format_note[32];
  char format_description[96];
  document = cJSON_CreateObject();
  if (document == NULL)
    return NULL;
  snprintf(format_id, sizeof(format_id), "%d", media->itag);
  if (media->height > 0)
    snprintf(resolution, sizeof(resolution), "%dx%d", media->width,
             media->height);
  else
    strcpy(resolution, "audio only");
  codec_name(media->mime_type, 0, vcodec);
  codec_name(media->mime_type, 1, acodec);
  if (media->height > 0) {
    snprintf(format_note, sizeof(format_note), "%dp", media->height);
    snprintf(format_description, sizeof(format_description), "%s - %s (%s)",
             format_id, resolution, format_note);
  } else {
    strcpy(format_note, "audio only");
    snprintf(format_description, sizeof(format_description),
             "%s - audio only", format_id);
  }
  if (!cJSON_AddStringToObject(document, "url", media->url) ||
      !cJSON_AddStringToObject(document, "format_id", format_id) ||
      !cJSON_AddStringToObject(document, "format", format_description) ||
      !cJSON_AddStringToObject(document, "format_note", format_note) ||
      !cJSON_AddNumberToObject(document, "itag", media->itag) ||
      !cJSON_AddStringToObject(document, "ext", format_ext(media->mime_type)) ||
      !cJSON_AddStringToObject(document, "resolution", resolution) ||
      !cJSON_AddStringToObject(document, "vcodec", vcodec) ||
      !cJSON_AddStringToObject(document, "acodec", acodec) ||
      !cJSON_AddStringToObject(document, "protocol", "https") ||
      (media->width > 0 &&
       !cJSON_AddNumberToObject(document, "width", media->width)) ||
      (media->height > 0 &&
       !cJSON_AddNumberToObject(document, "height", media->height)) ||
      (media->fps > 0 && !cJSON_AddNumberToObject(document, "fps", media->fps)) ||
      (media->audio_channels > 0 &&
       !cJSON_AddNumberToObject(document, "audio_channels",
                               media->audio_channels)) ||
      (media->content_length > 0 &&
       !cJSON_AddNumberToObject(document, "filesize",
                               (double)media->content_length))) {
    cJSON_Delete(document);
    return NULL;
  }
  headers = cJSON_AddObjectToObject(document, "http_headers");
  if (headers == NULL ||
      !cJSON_AddStringToObject(headers, "User-Agent", media->user_agent)) {
    cJSON_Delete(document);
    return NULL;
  }
  return document;
}

static int print_media_selection(const YTMediaSelection *selection,
                                 const char *input) {
  cJSON *document;
  cJSON *video;
  cJSON *audio;
  cJSON *requested;
  char *json;
  char webpage_url[128];
  char resolution[32];
  char vcodec[64];
  char acodec[64];
  char format_description[224];
  int64_t total_size;
  document = cJSON_CreateObject();
  video = media_request_json(&selection->video);
  audio = selection->adaptive ? media_request_json(&selection->audio) : NULL;
  snprintf(webpage_url, sizeof(webpage_url),
           "https://www.youtube.com/watch?v=%s", selection->video_id);
  snprintf(resolution, sizeof(resolution), "%dx%d", selection->video.width,
           selection->video.height);
  codec_name(selection->video.mime_type, 0, vcodec);
  codec_name(selection->adaptive ? selection->audio.mime_type
                                 : selection->video.mime_type,
             1, acodec);
  total_size = selection->video.content_length;
  if (selection->adaptive)
    total_size += selection->audio.content_length;
  if (selection->adaptive)
    snprintf(format_description, sizeof(format_description),
             "%d - %s (%dp)+%d - audio only", selection->video.itag,
             resolution, selection->video.height, selection->audio.itag);
  else
    snprintf(format_description, sizeof(format_description), "%d - %s (%dp)",
             selection->video.itag, resolution, selection->video.height);
  if (document == NULL || video == NULL ||
      (selection->adaptive && audio == NULL) ||
      !cJSON_AddStringToObject(document, "id", selection->video_id) ||
      !cJSON_AddStringToObject(document, "title", selection->title) ||
      !cJSON_AddStringToObject(document, "webpage_url", webpage_url) ||
      !cJSON_AddStringToObject(document, "original_url", input) ||
      !cJSON_AddStringToObject(document, "extractor", "youtube") ||
      !cJSON_AddStringToObject(document, "extractor_key", "Youtube") ||
      !cJSON_AddStringToObject(document, "format_id", selection->format_id) ||
      !cJSON_AddStringToObject(document, "format", format_description) ||
      !cJSON_AddStringToObject(document, "ext", "mp4") ||
      !cJSON_AddNumberToObject(document, "width", selection->video.width) ||
      !cJSON_AddNumberToObject(document, "height", selection->video.height) ||
      !cJSON_AddStringToObject(document, "resolution", resolution) ||
      !cJSON_AddStringToObject(document, "vcodec", vcodec) ||
      !cJSON_AddStringToObject(document, "acodec", acodec) ||
      !cJSON_AddStringToObject(document, "protocol",
                              selection->adaptive ? "https+https" : "https") ||
      (selection->video.fps > 0 &&
       !cJSON_AddNumberToObject(document, "fps", selection->video.fps)) ||
      (total_size > 0 &&
       !cJSON_AddNumberToObject(document, "filesize_approx",
                               (double)total_size))) {
    cJSON_Delete(document);
    cJSON_Delete(video);
    cJSON_Delete(audio);
    return 1;
  }
  if (selection->adaptive) {
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
    if (!cJSON_AddStringToObject(document, "url", selection->video.url) ||
        !cJSON_AddNumberToObject(document, "itag", selection->video.itag) ||
        (selection->video.content_length > 0 &&
         !cJSON_AddNumberToObject(document, "filesize",
                                 (double)selection->video.content_length)) ||
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

static int print_download_result(const char *path, int64_t bytes_written) {
  cJSON *document;
  char *json;
  document = cJSON_CreateObject();
  if (document == NULL)
    return 1;
  if (!cJSON_AddStringToObject(document, "status", "downloaded") ||
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

static void print_progress(const char *message, void *opaque) {
  FILE *stream;
  stream = (FILE *)opaque;
  fprintf(stream, "retro-dlp: %s\n", message);
}

static size_t maximum_width(size_t current, const char *value) {
  size_t length = strlen(value);
  return current > length ? current : length;
}

static const char *format_type_name(const YTFormatInfo *format) {
  if (format->has_video && format->has_audio)
    return "video+audio";
  if (format->has_video)
    return "video only";
  return "audio only";
}

static void format_resolution(const YTFormatInfo *format, char output[32]) {
  if (format->height > 0)
    snprintf(output, 32, "%dx%d", format->width, format->height);
  else
    strcpy(output, "audio only");
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

static void print_formats(FILE *stream, const YTMediaSelection *selection) {
  size_t index;
  size_t widths[8];
  char id[32];
  char resolution[32];
  char vcodec[64];
  char acodec[64];
  char fps[16];
  const char *type;
  const char *support;
  static const char *headings[8] = {
      "ID", "EXT", "RESOLUTION", "FPS", "TYPE", "VCODEC", "ACODEC",
      "SUPPORT"};
  for (index = 0; index < 8; ++index)
    widths[index] = strlen(headings[index]);
  for (index = 0; index < selection->format_count; ++index) {
    const YTFormatInfo *format = &selection->formats[index];
    snprintf(id, sizeof(id), "%d", format->itag);
    format_resolution(format, resolution);
    codec_name(format->mime_type, 0, vcodec);
    codec_name(format->mime_type, 1, acodec);
    type = format_type_name(format);
    if (format->fps > 0)
      snprintf(fps, sizeof(fps), "%d", format->fps);
    else
      strcpy(fps, "-");
    support = format->supported ? "Yes" : "No";
    widths[0] = maximum_width(widths[0], id);
    widths[1] = maximum_width(widths[1], format_ext(format->mime_type));
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
  for (index = 0; index < selection->format_count; ++index) {
    const YTFormatInfo *format = &selection->formats[index];
    snprintf(id, sizeof(id), "%d", format->itag);
    format_resolution(format, resolution);
    codec_name(format->mime_type, 0, vcodec);
    codec_name(format->mime_type, 1, acodec);
    type = format_type_name(format);
    if (format->fps > 0)
      snprintf(fps, sizeof(fps), "%d", format->fps);
    else
      strcpy(fps, "-");
    support = format->supported ? "Yes" : "No";
    fprintf(stream, "%-*s  %-*s  %-*s  %*s  %-*s  %-*s  %-*s  %-*s\n",
            (int)widths[0], id, (int)widths[1],
            format_ext(format->mime_type), (int)widths[2], resolution,
            (int)widths[3], fps, (int)widths[4], type, (int)widths[5],
            vcodec, (int)widths[6], acodec, (int)widths[7], support);
  }
}


static int resolve_argument(const char *input, const char *format_expression,
                            int list_formats, int dump_json, int simulate,
                            const char *cookie_file, const char *output) {
  YTMediaSelection selection;
  YTMediaRequest *media;
  YTStatus status;
  char destination[PATH_MAX];
  char video_destination[PATH_MAX];
  char audio_destination[PATH_MAX];
  long http_status;
  int64_t bytes_written;
  int64_t audio_bytes_written;
  int64_t muxed_bytes;
  int failed;
  int cleanup_failed;
  YTHttpSession *request_session;

  memset(&selection, 0, sizeof(selection));

  if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
    fprintf(stderr, "retro-dlp: could not initialize libcurl\n");
    return 1;
  }
  request_session = NULL;
  status = yt_http_session_create(cookie_file, &request_session);
  if (status != YT_OK) {
    fprintf(stderr, "retro-dlp: %s\n", yt_status_string(status));
    curl_global_cleanup();
    return 1;
  }
  fprintf(stderr, "retro-dlp: resolving video information\n");
  status = yt_resolve_video_with_http_session_and_format_and_progress(
      request_session, input, cookie_file,
      format_expression == NULL ? "22/18" : format_expression, list_formats,
      &selection, print_progress, stderr);
  if (status != YT_OK) {
    fprintf(stderr, "retro-dlp: %s\n", yt_status_string(status));
    if (status == YT_ERR_FORMAT_UNAVAILABLE && selection.format_count > 0) {
      fputc('\n', stderr);
      print_formats(stderr, &selection);
    }
    yt_media_selection_free(&selection);
    yt_http_session_destroy(request_session);
    curl_global_cleanup();
    return 1;
  }
  if (list_formats) {
    print_formats(stdout, &selection);
    yt_media_selection_free(&selection);
    yt_http_session_destroy(request_session);
    curl_global_cleanup();
    return 0;
  }
  media = &selection.video;
  if (dump_json) {
    failed = print_media_selection(&selection, input);
    yt_media_selection_free(&selection);
    yt_http_session_destroy(request_session);
    curl_global_cleanup();
    if (failed)
      fprintf(stderr, "retro-dlp: could not create result JSON\n");
    return failed;
  }
  if (simulate) {
    fprintf(stderr, "retro-dlp: selected format %s\n", selection.format_id);
    yt_media_selection_free(&selection);
    yt_http_session_destroy(request_session);
    curl_global_cleanup();
    return 0;
  }
  if (snprintf(destination, sizeof(destination), "%s",
               output == NULL ? "" : output) >= (int)sizeof(destination)) {
    yt_media_selection_free(&selection);
    yt_http_session_destroy(request_session);
    curl_global_cleanup();
    return 1;
  }
  if (output == NULL &&
      !retro_dlp_default_output_path(selection.title, selection.video_id,
                                     destination, sizeof(destination))) {
    yt_media_selection_free(&selection);
    yt_http_session_destroy(request_session);
    curl_global_cleanup();
    return 1;
  }
  fprintf(stderr, "retro-dlp: selected itag %d (%dx%d, %s)\n", media->itag,
          media->width, media->height, media->mime_type);
  if (selection.adaptive) {
    if (snprintf(video_destination, sizeof(video_destination), "%s.video.mp4",
                 destination) >= (int)sizeof(video_destination) ||
        snprintf(audio_destination, sizeof(audio_destination), "%s.audio.m4a",
                 destination) >= (int)sizeof(audio_destination)) {
      yt_media_selection_free(&selection);
      yt_http_session_destroy(request_session);
      curl_global_cleanup();
      return 1;
    }
    fprintf(stderr, "retro-dlp: selected audio itag %d (%s)\n",
            selection.audio.itag, selection.audio.mime_type);
    fprintf(stderr, "retro-dlp: starting audio download to %s\n",
            audio_destination);
    http_status = 0;
    audio_bytes_written = 0;
    status = yt_http_session_download(
        request_session, selection.audio.url, audio_destination, &http_status,
        &audio_bytes_written);
    if (status == YT_OK) {
      fprintf(stderr, "retro-dlp: starting video download to %s\n",
              video_destination);
      bytes_written = 0;
      status = yt_http_session_download(request_session, media->url,
                                        video_destination, &http_status,
                                        &bytes_written);
      if (status != YT_OK)
        unlink(audio_destination);
    }
    if (status != YT_OK) {
      yt_http_session_destroy(request_session);
      yt_media_selection_free(&selection);
      curl_global_cleanup();
      fprintf(stderr, "retro-dlp: adaptive download failed: %s (HTTP %ld)\n",
              yt_status_string(status), http_status);
      return 1;
    }
    fprintf(stderr, "retro-dlp: muxing tracks to %s\n", destination);
    muxed_bytes = 0;
    status = yt_mux_mp4_tracks(video_destination, audio_destination,
                               destination, &muxed_bytes);
    yt_http_session_destroy(request_session);
    yt_media_selection_free(&selection);
    curl_global_cleanup();
    if (status != YT_OK) {
      fprintf(stderr,
              "retro-dlp: mux failed: %s; downloaded tracks were retained\n",
              yt_status_string(status));
      return 1;
    }
    cleanup_failed = unlink(video_destination) != 0;
    if (unlink(audio_destination) != 0)
      cleanup_failed = 1;
    if (cleanup_failed) {
      fprintf(stderr,
              "retro-dlp: mux succeeded but source-track cleanup failed\n");
      return 1;
    }
    fprintf(stderr, "retro-dlp: mux completed and source tracks removed\n");
    failed = print_download_result(destination, muxed_bytes);
    if (failed)
      fprintf(stderr,
              "retro-dlp: mux completed but result JSON failed\n");
    return failed;
  }
  fprintf(stderr, "retro-dlp: starting download to %s\n", destination);
  http_status = 0;
  bytes_written = 0;
  status = yt_http_session_download(request_session, media->url, destination,
                                    &http_status, &bytes_written);
  yt_http_session_destroy(request_session);
  yt_media_selection_free(&selection);
  curl_global_cleanup();
  if (status != YT_OK) {
    fprintf(stderr, "retro-dlp: download failed: %s (HTTP %ld)\n",
            yt_status_string(status), http_status);
    return 1;
  }
  failed = print_download_result(destination, bytes_written);
  if (failed)
    fprintf(stderr, "retro-dlp: download completed but result JSON failed\n");
  return failed;
}

static int print_playlist_json(const YTPlaylist *playlist) {
  size_t index;
  for (index = 0; index < playlist->entry_count; ++index) {
    const YTPlaylistEntry *entry = &playlist->entries[index];
    cJSON *document = cJSON_CreateObject();
    char url[128];
    char *json;
    if (document == NULL ||
        snprintf(url, sizeof(url), "https://www.youtube.com/watch?v=%s",
                 entry->video_id) >= (int)sizeof(url) ||
        !cJSON_AddStringToObject(document, "id", entry->video_id) ||
        !cJSON_AddStringToObject(document, "title", entry->title) ||
        !cJSON_AddStringToObject(document, "url", url) ||
        !cJSON_AddStringToObject(document, "webpage_url", url) ||
        !cJSON_AddStringToObject(document, "playlist_id",
                                playlist->playlist_id) ||
        !cJSON_AddStringToObject(document, "playlist_title",
                                playlist->title) ||
        !cJSON_AddNumberToObject(document, "playlist_index",
                                (double)entry->index) ||
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

static void print_playlist_table(const YTPlaylist *playlist) {
  size_t index;
  size_t index_width = strlen("INDEX");
  char number[32];
  for (index = 0; index < playlist->entry_count; ++index) {
    size_t width;
    snprintf(number, sizeof(number), "%lu",
             (unsigned long)playlist->entries[index].index);
    width = strlen(number);
    if (width > index_width)
      index_width = width;
  }
  printf("Playlist: %s (%s)\n", playlist->title, playlist->playlist_id);
  printf("%-*s  %-11s  %s\n", (int)index_width, "INDEX", "ID", "TITLE");
  printf("%-*s  %-11s  %s\n", (int)index_width, "-----", "-----------",
         "-----");
  for (index = 0; index < playlist->entry_count; ++index) {
    const YTPlaylistEntry *entry = &playlist->entries[index];
    printf("%*lu  %-11s  %s\n", (int)index_width,
           (unsigned long)entry->index, entry->video_id, entry->title);
  }
}

static int print_playlist_collection_json(
    const YTPlaylistCollection *collection) {
  size_t index;
  for (index = 0; index < collection->playlist_count; ++index) {
    const YTPlaylistReference *reference = &collection->playlists[index];
    cJSON *document = cJSON_CreateObject();
    char url[256];
    char *json;
    if (document == NULL ||
        snprintf(url, sizeof(url),
                 "https://www.youtube.com/playlist?list=%s",
                 reference->playlist_id) >= (int)sizeof(url) ||
        !cJSON_AddStringToObject(document, "id", reference->playlist_id) ||
        !cJSON_AddStringToObject(document, "title", reference->title) ||
        !cJSON_AddStringToObject(document, "url", url) ||
        !cJSON_AddStringToObject(document, "webpage_url", url) ||
        !cJSON_AddNumberToObject(document, "playlist_index",
                                (double)reference->index) ||
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

static void print_playlist_collection_table(
    const YTPlaylistCollection *collection) {
  size_t index;
  size_t index_width = strlen("INDEX");
  char number[32];
  for (index = 0; index < collection->playlist_count; ++index) {
    size_t width;
    snprintf(number, sizeof(number), "%lu",
             (unsigned long)collection->playlists[index].index);
    width = strlen(number);
    if (width > index_width)
      index_width = width;
  }
  printf("%-*s  %-34s  %s\n", (int)index_width, "INDEX", "ID", "TITLE");
  printf("%-*s  %-34s  %s\n", (int)index_width, "-----",
         "----------------------------------", "-----");
  for (index = 0; index < collection->playlist_count; ++index) {
    const YTPlaylistReference *reference = &collection->playlists[index];
    printf("%*lu  %-34s  %s\n", (int)index_width,
           (unsigned long)reference->index, reference->playlist_id,
           reference->title);
  }
}

static int list_playlist_argument(const char *input, const char *cookie_file,
                                  int dump_json) {
  YTHttpSession *session = NULL;
  YTPlaylist playlist;
  YTPlaylistCollection collection;
  YTStatus status;
  int failed;
  memset(&playlist, 0, sizeof(playlist));
  memset(&collection, 0, sizeof(collection));
  if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
    fprintf(stderr, "retro-dlp: could not initialize libcurl\n");
    return 1;
  }
  status = yt_http_session_create(cookie_file, &session);
  if (status == YT_OK) {
    if (yt_is_playlist_collection_url(input))
      status = yt_list_account_playlists(session, input, cookie_file,
                                         &collection, print_progress, stderr);
    else
      status = yt_list_playlist(session, input, cookie_file, &playlist,
                                print_progress, stderr);
  }
  if (status != YT_OK) {
    fprintf(stderr, "retro-dlp: %s\n", yt_status_string(status));
    yt_http_session_destroy(session);
    curl_global_cleanup();
    return 1;
  }
  if (yt_is_playlist_collection_url(input)) {
    if (dump_json)
      failed = print_playlist_collection_json(&collection);
    else {
      print_playlist_collection_table(&collection);
      failed = 0;
    }
  } else if (dump_json)
    failed = print_playlist_json(&playlist);
  else {
    print_playlist_table(&playlist);
    failed = 0;
  }
  if (failed)
    fprintf(stderr, "retro-dlp: could not create playlist output\n");
  yt_playlist_free(&playlist);
  yt_playlist_collection_free(&collection);
  yt_http_session_destroy(session);
  curl_global_cleanup();
  return failed;
}

static int default_cookie_path(char *buffer, size_t buffer_size) {
  const char *home;
  size_t home_length;
  static const char suffix[] = "/.retro-dlp/cookies.txt";

  if (buffer == NULL || buffer_size == 0)
    return 0;
  buffer[0] = '\0';
  home = getenv("HOME");
  if (home == NULL || home[0] != '/')
    return 0;
  home_length = strlen(home);
  while (home_length > 1 && home[home_length - 1] == '/')
    --home_length;
  if (home_length + sizeof(suffix) > buffer_size)
    return 0;
  memcpy(buffer, home, home_length);
  memcpy(buffer + home_length, suffix, sizeof(suffix));
  return 1;
}

int retro_dlp_run(int argc, char **argv) {
  char default_cookie_file[PATH_MAX];
  const char *cookie_file;
  const char *input;
  const char *format_expression;
  const char *preset_alias;
  const char *output;
  int cookies_requested;
  int cookies_default;
  int list_formats;
  int dump_json;
  int simulate;
  int flat_playlist;
  int index;
  if (argc == 1) {
    print_usage(stdout);
    return 0;
  }

  if (argc == 2 &&
      (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0)) {
    print_usage(stdout);
    return 0;
  }

  if (argc == 2 &&
      (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-V") == 0)) {
    printf("retro-dlp %s (%s)\n", RETRO_DLP_VERSION, retro_dlp_platform());
    return 0;
  }

  if (argc == 3 && strcmp(argv[1], "assets") == 0)
    return run_asset_command(argv[2]);

  cookie_file = NULL;
  input = NULL;
  format_expression = NULL;
  preset_alias = NULL;
  output = NULL;
  cookies_requested = 0;
  cookies_default = 0;
  list_formats = 0;
  dump_json = 0;
  simulate = 0;
  flat_playlist = 0;
  for (index = 1; index < argc; ++index) {
    if (strcmp(argv[index], "--cookies") == 0) {
      if (cookies_requested || cookies_default || index + 1 >= argc ||
          argv[index + 1][0] == '\0')
        break;
      cookies_requested = 1;
      cookie_file = argv[++index];
    } else if (strcmp(argv[index], "--cookies-default") == 0) {
      if (cookies_requested || cookies_default)
        break;
      cookies_default = 1;
    } else if (strcmp(argv[index], "--format") == 0 ||
               strcmp(argv[index], "-f") == 0) {
      if (preset_alias != NULL) {
        fprintf(stderr,
                "retro-dlp: --format and --preset-alias cannot be combined\n");
        return 2;
      }
      if (format_expression != NULL || index + 1 >= argc)
        break;
      if (!yt_format_expression_valid(argv[index + 1])) {
        fprintf(stderr,
                "retro-dlp: unsupported format expression \"%s\"\n"
                "retro-dlp: supported forms are ITAG, VIDEO_ITAG+AUDIO_ITAG, "
                "and alternatives separated by /\n",
                argv[index + 1]);
        return 2;
      }
      format_expression = argv[++index];
    } else if (strcmp(argv[index], "--preset-alias") == 0 ||
               strcmp(argv[index], "-t") == 0) {
      const char *expanded;
      if (preset_alias != NULL || index + 1 >= argc)
        break;
      if (format_expression != NULL) {
        fprintf(stderr,
                "retro-dlp: --format and --preset-alias cannot be combined\n");
        return 2;
      }
      preset_alias = argv[++index];
      expanded = preset_format_expression(preset_alias);
      if (expanded == NULL) {
        fprintf(stderr,
                "retro-dlp: unknown preset alias \"%s\"\n"
                "retro-dlp: available presets are high, med, low\n",
                preset_alias);
        return 2;
      }
      format_expression = expanded;
    } else if (strcmp(argv[index], "--list-formats") == 0 ||
               strcmp(argv[index], "-F") == 0) {
      if (list_formats)
        break;
      list_formats = 1;
    } else if (strcmp(argv[index], "--flat-playlist") == 0) {
      if (flat_playlist)
        break;
      flat_playlist = 1;
    } else if (strcmp(argv[index], "--output") == 0 ||
               strcmp(argv[index], "-o") == 0) {
      if (output != NULL || index + 1 >= argc || argv[index + 1][0] == '\0')
        break;
      output = argv[++index];
    } else if (strcmp(argv[index], "--simulate") == 0 ||
               strcmp(argv[index], "-s") == 0) {
      if (simulate)
        break;
      simulate = 1;
    } else if (strcmp(argv[index], "--dump-json") == 0 ||
               strcmp(argv[index], "-j") == 0) {
      if (dump_json)
        break;
      dump_json = 1;
      simulate = 1;
    } else if (input == NULL) {
      char video_id[12];
      if (argv[index][0] == '-' &&
          yt_extract_video_id(argv[index], video_id) != YT_OK)
        break;
      input = argv[index];
    } else {
      break;
    }
  }
  if (index == argc) {
    if (cookies_default) {
      if (!default_cookie_path(default_cookie_file,
                               sizeof(default_cookie_file))) {
        fprintf(stderr,
                "retro-dlp: could not determine the default cookie path\n");
        return 1;
      }
      cookie_file = default_cookie_file;
    }
    if (input != NULL && flat_playlist && !list_formats &&
        format_expression == NULL && preset_alias == NULL && output == NULL)
      return list_playlist_argument(input, cookie_file, dump_json);
    if (input != NULL && !flat_playlist &&
        !(list_formats && format_expression != NULL) &&
        !(list_formats && dump_json))
      return resolve_argument(input, format_expression, list_formats,
                              dump_json, simulate, cookie_file, output);
  }

  fprintf(stderr, "retro-dlp: unsupported arguments\n");
  print_usage(stderr);
  return 2;
}
