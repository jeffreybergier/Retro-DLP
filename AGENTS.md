# Retro-DLP

Paths and commands below are relative to this repository. Read `README.md` for
the source layout and supported platforms. For library API work, read
`docs/library-api.md`; for native app work, read `docs/cocoa-apps.md`, especially
its shared architecture and platform boundaries. `PLAN.md` is planning context:
check the current implementation before treating an item there as unfinished.

## Build and validation

- Run `make test` for library, CLI, or build-system changes. Run `make sanitize`
  when changing C code with memory, parsing, or ownership risks.
- Run `make app-test` for changes to the shared app store, service, or bridge.
  Build the affected app with `make app-macOS` or `make app-iOS` for platform
  changes. Build both with `make apps` when shared app code or common native
  inputs change. Clean affected outputs when an incremental build could hide
  a dependency or configuration problem.
- Inspect compiler warnings as well as errors. Keep the supported macOS PPC
  and i386, iOS armv7 and arm64, and native Linux targets in mind. Apple builds
  require the Altivec toolchain and SDK inputs described in `README.md`.
- A cross-build, static analysis run, or artifact check does not establish that
  an app launches on a Mac or iOS device. Report device launch testing
  separately, including when it was not performed.
- `make app-validate` checks built app artifacts; `make validate-apple-artifacts`
  checks Apple CLI and library artifacts. Use the relevant check when changing
  packaging or release inputs.

## Library and component boundaries

- Preserve the supported C API declared in
  `source/library/shared/include/retrodlp/`. Applications and examples include
  those public headers, not private `source/library/shared` headers. Follow the
  compatibility, structure-size, ownership, and error rules in
  `docs/library-api.md`. Internal `yt_*` symbols are not a public API.
- Keep the CLI, portable library, optional download library, and Cocoa apps
  separated as described in `README.md` and `docs/cocoa-apps.md`. The apps
  consume the public Retro-DLP libraries; do not make their UI depend on
  resolver internals.
- Keep `source/gui/shared/rdapp_store.{h,c}` and `rdapp_service.{h,c}` portable.
  Shared Foundation code belongs in `source/gui/shared/`; AppKit and UIKit UI
  code belongs in `source/gui/macOS/` and `source/gui/iOS/`, respectively.
- Both UIs use the shared `RDLPLibrary` Objective-C facade. Keep application C
  APIs, C callbacks, raw buffers, and store/service access in the designated
  `source/gui/shared/RDLPLibrary.m` bridge and portable C files. UI controllers
  use Objective-C methods and objects rather than reaching into SQLite or
  resolver internals. Keep platform-specific library behavior in the existing
  `RDLPLibrary+macOS.m` and `RDLPLibrary+iOS.m` categories.

## Objective-C and compatibility

- Follow the existing manual retain/release convention in shared, macOS, and
  iOS Objective-C code. Retro-DLP's iOS UI is not an ARC target. Balance
  ownership, including delegates and callbacks, and keep Cocoa UI updates on
  the main thread.
- Do not use dot syntax in Objective-C
- Do not write C code in Objective-C, use companion C files to support 
  Objective-C code if necessary. Or use the designated C/Objective-C bridge file
  called 'RDLPLibrary.m'
- Prefer writing non-UI logic in C rather than Objective-C for performance 
  reasons
- Performance matters on retro devices. Avoid repeated work proportional to
  playlist size during row rendering or scrolling. Measure large-list operations
  on target devices before changing algorithms for performance.
- Avoid repeated database queries and row construction for the same displayed
  item. Reuse already loaded row data where practical.
- When rendering table views, obtain row counts without loading every row's
  details. Fetch details lazily for requested rows, using an indexed query or
  bounded cache to resolve row identities as needed. Do not preload an entire
  playlist solely to map row indexes to identities.
- In long loops that create autoreleased objects, use a local autorelease pool
  and drain it in bounded batches. Release owned objects promptly, and choose
  the batch size based on memory use and measured performance.
- Check both compile-time SDK availability and runtime availability before
  using newer Cocoa APIs. Prefer the existing `RDLPAppKit` and `RDLPUIKit`
  compatibility helpers where they cover the operation. Keep deprecation or
  availability warning suppressions narrow and next to the compatibility code;
  do not silence unrelated warnings.
- macOS code must remain compatible with Tiger and its PPC compiler: do not
  introduce blocks into code built for that target. This restriction does not
  apply to the existing iOS player code, which uses blocks.
- Follow existing `RDLP` class and file naming in app-owned code. Preserve
  persisted preference keys, notification names, and window identifiers when
  reorganizing classes so existing user state remains readable.

## Repository and release inputs

- Keep local SDK archives, secrets, downloaded EJS assets, generated runtime
  assets, and build outputs out of Git. Do not commit credentials, including
  cookies or local test keys.
- Preserve `source/deps/cJSON`, `source/deps/QuickJS`, and
  `source/deps/L-SMASH` as pinned Git submodules. Keep their upstream layouts
  intact; make project integration changes outside them where possible.
- Release packaging is configured in `.altivec-release.yml`; GitHub release
  automation is in `.github/workflows/release.yml`. Use those files and the
  release instructions in `README.md` when changing release behavior.
