# macOS and iOS status review

Reviewed 2026-09-15 at commit `73fc7ab`. This records the original source review before implementation. The subsequent user-approved design focuses on download steps and simple playlist activity, with shared ten-second expiry and separate error alerts; see [the current app documentation](cocoa-apps.md). The inventory below describes the old behavior.

## Main findings

The main problem is that **one mutable string represents activity, results, validation, and errors**. Shortening that string alone will not make feedback reliable.

1. Messages overwrite each other without priority or ownership. A download result can be replaced by `Starting…` roughly 0.1 seconds later.
2. macOS retains the latest message indefinitely. iOS clears idle messages after 10 seconds, including errors, using a separate timer in each view.
3. Progress text describes the current transfer, while the bar measures processed queue attempts, including failed and stopped attempts. iOS also displays a half-filled bar when progress is unknown.
4. Startup and removal instructions still refer to queue pause/resume controls that the current interface does not expose. Both app delegates automatically start downloads.
5. User-facing words also act as program state: changing `Ready`, `Cancelled`, or `Imported` can change behavior unless the corresponding comparisons are updated.

## 1. Where status appears

| Surface | Current behavior | Source |
| --- | --- | --- |
| Shared model | `status_` stores only the latest string. `showStatus:` posts `RDLPLibraryDidChange`; it carries no event ID, severity, action, timestamp, or operation identity. | [RDLPLibrary.m](../source/apps/shared/RDLPLibrary.m), `showStatus:` |
| macOS window footer | One line in a 32-point bottom strip, outside the panes. Tail truncation; full text in a tooltip. No expiry. | [RDLPLibraryWindowController.m](../source/apps/macOS/RDLPLibraryWindowController.m), `loadWindow` / `updateControls` |
| macOS progress | Visible only while the queue-run flag is active. Processed attempts / total attempts. Counts are in a tooltip. Metadata work alone has no bar. | Same controller, `updateControls` |
| macOS item status | Primarily an icon, with spoken status and a tooltip combining status and stored error. The selected queue error can be opened in an alert. | Same controller, table cell / tooltip methods and `showQueueError:`; [RDLPLibraryViews.m](../source/apps/macOS/RDLPLibraryViews.m) |
| iOS Playlists home | Toolbar always visible with Queue button. Single-line status, width limited to view width minus 80 points. | [RDLPPlaylistsViewController.m](../source/apps/iOS/RDLPPlaylistsViewController.m) |
| iOS Playlist / All Downloads | Same status view; entire toolbar hides for empty status, exact `Ready`, or an expired label, even if progress is active. | [RDLPVideoListViewController.m](../source/apps/iOS/RDLPVideoListViewController.m), `shouldHideToolbar` |
| iOS Queue | Same status view, without a Queue button. Toolbar stays visible during busy work or an active queue run even without text. | [RDLPQueueViewController.m](../source/apps/iOS/RDLPQueueViewController.m), `shouldHideToolbar` |
| iOS status component | Bold 15-point idle / 13-point active label. Active means queue-run flag OR busy. Idle text expires after 10 seconds; active text does not. Track is at most 100 points wide. | [RDLPStatusBarView.m](../source/apps/iOS/RDLPStatusBarView.m) |
| iOS item status | Icons plus accessibility text in video lists. Queue details show status, quality, and raw stored error. Retry dialogs include a reason, raw error, and restart explanation. | Video-list / queue controllers and [RDLPLibrarySections.m](../source/apps/iOS/RDLPLibrarySections.m) |
| iOS Settings | No status footer or toolbar. Cookie import shows an alert using the shared status. Cookie removal updates shared status but does not display a result locally. | [RDLPSettingsViewController.m](../source/apps/iOS/RDLPSettingsViewController.m) |
| Older iOS generic controller | Still compiled: three-line footer, queue fraction, and visible count summary; a separate home-toolbar path also exists. The current app root and primary navigation use the dedicated controllers above. | [RDLPLibraryViewController.m](../source/apps/iOS/RDLPLibraryViewController.m) and [RDLPLibraryActions.m](../source/apps/iOS/RDLPLibraryActions.m) |

These are in-app status displays and alerts. The change notifications are internal observer events, not system notification banners.

## 2. Shared status text inventory

