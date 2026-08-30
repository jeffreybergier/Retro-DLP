#include "cli_asset_store.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "platform.h"

static CLIAssetStatus cli_asset_directory(char *buffer, size_t buffer_size) {
  static const char suffix[] = "/.retro-dlp/cache/assets/ejs/";
  const char *home = getenv("HOME");
  size_t home_length;
  if (buffer == NULL || buffer_size == 0 || home == NULL || home[0] != '/')
    return RDLP_STATUS_STORAGE;
  home_length = strlen(home);
  while (home_length > 1 && home[home_length - 1] == '/')
    --home_length;
  if (home_length + sizeof(suffix) + strlen(rdlp_ejs_asset_version()) >
      buffer_size)
    return RDLP_STATUS_STORAGE;
  memcpy(buffer, home, home_length);
  memcpy(buffer + home_length, suffix, sizeof(suffix) - 1);
  memcpy(buffer + home_length + sizeof(suffix) - 1,
         rdlp_ejs_asset_version(), strlen(rdlp_ejs_asset_version()) + 1);
  return RDLP_STATUS_OK;
}

CLIAssetStatus cli_asset_store_inspect(CLIAssetInfo *info) {
  rdlp_ejs_asset_info public_info;
  rdlp_status status;
  if (info == NULL)
    return RDLP_STATUS_INVALID_ARGUMENT;
  memset(info, 0, sizeof(*info));
  if (cli_asset_directory(info->root, sizeof(info->root)) != RDLP_STATUS_OK) {
    if (info != NULL)
      memset(info, 0, sizeof(*info));
    return RDLP_STATUS_STORAGE;
  }
  memset(&public_info, 0, sizeof(public_info));
  public_info.struct_size = sizeof(public_info);
  status = rdlp_ejs_assets_inspect(info->root, &public_info, NULL);
  info->installed = public_info.installed;
  info->core_valid = public_info.core_valid;
  info->lib_valid = public_info.lib_valid;
  return status;
}

CLIAssetStatus cli_asset_store_install(void) {
  rdlp_ejs_asset_options options;
  char directory[4096];
  char ca_bundle[4096];
  if (cli_asset_directory(directory, sizeof(directory)) != RDLP_STATUS_OK)
    return RDLP_STATUS_STORAGE;
  memset(&options, 0, sizeof(options));
  memset(ca_bundle, 0, sizeof(ca_bundle));
  options.struct_size = sizeof(options);
  if (retro_dlp_default_ca_bundle_path(ca_bundle, sizeof(ca_bundle)))
    options.ca_bundle_path = ca_bundle;
  return rdlp_ejs_assets_install(directory, &options, NULL);
}

CLIAssetStatus cli_asset_store_remove(void) {
  char directory[4096];
  if (cli_asset_directory(directory, sizeof(directory)) != RDLP_STATUS_OK)
    return RDLP_STATUS_STORAGE;
  return rdlp_ejs_assets_remove(directory, NULL);
}
