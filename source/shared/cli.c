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
#include "yt_resolver.h"

#ifndef RETRO_DLP_VERSION
#define RETRO_DLP_VERSION "development"
#endif

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

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
          "  -F, --list-formats\n"
          "                   List formats advertised by YouTube and exit.\n"
          "  -o, --output FILE Write the final MP4 to FILE.\n"
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
  char video_id[12];
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
  if (yt_extract_video_id(input, video_id) != YT_OK ||
      snprintf(destination, sizeof(destination), "%s",
               output == NULL ? "" : output) >= (int)sizeof(destination)) {
    yt_media_selection_free(&selection);
    yt_http_session_destroy(request_session);
    curl_global_cleanup();
    return 1;
  }
  if (output == NULL &&
      snprintf(destination, sizeof(destination), "%s.mp4", video_id) >=
          (int)sizeof(destination)) {
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
  const char *output;
  int cookies_requested;
  int cookies_default;
  int list_formats;
  int dump_json;
  int simulate;
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
  output = NULL;
  cookies_requested = 0;
  cookies_default = 0;
  list_formats = 0;
  dump_json = 0;
  simulate = 0;
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
    } else if (strcmp(argv[index], "--list-formats") == 0 ||
               strcmp(argv[index], "-F") == 0) {
      if (list_formats)
        break;
      list_formats = 1;
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
    if (input != NULL && !(list_formats && format_expression != NULL) &&
        !(list_formats && dump_json))
      return resolve_argument(input, format_expression, list_formats,
                              dump_json, simulate, cookie_file, output);
  }

  fprintf(stderr, "retro-dlp: unsupported arguments\n");
  print_usage(stderr);
  return 2;
}
