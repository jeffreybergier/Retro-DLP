# Retro-DLP C API

The supported library interface is declared by
`include/retrodlp/retrodlp.h`. Applications must not include headers from
`source/shared`; those headers and all `yt_*` symbols are private and may
change without notice.

The API described here is stable beginning with Retro-DLP 1.0.0.
`RDLP_API_VERSION` identifies the incompatible public API generation;
`RDLP_VERSION_MAJOR`, `RDLP_VERSION_MINOR`, `RDLP_VERSION_PATCH`, and
`RDLP_VERSION_STRING` identify the library release. `rdlp_version_string()`
returns the release version used to build the linked library.

## Compatibility policy

Retro-DLP follows semantic versioning for the supported headers and `rdlp_`
symbols. Within one release major version:

- existing function signatures, symbol names, enum values, ownership rules,
  and documented behavior remain compatible;
- fields may be appended to structures that begin with `struct_size`, and enum
  values may be appended;
- callers must zero structures, set `struct_size` to the size visible when they
  were compiled, and ignore unknown event values;
- a newer library reads only fields covered by the caller's `struct_size`, and
  writes no more than the size supplied for output structures.

Removing a symbol, changing a signature or ownership rule, renumbering an enum,
or changing the layout of existing fields requires a new release major version
and a new `RDLP_API_VERSION`. Internal headers and `yt_*` symbols have no
compatibility guarantee. Static archives do not provide ABI compatibility
across incompatible C runtimes or platform toolchains.

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
strings are copied during context creation. No callback may start another
operation on the same context; such an attempt returns `RDLP_STATUS_BUSY`.

`cache_directory`, `ca_bundle_path`, and `ejs_asset_directory` must be absolute
when supplied. A `NULL` cache directory disables all resolver caching. An EJS
asset directory contains the version-matched `core.min.js` and `lib.min.js`
files. Zero EJS memory and stack limits select the internal defaults. A custom
clock returns Unix seconds and is used for cache expiry, cookie validation, and
authenticated request timestamps; a `NULL` clock uses system time.

Cookie options accept either a Netscape cookie-file path or caller-owned
Netscape cookie bytes, never both. The bytes are copied into the operation's
HTTP session and need remain valid only for the public call.

### Configuration fields

`rdlp_context_create(NULL, ...)` selects all defaults. With an `rdlp_config`:

| Field | Meaning and default |
|---|---|
| `cache_directory` | Absolute cache root; `NULL` disables caching. Entries are size-bounded, expired or corrupt entries are removed when read, and each cache class is pruned to its internal size/count limit. |
| `ca_bundle_path` | Absolute CA bundle used by the default transport; `NULL` uses libcurl's trust configuration. |
| `ejs_asset_directory` | Absolute directory containing version-matched `core.min.js` and `lib.min.js`; `NULL` means challenge assets are not provisioned by the library. |
| `network_timeout_milliseconds` | Per-request timeout; zero selects 20,000 milliseconds. |
| `ejs_memory_limit_bytes`, `ejs_stack_limit_bytes` | QuickJS resource limits; zero selects safe internal defaults. |
| `event_callback`, `cancel_callback`, `callback_context` | Synchronous operation callbacks and their borrowed context. |
| `transport` | Borrowed custom transport descriptor; `NULL` selects libcurl. The descriptor is copied, but its `context` remains borrowed. |
| `clock_callback`, `clock_context` | Unix-seconds clock and borrowed context; `NULL` uses system time. |

The library creates cache subdirectories as needed and never derives a core
library path from `$HOME` or the executable. The caller owns provisioning and
removing the configured cache and EJS assets. The CLI's `assets` commands are
not library API.

## Operations and options

`rdlp_resolve_video` accepts a video ID or supported URL and returns one
selected progressive request or an adaptive video/audio pair.
`rdlp_resolve_options` fields have these meanings:

| Field | Meaning and default |
|---|---|
| `format_expression` | Exact itag expression using `+` and `/`; `NULL` uses library selection policy. |
| `cookie_file` / `cookie_data`, `cookie_data_length` | One Netscape cookie source or none. |
| `include_format_inventory` | Nonzero retains the inspected format inventory in the result. |
| `maximum_height` | Automatic-selection height limit; zero selects 720. |
| `prefer_adaptive` | Nonzero prefers an adaptive video/audio pair; zero prefers progressive MP4. |

`rdlp_list_playlist` accepts a playlist ID or supported playlist URL.
`rdlp_list_playlist_collection` accepts a supported signed-in account
collection URL. Both use `rdlp_playlist_options`, whose cookie fields have the
same rules as resolve options. `rdlp_is_playlist_collection_input` can be used
to choose between the two calls.

The non-network helpers `rdlp_parse_video_id`, `rdlp_parse_playlist_id`, and
`rdlp_format_expression_valid` validate input without a context. A parsed video
ID output is always a 12-byte array (11 characters plus NUL). The playlist
parser accepts a caller-sized buffer. `rdlp_status_string` returns a static,
human-readable description for any public status.