The following tables cover the app-owned global status literals and formatting templates. Placeholders such as `{count}` describe runtime substitutions. Proposals are for review, not implemented copy. Additional instructions belong in a detail view or the relevant dialog.

### Idle, queue, and input

Source: [RDLPLibrary.m](../source/apps/shared/RDLPLibrary.m).

| ID | Trigger | Current text | Proposed short text / behavior |
| --- | --- | --- | --- |
| S01 | Initial value; `startDownloads` | `Ready` | Empty idle status. Represent idle explicitly. |
| S02 | Successful startup reconciliation | `Ready. Resume Queue to start pending downloads.` | Remove. Both app delegates call `startDownloads`. |
| S03 | `setPaused:YES` | `Queue paused. Active transfers stop and can be retried.` | `Stopping download…` while cancellation is pending; `Downloads paused` once stopped. Do not imply resumable transfer bytes. |
| S04 | `setPaused:NO` | `Queue resumed` | Derive actual activity; show `Starting download…` only when a job starts. |
| S05 | Any command starts | `Starting…` | `Starting download…`, `Syncing playlist…`, or `Loading playlists…` according to operation. |
| S06 | Empty playlist input | `Enter a playlist URL or ID.` | Keep, next to the input. |
| S07 | Enqueue without playlist key | `Select a synced playlist first.` | `Select a synced playlist` |
| S08 | Invalid format | `Enter an exact format such as 18 or 136+140.` | `Enter a format ID, such as 18 or 136+140.` in the format dialog. |
| S09 | Enqueue succeeds | `Added missing downloads. Existing jobs can be retried in Queue.` | `Queued 1 video` / `Queued {count} videos`; `No new downloads` if none inserted. Requires an actual inserted count. |
| S10 | Claiming next job fails | `Could not claim a download job.` | `Couldn’t start download` with database details available separately. |

### File and playlist removal

Source: [RDLPLibrary.m](../source/apps/shared/RDLPLibrary.m).

| ID | Trigger | Current text | Proposed short text / behavior |
| --- | --- | --- | --- |
| S11 | Remove download while busy | `Pause the queue and wait for the current operation before removing files.` | `Wait for the current operation to finish` in action feedback. Remove the unavailable Pause instruction. |
| S12 | Download removed | `Download removed; playlist membership retained.` | `Download deleted`. Keep the retained-membership explanation in deletion confirmation. |
| S13 | Remove playlist while busy | `Wait for the current operation before removing a playlist.` | `Wait for the current operation to finish` |
| S14 | Playlist removed | `Playlist removed.` | `Playlist removed` |

### Cookies and app setup

Source: [RDLPLibrary.m](../source/apps/shared/RDLPLibrary.m).

| ID | Trigger | Current text | Proposed short text / behavior |
| --- | --- | --- | --- |
| S15 | Import while busy | `Wait for the current operation before replacing cookies.` | `Wait for the current operation to finish` |
| S16 | Unreadable, empty, or oversized import | `Choose a Netscape cookies.txt file smaller than 4 MB.` | Separate `Couldn’t read cookie file`, `Cookie file is empty`, and `Cookie file is too large`. Explain the format and limit in import UI. |
| S17 | Write / permission failure | `Could not save cookies.` | `Couldn’t save cookies` |
| S18 | Import succeeds | `Cookies imported. Load My Playlists to discover your account library.` | `Cookies imported`. If loading follows immediately, transition to `Loading playlists…`. |
| S19 | Remove cookies while busy | `Wait for the current operation before removing cookies.` | `Wait for the current operation to finish` |
| S20 | Cookie removal fails | `Could not remove cookies.` | `Couldn’t remove cookies` |
| S21 | Cookie removal succeeds | `Cookies removed.` | `Cookies removed` |
| S22 | Worker lacks bundled CA resource | `The application is missing its CA certificate bundle.` | `App setup is incomplete`; explain the missing certificate resource in details. |

S16 currently allows exactly 4 × 1024 × 1024 bytes, despite saying “smaller than 4 MB.” Import checks readability/size and saves the file; it does not establish that YouTube accepts its cookies. `Cookies imported` must not become `Signed in`.

### Activity and byte progress

Source: callbacks and `progress:completed:expected:` in [RDLPLibrary.m](../source/apps/shared/RDLPLibrary.m).

