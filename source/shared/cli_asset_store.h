#ifndef RETRO_DLP_CLI_ASSET_STORE_H
#define RETRO_DLP_CLI_ASSET_STORE_H

#include "rdlp_asset_tool.h"

typedef RDLPAssetToolInfo CLIAssetInfo;
typedef RDLPAssetToolStatus CLIAssetStatus;

CLIAssetStatus cli_asset_store_inspect(CLIAssetInfo *info);
CLIAssetStatus cli_asset_store_install(void);
CLIAssetStatus cli_asset_store_remove(void);

#endif
