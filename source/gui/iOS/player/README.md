# RDLP Player

An isolated, manually reference-counted iOS 5+ player UI and playlist queue. Nothing in the app's
existing player path or build has been changed to use it.

`RDLPPlayerViewController.h` and `RDLPPlayerQueue.h` are the public APIs.
`RDLPPlayerControls` is an internal view. An internal UIView subclass in the
controller supplies the AVPlayerLayer.
There are no third-party runtime dependencies.

## Behavior

- Accepts an externally owned AVPlayer or AVQueuePlayer. Play/pause, seek, and
  fit/fill controls operate on that player; queue navigation goes to the delegate.
- Preserves ALMoviePlayerController's translucent bars, top scrubber, centered
  transport controls, time-label styling, button artwork, and five-second
  auto-hide behavior. Adds Playlist and Audio Only/Show Video buttons at the
  bottom edges. Targets are at least 44 points. The native volume/route view
  appears when there is room, as in AL's adaptive layout.
- Uses manual layout for iPhone portrait/landscape and iPad. Designed for views
  at least 320 points wide, without Auto Layout or nib dependencies.
- While dragging, displays the requested time and seeks once on release.
  Cancellation does not seek; switching queue items invalidates an old drag.
  Scrubbing preserves the existing play/pause state. Indefinite or invalid
  durations disable scrubbing. VoiceOver slider adjustments also seek.
- Observes current-item changes, readiness, buffering, failure, and time jumps.
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

## Connecting the two components

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
library. The host can separately handle the Playlist button and call
`selectItemAtIndex:` followed by `play` when a row is selected. Clear the
delegate and remove the notification observer when their owner is torn down.
Keep the queue alive after dismissing the view if playback should continue;
releasing the queue stops its player.

## Later integration

Compile the three `.m` files with ARC disabled and blocks enabled. Link UIKit,
Foundation, AVFoundation, CoreMedia, CoreGraphics, QuartzCore, and MediaPlayer.
Copy `RDLPPlayer.bundle` intact to the application bundle's resource root.
It contains AL's original normal/retina artwork and its required MIT notice.

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
requests, audio-only presentation, control layout, seek cancellation, queue
changes during a drag, lifecycle handling, artwork loading, and observer
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

## Upstream provenance

Layout and artwork adapted from Anthony Lobianco's ALMoviePlayerController:
https://github.com/lobianco/ALMoviePlayerController/tree/f6c08fccfcf09d060882954bf58975c0d54d912e

The adaptation retains the visual layout and original images while replacing
MPMoviePlayer notifications and transport calls, removing AL's fullscreen/window
management and helper classes, and using this project's manual memory management.
See `RDLPPlayer.bundle/LICENSE-ALMoviePlayerController.txt` for the MIT license.
