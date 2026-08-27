# Retro-DLP Implementation Plan

The initial goal is deliberately narrow: resolve an ordinary public YouTube
video to a directly downloadable, progressive H.264/AAC MP4 URL. The first
version will not support authentication, live streams, playlists, subtitles,
adaptive audio/video merging, conversion, DRM, SABR, or PO-token generation.

## 1. Build a desktop C resolver first

- [x] Complete the desktop C resolver milestone.

Create a command-line program that accepts a YouTube URL or video ID:

```sh
retro-dlp --dump-json VIDEO_ID
```

Return a machine-readable result such as:

```json
{
  "url": "https://example.googlevideo.com/videoplayback?...",
  "itag": 18,
  "width": 640,
  "height": 360,
  "mimeType": "video/mp4",
  "expires": 1785580000,
  "headers": {
    "User-Agent": "..."
  }
}
```

Use the current desktop version of yt-dlp as the comparison oracle. For each
test video, compare:

- [x] Selected itag
- [x] Final Google Video media service and stable important query fields
- [x] Direct signature parameter choice and absence of an unsolved `n`
- [x] Transformed signature (`s`) and throttling (`n`) results when present;
  covered by the matching deterministic EJS golden fixtures
- [x] Initial 10,241-byte range download and MP4 prefix validation

- [x] Use the public Big Buck Bunny upload (`YE7VzlLtp-4`) as an initial live
  fixture, since yt-dlp also uses it in its YouTube extractor tests.
- [x] Check `-_x6t4CaPzo` as a second live fixture.
- [x] Keep sanitized captured player responses and media metadata as
  deterministic embedded fixtures so the core parser and classifications can
  run without the network.
- [x] Retire automated live integration requests after hardware validation;
  routine tests now use deterministic fixtures exclusively to avoid YouTube
  throttling the downloader's public IP.

## 2. Implement direct itag 18 only

- [x] Complete the direct-itag-18 milestone without invoking QuickJS in the
  resolver path.

Do not involve QuickJS yet. Implement the smallest complete resolution path:

- [x] Parse and validate an 11-character YouTube video ID.
- [x] Call one configured JSless Innertube client.
- [x] Parse the player response JSON.
- [x] Inspect `streamingData.formats` only.
- [x] Select a direct itag 18 URL.
- [x] Return its URL, required headers, dimensions, MIME type, and expiry.
- [x] Probe it with yt-dlp's 10,241-byte test range, require a 2xx response,
  and validate the MP4 prefix.
- [x] Make `retro-dlp VIDEO_ID_OR_URL` stream the complete itag 18 MP4 into the
  current directory by default.
- [x] Make `--dump-json` return normalized yt-dlp-style resolver JSON
  without probing or downloading.
- [x] Write through an exclusive `.part` file, validate the MP4 `ftyp` box,
  refuse overwrites, remove handled failures, and publish atomically.
- [x] Classify a full-download HTTP 403 independently of the byte-range probe
  request. The first Linux live download reached GVS and confirmed the current
  `po_token_required` limitation without leaving a partial file.

Historical hardware validation downloaded the first 10,241 bytes of each live
fixture, matching yt-dlp's test size, and validated the MP4 prefix. Those live
requests are no longer part of routine automated tests. Normal CLI use performs
the complete streaming GET, and that result is authoritative for actual
download capability.

This phase proves the network, TLS, JSON parsing, client configuration, format
selection, result model, and download pipeline before JavaScript is introduced.

## 3. Add QuickJS and EJS

- [x] Complete the QuickJS and EJS integration milestone.

Integrate a pinned yt-dlp-ejs bundle behind a small native adapter. Test it
independently of HTTP first:

```text
reduced player-shaped base.js fixture + known s/n challenges
    -> C + QuickJS + EJS
    -> expected transformed values
```

### Phase 3 implementation sequence

1. [x] **Pin and vendor EJS.** Match the EJS version required by the vendored
   desktop yt-dlp, record its version, source hash, and license, and embed the
   required EJS source as a build asset.
2. [x] **Build a narrow native adapter.** Add a C module that uses the existing
   embedded QuickJS library, loads EJS, submits JSON requests containing batched
   `s` and `n` challenges, and parses the JSON result. Do not expose native
   networking, filesystem, process, or dynamic-module APIs to JavaScript.
