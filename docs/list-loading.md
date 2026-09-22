# Cocoa list loading

## Findings and changes

The previous iOS section builder loaded all entries and jobs on each refresh,
then scanned the job array for every playlist entry. This also checked file
existence and formatted strings for offscreen rows. The macOS refresh path loaded
all playlists, entries, and historical jobs, built another filtered queue array,
and scanned those arrays to restore selection and populate sidebar children.
Queue progress and individual job actions also read the entire job history.

Both frontends now use `RDLPLibraryRows`, an immutable `NSArray` subclass:

- Construction runs a count query. `count` and `copy` do not load row payloads.
- `objectAtIndex:` fetches one record and caches at most 128 records. UIKit cell
  requests and AppKit cell data-source callbacks drive loading. iOS row formatting
  has its own bounded cache. Selected-item actions may also request a single row.
- Sequential entry/job access seeks after the previous position/ID through an
  index. A random jump uses an indexed ordering with `LIMIT`/`OFFSET`; SQLite
  still walks the preceding index entries for that jump.
- Each list owns a read-only SQLite connection and transaction. WAL mode lets
  background writes commit while a displayed list retains consistent counts,
  ordering, and identities. Refresh replaces the list snapshot.
- Playlist entries retain duplicate memberships and their original positions.
  Representative download selection reads only that video's qualities.
- Queue filtering, ordering, counts, and selection-by-ID happen in SQL.
  Deliberate deletions stay hidden; missing-file jobs remain visible.
- AppKit's outline asks for child identities separately from cell values. These
  requests load IDs only; titles and video counts are fetched for displayed cells.
- Row heights and swipe eligibility do not fetch offscreen payloads. Delete and
  retry actions recheck the captured identity before changing the database.

Startup file reconciliation and XSPF/M3U8 exports now run on the existing background
worker before queued downloads. Retrying a job checks just its own file instead
of reconciling/exporting the entire library. Cancellation uses a separate short-held
lock, so backgrounding and shutdown do not wait for a sync/export to release the
database lock.

## Bulk operations and limits

Menu validation uses database counts instead of constructing download/sync plans.
Missing-download validation uses stored states; external file removal is reflected
by startup reconciliation, while individual video actions still check the file.
An explicitly requested bulk plan queries deduplicated eligible entries and checks
completed files. Its memory use includes the requested confirmation plan; temporary
row objects are drained during iteration.

Counts may still traverse matching index entries. Creating the new indexes on an
existing database is a one-time startup cost. Visible cells still perform bounded,
synchronous database and file reads. Explicit write actions can still wait for the
worker's store lock, and deleting a file can rewrite its playlist export. These
changes address list construction and read contention, not all possible I/O pauses.
Long-lived list snapshots retain WAL history until refreshed or released; controllers
should release old sources rather than accumulate them.

## Validation

`python3 source/gui/shared/tests/test_store.py` exercises counts, paging, indexed seeks,
duplicate memberships, queue filters, exact lookups, bulk eligibility, selected-job
recovery, and readers concurrent with committed and uncommitted writes. A 50,000-row
fixture verifies bounded returned payloads and checks actual SQLite VM work to catch
an accidental full scan during sequential scrolling.

`test_service.py` covers the real offline store/service workflow. Both production
apps and native regression-test packages build for their supported architectures.
Native tests additionally check lazy counts/copies, row caching, and selection
lookups. Run those test apps and profile scrolling on actual iOS/macOS hardware to
measure frame latency; cross-compilation and portable tests do not establish it.
