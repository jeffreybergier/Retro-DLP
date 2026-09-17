#include "rdlp_ejs_manifest.h"

#include <string.h>

#include "yt_crypto.h"

static const RDLPEJSAssetManifest manifests[] = {
    {"core.min.js",
     "https://github.com/yt-dlp/ejs/releases/download/"
     RDLP_EJS_ASSET_VERSION "/"
     "yt.solver.core.min.js",
     6945U,
     "18da6ce0758b416e7ae645084f4f8801f9f9d59d6c477c05eaa0ff94ebd8cc00"},
    {"lib.min.js",
     "https://github.com/yt-dlp/ejs/releases/download/"
     RDLP_EJS_ASSET_VERSION "/"
     "yt.solver.lib.min.js",
     151561U,
     "c55987fe697e5b9ee18830163f7af85327e9bb5c3e674b969d38c8d205eaa577"}};

const RDLPEJSAssetManifest *rdlp_ejs_asset_manifest(RDLPEJSAssetKind kind) {
  if ((int)kind < 0 || (size_t)kind >= sizeof(manifests) / sizeof(manifests[0]))
    return NULL;
  return &manifests[(size_t)kind];
}

int rdlp_ejs_asset_data_valid(RDLPEJSAssetKind kind, const void *data,
                              size_t length) {
  const RDLPEJSAssetManifest *manifest = rdlp_ejs_asset_manifest(kind);
  char actual_hash[65];
  return manifest != NULL && length == manifest->size &&
         yt_crypto_sha256_hex(data, length, actual_hash) == 0 &&
         strcmp(actual_hash, manifest->sha256) == 0;
}
