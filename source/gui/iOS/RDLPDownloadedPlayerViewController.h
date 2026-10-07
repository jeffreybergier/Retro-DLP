#import "player/RDLPPlayerViewController.h"
#import "player/RDLPPlayerNavigationController.h"
#import "player/RDLPPlayerQueue.h"

@class RDLPLibrary;

/* App session and navigation container. Present directly; its root child supplies
 * the player UI. Home/lock and Done while playing keep audio playing.
 * The session uses AVPlayer and the child's public API, never player subclassing.
 * Main thread only. */
@interface RDLPDownloadedPlayerViewController : RDLPPlayerNavigationController
    <RDLPPlayerViewControllerDelegate>
@property(nonatomic,readonly,retain) RDLPPlayerQueue *queue;
@property(nonatomic,readonly,retain) AVPlayer *player;
@property(nonatomic,readonly,retain) RDLPPlayerViewController *playerViewController;
/* Borrowed active session while dismissed; nil after Done while paused or stop.
 * The active session is retained independently of UIKit presentation. */
+ (RDLPDownloadedPlayerViewController *)hiddenPlayback;
- (void)reopenFromViewController:(UIViewController *)owner;
- (id)initWithLibrary:(RDLPLibrary *)library job:(NSDictionary *)job URL:(NSURL *)URL;
/* Jobs and URLs correspond one-to-one, including repeated playlist entries.
 * Invalid/empty input returns nil. Each selected item restores its own bookmark. */
- (id)initWithLibrary:(RDLPLibrary *)library jobs:(NSArray *)jobs URLs:(NSArray *)URLs startingAtIndex:(NSUInteger)index;
/* AVAudioSession's iOS 5 delegate selectors; installed by RDLPUIKit. */
- (void)beginInterruption;
- (void)endInterruptionWithFlags:(NSUInteger)flags;
- (void)stop;
@end

extern NSString *const RDLPPlaybackVisibilityDidChangeNotification;
