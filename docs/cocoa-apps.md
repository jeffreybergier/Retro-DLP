# RetroDLP Cocoa applications

The macOS and iOS applications consume the public Retro-DLP static libraries.
Their shared application code lives in `source/apps/shared`. The existing CLI
and public library API remain independent of the applications.

## Build

Use the same Altivec environment and SDKs as the library:

```sh
make apps          # builds both apps and their library dependencies
make app-macOS     # PowerPC, i386, x86_64, arm64
make app-iOS       # armv7 (iOS 5+), arm64 (iOS 7+)
make app-test      # portable store and application integration tests on Linux
make app-validate  # inspect already-built app bundles and ZIP/IPA artifacts
```

Outputs:

- `build/apps/macOS/RetroDLP.app` and `RetroDLP.zip`
- `build/apps/iOS/RetroDLP.app` and `RetroDLP.ipa`

The first app build downloads the small version-matched EJS assets through the
public provisioning API, validating their hashes. Subsequent builds inspect and
reuse those assets. Both bundles include the assets and CA certificate; launching
an installed app does not require the CLI or a separate asset installation.

The IPA is pseudo-signed with `ldid`, without private filesystem entitlements.
It is suitable for the existing jailbreak IPA installation workflow. Installing
on stock iOS requires a supported signing/provisioning workflow; this build does
not produce an Apple distribution signature or provisioning profile.

## Mac workflow

The window uses the textured style, including brushed metal on Tiger. A full-width
status bar below all three panes displays shared library activity even when a pane
is empty or hidden. Leopard and later draw its background using the native window
content border. Long messages truncate with the full text available in a tooltip;
selected download errors remain in the queue pane. The main video table fills its
pane edge to edge, with no surrounding labels or buttons. Video and playlist
actions are available through the toolbar and menu bar.

The menu bar uses File, Edit, View, Window, and Help. File groups playlist
addition/discovery, synchronization, downloading, playback, Finder reveal, and
Close Window. Edit contains standard text commands plus separate Remove Playlist
and Delete Download commands. View contains only pane visibility and Show in
Queue; Window provides Minimize, Zoom, and Bring All to Front. Download Quality sits directly above Cookies
inside the application menu, with Cookie Export Guide in Help.
The middle table shows a narrow, untitled status icon column before Video.
Playlist rows summarize all qualities: an existing playable file takes priority,
then downloading, queued, failed/interrupted/missing, cancelled, and not downloaded.
Playback and file actions use the representative job; changing preferred quality
no longer hides an available download. New explicit downloads still use the quality
preference. All Downloads keeps individual completed jobs and adds Quality after
Video to distinguish versions. Status tooltips and accessibility descriptions
provide text equivalents; long video titles truncate to fit the pane.

Menu-bar commands retain their positions and disable when unavailable; download
and playback labels follow the active video or playlist selection. File's Download
command retries a selected queue quality using that job's exact format. Toolbar
menus retain their task-specific grouping.

The queue is an edge-to-edge, cell-based NSOutlineView, compatible with Tiger.
Its groups are Done, Downloading, Queued, and Needs Attention; beneath each are
playlist, video, and quality rows. Needs Attention includes failed, stopped,
interrupted, and missing-file downloads, with the reason on the quality row and
full errors in tooltips or Show Error. Expansion and selected quality survive
refreshes and status changes. Playlist and video rows provide their respective
toolbar contexts; individual download operations require a quality row.

The queue uses AppKit’s default row height and indentation. Top-level titles
use the playlist sidebar’s bold styling without parenthesized counts; child
rows use the default font.
Actionable quality rows have one circular textured NSButtonCell sized to fit the row: Font
Awesome pause to stop queued/running work, rotate-right to retry stopped/failed
or missing-file work. Stop uses the existing cancellation confirmation; retry
restarts that exact quality. Completed qualities and parent rows have no button.
NSTableColumn dataCellForRow: supplies these cells on Tiger; no view-based rows
or Leopard-only outline delegate API is required. There is no queue footer or
global Pause control.

