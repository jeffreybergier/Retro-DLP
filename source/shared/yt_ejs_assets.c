#include "yt_ejs_assets.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "yt_cache.h"
#include "yt_crypto.h"
#include "yt_http.h"

#define EJS_CORE_PATH "assets/ejs/0.8.0/core.min.js"
#define EJS_LIB_PATH "assets/ejs/0.8.0/lib.min.js"
#define EJS_NOTICE_PATH "assets/ejs/0.8.0/NOTICE.txt"
#define EJS_CORE_SIZE 6945U
#define EJS_LIB_SIZE 151561U
#define EJS_CORE_SHA256 \
  "18da6ce0758b416e7ae645084f4f8801f9f9d59d6c477c05eaa0ff94ebd8cc00"
#define EJS_LIB_SHA256 \
  "c55987fe697e5b9ee18830163f7af85327e9bb5c3e674b969d38c8d205eaa577"
#define EJS_CORE_URL                                                        \
  "https://github.com/yt-dlp/ejs/releases/download/0.8.0/"                \
  "yt.solver.core.min.js"
#define EJS_LIB_URL                                                         \
  "https://github.com/yt-dlp/ejs/releases/download/0.8.0/"                \
  "yt.solver.lib.min.js"

static const char ejs_notice[] =
    "yt-dlp-ejs 0.8.0\n"
    "Upstream: https://github.com/yt-dlp/ejs\n"
    "License: Unlicense\n"
    "\n"
    "lib.min.js retains the complete ISC notice for Meriyah 6.1.4 and the "
    "MIT notice for Astring 1.9.0 in its source banner.\n";

static int asset_is_valid(const char *data, size_t length,
                          size_t expected_length, const char *expected_hash) {
  char actual_hash[65];

  return length == expected_length &&
         yt_crypto_sha256_hex(data, length, actual_hash) == 0 &&
         strcmp(actual_hash, expected_hash) == 0;
}

static YTEJSAssetsStatus cache_status_to_asset_status(YTCacheStatus status) {
  if (status == YT_CACHE_MISSING)
    return YT_EJS_ASSETS_MISSING;
  if (status == YT_CACHE_OUT_OF_MEMORY)
    return YT_EJS_ASSETS_OUT_OF_MEMORY;
  if (status == YT_CACHE_CORRUPT || status == YT_CACHE_TOO_LARGE)
    return YT_EJS_ASSETS_CORRUPT;
  return YT_EJS_ASSETS_STORAGE;
}

static YTEJSAssetsStatus load_one(const char *path, size_t expected_length,
                                  const char *expected_hash, char **data,
                                  size_t *length) {
  YTCacheStatus status;

  status = yt_cache_read_file(path, expected_length, data, length);
  if (status != YT_CACHE_OK)
    return cache_status_to_asset_status(status);
  if (!asset_is_valid(*data, *length, expected_length, expected_hash)) {
    free(*data);
    *data = NULL;
    *length = 0;
    return YT_EJS_ASSETS_CORRUPT;
  }
  return YT_EJS_ASSETS_OK;
}

YTEJSAssetsStatus yt_ejs_assets_load(YTEJSAssets *assets) {
  YTEJSAssetsStatus status;

  if (assets == NULL)
    return YT_EJS_ASSETS_STORAGE;
  memset(assets, 0, sizeof(*assets));
  status = load_one(EJS_CORE_PATH, EJS_CORE_SIZE, EJS_CORE_SHA256,
                    &assets->core, &assets->core_length);
  if (status != YT_EJS_ASSETS_OK)
    return status;
  status = load_one(EJS_LIB_PATH, EJS_LIB_SIZE, EJS_LIB_SHA256, &assets->lib,
                    &assets->lib_length);
  if (status != YT_EJS_ASSETS_OK) {
    yt_ejs_assets_free(assets);
    return status;
  }
  return YT_EJS_ASSETS_OK;
}

void yt_ejs_assets_free(YTEJSAssets *assets) {
  if (assets == NULL)
    return;
  free(assets->core);
  free(assets->lib);
  memset(assets, 0, sizeof(*assets));
}

