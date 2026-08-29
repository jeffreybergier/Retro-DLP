#include "rdlp_asset_tool.h"

#include <stdlib.h>
#include <string.h>

#include <curl/curl.h>

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

static RDLPAssetToolStatus cache_status(YTCacheStatus status) {
  if (status == YT_CACHE_MISSING)
    return RDLP_ASSET_TOOL_MISSING;
  if (status == YT_CACHE_OUT_OF_MEMORY)
    return RDLP_ASSET_TOOL_OUT_OF_MEMORY;
  if (status == YT_CACHE_CORRUPT || status == YT_CACHE_TOO_LARGE)
    return RDLP_ASSET_TOOL_CORRUPT;
  return RDLP_ASSET_TOOL_STORAGE;
}

static int asset_is_valid(const char *data, size_t length,
                          size_t expected_length, const char *expected_hash) {
  char actual_hash[65];
  return length == expected_length &&
         yt_crypto_sha256_hex(data, length, actual_hash) == 0 &&
         strcmp(actual_hash, expected_hash) == 0;
}

static RDLPAssetToolStatus load_one(const char *root, const char *path,
                                    size_t expected_length,
                                    const char *expected_hash) {
  char *data = NULL;
  size_t length = 0;
  YTCacheStatus status =
      yt_cache_read_file_at(root, path, expected_length, &data, &length);
  if (status != YT_CACHE_OK)
    return cache_status(status);
  if (!asset_is_valid(data, length, expected_length, expected_hash)) {
    free(data);
    return RDLP_ASSET_TOOL_CORRUPT;
  }
  free(data);
  return RDLP_ASSET_TOOL_OK;
}

RDLPAssetToolStatus rdlp_asset_tool_inspect(const char *root,
                                            RDLPAssetToolInfo *info) {
  RDLPAssetToolStatus core_status;
  RDLPAssetToolStatus lib_status;
  size_t root_length;
  if (root == NULL || info == NULL)
    return RDLP_ASSET_TOOL_STORAGE;
  memset(info, 0, sizeof(*info));
  root_length = strlen(root);
  if (root_length >= sizeof(info->root))
    return RDLP_ASSET_TOOL_STORAGE;
  memcpy(info->root, root, root_length + 1);
  core_status = load_one(root, EJS_CORE_PATH, EJS_CORE_SIZE, EJS_CORE_SHA256);
  lib_status = load_one(root, EJS_LIB_PATH, EJS_LIB_SIZE, EJS_LIB_SHA256);
  info->core_valid = core_status == RDLP_ASSET_TOOL_OK;
  info->lib_valid = lib_status == RDLP_ASSET_TOOL_OK;
  info->installed = info->core_valid && info->lib_valid;
  if (info->installed)
    return RDLP_ASSET_TOOL_OK;
  if (core_status == RDLP_ASSET_TOOL_CORRUPT ||
      lib_status == RDLP_ASSET_TOOL_CORRUPT)
    return RDLP_ASSET_TOOL_CORRUPT;
  if (core_status == RDLP_ASSET_TOOL_OUT_OF_MEMORY ||
      lib_status == RDLP_ASSET_TOOL_OUT_OF_MEMORY)
    return RDLP_ASSET_TOOL_OUT_OF_MEMORY;
  if ((core_status != RDLP_ASSET_TOOL_OK &&
       core_status != RDLP_ASSET_TOOL_MISSING) ||
      (lib_status != RDLP_ASSET_TOOL_OK &&
       lib_status != RDLP_ASSET_TOOL_MISSING))
    return RDLP_ASSET_TOOL_STORAGE;
  return RDLP_ASSET_TOOL_MISSING;
}

static RDLPAssetToolStatus download_asset(const char *url,
                                          size_t expected_length,
                                          const char *expected_hash,
                                          YTHttpSession *session,
                                          YTHttpResponse *response) {
  YTStatus status =
      yt_http_session_get(session, url, expected_length, response);
  if (status != YT_OK)
    return status == YT_ERR_OUT_OF_MEMORY ? RDLP_ASSET_TOOL_OUT_OF_MEMORY
                                         : RDLP_ASSET_TOOL_NETWORK;
  if (response->status != 200) {
    yt_http_response_free(response);
    return RDLP_ASSET_TOOL_HTTP;
  }
  if (!asset_is_valid(response->data, response->length, expected_length,
                      expected_hash)) {
    yt_http_response_free(response);
    return RDLP_ASSET_TOOL_CORRUPT;
  }
  return RDLP_ASSET_TOOL_OK;
}

