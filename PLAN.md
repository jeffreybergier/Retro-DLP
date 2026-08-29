# Retro-DLP Library Refactor Plan

## Objective

Turn Retro-DLP into a reusable C library while preserving the existing command
line tool as a thin client of that library. The core product of the library is
YouTube metadata, playlist, format, and media-URL resolution. Terminal output,
asset installation commands, file downloads, and MP4 muxing are separate
application or optional-library responsibilities.

The refactor must continue to support the project's current platform targets:

- macOS PowerPC, i386, x86_64, and arm64
- iOS armv7 and arm64
- Native Linux builds and tests

## Decisions and Assumptions

These are the working decisions for the initial implementation:

1. Ship static libraries first. Dynamic libraries, Apple frameworks, and
   XCFramework packaging are explicitly deferred.
2. Provide a default libcurl transport and an optional caller-supplied
   transport interface. Apps may therefore use the built-in implementation or
   bridge to platform networking.
3. Do not guarantee source or binary compatibility with the current `yt_*`
   interfaces. They were created for the executable and have not been
   published as a stable library API.
4. Prefix the supported API with `rdlp_`. Internal symbols should be hidden or
   use an internal naming convention.
5. A context may be used by only one operation at a time. Independent contexts
   should be safe to use concurrently. Shared-context concurrency is deferred.
6. The core library resolves media requests but does not require callers to use
   its downloader or muxer.
7. C99 remains the public API baseline. QuickJS may continue to use the newer C
   dialect required by its own sources.

Any change to these decisions should be made before the public API is declared
stable.

## Target Deliverables

The completed repository should produce:

```text
include/retrodlp/retrodlp.h
include/retrodlp/version.h
build/linux/libretrodlp.a
build/macOS/libretrodlp.a
build/iOS/libretrodlp.a
build/linux/retro-dlp
build/macOS/retro-dlp
build/iOS/retro-dlp
```

If download and mux support are separated into another archive, also produce:

```text
build/*/libretrodlp-download.a
```

The exact build layout may be adjusted to match the existing release tooling,
but public headers and library artifacts must be clearly distinguished from
private objects and executable artifacts.

## Desired Module Boundaries

### Public facade

`retrodlp.h` exposes the supported API only:

- library version information;
- context creation and destruction;
- resolver and playlist operations;
- result access and destruction;
- configuration, callbacks, and cancellation;
- structured error information;
- optional download entry points only if the download library is linked.

Consumers must not need to include cJSON, curl, QuickJS, L-SMASH, OpenSSL, or
private Retro-DLP headers.

### Context and dependencies

An opaque `rdlp_context` owns per-consumer state:

- HTTP session and cookies;
- client configuration;
- cache configuration;
- CA bundle configuration;
- EJS asset source and resource limits;
- progress/event and cancellation callbacks;
- clock and transport implementations;
- diagnostic state required by the current operation.

Avoid writable process-global state. Process-level libcurl initialization must
be handled safely by the default transport or exposed as a clearly documented
lifecycle requirement.

### Resolver orchestration

The resolver coordinates the operation but does not implement every detail.
Split the current resolver responsibilities into cohesive internal modules:

- `yt_webpage`: embedded JSON scanning and page/bootstrap configuration;
- `yt_session`: account context, cookies, visitor data, and authentication;
- `yt_innertube`: client definitions and player/browse requests;
- `yt_formats`: format inventory, expressions, selection, and media requests;
- `yt_challenges`: player JavaScript loading and EJS challenge resolution;
- `yt_resolver`: video-resolution orchestration;
- `yt_playlist`: playlist-specific traversal and orchestration.

These names describe responsibilities, not a mandatory one-file-per-item rule.
Combine very small modules where doing so keeps the legacy build simpler.

### Optional download pipeline

Move progressive download, adaptive-track download, cleanup, and mux
orchestration out of `cli.c`. It should consume resolved media requests through
the same public contract available to applications.

L-SMASH should not be a dependency of the resolver-only library. The CLI may
link both libraries.

### CLI

The CLI remains responsible for:

- argument parsing;
- choosing CLI defaults and presets;
- locating CLI-specific default paths;
- terminal and JSON presentation;
- asset management commands;
- translating library events and errors into process output;
- selecting whether to resolve, download, or mux.

The CLI must not duplicate resolver policy.

## Proposed Public API Shape

The exact declarations will be reviewed during implementation, but the facade
should follow this general model:

