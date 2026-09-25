/* Device regressions use real AVFoundation items and an isolated SQLite store. */
#import "../player/RDLPDownloadedPlayerViewController.h"
#import "../player/RDLPPlayerControls.h"
@interface RDLPDownloadedPlayerViewController (Testing)
- (void)saveProgress;
- (void)updateNowPlaying;
@end
@interface RDLPPlaybackTestEvent : UIEvent { UIEventSubtype _subtype; }
- (id)initWithSubtype:(UIEventSubtype)subtype;
@end
@implementation RDLPPlaybackTestEvent
- (id)initWithSubtype:(UIEventSubtype)subtype { self=[super init]; if(self) _subtype=subtype; return self; }
- (UIEventType)type { return UIEventTypeRemoteControl; }
- (UIEventSubtype)subtype { return _subtype; }
@end
static void playbackRemote(RDLPDownloadedPlayerViewController *controller,UIEventSubtype subtype) {
  RDLPPlaybackTestEvent *event=[[RDLPPlaybackTestEvent alloc] initWithSubtype:subtype];
  [controller remoteControlReceivedWithEvent:event]; [event release];
}
@interface RDLPPlaybackTestLibrary : NSObject { rdapp_store *store_; NSUInteger _writes; }
@property(nonatomic,readonly) NSUInteger writes;
- (id)initWithPath:(NSString *)path;
- (double)playbackSecondsForVideo:(NSString *)video;
- (void)savePlaybackSeconds:(double)seconds forVideo:(NSString *)video;
@end
@implementation RDLPPlaybackTestLibrary
@synthesize writes=_writes;
- (id)initWithPath:(NSString *)path;
{
  self=[super init]; if(!self) return nil;
  if(!rdapp_store_open([path fileSystemRepresentation],&store_) ||
     !rdapp_store_add_adhoc(store_,"AAAAAAAAAAA","Playback test",NULL))
    [NSException raise:@"PlaybackTest" format:@"Open playback fixture"];
  return self;
}
- (void)dealloc; { rdapp_store_close(store_); [super dealloc]; }
- (double)playbackSecondsForVideo:(NSString *)video;
{
  double seconds=0;
  if(!rdapp_store_playback_seconds(store_,[video UTF8String],&seconds))
    [NSException raise:@"PlaybackTest" format:@"Read playback fixture"];
  return seconds;
}
- (void)savePlaybackSeconds:(double)seconds forVideo:(NSString *)video;
{
  if(!rdapp_store_save_playback_seconds(store_,[video UTF8String],seconds))
    [NSException raise:@"PlaybackTest" format:@"Save playback fixture"];
  ++_writes;
}
@end
static void playbackRequire(BOOL condition,NSString *message) {
  if(!condition) [NSException raise:@"PlaybackTest" format:@"%@",message];
}
@interface RDLPPlaybackWriteTestLibrary : RDLPLibrary
@end
@implementation RDLPPlaybackWriteTestLibrary
- (void)startNext; { /* Keep the real store, but never schedule network work. */ }
@end
static void testIOSPlaybackWrites(NSString *directory) {
  [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
  NSString *support=[directory stringByAppendingPathComponent:@"Support"];
  NSString *path=[support stringByAppendingPathComponent:@"retrodlp.sqlite"], *video=@"AAAAAAAAAAA";
  RDLPLibrary *library=[[RDLPPlaybackWriteTestLibrary alloc] initWithSupportDirectory:support
    downloadDirectory:[directory stringByAppendingPathComponent:@"Downloads"]];
  playbackRequire(library!=nil,@"Open asynchronous checkpoint fixture");
  rdapp_store *store=NULL;
  playbackRequire(rdapp_store_open([path fileSystemRepresentation],&store) &&
    rdapp_store_add_adhoc(store,[video UTF8String],"Checkpoint",NULL),@"Create checkpoint video");
  rdapp_store_close(store);
  NSLock *lock=[library valueForKey:@"lock_"];
  dispatch_semaphore_t acquired=dispatch_semaphore_create(0), release=dispatch_semaphore_create(0);
  dispatch_group_t blocker=dispatch_group_create();
  dispatch_group_async(blocker,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{
    [lock lock]; dispatch_semaphore_signal(acquired);
    /* A timeout makes the old synchronous implementation fail, not hang. */
    dispatch_semaphore_wait(release,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC));
    [lock unlock];
  });
  playbackRequire(dispatch_semaphore_wait(acquired,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0,@"Hold the download worker's store lock");
  NSTimeInterval start=[NSDate timeIntervalSinceReferenceDate];
  [library savePlaybackSeconds:42 forVideo:video];
  [library savePlaybackSeconds:5 forVideo:video];
  double backward=[library playbackSecondsForVideo:video];
  [library savePlaybackSeconds:0 forVideo:video];
  double reset=[library playbackSecondsForVideo:video];
  NSTimeInterval elapsed=[NSDate timeIntervalSinceReferenceDate]-start;
  NSUInteger pending=[library operationCount];
  dispatch_semaphore_signal(release);
  dispatch_group_wait(blocker,DISPATCH_TIME_FOREVER);
  dispatch_release(blocker); dispatch_release(acquired); dispatch_release(release);
  playbackRequire(elapsed<0.5,@"Checkpoint callbacks and immediate resume reads do not wait for the store lock");
  playbackRequire(backward==5 && reset==0,@"Pending backward seeks and completion reset are immediately visible");
  playbackRequire(pending==3,@"Accepted writes hold background-operation references");
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
  while([library operationCount] && [deadline timeIntervalSinceNow]>0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  playbackRequire([library operationCount]==0,@"Checkpoint writes release their operation references");
  playbackRequire(rdapp_store_open([path fileSystemRepresentation],&store),@"Reopen checkpoint store");
  double saved=-1;
  playbackRequire(rdapp_store_playback_seconds(store,[video UTF8String],&saved) && saved==0,@"Serial persistence cannot overwrite completion with an older checkpoint");
  rdapp_store_close(store);
  [library shutdown]; [library release];
}
static void playbackPump(void) {
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
static void playbackWait(RDLPDownloadedPlayerViewController *controller) {
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
  while(![[controller valueForKey:@"ready"] boolValue] && [deadline timeIntervalSinceNow]>0) playbackPump();
  playbackRequire([[controller valueForKey:@"ready"] boolValue],@"Local AVPlayer item and resume seek become ready");
}
static void playbackSeek(AVPlayer *player,double seconds) {
  __block BOOL done=NO;
  [player seekToTime:CMTimeMakeWithSeconds(seconds,600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero
    completionHandler:^(BOOL finished) { (void)finished; done=YES; }];
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
  while(!done && [deadline timeIntervalSinceNow]>0) playbackPump();
  playbackRequire(done,@"Fixture seek completes");
}
static RDLPDownloadedPlayerViewController *playbackController(RDLPPlaybackTestLibrary *library,NSDictionary *job) {
  NSURL *URL=[[NSBundle mainBundle] URLForResource:@"playback-fixture" withExtension:@"mp4"];
  RDLPDownloadedPlayerViewController *controller=[[RDLPDownloadedPlayerViewController alloc]
    initWithLibrary:(RDLPLibrary *)library job:job URL:URL];
  [controller viewWillAppear:NO]; [controller viewDidAppear:NO]; playbackWait(controller);
  return controller;
}
static void testIOSPlaybackProgress(NSString *directory) {
  [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  NSString *path=[directory stringByAppendingPathComponent:@"playback.sqlite"], *video=@"AAAAAAAAAAA";
  RDLPPlaybackTestLibrary *library=[[RDLPPlaybackTestLibrary alloc] initWithPath:path];
  [library savePlaybackSeconds:12 forVideo:video];
  NSDictionary *job=[NSDictionary dictionaryWithObject:video forKey:@"video_id"];
  RDLPDownloadedPlayerViewController *controller=playbackController(library,job);
  playbackRequire(controller.queue.playlist.count==1 && controller.queue.currentIndex==0 &&
    !controller.queue.canSkipToNextItem && !controller.queue.canSkipToPreviousItem,@"A tap owns exactly one queue item");
  playbackRequire(controller.player.rate==1 && fabs(CMTimeGetSeconds(controller.player.currentTime)-12)<1,@"Opening restores the bookmark and starts playback");
  playbackSeek(controller.player,20); [controller saveProgress];
  playbackRequire(fabs([library playbackSecondsForVideo:video]-20)<1,@"Foreground playback saves its actual position");
  [controller.player pause];
  NSUInteger writes=library.writes;
  playbackSeek(controller.player,25);
  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  for(NSUInteger i=0;i<100;++i)
    [center postNotificationName:AVPlayerItemTimeJumpedNotification object:controller.player.currentItem];
  playbackRequire(library.writes==writes,@"A burst of position changes does not write synchronously");
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.7]];
  playbackRequire(library.writes==writes+1 && fabs([library playbackSecondsForVideo:video]-25)<0.1,@"Paused seeks debounce into one write of the final position");
  [controller saveProgress]; [controller saveProgress];
  playbackRequire(library.writes==writes+1,@"An unchanged paused position is not written repeatedly");
  [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  [controller.player play]; playbackSeek(controller.player,30); [controller saveProgress];
  playbackRequire(fabs([library playbackSecondsForVideo:video]-30)<1,@"Background playback advances the bookmark");
  [controller playerViewController:controller didRequestAudioOnly:YES];
  playbackRequire(controller.audioOnly && controller.queue.audioOnly && controller.player.rate==1,@"Audio Only changes presentation and queue without pausing");
  for(AVPlayerItemTrack *track in controller.player.currentItem.tracks)
    if([track.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) playbackRequire(!track.enabled,@"Audio Only disables video tracks");
  [controller playerViewController:controller didRequestAudioOnly:NO];
  [controller.player pause];
  double positions[]={5,6,6.1,53.9,54,55};
  double expected[]={0,0,6.1,53.9,0,0};
  for(NSUInteger i=0;i<sizeof(positions)/sizeof(positions[0]);++i) {
    playbackSeek(controller.player,positions[i]); [controller saveProgress];
    playbackRequire(fabs([library playbackSecondsForVideo:video]-expected[i])<0.01,@"First/last ten percent (including boundaries) saves zero; middle positions survive");
  }
  playbackSeek(controller.player,60);
  [center postNotificationName:AVPlayerItemDidPlayToEndTimeNotification object:controller.player.currentItem];
  playbackRequire([library playbackSecondsForVideo:video]==0,@"Background completion resets the bookmark");
  [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  playbackSeek(controller.player,35);
  [controller stop];
  playbackRequire(fabs([library playbackSecondsForVideo:video]-35)<0.1,@"Dismissal flushes a pending paused seek immediately");
  [library savePlaybackSeconds:7 forVideo:video];
  [controller saveProgress]; playbackRemote(controller,UIEventSubtypeRemoteControlPlay);
  playbackRequire(controller.player.rate==0 && [library playbackSecondsForVideo:video]==7,@"Stopped controllers cannot restart or overwrite progress");
  [controller release]; [library release];
  library=[[RDLPPlaybackTestLibrary alloc] initWithPath:path];
  controller=playbackController(library,job);
  playbackRequire(fabs(CMTimeGetSeconds(controller.player.currentTime)-7)<1,@"A new presentation restores persisted progress");
  [controller stop]; [controller release];
  for(NSNumber *position in [NSArray arrayWithObjects:@5,@55,nil]) {
    [library savePlaybackSeconds:position.doubleValue forVideo:video];
    controller=playbackController(library,job);
    playbackRequire(CMTimeGetSeconds(controller.player.currentTime)<1,@"Old bookmarks near either end restart at zero");
    [controller stop]; [controller release];
  }
  [library release];
}
static NSDictionary *playbackNowPlayingInfo(void) {
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.1]];
  return [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo;
}
static void testIOSNowPlaying(NSString *directory) {
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  RDLPPlaybackTestLibrary *library=[[RDLPPlaybackTestLibrary alloc] initWithPath:[directory stringByAppendingPathComponent:@"now-playing.sqlite"]];
  NSDictionary *job=[NSDictionary dictionaryWithObjectsAndKeys:@"AAAAAAAAAAA",@"video_id",@"Video title",@"title",@"Channel name",@"channel",nil];
  RDLPDownloadedPlayerViewController *controller=playbackController(library,job);
  playbackRequire([[playbackNowPlayingInfo() objectForKey:MPMediaItemPropertyTitle] isEqualToString:@"Video title"] &&
    [[playbackNowPlayingInfo() objectForKey:MPMediaItemPropertyArtist] isEqualToString:@"Channel name"],@"Now Playing publishes library metadata");
  playbackRemote(controller,UIEventSubtypeRemoteControlPause);
  playbackSeek(controller.player,12);
  playbackRequire([[playbackNowPlayingInfo() objectForKey:MPNowPlayingInfoPropertyPlaybackRate] doubleValue]==0 &&
    fabs([[playbackNowPlayingInfo() objectForKey:MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue]-12)<0.1,@"Remote pause and paused seek update Now Playing");
  playbackRemote(controller,UIEventSubtypeRemoteControlPlay);
  playbackRequire(controller.player.rate==1,@"Remote Play resumes playback");
  [controller beginInterruption];
  playbackRequire(controller.player.rate==0,@"Interruption pauses playback");
  [controller endInterruptionWithFlags:AVAudioSessionInterruptionFlags_ShouldResume];
  playbackRequire(controller.player.rate==1,@"Allowed interruption recovery resumes previously playing audio");
  [controller beginInterruption];
  [controller endInterruptionWithFlags:0];
  playbackRequire(controller.player.rate==0,@"Interruption without permission to resume stays paused");
  playbackRemote(controller,UIEventSubtypeRemoteControlPause);
  [controller beginInterruption]; [controller endInterruptionWithFlags:AVAudioSessionInterruptionFlags_ShouldResume];
  playbackRequire(controller.player.rate==0,@"An interruption cannot start user-paused playback");
  RDLPDownloadedPlayerViewController *next=playbackController(library,[NSDictionary dictionaryWithObject:@"AAAAAAAAAAA" forKey:@"video_id"]);
  playbackRequire(controller.player.rate==0,@"Replacement stops the previous session");
  [controller release];
  playbackRequire([[playbackNowPlayingInfo() objectForKey:MPMediaItemPropertyTitle] isEqualToString:@"AAAAAAAAAAA"] &&
    ![playbackNowPlayingInfo() objectForKey:MPMediaItemPropertyArtist],@"Old teardown cannot erase replacement metadata; missing title falls back to ID");
  [next stop];
  playbackRequire(!playbackNowPlayingInfo().count,@"Stopping clears Now Playing");
  [next release]; [library release];
}
