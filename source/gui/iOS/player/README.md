# RDLP Player

A self-contained, manually reference-counted iOS 5+ player UI and playlist queue.
The code in this folder depends only on Apple frameworks and its bundled artwork;
it does not import app code or know about the library, download jobs, or database.

`RDLPPlayerViewController.h` and `RDLPPlayerQueue.h` are the playback APIs.
`RDLPPlayerNavigationController` is the native navigation container for presentation.
`RDLPPlayerControls` is an internal view. An internal UIView subclass in the
controller supplies the AVPlayerLayer.
There are no third-party runtime dependencies.

## Behavior

- Accepts an externally owned AVPlayer or AVQueuePlayer. Play/pause, seek, and
  double-tap fit/fill operate on that player; queue navigation goes to the delegate.
- Uses a dedicated UINavigationController's black translucent navigation bar
  and toolbar. The top bar contains headphones on the left, the inherited
  `title` in the center, and Done on the right. Headphones toggles audio-only
  mode and highlights when enabled. Both buttons are native UIBarButtonItems.
  The bottom bar contains previous, the timeline, next, and play/pause, in that
  order. All icon artwork is exported from Font Awesome Free Solid.
  Volume uses the device's hardware buttons.
- UIKit lays out the bars in portrait and landscape and slides both bars with
  its animated hide/show methods. Video extends underneath them without changing
  size. Playing video auto-hides controls after five seconds; tapping toggles
  them. Only the timeline and central status text need manual layout.
- Double-tapping the video toggles aspect fit/fill. Single-tap control visibility
  waits for the double-tap recognizer to fail. Audio-only mode ignores fit/fill.
  The slider is vertically centered and expands to use the available toolbar
  width. Time counters are available to VoiceOver without visible labels.
- The status bar stays hidden throughout the player session, independently of
  the playback controls. Its style is unchanged. On iOS 5/6 the navigation
  container saves and restores the application's previous status-bar visibility;
  on iOS 7+ UIKit handles visibility through the presented controller.
- While dragging, seeks continuously with one seek in flight and only the latest
  requested position retained. The thumb stays at the requested position until
  the final seek completes. Cancellation keeps the last scrubbed position;
  switching queue items invalidates an old drag and its pending completion.
  Scrubbing preserves the existing play/pause state. Indefinite or invalid
  durations disable scrubbing. VoiceOver slider adjustments also seek.
- Observes current-item changes, readiness, failure, and time jumps. No spinner
  is displayed in any playback state.
  A single AVPlayer time observer updates the position four times per second
  while the view is visible and the app is active. No repeating NSTimer.
- Detaches the video layer and removes playback observers when disappearing
  or becoming inactive. It never forces playback to restart on foregrounding.
  Controls stay visible while paused, in audio-only mode, or with VoiceOver
  running (unless explicitly hidden by the caller or user).

## Playlist queue

`RDLPPlayerQueue` owns a stable AVQueuePlayer and an immutable snapshot of the
full ordered list of URLs, including played entries. It supports loading a
playlist at a chosen index, selecting/restarting an entry, previous/next, and
clearing the playlist. Duplicate URLs remain distinct playlist entries.

Only the current and next AVPlayerItems are prepared. AVQueuePlayer advances
automatically, and the queue refills its next item without depending on a view
controller. Selecting an earlier entry creates fresh playback items. Navigation
preserves the player's rate; replacing the playlist starts paused. The final
item pauses at its end and stays selected for replay. Invalid indices and
non-URL entries are rejected without altering playback. Failed media remains
visible as a player/item error instead of being silently skipped.

The queue's `audioOnly` property disables video tracks on current and upcoming
file-based items as they load. Turning it off restores only tracks the queue
disabled. The preference survives playlist replacement. Reflect it in the view
controller's `audioOnly` property to detach the video presentation as well.

Observe `RDLPPlayerQueueDidChangeNotification` to update the view controller's
audio mode and previous/next availability. The notification is synchronous on
the main thread, with the queue as its object. Use `queue.player` for play,
pause, rate, and seek; use the queue's API for all playlist mutations.

Playlist persistence/titles, the playlist table, audio-session configuration,
background capability, remote commands, Now Playing metadata, and progress
persistence remain app integration concerns. Queue navigation, automatic
advancement, and audio-only track handling do not require library integration.

## Downloaded-video integration

[`RDLPDownloadedPlayerViewController`](../RDLPDownloadedPlayerViewController.h),
outside this folder, is the app-specific adapter. All
library, playlist, and download-list Play actions present it through RDLPUIKit
inside a dedicated modal UINavigationController.
Playlist-row taps create a snapshot of all available downloads in playlist
order, select the tapped occurrence, restore its bookmark, then autoplay. Missing
files and unfinished downloads are excluded. Each occurrence uses the same newest
available quality as its library row, with the tapped row's exact job preserved.
Repeated entries stay distinct. All Downloads and individual-video Play actions
still start one-item queues. The adapter updates the navigation title on each item.
Previous/next buttons and remote track commands navigate the queue, preserving
play/pause state. Natural completion advances and restores the following video's
bookmark before continuing; the last item stops without wrapping.
Audio Only updates both the presentation and video tracks; Show Video restores
them without replacing the item. Audio-only mode survives item changes.

