#ifndef RETRO_DLP_YT_EJS_ASSETS_H
#define RETRO_DLP_YT_EJS_ASSETS_H

#include <stddef.h>

#include "retrodlp/assets.h"

#define YT_EJS_ASSET_VERSION RDLP_EJS_ASSET_VERSION

typedef enum {
  YT_EJS_ASSETS_OK = 0,
  YT_EJS_ASSETS_MISSING,
  YT_EJS_ASSETS_CORRUPT,
  YT_EJS_ASSETS_NETWORK,
  YT_EJS_ASSETS_HTTP,
  YT_EJS_ASSETS_STORAGE,
  YT_EJS_ASSETS_OUT_OF_MEMORY
} YTEJSAssetsStatus;

typedef struct {
  char *core;
  size_t core_length;
  char *lib;
  size_t lib_length;
} YTEJSAssets;

YTEJSAssetsStatus yt_ejs_assets_load_from_directory(const char *directory,
                                                    YTEJSAssets *assets);
void yt_ejs_assets_free(YTEJSAssets *assets);
const char *yt_ejs_assets_status_string(YTEJSAssetsStatus status);

#endif