| ID | Current text/template | Proposed short text / behavior |
| --- | --- | --- |
| P01 | `Loading YouTube metadata` | `Preparing download…`, `Syncing playlist…`, or `Loading playlists…` based on command. Every resolver event currently maps to this one phrase. |
| P02 | `Downloading audio` | `Downloading audio…` |
| P03 | `Downloading video` | `Downloading video…` (used for both video-only and combined audio/video events). |
| P04 | `Muxing MP4` | `Combining audio and video…` |
| P05 | `Cleaning up` | `Finishing download…` |
| P06 | `Downloading` | `Downloading…` (fallback for unknown download event type). |
| P07 | `{phase}: {percent}% ({megabytes} MB)` | `{phase} · {percent}%`; put transferred size in details. Percent belongs to that transfer phase, not the whole job. |
| P08 | `{phase}: {megabytes} MB` | `{phase} · {size}` only when useful; unknown total must not imply a percentage. |

Without either byte value, the phase is shown alone. Percent is rounded to a whole number, size to one decimal; bytes are divided by 1,048,576 but labeled MB. Use consistent units in any retained detailed display. Updates are throttled to at most four per second, including phase changes. A fast phase can therefore be skipped. No title or playlist identity accompanies these global messages.

### Service results

Source: [rdapp_service.c](../source/apps/shared/rdapp_service.c).

| ID | Trigger | Current text/template | Proposed short text / behavior |
| --- | --- | --- | --- |
| R01 | Playlist sync succeeds | `Synced {title} ({count} entries)` | `Playlist synced · {count} videos`; keep title in details. Use singular for one. |
| R02 | Account discovery succeeds | `Found {count} playlists. Select a playlist and Sync, or Sync All.` | `Found 1 playlist` / `Found {count} playlists` / `No playlists found` |
| R03 | Download succeeds | `Download complete ({format})` | `Download complete`; put title and quality in details. |
| R04 | File published, database update fails | `File downloaded, but its database update failed. Reopen the library to recover it.` | `Download needs recovery`; retain the reopen instruction in a persistent detail message. |
| R05 | File recorded, playlist export fails | `Downloaded. VLC playlist export failed: {error}. Sync the playlist to retry export.` | `Downloaded; playlist export failed`; retain error and Sync recovery action in details. |
| R06 | Publishing final file fails | `Cannot publish downloaded file: {system error}` | `Couldn’t save download`; distinguish an existing destination in details. |

R04 and R05 return a successful service code with warning text. A replacement event model must distinguish success, partial success, and failure explicitly. R04 may also leave the stored job in `running` while the bridge counts its attempt as processed, so it needs recovery handling as well as clearer wording.

## 3. Item states and secondary status text

Source: [RDLPDownloadPolicy.m](../source/apps/shared/RDLPDownloadPolicy.m), [RDLPLibrarySections.m](../source/apps/iOS/RDLPLibrarySections.m), and the platform renderers.

| Current | Meaning / surface | Proposed |
| --- | --- | --- |
| `Downloaded` | Complete job with an existing file; item icon/accessibility/details | Keep |
| `Downloading` | Stored `running` job, including preparation and finalization | Keep as broad row status; show precise activity separately |
| `Queued` | Pending job | Keep |
| `Failed` | Failed job | Keep; add readable reason in details |
| `Interrupted` | Previously running job recovered after relaunch | Keep; explain `Retry starts from the beginning.` |
| `Cancelled` | Shared policy and macOS; also iOS playlist accessibility | `Stopped` consistently, matching current iOS actions |
| `Stopped` | iOS Queue remaps `Cancelled` | Keep and share the mapping |
| `File missing` | Complete file absent, or reconciled removed job with error | Keep |
| `Not downloaded` | No job or ordinary removed job | Keep |
| `Not synced` | iOS playlist metadata absent | Keep |
| `{count} videos` | iOS synced playlist subtitle | `1 video` / `{count} videos` |
| `Not Imported`, `Imported`, `Unavailable` | Cookie model states, used to select/enable controls; not a dedicated status label in current Settings | Keep typed states internally; if displayed, use `Not imported`, `Imported`, `Unavailable` |
| `Low ({format})`, `Med ({format})`, `High ({format})`, `Custom ({format})` | Quality accompanies item details and results | `Low`, `Medium`, `High`, `Custom` in compact UI; preserve exact format in details/custom input |

