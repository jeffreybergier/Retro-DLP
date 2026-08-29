# Retro-DLP C API

The supported library interface is declared by
`include/retrodlp/retrodlp.h`. Applications must not include headers from
`source/shared`; those headers and all `yt_*` symbols are private and may
change without notice.

The API is currently provisional. `RDLP_VERSION_*` describes the library
release, not a promise of ABI stability.

## Context lifecycle and threading

Initialize every public configuration or option structure to zero and set its
`struct_size` before use. Passing `NULL` for the configuration or operation
options selects the documented defaults: a 20-second network timeout, the
default libcurl transport, disabled caching, no cookies, the system libcurl
trust configuration, progressive MP4 selection, and a maximum height of 720
pixels.

`rdlp_context_create` returns an owned context through its output pointer.
Destroy it with `rdlp_context_destroy`. A context accepts only one operation at
a time; reentrant use from an event callback returns `RDLP_STATUS_BUSY`.
Creation and destruction of default-transport contexts safely reference-counts
the libcurl lifecycle. Independent contexts may operate concurrently. The
one-operation rule is enforced per context and reentrant or concurrent use of
the same context returns `RDLP_STATUS_BUSY`.

The callback context, clock context, and custom transport context are borrowed.
They must remain valid until the `rdlp_context` is destroyed. Callbacks are
synchronous and run on the thread performing the operation. Configuration path
strings are copied during context creation.

`cache_directory`, `ca_bundle_path`, and `ejs_asset_directory` must be absolute
when supplied. A `NULL` cache directory disables all resolver caching. An EJS
asset directory contains the version-matched `core.min.js` and `lib.min.js`
files. Zero EJS memory and stack limits select the internal defaults. A custom
clock returns Unix seconds and is used for cache expiry, cookie validation, and
authenticated request timestamps; a `NULL` clock uses system time.

Cookie options accept either a Netscape cookie-file path or caller-owned
Netscape cookie bytes, never both. The bytes are copied into the operation's
HTTP session and need remain valid only for the public call.

## Results and ownership

Every result is owned by the caller. Destroy selections with
`rdlp_selection_destroy`, playlists with `rdlp_playlist_destroy`, and account
playlist collections with `rdlp_playlist_collection_destroy`. Strings, media
headers, and playlist entries returned by accessors are borrowed from their
parent result and remain valid until that result is destroyed. An out-of-range
accessor returns `NULL`, zero, or an empty count as appropriate.

Media index zero is the video or progressive request. For adaptive selections,
index one is the audio request. Each request includes the headers that must be
used to fetch it; the Phase 2 adapter currently supplies the resolved
`User-Agent` header. Set `include_format_inventory` to expose all formats through
the format accessors; otherwise the inventory is discarded before return.

On every failed operation, its output pointer is set to `NULL`. Destroy
functions accept `NULL`.

## Errors

An error argument is optional. When supplied, initialize it to zero and set
`struct_size`. The operation returns the same high-level status stored in the
error. `message` is intended for diagnostics, not programmatic matching.
`http_status` and `transport_code` are zero when the underlying adapter cannot
provide more detail. `retryable` is set for network and HTTP failures.

## Events and cancellation

Events are typed and contain no terminal-oriented text. Event callbacks are
informational and must not call another operation on the same context.

The cancellation callback should return nonzero to cancel. It is checked before
an operation, around custom-transport requests, during default libcurl
transfers, between playlist pages, and through the QuickJS interrupt handler. A
custom transport also receives the callback in every request and should check
it while blocking. A cancelled call returns `RDLP_STATUS_CANCELLED` and no
result.

Library facade operations never write to stdout or stderr. Event callbacks are
the only progress-reporting boundary.

## Optional download component

Resolver-only applications link `libretrodlp.a` and do not need L-SMASH.
Applications that want Retro-DLP's progressive/adaptive download and MP4 mux
pipeline also include `<retrodlp/download.h>` and link
`libretrodlp-download.a` before the resolver library.

`rdlp_download_selection` consumes the opaque result returned by
`rdlp_resolve_video`. It sends every HTTP header carried by each resolved media
request, writes through an exclusive `.part` file, and retains downloaded
source tracks if muxing fails. Download events, cancellation, timeouts, and CA
configuration are supplied through `rdlp_download_options`. The component does
not write to stdout or stderr.

## Building, installing, and linking

`make linux`, `make macOS`, and `make iOS` each produce `retro-dlp`,
`libretrodlp.a`, and `libretrodlp-download.a` in their corresponding
`build/<platform>` directory. The Apple archives have the same architecture
slices and are compiled with the same deployment targets as the executable.
`make validate-apple-artifacts` inspects those properties after an Apple build.

On Linux, `make install PREFIX=/usr/local` installs the executable, both
archives, and only the supported headers. `DESTDIR` is supported for package
staging. `make validate-package` stages an installation into a temporary
prefix, compiles the public headers in strict C99 mode, then builds and runs a
consumer from outside the source tree.

Static-library consumers must specify Retro-DLP's transitive dependencies:

| Platform | Resolver library link dependencies | Additional download dependency |
|---|---|---|
| Linux | `-lcurl -lcrypto -lm -ldl -lpthread` | None; L-SMASH is included in `libretrodlp-download.a` |
| macOS | AltivecCore, `libcrypto.a`, Foundation, CoreFoundation, SystemConfiguration, `-lobjc -lm -lpthread` | None; L-SMASH is included |
| iOS | AltivecCore, `libcrypto.a`, Foundation, CoreFoundation, SystemConfiguration, Security, `-lobjc -lm -lpthread` | None; L-SMASH is included |

Place `libretrodlp-download.a` before `libretrodlp.a` when using the optional
download API. QuickJS and cJSON implementation objects needed by the resolver
are either included in the archive or supplied by AltivecCore on Apple; their
headers are never required by consumers. The default transport uses libcurl,
and direct OpenSSL SHA functions require the crypto library.

`make package-libraries` creates one library ZIP per platform containing the
public headers, both archives, this API guide, and the project license. Release
automation publishes these alongside the unchanged CLI-only ZIPs.

## Custom transport

A custom transport's `send` callback is synchronous. Request pointers and their
contents are borrowed and valid only during the call. Response bytes are owned
by the transport and need to remain valid only until `send` returns; Retro-DLP
copies them before returning to resolver code.

The transport must enforce HTTPS and its redirect policy, honor
`maximum_response_bytes`, the timeout, and cancellation, and return the final
HTTP status. It owns cookie behavior. An HTTP response, including a non-2xx
response, is a successful transport operation with its status in
`http_status`; connection and policy failures are returned as an `rdlp_status`.

## Minimal use

```c
#include <retrodlp/retrodlp.h>

rdlp_context *context = NULL;
rdlp_selection *selection = NULL;
rdlp_error error = {0};

error.struct_size = sizeof(error);
if (rdlp_context_create(NULL, &context, &error) == RDLP_STATUS_OK &&
    rdlp_resolve_video(context, "YE7VzlLtp-4", NULL, &selection, &error) ==
        RDLP_STATUS_OK) {
  const char *url = rdlp_selection_media_url(selection, 0);
  /* Use url and the media headers before destroying selection. */
}
rdlp_selection_destroy(selection);
rdlp_context_destroy(context);
```
