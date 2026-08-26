# Retro-DLP Implementation Plan

The initial goal is deliberately narrow: resolve an ordinary public YouTube
video to a directly downloadable, progressive H.264/AAC MP4 URL. The first
version will not support authentication, live streams, playlists, subtitles,
adaptive audio/video merging, conversion, DRM, SABR, or PO-token generation.

## 1. Build a desktop C resolver first

- [x] Complete the desktop C resolver milestone.

Create a command-line program that accepts a YouTube URL or video ID:

```sh
retro-dlp --no-download VIDEO_ID
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
- [x] HEAD request status and failure classification

- [x] Use the public Big Buck Bunny upload (`YE7VzlLtp-4`) as an initial live
  fixture, since yt-dlp also uses it in its YouTube extractor tests.
- [x] Keep sanitized captured player responses and media metadata as
  deterministic embedded fixtures so the core parser and classifications can
  run without the network.
- [x] Keep a live integration test so tests do not depend entirely on captured
  responses remaining representative of YouTube.

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
- [x] Probe it with a bodyless HTTP HEAD request and classify HTTP 403 as the
  current PO-token limitation.
- [x] Make `retro-dlp VIDEO_ID_OR_URL` stream the complete itag 18 MP4 into the
  current directory by default.
- [x] Make `--no-download` return resolver JSON without probing or downloading.
- [x] Write through an exclusive `.part` file, validate the MP4 `ftyp` box,
  refuse overwrites, remove handled failures, and publish atomically.
- [x] Classify a full-download HTTP 403 independently of the diagnostic HEAD
  request. The first Linux live download reached GVS and confirmed the current
  `po_token_required` limitation without leaving a partial file.

The embedded live test retains its bodyless HEAD comparison so routine tests do
not download the fixture. Normal CLI use performs the complete streaming GET,
and that result is authoritative for actual download capability.

This phase proves the network, TLS, JSON parsing, client configuration, format
selection, result model, and download pipeline before JavaScript is introduced.

## 3. Add QuickJS and EJS

- [ ] Complete the QuickJS and EJS integration milestone.

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
7. [ ] **Validate end to end.** Preserve the direct-URL fast path, compare final
   `s` and `n` values with the pinned yt-dlp oracle, probe the resulting media
   URL, and keep PO-token failures distinct from EJS failures.

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

## 6. Add GVS PO-token support

- [ ] Complete the GVS PO-token milestone.

The complete download path now establishes that current itag 18 URLs can reach
GVS but receive HTTP 403 without attestation. Keep PO-token failures distinct
from signature and throttling challenge failures.

- [ ] Define a native provider interface that binds tokens to the correct
  client, visitor/session, video ID, and token lifetime.
- [ ] Add explicit token ingestion first so provider output can be tested
  independently of token generation.
- [ ] Attach the token only to the matching GVS media request and never reuse a
  Web, Android, or iOS token across client families.
- [ ] Cache tokens only within their binding and expiry constraints.
- [ ] Add a provider implementation suitable for the selected client.
- [ ] Validate a complete MP4 download and retain the no-token 403 fixture.

## 7. Package and validate for ARMv7 and iOS 5

- [ ] Complete the ARMv7/iOS 5 packaging and validation milestone.

Once the desktop resolver and EJS fixtures work, package the existing portable
resolver for iOS 5. QuickJS already works in the PowerPC build, so treat this
as platform integration and real-device validation rather than a separate
engine-porting effort. The remaining work is expected to be:

- [ ] An ARMv7/iOS 5 build target
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
