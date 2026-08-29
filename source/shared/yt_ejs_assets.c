#include "yt_ejs_assets.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "yt_crypto.h"
#define EJS_CORE_SIZE 6945U
#define EJS_LIB_SIZE 151561U
#define EJS_CORE_SHA256 \
  "18da6ce0758b416e7ae645084f4f8801f9f9d59d6c477c05eaa0ff94ebd8cc00"
#define EJS_LIB_SHA256 \
  "c55987fe697e5b9ee18830163f7af85327e9bb5c3e674b969d38c8d205eaa577"

static int asset_is_valid(const char *data, size_t length,
                          size_t expected_length, const char *expected_hash) {
  char actual_hash[65];

  return length == expected_length &&
         yt_crypto_sha256_hex(data, length, actual_hash) == 0 &&
         strcmp(actual_hash, expected_hash) == 0;
}

static YTEJSAssetsStatus load_direct_asset(const char *directory,
                                           const char *name,
                                           size_t expected_length,
                                           const char *expected_hash,
                                           char **data, size_t *length) {
  char path[4096];
  FILE *file;
  size_t count;
  if (directory == NULL || directory[0] != '/' ||
      snprintf(path, sizeof(path), "%s%s%s", directory,
               directory[strlen(directory) - 1] == '/' ? "" : "/", name) >=
          (int)sizeof(path))
    return YT_EJS_ASSETS_STORAGE;
  file = fopen(path, "rb");
  if (file == NULL)
    return YT_EJS_ASSETS_MISSING;
  *data = (char *)malloc(expected_length + 1);
  if (*data == NULL) {
    fclose(file);
    return YT_EJS_ASSETS_OUT_OF_MEMORY;
  }
  count = fread(*data, 1, expected_length + 1, file);
  if (ferror(file) || fclose(file) != 0 || count != expected_length ||
      !asset_is_valid(*data, count, expected_length, expected_hash)) {
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
  status = load_direct_asset(directory, "core.min.js", EJS_CORE_SIZE,
                             EJS_CORE_SHA256, &assets->core,
                             &assets->core_length);
  if (status != YT_EJS_ASSETS_OK)
    return status;
  status = load_direct_asset(directory, "lib.min.js", EJS_LIB_SIZE,
                             EJS_LIB_SHA256, &assets->lib,
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