Do not shorten by replacing status names indiscriminately: icons, retry explanations, accessibility hints, and cookie actions compare these display strings directly. Map typed state to words once. Representative playlist status also intentionally prefers any playable quality over an active/failed alternative; it describes availability of the video, not necessarily its newest attempt.

### Count and detail templates

| Current template | Surface | Proposed |
| --- | --- | --- |
| `{processed} of {total} processed · {failed} failed · {cancelled} stopped` | macOS progress tooltip | `Processed {processed} of {total}` plus nonzero failure/stop counts |
| `{processed} processed of {total}; {failed} failed; {cancelled} stopped` | iOS progress accessibility; older controller also displays it | `Processed {processed} of {total}. {failed} failed. {stopped} stopped.` Omit zero outcomes. |
| `In progress` | iOS unknown-progress accessibility | Name the operation, such as `Syncing playlist` |
| `{status}: {error}` | macOS item tooltip | Status and a short reason; full diagnostic in details |
| `{status} · {quality}\n{error}` | iOS job details / older job rows | Status and quality; separate user explanation from diagnostic |
| `{title}, {detail}, {status}` | iOS item accessibility | Omit empty detail and its extra punctuation |
| `Download in progress` | iOS accessibility hint for both queued and downloading videos | `Waiting to download` for queued; `Download in progress` for running |

## 4. Errors that enter the same status channel

There is no finite, closed list of all possible rendered status strings. The service copies `rdlp_error.message`, or the literal `RDLP_ERROR_*` name if empty, into status. Storage also passes SQLite messages and `strerror(errno)` through. Titles, counts, paths, and transport diagnostics vary at runtime.

The app-owned store literals below are the complete fixed-text store inventory relevant to status/errors. Some are defensive failures rather than normal user flows. Sources: [rdapp_store.c](../source/apps/shared/rdapp_store.c), [rdapp_service.c](../source/apps/shared/rdapp_service.c).

| Current text | Proposed user summary / location |
| --- | --- |
| `Cannot open library database` | `Couldn’t open library`; startup alert |
| `Too many result columns` | `Couldn’t read library`; diagnostic in details |
| `Result processing failed` | `Couldn’t read library`; diagnostic in details |
| `Invalid playlist ID` | `Invalid playlist ID`; input feedback |
| `Invalid video ID in playlist` | `Playlist contains invalid video data` |
| `Cancel queued jobs and remove downloaded files before removing this playlist.` | `Playlist still has downloads`; details explain stopping queued work and deleting files |
| `Playlist does not exist` | `Playlist no longer exists` |
| `Cannot create playlist directory` | `Couldn’t create playlist folder` |
| `Playlist path is too long` | `Playlist path is too long`; details |
| `Could not write VLC playlist` | `Couldn’t export playlist` |
| `Job does not exist` | `Download no longer exists` |
| `Cancel the active download before removing it` | `Stop the download before deleting it` |
| `Download path is too long` | Keep in details under `Couldn’t save download` |
| `Staging path is too long` | Keep in details under `Couldn’t save download` |
| `Interrupted. Retry restarts the download.` | `Download interrupted`; `Retry starts from the beginning.` in details |
| `Cancelled` | `Stopped`; do not repeat as an error beneath a stopped status |
| `File is missing. Retry to download it again.` | `File missing`; a Retry action supplies the next step |

### Lower-level wording families

These examples illustrate the additional library-owned vocabulary that can escape into app status. They are not an exhaustive catalog of every core diagnostic or a claim that every defensive core error is reachable through normal app inputs.

