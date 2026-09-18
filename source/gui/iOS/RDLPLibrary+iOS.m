#import "RDLPLibrary+Platform.h"
#import "RDLP_Foundation.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#include <sys/xattr.h>
#include <errno.h>
#include <math.h>

@interface RDLPIOSPlaybackStorage : NSObject {
@public
  dispatch_queue_t queue;
  NSMutableDictionary *positions;
}
@end
@implementation RDLPIOSPlaybackStorage
- (id)init;
{
  self=[super init]; if(!self) return nil;
  queue=dispatch_queue_create("com.altivecintelligence.RetroDLP.playback",DISPATCH_QUEUE_SERIAL);
  positions=[[NSMutableDictionary alloc] init]; return self;
}
- (void)dealloc;
{ dispatch_release(queue); [positions release]; [super dealloc]; }
@end

@implementation RDLPLibrary (Platform)
- (void)configurePlatformStorage;
{
  platformStorage_=[[RDLPIOSPlaybackStorage alloc] init];
  /* Exclude downloaded media and staging files, keeping settings and the
     database eligible for backup. iOS 5.0.1 uses the older extended attribute. */
  NSError *backupError=nil; BOOL excluded=NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
  if(kCFCoreFoundationVersionNumber>=kCFCoreFoundationVersionNumber_iOS_5_1)
    excluded=[[NSURL fileURLWithPath:root_ isDirectory:YES] setResourceValue:[NSNumber numberWithBool:YES]
      forKey:NSURLIsExcludedFromBackupKey error:&backupError];
  else {
    unsigned char value=1;
    excluded=setxattr([root_ fileSystemRepresentation],"com.apple.MobileBackup",&value,sizeof(value),0,0)==0;
    if(!excluded) backupError=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
  }
#pragma clang diagnostic pop
  if(!excluded) [self reportError:@"Couldn’t exclude downloads from backups" detail:[backupError localizedDescription]];
}
@end

@implementation RDLPLibrary (Playback)
- (double)playbackSecondsForVideo:(NSString *)video;
{
  NSAssert([NSThread RLDP_isMainThread],@"Playback checkpoints belong to the main thread");
  RDLPIOSPlaybackStorage *storage=platformStorage_;
  NSNumber *pending=[storage->positions objectForKey:video];
  return pending?[pending doubleValue]:[self storedPlaybackSecondsForVideo:video];
}
- (void)savePlaybackSeconds:(double)seconds forVideo:(NSString *)video;
{
  NSAssert([NSThread RLDP_isMainThread],@"Playback checkpoints belong to the main thread");
  if(![video length] || !isfinite(seconds) || seconds<0) return;
  RDLPIOSPlaybackStorage *storage=platformStorage_;
  [storage->positions setObject:[NSNumber numberWithDouble:seconds] forKey:video];
  /* Native control callbacks never wait for SQLite or the worker's lock.
     Serial writes preserve backward seeks and completion resets. Pending
     values remain available if another player is opened before a write ends. */
  NSString *videoID=[[video copy] autorelease];
  [self beginOperation];
  dispatch_async(storage->queue,^{
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    [self storePlaybackSeconds:seconds forVideo:videoID];
    dispatch_async(dispatch_get_main_queue(),^{ [self endOperation]; });
    [pool drain];
  });
}
@end
