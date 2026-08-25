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

Resolve a public YouTube video to a progressive MP4 media request:

```sh
build/linux/retro-dlp YE7VzlLtp-4
build/linux/retro-dlp 'https://www.youtube.com/watch?v=YE7VzlLtp-4'
```

The command prints JSON containing the direct URL, itag, dimensions, MIME type,
expiry time, required request headers, and the result of a bodyless media HEAD
probe. HTTP 403 is represented as the machine-readable classification
`po_token_required`. The phase-one resolver intentionally supports only direct
itag 18 returned by its configured JSless client. It rejects URLs containing
an unsolved `n` challenge and does not yet solve JavaScript challenges or
generate PO tokens.

On macOS, every libcurl handle is configured with `cacert.pem` resolved beside
the running executable. Network requests fail explicitly if the bundle is
missing or unreadable. Linux continues to use libcurl's system trust settings.

The Linux executable compiles and links the vendored cJSON submodule. It also
builds QuickJS as `build/intermediates/linux/libquickjs.a` and statically links
the complete engine into the executable. The macOS executable links the
quad-fat static AltivecCore archive, which supplies cJSON and the rest of
AltivecCore on each supported Mac architecture. QuickJS is compiled into a
separate static archive for each of the PowerPC, i386, x86_64, and arm64
macOS slices.

Run `make clean` to empty the three build output directories without deleting
the directories themselves.

Run the embedded cJSON and QuickJS smoke tests directly on any supported
platform:

```sh
retro-dlp --test
```

This runs deterministic embedded player-response fixtures first, followed by a
staged resolver test against yt-dlp's public Big Buck Bunny fixture and a
bodyless HEAD request to the resulting Google Video URL. The live portion
therefore requires internet access. A current HTTP 403 is reported as a
successful transport probe with a PO-token-required classification; it does not
mean that the video was downloaded. The tests execute inside the current binary
slice, making them suitable for checking the actual PowerPC, i386, x86_64,
arm64, or Linux build on its target machine.

`make test` additionally runs the pinned vendored yt-dlp with the same
`android_vr` client. It compares selected format metadata, the Google Video
media service and stable query fields, direct signature parameter choice,
absence of an unsolved `n`, and the HEAD result/classification. Python 3 is
required for this Linux integration comparison.

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
