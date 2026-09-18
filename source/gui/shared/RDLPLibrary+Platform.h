#import "RDLPLibrary.h"

/* Each target links its own category for platform setup and playback policy. */
@interface RDLPLibrary (Platform)
- (void)configurePlatformStorage;
@end

/* Shared storage primitives. Platform code chooses when to call them. */
@interface RDLPLibrary (PlatformSupport)
- (double)storedPlaybackSecondsForVideo:(NSString *)video;
- (void)storePlaybackSeconds:(double)seconds forVideo:(NSString *)video;
- (void)beginOperation;
- (void)endOperation;
- (void)reportError:(NSString *)title detail:(NSString *)detail;
@end