## Results and ownership

Every result is owned by the caller. Destroy selections with
`rdlp_selection_destroy`, playlists with `rdlp_playlist_destroy`, and account
playlist collections with `rdlp_playlist_collection_destroy`. Strings, media
headers, and playlist entries returned by accessors are borrowed from their
parent result and remain valid until that result is destroyed. An out-of-range
accessor returns `NULL`, zero, or an empty count as appropriate.

Media index zero is the video or progressive request. For adaptive selections,
index one is the audio request. Each request includes the complete header list
that must be used to fetch it. Iterate it with
`rdlp_selection_media_header_count` and `rdlp_selection_media_header`; do not
assume the only header is `User-Agent`.

Selection accessors expose the video ID, title, selected format expression,
adaptive flag, and media count. Per-media accessors expose URL, MIME type,
itag, dimensions, content length, frame rate, audio channel count, and headers.
When `include_format_inventory` was nonzero, the format accessors expose each
format's itag, MIME type, dimensions, frame rate, video/audio presence, and
whether Retro-DLP supports it.

Playlist accessors expose ID, title, and ordered entries. Each entry has its
service index, video ID, and title. Playlist-collection accessors expose the
count and each playlist's service index, ID, and title.

On every failed operation, its output pointer is set to `NULL`. Destroy
functions accept `NULL`.

## Errors

An error argument is optional. When supplied, initialize it to zero and set
`struct_size`. The operation returns the same high-level status stored in the
error. `message` is intended for diagnostics, not programmatic matching.
`http_status` and `transport_code` are zero when the underlying adapter cannot
provide more detail. `retryable` is set for network and HTTP failures.

Programs should branch on `rdlp_status`, not `message` or third-party transport
codes. In particular, cancellation, authentication, missing EJS assets,
certificate configuration, service unavailability, format unavailability,
storage failures, and a busy context have distinct statuses. A successful call
also resets a supplied error to `RDLP_STATUS_OK`.

| Status | Meaning |
|---|---|
| `RDLP_STATUS_OK` | Success. |
| `RDLP_STATUS_INVALID_ARGUMENT` | A required value, structure size, path, ID, URL, format expression, or option combination is invalid. |
| `RDLP_STATUS_OUT_OF_MEMORY` | An allocation failed. |
| `RDLP_STATUS_NETWORK` | The transport could not complete a request. |
| `RDLP_STATUS_CERTIFICATE_BUNDLE` | The configured CA bundle cannot be used. |
| `RDLP_STATUS_HTTP` | A completed HTTP response indicates failure. |
| `RDLP_STATUS_INVALID_RESPONSE` | Response data or downloaded media is malformed or exceeds a limit. |
| `RDLP_STATUS_UNAVAILABLE` | The requested service object is unavailable. |
| `RDLP_STATUS_FORMAT_UNAVAILABLE` | No requested/supported format matched. |
| `RDLP_STATUS_EJS_ASSETS_MISSING` | Required challenge assets were not provisioned. |
| `RDLP_STATUS_JS_CHALLENGE` | Player challenge processing failed. |
| `RDLP_STATUS_AUTHENTICATION_REQUIRED` | Authentication is required or supplied authentication is unusable. |
| `RDLP_STATUS_COOKIE` | Cookie data cannot be loaded or parsed. |
| `RDLP_STATUS_CANCELLED` | A cancellation callback stopped the operation. |
| `RDLP_STATUS_BUSY` | Another operation owns the same context. |
| `RDLP_STATUS_STORAGE` | A cache, destination, temporary file, or cleanup operation failed. |
| `RDLP_STATUS_INTERNAL` | An uncategorized internal failure occurred. |

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

Resolver event types cover configuration, bootstrap fetching, metadata,
player JavaScript, challenge solving, format selection, and playlist
enumeration. `completed_bytes` and `expected_bytes` are zero when a phase has no
byte progress. Event pointers are borrowed and valid only during the callback.
The corresponding values are `RDLP_EVENT_LOADING_CONFIGURATION`,
`RDLP_EVENT_FETCHING_BOOTSTRAP`, `RDLP_EVENT_REQUESTING_METADATA`,
`RDLP_EVENT_LOADING_PLAYER_JAVASCRIPT`, `RDLP_EVENT_SOLVING_CHALLENGES`,
`RDLP_EVENT_SELECTING_FORMATS`, `RDLP_EVENT_ENUMERATING_PLAYLIST`, and the
forward-compatible fallback `RDLP_EVENT_OTHER`.

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

Cancellation is checked before and during transfers, before muxing, and while
samples are being muxed. Cancelling or failing during adaptive muxing retains
the downloaded audio and video tracks and reports that fact through
`source_tracks_retained`.

The selection and destination string are borrowed for the duration of the
call. `rdlp_download_options` configures an optional CA bundle, timeout,
synchronous event callback, cancellation callback, and borrowed callback
context. Download events distinguish progressive media, adaptive audio,
adaptive video, muxing, and cleanup; their path and event object are borrowed
for the callback. A zero timeout selects the component default.