| Family | Current examples | Proposed app summary |
| --- | --- | --- |
| Network | `network request failed`, `transport request timed out`, `HTTP request failed`, `media download returned an HTTP error`, libcurl diagnostic strings | `Couldn’t connect to YouTube`, `Request timed out`, or operation-specific download failure; use actual error code/host to choose |
| Unavailable content/quality | `video unavailable`, `requested format is not available`, `no direct progressive MP4 available` | `Video unavailable` / `Quality unavailable` |
| Invalid input/response | `invalid YouTube video ID`, `invalid or unsupported YouTube playlist URL`, `invalid format expression`, `invalid YouTube response`, `response exceeds its size limit` | Input-specific explanation, or `Couldn’t read YouTube’s response` |
| Cookies/access | `invalid or unreadable Netscape cookie file`, `YouTube authentication cookies are missing, expired, or invalid`, `PO token required` | `Couldn’t read cookies`, `Import fresh YouTube cookies`, or `YouTube requires additional verification`; do not label every access failure as a cookie problem |
| App resources | `CA certificate bundle is missing beside the executable`, `CA certificate bundle unavailable`, `EJS assets missing; run: retro-dlp assets install`, `EJS assets are missing`, `EJS assets are corrupt`, `EJS asset directory must be absolute` | `App setup is incomplete`; app-appropriate recovery in details, without CLI commands in the bar |
| Resource download/storage | `EJS asset download failed`, `EJS asset download returned an HTTP error`, `EJS asset storage error`, `EJS asset operation failed` | `Couldn’t prepare download`; retain cause in details |
| YouTube player processing | `JavaScript challenge resolution failed`, `EJS execution deadline exceeded`, `EJS execution failed`, `EJS returned an invalid result`, `EJS signature transformation failed`, `EJS n transformation failed` | `Couldn’t prepare this video`; diagnostic in details |
| File/media | `destination or partial download already exists`, `download storage error`, `download response is not an MP4 file`, `MP4 muxing failed`, `mux succeeded but source-track cleanup failed` | `Download file already exists`, `Couldn’t save download`, `Invalid video file`, `Couldn’t combine audio and video`, `Couldn’t finish download` |
| Cancellation | `operation cancelled` | `Download stopped` or operation-specific cancellation; informational when requested by user |
| Internal/fallback | `out of memory`, `unknown error`, `RDLP_ERROR_*`, SQLite/system diagnostics | Operation-specific failure with complete diagnostics retained |

Error sources: [yt_resolver.c](../source/shared/yt_resolver.c), `yt_status_string`; [retrodlp.c](../source/shared/retrodlp.c), `finish_session_status` / `rdlp_error_name`; [retrodlp_download.c](../source/shared/retrodlp_download.c), `set_error` callers; [retrodlp_assets.c](../source/shared/retrodlp_assets.c), `asset_status_message` / `publish_error` callers. The cleanup error occurs before the app publishes the final file, so “Download complete” would be misleading for that case.

## 5. Related alerts and recovery instructions

These are action feedback adjacent to the status system, not the full inventory of menus and pre-action confirmation copy.

| Current text/template | Location | Proposed treatment |
| --- | --- | --- |
| `Could not open the RetroDLP library. Check permissions and free space in Documents and Application Support.` | macOS app delegate | `Couldn’t open library` title; retain recovery detail |
| `Cannot open the RetroDLP library. Check available storage and restart the app.` | iOS app delegate | Same title; retain platform recovery detail |
| `Could not reveal this file in Finder. Check that the download exists.` | macOS `RDLPAppKit` | `Couldn’t show file in Finder`; detail explains missing-file check |
| `Could not open this file in VLC.` | macOS `RDLPAppKit` | `Couldn’t open video in VLC` |
| `Could not open this file in its default app. Check that the download exists and choose an app in Finder’s Open With settings.` | macOS `RDLPAppKit` | `Couldn’t open video`; retain recovery detail |
| `Could not open the cookie export guide in your browser.` | macOS window controller | `Couldn’t open cookie guide` |
| `The downloaded file is missing. Retry its download from Queue.` | iOS `RDLPUIKit` | `File missing`; offer a reachable Retry or Queue action |
| `Finish the current operation or dialog before importing cookies.` | Three iOS cookie-import implementations | Distinguish `Wait for the current operation to finish` from `Close the current dialog first` |
| `Copy cookies.txt into RetroDLP with iTunes File Sharing, or open your exported text file in RetroDLP. Then use Load My Playlists again.` | iOS Playlists and older actions | `Import a cookies.txt file to load your playlists.` Keep transfer methods in import help. |
| Same import instructions ending `Then use Import Cookies again.` | iOS Settings | Same shared import help; use the initiating action for recovery |
| `The previous download failed.` / `The previous download was interrupted.` / `The previous download was stopped.` / `The downloaded file is missing.` | iOS retry dialog | `Download failed` / `Download interrupted` / `Download stopped` / `File missing` |
| `{reason}\n\n{raw error}\n\nRetry downloads this video from the beginning at the same quality: {quality}.` | iOS retry dialog (error segment optional) | Short reason + `Download again from the beginning at {quality}?`; diagnostic available separately |
| `Retry restarts this quality from the beginning. Other queued downloads continue.` | iOS Stop confirmation | `Retry starts from the beginning. Other downloads continue.` |
| `Retrying this job restarts the transfer; it does not resume from where it stopped.` | macOS Cancel confirmation | `Retry starts from the beginning.` |

