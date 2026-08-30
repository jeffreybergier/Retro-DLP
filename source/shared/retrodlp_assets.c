#include "retrodlp/assets.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "rdlp_curl.h"
#include "rdlp_ejs_manifest.h"
#include "yt_cache.h"
#include "yt_http.h"

#define HAS_FIELD(value, type, field)                                           \
  ((value)->struct_size >= offsetof(type, field) + sizeof((value)->field))

static const char ejs_notice[] =
    "yt-dlp-ejs " RDLP_EJS_ASSET_VERSION "\n"
    "Upstream: https://github.com/yt-dlp/ejs\n"
    "License: Unlicense\n"
    "\n"
    "lib.min.js retains the complete ISC notice for Meriyah 6.1.4 and the "
    "MIT notice for Astring 1.9.0 in its source banner.\n";

static void publish_error(rdlp_error *error, rdlp_error_code status,
                          const char *message, long http_status,
                          int transport_code) {
  rdlp_error value;
  size_t size;
  if (error == NULL)
    return;
  size = error->struct_size;
  if (size == 0 || size > sizeof(value))
    size = sizeof(value);
  memset(&value, 0, sizeof(value));
  value.struct_size = sizeof(value);
  value.code = status;
  value.http_status = http_status;
  value.transport_code = transport_code;
  value.retryable = rdlp_error_is_retryable(status);
  if (message != NULL)
    snprintf(value.message, sizeof(value.message), "%s", message);
  memcpy(error, &value, size);
}

static rdlp_error_code cache_status(YTCacheStatus status) {
  if (status == YT_CACHE_MISSING)
    return RDLP_ERROR_EJS_ASSETS_MISSING;
  if (status == YT_CACHE_OUT_OF_MEMORY)
    return RDLP_ERROR_OUT_OF_MEMORY;
  if (status == YT_CACHE_CORRUPT || status == YT_CACHE_TOO_LARGE)
    return RDLP_ERROR_EJS_ASSETS_CORRUPT;
  if (status == YT_CACHE_INVALID_ARGUMENT)
    return RDLP_ERROR_INVALID_PATH;
  return RDLP_ERROR_STORAGE_IO;
}

static rdlp_error_code write_cache_status(YTCacheStatus status) {
  if (status == YT_CACHE_OUT_OF_MEMORY)
    return RDLP_ERROR_OUT_OF_MEMORY;
  if (status == YT_CACHE_INVALID_ARGUMENT)
    return RDLP_ERROR_INVALID_ARGUMENT;
  return RDLP_ERROR_STORAGE_IO;
}

static rdlp_error_code inspect_one(const char *directory, RDLPEJSAssetKind kind) {
  const RDLPEJSAssetManifest *manifest = rdlp_ejs_asset_manifest(kind);
  char *data = NULL;
  size_t length = 0;
  YTCacheStatus status = yt_cache_read_file_at(
      directory, manifest->name, manifest->size, &data, &length);
  rdlp_error_code result;
  if (status != YT_CACHE_OK)
    return cache_status(status);
  result = rdlp_ejs_asset_data_valid(kind, data, length)
               ? RDLP_OK
               : RDLP_ERROR_EJS_ASSETS_CORRUPT;
  free(data);
  return result;
}

static const char *asset_status_message(rdlp_error_code status) {
  switch (status) {
  case RDLP_OK:
    return "EJS assets are installed";
  case RDLP_ERROR_EJS_ASSETS_MISSING:
    return "EJS assets are missing";
  case RDLP_ERROR_EJS_ASSETS_CORRUPT:
    return "EJS assets are corrupt";
  case RDLP_ERROR_INVALID_ARGUMENT:
  case RDLP_ERROR_INVALID_PATH:
    return "EJS asset directory must be absolute";
  case RDLP_ERROR_OUT_OF_MEMORY:
    return "out of memory";
  case RDLP_ERROR_STORAGE_IO:
    return "EJS asset storage error";
  case RDLP_ERROR_TRANSPORT_REQUEST_FAILED:
  case RDLP_ERROR_TRANSPORT_TIMEOUT:
  case RDLP_ERROR_TRANSPORT_INITIALIZATION_FAILED:
    return "EJS asset download failed";
  case RDLP_ERROR_HTTP_STATUS:
    return "EJS asset download returned an HTTP error";
  case RDLP_ERROR_CERTIFICATE_BUNDLE:
    return "CA certificate bundle unavailable";
  case RDLP_ERROR_CANCELLED:
    return "operation cancelled";
  default:
    return "EJS asset operation failed";
  }
}

