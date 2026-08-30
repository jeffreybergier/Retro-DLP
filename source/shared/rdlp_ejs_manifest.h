#ifndef RETRO_DLP_RDLP_EJS_MANIFEST_H
#define RETRO_DLP_RDLP_EJS_MANIFEST_H

#include <stddef.h>

#include "retrodlp/assets.h"

typedef enum {
  RDLP_EJS_ASSET_CORE = 0,
  RDLP_EJS_ASSET_LIB = 1
} RDLPEJSAssetKind;

typedef struct {
  const char *name;
  const char *url;
  size_t size;
  const char *sha256;
} RDLPEJSAssetManifest;

const RDLPEJSAssetManifest *rdlp_ejs_asset_manifest(RDLPEJSAssetKind kind);
int rdlp_ejs_asset_data_valid(RDLPEJSAssetKind kind, const void *data,
                              size_t length);

#endif