3. [x] **Establish deterministic correctness first.** Maintain golden fixtures
   generated with matching desktop yt-dlp and EJS versions. Test a reduced,
   deterministic player-shaped `base.js` fixture, known `s` and `n` challenges,
   batching, malformed results, exceptions, and timeouts without depending on
   HTTP.
4. [x] **Add resource containment and validate it on PowerPC.**
   - [x] Apply memory and stack limits plus an execution deadline.
   - [x] Recreate the runtime after a timeout, out-of-memory condition, or
     unexpected JavaScript exception by using a fresh runtime for each solve.
   - [x] Compile and link the EJS adapter and fixtures into the PowerPC slice.
   - [x] Run the EJS fixtures in a PowerPC Tiger environment. Validated on
     Darwin 8.11.0 PowerPC: the complete self-test and live resolver
     passed; the media probe reached GVS and returned the expected PO-token
     `403` classification.
5. [x] **Integrate with format parsing.** Retain itag 18 candidates containing
   `signatureCipher` or `n`, collect all required transformations, invoke EJS
   once, rewrite the final URL, and reject any unresolved challenge.
6. [x] **Retrieve the player JavaScript.** Prefer a player URL supplied by the
   Innertube response, add the smallest necessary watch-page fallback, and fetch
   `base.js` in native C so JavaScript receives only its source text.
7. [x] **Validate end to end.** Preserve the direct-URL fast path, compare the
   final signature and transformed-`n` URL structure with the pinned yt-dlp
   oracle, probe the resulting media URL, and keep PO-token failures distinct
   from EJS failures. On August 26, 2026, the `mweb` path resolved and
   downloaded a complete 7,227,427-byte itag 18 MP4 on Darwin 8.11.0 PowerPC
   Tiger.

## 4. Make EJS assets downloadable on demand by the CLI

- [x] Complete the on-demand EJS asset milestone.

Keep QuickJS compiled into the native executable, but stop embedding the EJS
`core` and `lib` JavaScript in release binaries once the asset loader is ready.
Direct itag 18 resolution must continue to work without EJS being installed.

- [x] Ship a small built-in bootstrap manifest containing the pinned EJS
  version, HTTPS download URLs, expected sizes, SHA-256 hashes, and license
  metadata.
- [x] Add `retro-dlp assets status`, `retro-dlp assets install`, and
  `retro-dlp assets remove` commands with machine-readable output.
- [x] Download through the existing native HTTP/TLS layer with strict response
  size limits and no JavaScript-visible networking APIs.
- [x] Verify every asset's size and SHA-256 hash before installation, then use
  atomic writes so an interruption cannot replace a working installation with
  a partial one.
- [x] Store assets under `~/.retro-dlp/cache/assets` rather than beside the
  executable. Use the same `~/.retro-dlp/cache` root on Linux, macOS, and iOS.
- [x] When EJS execution is requested but the assets are absent, return a
  distinct `ejs_assets_missing` classification that names the install command;
  do not download implicitly during ordinary video resolution.
- [x] Exercise the production asset loader in deterministic tests, including
  missing, truncated, oversized, corrupt, wrong-version, and interrupted
  installations. Test builds may inject the pinned vendored assets, but release
  builds must demonstrate that the EJS source is not embedded.
- [x] Retain complete EJS and bundled-dependency license notices with the
  installed assets.

This phase installs only the EJS version pinned by the native executable. A new
version still requires rebuilding the executable until the signed update
channel is implemented.

## 5. Add caches

- [x] Complete the caching milestone.

Add bounded, versioned caches for:

Use `~/.retro-dlp/cache/v1` as the common cache root on Linux, macOS, and iOS.

- [x] The client manifest
- [x] Raw player JavaScript
- [x] EJS `preprocessed_player` output
- [x] The most recently successful client, for a limited period
- [x] Failure classifications, with short and error-specific lifetimes

- [x] Key player artifacts by canonical player URL and/or an OpenSSL SHA-256
  hash.
- [x] Make cache writes atomic.
- [x] Safely discard corrupt or incompatible entries.
- [x] Do not use downloaded QuickJS bytecode as a cache or update format.

All five cache namespaces are connected to production resolver behavior. Raw
player JavaScript is keyed by its canonical URL hash, successful-client entries
expire after one day, and failure lifetimes range from 15 seconds to five
minutes by classification.

