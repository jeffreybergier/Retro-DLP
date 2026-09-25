#import "RDLPPlayerViewController.h"
#import "RDLPPlayerQueue.h"

@class RDLPLibrary;

/* App adapter: one downloaded job per presentation. Home/lock keeps audio
 * playing; dismissing the controller ends the session. Main thread only. */
@interface RDLPDownloadedPlayerViewController : RDLPPlayerViewController
    <RDLPPlayerViewControllerDelegate, AVAudioSessionDelegate>
@property(nonatomic,readonly,retain) RDLPPlayerQueue *queue;
- (id)initWithLibrary:(RDLPLibrary *)library job:(NSDictionary *)job URL:(NSURL *)URL;
- (void)stop;
@end
