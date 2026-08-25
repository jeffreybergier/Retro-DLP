# Retro-DLP Implementation Plan

The initial goal is deliberately narrow: resolve an ordinary public YouTube
video to a directly downloadable, progressive H.264/AAC MP4 URL. The first
version will not support authentication, live streams, playlists, subtitles,
adaptive audio/video merging, conversion, DRM, SABR, or PO-token generation.

## 1. Build a desktop C resolver first

- [ ] Complete the desktop C resolver milestone.

Create a command-line program that accepts a YouTube URL or video ID:

```sh
retro-dlp VIDEO_ID
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

- [ ] Selected itag
- [ ] Final media host and important query fields
- [ ] Signature (`s`) result, when present
- [ ] Throttling (`n`) result, when present
- [ ] Range-request success

- [ ] Use the public Big Buck Bunny upload (`YE7VzlLtp-4`) as an initial live
  fixture, since yt-dlp also uses it in its YouTube extractor tests.
- [ ] Keep captured player responses and media metadata as deterministic
  offline fixtures so tests do not depend entirely on YouTube remaining
  unchanged.

## 2. Implement direct itag 18 only

- [ ] Complete the direct-itag-18 milestone without QuickJS.

Do not involve QuickJS yet. Implement the smallest complete resolution path:

- [ ] Parse and validate an 11-character YouTube video ID.
- [ ] Call one configured JSless Innertube client.
- [ ] Parse the player response JSON.
- [ ] Inspect `streamingData.formats` only.
- [ ] Select an immediately usable itag 18 URL.
- [ ] Return its URL, required headers, dimensions, MIME type, and expiry.
- [ ] Verify it with a small HTTP range request.

The validation request should ask for approximately the first 4 KiB, accept a
valid `206 Partial Content` or suitably small `200 OK`, and check for an ISO
Base Media File Format `ftyp` box rather than an HTML error response.

This phase proves the network, TLS, JSON parsing, client configuration, format
selection, result model, and download pipeline before JavaScript is introduced.

## 3. Add QuickJS and EJS

- [ ] Complete the QuickJS and EJS integration milestone.

Integrate a pinned yt-dlp-ejs bundle behind a small native adapter. Test it
independently of HTTP first:

```text
captured base.js + known s/n challenges
    -> C + QuickJS + EJS
    -> expected transformed values
```

- [ ] Integrate a pinned yt-dlp-ejs bundle behind a small native adapter.
- [ ] Maintain golden fixtures generated with matching desktop yt-dlp and EJS
  versions.
- [ ] Pass captured `base.js` and known `s`/`n` fixture tests.
- [ ] Connect the adapter to live player responses containing `signatureCipher`
  or an `n` query parameter.

- [ ] Ensure the production QuickJS embed exposes no native networking,
  filesystem, process, or dynamic-module APIs.
- [ ] Apply memory, stack, and execution deadlines.
- [ ] Recreate the runtime after an interruption, out-of-memory condition, or
  unexpected uncaught exception.
- [ ] Measure cold and warm EJS execution time and peak memory on an actual
  iPhone 4.
- [ ] Run the EJS fixtures on an actual PowerPC Mac.

## 4. Add caches

- [ ] Complete the caching milestone.

Add bounded, versioned caches for:

- [ ] The client manifest
- [ ] Raw player JavaScript
- [ ] EJS `preprocessed_player` output
- [ ] The most recently successful client, for a limited period
- [ ] Failure classifications, with short and error-specific lifetimes

- [ ] Key player artifacts by canonical player URL and/or a cryptographic hash.
- [ ] Make cache writes atomic.
- [ ] Safely discard corrupt or incompatible entries.
- [ ] Do not use downloaded QuickJS bytecode as a cache or update format.

## 5. Cross-compile for ARMv7 and iOS 4.3

- [ ] Complete the ARMv7/iOS 4.3 milestone.

Once the desktop resolver and EJS fixtures work, add the iOS target. The main
platform work is expected to be:

- [ ] QuickJS compilation and compatibility changes
- [ ] A current libcurl/TLS stack and CA bundle
- [ ] Filesystem cache locations and storage limits
- [ ] Memory and latency instrumentation
- [ ] A serial background resolver execution model
- [ ] An Objective-C wrapper and user interface

- [ ] Test on a physical iPhone 4 throughout this phase. Simulator or successful
  cross-compilation alone cannot establish acceptable memory use and latency.
- [ ] Keep the native resolver independent of UIKit so the same C API and
  fixtures remain usable by Linux, macOS, Tiger, and iOS front ends.

## 6. Add a signed update channel

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

- [ ] Bypass JavaScript entirely for direct URLs.
- [ ] Invoke EJS only when a selected format requires it.
- [ ] Solve all collected challenges in one batch.
- [ ] Cache and reuse `preprocessed_player`.
- [ ] Keep only the chosen progressive format.
- [ ] Release raw player source and temporary results promptly.
- [ ] Run resolution away from the UI thread.
- [ ] Enforce measured memory, stack, and execution limits.

- [ ] Complete the first real-device EJS benchmark and record peak memory and
  cold/warm latency.
- [ ] If the results are unacceptable, investigate preprocessing on a newer
  companion system as an optional fallback without changing the resolver's
  public C interface.
