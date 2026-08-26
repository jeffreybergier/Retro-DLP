#include "cli.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <curl/curl.h>

#include "cJSON.h"
#include "platform.h"
#include "test/self_test.h"
#include "yt_ejs_assets.h"
#include "yt_http.h"
#include "yt_resolver.h"

#ifndef RETRO_DLP_VERSION
#define RETRO_DLP_VERSION "development"
#endif

static void print_usage(FILE *stream) {
  fprintf(stream,
          "Usage: retro-dlp [OPTION] | assets COMMAND | VIDEO_ID_OR_URL\n"
          "\n"
          "Retro-DLP command line tool.\n"
          "\n"
          "Options:\n"
          "  -h, --help       Show this help.\n"
          "  -V, --version    Show version and build platform.\n"
          "      --no-download VIDEO_ID_OR_URL\n"
          "                   Resolve and print media JSON without downloading.\n"
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

static int resolve_argument(const char *input, int no_download) {
  YTMediaRequest media;
  YTStatus status;
  char video_id[12];
  char destination[32];
  long http_status;
  int64_t bytes_written;
  int failed;

  if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
    fprintf(stderr, "retro-dlp: could not initialize libcurl\n");
    return 1;
  }
  status = yt_resolve_video(input, &media);
  if (status != YT_OK) {
    fprintf(stderr, "retro-dlp: %s\n", yt_status_string(status));
    curl_global_cleanup();
    return 1;
  }
  if (no_download) {
    failed = print_media_request(&media);
    yt_media_request_free(&media);
    curl_global_cleanup();
    if (failed)
      fprintf(stderr, "retro-dlp: could not create result JSON\n");
    return failed;
  }
  if (yt_extract_video_id(input, video_id) != YT_OK ||
      snprintf(destination, sizeof(destination), "%s.mp4", video_id) >=
          (int)sizeof(destination)) {
    yt_media_request_free(&media);
    curl_global_cleanup();
    return 1;
  }
  fprintf(stderr, "retro-dlp: downloading to %s\n", destination);
  status = yt_http_download(media.url, media.user_agent, destination,
                            &http_status, &bytes_written);
  yt_media_request_free(&media);
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

int retro_dlp_run(int argc, char **argv) {
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

  if (argc == 2 && strcmp(argv[1], "--test") == 0) {
    int result;
    if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
      fprintf(stderr, "retro-dlp: could not initialize libcurl\n");
      return 1;
    }
    result = retro_dlp_run_self_tests();
    curl_global_cleanup();
    return result;
  }

  if (argc == 3 && strcmp(argv[1], "assets") == 0)
    return run_asset_command(argv[2]);

  if (argc == 3 && strcmp(argv[1], "--no-download") == 0)
    return resolve_argument(argv[2], 1);

  if (argc == 2 && argv[1][0] != '-')
    return resolve_argument(argv[1], 0);

  fprintf(stderr, "retro-dlp: unsupported arguments\n");
  print_usage(stderr);
  return 2;
}
