#import "RDLPLibrary+Platform.h"
#import "RDLPAppKit.h"

@implementation RDLPLibrary (Platform)
- (void)configurePlatformStorage; { }
- (NSString *)removeDownloadFileAtPath:(NSString *)path;
{
  return [RDLPAppKit moveFileToTrash:path]?nil:[NSString stringWithFormat:@"Couldn’t move ‘%@’ to the Trash. Check permissions and try again.",[path lastPathComponent]];
}
@end

@implementation RDLPLibrary (Playback)
- (double)playbackSecondsForVideo:(NSString *)video;
{ return [self storedPlaybackSecondsForVideo:video]; }
- (void)savePlaybackSeconds:(double)seconds forVideo:(NSString *)video;
{ [self storePlaybackSeconds:seconds forVideo:video]; }
@end