const char *rdlp_ejs_asset_version(void) { return RDLP_EJS_ASSET_VERSION; }

rdlp_error_code rdlp_ejs_assets_inspect(const char *directory,
                                    rdlp_ejs_asset_info *info,
                                    rdlp_error *error) {
  rdlp_ejs_asset_info value;
  size_t info_size;
  rdlp_error_code core_status;
  rdlp_error_code lib_status;
  rdlp_error_code result;
  if (info == NULL || info->struct_size < sizeof(info->struct_size)) {
    if (info != NULL) {
      size_t size = info->struct_size;
      if (size == 0 || size > sizeof(*info))
        size = sizeof(*info);
      memset(info, 0, size);
    }
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  asset_status_message(RDLP_ERROR_INVALID_ARGUMENT), 0, 0);
    return RDLP_ERROR_INVALID_ARGUMENT;
  }
  if (directory == NULL || directory[0] != '/') {
    memset(info, 0, info->struct_size > sizeof(*info) ? sizeof(*info)
                                                      : info->struct_size);
    publish_error(error, RDLP_ERROR_INVALID_PATH,
                  asset_status_message(RDLP_ERROR_INVALID_ARGUMENT), 0, 0);
    return RDLP_ERROR_INVALID_PATH;
  }
  info_size = info->struct_size;
  if (info_size > sizeof(value))
    info_size = sizeof(value);
  memset(&value, 0, sizeof(value));
  value.struct_size = sizeof(value);
  core_status = inspect_one(directory, RDLP_EJS_ASSET_CORE);
  lib_status = inspect_one(directory, RDLP_EJS_ASSET_LIB);
  value.core_valid = core_status == RDLP_OK;
  value.lib_valid = lib_status == RDLP_OK;
  value.installed = value.core_valid && value.lib_valid;
  if (core_status == RDLP_OK && lib_status == RDLP_OK)
    result = RDLP_OK;
  else if (core_status == RDLP_ERROR_EJS_ASSETS_CORRUPT ||
           lib_status == RDLP_ERROR_EJS_ASSETS_CORRUPT)
    result = RDLP_ERROR_EJS_ASSETS_CORRUPT;
  else if (core_status == RDLP_ERROR_OUT_OF_MEMORY ||
           lib_status == RDLP_ERROR_OUT_OF_MEMORY)
    result = RDLP_ERROR_OUT_OF_MEMORY;
  else if ((core_status != RDLP_OK &&
            core_status != RDLP_ERROR_EJS_ASSETS_MISSING) ||
           (lib_status != RDLP_OK &&
            lib_status != RDLP_ERROR_EJS_ASSETS_MISSING))
    result = RDLP_ERROR_STORAGE_IO;
  else
    result = RDLP_ERROR_EJS_ASSETS_MISSING;
  memcpy(info, &value, info_size);
  publish_error(error, result, asset_status_message(result), 0, 0);
  return result;
}