```c
typedef struct rdlp_context rdlp_context;
typedef struct rdlp_selection rdlp_selection;
typedef struct rdlp_playlist rdlp_playlist;

typedef struct {
  size_t struct_size;
  const char *cache_directory;
  const char *ca_bundle_path;
  const char *ejs_asset_directory;
  unsigned long network_timeout_milliseconds;
  size_t ejs_memory_limit_bytes;
  size_t ejs_stack_limit_bytes;
  rdlp_event_callback event_callback;
  rdlp_cancel_callback cancel_callback;
  void *callback_context;
  const rdlp_transport *transport;
} rdlp_config;

typedef struct {
  size_t struct_size;
  const char *format_expression;
  const char *cookie_file;
  const void *cookie_data;
  size_t cookie_data_length;
  int include_format_inventory;
} rdlp_resolve_options;

rdlp_status rdlp_context_create(const rdlp_config *config,
                                rdlp_context **context,
                                rdlp_error *error);
void rdlp_context_destroy(rdlp_context *context);

rdlp_status rdlp_resolve_video(rdlp_context *context,
                               const char *input,
                               const rdlp_resolve_options *options,
                               rdlp_selection **selection,
                               rdlp_error *error);

rdlp_status rdlp_list_playlist(rdlp_context *context,
                               const char *input,
                               const rdlp_playlist_options *options,
                               rdlp_playlist **playlist,
                               rdlp_error *error);

void rdlp_selection_destroy(rdlp_selection *selection);
void rdlp_playlist_destroy(rdlp_playlist *playlist);
```

Important API rules:

- All public symbols use the `rdlp_` prefix.
- Public configuration structures contain `struct_size` for additive growth.
- Functions accept `NULL` options to select documented defaults.
- Returned objects are either fully opaque or have explicit ownership rules.
- Failed calls leave output pointers as `NULL` unless partial results are an
  explicitly documented feature.
- Results return all HTTP headers needed for a media request, not only a user
  agent.
- Cancellation is distinguishable from network and protocol failures.
- No public function writes to stdout or stderr.
- No public header exposes third-party types.

## Structured Errors

Replace status-only diagnostics with a stable high-level status plus optional
details:

```c
typedef struct {
  size_t struct_size;
  rdlp_status status;
  long http_status;
  int transport_code;
  int retryable;
  char message[256];
} rdlp_error;
```

Do not expose raw internal or third-party error values as the primary API.
Preserve enough detail for applications to decide whether to retry, ask for
authentication, install EJS assets, or report a protocol change.

## Events and Cancellation

Replace free-form progress strings in the library boundary with typed events.
Suggested event categories include:

- loading configuration;
- fetching bootstrap data;
- requesting metadata;
- loading player JavaScript;
- solving challenges;
- enumerating playlist pages;
- downloading a stream;
- muxing tracks.

An event may also include completed and expected byte counts when applicable.
The CLI converts these events into its existing messages.

Check cancellation:

- before and after network requests;
- between playlist continuation pages;
- before starting EJS evaluation;
- through the QuickJS interrupt handler;
- during downloads through the transport progress callback;
- between major mux phases where interruption is safe.

## Transport Boundary

Define the smallest transport interface needed by the resolver. It should
support request method, URL, headers, body, response-size bounds, timeout or
cancellation state, response status, response headers if needed, and response
bytes.

The default implementation uses libcurl. A custom implementation allows an app
to bridge to NSURLSession or another networking stack without changing
resolver code.

The transport contract must specify:

- whether callbacks are synchronous;
- ownership of request and response memory;
- redirect policy;
- HTTPS-only enforcement;
- cookie handling expectations;
- timeout and cancellation behavior;
- maximum response enforcement;
- mapping of transport failures into `rdlp_error`.

Media requests returned by the resolver must include an extensible header list.
The default downloader must use those exact headers.

## Storage and Asset Configuration

Remove implicit `$HOME` and executable-relative paths from the library core.
Configuration should support:

- an explicit cache directory;
- disabled caching;
- caller-provided cache operations if later required;
- an explicit CA bundle path for the libcurl transport;
- EJS assets supplied by directory; ~~caller-owned EJS asset bytes~~;
- cookies supplied by file or memory.

CLI defaults such as `~/.retro-dlp/cache`, `~/.retro-dlp/cookies.txt`, and a CA
bundle beside the executable remain valid CLI policies, applied when building
the CLI's `rdlp_config`.

## Implementation Checklist

## Phase 1: Establish a safe baseline

- [x] Fix silent playlist truncation when a continuation token cannot be copied.
- [x] Accept supported raw playlist IDs without requiring the `PL` prefix.
- [x] Make playlist host matching case-insensitive.
- [x] Ensure downloads use the headers and user agent from the resolved media
  request.
- [x] Resolve the strict-build format-description truncation warning.
- [x] Add fixture tests covering playlist bootstrap parsing, normal entries,
  continuation pagination, duplicate entries, malformed continuations, and
  allocation/error paths where practical.
- [x] Add push and pull-request Linux CI running `make test`.
- [x] Add a supported sanitizer test target or make the link rules honor
  `LDFLAGS` and `LDLIBS`.

