#ifndef RETRO_DLP_CLI_ASSET_STORE_H
#define RETRO_DLP_CLI_ASSET_STORE_H

#include "retrodlp/assets.h"

typedef struct {
  int installed;
  int core_valid;
  int lib_valid;
  char root[4096];
} CLIAssetInfo;

typedef rdlp_error_code CLIAssetStatus;

CLIAssetStatus cli_asset_store_inspect(CLIAssetInfo *info);
CLIAssetStatus cli_asset_store_install(void);
CLIAssetStatus cli_asset_store_remove(void);

#endif
