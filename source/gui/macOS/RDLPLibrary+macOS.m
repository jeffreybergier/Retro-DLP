#import "RDLPLibrary+Platform.h"

@implementation RDLPLibrary (Platform)
- (void)configurePlatformStorage; { }
@end

@implementation RDLPLibrary (Playback)
- (double)playbackSecondsForVideo:(NSString *)video;
{ return [self storedPlaybackSecondsForVideo:video]; }
- (void)savePlaybackSeconds:(double)seconds forVideo:(NSString *)video;
{ [self storePlaybackSeconds:seconds forVideo:video]; }
@end