Exit criteria:

- [x] Existing CLI behavior remains compatible.
- [x] Normal Linux tests pass.
- [x] ASan/UBSan tests pass for first-party code.
- [x] New playlist fixtures demonstrate that truncation cannot be reported as
  success.

## Phase 2: Introduce the library facade

- [x] Create `include/retrodlp/retrodlp.h` and `version.h`.
- [x] Define `rdlp_status`, `rdlp_error`, opaque result types, configuration,
  options, typed events, and cancellation.
- [x] Add `rdlp_context_create` and `rdlp_context_destroy`.
- [x] Implement the initial facade as adapters over current internals before doing
  large source moves.
- [x] Document defaults, ownership, error behavior, threading, and cancellation.
- [x] Add symbol visibility/export macros suitable for static use now and possible
  shared-library use later.

Exit criteria:

- [x] A small external C program can create a context, parse an ID, resolve an
  offline fixture through a test transport, inspect a result, and clean up.
- [x] The consumer includes only public Retro-DLP headers.
- [x] No third-party type appears in the supported API.

## Phase 3: Make dependencies context-driven

- [x] Move HTTP session state under `rdlp_context`.
- [x] Add the transport interface and default libcurl implementation.
- [x] Move cache root and policy state under the context.
- [x] Make CA bundle, EJS assets, cookies, resource limits, timeouts, and clock
  configurable.
- [x] Remove direct library access to `$HOME`, executable paths, stdout, and
  stderr.
- [x] Remove or synchronize writable global state, including cache temporary-name
  state and platform-path initialization.
- [x] Define and test independent-context concurrency.

Exit criteria:

- [x] Two independent contexts can operate concurrently in a thread-enabled test.
- [x] A context can operate with caching disabled.
- [x] A context can resolve fixtures using an injected transport and clock.
- [x] The library produces no process output.

## Phase 4: Separate internal responsibilities

- [x] Extract shared webpage/config scanning used by resolver and playlist code.
- [x] Consolidate account context and authenticated-header construction.
- [x] Extract client and Innertube request handling.
- [x] Extract format inventory, grammar, and selection.
- [x] Keep challenge resolution behind one internal interface.
- [x] Reduce `yt_resolver.c` and `yt_playlist.c` to orchestration plus domain-specific
  traversal.
- [x] Centralize duplicated allocation, JSON, URL, and time helpers where doing so
  improves correctness.

Exit criteria:

- [x] Resolver and playlist orchestration can be understood without reading HTTP,
  cache, authentication-header, or format-selection implementations.
- [x] Duplicated page-marker and account-context logic is removed.
- [x] Existing fixture behavior remains unchanged.

## Phase 5: Separate CLI and download responsibilities

- [x] Split CLI argument parsing from output rendering.
- [x] Move JSON and table rendering into CLI-only code.
- [x] Move progressive/adaptive download and mux orchestration into the optional
  download component.
- [x] Remove all terminal output from HTTP and download internals.
- [x] Have the CLI construct a context and call only the supported library facade.
- [x] Keep asset install/status/remove as CLI tooling or a separately documented
  utility API, not part of normal resolution.

Exit criteria:

- [x] `main.c` and CLI sources are not present in library archives.
- [x] The CLI has no direct dependency on resolver-private headers.
- [x] An application can resolve URLs without linking L-SMASH.
- [x] CLI output and exit behavior remain covered by shell tests.

## Phase 6: Build and packaging

- [x] Add static archive targets for Linux, macOS, and iOS.
- [x] Produce the existing multi-architecture Apple outputs.
- [x] Document all transitive dependencies and platform link flags.
- [x] Add a consumer smoke test that links from outside the source tree.
- [x] Ensure Makefiles honor standard customization variables where compatible
  with the legacy toolchains.
- [x] Add installed-header validation and a public-header C99 compile test.
- [x] Pin release build containers by immutable digest.
- [x] Update release staging to include the desired library packages without
  changing existing CLI packages unexpectedly.

Exit criteria:

- [x] Each platform produces a library and executable from the same core objects.
- [x] A standalone consumer links and runs on Linux.
- [x] Apple validation confirms expected architectures and minimum deployment
  targets.
- [x] Release inputs are reproducible and pinned.

## Phase 7: Migrate and remove superseded code

- [x] Migrate all tests to the public facade or explicit internal test seams.
- [x] Remove superseded `yt_resolve_video_with_*` entry points.
- [x] Move low-level player-response parsing into private/test-support headers
  unless a concrete public use case exists.
- [x] Remove unused stateless HTTP wrappers and other unreachable internals.
- [x] Decide whether multi-client configuration is imminent. Retain the client
  manifest and successful-client cache behind the context if it is; otherwise
  remove them until the second client is implemented.
