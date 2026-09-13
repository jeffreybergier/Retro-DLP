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
| Play / playable video or exported playlist | Open in default app; Reveal in Finder if no handler | YouTube Brands |
| Play / no playable target | Disabled | Dimmed YouTube Brands |

Starting or retrying any download reveals Queue, selects the job, and scrolls
it into view, even if Queue was manually hidden. The paused state is preserved.

Labels are Download and Play; Download becomes Delete for an existing downloaded video. The caret opens the same menu as right-click,
Control-click, or Accessibility Show Menu. Open With is absent. Explicit VLC
commands require VLC. Tiger uses a named Brands glyph outline to avoid ATSUI’s
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
download; Sync All; account playlist discovery; and resuming a nonempty queue.
Pausing a running transfer also requires confirmation because retry restarts it.
Cancelling a sheet performs no operation. Single-video enqueue/retry and
single-playlist metadata sync are immediate. Duplicate pending/running syncs are
not added again. Playlist removal remains unavailable until queued jobs are
cancelled and completed downloads removed; removal affects only the local library.

Each launch starts paused. Enqueue and retry preserve Pause, including when a bulk
operation is confirmed. Resume explicitly allows queued transfers to start;
failed or cancelled jobs still require Retry. Pausing an idle queue and resuming
an empty queue are immediate. Pause stops downloads, not metadata sync commands.

Cookies status indicates only whether the local working file is available, not
whether its Netscape format or account session is valid. Import/replacement/removal
are unavailable while the library is busy. Account discovery first confirms its
scope and requests an import if needed. Export Guide is always available.

Toolbar Font Awesome glyphs render at 24 points on a 32-point canvas with the
window’s backing scale; the caret uses an 8-point glyph in a 10-point corner.
`ATSApplicationFontsPath = Fonts` registers the bundled fonts, including on Tiger.
AppKit draws the toolbar images and handles template tinting. Standard toolbar
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

The root screen contains playlists, Queue, Downloads, and Settings. Add a playlist
with **+**, or discover account playlists using **My Playlists**. Open a playlist
and tap **Sync**. Select a video to download it or access its download jobs.
**Download All** queues the entire playlist at the quality selected in Settings.
Tapping a completed job offers native playback, retry, cancellation, and removal.

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

Downloads are foreground operations. Backgrounding pauses the queue and cancels
an active transfer. Resume the queue and retry that job after returning. The app
does not claim indefinite background downloading or use a background-audio mode
to keep downloads alive. Each launch starts the persisted queue paused.

## Shared architecture and invariants

- `rdapp_store.{h,c}`: normalized SQLite tables, complete playlist snapshots,
  ordered membership, durable jobs, recovery, file removal, path construction,
  and atomic M3U8 export. No Apple headers.
- `rdapp_service.{h,c}`: sync, account discovery, resolve/download/mux orchestration,
  staging and publication, and durable operation outcomes. It accepts the public
  resolver transport/callback options, including fixture transports on Linux.
- `RetroDLPLibrary.{h,m}`: shared Foundation/MRC bridge. Owns the store, main-thread
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

## Validation

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
playback checks. To test VLC, associate the fixture’s media files with VLC in
Finder. The original Tiger playback test used [VideoLAN’s legacy VLC 0.9.10 build](https://images.videolan.org/vlc/download-macosx.html).

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
requeue, custom-format cancellation/validation, cookie removal, and paused
queue/retry behavior. Sync All, discovery, and Resume confirmations are cancelled;
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
