# Retro-DLP

Paths and commands below are relative to this repository. Retro-DLP is a narrow
C implementation of video and playlist resolution for older Apple devices. It
uses libcurl, QuickJS, L-SMASH, and cJSON. Supported targets are Linux, macOS
10.4+ (PowerPC/i386), and jailbroken iOS 5+ (armv7; arm64 requires iOS 7+).
Apple builds use the pinned Altivec Intelligence container and user-supplied SDKs.

## Layout and builds

- The portable resolver, public headers, examples, and tests are in
  `source/library/shared/`; platform code is in `source/library/{linux,macOS,iOS}/`.
  The CLI is in `source/cli/`. Shared app code and its Foundation bridge are in
  `source/gui/shared/`; native UI is in `source/gui/{macOS,iOS}/`. Build rules
  are in `make/`; `build/` is ignored generated output. Keep
  `source/deps/{cJSON,QuickJS,L-SMASH}` pinned submodules with intact layouts.
- Build with `make linux`, `make macOS`, `make iOS`, or `make apps`. For Apple
  builds, first run `docker compose run --rm altivec-sdk install`, then
  `docker compose run --rm altivec "make clean release"`. Outputs include
  `build/macOS/ppc-i386/retro-dlp`, `build/iOS/retro-dlp`, platform static
  libraries, `build/apps/macOS/RetroDLP.zip`, and `build/apps/iOS/RetroDLP.ipa`.
  Apps bundle the CA certificate and version-matched EJS assets. The IPA uses
  jailbreak-oriented `ldid` signing, not Apple distribution signing.
- Run `make test` for library, CLI, or build changes; `make sanitize` for C
  memory, parsing, or ownership risks; `make app-test` for shared app changes.
  Build affected apps with `make app-macOS` or `make app-iOS`, both with
  `make apps` for shared native changes. Use `make app-validate` and
  `make validate-apple-artifacts` for affected Apple packages;
  `make validate-package` checks an external Linux C consumer.
  `make examples` builds public API examples; `make validate-examples` also
  runs the offline custom-transport example. Inspect warnings and clean outputs
  when incremental builds might hide dependency problems. Cross-builds and
  artifact checks do not establish device launch or playback behavior.
- `make package-libraries` produces library ZIPs after all three platform
  builds. Linux supports `make install PREFIX=/usr/local DESTDIR=/package/root`.
  Library ZIPs contain public headers, static libraries, C examples, and
  `LICENSE`. Build and packaging steps must not read, copy, or emit Markdown.

## CLI and releases

- `retro-dlp -t low|med|high VIDEO` selects presets; `-F` lists formats;
  `-f '137+599/137+140/136+140'` tries exact alternatives in order. `+`
  combines video and audio, `/` separates alternatives, and the default is
  `22/18`. `--dump-json` prints metadata; `--simulate` resolves without
  writing; `--flat-playlist [-j] PLAYLIST` lists entries without per-video
  resolution. `--cookies FILE` and `--cookies-default` use Netscape cookies;
  the default path is `~/.retro-dlp/cookies.txt`. `assets install` provisions
  EJS assets. CLI ZIPs require `retro-dlp` and `cacert.pem` together.
- The implementation identifies as YouTube `mweb`. It does not generate PO
  tokens or support WebM, VP9, AV1, Opus, transcoding, or yt-dlp selectors.
  Higher-quality requests may fail with HTTP 403. Keep credentials, downloaded
  EJS assets, SDK archives, and build outputs out of Git.
- Release configuration is `.altivec-release.yml`; automation is
  `.github/workflows/release.yml`. Keep the image digest in `compose.yml`
  consistent. From a clean committed checkout, use
  `docker compose run --rm altivec "altivec-release bump patch"` (or `minor` /
  `major`; `--dry-run` previews). A `v` tag builds macOS/iOS CLI, app, and
  library assets; branch pushes run checks. CI verifies private SDK hashes and
  layouts and validates packages before upload. Linux users build from source.

## Public C API

- The supported API is in `source/library/shared/include/retrodlp/`:
  `retrodlp.h`, `assets.h`, `download.h`, and `version.h`. Public `rdlp_*`
  symbols are the contract; private headers and `yt_*` symbols may change.
  Within a major version, preserve signatures, enum values, ownership, and
  documented behavior. Append fields only to `struct_size` structures;
  callers zero them and set `struct_size`, and implementations respect the
  caller's size.
- Create/destroy an `rdlp_context` for resolver and playlist operations.
  A context runs one operation at a time; reentrant or concurrent use returns
  `RDLP_ERROR_CONTEXT_BUSY`. Independent contexts may run concurrently.
  Callbacks are synchronous on the operation thread and must not start another
  operation on that context. Callback and custom-transport contexts are borrowed
  until context destruction; configuration paths are copied.
- `NULL` configuration uses libcurl, system trust, a 60-second network
  timeout, no cache/cookies, progressive MP4 preference, and a 720-pixel height
  limit. Supplied cache, CA, and EJS directories must be absolute. Cookie-file
  input and caller-owned Netscape cookie bytes are mutually exclusive; bytes
  only need to live through the operation. The core library never infers paths
  from `$HOME` or writes to stdout/stderr.
- EJS inspection, installation, and removal use an explicit absolute directory
  and version-matched `core.min.js` and `lib.min.js`. Installation verifies
  hashes and writes atomically; it never runs implicitly during resolution.