During processing, a native NSProgressIndicator in the app-wide status bar shows
processed attempts out of the current run's total. Downloading also shows this
count; the progress tooltip reports failed and stopped attempts separately.
Historical downloads do not contribute; new pending jobs extend the total and
cancelled pending jobs leave it. Draining the queue hides the indicator, and the
next run starts fresh. Playlist metadata work does not activate queue progress.
Detailed transfer bytes remain in the app-wide status. The outline's frame does
not change when progress appears.

The sidebar is an NSOutlineView with three collapsible, nonselectable parent
rows: System (All Downloads), Added Playlists (manually added), and My Playlists
(discovered through Load My Playlists). Groups start expanded and keep their
collapse state during library refreshes. Selecting a child keeps the existing
Download/Play targeting behavior. Discovery promotes an existing manual playlist
without duplicating it and preserves its selection, membership, and downloads.

Database version 2 records discovery origin. Existing version-1 playlists migrate
to Added Playlists because their original source was not recorded. Running Load
My Playlists moves discovered matches into My Playlists. Using cookies for an
ordinary playlist sync does not change its group; clearing cookies does not
change stored provenance. Both app platforms can read the upgraded database.


The toolbar is arranged as Download, Play, flexible space, Cookies, and Queue.
Download and Play precede Edit in the menu bar and share their toolbar menu
builders and validation. The application menu uses `setAppleMenu:` and contains
About RetroDLP and Cookies. View provides Show/Hide Playlists, Show/Hide Download
Queue, and a Download Queue submenu for queue operations.

Both Download and Play follow the last-used pane. A sidebar selection targets
that playlist; a video row targets that video; Queue and All Downloads rows use
the selected job’s exact quality. A playlist video uses the remembered quality.
Clicking a toolbar button or opening a menu preserves the target. Hiding Queue
returns targeting to the center. An unplayable video never falls back to playing
its playlist.

Download and Play menus rebuild when opened to show the current scope. Playlist
Download options include missing-video qualities, sync, removal, and Queue;
video options include quality selection, Download Video, cancellation, deletion,
and Show in Queue. Add Playlist, Sync All, and Load My Playlists remain available
under Download in every context. Play contains default-app playback, explicit
VLC playback, and Reveal in Finder for the current video or playlist. A selected
video also retains default-app and VLC playback options for its containing
playlist, including Queue selections whose playlist is not selected in the sidebar.

| Button / context | Default action | Icon |
| --- | --- | --- |
| Download / new video | Enqueue the current quality | Solid download |
| Download / existing downloaded video | Confirm deletion; toolbar label becomes Delete | Solid trash |
| Download / queued or running job | Show the job in Queue | Solid hourglass |
| Download / failed, cancelled, interrupted, removed, or missing-file job | Restart download and reveal/select it in Queue | Solid download |
| Download / selected playlist | Sync metadata, disabled if already syncing | Solid arrows-rotate |
| Download / no target | Add Playlist sheet | Solid plus |
| Play / playable video or exported playlist | Open in VLC when installed, otherwise the system default app; Reveal in Finder if neither is available | YouTube Brands |
| Play / no playable target | Disabled | Dimmed YouTube Brands |

Starting or retrying any download reveals Queue, selects the job, and scrolls
it into view, even if Queue was manually hidden. The selected quality is retained.

Labels are Download and Play; Download becomes Delete for an existing downloaded video. The caret opens the same menu as right-click,
Control-click, or Accessibility Show Menu. Open With is absent. Explicit VLC
commands require VLC. The main Play button and video/queue double-clicks prefer
VLC when installed, falling back to the system default only when VLC is absent.
The Play tooltip names the selected player. Explicit “Default App” menu commands
continue to use the system association. Tiger uses a named Brands glyph outline to avoid ATSUI’s
missing Unicode mapping. Destructive actions retain their confirmation sheets, including the default Delete
action for a downloaded video. Cookies and Queue toolbar behavior is unchanged.

