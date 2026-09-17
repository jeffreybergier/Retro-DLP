# Playlist detail metadata

The review of library commit `1c1d408919c68c1217d77f7f159b524c3c1934e5`
found that the Cocoa apps discarded its optional playlist metadata at sync time.
Both apps now persist that metadata and display the text fields described below.
Thumbnail URLs are stored only: images are never requested or displayed.

## Display

| Data | iOS Playlist / All Downloads | macOS Playlist / All Downloads |
|---|---|---|
| Duration | Subtitle, before channel | Video tooltip |
| Channel | Subtitle | Resizable Channel column and Video tooltip |
| Views and publication text | Stored for a later richer layout | Video tooltip, labeled “At last sync” |
| Description snippet | Stored for a later information view | Video tooltip when available |
| Channel ID | Stored identifier | Stored identifier |
| Thumbnail URLs | Stored per playlist occurrence only | Stored per playlist occurrence only |
| Local quality and size | Subtitle when completed file exists | Quality and Size columns when completed file exists |

An iOS row with a playable Low-quality copy now looks like:

```text
Building a tiny Macintosh                          ✓
12:34 · 24.3 MB · Low (18) · Example Channel
```

Missing subtitle components and their separators are omitted. Quality remains
visible only for a playable local copy, using the existing quality label rules.
The trailing status icon, row height, tap-to-play/download behavior, and swipe
Delete remain intact. Accessibility speaks durations as hours, minutes, and
seconds, and announces file sizes in kilobytes or megabytes. The native subtitle
label truncates at the end, so the trailing channel text truncates first.

macOS uses Status, Size, Quality, Video, and Channel in both screens.
Text columns can be resized; horizontal scrolling keeps every field reachable in
a narrow pane. Video tooltips include the title, channel/duration, source
view/publication labels, description snippet, and local file details. The existing
status/error tooltip remains. The table stays cell-based for Mac OS X 10.4.

Both apps use `RDLPVideoRows` for presentation. Playlist selects a representative
job for each occurrence; All Downloads uses each exact completed job. Presentation
has no playlist/download mode. The small iOS subclasses supply data and retain
screen-specific actions such as Sync.

The download policy reads a completed file’s type and byte size with one `stat`
call, reused for status, quality, and size. Only regular files qualify. Display
rows cache this result with the existing 128-row bound; refresh gets fresh file
information, and actions always recheck. Size is not persisted: below 1,000,000
bytes it displays rounded-up decimal KB; otherwise it displays MB to one decimal.

## Data path and semantics

- [rdapp_service.c](../source/gui/shared/rdapp_service.c), `sync_playlist`, reads
  every optional metadata accessor while the library playlist is alive.
- [rdapp_store.h](../source/gui/shared/rdapp_store.h), `rdapp_entry`, carries
  borrowed strings, ordered thumbnail URLs, and explicit numeric presence flags.
- [rdapp_store.c](../source/gui/shared/rdapp_store.c), `rdapp_store_snapshot`,
  copies strings into SQLite before the playlist is destroyed. Metadata belongs
  to `(playlist_id, position)` so duplicate video IDs remain independent.
- [RDLPLibrary.m](../source/gui/shared/RDLPLibrary.m) loads row dictionaries on
  demand and provides shared duration, accessibility, summary, and tooltip formatters.
- [RDLPVideoRows.m](../source/gui/shared/RDLPVideoRows.m) builds the shared
  presentation for both platforms and sources. iOS sections choose the source;
  its shared list controller renders the native subtitle cell.
- [RDLPLibraryWindowController.m](../source/gui/macOS/RDLPLibraryWindowController.m)
  manages macOS columns and tooltips.

Duration and exact view count use nullable 64-bit SQLite integers. Zero is present
and displays as `0:00` or `0 views`; absent values stay empty. The library's maximum
numeric value, `2^53 - 1`, remains exact on PowerPC and armv7. The Objective-C bridge
represents SQL numbers as strings and NULL as an empty string, so formatters check
presence before conversion.

