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
default libcurl transport, no cookies, progressive MP4 selection, and a maximum
height of 720 pixels.

`rdlp_context_create` returns an owned context through its output pointer.
Destroy it with `rdlp_context_destroy`. A context accepts only one operation at
a time; reentrant use from an event callback returns `RDLP_STATUS_BUSY`.
Creation and destruction of default-transport contexts safely reference-counts
the libcurl lifecycle. Concurrent resolution on separate contexts is the target
contract, but is not guaranteed by the Phase 2 adapter while legacy cache and
platform state remain shared; Phase 3 removes that shared state and validates
independent-context concurrency.

The callback context and custom transport context are borrowed. They must
remain valid until the `rdlp_context` is destroyed. Callbacks are synchronous
and run on the thread performing the operation.

The cache directory, CA bundle, EJS asset directory, EJS limits, and in-memory
cookie fields reserve their stable API locations in Phase 2. The current
adapter continues to use the legacy defaults for cache, CA, and EJS assets;
in-memory cookies are rejected. Phase 3 makes these dependencies fully
context-driven.

## Results and ownership

Every result is owned by the caller. Destroy selections with
`rdlp_selection_destroy` and playlists with `rdlp_playlist_destroy`. Strings,
media headers, and playlist entries returned by accessors are borrowed from
their parent result and remain valid until that result is destroyed. An
out-of-range accessor returns `NULL`, zero, or an empty count as appropriate.

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
an operation, around requests made by a custom transport, and after legacy
resolver orchestration. A custom transport also receives the callback in every
request and should check it while blocking. Fine-grained interruption inside
the default libcurl and QuickJS implementations is part of Phase 3. A cancelled
call returns `RDLP_STATUS_CANCELLED` and no result.

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
