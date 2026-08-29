#include "cli_assets.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <curl/curl.h>

#include "cJSON.h"
#include "yt_ejs_assets.h"

const char *cli_ejs_asset_version(void) { return YT_EJS_ASSET_VERSION; }

static int print_asset_result(const char *action, YTEJSAssetsStatus status) {
  YTEJSAssetsInfo info;
  YTEJSAssetsStatus inspect_status = yt_ejs_assets_inspect(&info);
  cJSON *document = cJSON_CreateObject();
  char *json;
  if (document == NULL)
    return 1;
  if (!cJSON_AddStringToObject(document, "action", action) ||
      !cJSON_AddStringToObject(document, "status",
                              yt_ejs_assets_status_string(status)) ||
      !cJSON_AddStringToObject(document, "version", YT_EJS_ASSET_VERSION) ||
      !cJSON_AddBoolToObject(document, "installed", info.installed) ||
      !cJSON_AddBoolToObject(document, "coreValid", info.core_valid) ||
      !cJSON_AddBoolToObject(document, "libValid", info.lib_valid) ||
      !cJSON_AddStringToObject(document, "root",
                              info.root[0] == '\0' ? "" : info.root) ||
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

int cli_run_asset_command(const char *command) {
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