Download Video (or Download Missing Videos for a playlist) is a direct command
using the last selected quality. The separate Download Quality submenu contains
Low (18), Medium (136+140), High (137+140), and Custom Format…. Choosing a quality
only saves the preference; it never queues work or opens a bulk confirmation.
Custom Format validates input and has Save/Cancel buttons. Saving changes only
the quality, and cancelling leaves it unchanged. Quality choices remain available
even if that quality already has a download. Use Download Video or Download
Missing Videos to start work; playlist downloads still require confirmation.

Bulk download includes videos with no job at the requested quality and jobs whose
files were removed or are missing. It does not restart failed, interrupted, or
cancelled jobs. The confirmation captures its exact plan and rechecks eligibility
before acting. Duplicate playlist entries do not create duplicate jobs.

Destructive and bulk actions use attached confirmation sheets: removal of files,
playlists, and cookies; cookie replacement; download cancellation; bulk video
download; Sync All; and account playlist discovery.
Cancelling a sheet performs no operation. Single-video enqueue/retry and
single-playlist metadata sync are immediate. Duplicate pending/running syncs are
not added again. Playlist removal remains unavailable until queued jobs are
cancelled and completed downloads removed; removal affects only the local library.

The Mac app processes queued downloads automatically on launch and when work is
added. Failed, stopped, and interrupted jobs require an explicit Retry. Stopping
one quality leaves other queued downloads eligible to run. The shared bridge's
Pause API remains for iOS foreground/background lifecycle management.

Cookies status indicates only whether the local working file is available, not
whether its Netscape format or account session is valid. Import/replacement/removal
are unavailable while the library is busy. Account discovery first confirms its
scope and requests an import if needed. Export Guide is always available.

Toolbar Font Awesome glyphs render at 24 points on a 32-point canvas with the
window’s backing scale; the caret uses an 8-point glyph in a 10-point corner.
`ATSApplicationFontsPath = Fonts` registers the bundled fonts, including on Tiger.
Control icons use cached, explicitly black images on every supported OS. This includes toolbar glyphs, carets, YouTube, and
queue action buttons; table status indicators retain template rendering. AppKit
still draws native pressed/disabled feedback. Standard toolbar
labels remain below the custom buttons; Play is centered between flexible spaces.

Media is organized under:

```text
~/Documents/RetroDLP/
  Playlists/<sanitized playlist title> [<YouTube playlist ID>]/
    <sanitized video title> [<local download ID>].mp4
    Playlist.m3u8
  .staging/<local download ID>/       # partial transfers / retained mux inputs
```

A playlist's directory is stable after creation. Exported playlists use UTF-8,
relative file paths, and current playlist order, including repeated entries. Only
completed files that still exist are exported. If several qualities exist, the
most recently created completed job supplies that video's playlist entry. A
video in different playlists has an independent local copy in each folder.

`~/Library/Application Support/RetroDLP/retrodlp.sqlite` stores the library and
queue. Cookies are copied to an owner-only file alongside it. The original
imported cookie file is not removed.

## iOS workflow

The root screen groups System (All Downloads, Download Queue, Settings), Added
Playlists, and My Playlists. Section headers collapse and preserve their state
during refreshes. Add a playlist with **+**, discover account playlists using
**My Playlists**, or open a playlist and tap **Sync**. Pending syncs/discovery
cannot be submitted again. Sync All and account discovery confirm their scope.

Playlist videos summarize every downloaded quality. A playable file takes
priority over running, queued, failed/missing, and stopped work, even when the
preferred quality differs. Status icons also have text equivalents. Opening a
video offers native playback of its representative download, the action for the
preferred quality, quality settings, and individual download jobs. All Downloads
keeps individual qualities with their playlist and requested format visible.