static rdlp_error_code download_one(YTHttpSession *session,
                                RDLPEJSAssetKind kind,
                                YTHttpResponse *response) {
  const RDLPEJSAssetManifest *manifest = rdlp_ejs_asset_manifest(kind);
  YTStatus status =
      yt_http_session_get(session, manifest->url, manifest->size, response);
  if (status == YT_ERR_OUT_OF_MEMORY)
    return RDLP_ERROR_OUT_OF_MEMORY;
  if (status == YT_ERR_CERTIFICATE_BUNDLE)
    return RDLP_ERROR_CERTIFICATE_BUNDLE;
  if (status == YT_ERR_CANCELLED)
    return RDLP_ERROR_CANCELLED;
  if (status == YT_ERR_HTTP)
    return RDLP_ERROR_HTTP_STATUS;
  if (status == YT_ERR_RESPONSE_TOO_LARGE)
    return RDLP_ERROR_RESPONSE_TOO_LARGE;
  if (status == YT_ERR_TRANSPORT_TIMEOUT)
    return RDLP_ERROR_TRANSPORT_TIMEOUT;
  if (status == YT_ERR_INVALID_RESPONSE)
    return RDLP_ERROR_EJS_ASSETS_CORRUPT;
  if (status != YT_OK)
    return RDLP_ERROR_TRANSPORT_REQUEST_FAILED;
  if (response->status != 200) {
    yt_http_response_free(response);
    return RDLP_ERROR_HTTP_STATUS;
  }
  if (!rdlp_ejs_asset_data_valid(kind, response->data, response->length)) {
    yt_http_response_free(response);
    return RDLP_ERROR_EJS_ASSETS_CORRUPT;
  }
  return RDLP_OK;
}

rdlp_error_code rdlp_ejs_assets_install(const char *directory,
                                    const rdlp_ejs_asset_options *options,
                                    rdlp_error *error) {
  YTHttpSessionConfig session_config;
  rdlp_transport transport;
  YTHttpSession *session = NULL;
  YTHttpResponse core;
  YTHttpResponse lib;
  YTHttpDiagnostic diagnostic;
  const RDLPEJSAssetManifest *core_manifest =
      rdlp_ejs_asset_manifest(RDLP_EJS_ASSET_CORE);
  const RDLPEJSAssetManifest *lib_manifest =
      rdlp_ejs_asset_manifest(RDLP_EJS_ASSET_LIB);
  rdlp_error_code result;
  YTCacheStatus write_status;
  YTStatus session_status;
  int owns_curl = 0;
  if (options != NULL &&
      options->struct_size < sizeof(options->struct_size)) {
    publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                  asset_status_message(RDLP_ERROR_INVALID_ARGUMENT), 0, 0);
    return RDLP_ERROR_INVALID_ARGUMENT;
  }
  if (directory == NULL || directory[0] != '/') {
    publish_error(error, RDLP_ERROR_INVALID_PATH,
                  asset_status_message(RDLP_ERROR_INVALID_ARGUMENT), 0, 0);
    return RDLP_ERROR_INVALID_PATH;
  }
  memset(&session_config, 0, sizeof(session_config));
  session_config.timeout_milliseconds = 60000UL;
  memset(&transport, 0, sizeof(transport));
  memset(&core, 0, sizeof(core));
  memset(&lib, 0, sizeof(lib));
  memset(&diagnostic, 0, sizeof(diagnostic));
  if (options != NULL) {
    if (HAS_FIELD(options, rdlp_ejs_asset_options, ca_bundle_path))
      session_config.ca_bundle_path = options->ca_bundle_path;
    if (HAS_FIELD(options, rdlp_ejs_asset_options,
                  network_timeout_milliseconds) &&
        options->network_timeout_milliseconds != 0)
      session_config.timeout_milliseconds =
          options->network_timeout_milliseconds;
    if (HAS_FIELD(options, rdlp_ejs_asset_options, cancel_callback))
      session_config.cancel_callback = options->cancel_callback;
    if (HAS_FIELD(options, rdlp_ejs_asset_options, callback_context))
      session_config.cancel_opaque = options->callback_context;
    if (HAS_FIELD(options, rdlp_ejs_asset_options, transport) &&
        options->transport != NULL) {
      if (!HAS_FIELD(options->transport, rdlp_transport, send) ||
          options->transport->send == NULL) {
        publish_error(error, RDLP_ERROR_INVALID_ARGUMENT,
                      "transport structure is invalid", 0, 0);
        return RDLP_ERROR_INVALID_ARGUMENT;
      }
      transport.struct_size = sizeof(transport);
      transport.send = options->transport->send;
      if (HAS_FIELD(options->transport, rdlp_transport, context))
        transport.context = options->transport->context;
      session_config.transport = &transport;
    }
  }
  if (session_config.ca_bundle_path != NULL &&
      session_config.ca_bundle_path[0] != '/') {
    publish_error(error, RDLP_ERROR_INVALID_PATH,
                  "CA certificate bundle path must be absolute", 0, 0);
    return RDLP_ERROR_INVALID_PATH;
  }
  if (session_config.transport == NULL) {
    if (!rdlp_curl_acquire()) {
      publish_error(error, RDLP_ERROR_TRANSPORT_INITIALIZATION_FAILED,
                    "could not initialize default HTTP transport", 0, 0);
      return RDLP_ERROR_TRANSPORT_INITIALIZATION_FAILED;
    }
    owns_curl = 1;
  }
  session_status = yt_http_session_create_with_config(&session_config, &session);
  if (session_status != YT_OK) {
    if (owns_curl)
      rdlp_curl_release();
    result = session_status == YT_ERR_OUT_OF_MEMORY
                 ? RDLP_ERROR_OUT_OF_MEMORY
                 : RDLP_ERROR_TRANSPORT_REQUEST_FAILED;
    publish_error(error, result,
                  result == RDLP_ERROR_OUT_OF_MEMORY
                      ? "out of memory"
                      : "could not initialize EJS asset transport",
                  0, 0);
    return result;
  }
  result = download_one(session, RDLP_EJS_ASSET_CORE, &core);
  if (result != RDLP_OK)
    goto finished;
  result = download_one(session, RDLP_EJS_ASSET_LIB, &lib);
  if (result != RDLP_OK)
    goto finished;
  write_status = yt_cache_write_file_atomic_at(
      directory, core_manifest->name, core.data, core.length);
  if (write_status == YT_CACHE_OK)
    write_status = yt_cache_write_file_atomic_at(
        directory, lib_manifest->name, lib.data, lib.length);
  if (write_status == YT_CACHE_OK)
    write_status = yt_cache_write_file_atomic_at(
        directory, "NOTICE.txt", ejs_notice, sizeof(ejs_notice) - 1);
  result = write_status == YT_CACHE_OK ? RDLP_OK
                                      : write_cache_status(write_status);

