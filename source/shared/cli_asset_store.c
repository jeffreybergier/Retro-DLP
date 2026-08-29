#include "cli_asset_store.h"

#include <stdlib.h>
#include <string.h>

static CLIAssetStatus cli_cache_root(char *buffer, size_t buffer_size) {
  static const char suffix[] = "/.retro-dlp/cache";
  const char *home = getenv("HOME");
  size_t home_length;
  if (buffer == NULL || buffer_size == 0 || home == NULL || home[0] != '/')
    return RDLP_ASSET_TOOL_STORAGE;
  home_length = strlen(home);
  while (home_length > 1 && home[home_length - 1] == '/')
    --home_length;
  if (home_length + sizeof(suffix) > buffer_size)
    return RDLP_ASSET_TOOL_STORAGE;
  memcpy(buffer, home, home_length);
  memcpy(buffer + home_length, suffix, sizeof(suffix));
  return RDLP_ASSET_TOOL_OK;
}

CLIAssetStatus cli_asset_store_inspect(CLIAssetInfo *info) {
  char root[4096];
  if (cli_cache_root(root, sizeof(root)) != RDLP_ASSET_TOOL_OK) {
    if (info != NULL)
      memset(info, 0, sizeof(*info));
    return RDLP_ASSET_TOOL_STORAGE;
  }
  return rdlp_asset_tool_inspect(root, info);
}

CLIAssetStatus cli_asset_store_install(void) {
  char root[4096];
  if (cli_cache_root(root, sizeof(root)) != RDLP_ASSET_TOOL_OK)
    return RDLP_ASSET_TOOL_STORAGE;
  return rdlp_asset_tool_install(root);
}

CLIAssetStatus cli_asset_store_remove(void) {
  char root[4096];
  if (cli_cache_root(root, sizeof(root)) != RDLP_ASSET_TOOL_OK)
    return RDLP_ASSET_TOOL_STORAGE;
  return rdlp_asset_tool_remove(root);
}