- `rdlp_resolve_video` returns a progressive request or adaptive video/audio
  pair; playlist calls return ordered entries. Destroy owned selections,
  playlists, and collections with their matching destroy calls. Accessor
  strings and media headers are borrowed until the parent is destroyed. For
  adaptive selections, media index 0 is video and 1 is audio; send every
  provided header when fetching. Failed operations clear output pointers.
  Branch on negative `rdlp_error_code`, not diagnostic messages.
- Exact and automatic selection choose the original audio track before DRC,
  challenge, or bitrate preferences. Never silently substitute a known dub.
  Ambiguous multilingual responses fail; unambiguous single-track responses
  remain supported. Adaptive muxing records a known audio language in the MP4;
  progressive files pass through unchanged.
- Playlist metadata comes from existing browse responses without individual
  video or thumbnail requests. Entries preserve order and duplicates. Optional
  duration and exact view count distinguish absent from zero; rounded or live
  counts stay as source text. Publication labels can be relative, snippets can
  be truncated, and thumbnails are URL strings only.
- Resolver and download callbacks report typed events and support cancellation.
  The optional `libretrodlp-download.a` uses the selection's headers,
  exclusive `.part` files, and MP4 muxing; source tracks remain after mux
  failure. Link it before `libretrodlp.a`. Linux resolver consumers also link
  `-lcurl -lcrypto -lm -ldl -lpthread`; Apple consumers need AltivecCore,
  `libcrypto.a`, Foundation, CoreFoundation, SystemConfiguration, `-lobjc`,
  `-lm`, and `-lpthread` (plus Security on iOS). See
  `source/library/shared/examples/` for usage. Custom transports must enforce
  HTTPS/redirect policy, response limits, timeouts, and cancellation.

## Native apps

- Both apps consume the public libraries through `RDLPLibrary`, the shared
  Objective-C facade. Put application C APIs, C callbacks, raw buffers, and
  store/service access in `source/gui/shared/RDLPLibrary.m` and portable C
  files. Keep `rdapp_store.{h,c}` and `rdapp_service.{h,c}` portable. Put shared
  Foundation code in `source/gui/shared/`, AppKit UI in `source/gui/macOS/`,
  and UIKit UI in `source/gui/iOS/`. Keep platform library behavior in the
  existing `RDLPLibrary+macOS.m` and `RDLPLibrary+iOS.m` categories.
- Use manual retain/release in app Objective-C; iOS is not an ARC target.
  Balance delegate/callback ownership and update Cocoa UI on the main thread.
  Do not use Objective-C dot syntax. Prefer C for non-UI logic. Put C support
  in C files or the designated bridge; narrow system-API exceptions already
  present in platform categories and `RDLPDownloadPolicy.m` may remain.
  Keep SDK/platform conditionals and diagnostic pragmas in `RDLPAppKit.m`,
  `RDLPUIKit.m`, or `RDLP_Foundation.m`; use runtime-checked helpers elsewhere.
  Do not suppress deprecated-API warnings in app-owned code. Tiger PPC code
  cannot use blocks; the existing iOS player can. Preserve `RDLP` names and
  persisted keys, notification names, and window identifiers.
- Table counts and copies must not load all rows. `RDLPLibraryRows` fetches
  displayed rows on demand and caches at most 128; keep indexed sequential
  reads and bounded caches. Do not scan every job for every entry or check
  offscreen files during rendering. Preserve playlist occurrence identity,
  duplicate entries, stable job IDs, and read-only SQLite snapshots. Recheck
  identities and files before write actions. Drain autorelease pools in long
  loops; measure scrolling and bulk work on target devices.
- Shared download policy decides playable-file and job state behavior. Only
  completed regular files are playable; stat results may be cached for display
  but actions recheck. Playlist sync persists optional metadata per
  `(playlist_id, position)` and updates matching jobs atomically. Thumbnail
  URLs are stored without fetching images. Missing optional fields remain
  missing; relative publication labels are marked as last-sync data.
- Shared status messages describe the current resolver/download phase and
  transfer bytes. Each idle message expires after ten seconds; navigation and
  refresh do not reset it. Errors and recovery warnings use a separate native
  alert queue; user cancellation does not open an alert. Cookie and file
  bookkeeping do not write status messages.
- The iOS player in `source/gui/iOS/player/` is a reusable, manually managed
  AVPlayer UI and queue independent of the database and downloader. The queue
  retains the full ordered URL snapshot, prepares only current/next items,
  preserves duplicates, and posts changes on the main thread. App integration
  lives in `RDLPDownloadedPlayerViewController`, which owns bookmarks, audio
  session, remote commands, Now Playing metadata, and teardown. Run
  `python3 source/gui/iOS/player/tests/check.py` for standalone cross-build
  and static-analysis checks; device playback remains a separate test.
- Generated icons are committed resources; ordinary builds must not run their
  generators. Regenerate with `source/gui/shared/artwork/prepare_icons.sh`
  and `source/gui/shared/scripts/generate_icons.py`, then validate packages.
  Keep each ICNS element at most 300,000 bytes and the whole file at most
  1,000,000 bytes for Leopard. Preserve Tiger legacy representations and the
  iOS legacy icon and launch-image declarations. Font Awesome player assets
  carry their bundled license; account for screen scale when rendering icons.

## Research and fixtures

- Upstream protocol references include yt-dlp's YouTube extractor and PO Token
  Guide, yt-dlp EJS, QuickJS, and YouTube embedded-player parameters. They are
  research sources, not build dependencies. Cite the specific upstream change
  when adjusting protocol behavior.
- `source/library/shared/tests/fixtures/` includes tiny generated H.264/AAC
  mux inputs; offline tests do not require FFmpeg at runtime. Do not commit
  local investigation artifacts, credentials, or device data.
