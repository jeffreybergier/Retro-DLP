# Status bar messages

macOS and iOS use the same messages and timer in `source/gui/shared/RDLPLibrary.m`.
Active operations keep their current phase and progress visible until completion.
Once idle, each new message resets the ten-second expiry timer, including identical
text. Ten idle seconds without another message clears the text and progress.
Screen refreshes and navigation do not reset it. Add Video queues locally and
shows `Video added` when idle, preserving another active operation’s status.
Its queued download uses the normal resolver and transfer phases below.

## Download steps

Only steps actually reported by the resolver/downloader appear; cached work may
skip steps. Fast steps can pass quickly because the bar shows the current step.

- Resolving video…
- Reading cookies…
- Configuring client…
- Loading mobile player…
- Requesting metadata…
- Refreshing visitor data…
- Selecting format…
- Downloading player script…
- Solving challenges…
- Reading playlist… (if reported during resolution)
- Format: `{format} · {width}x{height}`
- File: `{filename}`
- Downloading / Downloading video / Downloading audio
- Combining audio and video…
- Finishing download…

During transfer the message includes `{percent}%` when the total is known and
average speed in Mbps when measurable. The bar measures that transfer's bytes.
Unknown progress uses an indeterminate indicator, not a made-up percentage.

Possible final download messages:

- Downloaded · `{size} MiB`
- Download stopped
- Download failed
- Download needs attention (file/database/export recovery warning)

## Playlist activity

| Operation | Working | Success | Failure |
| --- | --- | --- | --- |
| Add | Adding playlist… | Playlist added | Error adding playlist |
| Sync | Syncing playlist… | Playlist synced | Error syncing playlist |
| Load account playlists | Loading playlists… | Playlists loaded | Error loading playlists |

A cancelled playlist operation shows `Playlist operation stopped`.

## Errors and quiet actions

Failures and recovery warnings open a normal native alert with details. The
shared error queue keeps alerts separate from progress and survives status expiry.
User-requested cancellation does not open an error alert.

Cookie import/removal, file deletion, playlist removal, and queue bookkeeping do
not write status messages. Their failures use alerts. There is no `Ready` message.
