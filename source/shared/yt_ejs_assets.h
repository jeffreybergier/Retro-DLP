#ifndef RETRO_DLP_YT_EJS_ASSETS_H
#define RETRO_DLP_YT_EJS_ASSETS_H

#include <stddef.h>

#define YT_EJS_ASSET_VERSION "0.8.0"

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

typedef struct {
  int installed;
  int core_valid;
  int lib_valid;
  char root[4096];
} YTEJSAssetsInfo;

YTEJSAssetsStatus yt_ejs_assets_inspect(YTEJSAssetsInfo *info);
YTEJSAssetsStatus yt_ejs_assets_install(void);
YTEJSAssetsStatus yt_ejs_assets_remove(void);
YTEJSAssetsStatus yt_ejs_assets_load(YTEJSAssets *assets);
void yt_ejs_assets_free(YTEJSAssets *assets);
const char *yt_ejs_assets_status_string(YTEJSAssetsStatus status);

#endif