Choosing Low, Medium, High, or saving a valid Custom Format only saves the
preference. It does not download anything. **Download Missing** confirms an exact,
deduplicated plan at the selected quality. It includes new and removed/missing-file
downloads, skips failed/interrupted/stopped jobs, and rechecks eligibility before
performing the captured plan. Single-video downloads and retries are immediate.

Queue has Done, Downloading, Queued, and Needs Attention sections, with
collapsible playlist and video rows above individual qualities. Each pending or
running quality has a Stop button; failed/stopped/missing qualities have Retry.
These buttons carry stable job IDs, so a refresh cannot change their target.
Starting or retrying reveals Queue, expands the target's ancestors, and selects
that exact quality. Selection follows its status changes. Other collapsed branches
stay collapsed. Job actions show only applicable playback, download, stop, delete,
and Show in Queue commands; full errors are available in the job dialog.

A fixed status area below each table shows current activity and a native progress
bar for processed attempts in the current run. Failed and stopped counts are
included in its accessible description. Historical jobs do not contribute, and
progress appearing or disappearing never changes the table's frame.

Deleting a download, stopping work, removing a playlist, replacing/removing
cookies, and bulk operations require confirmation. Cancel performs no operation.
Playlist removal is disabled until pending jobs and completed downloads have
been removed. Cookie changes and discovery are disabled while busy; cookie status
indicates local file availability, not authentication. Settings includes the
Cookie Export Guide.

Cookies can be imported by opening a text file in RetroDLP from another app, or
by copying `cookies.txt` into RetroDLP's Documents using iTunes File Sharing and
choosing **Import Documents/cookies.txt** in Settings. Import creates a private
working copy; the original document remains where it was supplied.

Media lives in the app's `Documents/RetroDLP`; the database and working cookies
live in its `Library/Application Support/RetroDLP`. No VLC-container access or
private sandbox entitlements are used. Native playback uses AVKit where available
and the legacy movie player on older iOS. H.264 profile, level, resolution, and
frame rate still need to be supported by the device; choosing an MP4 format does
not transcode it.

Downloads process automatically on launch and when returning to the foreground.
Backgrounding pauses the queue and cancels an active transfer; queued work
continues on return, but interrupted/stopped/failed jobs require an explicit Retry.
Stopping one quality leaves other queued downloads eligible to run. There is no
global Pause control or indefinite background downloading, and no background-audio
mode is used to keep transfers alive.

## Shared architecture and invariants

- `rdapp_store.{h,c}`: normalized SQLite tables, complete playlist snapshots,
  ordered membership, durable jobs, recovery, file removal, path construction,
  and atomic M3U8 export. No Apple headers.
- `rdapp_service.{h,c}`: sync, account discovery, resolve/download/mux orchestration,
  staging and publication, and durable operation outcomes. It accepts the public
  resolver transport/callback options, including fixture transports on Linux.
- `RDLPLibrary.{h,m}`: shared Foundation/MRC bridge. Owns the store, main-thread
  commands, worker scheduling, cancellation locking, credential import, shared
  quality choices, and notifications. Network/media work runs off the main thread.
- `macOS/`: native AppKit window/tables and default-app launching using AltivecCocoa's
  window and pane-controller infrastructure.
- `iOS/`: native UIKit navigation/tables and a small native-player compatibility
  wrapper. Both UIs talk to the same Objective-C bridge, not SQLite or resolver
  internals.

A failed network refresh leaves the last successful playlist snapshot intact.
A completed snapshot replaces membership in one short transaction; downloads
remain independent when a video disappears remotely. Discovery merges account
playlists without silently removing manually added playlists.

The queue deduplicates by playlist, video ID, and requested format. Requested and
actual formats are distinct. Only one worker operation runs at a time; database
locks are not held over network transfers or muxing. Progress is throttled, copied
before the C callback returns, and delivered on the main thread.

