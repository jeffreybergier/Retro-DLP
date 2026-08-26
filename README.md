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

Resolve without downloading or probing the media URL with:

```sh
build/linux/retro-dlp --no-download YE7VzlLtp-4
```

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

This runs deterministic cache, player-response, and batched `s`/`n` resolver
fixtures first, followed by a staged resolver test against yt-dlp's public Big
Buck Bunny fixture and a bodyless HEAD request to the resulting Google Video
URL. When EJS assets are
installed, it also runs the `s`/`n` tests for batching, preprocessed-player
reuse, malformed output, exceptions, execution deadlines, memory limits, and
runtime recovery. Otherwise that section reports a skip with the installation
command. The live portion requires internet access. A current HTTP 403 is
reported as a successful transport probe with a PO-token-required
classification; it does not mean that the video was downloaded. The tests
execute inside the current binary slice, making them suitable for checking the
actual PowerPC, i386, x86_64, arm64, or Linux build on its target machine.

`make test` additionally runs the pinned vendored yt-dlp with the same
`android_vr` client. It compares selected format metadata, the Google Video
media service and stable query fields, direct signature parameter choice,
absence of an unsolved `n`, and the HEAD result/classification.

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
- `source/iOS`: reserved for a future iOS target
- `source/deps`: vendored dependencies, when needed
- `source/make/Makefile`: complete cross-platform build graph
- `source/make/apple-gcc4.mk`: isolated PowerPC/i386 and Tiger build profile
- `source/make/clang.mk`: isolated x86_64/arm64 and pristine QuickJS profile

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
