# Retro-DLP

`retro-dlp` is a command-line tool built as one quad-fat macOS executable for
PowerPC, i386, x86_64, and arm64. The project uses the Altivec toolchains while
keeping platform sources, tests, products, and intermediate files separate.

## Build

Build the macOS release executable with the Altivec environment:

```sh
make release
```

The result is `build/macOS/retro-dlp`. Architecture-specific objects and
linked slices stay under `build/intermediates/macOS`.

Build and test the native Linux executable:

```sh
make linux
make test
```

The Linux product is `build/linux/retro-dlp`; its intermediate objects stay
under `build/intermediates/linux`. Platform tests belong under the matching
directory in `tests` (currently `tests/linux`).

The Linux executable compiles and links the vendored cJSON submodule. It also
builds QuickJS as `build/intermediates/linux/libquickjs.a` and statically links
the complete engine into the executable. The macOS executable links the
quad-fat static AltivecCore archive, which supplies cJSON and the rest of
AltivecCore on each supported Mac architecture. QuickJS is also compiled into
separate x86_64 and arm64 static archives and linked only into those two modern
macOS slices; the PowerPC and i386 slices do not contain QuickJS.

Run `make clean` to empty the three build output directories without deleting
the directories themselves.

## Source layout

- `source/shared`: portable CLI code
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

Initialize cJSON and QuickJS after cloning:

```sh
git submodule update --init --recursive
```