Downloads use app-owned staging files and publish exclusively on the destination
volume. Existing files are never overwritten. Retry clears only the job's known
staging files. Startup marks abandoned running jobs interrupted, reconciles
published completed files, and marks missing downloads available for retry.
Sync/export failures and media failures remain visible; no implicit quality
fallback is added to an exact expression.

## iOS code boundaries

The recent macOS application changes map to iOS as follows. The earlier commits
in the ten-commit review concern the shared CLI/library and are already consumed
by both applications.

| macOS change | UIKit equivalent |
| --- | --- |
| Sidebar outline and discovery provenance | Collapsible System, Added Playlists, My Playlists sections |
| Queue outline and quality action cells | Grouped playlist/video/quality rows with stable-ID Stop/Retry buttons |
| Context commands, quality preferences, confirmations | Video/job dialogs, Settings, and captured/revalidated alert requests |
| Representative status and app-wide progress | Shared download policy, status icons, fixed status/progress area |
| Automatic queue processing | Automatic foreground processing; background pause/cancellation |
| Class naming and smaller collaborators | RDLP delegate, controller, sections model, actions category, UIKit compatibility wrapper |

`RDLPAppDelegate` owns lifecycle and routes cookie URLs to the visible controller.
`RDLPLibraryViewController` owns navigation, table rendering, refreshes, and stable
selection. `RDLPLibrarySections` constructs read-only table snapshots, validates
job actions, and plans missing downloads. `RDLPLibraryActions` is a controller
category containing command execution and immutable confirmation requests.
`RDLPUIKit` owns compatibility, cached status icons, alerts, and native playback.
`RDLPDownloadPolicy` now lives in `shared/` and is compiled unchanged by both apps.
All app-owned iOS classes/files use `RDLP`; preference and notification keys are
unchanged. Application C APIs remain inside the Foundation bridge, with `main`
as the UI entry-point exception.

The iOS interface uses navigation and native playback in its own sandbox.
Desktop menu bars, Finder reveal, and Mac application selection remain AppKit
features. iOS retains iOS 5+ armv7 / iOS 7+ arm64 compatibility and manual memory
management.

## macOS code boundaries

App-owned macOS classes and their source files use the `RDLP` prefix.
`RDLPLibraryWindowController` owns the window, `RDLPAppDelegate` owns application
lifecycle, and the shared `RDLPLibrary` bridge serves both macOS and iOS. Saved
window identifiers, preferences, and the notification string retain their existing
values so renaming classes does not reset application state.

`RDLPLibraryWindowController` coordinates selection, refreshes, command validation, and
confirmation sheets. Its collaborators have narrower responsibilities:

- `RDLPDownloadPolicy` interprets job states and file availability, including retry,
  cancellation, deletion eligibility, and representative-quality priority. The
  table and queue share its playable-file rule. Equal priorities retain the
  library's newest-first order.
- `RDLPLibraryMenus` builds menu structure against the read-only
  `RDLPLibraryMenuContext` protocol. Menu items still target the controller, which
  validates and executes commands. Queue action groups are built explicitly;
  they do not depend on deleting items at hard-coded positions.
- `RDLPLibraryViews` constructs AppKit controls and owns the small selection,
  accessibility, and Tiger pane-layout helpers.
- `RDLPQueueTree` builds stable queue nodes; `RDLPQueueOutlineView` and
  `RDLPQueueActionColumn` handle queue interaction and rendering.
- `RDLPToolbarButton` handles toolbar interactions; its private
  `RDLPToolbarGeometry` object keeps drawing and hit testing consistent.
- `RDLPAppKit` exposes Objective-C class methods for OS compatibility, icon
  rendering, file panels, alerts, and application launching.