RDLPAssetToolStatus rdlp_asset_tool_install(const char *root) {
  YTHttpResponse core;
  YTHttpResponse lib;
  RDLPAssetToolStatus status;
  YTCacheStatus write_status;
  YTHttpSessionConfig session_config;
  YTHttpSession *session;
  if (root == NULL || root[0] != '/')
    return RDLP_ASSET_TOOL_STORAGE;
  if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK)
    return RDLP_ASSET_TOOL_NETWORK;
  memset(&core, 0, sizeof(core));
  memset(&lib, 0, sizeof(lib));
  memset(&session_config, 0, sizeof(session_config));
  session = NULL;
  if (yt_http_session_create_with_config(&session_config, &session) != YT_OK) {
    curl_global_cleanup();
    return RDLP_ASSET_TOOL_NETWORK;
  }
  status = download_asset(EJS_CORE_URL, EJS_CORE_SIZE, EJS_CORE_SHA256, session,
                          &core);
  if (status != RDLP_ASSET_TOOL_OK)
    goto finished;
  status = download_asset(EJS_LIB_URL, EJS_LIB_SIZE, EJS_LIB_SHA256, session,
                          &lib);
  if (status != RDLP_ASSET_TOOL_OK) {
    yt_http_response_free(&core);
    goto finished;
  }
  write_status = yt_cache_write_file_atomic_at(root, EJS_CORE_PATH, core.data,
                                               core.length);
  if (write_status == YT_CACHE_OK)
    write_status = yt_cache_write_file_atomic_at(root, EJS_LIB_PATH, lib.data,
                                                 lib.length);
  if (write_status == YT_CACHE_OK)
    write_status = yt_cache_write_file_atomic_at(
        root, EJS_NOTICE_PATH, ejs_notice, sizeof(ejs_notice) - 1);
  yt_http_response_free(&core);
  yt_http_response_free(&lib);
  status = write_status == YT_CACHE_OK ? RDLP_ASSET_TOOL_OK
                                      : cache_status(write_status);
finished:
  yt_http_session_destroy(session);
  curl_global_cleanup();
  return status;
}

RDLPAssetToolStatus rdlp_asset_tool_remove(const char *root) {
  YTCacheStatus core;
  YTCacheStatus lib;
  YTCacheStatus notice;
  if (root == NULL || root[0] != '/')
    return RDLP_ASSET_TOOL_STORAGE;
  core = yt_cache_remove_file_at(root, EJS_CORE_PATH);
  lib = yt_cache_remove_file_at(root, EJS_LIB_PATH);
  notice = yt_cache_remove_file_at(root, EJS_NOTICE_PATH);
  if ((core == YT_CACHE_OK || core == YT_CACHE_MISSING) &&
      (lib == YT_CACHE_OK || lib == YT_CACHE_MISSING) &&
      (notice == YT_CACHE_OK || notice == YT_CACHE_MISSING))
    return RDLP_ASSET_TOOL_OK;
  return RDLP_ASSET_TOOL_STORAGE;
}

const char *rdlp_asset_tool_status_string(RDLPAssetToolStatus status) {
  switch (status) {
  case RDLP_ASSET_TOOL_OK:
    return "ok";
  case RDLP_ASSET_TOOL_MISSING:
    return "missing";
  case RDLP_ASSET_TOOL_CORRUPT:
    return "corrupt";
  case RDLP_ASSET_TOOL_NETWORK:
    return "network";
  case RDLP_ASSET_TOOL_HTTP:
    return "http";
  case RDLP_ASSET_TOOL_STORAGE:
    return "storage";
  case RDLP_ASSET_TOOL_OUT_OF_MEMORY:
    return "out_of_memory";
  }
  return "unknown";
}