- [x] Remove obsolete `.gitkeep` files.
- [x] Remove the unused `inspiration/yt-dlp` submodule and replace it with source
  links in maintained documentation.
- [x] Replace or remove the research-transcript-style `CONTEXT.md`.

Exit criteria:

- [x] No unsupported legacy API remains in public headers.
- [x] No production source is retained solely because an obsolete test calls it.
- [x] Repository setup downloads only dependencies required to build or test.

## Phase 8: Documentation and stabilization

- [x] Document context lifecycle, ownership, threading, callbacks, cancellation,
  cache behavior, asset provisioning, cookies, and error handling.
- [x] Add examples for resolver-only, authenticated, playlist, custom transport,
  and optional download use.
- [x] Add an API version macro and compatibility policy.
- [x] Review all public names and structures before declaring the API stable.
- [x] Run normal, warning-clean, sanitizer, Linux, macOS, and iOS validation.

Exit criteria:

- [x] README build and CLI instructions remain correct.
- [x] Library consumers have a concise getting-started example.
- [x] The supported API is small enough to document completely.
- [x] All validation listed below passes.

## Validation Matrix

Every phase should run the smallest relevant subset. Before completion, run:

### Functional

- Video-ID parsing fixtures
- Playlist-ID and collection URL fixtures
- Progressive and adaptive format fixtures
- Exact-format fallback fixtures
- Signature and `n` challenge fixtures
- Cookie and SAPISID authorization fixtures
- Playlist bootstrap and continuation fixtures
- Cache corruption, expiry, pruning, and disabled-cache fixtures
- CLI argument and output tests

### Failure behavior

- Allocation failures at owned-result and pagination boundaries where injectable
- Network, timeout, cancellation, HTTP, malformed JSON, and oversized response
  failures
- Missing and corrupt EJS assets
- Invalid and expired cookies
- Existing destination and partial-file behavior
- Mux failure and source-track retention

### Library contract

- Public headers compile as C99 and C++ consumers can include them under
  `extern "C"` guards
- No third-party headers are required by public headers
- Output objects are `NULL` or safely destructible after every failure
- Multiple independent contexts do not share mutable configuration
- No stdout or stderr output from library operations
- Custom transport and clock fixture tests
- Cancellation at network, playlist, EJS, download, and mux boundaries

### Toolchains

- Native Linux warning-clean build and tests
- Linux ASan/UBSan build and tests
- macOS PowerPC and i386 legacy validation
- macOS x86_64 and arm64 validation
- iOS armv7 and arm64 validation
- Architecture and minimum-deployment-target inspection of Apple artifacts

## Compatibility and Migration Policy

Until the library facade is declared stable:

- The CLI is the compatibility target.
- New application code should use only `include/retrodlp` headers.
- Existing `yt_*` headers are internal and may change without compatibility
  shims.
- If external users of the old headers are discovered, add a separately built,
  deprecated compatibility layer rather than compromising the new facade.

Once stable:

- Follow semantic versioning for the public API.
- Permit additive options through `struct_size`-versioned structures.
- Treat public symbol removal, signature changes, enum renumbering, and ownership
  changes as breaking changes.
- Keep internal headers outside the installed include directory.

## Risks and Mitigations

### Legacy platform regression

Mitigation: keep C99-compatible public and first-party code, preserve existing
toolchain profiles, and validate architecture-specific builds at milestone
boundaries rather than only at the end.

### Over-abstraction

Mitigation: introduce interfaces only at application boundaries—transport,
storage/configuration, clock, events, and cancellation. Keep parsing and format
logic as normal internal C functions.

### API designed around current YouTube behavior

Mitigation: return extensible header collections, use options structures, keep
client details internal, and avoid exposing Innertube response shapes directly.

### Binary size growth

Mitigation: keep downloader/mux support optional, avoid forcing L-SMASH into the
resolver archive, inspect linked symbols, and preserve dead-code elimination.

### Partial migration

Mitigation: make the CLI consume the facade before removing old entry points.
Do not maintain two independent resolver implementations.

### Threading ambiguity

Mitigation: document the initial one-operation-per-context contract, remove
writable globals, and test independent contexts before promising stronger
thread safety.

## Definition of Done

The project is considered successfully converted when:

- applications can link a static resolver library without CLI sources or
  L-SMASH;
- the CLI is implemented through the same supported API offered to applications;
- library calls use explicit context configuration and never write to process
  output;
- cache, CA bundle, EJS assets, cookies, transport, timeouts, events, and
  cancellation are application-configurable;
- results have documented ownership and include all headers required to fetch
  media;
- errors retain useful protocol and transport details;
- independent contexts have a tested concurrency contract;
- obsolete entry points and unused repository content are removed;
- normal, sanitizer, consumer, Linux, macOS, and iOS validations pass;
- the public API and migration policy are documented.