YTEJSAssetsStatus yt_ejs_assets_inspect(YTEJSAssetsInfo *info) {
  YTEJSAssetsStatus core_status;
  YTEJSAssetsStatus lib_status;
  char *data;
  size_t length;
  YTCacheStatus root_status;

  if (info == NULL)
    return YT_EJS_ASSETS_STORAGE;
  memset(info, 0, sizeof(*info));
  root_status = yt_cache_root(info->root, sizeof(info->root));
  if (root_status != YT_CACHE_OK)
    return cache_status_to_asset_status(root_status);

  data = NULL;
  length = 0;
  core_status = load_one(EJS_CORE_PATH, EJS_CORE_SIZE, EJS_CORE_SHA256, &data,
                         &length);
  if (core_status == YT_EJS_ASSETS_OK) {
    info->core_valid = 1;
    free(data);
  }
  data = NULL;
  length = 0;
  lib_status = load_one(EJS_LIB_PATH, EJS_LIB_SIZE, EJS_LIB_SHA256, &data,
                        &length);
  if (lib_status == YT_EJS_ASSETS_OK) {
    info->lib_valid = 1;
    free(data);
  }
  info->installed = info->core_valid && info->lib_valid;
  if (info->installed)
    return YT_EJS_ASSETS_OK;
  if (core_status == YT_EJS_ASSETS_CORRUPT ||
      lib_status == YT_EJS_ASSETS_CORRUPT)
    return YT_EJS_ASSETS_CORRUPT;
  if (core_status == YT_EJS_ASSETS_OUT_OF_MEMORY ||
      lib_status == YT_EJS_ASSETS_OUT_OF_MEMORY)
    return YT_EJS_ASSETS_OUT_OF_MEMORY;
  if ((core_status != YT_EJS_ASSETS_OK &&
       core_status != YT_EJS_ASSETS_MISSING) ||
      (lib_status != YT_EJS_ASSETS_OK &&
       lib_status != YT_EJS_ASSETS_MISSING))
    return YT_EJS_ASSETS_STORAGE;
  return YT_EJS_ASSETS_MISSING;
}

static YTEJSAssetsStatus download_asset(const char *url, size_t expected_length,
                                        const char *expected_hash,
                                        YTHttpResponse *response) {
  YTStatus status;

  status = yt_http_get(url, expected_length, response);
  if (status != YT_OK)
    return status == YT_ERR_OUT_OF_MEMORY ? YT_EJS_ASSETS_OUT_OF_MEMORY
                                         : YT_EJS_ASSETS_NETWORK;
  if (response->status != 200) {
    yt_http_response_free(response);
    return YT_EJS_ASSETS_HTTP;
  }
  if (!asset_is_valid(response->data, response->length, expected_length,
                      expected_hash)) {
    yt_http_response_free(response);
    return YT_EJS_ASSETS_CORRUPT;
  }
  return YT_EJS_ASSETS_OK;
}

YTEJSAssetsStatus yt_ejs_assets_install(void) {
  YTHttpResponse core;
  YTHttpResponse lib;
  YTEJSAssetsStatus status;
  YTCacheStatus cache_status;

  memset(&core, 0, sizeof(core));
  memset(&lib, 0, sizeof(lib));
  status = download_asset(EJS_CORE_URL, EJS_CORE_SIZE, EJS_CORE_SHA256, &core);
  if (status != YT_EJS_ASSETS_OK)
    return status;
  status = download_asset(EJS_LIB_URL, EJS_LIB_SIZE, EJS_LIB_SHA256, &lib);
  if (status != YT_EJS_ASSETS_OK) {
    yt_http_response_free(&core);
    return status;
  }
  cache_status =
      yt_cache_write_file_atomic(EJS_CORE_PATH, core.data, core.length);
  if (cache_status == YT_CACHE_OK)
    cache_status =
        yt_cache_write_file_atomic(EJS_LIB_PATH, lib.data, lib.length);
  if (cache_status == YT_CACHE_OK)
    cache_status = yt_cache_write_file_atomic(
        EJS_NOTICE_PATH, ejs_notice, sizeof(ejs_notice) - 1);
  yt_http_response_free(&core);
  yt_http_response_free(&lib);
  if (cache_status != YT_CACHE_OK)
    return cache_status_to_asset_status(cache_status);
  return YT_EJS_ASSETS_OK;
}

YTEJSAssetsStatus yt_ejs_assets_remove(void) {
  YTCacheStatus core;
  YTCacheStatus lib;
  YTCacheStatus notice;

  core = yt_cache_remove_file(EJS_CORE_PATH);
  lib = yt_cache_remove_file(EJS_LIB_PATH);
  notice = yt_cache_remove_file(EJS_NOTICE_PATH);
  if ((core == YT_CACHE_OK || core == YT_CACHE_MISSING) &&
      (lib == YT_CACHE_OK || lib == YT_CACHE_MISSING) &&
      (notice == YT_CACHE_OK || notice == YT_CACHE_MISSING))
    return YT_EJS_ASSETS_OK;
  return YT_EJS_ASSETS_STORAGE;
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