## 6. Add authenticated tokenless playback and GVS PO-token fallback

- [ ] Complete the authenticated tokenless playback and GVS PO-token fallback
  milestone.

Keep PO-token failures distinct from signature and throttling challenge
failures. The former built-in `android_vr` 1.65.10 client is no longer a viable
no-token escape hatch: YouTube began returning HTTP 403 for all of its formats,
including itag 18, on August 17, 2026.

Retro-DLP switched to the WebPO-capable `mweb` client on August 26, 2026. The
first companion-provider experiment generated a video-bound token with BgUtils,
selected `mweb` itag 18, and downloaded the first 10 KiB of `EYBBXG8eyo0`.
More importantly, the native PowerPC build subsequently downloaded the complete
7,227,427-byte MP4 without a PO token using the `mweb` identity for the player
and media requests. The implementation now applies that same iPad/Safari user
agent to every native HTTP request. PO-token generation is therefore a fallback
for videos, sessions, networks, or future enforcement that reject this path,
rather than a blocker for the first working release. Current yt-dlp policy also
exempts YouTube Premium subscribers from the GVS PO-token requirement for HTTPS
and DASH media. Implement authenticated tokenless playback before investing
further in token generation, while retaining PO-token support for non-Premium
accounts, subtitles, rejected sessions, and future enforcement.

### Phase 6A: Cookie authentication and tokenless GVS playback

- [x] Add an `mweb` client definition to the updateable client manifest with
  numeric ID 2 and the current iPad/Safari user agent. Bootstrap each
  resolution from the mobile watch page to obtain the current client version,
  player URL, and signature timestamp rather than permanently hardcoding
  volatile values. Bump the built-in manifest key to `builtin-v2` so an
  existing installation cannot restore the cached `android_vr` definition.
- [x] Generalize client request construction so Android-specific fields are not
  emitted for Web-family clients.
- [x] Make the resolver's `mweb` user agent the single native HTTP identity.
  The common curl setup now obtains it from `yt_resolver.c`; generic GETs,
  bootstrap requests, player-JavaScript and asset downloads, probes, and full
  media downloads no longer accept a caller-selected user agent. Keep
  `--dump-json` reporting the identity for users who download the returned
  URL themselves with curl.
- [x] Validate a complete tokenless `mweb` itag 18 download on PowerPC Tiger:
  `EYBBXG8eyo0.mp4`, 7,227,427 bytes, on Darwin 8.11.0 PowerPC.
- [x] Add `--cookies FILE` with Mozilla/Netscape `cookies.txt` support. Keep
  browser-database discovery and decryption out of the portable resolver;
  export the YouTube session on a modern browser and transfer it securely.
- [x] Add unambiguous `--cookies-default` loading of
  `~/.retro-dlp/cookies.txt`, while preserving yt-dlp-compatible
  `--cookies FILE` for explicit paths.
- [x] Introduce a resolution-scoped native HTTP session shared by webpage,
  Innertube, player-JavaScript, probe, and media-download requests. Use
  libcurl's cookie engine and domain rules rather than constructing raw
  `Cookie` headers manually, and preserve `Set-Cookie` updates for the life of
  the resolution.
- [x] Treat a session as authenticated only when it contains `LOGIN_INFO` and
  at least one of `SAPISID`, `__Secure-1PAPISID`, or
  `__Secure-3PAPISID`, matching current yt-dlp behavior. Return a distinct
  stale/invalid-cookie classification when an imported session stops meeting
  this condition.
- [x] Implement yt-dlp-compatible timestamped SHA-1 Innertube authorization
  for every available SAPISID-family cookie. Bind the hash to the exact API
  origin and add the corresponding `SAPISIDHASH`, `SAPISID1PHASH`, and
  `SAPISID3PHASH` authorization values without logging their inputs or output.
- [x] Extract and preserve authenticated account-selection state from webpage
  configuration and initial data, including `SESSION_INDEX`, `DATASYNC_ID`,
  delegated/user session IDs, `LOGGED_IN`, and visitor data. Generate
  `X-Origin`, `X-Goog-AuthUser`, `X-Goog-PageId`, and
  `X-Youtube-Bootstrap-Logged-In` consistently with yt-dlp.
