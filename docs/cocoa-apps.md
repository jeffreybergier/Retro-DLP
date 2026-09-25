# RetroDLP Cocoa applications

The macOS and iOS applications consume the public Retro-DLP static libraries.
Their shared application code lives in `source/gui/shared`. The existing CLI
and public library API remain independent of the applications.

## Build

Use the same Altivec environment and SDKs as the library:

```sh
make apps          # builds both apps and their library dependencies
make app-macOS     # PowerPC, i386 (Apple GCC 4.2.1)
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

### iPhone launch images

The iOS bundle uses ENIL's plain white launch images, plus a matching landscape
image for Plus phones. `Resources/*.png` are copied to the bundle root; changing
an image rebuilds the bundle and IPA. No asset catalog compiler is required.

| Image | Pixels | iPhone layout |
| --- | --- | --- |
| `Default.png` | 320 × 480 | 3.5-inch, non-Retina |
| `Default@2x.png` | 640 × 960 | 3.5-inch, Retina |
| `Default-568h@2x.png` | 640 × 1136 | 4-inch (5/5c/5s/SE first generation) |
| `Default-667h@2x.png` | 750 × 1334 | 4.7-inch (6/6s/7/8/SE second and third generation) |
| `Default-736h@3x.png` | 1242 × 2208 | 5.5-inch Plus, portrait |
| `Default-Landscape-736h@3x.png` | 2208 × 1242 | 5.5-inch Plus, landscape |

iOS 5/6 discover the legacy `Default` filenames. For iOS 7+, the iPhone-specific
`UILaunchImages` array explicitly declares every supported size in **points**,
with portrait dimensions even for the landscape entry, following
[Apple's launch-image rules](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html#//apple_ref/doc/uid/TP40009251-SW28).
The larger entries require iOS 8. These assets cover classic iPhone layouts;
they do not establish native full-screen support on edge-to-edge iPhones.
That needs a modern launch-screen setup and toolchain work beyond the current
iOS 8.4 SDK build. Verify cold launches on devices separately from packaging.

## Mac workflow

The window uses the textured style, including brushed metal on Tiger. A full-width
status bar below the playlist sidebar and video table displays shared library activity even when a pane
is empty or hidden. Leopard and later draw its background using the native window
content border. Long messages truncate with the full text available in a tooltip;
selected download errors remain in the separate Download Queue window. The main video table fills its
pane edge to edge, with no surrounding labels or buttons. Video and playlist
actions are available through the toolbar and menu bar.

The menu bar uses File, Edit, View, Window, and Help. File groups playlist
addition/discovery, synchronization, downloading, playback, Finder reveal, and
Close Window. Edit contains standard text commands plus separate Remove Playlist
and Delete Download commands. View contains Show/Hide Playlists and Show Download
Queue. Window provides Download Queue, Minimize, Zoom, and Bring All to Front.
Download Quality, Video Player, and Cookies sit inside the application menu,
with Cookie Export Guide in Help.
The middle table shows a narrow, untitled status icon column before Video.
Playlist rows summarize all qualities: an existing playable file takes priority,
then downloading, queued, failed/interrupted/missing, cancelled, and not downloaded.
Playback and file actions use the representative job; changing preferred quality
no longer hides an available download. New explicit downloads still use the quality
preference. All Downloads keeps individual completed jobs and adds Quality after
Video to distinguish versions. Status tooltips and accessibility descriptions
provide text equivalents; long video titles truncate to fit the pane.

Playlist mode also includes Channel and Duration columns. The Video tooltip
shows available channel/duration, views, publication text, and description snippet;
views and publication labels are identified as captured at the last sync.
All Downloads retains its existing three columns.

Menu-bar commands retain their positions and disable when unavailable; download
and playback labels follow the active video or playlist selection. File's Download
command retries a selected queue quality using that job's exact format. Toolbar
menus retain their task-specific grouping.

Download Queue is a separate resizable window with the textured window style
(brushed metal on Tiger). The library has two panes and no inspector. The Queue
button, View > Show Download Queue, and Window > Download Queue open or focus this
window. It starts closed and remembers its own size and position. Closing either
window leaves the other usable and does not stop downloads. Its toolbar provides
Retry, Stop, Error, and Delete for the selected job. Queue confirmations
attach to the queue window. A bottom status bar mirrors shared library activity.

The queue is a flat, cell-based NSTableView, compatible with Tiger. Its columns
are number (blank header), status (blank header), Quality, Video, and Playlist.
Each download quality occupies one row, newest first (descending permanent
job ID), labeled with that permanent database job ID. Downloads still process
oldest first.
Deliberately deleted jobs are hidden; missing
files remain visible for retry. Text columns can be resized, with horizontal
scrolling available in narrow panes. Number and status columns stay compact.

Mac quality labels use `Low (18)`, `Med (136+140)`, `High (137+140)`, or
`Custom (expression)`. Queue, All Downloads, preset menus, download-button
tooltips, and download confirmations share this formatter. The labels identify
format presets rather than measured resolution. Queue retains requested-to-actual
format differences; All Downloads labels the saved format when available.

The queue uses AppKit’s default row height and the same status image cells and
Font Awesome icons as the video table. Status tooltips and Show Error expose full
failure details. Play, Retry, Stop Download, and Delete Download remain available
through the context menu; double-click plays a downloaded video. Each row retains
its exact job and containing playlist for toolbar/menu targeting. Selection
survives refresh and status changes without regrouping or automatic scrolling.
The queue status bar shows transfer progress; there is no global Pause control.

During processing, the app-wide status bar follows the same resolver and download
steps as the CLI: reading cookies, configuring the client, loading the mobile
player, requesting/refreshing metadata, selecting a format, downloading the player
script, solving challenges, the selected format and destination, transfer, and
finalization. Transfer text includes percentage (when known) and average Mbps;
the progress indicator measures the current transfer's bytes. Unknown progress
uses an indeterminate indicator. Completion shows `Downloaded · {size} MiB`.
The queue table's frame does not change when progress appears.

The complete wording is listed in [Status bar messages](status-messages.md).

`RDLPLibrary` owns the labels, transfer values, and one shared ten-second idle expiry.
Active operations retain their current phase and progress until they finish, even
when no events arrive for more than ten seconds. Once idle, every new message
resets the timer, including identical text; reading or refreshing the UI does not.
After ten idle seconds without a new message, text and progress clear. A new screen reads the same current value
and cannot resurrect expired text. Progress notifications update the status views
without rebuilding the library tables.

Adding, syncing, and discovering playlists use simple operation/result messages,
such as `Adding playlist…`, `Playlist added`, or `Error adding playlist`.
Cookie import/removal, file deletion, and queue bookkeeping do not write status
messages. Errors go into a shared alert queue; each app presents the title and
details using native alerts, one at a time. Download and playlist errors also
leave a short final status. Successful downloads with database/export warnings
produce an alert instead of hiding those warnings inside progress text.

The sidebar is an NSOutlineView with four collapsible, nonselectable parent
rows: System (All Downloads and the local **Ad-Hoc** collection), Added Playlists
(manually added), My Playlists (discovered through Load My Playlists), and
Unsupported Playlists. Groups start expanded and keep their
collapse state during library refreshes. Selecting a child keeps the existing
Download/Play targeting behavior. Discovery promotes an existing manual playlist
without duplicating it and preserves its selection, membership, and downloads.
Adding an individual video parses its URL/ID locally and immediately queues it
in Ad-Hoc at the quality selected when Add Video was submitted. A new video
initially displays its ID; known titles are preserved. The download worker resolves
the selected quality once, then updates the title and filename before transferring.
Both apps refresh the queued row as soon as its title is available. Downloads
start automatically while the queue is active; a paused queue stays paused.
Re-adding a video preserves queued, running, and completed downloads of that
quality, and retries failed, cancelled, interrupted, or deleted downloads.
This local collection is never synced to YouTube. Unavailable videos or qualities
fail as normal queue jobs and remain available for retry.

Database version 2 records discovery origin. Existing version-1 playlists migrate
to Added Playlists because their original source was not recorded. Running Load
My Playlists moves supported discovered matches into My Playlists. Using cookies
for an ordinary playlist sync does not change its group; clearing cookies does not
change stored provenance. Both app platforms can read the upgraded database.

Unsupported playlists (including History and Watch Later) retain their metadata
and provenance but appear only in Unsupported Playlists. The shared application
store uses the library’s offline `rdlp_parse_playlist_id` function to classify
IDs, exposed to SQLite for count/page queries without loading every playlist
into Objective-C objects. URL submissions also check the extracted ID against
the raw-ID parser. This is a local type check, not a network availability check.
No schema migration or persistent capability flag is needed. Both apps disable
manual Sync and omit these records from Sync All; the shared scheduler and
service also guard direct submissions before network work. Ad-Hoc remains in
System. Unsupported playlists can still be selected and removed locally.

Validation: Docker builds passed for macOS PowerPC/i386 and iOS armv7/arm64,
as did all 42 portable store tests, service integration, and app artifact checks.
Both Apple static analyzers reported zero warnings/errors. The full native Mac
regression suite passed on x4-vm with synthetic data, including unsupported
outline grouping, disabled Sync, bulk-plan exclusion, and submission guards.
The iOS UI regression bundle compiled; its new checks were not run on a device.


The main toolbar contains Library, Download, Play, Remove, flexible space,
Cookies, and Queue. Labels stay fixed, and each button has one responsibility.
Choose View > Customize Toolbar… (or right-click an empty toolbar area) to add,
remove, or rearrange the main-window buttons, insert spaces or separators, or
restore the default set. AppKit saves the arrangement and display settings for
future launches. The Queue window keeps its existing toolbar.

| Button | Main click | Menu |
| --- | --- | --- |
| Library | Open menu (plus icon) | Add Video, Add Playlist, Load My Playlists; then Sync Current Playlist and Sync All Playlists |
| Download | Download/retry the selected video, or confirm cancellation of queued/running work (arrow/stop sign) | Download Video, Retry Download with original quality when applicable, Cancel Download, Download Quality submenu |
| Play | Play the selected video or playlist in the selected player (YouTube icon) | Play Video or Play Playlist for the selection, Play Playlist for a selected video, Reveal in Finder |
| Remove | Confirm deletion of the selected download or removal of the selected sidebar playlist (fixed trash icon) | Delete Download for a selected video, or Remove Playlist naming the selected playlist |
| Cookies | Open menu (fixed cookie icon) | Import, Replace, Remove; then Export Guide |
| Queue | Show Download Queue (list-check icon) | None |

Library groups adding/discovering content separately from refreshing playlist
metadata. Its commands remain in stable positions across selection changes.
Queue navigation appears only on the Queue button, rather than in Library's menu.
Cookies remains available while busy so its guide is accessible; cookie mutations
are disabled until the library is idle.

Download never deletes files. It shows a stop sign for the selected queued/running
job and confirms cancellation. Failed, cancelled, interrupted, removed, or
missing-file jobs retry at their original quality. Otherwise it downloads at the
preferred quality, disabling duplicate downloads at that quality. A completed Low
copy can therefore remain playable while High is selected for a new download.
Download Video keeps a short menu title; Retry Download names the original quality.
Removal confirmations continue to identify the video and quality.
Changing Download Quality only saves the preference; it never starts a transfer.

Remove always uses a trash icon. A selected video targets its representative job;
a sidebar selection targets the playlist. All Downloads and Ad-Hoc cannot be
removed. Removal keeps the existing eligibility checks and confirmation sheets.
Play is disabled when no playback application is available; Reveal in Finder
remains an explicit menu command.

Main-window toolbar actions follow the library's own selection even when Queue
is active. Opening a contextual toolbar menu restores the library as the action
target. Menu-bar commands continue to follow the active window, including the
Queue's exact selected quality. Returning to the library or closing Queue restores
library targeting. An unplayable video never falls back to playing its playlist.

Starting or retrying a download reveals Queue, selects the job, and
scrolls it into view, even if the queue window was closed. The selected quality
is retained. The caret opens the same menu as right-click, Control-click, or
Accessibility Show Menu, including when the button's default action is disabled.
Open With is absent.
The application menu's Video Player submenu contains VLC, QuickTime, and Default
App, with a checkmark for the current choice. Uninstalled players are disabled.
The choice is saved for future launches; without a saved choice VLC is used when
installed, otherwise Default App. A saved player that is no longer installed
falls back to Default App. Default App follows the system file association.
Toolbar, File, queue, double-click, and whole-playlist playback all use this
preference; player-specific playback commands have been removed. Tiger uses a
named Brands glyph outline to avoid ATSUI’s
missing Unicode mapping. Destructive actions retain their confirmation sheets,
including the Remove button's action for a downloaded video.

Download Video is a direct command using the last selected quality. In File it
is disabled until a video is selected; the toolbar menu disables it without a video selection. There is no playlist-wide download command. The Download Quality
submenu appears in the Download toolbar menu and the RetroDLP application menu, and contains
Low (18), Med (136+140), High (137+140), and Custom Format…. Choosing a quality
only saves the preference; it never queues work.
Custom Format validates input and has Save/Cancel buttons. Saving changes only
the quality, and cancelling leaves it unchanged. Quality choices remain available
even if that quality already has a download. Use Download Video to start work.

Destructive and bulk actions use attached confirmation sheets: removal of files,
playlists, and cookies; cookie replacement; download cancellation; Sync All;
and account playlist discovery.
Cancelling a sheet performs no operation. Single-video enqueue/retry and
single-playlist metadata sync are immediate. Duplicate pending/running syncs are
not added again. Playlist removal remains unavailable until queued jobs are
cancelled and completed downloads removed; removal affects only the local library.

The Mac app processes queued downloads automatically on launch and when work is
added. Failed, stopped, and interrupted jobs require an explicit Retry. Stopping
one quality leaves other queued downloads eligible to run. The shared bridge's
Pause API remains available; iOS background expiration uses a separate suspension
gate that also stops playlist sync and discovery workers.

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
    Playlist.xspf
    Playlist.m3u8
  .staging/<local download ID>/       # partial transfers / retained mux inputs
```

A playlist's directory is stable after creation. Exported XSPF playlists use UTF-8,
percent-encoded relative file URIs, and current playlist order, including repeated entries. Only
completed files that still exist are exported. If several qualities exist, the
most recently created completed job supplies that video's playlist entry. A
video in different playlists has an independent local copy in each folder.
The root `xml:base` is the percent-encoded absolute `file://` URI of the playlist
directory with a trailing slash, allowing VLC 0.9.10 to resolve relative tracks.
Moving a library requires regenerating its playlists to update that base.

Each track carries the occurrence's title, channel as artist (`creator`),
description (`annotation`), first stored thumbnail URL (`image`), playlist title
as `album`, original one-based position (`trackNum`), and duration in milliseconds
when available. The YouTube video URL supplies both `identifier` and `info`.
Channel ID, numeric and display view counts, and publication text are preserved
in `meta` fields whose `rel` values start with
`https://github.com/jeffreybergier/Retro-DLP/metadata/` and end in the database
field name (`channel_id`, `view_count`, `view_count_text`, `published_text`).
VLC can display the standard fields; custom metadata is retained for readers
that understand it. Missing optional values are omitted, and known zero values
remain zero. Publication text is not treated as an exact date. The export does
not fetch artwork or modify media files. The playlist itself includes its title
and YouTube URL, except that the local Ad-Hoc collection has no YouTube URL.
Both files are generated from the same query and row traversal, preserving identical
files, order, and duplicates. M3U8 uses UTF-8, plain relative filenames,
and `EXTINF` metadata containing duration in seconds (or -1 when unknown), channel,
and title. Line breaks in metadata are flattened. XSPF retains the richer fields.
Startup reconciliation regenerates both files, each published with an atomic rename
after both have been fully written. The M3U8 file remains portable with its folder.

When VLC is the selected player, native code reads `CFBundleShortVersionString`
from its app bundle and compares numeric version components. VLC below 1.1.12,
or an absent/unrecognized version, opens `Playlist.m3u8`; VLC 1.1.12 or newer
opens `Playlist.xspf`. Single-video playback and other player choices keep their
existing behavior. A missing compatible playlist does not fall back to XSPF on
old VLC. The threshold is conservative: 0.9.10 crashes in its Mac interface with
XSPF tracks, while 1.1.12 was tested without that crash.

`~/Library/Application Support/RetroDLP/retrodlp.sqlite` stores the library and
queue. Cookies are copied to an owner-only file alongside it. The original
imported cookie file is not removed.

## iOS workflow

The fresh-launch root is `RDLPPlaylistsViewController`, a `UITableViewController`
with a plain table titled **Playlists**, containing System
(All Downloads and Ad-Hoc after adding a video), Added Playlists, My Playlists,
and Unsupported Playlists. These section headers use UIKit's default sizing and do not collapse. Empty sections have
zero rows and no placeholder footer. Swipe an Added Playlists, My Playlists, or
Unsupported Playlists row to reveal **Delete**. Tapping Delete removes only its local library entry; the
YouTube playlist is unchanged. All Downloads and Ad-Hoc cannot be deleted.
Removal is unavailable while the library is busy or the playlist has pending or
completed downloads. The swiped playlist stays fixed across refreshes, and these
restrictions are checked again when Delete is tapped. Dismissing the swipe does
nothing. The top-left Font Awesome gear opens Settings
modally with a Done button. Settings is a dedicated `UITableViewController`
with no bottom status area and no explanatory section footers. Its
**Import Cookies...** row has no subtitle and is disabled while cookies are
imported (or the library is busy); removing cookies enables import again. Cookie
action rows have no disclosure chevrons. The
top-right Font Awesome **+** opens an action sheet with **Add Video…**,
**Add Playlist…**, **Sync All Playlists…**, and **Load My Playlists…**.
These commands reuse the existing input and confirmation dialogs. Download
quality is available in Settings. Cancel does nothing.
On All Downloads and Ad-Hoc, the top-right **+** opens the **Add Video**
URL/ID prompt directly, without an action sheet. Other playlists retain Sync.
The home screen uses ENIL's status-toolbar layout: a content-sized center view
between flexible spaces, with a Font Awesome Queue button on the right. UIKit
provides the native iOS 5/6 gloss and bordered button, or iOS 7+ flat chrome and
tinted button. Empty status is idle. The shared bridge clears the last message
after ten idle seconds without a new event on both platforms; active work remains visible. Idle text is bold 15pt;
active text is bold 13pt with a 100pt transfer-progress track when its total is
known, or a spinner in the left toolbar slot when it is unknown. The spinner
hides when stopped while its toolbar slot remains reserved. The Queue button
uses UIKit's natural width; on Queue itself the right slot is empty.
Legacy text uses ENIL's white engraved
shadow; iOS 7+ uses dark text without a shadow. Long text truncates in the middle
to leave room for Queue; its full text remains accessible.
The toolbar replaces the home screen's old status footer. Playlist and All Downloads
share `RDLPVideoListViewController`, a plain `UITableViewController`, including
subtitle cells, status accessories, playback/retry handling, and toolbar lifecycle.
Their entire toolbar is hidden for empty status and animates out when
the shared idle message expires after ten seconds. Offscreen refreshes do not change the
visible screen's toolbar. Playlist alone adds the Sync button. Both video lists
remain blank when empty, with no placeholder section footer.

Playlist and All Downloads subtitles show duration, completed file size, quality,
and channel, in that order, for example
`12:34 · 24.3 MB · Low (18) · Example Channel`. The trailing channel text
truncates first. Missing fields are omitted; a present zero duration displays as `0:00`. VoiceOver speaks
duration in hours, minutes, and seconds. Views, publication text, and description
snippets are stored for future iOS information views.

Both apps automatically upgrade existing databases to schema version 5 and save
all optional playlist metadata on the next sync. Thumbnail URLs are stored in a
separate table; images are neither fetched nor displayed. See
[Playlist detail metadata](playlist-detail-review.md) for field semantics,
migration behavior, and validation.

Queue opens modally in its own navigation controller with a **Done** button.
The toolbar button and Show in Queue actions use the same presentation. Revealing a
job inside Queue reuses the open screen instead of stacking another modal.

Open a playlist and tap **Sync**. Pending syncs/discovery
cannot be submitted again. Sync All and account discovery confirm their scope.

The Playlists home screen, individual playlist video lists, and All Downloads use standard
UIKit subtitle cells, with default typography, single-line labels, and row heights.

Playlist keeps one row per playlist entry and summarizes every downloaded quality.
A playable file takes priority over running, queued, failed/missing, and stopped
work, even when the preferred quality differs. All Downloads keeps one row per
completed job, including multiple qualities of the same video. Both screens share
`RDLPVideoRows`, which builds the title, subtitle, status, accessibility text, and
tooltip lazily. Actual downloaded quality takes precedence over requested quality.
Quality and size appear only when the completed job has an existing regular file.
A single filesystem check supplies status and byte size, cached with the display
row; playback and deletion revalidate the current file. Size uses decimal KB
(rounded up) below one million bytes and MB (one decimal) above that threshold.
No size is stored in the database.

macOS uses the same Status, Size, Quality, Video, and Channel columns
for Playlist and All Downloads. Text columns are resizable, and narrow panes can
scroll horizontally. Video tooltips include metadata and local file details.

Version 5 stores text metadata on jobs, backfills existing jobs from the first
matching playlist occurrence, and refreshes it atomically during sync. Jobs keep
that metadata if their playlist occurrence disappears. Playlist rows retain each
occurrence’s own metadata. The iOS base controller uses small source/action hooks;
its named Playlist, All Downloads, and Queue subclasses retain their navigation
and action differences without branching on a rendering mode.

Quality labels across iOS lists, Settings presets, job dialogs, and confirmations
share the Mac formatter: `Low (18)`, `Med (136+140)`, `High (137+140)`, and
`Custom (expression)`, without resolution claims.
Tapping plays that row's local file, ignores pending work, or offers an exact-quality
retry for failed/missing downloads. An undownloaded playlist entry queues the
preferred quality, including after deliberately deleting its previous download.
Changing Low to Med after deletion therefore queues Med; the old Low job stays
removed. All Downloads retains each job's playlist identity internally.

Swipe a completed, failed, interrupted, or stopped video row to reveal **Delete**.
Tapping Delete removes that row's quality and any staged audio/video fragments;
other qualities and playlist membership remain. All Downloads removes the row,
while Playlist updates its representative download or shows an undownloaded row.
Queued/running downloads must be stopped first, and deletion is disabled while the
library is busy. The selected job stays fixed during the swipe, and its eligibility
is checked again when Delete is tapped. Dismissing the swipe does nothing.
Deletion and the post-swipe refresh run after UIKit's editing callbacks return;
reloading during confirmation dismissal can recursively reenter UIKit on iOS 8.

Choosing Low, Medium, High, or saving a valid Custom Format only saves the
preference. It does not download anything. **Download Missing** confirms an exact,
deduplicated plan at the selected quality. It includes new and removed/missing-file
downloads, skips failed/interrupted/stopped jobs, and rechecks eligibility before
performing the captured plan. Single-video downloads are immediate; failed or
missing rows in Playlist and All Downloads confirm an exact-quality retry.

Queue shares the native `UITableViewController` base and standard subtitle cells
with Playlist and All Downloads. It is a flat list with newest items first
(descending permanent job ID); downloads still process oldest first.
Titles use permanent database job IDs, such as `42) My Video`;
these numbers stay the same across retries and retain gaps when jobs are deleted.
Each quality gets its own row,
with quality followed by playlist in the subtitle and the same trailing Font Awesome status
icons as Playlist and All Downloads.
States are Queued, Downloading, Downloaded, Failed, Stopped, Interrupted, and File
missing. Deliberately deleted jobs are hidden; missing files remain retryable.

Tapping a row shows its status, full error, and applicable Play, Retry Download,
Stop Download, and Delete Download actions. Actions recheck the stable job ID and
current state after confirmation. Revealing a job selects and scrolls to its exact
quality. Ordinary refreshes retain selection without scrolling or regrouping rows.

Queue uses the same shared bottom status toolbar without a Queue button. It hides
with animation when the shared status clears. The older video detail controller
retains its fixed status area. Progress always describes the current transfer;
historical jobs and queue attempt counts do not contribute to the visible bar.

Deleting a download, stopping work, removing a playlist, replacing/removing
cookies, and bulk operations require confirmation. For swipe deletion, tapping
the revealed Delete button is the confirmation; other deletion actions use a dialog.
Cancel performs no operation.
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
private sandbox entitlements are used. Native playback always uses
`MPMoviePlayerViewController`. Opening a video restores its saved position and
waits for the user to tap the native Play button; the app does not start playback
automatically. H.264 profile, level, resolution, and frame rate still need to be
supported by the device; choosing an MP4 format does
not transcode it.

On iOS, opening the library marks `Documents/RetroDLP` as excluded from iTunes
and iCloud backups. The directory-level flag covers existing videos, future
downloads, exported playlists, and `.staging` partials. The database and working
cookies remain eligible for backup. iOS 5.1+ uses
[`NSURLIsExcludedFromBackupKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/isexcludedfrombackupkey);
the legacy `com.apple.MobileBackup` extended attribute supports iOS 5.0.1.
iOS 5.0 itself has no supported backup-exclusion flag. Failures setting the flag
are reported through the app's error queue.

Downloads process automatically on launch and when returning to the foreground.
Each worker holds a main-thread operation reference through completion. The
AppDelegate observes this count and requests a UIKit background task before work
starts, keeping it across consecutive operations and releasing it when the count
reaches zero. Downloads, playlist sync, account discovery, and startup
reconciliation share this lifecycle. Backgrounding no longer immediately cancels
an active transfer.

Each download that completes while the iOS app is in the background sends a
local alert with sound: `Download Complete 'Video Title'`. It uses the final
stored title, including titles resolved during Ad-Hoc downloads, and is sent
before releasing background execution time. Foreground downloads, failures,
cancellations, and library reconciliation do not send completion alerts.
Delivery uses `UILocalNotification` on iOS 5+; iOS 8+ requests alert and sound
permission, and system notification preferences control presentation.

UIKit grants a finite amount of execution time using
[`beginBackgroundTaskWithExpirationHandler:`](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(expirationhandler:)).
It needs no `UIBackgroundModes` entry or entitlement. When time expires (or a
background request is denied), the delegate cancels active requests, blocks all
new workers, and ends the task without waiting for worker completion. Returning
to the foreground resumes queued work; interrupted/stopped/failed downloads
still require explicit Retry. Stopping one quality leaves other queued downloads
eligible to run. There is no global Pause control or indefinite background
downloading.

iOS downloaded-video playback uses `RDLPDownloadedPlayerViewController`, a small
app adapter in `source/gui/iOS/`, over `RDLPPlayerViewController` and
`RDLPPlayerQueue`. The reusable `source/gui/iOS/player/` folder has no app-code
dependencies; library/job metadata and bookmark persistence stay in the adapter.
A playlist-row
tap queues all available downloaded entries in playlist order, selects the tapped
occurrence, restores its bookmark, then autoplays. Missing files and unfinished
downloads are excluded. Repeated entries remain distinct, and each entry uses its
newest existing downloaded quality, with the tapped job preserved exactly.
All Downloads and individual-video Play actions still create one-item queues.
Previous/next buttons and remote track commands navigate the available entries.
Automatic advancement restores each video's bookmark and updates Now Playing;
the final item stops without wrapping. The playlist button remains hidden.
Audio Only disables the item's video tracks and
detaches the video layer; Show Video restores them without replacing the item.

The app declares `UIBackgroundModes = audio` and activates
`AVAudioSessionCategoryPlayback` when the player appears. The UI detaches its
AVPlayerLayer before backgrounding, following Apple's
[background audio guidance](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MediaPlaybackGuide/Contents/Resources/en.lproj/RefiningTheUserExperience/RefiningTheUserExperience.html).
Home/lock can continue audio; Done ends playback and deactivates the session.
Foregrounding never forces playback to resume. iOS 5 remote-control events
support play, pause, toggle, and stop; interruption handling resumes only when
playback was active and the system allows it. Downloads still use the finite
background-task allowance described above.

The adapter publishes title, channel, elapsed time, duration, and playback rate
through `MPNowPlayingInfoCenter`. AVFoundation rate/readiness/buffering changes
and time-jump notifications refresh metadata, including paused seeks and
background remote control. Completion, failure, and dismissal clear metadata;
an old controller cannot clear its replacement's metadata. Missing titles fall
back to the video ID; missing channels omit the artist.

Bookmarks save during foreground and background playback, including paused
seeks. An AVPlayer periodic time observer checkpoints every ten playback seconds;
time-jump notifications debounce seeks for 0.5 seconds. The custom scrubber
previews while dragging and performs one seek on release. Pause, backgrounding,
and Done flush the latest position immediately. Identical saved positions skip
the database write. Autoplay starts after restoring the saved position.

At ten percent of the duration or earlier, or ninety percent or later, a
checkpoint saves zero so the next viewing starts over. Natural completion also
saves zero in the background. Existing checkpoints near either end restart
from the beginning.
iOS captures accepted positions in memory and writes them on a serial background
queue, so player callbacks do not wait for SQLite or a download worker's database
lock. Reads see pending checkpoints. Writes already accepted hold the existing
finite background-operation allowance until they finish; an abrupt process kill
can still interrupt a pending write.

Build the focused downloaded-player and checkpoint regression suite with
`RDLP_TEST_PLAYBACK_ONLY=1 python3 source/gui/iOS/tests/build_ios_ui_test.py`.
Use `RDLP_TEST_INTERACTION_ONLY=1` instead to include the Low/delete/Medium
redownload regression.

The shared library uses platform categories from `iOS/RDLPLibrary+iOS.m` and
`macOS/RDLPLibrary+macOS.m`. iOS owns its backup-exclusion setup, checkpoint
cache, and serial writer; shared code owns the SQLite primitives and operation
references. No platform-selection macros are needed in the shared Objective-C
library.

## Shared architecture and invariants

- `rdapp_store.{h,c}`: normalized SQLite tables, complete playlist snapshots,
  ordered membership, durable jobs, recovery, file removal, path construction,
  and atomic XSPF/M3U8 exports. No Apple headers.
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

Resolver workers receive a 2 MiB native stack, leaving headroom above QuickJS's
1 MiB stack limit. The default 512 KiB worker stack can hit its guard page during
recursive JavaScript conversion before QuickJS can return an exception. iOS sets
the stack size on `NSThread` before starting it. macOS uses detached POSIX threads
so this also works on Tiger; a one-time empty `NSThread` launch enables Cocoa's
internal thread locks when necessary. The shared native worker regression runs
recursive QuickJS array conversion through the real scheduler and checks the
actual stack allocation, exception result, and balanced completion.

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
| Sidebar outline and discovery provenance | Collapsible System, Added Playlists, My Playlists, Unsupported Playlists sections |
| Flat queue table with job ID, status, quality, video, playlist columns | Native flat subtitle cells, permanent job IDs, status accessories, and stable-ID job actions |
| Context commands, quality preferences, confirmations | Video/job dialogs, Settings, and captured/revalidated alert requests |
| Representative status and app-wide progress | Shared download policy, status icons, fixed status/progress area |
| Automatic queue processing | Automatic processing with finite background execution and cancellation on expiration |
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
- The queue reuses `RDLPTableView` and `RDLPStatusCell`; a flat job snapshot
  displays newest items first and preserves selection by permanent job ID.
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

Flat macOS Queue (2026-09-15): PowerPC, i386, x86_64, and arm64 builds and
package validation passed. The static analyzer reported zero warnings/errors.
The offline native suite passed on x4-vm (Tiger 10.4.11), covering five-column
order and blank headers, consecutive processing-order numbers, one row per
quality, status/error tooltips, exact-quality context-menu retry and stop,
selection stability, and existing playback, sidebar, menu, and progress behavior.
The Tiger run caught unsupported integer convenience methods in the initial
implementation/test; the final code uses Tiger-compatible numeric APIs.

Native iOS Queue (2026-09-15): armv7/arm64 builds, package validation, and the
static analyzer passed with zero warnings/errors. All 13 portable store tests and
the local HTTPS service integration passed. The isolated native suite passed on
`koolphone5` with the merged playlist-metadata library, covering plain subtitle
cells, processing order and consecutive numbering, status glyph rendering, empty
queues, exact-quality retry/stop, stable selection, and animated toolbar expiry.
UIKit's real row-edit/Delete controls verified that deleting a queue job closes
the display-number gap while missing files remain retryable. The full existing
Playlist/All Downloads, playback, and swipe regressions also passed. Queue and
active-progress screenshots were inspected. Network work remained disabled in the
native fixture; older iOS versions and the arm64 slice were cross-built/analyzed.
The follow-up icon correction removes Queue’s icon override so it inherits the
Playlist/All Downloads renderer. Build and package checks passed; native UI tests
were not rerun for that correction.

Shared iOS video lists (2026-09-15): armv7/arm64 app builds and artifact checks
passed, the iOS static analyzer reported zero warnings/errors, and the portable
store/service suites passed. The isolated native suite passed on `koolphone5`,
covering matching Playlist/All Downloads cells, representative playlist rows,
separate completed qualities, exact-file playback, missing-file retry, empty state,
and animated ten-second toolbar expiry across navigation and modal dismissal.
Playlist and All Downloads screenshots were inspected.
The follow-up native swipe-deletion suite also passed on the same device: it
verified exact-quality deletion, sibling and playlist preservation, cleanup of all
staged fragments for failed/interrupted/cancelled jobs, cancelled swipe behavior,
and revalidation when work starts or a quality is requeued during the gesture.
An iOS 8 crash report subsequently exposed recursive table reload during UIKit's
confirmation dismissal, which direct delegate-call tests missed. The fix defers
deletion and refresh until those callbacks return. The updated native suite passed
on `koolphone5`, including pressing UIKit's real row-edit/Delete controls to remove
the last All Downloads row, plus the existing playback, toolbar, and cleanup tests.

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
python3 source/gui/iOS/tests/build_ios_ui_test.py
scp build/apps/tests/RetroDLPIOSOfflineTest.ipa koolphone5:/tmp/
ssh koolphone5 'appinst /tmp/RetroDLPIOSOfflineTest.ipa'
ssh koolphone5 'su mobile -c "uiopen retrodlp-offline-test://run"'
```

The test has bundle ID `test.retrodlp.ios` and creates synthetic data only inside
its own Documents fixture directories. Run test builds on `koolphone5`;
`gomadango` is a production phone and receives only final production IPAs.
Its `RDLPOfflineLibrary` overrides scheduling
to never start a worker, and the bundle omits the CA resource. It can exercise
sync/download actions without contacting YouTube. Native playback uses a bundled,
FFmpeg-generated local MP4. Result and screenshots are in the test app's Documents
(`result.txt`, `library.png`, `queue.png`, `progress.png`). On old iOS, allow Launch
Services to finish registering a newly installed app before opening it. Reinstall
the IPA for new test builds; overwriting a running signed executable in place can
leave the kernel's cached signature stale.

The playback tests cover Now Playing title/channel, duration, resume position,
play/pause, paused seeks, simulated background updates, completion/error cleanup,
and replacement-player ownership. They allow legacy MediaPlayer's metadata
updates to settle before reading back the dictionary. For an interactive lock
screen check, build with `RDLP_TEST_PLAYBACK_ONLY=1 RDLP_TEST_NOW_PLAYING_HOLD=1`
prefixed to the Python command above. The native-player test then plays a local
60-second video with silent AAC audio and holds for about 35 seconds. Lock the
device and use its system media controls to resume/pause; `NativePlayback/controls.txt`
records the movie state and published metadata during that interval.

Now Playing validation passed on `koolphone5` (iOS 8.4.1): the complete offline
suite, plus an actual lock-screen check showing video title, channel, elapsed
time, and working system pause/resume. Captures are under
`build/apps/tests/now-playing/`. The armv7/iOS 5 and arm64 builds, static analysis
(zero warnings/errors), and app artifact validation passed. iOS 6 was checked
for API compatibility against the SDK declarations, but was not run on a device.

The lifecycle fixture verifies the real backup-exclusion flag while preserving
existing media and keeping library metadata eligible for backup. It also runs
the real scheduler and AppDelegate with synthetic worker completions and simulated
OS grants, checking reference balancing, consecutive operations, errors,
expiration, denied grants, foreground return, and shutdown. It does not measure
the OS background time allowance or perform live background network transfers.

The notification fixture runs the real scheduler and completion handler with
synthetic workers and persisted job outcomes. It checks exact alert text,
resolved Unicode titles, default sound, delivery before the task ends, and
suppression for foreground work, failures, cancellation, and uncommitted success.
It captures local notifications at the UIKit delivery boundary; it does not
verify system banner presentation or notification permission dialogs.

The full native suite, including notification regressions, passed on koolphone5
(iOS 8.4.1). The universal iOS build, static analysis (zero warnings/errors),
32 host store tests, service integration, and package validation also passed.
The final production IPA was installed on gomadango over SSH/SCP. Logs are in
`build/apps/tests/notification-review/`.

Backup/background lifecycle update (2026-09-16): the full isolated iOS suite
passed on `koolphone5`, including this fixture. Both iOS slices and all four
macOS slices built, the iOS static analyzer reported zero warnings/errors,
all 32 portable store tests and the local HTTPS service suite passed, and both
platforms passed artifact validation. The production IPA was built but not
deployed as part of this validation.


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
make -C source/gui/macOS analyze
make -C source/gui/iOS analyze
```

The macOS analyzer retains Clang, the macOS 11.3 SDK, and an x86_64 analysis
target even though the shipped app contains only GCC-built `ppc` and `i386`
slices. Analysis does not build or link a modern macOS executable.

Reports remain under `build/apps/<platform>/analyze`. Cross-builds and static
analysis establish compilation and API/link compatibility, not device launch or
decoder performance. Native iOS playback should be checked on each device class
before distributing a release.

For an isolated Mac UI test, generate synthetic media and metadata with
`python3 source/gui/shared/tests/prepare_native_fixture.py /absolute/test/state`.
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

After `make app-macOS`, run `python3 source/gui/macOS/tests/build_mac_toolbar_test.py`
to build `build/apps/tests/RetroDLPToolbarTest.app`. This test-only PowerPC bundle
omits the CA resource. Prepare a fresh library with
`python3 source/gui/shared/tests/prepare_native_fixture.py /tmp/retrodlp-toolbar-fixture`,
copy the app and fixture to `/tmp` on the Tiger test Mac, and launch the test app.
It writes `/tmp/retrodlp-toolbar-test.txt` and exits. Recreate/restore the fixture
before each run; the test deliberately changes only that fixture.

For focused native playback routing tests, run the test bundle's executable with
`RDPlaybackTestOnly=1`. It creates and removes its own temporary playlist fixture,
checks versions below/at/above 1.1.12 and malformed/missing versions, and verifies
playlist dispatch, missing-file behavior, and unchanged single-video paths.

For toolbar persistence coverage, launch with `RDToolbarCustomizationTest=save`
in the test bundle's `LSEnvironment`, then relaunch with that value set to
`restore`. These checks remove/reinsert buttons, save a custom layout and display
settings, verify them in the new process, and open/close the native customization
palette. The restore pass clears the test bundle's saved toolbar configuration.

Set `RDToolbarPreview=1` in the test bundle's `LSEnvironment` to keep the paused
offline library open for `mac_toolbar_menus.applescript`. This accessibility test
checks the six-button order, Library and Cookies primary menus, Add Video dispatch,
and the separate Remove confirmation without approving any work.

Set `RDQueueWindowTestOnly=1` in the test bundle's `LSEnvironment` to run the
focused queue-window regression using the same fresh fixture. It checks the
two-pane library, textured queue window, toolbar actions and attached sheets,
exact-job selection, independent window closure, continued queue management with
the library closed, and saved window geometry. `RDQueueWindowScreenshot=1` also
captures `/tmp/retrodlp-queue-window.png` before exercising destructive controls.

The native test exercises real toolbar controls, pane targeting, fixed menu
structure, removal/cancellation sheets, absence of playlist downloads and removed-file
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


Shared status revision (2026-09-15): all four macOS and both iOS slices built
without compiler warnings. Both static analyzers reported zero warnings/errors;
portable store/service tests and app artifact validation passed. The same bridge
regressions passed natively on Tiger 10.4.11 and iOS 8.4 (`koolphone5`), covering
CLI phase delivery, byte progress, simple playlist results, silent cookie changes,
separate errors, identical-message timer reset, and expiry while busy. Native Mac
and iOS suites also exercised real error alerts; iOS checked sequential dismissal.
Tests used isolated synthetic libraries and test bundles without the CA resource;
no live YouTube downloads were performed. The Tiger run caught the Foundation
common-mode constant's 10.5 dependency; shared expiry uses the Tiger-compatible
Core Foundation constant instead.


### Ad-Hoc collection validation (2026-09-15)

All four macOS and both iOS architecture slices built without warnings. Bundle
validation passed, and both Apple static analyzers reported zero warnings/errors.
The 28 portable store tests and local-HTTPS service integration passed, including
adding a video when the saved download quality is unavailable, duplicate updates,
retained queued jobs, invalid input, and system collection grouping.

The native offline suites passed on x4-vm (Tiger 10.4.11, PowerPC) and koolphone5,
including Add Video dialogs, Ad-Hoc placement, disabled sync, and existing
queue/download/playback regressions. These tests use isolated fixture libraries;
live YouTube access was not tested. The release IPA was installed on koolphone5,
and the Mac release was extracted to `~/Desktop/RetroDLP-AdHoc/RetroDLP.app`.
Review logs and native results are in `build/apps/tests/adhoc-review/`.

### Ad-Hoc startup and active progress validation (2026-09-16)

Add Video now queues locally with no resolver requests. The normal download
worker resolves the requested quality once, publishes the title and final path,
and notifies both frontends before transferring. Active status survives quiet
phases longer than ten seconds; idle completion messages still expire.

All 32 portable store tests and the local HTTPS service integration passed,
including zero-request admission, one resolver pass, title/path persistence,
duplicate submissions, retries, and preservation of completed files. Both
universal app builds and static analyzers passed (zero warnings/errors).
The full offline native suites passed on x4-vm (Tiger 10.4.11) and koolphone5
(iOS 8.4.1), including local admission during active work and a quiet active
phase lasting over ten seconds. Queue-order test expectations were corrected
for Tiger's string APIs and the iOS fixture's additional queued jobs.
No real YouTube requests were made; device tests used isolated libraries and
synthetic media. Live network startup latency was not measured.

### Ad-Hoc automatic download validation (2026-09-15)

The updated UI suites passed over SSH/SCP on x4-vm (Tiger 10.4.11, PowerPC)
and koolphone5 (iOS 8.4.1, armv7). The iOS suite additionally checks that Add
Video captures the selected quality before the preference changes.

The portable service integration test also ran natively on both devices, using
synthetic resolver responses and a local HTTPS media server through SSH reverse
forwarding. It verified that Add Video queues the selected quality without a
separate enqueue call, the queued video downloads successfully, re-adding a
completed quality creates no pending download, unavailable quality fails through
the normal download path, and invalid input creates no job. Existing export,
retry, cancellation, and removal checks passed as well.

All 30 Linux store tests and the Linux service integration passed. Both app builds
and bundle validation passed. Tests used isolated libraries and test apps; no
live YouTube requests were made. Device reports are in
`build/apps/tests/autodownload-device-review/`.