Keep application C APIs, C callbacks, raw buffers, and POSIX operations inside
`shared/RDLPLibrary.m`, the designated C bridge. The portable store and
service remain `.c` files. macOS UI code uses Objective-C methods and objects,
with no application-defined free C helpers, C arrays, or custom C structs.
Standard Cocoa scalar types, geometry helpers (`NSRect`, `NSMakeRect`, etc.),
selectors, constants, and required AppKit callback signatures are normal Cocoa
usage. The other narrow exceptions are the `main` entry point and the drawing
math (`isfinite`/`ceil`) and AppKit ABI adaptation inside `RDLPAppKit`.

## Validation

iOS parity refactor (2026-09-14): armv7 and arm64 builds completed without compiler
warnings, both Apple static analyzers reported zero warnings/errors, and both
platforms' artifact checks passed. All 13 portable store tests and the local HTTPS
service integration suite passed. The isolated native suite passed on
`koolphone5`, including playlist provenance, representative-quality status,
quality-only preferences, captured/revalidated bulk plans, cancellation and cookie
confirmations, exact-quality retry/stop, stable selection and scrolling, lifecycle
pause/resume, glyph rendering, fixed progress layout, and local native MP4
playback/dismissal. Final queue and progress screenshots were inspected. No live
YouTube requests were made; the production app's library was not used for testing.
The older iOS deployment targets and arm64 slice were cross-built/analyzed, not
run on additional devices. The shared policy relocation is byte-for-byte unchanged.

Build the isolated native iOS regression app after the normal app build:

```sh
python3 source/apps/tests/build_ios_ui_test.py
scp build/apps/tests/RetroDLPIOSOfflineTest.ipa koolphone5:/tmp/
ssh koolphone5 'appinst /tmp/RetroDLPIOSOfflineTest.ipa'
ssh koolphone5 'su mobile -c "uiopen retrodlp-offline-test://run"'
```

The test has bundle ID `test.retrodlp.ios` and creates synthetic data only inside
its own Documents/Fixture directory. Its `RDLPOfflineLibrary` overrides scheduling
to never start a worker, and the bundle omits the CA resource. It can exercise
sync/download actions without contacting YouTube. Native playback uses a bundled,
FFmpeg-generated local MP4. Result and screenshots are in the test app's Documents
(`result.txt`, `library.png`, `queue.png`, `progress.png`). On old iOS, allow Launch
Services to finish registering a newly installed app before opening it. Reinstall
the IPA for new test builds; overwriting a running signed executable in place can
leave the kernel's cached signature stale.


VLC preference update: all four macOS slices built without warnings, static
analysis reported zero warnings/errors, and artifact checks passed. The full
x4-vm native suite passed, including simulated VLC-present/absent behavior for
videos and playlists, missing files, explicit Default App commands, and toolbar
tooltips. `RDPlaybackHandoffTest=1` additionally clicked the real toolbar Play
action for a synthetic local video; `lsof` confirmed VLC opened that fixture MP4.
No YouTube requests were made, and system file associations were not changed.


The subsequent `RDLP` class/file rename passed all four macOS and both iOS
builds, both static analyzers with zero warnings/errors, portable app tests,
artifact validation, and the offline native regression suite on x4-vm.

macOS abstraction refactor (2026-09-14): all four macOS slices built without
compiler warnings; Clang static analysis reported zero warnings/errors. The 13
portable store tests, local service integration suite, and bundle artifact checks
passed. The native regression app passed on x4-vm (Tiger 10.4.11), including
new policy checks and actual queue-cell mouse tracking. The separate icon test
passed color, transparency, cache, 1x/2x resolution, and Tiger glyph fallback
checks. Investigation reproduced
two failures in the original code: a test that assumed an unflipped scroll view,
and queue action cells outside the visible pane. The test now compares window
coordinates, and queue refresh fits columns with a fixed-width action column.
The native test also asserts that each clicked action cell is visible.

Use `open /tmp/.../RetroDLPToolbarTest.app` on Tiger to launch the native UI test
through Launch Services. Test only a fresh synthetic fixture and the test bundle
without its CA resource; service operations fail locally before networking.
No live YouTube requests or external media playback were used for this refactor.


