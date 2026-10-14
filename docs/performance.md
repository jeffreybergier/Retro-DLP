# Native collection performance

These offline tests use the real Retro-DLP playlist controllers, SQLite row
sources, workers, and AppKit/UIKit tables. They create an isolated 10,000-entry
playlist per invocation. The test subclass disables the download scheduler;
no resolver requests, media downloads, or live app data are involved.

The shared instrumentation is in
`source/gui/shared/tests/native_performance.h`; platform adapters are in
`source/gui/{macOS,iOS}/tests/*_performance_test.m`. Shared collection
microbenchmarks remain in AltivecIntelligence's `libs/cocoa/tests/`.

## Build and run

Use the same current Altivec checkout for the production objects and test link.
The container's baked-in libraries may predate the app's collection API.
`ALTIVEC_ROOT` defaults to `/altivec`; both test builders accept an override.
Build its Cocoa static libraries first if changed:

```sh
make -C "$ALTIVEC_ROOT/libs/cocoa" mac-static phone-static
make apps ALTIVEC_ROOT="$ALTIVEC_ROOT"
```

Existing build prerequisites (SDKs, core libraries, and generated EJS resources)
apply. A separate `BUILD_ROOT` is supported; provision its `generated/ejs`
resources as for the normal app. Test code is optimized with `-O3` and compiled
with `-Wall -Wextra -Werror`. Performance mode skips iOS playback fixtures.

For Tiger, use a fresh directory under the desktop user's Desktop and compile
its absolute path into the test. A logged-in graphical session is required:

```sh
ssh x4-vm 'mkdir ~/Desktop/RDLP-performance-run1'
RDLP_TEST_PERFORMANCE=1 \
RDLP_TEST_ROOT=/Users/me/Desktop/RDLP-performance-run1 \
python3 source/gui/macOS/tests/build_mac_toolbar_test.py
scp -O -r build/tests/macOS/RetroDLPPerformance.app \
  x4-vm:Desktop/RDLP-performance-run1/
ssh x4-vm 'cd ~/Desktop/RDLP-performance-run1 && ./RetroDLPPerformance.app/Contents/MacOS/RetroDLPToolbarTest > app.log 2>&1'
scp -O x4-vm:Desktop/RDLP-performance-run1/retrodlp-performance.plist build/tests/
```

A successful Mac run exits zero. Exceptions produce
`retrodlp-performance-error.txt` and exit one. Keep `app.log` on failure.

For a jailbroken iPhone, install the separate test bundle with its package
installer. Keep transfers under `~/tmp_altivec`; the installed test app owns
its sandbox. Unlock the device and leave the test foregrounded until complete:

```sh
RDLP_TEST_PERFORMANCE=1 python3 source/gui/iOS/tests/build_ios_ui_test.py
ssh koolphone5 'mkdir ~/tmp_altivec/RDLP-performance-run1'
scp -O build/tests/iOS/RetroDLPIOSPerformance.ipa \
  koolphone5:tmp_altivec/RDLP-performance-run1/
ssh koolphone5 'cd ~/tmp_altivec/RDLP-performance-run1 && appinst RetroDLPIOSPerformance.ipa && uiopen retrodlp-performance://'
```

The bundle ID is `test.retrodlp.performance`. Retrieve `performance.plist` from
that installed app's Documents directory. `performance-error.txt` means failure,
including when a partial report also exists. Both files are cleared on launch.
The app stays open after completion. A run that loses foreground status fails;
relaunch it for a fresh measurement. After installation, retry `uiopen` once
LaunchServices has registered the URL if the first invocation does not launch. Collect results before starting another run;
new fixtures are retained for inspection. Remove this test app using the device's
normal uninstaller when finished. Never manually delete system app directories.

## Measurements and limits

- Initial display includes opening the facade, preparing rows, native controller
  creation, and the first run-loop turn. Fixture generation is excluded.
- Sequential scrolling: 120 jumps of eight rows. Random jumps: 80 deterministic
  jumps spread across the playlist. These are programmatic, nonanimated native
  scroll operations; they measure cell/layout work, not touch latency or FPS.
- Concurrent scrolling: 80 random jumps while a separate SQLite connection
  updates the first entry every 25 ms. Twenty explicit refreshes follow while
  that writer continues. Each refresh must replace the displayed snapshot.
- Each phase reports all samples, p50, p95, maximum, SQL statement count, sampled
  resident-memory peak, and maximum observed display/source cache occupancy.
  Timings include a 2 ms run-loop pump. SQL counts include all traced connections,
  including the writer and transaction statements; they are not SELECT counts.
- A 10 ms main-thread timer reports the largest callback gap and gaps over 50 ms.
  This is a responsiveness proxy, not a compositor frame-time measurement.
- Both caches must be exercised and stay at or below 128 rows each. Memory is
  sampled after operations; transient allocations between samples can be missed. Resident memory includes
  the process allocator state left by fixture generation.
- An explicitly retained old snapshot pins WAL during writes. Report WAL bytes
  before release and after closing the UI/library and truncating the WAL. The
  final checkpoint must succeed and leave zero WAL bytes. The checkpoint
  connection first reads journal mode so a fresh connection cannot silently
  return success without discovering the WAL.