- [x] Use the authenticated `mweb` player request for itag 18 and attempt the
  GVS media request without a PO token. Let the media response be authoritative:
  continue on success and route HTTP 403 to the PO-token fallback. Do not gate
  this path on brittle Premium-logo or tooltip detection.
- [x] Isolate authenticated and anonymous success/failure cache entries. Do not
  allow an anonymous cached 403 to suppress an authenticated attempt, and do
  not persist account cookies, authorization headers, data-sync IDs, media
  URLs, or other session secrets in ordinary resolver caches.
- [x] Keep authenticated downloads inside Retro-DLP by default. Never print a
  raw cookie or authorization header in normal, debug, error, or
  `--dump-json` output; document that exported cookies are equivalent
  to account credentials and should be stored with owner-only permissions.
- [x] Add deterministic tests for Netscape parsing, cookie domain/path/expiry
  handling, SAPISID hash vectors, account/session fields, stale and malformed
  cookies, redaction, and authenticated/anonymous cache separation.
- [x] Validate the same exported session first with the pinned desktop yt-dlp
  using an explicit `mweb` client and itag 18; then compare Retro-DLP
  metadata, final URL structure, 10,241-byte MP4 probe, and complete download
  on Linux and PowerPC Tiger. Include non-Premium and deliberately incomplete
  cookies as negative fixtures that verify HTTP 403 fallback and invalid-session
  handling without relying on local subscription detection.
  - [x] Linux: pinned yt-dlp oracle returned HTTP 200; authenticated Retro-DLP
    returned HTTP 206 for both 10,241-byte fixtures and downloaded the complete
    7,227,427-byte `EYBBXG8eyo0` itag 18 MP4 without a PO token.
  - [x] Negative fixtures: anonymous media requests reproduced HTTP 403, and
    incomplete Netscape cookies returned the distinct invalid-authentication
    classification without making a network request.
  - [x] Cross-build the authenticated implementation in the quad-fat macOS
    PowerPC/i386/x86_64/arm64 binary and universal iOS ARMv7/ARM64 binary.
  - [x] PowerPC Tiger hardware (Darwin 8.11.0): both authenticated 10,241-byte
    fixtures returned HTTP 206, `YE7VzlLtp-4` downloaded as a 25,333,815-byte
    MP4, and `jdP8ZXSflqg` downloaded as a 12,836,383-byte MP4. The same binary
    reproduced anonymous HTTP 403 responses without cookies.

### Phase 6B: Explicit token ingestion and request binding

- [ ] Define a native PO-token request/response interface carrying at least:
  client family, token context (`gvs` initially), content-binding type and
  value, video ID, visitor/session data, expiry, and network identity where
  available.
- [ ] Add explicit token ingestion first, exposed by a temporary/test-oriented
  `--po-token TOKEN` option, so token validation and attachment can be tested
  independently of generation.
- [ ] Validate ingested tokens as base64url data, reject query-string fragments
  or malformed values, and never print tokens in normal, debug, or error logs.
- [ ] Detect whether the active WebPO experiment binds the GVS token to the
  video ID, visitor data/visitor ID, or authenticated data-sync ID. Do not
  assume one binding mode permanently.
- [ ] Append the token as the `pot` query parameter only to the matching GVS
  media URL. Never send it in unrelated Innertube, player-JavaScript, asset, or
  subtitle requests.
- [ ] If future enforcement requires more than the currently successful shared
  user agent, preserve additional `mweb` media headers such as `Accept`,
  `Accept-Language`, and `Sec-Fetch-Mode` through resolution, JSON output,
  probing, and the complete download.
- [ ] Never reuse a Web, Android, or iOS token across client families or reuse a
  token across incompatible binding types.
- [ ] Cache tokens only within their client, context, content binding, network
  identity, and provider-supplied expiry constraints. Prefer caching and
  reusing the more expensive integrity-token/minter state while minting a new
  content token for each video when required.
- [ ] Add deterministic tests for parsing, validation, query attachment,
  binding mismatches, expiry, cache isolation, header preservation, and token
  redaction.

### Phase 6C: Companion WebPO provider

Use the maintained BgUtils/BotGuard implementation on a modern companion
system first when tokenless `mweb` access is rejected. This provides a fallback
for the PowerPC and future iPhone clients while keeping token generation behind
a native interface that can later receive an embedded provider.