The adapter configures the playback audio session, receives iOS 5 remote-control
events, handles interruptions, and publishes Now Playing metadata. It saves
positions while playing or paused, in the foreground or background. Seeks use a
0.5-second debounce; normal playback checkpoints every ten seconds. Pause,
backgrounding, and dismissal flush immediately, and identical positions skip
the database write. Positions in the first or last ten percent save as zero.
The reusable view detaches its video
layer before backgrounding so audio can continue with Home or device lock.
Pushing another screen within that navigation controller keeps playback alive.
Done or dismissing the player session saves progress, stops playback, removes the checkpoint observer,
clears metadata, and deactivates the audio session. A replacement stops the prior
session. Each item transition flushes the outgoing bookmark, switches observers
and metadata, then restores the new item's bookmark. Late notifications and seek
completions from a previous item cannot overwrite the current item's state.

The app Makefile compiles the player classes and adapter and packages `RDLPPlayer.bundle`.
`python3 source/gui/iOS/tests/build_ios_ui_test.py` builds offline device tests of
this adapter after `make app-iOS`, including playlist filtering/order/duplicates,
per-item resume, natural advancement, rapid skips, controls, audio-only tracks,
remote events, interruption handling, and teardown.

## Connecting the two reusable components

A host retains the queue for the playback session, assigns `queue.player` to
the view controller, and forwards its delegate requests. For example, with
retained `queue_` and `playerView_` instance variables:

```objc
queue_ = [[RDLPPlayerQueue alloc] init];
playerView_ = [[RDLPPlayerViewController alloc] init];
playerView_.player = queue_.player;
playerView_.delegate = self;
[[NSNotificationCenter defaultCenter] addObserver:self
    selector:@selector(queueChanged:)
    name:RDLPPlayerQueueDidChangeNotification object:queue_];
if ([queue_ setPlaylist:URLs startingAtIndex:0]) [queue_.player play];
UINavigationController *navigation = [[[RDLPPlayerNavigationController alloc]
    initWithRootViewController:playerView_] autorelease];
[self presentViewController:navigation animated:YES completion:nil];

- (void)queueChanged:(NSNotification *)notification {
    playerView_.canSkipToPreviousItem = queue_.canSkipToPreviousItem;
    playerView_.canSkipToNextItem = queue_.canSkipToNextItem;
    playerView_.audioOnly = queue_.audioOnly;
}

- (void)playerViewControllerDidRequestPreviousItem:(RDLPPlayerViewController *)controller {
    [queue_ skipToPreviousItem];
}

- (void)playerViewControllerDidRequestNextItem:(RDLPPlayerViewController *)controller {
    [queue_ skipToNextItem];
}

- (void)playerViewController:(RDLPPlayerViewController *)controller
       didRequestAudioOnly:(BOOL)audioOnly {
    queue_.audioOnly = audioOnly;
}
```

The standalone queue tests exercise this connection without using the app's
library. A host can supply a separate playlist-selection screen and call
`selectItemAtIndex:` followed by `play` when a row is selected. Clear the
delegate and remove the notification observer when their owner is torn down.
Keep the queue alive after dismissing the view if playback should continue;
releasing the queue stops its player.

## Build integration

Compile the four reusable `.m` files with ARC disabled and blocks enabled. Link UIKit,
Foundation, AVFoundation, CoreMedia, CoreGraphics, QuartzCore, and MediaPlayer.
Copy `RDLPPlayer.bundle` intact to the application bundle's resource root.
It contains Font Awesome icons at 1x, 2x, and 3x and their attribution/license.

The delegate is nonretained; clear it before the owner deallocates. Use the API
on the main thread with AVPlayer's default main-queue observation behavior.
Retain the queue independently of the view controller.

## Validation

From the repository root:

```sh
python3 source/gui/iOS/player/tests/check.py
```

This compiles and links a standalone test app and runs Clang static analysis
for armv7/iOS 5.0 and arm64/iOS 7.0 using the local iPhoneOS 8.4 SDK. It does
not change, build, install, or launch the Retro-DLP app. Output is under
`build/apps/tests/player/{armv7,arm64}/RDLPPlayerTests.app`.

The device test app uses a generated local H.264/AAC fixture. It checks delegate
requests, audio-only presentation, portrait/landscape slider hit testing and
resizing, coalesced seeks, release snap-back, VoiceOver, seek cancellation, queue
changes during a drag or pending seek, lifecycle handling, artwork loading, and observer
teardown. Queue tests additionally check URL snapshots and duplicates, selection,
navigation boundaries, invalid input, UI binding, preparation bounded to two
items, native automatic advancement after releasing the view, audio/video track
states, and pausing at the end of the last item. Results appear on screen and in
`Documents/player-tests.txt`.

Both architectures have compiled, linked, and passed static analysis here.
The device tests have not been executed in this Linux environment. Real iOS 5
validation of rendering, rotation, touch/VoiceOver interaction, and continuous
background playback remains necessary; compilation does not establish those
runtime behaviors. The test app exercises queue advancement without a view,
but does not configure background audio or perform actual device-lock testing.

## Icon provenance

The bundle contains PNG exports of Font Awesome Free Solid 7.2.0 by Fonticons,
Inc.: `headphones`, `backward-fast`, `forward-fast`, `play`, and `pause`.
Source: https://github.com/FortAwesome/Font-Awesome/tree/7.2.0/otfs
See `RDLPPlayer.bundle/LICENSE-Font-Awesome.txt` for attribution and licensing.
Regenerate using `tools/render_icons.py` with Pillow and the upstream
`FA7-Solid-900.otf`. Exports are white glyphs centered on transparent 26-point
canvases. No font registration, app icon helper, or third-party runtime is needed.