`make app-test` runs without contacting YouTube. Store tests cover transactional
rollback, duplicate ordering, queue idempotence, quality-specific jobs, interrupted
work, crash publication, missing files, removal, and export. Integration tests run
the actual public resolver and downloader with synthetic metadata, synthetic
cookies, and a local TLS media server; they cover discovery, sync, downloading,
HTTP retry, cancellation, export, and cleanup.

Run the Apple analyzers with:

```sh
make -C source/apps/macOS analyze
make -C source/apps/iOS analyze
```

Reports remain under `build/apps/<platform>/analyze`. Cross-builds and static
analysis establish compilation and API/link compatibility, not device launch or
decoder performance. Native iOS playback should be checked on each device class
before distributing a release.

For an isolated Mac UI test, generate synthetic media and metadata with
`python3 source/apps/tests/prepare_native_fixture.py /absolute/test/state`.
Launch the Mac app with `-RetroDLPTestDirectory /absolute/test/state`, or add the
same `RetroDLPTestDirectory` key to a **test copy** of the app's Info.plist when
launching through Finder/Launch Services. This places support data and downloads
inside the selected test directory. Do not ship that key in a release bundle.

`mac_smoke.applescript` exercises the native toolbar, Custom Format sheet
validation/cancellation, independent queue selection, cancellation, Queue toggle,
and Add sheet without
starting network work. The fixture includes completed, failed, and queued jobs;
**do not resume or retry them**. `mac_removal.applescript`, run after the smoke
script, additionally removes the synthetic media and playlist. Both scripts accept
an optional process name for a separately named test app. Run removal only against
that fixture, and recreate the fixture afterward. `mac_cookies.applescript` takes
the test process name and the fixture's absolute `synthetic-cookies.txt` path;
it checks import, persistent status across selection changes, and confirmed removal
without account discovery.