- [ ] Add `--po-provider URL` and a native HTTP provider implementation. Use a
  narrow JSON contract such as:

  ```json
  POST /get_pot
  {"content_binding":"EYBBXG8eyo0"}
  ```

  ```json
  {"poToken":"BASE64URL_TOKEN","expiresAt":"2026-08-26T11:42:13Z"}
  ```

- [ ] Pass the provider the active client context, token context, binding type,
  video ID, visitor/session data, and enough proxy/source-address information
  to ensure attestation and media requests use the same network identity.
- [ ] Require the companion and downloader to share the same public egress IP
  unless the provider explicitly proxies attestation through the downloader's
  route; WebPO state may be IP-bound.
- [ ] Default to a loopback or explicitly configured LAN endpoint. Require HTTPS
  and authenticated requests for non-local providers, impose strict response
  size and time limits, and never expose the provider to the public network by
  default.
- [ ] Distinguish provider-unavailable, provider-rejected, malformed-token,
  expired-token, and GVS-rejected-token failures.
- [ ] On an authenticated 403, invalidate only the matching cached token and
  retry once with a freshly minted token; prevent unbounded retry loops.
- [ ] Validate a complete `mweb` itag 18 MP4 download on Linux and PowerPC
  Tiger, then retain both the successful token-backed fixture and the no-token
  HTTP 403 fixture.

### Phase 6D: Embedded QuickJS WebPO generation

Treat standalone generation as a separate research and implementation
milestone. The existing EJS bundle solves `s` and `n`; it does not generate PO
tokens. Native WebPO generation must reproduce the BotGuard attestation flow:
obtain the current challenge and interpreter, execute a snapshot, exchange it
for an integrity token, construct a WebPO minter, and mint a token for the
current content binding.

- [ ] Pin and vendor or download-on-demand a reviewed BgUtils-compatible WebPO
  implementation with complete version, hash, and license metadata.
- [ ] Fetch the YouTube homepage/configuration and its self-consistent BotGuard
  challenge, download the referenced interpreter in native C, and pass only
  bounded source/data into QuickJS.
- [ ] Add the minimum browser environment required by the BotGuard interpreter,
  including tested implementations or shims for promises/jobs, timers,
  `TextEncoder`/`TextDecoder`, base64, randomness, performance timing,
  navigator/location, DOM operations, and any required canvas signals.
- [ ] Keep all networking in native C. Do not expose arbitrary filesystem,
  process, module-loading, or unrestricted network APIs to downloaded
  JavaScript.
- [ ] Execute the BotGuard snapshot, submit it to `GenerateIT`, honor the
  returned integrity-token TTL and mint-refresh threshold, and construct a
  reusable WebPO minter.
- [ ] Mint a fresh GVS content token for the detected binding, return it through
  the same native provider interface used by explicit and HTTP providers, and
  attach it through the already-tested Phase 6B path.
- [ ] Apply strict memory, stack, response-size, and execution deadlines. Destroy
  and recreate the QuickJS runtime after timeout, out-of-memory, interpreter,
  or unexpected attestation failures.
- [ ] Benchmark cold attestation, warm minting, peak memory, and interpreter
  compatibility on PowerPC Tiger before making embedded generation the default.
- [ ] Keep the companion HTTP provider as a supported fallback because the
  downloaded BotGuard interpreter and its browser-environment checks can change
  independently of Retro-DLP releases.

## 7. Package and validate for ARMv7 and iOS 5

- [ ] Complete the ARMv7/iOS 5 packaging and validation milestone.

Once the desktop resolver and EJS fixtures work, package the existing portable
resolver for iOS 5. QuickJS already works in the PowerPC build, so treat this
as platform integration and real-device validation rather than a separate
engine-porting effort. The remaining work is expected to be:

- [x] A universal ARMv7/iOS 5 and ARM64/iOS 7 build target
- [ ] A current libcurl/TLS stack and CA bundle
- [ ] Filesystem cache locations and storage limits
- [ ] Memory and latency instrumentation
- [ ] A serial background resolver execution model
- [ ] An Objective-C wrapper and user interface

- [ ] Test on a physical iPhone 4 throughout this phase. Simulator or successful
  cross-compilation alone cannot establish acceptable memory use, latency, or
  integration with iOS 5 platform services.
- [ ] Run the EJS fixtures and measure cold and warm execution time and peak
  memory on the physical iPhone 4.
