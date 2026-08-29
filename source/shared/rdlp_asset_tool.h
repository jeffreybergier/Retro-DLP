#ifndef RETRO_DLP_RDLP_ASSET_TOOL_H
#define RETRO_DLP_RDLP_ASSET_TOOL_H

#define RDLP_ASSET_TOOL_VERSION "0.8.0"

typedef enum {
  RDLP_ASSET_TOOL_OK = 0,
  RDLP_ASSET_TOOL_MISSING,
  RDLP_ASSET_TOOL_CORRUPT,
  RDLP_ASSET_TOOL_NETWORK,
  RDLP_ASSET_TOOL_HTTP,
  RDLP_ASSET_TOOL_STORAGE,
  RDLP_ASSET_TOOL_OUT_OF_MEMORY
} RDLPAssetToolStatus;

typedef struct {
  int installed;
  int core_valid;
  int lib_valid;
  char root[4096];
} RDLPAssetToolInfo;

RDLPAssetToolStatus rdlp_asset_tool_inspect(const char *root,
                                            RDLPAssetToolInfo *info);
RDLPAssetToolStatus rdlp_asset_tool_install(const char *root);
RDLPAssetToolStatus rdlp_asset_tool_remove(const char *root);
const char *rdlp_asset_tool_status_string(RDLPAssetToolStatus status);

#endif
