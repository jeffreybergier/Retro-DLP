# Retro-DLP

`retro-dlp` is a command-line tool built as one quad-fat macOS executable for
PowerPC, i386, x86_64, and arm64. The project uses the Altivec toolchains while
keeping platform sources, tests, products, and intermediate files separate.

## Build

Build the macOS release executable with the Altivec environment:

```sh
make release
```

The results are `build/macOS/retro-dlp` and its required certificate bundle,
`build/macOS/cacert.pem`. Distribute both files in the same directory.
Architecture-specific objects and linked slices stay under
`build/intermediates/macOS`.

Build and test the native Linux executable:

```sh
make linux
make test
```

Build the universal iOS command-line executable with the Altivec environment:

```sh
make iOS
```

The result is `build/iOS/retro-dlp`, containing an ARMv7 slice with an iOS 5.0
deployment target and an ARM64 slice with an iOS 7.0 deployment target. Its
required `build/iOS/cacert.pem` must be installed beside the executable. This
is the UIKit-independent resolver build intended for the future Objective-C
wrapper; it is not yet an application bundle.

The Linux product is `build/linux/retro-dlp`; its intermediate objects stay
under `build/intermediates/linux`. Shared tests live under `source/shared/test`;
future platform-specific tests belong under `source/<platform>/test`.

Download a public YouTube video to the current directory:

```sh
build/linux/retro-dlp YE7VzlLtp-4
build/linux/retro-dlp 'https://www.youtube.com/watch?v=YE7VzlLtp-4'
```

The default command streams into `VIDEO_ID.mp4.part`, validates the MP4 `ftyp`
box, and atomically publishes `VIDEO_ID.mp4` after success. It refuses to
overwrite an existing final or partial file and removes partial output after a
handled failure. A full-download HTTP 403 is reported as `po_token_required`.
Resolver stages and download status are written to stderr, while the final JSON
result remains on stdout. The media transfer enables libcurl's built-in
progress meter; it is supplied by libcurl rather than by launching the `curl`
command-line program.

Resolve without downloading or probing the media URL with:

```sh
build/linux/retro-dlp --no-download YE7VzlLtp-4
```

Use an authenticated YouTube session exported in Mozilla/Netscape
`cookies.txt` format with:

```sh
build/linux/retro-dlp --cookies /path/to/youtube-cookies.txt YE7VzlLtp-4
build/linux/retro-dlp --cookies /path/to/youtube-cookies.txt \
  --no-download YE7VzlLtp-4
```

If the exported file is stored at `~/.retro-dlp/cookies.txt`, omit the path:

```sh
retro-dlp --cookies YE7VzlLtp-4
retro-dlp --cookies --no-download YE7VzlLtp-4
```

The argument following `--cookies` is treated as the video when it is a valid
11-character YouTube ID or supported YouTube URL. Otherwise, it is treated as
an explicit cookie-file path.

Retro-DLP accepts a cookie file as authenticated only when it contains a
current `LOGIN_INFO` cookie and at least one current `SAPISID`,
`__Secure-1PAPISID`, or `__Secure-3PAPISID` cookie for YouTube. It uses those
cookies to generate the timestamped SHA-1 authorization required by Innertube
and preserves the same in-memory libcurl cookie session through webpage,
player, JavaScript, probe, and media requests. An authenticated `mweb` media
request is attempted without a GVS PO token; HTTP 403 remains the authoritative
`po_token_required` result and will feed the future PO-token fallback.

Cookie files grant access to the associated YouTube account. Store them outside
the repository with owner-only permissions (`chmod 600`), never commit or share
them, and avoid using an active browser session whose cookies YouTube may
rotate. Retro-DLP never includes cookies, SAPISID authorization, account sync
IDs, or other session secrets in result JSON or resolver caches. Authenticated
and anonymous success/failure cache entries are separate.

This prints JSON containing the direct URL, itag, dimensions, MIME type, expiry
time, and required request headers. Retro-DLP supports itag 18 returned by its
configured client and does not yet generate PO tokens.

On macOS, every libcurl handle is configured with `cacert.pem` resolved beside
the running executable. Network requests fail explicitly if the bundle is
missing or unreadable. Linux continues to use libcurl's system trust settings.

The Linux executable compiles and links the vendored cJSON submodule. It also
builds QuickJS as `build/intermediates/linux/libquickjs.a` and statically links
the complete engine into the executable. The resource-limited native adapter
loads the pinned `yt-dlp-ejs` 0.8.0 JavaScript assets from
`~/.retro-dlp/cache/assets`; release binaries do not embed those assets. The
resolver preserves a no-JavaScript fast path for direct itag 18 URLs. When the
selected itag 18 contains `signatureCipher` or an `n` parameter, it obtains and
caches the player JavaScript, submits all required transformations to EJS in
one batch, and rejects an unresolved challenge.
The macOS executable links the quad-fat static AltivecCore archive, which
supplies cJSON and the rest of AltivecCore on each supported Mac architecture.
QuickJS is compiled into a separate static archive for each of the PowerPC,
i386, x86_64, and arm64 macOS slices.