- [ ] Keep the native resolver independent of UIKit so the same C API and
  fixtures remain usable by Linux, macOS, Tiger, and iOS front ends.

## 8. Add a signed update channel

- [ ] Complete the signed-update-channel milestone.

Add signed, versioned updates before attempting broad YouTube coverage. The
update package should be able to carry:

- [ ] Innertube client definitions and policy
- [ ] A yt-dlp-ejs source bundle
- [ ] Compatibility and minimum-resolver version metadata
- [ ] Cryptographic hashes for every included artifact

- [ ] Verify updates using a public key built into the application.
- [ ] Make installation atomic and rollback-capable.
- [ ] Retain a built-in last-known-good configuration.
- [ ] Reject updates that require a newer native resolver.

This prevents every YouTube client-version or EJS change from requiring a full
application rebuild and redeployment.

## Expected size and performance

These are planning estimates, not measurements:

- Approximately 1,000-2,000 lines of C for an intentionally crude direct-itag
  18 proof of concept
- Approximately 3,000-8,000 lines of application C for robust error handling,
  caching, multiple clients, EJS integration, and tests
- Plus QuickJS, libcurl/TLS, and a C JSON parser

For comparison, yt-dlp's current YouTube video extractor alone is more than
4,300 lines. Most of it handles metadata, playlists, manifests, subtitles, live
streams, authentication, multiple tracks, format ranking, and accumulated edge
cases that Retro-DLP can intentionally omit.

On the iPhone 4, the likely expensive cold operation is Meriyah parsing a
complete modern YouTube player script into an AST. Track these mitigations:

- [x] Bypass JavaScript entirely for direct URLs.
- [x] Invoke EJS only when a selected format requires it.
- [x] Solve all collected challenges in one batch.
- [x] Cache and reuse `preprocessed_player`.
- [x] Keep only the chosen progressive format.
- [x] Release raw player source and temporary results promptly.
- [ ] Run resolution away from the UI thread.
- [ ] Enforce measured memory, stack, and execution limits.

- [ ] Complete the first real-device EJS benchmark and record peak memory and
  cold/warm latency.
- [ ] If the results are unacceptable, investigate preprocessing on a newer
  companion system as an optional fallback without changing the resolver's
  public C interface.

## 9. Add adaptive 720p downloads with native MP4 muxing

- [ ] Complete the adaptive-download and native-muxing milestone.

Keep this as the final, optional expansion after the progressive download path
and real-device application are stable. YouTube commonly exposes only itag 18
as a directly downloadable MP4 containing both video and audio; higher-quality
entries are normally separate video-only and audio-only streams in
`streamingData.adaptiveFormats`.

- [x] Inspect `streamingData.adaptiveFormats` only for this path and retain the
  existing progressive `streamingData.formats` path as the first fallback.
- [x] Select an H.264 video stream at or below 720p and a compatible AAC/M4A
  audio stream. Prefer formats suitable for PowerPC Tiger and iPhone 4 playback.
- [x] Replace the resolution-oriented `--size` interface with exact yt-dlp-style
  `-f`/`--format` itag selection, supporting one progressive itag, one explicit
  video+audio pair, and `/`-separated explicit alternatives. Add
  `-F`/`--list-formats` and normalized `-j`/`--dump-json` output, keeping the
  complete format inventory exclusive to `--list-formats`.
- [x] Download both streams through the existing native HTTP/TLS, cookie,
  challenge-solving, PO-token, expiry, and atomic-file infrastructure.
- [x] Add or integrate a small, reviewed native ISO Base Media File Format muxer
  that combines the existing encoded tracks without decoding or re-encoding.
- [x] Do not require FFmpeg, MP4Box, or another external executable at runtime.
- [x] Bound parser input, allocation sizes, sample counts, and arithmetic; reject
  malformed or unsupported MP4 structures without publishing partial output.
- [ ] Preserve timestamps, duration, orientation, aspect ratio, and audio/video
  synchronization in the final MP4.
- [ ] Fall back cleanly to the best progressive MP4 at or below the requested
  size when adaptive selection, download, or muxing is unavailable.
- [ ] Validate the resulting 720p H.264/AAC MP4 on PowerPC Tiger and a physical
  iPhone 4, including long videos, unusual aspect ratios, interrupted transfers,
  expired URL recovery, and A/V synchronization.