`rdlp_download_result` is optional. Initialize it with `struct_size`; on return,
`bytes_written` is the completed destination size when known and
`source_tracks_retained` reports adaptive tracks left behind by mux or cleanup
failure. Existing destinations are never overwritten. A progressive transfer
uses an exclusive `DESTINATION.part` and renames it only after success.

The event values are `RDLP_DOWNLOAD_EVENT_DOWNLOADING_AUDIO`,
`RDLP_DOWNLOAD_EVENT_DOWNLOADING_VIDEO`,
`RDLP_DOWNLOAD_EVENT_DOWNLOADING_MEDIA`, `RDLP_DOWNLOAD_EVENT_MUXING`, and
`RDLP_DOWNLOAD_EVENT_CLEANING_UP`.

## Public API index

Opaque owned types are `rdlp_context`, `rdlp_selection`, `rdlp_playlist`, and
`rdlp_playlist_collection`. Versioned value types are `rdlp_error`,
`rdlp_event`, `rdlp_transport_request`, `rdlp_transport_response`,
`rdlp_transport`, `rdlp_config`, `rdlp_resolve_options`,
`rdlp_playlist_options`, `rdlp_download_event`, `rdlp_download_options`, and
`rdlp_download_result`. `rdlp_http_header` is a borrowed name/value pair.
Callback types are `rdlp_event_callback`, `rdlp_cancel_callback`,
`rdlp_clock_callback`, `rdlp_transport_send_callback`, and
`rdlp_download_event_callback`; their lifetime and threading rules are given
above. Enum types are `rdlp_event_type`, `rdlp_download_event_type`, and
`rdlp_http_method`. HTTP methods are `RDLP_HTTP_GET`, `RDLP_HTTP_POST`, and
`RDLP_HTTP_HEAD`.

| Function family | Functions |
|---|---|
| Version and status | `rdlp_version_string`, `rdlp_status_string` |
| Context | `rdlp_context_create`, `rdlp_context_destroy` |
| Validation | `rdlp_parse_video_id`, `rdlp_parse_playlist_id`, `rdlp_format_expression_valid`, `rdlp_is_playlist_collection_input` |
| Operations | `rdlp_resolve_video`, `rdlp_list_playlist`, `rdlp_list_playlist_collection`, `rdlp_download_selection` |
| Selection identity | `rdlp_selection_destroy`, `rdlp_selection_video_id`, `rdlp_selection_title`, `rdlp_selection_format_id`, `rdlp_selection_is_adaptive` |
| Selected media | `rdlp_selection_media_count`, `rdlp_selection_media_url`, `rdlp_selection_media_mime_type`, `rdlp_selection_media_itag`, `rdlp_selection_media_width`, `rdlp_selection_media_height`, `rdlp_selection_media_content_length`, `rdlp_selection_media_fps`, `rdlp_selection_media_audio_channels`, `rdlp_selection_media_header_count`, `rdlp_selection_media_header` |
| Format inventory | `rdlp_selection_format_count`, `rdlp_selection_format_itag`, `rdlp_selection_format_mime_type`, `rdlp_selection_format_width`, `rdlp_selection_format_height`, `rdlp_selection_format_fps`, `rdlp_selection_format_has_video`, `rdlp_selection_format_has_audio`, `rdlp_selection_format_is_supported` |
| Playlist | `rdlp_playlist_destroy`, `rdlp_playlist_id`, `rdlp_playlist_title`, `rdlp_playlist_entry_count`, `rdlp_playlist_entry_video_id`, `rdlp_playlist_entry_title`, `rdlp_playlist_entry_index` |
| Playlist collection | `rdlp_playlist_collection_destroy`, `rdlp_playlist_collection_count`, `rdlp_playlist_collection_id`, `rdlp_playlist_collection_title`, `rdlp_playlist_collection_index` |

All accessors are side-effect-free. Pointer accessors return borrowed pointers;
numeric accessors return zero and pointer accessors return `NULL` for a `NULL`
parent or out-of-range index.

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

`make examples` compiles all programs in `examples/`; `make
validate-examples` also runs the network-free custom-transport example.
`make package-libraries` creates one library ZIP per platform containing the
public headers, both archives, this API guide, examples, and the project
license. Release automation publishes these alongside the unchanged CLI-only
ZIPs.

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

The request method, URL, headers, optional body, response limit, timeout, and
cancellation hook are fully populated by Retro-DLP. Initialize the response
fields you provide; set `http_status`, `data`, and `data_length` on success and
set `transport_code` when useful. Do not write beyond the response's
`struct_size`. Redirects must remain HTTPS. The callback must not retain request
pointers or call another operation on the same context.

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

Complete resolver-only, authenticated, playlist, custom-transport, and optional
download programs are in [`examples/`](../examples/README.md).
