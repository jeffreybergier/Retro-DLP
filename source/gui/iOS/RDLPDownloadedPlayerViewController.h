#import "player/RDLPPlayerViewController.h"
#import "player/RDLPPlayerQueue.h"

@class RDLPLibrary;

/* App adapter: a snapshot of downloaded jobs in playlist order. Home/lock keeps audio
 * playing; dismissing the controller ends the session. Main thread only. */
@interface RDLPDownloadedPlayerViewController : RDLPPlayerViewController
    <RDLPPlayerViewControllerDelegate, AVAudioSessionDelegate>
@property(nonatomic,readonly,retain) RDLPPlayerQueue *queue;
- (id)initWithLibrary:(RDLPLibrary *)library job:(NSDictionary *)job URL:(NSURL *)URL;
/* Jobs and URLs correspond one-to-one, including repeated playlist entries.
 * Invalid/empty input returns nil. Each selected item restores its own bookmark. */
- (id)initWithLibrary:(RDLPLibrary *)library jobs:(NSArray *)jobs URLs:(NSArray *)URLs startingAtIndex:(NSUInteger)index;
- (void)stop;
@end