Source view labels take precedence over numeric fallback formatting. Rounded,
localized, and live-viewer labels stay verbatim. Publication text such as “2 days
ago” is identified as captured at the last sync; it is not converted into an
estimated date. Description snippets may be truncated by the source. Missing
duration does not imply a live video, and these fields do not establish download
availability or quality.

A successful sync replaces all metadata from that snapshot, clearing fields now
absent. Failed snapshots roll back entries and metadata together. No global-video
metadata merge is performed. The library's authoritative browse response can
omit metadata present only in its discarded bootstrap page.

## Database upgrades

Version 3 introduced `entry_thumbnails`, keyed by playlist, position, and thumbnail
index. Version 4 adds channel, channel ID, source view/publication labels,
description snippet, duration, and exact view count to `entries`. Version 5 adds
these same seven fields to `jobs`. Enqueue and migration copy the first matching
occurrence, without duplicating jobs. Sync refreshes matching jobs atomically,
including clearing absent fields; jobs whose occurrence disappears keep their
previous metadata. Different playlist occurrences retain independent entry data.

Versions 1, 2, 3, and 4 upgrade transactionally on open. Existing entries initially
have unknown text metadata; syncing fills whatever the service provides. Download
jobs and previously stored thumbnail URLs survive the upgrade. There is no need
to delete the database or redownload media.

Thumbnail rows retain source order, are replaced with their entry snapshot, and
cascade away when their entry is deleted. Normal table-row queries exclude these
URLs. No thumbnail bytes, image cache, image downloader, or image UI is added.

## Loading and validation

The [on-demand loading architecture](list-loading.md) is preserved: counts and
refreshes do not format all entries, row caches remain bounded, and sequential
reads use indexed positions. Displaying text metadata adds no per-video resolution
or thumbnail requests. Playlist ordering and duplicate occurrences are unchanged.

Portable tests cover all optional fields, Unicode, zero versus NULL, rounded view
labels, 64-bit limits, duplicate occurrences, replacement, rollback, migration,
thumbnail cleanup, and retained download jobs. The service fixture verifies that
all metadata remains stored after playlist destruction and asserts only the existing
playlist page/browse requests. The 50,000-entry loading regression remains covered.
Native tests exercise both platforms' formatting, iOS subtitle/quality/accessibility
behavior, macOS columns/tooltips, and switching between Playlist and All Downloads.

Validation of the initial metadata increment passed: 25 portable store tests, the local service integration suite,
all iOS/macOS app builds, both static analyzers (zero warnings/errors), and bundle
artifact checks. The full native suites passed on koolphone5 (iOS 8.4) and x4-vm
(Tiger 10.4.11), using isolated synthetic libraries without YouTube requests.
The iOS screenshot confirms the subtitle layout with no thumbnails.

The Mac test helper now uses the current queue snapshot. Its long synchronous
callback also needed a higher process-local file-descriptor limit: unlike normal
AppKit events, its autoreleased SQLite snapshots survive across many actions.
The suite passed with a 4096-descriptor limit; the test harness now requests that
limit itself. This changes only the test process, not the production app.

The shared-row increment adds portable tests for version-4 backfill, job metadata
refresh/removal retention, and rollback. Native tests cover identical presentation
across screens, exact per-quality file sizes, zero and 64-bit byte counts, lazy
loading and one filesystem probe per cached row, deleted files, and directories
that must not count as playable files. Font Awesome scale checks are documented
in [icon-scale-review.md](icon-scale-review.md).

The completed shared-row increment passed all 27 portable store tests, the local
service suite, universal builds, both analyzers with zero warnings/errors, and
artifact checks. Full native suites passed on koolphone5 and x4-vm, including
shared row/file-size behavior and icon scale coverage. The phone’s Playlist and
All Downloads screenshots were inspected. Updated production packages were
installed on koolphone5 and copied/extracted on x4-vm’s Desktop.