finished:
  yt_http_session_diagnostic(session, &diagnostic);
  yt_http_response_free(&core);
  yt_http_response_free(&lib);
  yt_http_session_destroy(session);
  if (owns_curl)
    rdlp_curl_release();
  publish_error(error, result, asset_status_message(result),
                diagnostic.http_status, diagnostic.transport_code);
  return result;
}

rdlp_error_code rdlp_ejs_assets_remove(const char *directory, rdlp_error *error) {
  const RDLPEJSAssetManifest *core =
      rdlp_ejs_asset_manifest(RDLP_EJS_ASSET_CORE);
  const RDLPEJSAssetManifest *lib =
      rdlp_ejs_asset_manifest(RDLP_EJS_ASSET_LIB);
  YTCacheStatus core_status;
  YTCacheStatus lib_status;
  YTCacheStatus notice_status;
  rdlp_error_code result;
  if (directory == NULL || directory[0] != '/') {
    publish_error(error, RDLP_ERROR_INVALID_PATH,
                  asset_status_message(RDLP_ERROR_INVALID_ARGUMENT), 0, 0);
    return RDLP_ERROR_INVALID_PATH;
  }
  core_status = yt_cache_remove_file_at(directory, core->name);
  lib_status = yt_cache_remove_file_at(directory, lib->name);
  notice_status = yt_cache_remove_file_at(directory, "NOTICE.txt");
  result = (core_status == YT_CACHE_OK || core_status == YT_CACHE_MISSING) &&
                   (lib_status == YT_CACHE_OK ||
                    lib_status == YT_CACHE_MISSING) &&
                   (notice_status == YT_CACHE_OK ||
                    notice_status == YT_CACHE_MISSING)
               ? RDLP_OK
               : RDLP_ERROR_STORAGE_IO;
  publish_error(error, result, asset_status_message(result), 0, 0);
  return result;
}