The current playlist UI has no sort/filter controls; those scenarios are not
covered. This fixture has no download jobs or local files, so it does not measure
job-heavy playlists, filesystem checks, or downloaded-library sections. Worker
queue and SQL time are included in refresh latency but are not separately timed.
Keep these limitations when comparing the baseline with everyday app use.

## Baseline and comparison method

Record OS/device, Retro-DLP commit, Altivec commit, build optimization, fixture
size, and raw reports alongside a summary. Run at least three times on each
otherwise idle device before treating small differences as regressions.

Hard correctness budgets are 128 rows per cache, successful concurrent commits,
a fresh snapshot on each refresh, and zero retained WAL after readers close.
The 50 ms main-loop threshold is a diagnostic bucket. Evaluate timing and
memory changes relative to a contemporaneous baseline on the same device;
do not fail builds on universal latency limits.

### 2026-10-14 baseline

Three successful launches per device, using the final harness in this change,
Retro-DLP `258b5a0a10b86116771211fecb745a902f9265c4`, and AltivecIntelligence
`bca419569c1de64ce7c52c10c6bb7aa1ca25099d`. Both app objects and test entry
points were built with `-O3`. No device reboot or OS cache flush separated runs.
Tiger is a VM reporting PowerMac3,1, one PowerPC CPU, 512 MiB RAM, OS X 10.4.11
(8S165). Koolphone5 is an iPhone5,2 running iOS 8.4.1 (12H321), armv7.

[Machine-readable results](performance-baseline.json) retain each run's summary,
SQL counts, loop gaps, memory/cache measurements, and WAL sizes. Full sample
plists from this session are retained locally in `build/tests/performance/results/`
and on the devices, outside Git. Interrupted and failed exploratory runs are
excluded. The fixtures contain 10,000 entries and no jobs.

| Metric | x4-vm, range across three runs | koolphone5, range across three runs |
| --- | ---: | ---: |
| Initial display | 1,887–2,642 ms | 185–219 ms |
| Sequential scroll p95 | 67.5–98.7 ms | 31.2–31.3 ms |
| Random jump p95 | 120.7–204.5 ms | 55.2–55.9 ms |
| Scroll during writes p95 | 178.2–187.3 ms | 56.2–57.6 ms |
| Refresh during writes p95 | 390.1–529.7 ms | 66.8–72.4 ms |
| Largest measured loop gap during phases | 502.9 ms | 133.3 ms |
| Highest sampled resident memory | 29.3 MiB | 15.6 MiB |
| Maximum display/source cached rows | 128 / 128 | 128 / 128 |
| WAL after release and checkpoint | 0 bytes | 0 bytes |

### Relative regression comparisons

Absolute times above describe the test environment; they are not product targets
or pass/fail budgets. In particular, x4-vm is deliberately very slow. Its value is
showing relative changes under the same conditions, not predicting real Mac
latency. Do not compare Tiger and iPhone timings as a performance ranking.

For each proposed optimization or suspected regression:

1. Build the baseline and candidate with the same toolchain, dependencies,
   optimization flags, fixture, and instrumentation. Change only the code under
   investigation.
2. Run both on the same device with the same foreground/background conditions.
   Use one unrecorded warm-up per build, then at least three measured launches
   each. Alternate baseline and candidate launches to reduce host-load drift,
   especially for the VM. Compare cold launches separately if needed.
3. For each phase, compare the median of the per-run p95 values. Compare initial
   display, statement counts, and sampled resident memory using their per-run
   medians as well. Report `(candidate / baseline - 1) * 100` percent change,
   alongside each build's range; negative latency changes are improvements.
4. Use a repeatable increase above 25% as a provisional investigation trigger,
   not an automatic failure. If ranges overlap substantially or VM load varies,
   collect more paired runs before attributing the change to code. Re-measure
   the baseline alongside the candidate rather than relying solely on this
   historical snapshot.

The three-run results above are a starting reference, not a paired comparison:
there was no candidate optimization in this change and no controlled warm-up.
No speedup or regression is inferred from them. The 50 ms loop-gap counter is a
fixed diagnostic bucket, not a Tiger performance requirement. Cache occupancy
(128 rows per layer) and WAL release (zero bytes after checkpoint) remain hard
correctness checks independent of device speed.

Next investigation: separate synchronous row formatting/SQL from native drawing
on Tiger, especially random jumps and initial presentation. Statement counts show
substantial work per page, but this harness does not isolate its cost; no production
cache or cell-text behavior was changed from these measurements alone. Add a
job-heavy fixture before generalizing these results to the downloaded library.

Validation: `make test`, full `make apps`, `make app-validate`, and
`make validate-apple-artifacts` passed. Both performance and existing regression
entry points cross-compiled (PowerPC and armv7/arm64) with `-Werror`. The production
and dependency builds emitted existing L-SMASH warnings (including signedness,
missing initializers, and possible uninitialized values) and Cocoa
`AIWebViewController` function-pointer-cast warnings; native performance entry
points emitted no warnings. Cross-compilation of the existing regression entry
points is not a claim that their UI/playback suites were run on devices.
