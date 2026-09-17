#include "cli_assets.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "cli_asset_store.h"

const char *cli_ejs_asset_version(void) { return rdlp_ejs_asset_version(); }

static int print_asset_result(const char *action, CLIAssetStatus status) {
  CLIAssetInfo info;
  CLIAssetStatus inspect_status = cli_asset_store_inspect(&info);
  cJSON *document = cJSON_CreateObject();
  char *json;
  if (document == NULL)
    return 1;
  if (!cJSON_AddStringToObject(document, "action", action) ||
      !cJSON_AddStringToObject(document, "status", rdlp_error_name(status)) ||
      !cJSON_AddNumberToObject(document, "code", (double)status) ||
      !cJSON_AddStringToObject(document, "version",
                              rdlp_ejs_asset_version()) ||
      !cJSON_AddBoolToObject(document, "installed", info.installed) ||
      !cJSON_AddBoolToObject(document, "coreValid", info.core_valid) ||
      !cJSON_AddBoolToObject(document, "libValid", info.lib_valid) ||
      !cJSON_AddStringToObject(document, "root",
                              info.root[0] == '\0' ? "" : info.root) ||
      !cJSON_AddStringToObject(document, "inspection",
                              rdlp_error_name(inspect_status))) {
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
  CLIAssetStatus status;
  CLIAssetInfo info;
  int failed;
  if (strcmp(command, "status") == 0) {
    status = cli_asset_store_inspect(&info);
    return print_asset_result("status", status);
  }
  if (strcmp(command, "remove") == 0) {
    status = cli_asset_store_remove();
    failed = print_asset_result("remove", status);
    return failed || status != RDLP_OK;
  }
  if (strcmp(command, "install") == 0) {
    status = cli_asset_store_install();
    failed = print_asset_result("install", status);
    return failed || status != RDLP_OK;
  }
  fprintf(stderr, "retro-dlp: unsupported asset command\n");
  return 2;
}