The iOS generic message alert always uses title `RetroDLP` and button `OK`. macOS puts the whole message in the alert heading. Both would benefit from separate concise titles and detail text.

## 6. Behavioral issues to fix

### A. Results disappear behind unrelated activity

`finished:` publishes the result, then schedules `startNext` after 0.1 seconds. The next command publishes `Starting…`. Successes, sync errors, and partial-success warnings can be effectively unreadable in a batch. Byte progress can also replace validation/action feedback during a download. Failed download diagnostics survive on the job; sync/discovery failures and export warnings have no equivalent retained event record.

**Proposal:** separate ongoing activity from short-lived notices and retained problems. Keep important failures/recovery warnings reachable after the next command starts. Add an end-of-run summary, for example `3 downloaded · 2 failed`, based on outcomes, not just the last job's message.

### B. iOS expiry uses text equality instead of event identity

`RDLPStatusBarView` remembers the last string to prevent refreshes resurrecting expired text. Consequently, repeating an idle action that produces exactly the same message may never show the second result. Conversely, a newly created screen has no previous string/timer and can redisplay an old shared status for another 10 seconds. A loaded but hidden screen can consume the dwell time before the user sees it.

`Ready` also deliberately preserves the previous label in the component. It can leave an old `Downloading` label after work stops, while Playlist/All Downloads hide their toolbar on that same `Ready` value.

**Proposal:** give each notice an ID and shared expiry time. A new action gets a new ID even if its words match. Let explicit activity state control busy visibility. Routine notices can use a shared, proposed 5-second lifetime; failures and recovery instructions remain reachable until resolved/dismissed.

### C. The progress display mixes different measurements

The text percentage comes from the current audio/video transfer. The bar uses `processed / (processed + queued + running)` for the queue run. Failed and stopped attempts count as processed; newly added jobs can lower the fraction; cancelling queued jobs removes them from the denominator without incrementing processed/stopped run counters. This is not a fixed batch or a count of successful downloads.

iOS uses exactly 50% for busy work without a queue total. A paused queue keeps `queueRun_` true, so it can look active indefinitely. macOS and iOS disagree on whether metadata work gets a progress indicator.

**Proposal:** use a spinner for unknown progress. Make the bar's scope explicit: current-transfer percentage or queue attempts, with matching text. If keeping queue progress, say `Processed 3 of 5` and show success/failure/stop outcomes separately. Preserve run membership and outcome accounting if a stable batch summary is required. Do not label processed attempts as downloaded videos.

### D. Pause and startup feedback contradict current operation

The initializer says to Resume Queue; both production delegates call `startDownloads`. Current macOS menus have removed global pause/resume. iOS pauses on backgrounding and calls `startDownloads` on foregrounding. Pause requests cancellation of the active download; the job becomes cancelled and must be retried from the beginning. Foregrounding starts queued work but does not automatically retry that stopped job.

**Proposal:** remove obsolete startup/control instructions. Distinguish stopping an item, pausing scheduling, and retrying from the beginning. Keep lifecycle cancellation semantics explicit in item details; changing those semantics is a separate product decision from shortening text.

### E. Cookie alerts can show the wrong result

In iOS import-and-discover flows, import publishes success, discovery immediately publishes `Starting…`, and then `showMessage:[library_ status]` reads that overwritten value. The alert can therefore say only `Starting…`. The logic is duplicated across Playlists, Settings, and the older action controller. Settings cookie removal does not present local success/failure feedback because Settings hides the global status surface.

**Proposal:** return the specific action result to its caller. Show import errors locally; successful import-and-load can show ongoing playlist activity. Give Settings its own concise action feedback and share the import handling.

