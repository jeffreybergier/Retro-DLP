#import <AVFoundation/AVFoundation.h>

/* Posted on the main thread, with the queue as object, after its playlist,
 * currentIndex, or audioOnly changes. Observe this to update the player UI. */
extern NSString *const RDLPPlayerQueueDidChangeNotification;

/**
 * Small, UI-independent playlist owner for iOS 5+. Retain this object for the
 * playback session, independently of any RDLPPlayerViewController.
 *
 * The playlist contains NSURL objects (normally downloaded file URLs). Duplicate
 * URLs are separate entries. Only the current and next AVPlayerItems are loaded.
 * AVQueuePlayer advances automatically; the last item pauses at its end and
 * stays selected, allowing the view controller's Play button to replay it.
 * Errors remain visible on the player/item; failed entries are not silently
 * skipped. All calls and notifications use the main thread.
 */
@interface RDLPPlayerQueue : NSObject

/** Stable player instance. Use play, pause, rate, and seek on this object.
 * Change its queue only through RDLPPlayerQueue; do not directly insert/remove
 * items, replace currentItem, or change actionAtItemEnd. */
@property(nonatomic,readonly,retain) AVQueuePlayer *player;

/** Immutable snapshot of the full ordered URL list, including played entries. */
@property(nonatomic,readonly,copy) NSArray *playlist;
@property(nonatomic,readonly) NSUInteger currentIndex; /* NSNotFound when empty. */
@property(nonatomic,readonly) BOOL canSkipToPreviousItem;
@property(nonatomic,readonly) BOOL canSkipToNextItem;

/** Default NO. Disables video tracks on current and upcoming file-based items
 * as their tracks load, without pausing audio or seeking. Restores only the
 * video tracks this queue disabled when switched off. Reflect this value in
 * RDLPPlayerViewController.audioOnly to detach its video presentation too. */
@property(nonatomic,assign,getter=isAudioOnly) BOOL audioOnly;

/** Replaces the playlist and prepares the chosen entry, paused at its start.
 * Empty/nil URLs clear the queue (index is ignored). Returns NO for an invalid
 * index or a non-URL entry, leaving the existing playlist and playback intact.
 * Does not check file existence or pre-load the entire playlist. */
- (BOOL)setPlaylist:(NSArray *)URLs startingAtIndex:(NSUInteger)index;

/** Selects/restarts an entry at time zero, preserving the player's rate.
 * Returns NO for an out-of-range index without changing anything. */
- (BOOL)selectItemAtIndex:(NSUInteger)index;

/** Preserve play/pause state; return NO at the corresponding playlist edge.
 * Previous always selects the preceding entry, not the current item's start. */
- (BOOL)skipToPreviousItem;
- (BOOL)skipToNextItem;

/** Stops playback, releases loaded items, and clears the playlist. */
- (void)removeAllItems;
@end