For an additional network safeguard, remove `Contents/Resources/cacert.pem` from
that **test copy only**: the bridge refuses to run service operations when its
bundled CA resource is missing. Never remove the resource from the release app.
The default player must be installed and its first-launch prompts dismissed for
playback checks. Automatic Play prefers installed VLC without changing Finder associations. The original Tiger playback test used [VideoLAN’s legacy VLC 0.9.10 build](https://images.videolan.org/vlc/download-macosx.html).

Initial app implementation validation: all six Apple architecture slices
built without compiler warnings; both Apple analyzers reported zero warnings or
errors; 11 portable store tests and the local-HTTPS application integration suite
passed, as did the existing Retro-DLP tests. On x4-vm (Tiger 10.4.11, PowerPC),
Accessibility tests passed for browsing, quality selection, queue controls, invalid
input, VLC handoff, and both removal flows. VLC opened the exported media, but the
emulator dropped late video frames; decoder performance was not established.
iOS was cross-built and analyzed, not installed or exercised on a device.

Three-pane Mac update validation: all four Mac slices and both iOS slices built;
both Apple analyzers reported zero warnings/errors. The 11 store tests, local-HTTPS
service integration suite, and bundle artifact checks passed. On x4-vm (Tiger
10.4.11), the updated smoke, cookie, and removal scripts passed against a separate
synthetic library and an app copy without its CA resource. Imported-cookie status
also survived relaunch. No YouTube API requests were made. Playback and live
transfers were not exercised for this update.

### Context-sensitive toolbar regression test

After `make app-macOS`, run `python3 source/apps/tests/build_mac_toolbar_test.py`
to build `build/apps/tests/RetroDLPToolbarTest.app`. This test-only PowerPC bundle
omits the CA resource. Prepare a fresh library with
`python3 source/apps/tests/prepare_native_fixture.py /tmp/retrodlp-toolbar-fixture`,
copy the app and fixture to `/tmp` on the Tiger test Mac, and launch the test app.
It writes `/tmp/retrodlp-toolbar-test.txt` and exits. Recreate/restore the fixture
before each run; the test deliberately changes only that fixture.

The native test exercises real toolbar controls, pane targeting, fixed menu
structure, removal/cancellation sheets, bulk confirmation and removed-file
requeue, custom-format cancellation/validation, cookie removal, and exact-quality
queue/retry behavior. It also checks the textured window style and that the shared
status stays outside the split panes when resizing and toggling panels.
Queue checks cover four-level grouping, real cell-button clicks, collapsed-state
and selection preservation, blank completed action cells, automatic startup,
app-wide progress, run counters, and reset after draining. Test downloads fail locally
because the test bundle omits the CA certificate; metadata work is also checked
to ensure it does not activate queue progress.
Sync All and discovery confirmations are cancelled;
no network work is started. The Accessibility smoke/cookie/removal scripts target
a separate fixture review app. Custom toolbar buttons are children of toolbar
groups on Tiger and expose `AXShowMenu` for the same menus used by right-click.

Earlier context-sensitive toolbar validation: all four Mac and both iOS slices built;
both Apple analyzers reported zero warnings/errors. The 11 portable store tests,
local-HTTPS service tests, and app artifact checks passed. The native toolbar
regression and updated Accessibility smoke, cookie, and removal scripts passed on
Tiger using isolated fixtures and test bundles without the CA resource. Real
mouse caret clicks, right-clicks, and Control-clicks also opened Play’s menu while its main action
was disabled. Live YouTube transfers and playback in external apps were not
exercised for this update.

Video/Playlist consolidation validation: all four macOS slices built without
warnings; macOS static analysis reported zero warnings/errors, and artifact
validation passed. The isolated Tiger native test passed fixed menu parity,
stable labels, sidebar-only Playlist targeting while Queue has focus, exact
Video quality targeting, and the existing sheet/paused-queue regressions.
`mac_object_menus.applescript` checks the real Playlist, Video, Cookies, and Queue
menu bar entries, opens/cancels Add Playlist from the menu bar, and checks that
Video playback is disabled without a selection. It and the updated toolbar
smoke, cookie, and removal scripts passed on Tiger. No live YouTube transfers or media playback were
performed for this change.

Context icon update: all four macOS builds, static analysis, artifact checks,
and the isolated Tiger native regression passed. Failed and removed-job default
clicks were verified to show Queue without restarting work; Open With is absent.
A Tiger screenshot confirmed the plus and disabled YouTube Brands icons render
correctly. No live transfers or playback were performed.

Menu bar reorganization validation: four macOS builds, zero-warning static
analysis, and artifact checks passed. The updated `mac_object_menus.applescript`
passed on isolated Tiger: no duplicate application menu, Playlist/Video before
Edit, Cookies inside the application menu, and both View visibility toggles
working in both directions. Add-sheet cancellation and disabled Video validation
also passed.

Download/Play revision validation: all four macOS builds, zero-warning static
analysis, artifact validation, and one focused automated Tiger regression passed.
The test covers adaptive playlist/video menus, shared toolbar/menu definitions,
exact Queue quality targeting, completed/failed defaults showing Queue, explicit
retry preserving Pause, and cancelled bulk/destructive sheets. No manual UI tour,
screenshots, live transfers, or playback were performed for this revision.

Download Video handles new, failed, cancelled, interrupted, removed, and missing-file
jobs at the selected quality. Retry Download and Download Again are no longer
separate menu entries. Queue offers one Download Selected Queue Video command
using that job’s exact quality. Delete Download remains for local deletion.

Outline sidebar validation: 13 portable store tests (including version-1 migration
and discovery promotion), the local service discovery test, all Mac/iOS builds
and static analysis, and artifact checks passed. One automated Tiger run checked
outline groups, collapse persistence, existing action targeting, and promotion
to My Playlists while retaining the selected playlist. No manual UI tour or live
YouTube discovery was performed.
