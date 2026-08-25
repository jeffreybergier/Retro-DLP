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

The Linux executable compiles and links the vendored cJSON submodule. The
macOS executable links the quad-fat static AltivecCore archive, which supplies
cJSON and the rest of AltivecCore on each supported Mac architecture.

Run `make clean` to empty the three build output directories without deleting
the directories themselves.

## Source layout

- `source/shared`: portable CLI code
- `source/macOS`: macOS-specific implementations
- `source/linux`: Linux-specific implementations
- `source/iOS`: reserved for a future iOS target
- `source/deps`: vendored dependencies, when needed

Initialize cJSON and QuickJS after cloning:

```sh
git submodule update --init --recursive
```
