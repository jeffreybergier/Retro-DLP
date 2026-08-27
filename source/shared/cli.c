#include "cli.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <curl/curl.h>

#include "cJSON.h"
#include "platform.h"
#include "test/self_test.h"
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
          "Usage: retro-dlp [OPTIONS] VIDEO_ID_OR_URL | assets COMMAND\n"
          "\n"
          "Retro-DLP command line tool.\n"
          "\n"
          "Options:\n"
          "  -h, --help       Show this help.\n"
          "  -V, --version    Show version and build platform.\n"
          "      --cookies [FILE]\n"
          "                   Read YouTube login cookies in Netscape format.\n"
          "                   Defaults to ~/.retro-dlp/cookies.txt.\n"
          "      --no-download VIDEO_ID_OR_URL\n"
          "                   Resolve and print media JSON without downloading.\n"
          "      --size SIZE   Select the best MP4 no larger than 480p, 720p,\n"
          "                   or 1080p (default: 720p). Explicit 720p/1080p\n"
          "                   mux separate H.264 and AAC tracks natively.\n"
          "      --test       Run embedded dependency tests.\n");
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

static int print_media_request(const YTMediaRequest *media) {
  cJSON *document;
  cJSON *headers;
  char *json;

  document = cJSON_CreateObject();
  if (document == NULL)
    return 1;
  if (!cJSON_AddStringToObject(document, "url", media->url) ||
      !cJSON_AddNumberToObject(document, "itag", media->itag) ||
      !cJSON_AddNumberToObject(document, "width", media->width) ||
      !cJSON_AddNumberToObject(document, "height", media->height) ||
      !cJSON_AddStringToObject(document, "mimeType", media->mime_type) ||
      !cJSON_AddNumberToObject(document, "expires",
                              (double)media->expires_unix)) {
    cJSON_Delete(document);
    return 1;
  }
  headers = cJSON_AddObjectToObject(document, "headers");
  if (headers == NULL ||
      !cJSON_AddStringToObject(headers, "User-Agent", media->user_agent)) {
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

static cJSON *media_request_json(const YTMediaRequest *media) {
  cJSON *document;
  cJSON *headers;
  document = cJSON_CreateObject();
  if (document == NULL)
    return NULL;
  if (!cJSON_AddStringToObject(document, "url", media->url) ||
      !cJSON_AddNumberToObject(document, "itag", media->itag) ||
      !cJSON_AddNumberToObject(document, "width", media->width) ||
      !cJSON_AddNumberToObject(document, "height", media->height) ||
      !cJSON_AddStringToObject(document, "mimeType", media->mime_type) ||
      !cJSON_AddNumberToObject(document, "expires",
                              (double)media->expires_unix)) {
    cJSON_Delete(document);
    return NULL;
  }
  headers = cJSON_AddObjectToObject(document, "headers");
  if (headers == NULL ||
      !cJSON_AddStringToObject(headers, "User-Agent", media->user_agent)) {
    cJSON_Delete(document);
    return NULL;
  }
  return document;
}

static int print_media_selection(const YTMediaSelection *selection) {
  cJSON *document;
  cJSON *video;
  cJSON *audio;
  char *json;
  if (!selection->adaptive)
    return print_media_request(&selection->video);
  document = cJSON_CreateObject();
  video = media_request_json(&selection->video);
  audio = media_request_json(&selection->audio);
  if (document == NULL || video == NULL || audio == NULL ||
      !cJSON_AddBoolToObject(document, "adaptive", 1)) {
    cJSON_Delete(document);
    cJSON_Delete(video);
    cJSON_Delete(audio);
    return 1;
  }
  cJSON_AddItemToObject(document, "video", video);
  cJSON_AddItemToObject(document, "audio", audio);
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

static int parse_size(const char *value, int *max_height) {
  if (value == NULL || max_height == NULL)
    return 0;
  if (strcmp(value, "480p") == 0)
    *max_height = 480;
  else if (strcmp(value, "720p") == 0)
    *max_height = 720;
  else if (strcmp(value, "1080p") == 0)
    *max_height = 1080;
  else
    return 0;
  return 1;
}

static int resolve_argument(const char *input, int no_download,
                            const char *cookie_file, int max_height,
                            int try_adaptive) {
  YTMediaSelection selection;
  YTMediaRequest *media;
  YTStatus status;
  char video_id[12];
  char destination[32];
  char video_destination[40];
  char audio_destination[40];
  long http_status;
  int64_t bytes_written;
  int64_t audio_bytes_written;
  int64_t muxed_bytes;
  int failed;
  int cleanup_failed;
  YTHttpSession *request_session;

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
  status = yt_resolve_video_with_http_session_and_size_and_progress(
      request_session, input, cookie_file, max_height, try_adaptive,
      &selection, print_progress, stderr);
  if (status != YT_OK) {
    fprintf(stderr, "retro-dlp: %s\n", yt_status_string(status));
    yt_http_session_destroy(request_session);
    curl_global_cleanup();
    return 1;
  }
  media = &selection.video;
  if (no_download) {
    failed = print_media_selection(&selection);
    yt_media_selection_free(&selection);
    yt_http_session_destroy(request_session);
    curl_global_cleanup();
    if (failed)
      fprintf(stderr, "retro-dlp: could not create result JSON\n");
    return failed;
  }
  if (yt_extract_video_id(input, video_id) != YT_OK ||
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
                 video_id) >= (int)sizeof(video_destination) ||
        snprintf(audio_destination, sizeof(audio_destination), "%s.audio.m4a",
                 video_id) >= (int)sizeof(audio_destination)) {
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

static int run_self_tests(const char *cookie_file) {
  int result;
  if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
    fprintf(stderr, "retro-dlp: could not initialize libcurl\n");
    return 1;
  }
  result = retro_dlp_run_self_tests_with_cookies(cookie_file);
  curl_global_cleanup();
  return result;
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
  int cookies_requested;
  int no_download;
  int max_height;
  int size_requested;
  int test_mode;
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
  cookies_requested = 0;
  no_download = 0;
  max_height = YT_DEFAULT_MAX_HEIGHT;
  size_requested = 0;
  test_mode = 0;
  for (index = 1; index < argc; ++index) {
    if (strcmp(argv[index], "--cookies") == 0) {
      char video_id[12];
      if (cookies_requested)
        break;
      cookies_requested = 1;
      if (index + 1 < argc &&
          yt_extract_video_id(argv[index + 1], video_id) != YT_OK &&
          argv[index + 1][0] != '-')
        cookie_file = argv[++index];
    } else if (strcmp(argv[index], "--no-download") == 0) {
      if (no_download)
        break;
      no_download = 1;
    } else if (strcmp(argv[index], "--size") == 0) {
      if (size_requested || index + 1 >= argc ||
          !parse_size(argv[index + 1], &max_height))
        break;
      size_requested = 1;
      ++index;
    } else if (strcmp(argv[index], "--test") == 0) {
      if (test_mode)
        break;
      test_mode = 1;
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
    if (cookies_requested && cookie_file == NULL) {
      if (!default_cookie_path(default_cookie_file,
                               sizeof(default_cookie_file))) {
        fprintf(stderr,
                "retro-dlp: could not determine the default cookie path\n");
        return 1;
      }
      cookie_file = default_cookie_file;
    }
    if (test_mode && input == NULL && !no_download)
      return run_self_tests(cookie_file);
    if (!test_mode && input != NULL)
      return resolve_argument(input, no_download, cookie_file, max_height,
                              size_requested && max_height >= 720);
  }

  fprintf(stderr, "retro-dlp: unsupported arguments\n");
  print_usage(stderr);
  return 2;
}