Install, inspect, or remove the EJS assets with:

```sh
retro-dlp assets install
retro-dlp assets status
retro-dlp assets remove
```

Run `make clean` to empty the three build output directories without deleting
the directories themselves.

Run the embedded cJSON and QuickJS smoke tests directly on any supported
platform:

```sh
retro-dlp --test
```

Supply authenticated cookies to run the same fixtures through the tokenless
authenticated media path:

```sh
retro-dlp --cookies /path/to/youtube-cookies.txt --test
retro-dlp --cookies --test
make test TEST_COOKIES=/absolute/path/to/youtube-cookies.txt
```

This runs deterministic cache, player-response, and batched `s`/`n` resolver
fixtures first, followed by staged resolver tests for `YE7VzlLtp-4` and
`-_x6t4CaPzo`. Each live test requests the same 10,241-byte prefix as yt-dlp's
test mode from the resulting Google Video URL and validates the returned MP4
prefix. When EJS assets are
installed, it also runs the `s`/`n` tests for batching, preprocessed-player
reuse, malformed output, exceptions, execution deadlines, memory limits, and
runtime recovery. Otherwise that section reports a skip with the installation
command. The live portion requires internet access and a successful 2xx media
response; a PO-token-related HTTP 403 fails the self-test. The tests
execute inside the current binary slice, making them suitable for checking the
actual PowerPC, i386, x86_64, arm64, or Linux build on its target machine.

`make test` additionally runs the pinned vendored yt-dlp with the same `mweb`
client. It compares selected format metadata, the Google Video
media service and stable query fields, direct signature parameter choice,
matching transformed-`n` parameter presence, and the HEAD
result/classification.

The resolver keeps bounded, versioned caches under `~/.retro-dlp/cache/v1` for
the active client manifest, raw player JavaScript, EJS preprocessed players,
the most recently successful client, and short-lived failure classifications.
Player artifacts use SHA-256 keys, and corrupt or expired entries are discarded.

## Source layout

- `source/shared`: portable CLI code
- `source/shared/test`: tests embedded into every platform binary
- `source/linux/test`: Linux-only CLI integration tests
- `source/macOS`: macOS-specific implementations
- `source/linux`: Linux-specific implementations
- `source/iOS`: iOS platform integration and Clang compatibility sources
- `source/deps`: vendored dependencies, when needed
- `source/make/Makefile`: complete cross-platform build graph
- `source/make/apple-gcc4.mk`: isolated PowerPC/i386 and Tiger build profile
- `source/make/clang.mk`: isolated x86_64/arm64 and pristine QuickJS profile
- `source/make/ios-clang.mk`: universal ARMv7/ARM64 iOS Clang profile

Tiger-specific compatibility sources can be added with
`LEGACY_MACOS_EXTRA_SOURCES`; legacy-only flags and libraries can be added with
`LEGACY_MACOS_EXTRA_CPPFLAGS`, `LEGACY_MACOS_EXTRA_CFLAGS`, and
`LEGACY_MACOS_EXTRA_LIBRARIES`. These inputs are not used by the modern Clang
build. QuickJS source-level compatibility work should likewise be staged as a
legacy-only source or forced-include compatibility header rather than changing
the vendored submodule used by `source/make/clang.mk`.

The current Apple GCC 4 profile uses an isolated compatibility layer under
`source/macOS/apple-gcc4/QuickJS`. It provides C11-style atomics—including a
mutex-backed 64-bit implementation for 32-bit CPUs—and a Tiger-compatible
`clock_gettime` implementation. The Clang profile compiles the unmodified
QuickJS submodule without this layer.

Initialize cJSON and QuickJS after cloning:

```sh
git submodule update --init --recursive
```

# License

Retro-DLP is licensed under the [MIT License](https://opensource.org/license/mit/).
It includes, links against, downloads, or uses for testing components that
remain subject to their own licenses:

- [QuickJS](https://github.com/bellard/quickjs/blob/master/LICENSE) — MIT
- [cJSON](https://github.com/DaveGamble/cJSON/blob/master/LICENSE) — MIT
- AltivecCore — [MIT](https://opensource.org/license/mit/)
- [libcurl](https://curl.se/docs/copyright.html) — curl license
- [OpenSSL](https://www.openssl.org/source/license.html) — OpenSSL licenses
- [yt-dlp](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE) — Unlicense
- [yt-dlp-ejs](https://github.com/yt-dlp/ejs/blob/main/LICENSE) — Unlicense;
  its prebuilt assets also contain
  [Meriyah](https://github.com/meriyah/meriyah/blob/master/LICENSE.md) under ISC
  and [Astring](https://github.com/davidbonnet/astring/blob/main/LICENSE) under
  MIT

Each third-party component is provided under its respective license, and those
licenses apply independently of Retro-DLP's MIT license.
