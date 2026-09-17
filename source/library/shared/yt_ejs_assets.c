#include "yt_ejs_assets.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rdlp_ejs_manifest.h"

static YTEJSAssetsStatus load_direct_asset(const char *directory,
                                           RDLPEJSAssetKind kind,
                                           char **data, size_t *length) {
  const RDLPEJSAssetManifest *manifest = rdlp_ejs_asset_manifest(kind);
  char path[4096];
  FILE *file;
  size_t count;
  if (directory == NULL || directory[0] != '/' ||
      snprintf(path, sizeof(path), "%s%s%s", directory,
               directory[strlen(directory) - 1] == '/' ? "" : "/",
               manifest->name) >=
          (int)sizeof(path))
    return YT_EJS_ASSETS_STORAGE;
  file = fopen(path, "rb");
  if (file == NULL)
    return YT_EJS_ASSETS_MISSING;
  *data = (char *)malloc(manifest->size + 1);
  if (*data == NULL) {
    fclose(file);
    return YT_EJS_ASSETS_OUT_OF_MEMORY;
  }
  count = fread(*data, 1, manifest->size + 1, file);
  if (ferror(file) || fclose(file) != 0 ||
      !rdlp_ejs_asset_data_valid(kind, *data, count)) {
    free(*data);
    *data = NULL;
    return YT_EJS_ASSETS_CORRUPT;
  }
  (*data)[count] = '\0';
  *length = count;
  return YT_EJS_ASSETS_OK;
}

YTEJSAssetsStatus yt_ejs_assets_load_from_directory(const char *directory,
                                                    YTEJSAssets *assets) {
  YTEJSAssetsStatus status;
  if (assets == NULL)
    return YT_EJS_ASSETS_STORAGE;
  memset(assets, 0, sizeof(*assets));
  status = load_direct_asset(directory, RDLP_EJS_ASSET_CORE, &assets->core,
                             &assets->core_length);
  if (status != YT_EJS_ASSETS_OK)
    return status;
  status = load_direct_asset(directory, RDLP_EJS_ASSET_LIB, &assets->lib,
                             &assets->lib_length);
  if (status != YT_EJS_ASSETS_OK)
    yt_ejs_assets_free(assets);
  return status;
}

void yt_ejs_assets_free(YTEJSAssets *assets) {
  if (assets == NULL)
    return;
  free(assets->core);
  free(assets->lib);
  memset(assets, 0, sizeof(*assets));
}

const char *yt_ejs_assets_status_string(YTEJSAssetsStatus status) {
  switch (status) {
    case YT_EJS_ASSETS_OK:
      return "ok";
    case YT_EJS_ASSETS_MISSING:
      return "missing";
    case YT_EJS_ASSETS_CORRUPT:
      return "corrupt";
    case YT_EJS_ASSETS_NETWORK:
      return "network_error";
    case YT_EJS_ASSETS_HTTP:
      return "http_error";
    case YT_EJS_ASSETS_STORAGE:
      return "storage_error";
    case YT_EJS_ASSETS_OUT_OF_MEMORY:
      return "out_of_memory";
  }
  return "unknown";
}
