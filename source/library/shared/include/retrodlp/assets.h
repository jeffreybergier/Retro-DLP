#ifndef RETRODLP_ASSETS_H
#define RETRODLP_ASSETS_H

#include <stddef.h>

#include "retrodlp.h"

#ifdef __cplusplus
extern "C" {
#endif

#define RDLP_EJS_ASSET_VERSION "0.8.0"

typedef struct {
  size_t struct_size;
  int installed;
  int core_valid;
  int lib_valid;
} rdlp_ejs_asset_info;

typedef struct {
  size_t struct_size;
  const char *ca_bundle_path;
  unsigned long network_timeout_milliseconds;
  rdlp_cancel_callback cancel_callback;
  void *callback_context;
  const rdlp_transport *transport;
} rdlp_ejs_asset_options;

RDLP_API const char *rdlp_ejs_asset_version(void);
RDLP_API rdlp_error_code rdlp_ejs_assets_inspect(
    const char *directory, rdlp_ejs_asset_info *info, rdlp_error *error);
RDLP_API rdlp_error_code rdlp_ejs_assets_install(
    const char *directory, const rdlp_ejs_asset_options *options,
    rdlp_error *error);
RDLP_API rdlp_error_code rdlp_ejs_assets_remove(const char *directory,
                                                rdlp_error *error);

#ifdef __cplusplus
}
#endif

#endif