### F. Some operations have no reliable failure or no-op feedback

`retryJob:` ignores reconciliation failure and gives no message when retry fails. `cancelJob:` ignores the queued-cancel store result. `rows:` changes `status_` directly on error without posting a notification, potentially during a UI refresh. Enqueue reports “Added” even when `INSERT OR IGNORE` adds nothing. Sync All with no work and duplicate sync/discovery requests return without feedback.

**Proposal:** return structured success/failure/no-change results and affected counts. Avoid mutating status from read methods. A duplicate request can simply retain the existing activity indication; an empty user-triggered action should explain `No playlists to sync` or `No new downloads` when the UI allows it.

### G. A wording edit can accidentally alter control behavior

State checks depend on English display text throughout both UIs. Resolver callbacks discard event type, while download phases index a string array by enum ordinal. Every progress update also posts the same broad library-change notification used to rebuild lists and controls.

**Proposal:** make rendering consume a typed state snapshot. Use explicit enum-to-label mappings. Separate status/progress updates from structural library changes so transfer ticks do not trigger full data reloads. Keep accessibility output synchronized without announcing every byte update.

## 7. Proposed implementation shape

Use the existing shared bridge as the owner of presentation state; both platform views should render the same meaning.

| Shared information | Purpose |
| --- | --- |
| Activity: operation ID/type, item identity, phase, busy/stopping/paused state | Answers “What is happening?” without parsing text |
| Progress: scope, completed, total, whether total is known | Supplies a real fraction or an indeterminate indicator |
| Notice: unique ID, kind, short text, detail, creation/expiry time | Makes repeat actions and lifetime consistent across screens |
| Problem: error code, operation/item, readable reason, diagnostic, recovery action | Keeps actionable failures available after progress continues |
| Result: success/partial success/failure/no change, affected count | Supports accurate acknowledgements and final summaries |

Suggested display rules:

1. Use short, sentence-case phrases. Ellipses mean ongoing work; compact results do not need a final period.
2. Keep one operation/result in the compact message. Put title, exact quality, transferred bytes, and technical diagnostics in details.
3. Prefer 2–5 words for ordinary activity/results, but measure fit at the actual font and width instead of enforcing an arbitrary character limit.
4. A failure needing recovery must remain accessible even after its compact notice expires or another job starts.
5. A brief acknowledgement may temporarily occupy the status label, after which it returns to current activity. Unresolved problems need a persistent affordance so neither they nor progress silently erase each other.
6. Use `Stop` / `Stopped` for download actions/states; reserve `Cancel` for dismissing a dialog. Preserve restart-from-beginning information where the user chooses Retry.

Suggested implementation order:

1. Introduce typed state/results and centralized copy while preserving current rendering APIs through an adapter.
2. Fix result ownership, error retention, import feedback, and affected counts.
3. Align lifetime/visibility and progress semantics between platforms.
4. Apply approved wording from the tables, update text-dependent consumers, then remove redundant rendering/import paths where appropriate.

## 8. Validation needed for implementation

Existing tests already encode some behaviors this proposal changes: [ios_ui_test.m](../source/apps/tests/ios_ui_test.m) asserts the 50% unknown-progress track, hiding `Ready` even during active work, preserving previous activity on `Ready`, and 10-second expiry. [mac_toolbar_test.m](../source/apps/tests/mac_toolbar_test.m) asserts queue-only progress, visibility while paused, automatic startup, and processed attempt counters. Update these expectations deliberately.

Focused scenarios:

- Empty launch and launch with pending/interrupted jobs; no obsolete Resume instruction.
- Sync/discovery/download phase changes, known and unknown totals, long titles, and narrow iOS layouts.
- Two successive identical actions; repeated refreshes; navigating to a new screen after notice expiry.
- Failure followed immediately by the next job; partial-success export/recovery warnings remain available.
- Mixed success/failure/stopped queue, cancelling queued jobs, adding jobs mid-run, and final summary.
- Background/foreground during a download, including the stopped job's retry behavior.
- Cookie import, import-and-load, unreadable/empty/oversized input, and removal feedback inside Settings.
- Accessibility state names, progress meaning, and recovery access on both platforms.

This review made only a documentation change. Validation here consisted of tracing producers, consumers, navigation, and existing test expectations; no build or runtime test results are claimed.
