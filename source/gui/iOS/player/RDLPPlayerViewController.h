#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@class RDLPPlayerViewController;
@protocol RDLPPlayerViewControllerDelegate;

/**
 * iOS 5+ player UI with native navigation and toolbars.
 * The core properties follow AVPlayerViewController's naming and semantics.
 * Use init, assign player, and embed in RDLPPlayerNavigationController for
 * native bars and a status bar that stays hidden throughout the player session.
 * Present that navigation controller modally using normal UIViewController APIs.
 * All properties and delegate callbacks are used on the main thread.
 * Set the inherited title property to the current video's display title.
 *
 * A persistent playback owner (such as RDLPPlayerQueue) retains the player
 * independently and manages its playlist and audio-only track selection.
 * Audio-session setup, remote controls, Now Playing metadata, and saved
 * progress remain app responsibilities. This view controller
 * supplies video presentation, play/pause, scrubbing, and double-tap fit/fill.
 * Setting player, presenting, or dismissing this controller does not itself
 * start or stop playback. Dismissal detaches video presentation.
 */
@interface RDLPPlayerViewController : UIViewController

/* AVPlayerViewController-compatible core. */

/**
 * Default nil. Accepts AVPlayer or its AVQueuePlayer subclass.
 * Observes currentItem and playback state to keep the controls current.
 * Assigning nil detaches presentation and disables playback controls without
 * pausing the old player. Play, pause, and seek remain AVPlayer operations;
 * this controller does not duplicate those methods in its public API.
 */
@property(nonatomic,retain) AVPlayer *player;

/** Default YES. NO hides all playback chrome; YES permits auto-hiding controls. */
@property(nonatomic,assign) BOOL showsPlaybackControls;

/**
 * Default AVLayerVideoGravityResizeAspect. Accepts the AVLayerVideoGravity
 * string constants, including ResizeAspectFill and Resize. NSString keeps
 * this declaration compatible with the iOS 5 SDK.
 */
@property(nonatomic,copy) NSString *videoGravity;

/**
 * Custom delegate for Retro-DLP actions, not AVPlayerViewControllerDelegate.
 * Nonretained under this app's manual memory management. The owner must clear
 * this property before the delegate is deallocated. Default nil.
 */
@property(nonatomic,assign) id<RDLPPlayerViewControllerDelegate> delegate;

/* Retro-DLP extensions. These properties reflect the playback owner's state. */

/**
 * Default NO. The current session's audio-only mode, supplied by its owner.
 * YES detaches video presentation and shows an audio-only placeholder while
 * retaining transport controls. NO allows video presentation while visible
 * and in the foreground. Neither value changes the player's time or rate.
 *
 * This is presentation state: the owner must also disable/enable video tracks
 * on the current and subsequent items. Setting it does not call the delegate.
 * The Audio Only button requests a change through the delegate below; the
 * owner applies the playback change and updates this property. Backgrounding
 * detaches presentation independently and does not change this preference.
 */
@property(nonatomic,assign,getter=isAudioOnly) BOOL audioOnly;

/**
 * Both default NO. The owner updates these as the playlist position changes.
 * A button is enabled only when its flag is YES, player is non-nil, and the
 * delegate implements the corresponding request. These mean playlist item
 * navigation, not fast-forward/rewind or seeking within the current item.
 */
@property(nonatomic,assign) BOOL canSkipToPreviousItem;
@property(nonatomic,assign) BOOL canSkipToNextItem;

@end

/**
 * Requests originate from the UI; the playback owner performs the action.
 * Programmatic property changes do not generate requests. The optional
 * headphones button is shown only if its audio-only handler is implemented;
 * the Audio Only button also requires a non-nil player.
 *
 * The controller does not maintain a second playlist or automatically advance
 * an AVQueuePlayer in response to these requests. The owner handles previous,
 * next, and selection consistently with remote playback controls.
 */
@protocol RDLPPlayerViewControllerDelegate <NSObject>
@optional

- (void)playerViewControllerDidRequestPreviousItem:(RDLPPlayerViewController *)playerViewController;
- (void)playerViewControllerDidRequestNextItem:(RDLPPlayerViewController *)playerViewController;

/**
 * Requests the new mode. The owner may decline by leaving audioOnly unchanged.
 * Apply track selection in the persistent playback owner so it also takes
 * effect when the queue advances while this view controller is dismissed.
 */
- (void)playerViewController:(RDLPPlayerViewController *)playerViewController
       didRequestAudioOnly:(BOOL)audioOnly;

/**
 * Done was tapped. The owner dismisses or removes this controller; playback
 * continues unless the owner explicitly pauses it. Without this handler, Done
 * dismisses the modal navigation controller when this is its root. Otherwise
 * Done is hidden and normal navigation back behavior is available.
 */
- (void)playerViewControllerDidRequestDismissal:(RDLPPlayerViewController *)playerViewController;

@end
