/* Device regressions use real AVFoundation items and an isolated SQLite store. */
#import "../RDLPDownloadedPlayerViewController.h"
#import "../player/RDLPPlayerControls.h"
@interface RDLPDownloadedPlayerViewController (Testing)
- (void)saveProgress;
- (void)updateNowPlaying;
- (void)selectIndex:(NSUInteger)index;
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
     !rdapp_store_add_adhoc(store_,"AAAAAAAAAAA","Playback test",NULL) ||
     !rdapp_store_add_adhoc(store_,"BBBBBBBBBBB","Second video",NULL) ||
     !rdapp_store_add_adhoc(store_,"CCCCCCCCCCC","Third video",NULL))
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
/* Feed the registered target an event with a real command object, without
 * requiring lock-screen automation. The bridge only consumes its command. */
@interface RDLPPlaybackCommandTestEvent : NSObject {
  id _command;
}
- (id)initWithCommand:(id)command;
- (id)command;
@end
@implementation RDLPPlaybackCommandTestEvent
- (id)initWithCommand:(id)command {
  self=[super init]; if(self) _command=[command retain]; return self;
}
- (id)command { return _command; }
- (void)dealloc { [_command release]; [super dealloc]; }
@end
@protocol RDLPPlaybackCommandTestHandler <NSObject>
- (NSInteger)handleCommand:(id)event;
@end
static id playbackCommandCenter(void) {
  return [NSClassFromString(@"MPRemoteCommandCenter") performSelector:@selector(sharedCommandCenter)];
}
static void playbackModernRemote(RDLPDownloadedPlayerViewController *controller,BOOL backward) {
  BOOL longContent=[[controller playerViewController] longContent];
  NSString *key=longContent?(backward?@"skipBackwardCommand":@"skipForwardCommand"):
    (backward?@"previousTrackCommand":@"nextTrackCommand");
  id command=[playbackCommandCenter() valueForKey:key];
  RDLPPlaybackCommandTestEvent *event=[[RDLPPlaybackCommandTestEvent alloc] initWithCommand:command];
  id<RDLPPlaybackCommandTestHandler> registration=[controller valueForKey:@"remoteCommands"];
  playbackRequire(registration && [registration handleCommand:event]==0,@"Registered system command reaches playback owner");
  [event release];
}
static void playbackCheckCommandConfiguration(RDLPDownloadedPlayerViewController *controller,BOOL longContent) {
  id center=playbackCommandCenter();
  if(!center) {
    playbackRequire(![controller valueForKey:@"remoteCommands"],@"Old iOS uses legacy remote events");
    return;
  }
  playbackRequire([controller valueForKey:@"remoteCommands"]!=nil,@"Modern iOS registers system commands");
  playbackRequire([[center valueForKeyPath:@"skipBackwardCommand.enabled"] boolValue]==longContent &&
    [[center valueForKeyPath:@"skipForwardCommand.enabled"] boolValue]==longContent &&
    [[center valueForKeyPath:@"previousTrackCommand.enabled"] boolValue]!=longContent &&
    [[center valueForKeyPath:@"nextTrackCommand.enabled"] boolValue]==(!longContent && [[controller queue] canSkipToNextItem]),
    @"System buttons switch between time jumps and track navigation");
  playbackRequire([[center valueForKeyPath:@"skipBackwardCommand.preferredIntervals"] isEqual:[NSArray arrayWithObject:@30]] &&
    [[center valueForKeyPath:@"skipForwardCommand.preferredIntervals"] isEqual:[NSArray arrayWithObject:@60]],
    @"System time-jump buttons advertise thirty and sixty seconds");
}
/* Exercise the UI delegate and remote-event entry points with identical positions.
 * The standalone UI tests separately verify that button taps invoke these delegates. */
static void playbackCheckNavigation(RDLPDownloadedPlayerViewController *controller,BOOL longContent) {
  AVPlayer *player=[controller player];
  [player pause];
  playbackCheckCommandConfiguration(controller,longContent);
  double positions[]={100,100,10,590};
  double targets[]={70,160,0,600};
  for(NSUInteger route=0;route<([controller valueForKey:@"remoteCommands"]?3:2);++route) {
    if(route) [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    for(NSUInteger i=0;i<(longContent?4:1);++i) {
      playbackSeek(player,longContent?positions[i]:6);
      BOOL backward=!longContent || i%2==0;
      if(route==2) playbackModernRemote(controller,backward);
      else if(route) playbackRemote(controller,backward?UIEventSubtypeRemoteControlPreviousTrack:UIEventSubtypeRemoteControlNextTrack);
      else if(backward) [controller playerViewControllerDidRequestBack:[controller playerViewController]];
      else [controller playerViewControllerDidRequestForward:[controller playerViewController]];
      double target=longContent?targets[i]:0;
      NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
      while(fabs(CMTimeGetSeconds([player currentTime])-target)>0.1 && [deadline timeIntervalSinceNow]>0) playbackPump();
      playbackRequire(fabs(CMTimeGetSeconds([player currentTime])-target)<0.1 && [[controller queue] currentIndex]==0,
        @"UI and inactive remote navigation share restart, time jumps, and clamping");
      playbackRequire([player rate]==0,@"Navigation leaves paused playback paused");
    }
    if(route) [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  }
}
static RDLPDownloadedPlayerViewController *playbackControllerWithResource(RDLPPlaybackTestLibrary *library,NSDictionary *job,NSString *resource) {
  NSURL *URL=[[NSBundle mainBundle] URLForResource:resource withExtension:@"mp4"];
  RDLPDownloadedPlayerViewController *controller=[[RDLPDownloadedPlayerViewController alloc]
    initWithLibrary:(RDLPLibrary *)library job:job URL:URL];
  [controller viewWillAppear:NO]; [controller viewDidAppear:NO]; playbackWait(controller);
  return controller;
}
static RDLPDownloadedPlayerViewController *playbackController(RDLPPlaybackTestLibrary *library,NSDictionary *job) {
  return playbackControllerWithResource(library,job,@"playback-long-fixture");
}
static void testIOSPlaybackProgress(NSString *directory) {
  [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  NSString *path=[directory stringByAppendingPathComponent:@"playback.sqlite"], *video=@"AAAAAAAAAAA";
  RDLPPlaybackTestLibrary *library=[[RDLPPlaybackTestLibrary alloc] initWithPath:path];
  [library savePlaybackSeconds:120 forVideo:video];
  NSDictionary *job=[NSDictionary dictionaryWithObject:video forKey:@"video_id"];
  RDLPDownloadedPlayerViewController *invalid=[[RDLPDownloadedPlayerViewController alloc]
    initWithLibrary:(RDLPLibrary *)library jobs:[NSArray arrayWithObject:job]
    URLs:[NSArray arrayWithObject:@"not a URL"] startingAtIndex:0];
  playbackRequire(invalid==nil,@"Invalid initialization cleans up without removing an unregistered player observer");
  [invalid release];
  RDLPDownloadedPlayerViewController *controller=playbackController(library,job);
  playbackRequire([[controller playerViewController] longContent],@"Ten-minute media is long content");
  playbackRequire(controller.queue.playlist.count==1 && controller.queue.currentIndex==0 &&
    !controller.queue.canSkipToNextItem && !controller.queue.canSkipToPreviousItem,@"A tap owns exactly one queue item");
  playbackRequire(controller.player.rate==1 && fabs(CMTimeGetSeconds(controller.player.currentTime)-120)<1,@"Opening restores the bookmark and starts playback");
  playbackCheckNavigation(controller,YES);
  playbackSeek([controller player],200);
  [[controller player] play]; [controller saveProgress];
  playbackRequire(fabs([library playbackSecondsForVideo:video]-200)<1,@"Foreground playback saves its actual position");
  [controller.player pause];
  playbackSeek(controller.player,250);
  /* Waiting for a real seek may run the debounce timer on slower devices.
   * Measure the notification burst separately from that asynchronous wait. */
  NSUInteger writes=library.writes;
  NSUInteger expectedWrites=writes+(fabs([library playbackSecondsForVideo:video]-250)<0.1?0:1);
  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  for(NSUInteger i=0;i<100;++i)
    [center postNotificationName:AVPlayerItemTimeJumpedNotification object:controller.player.currentItem];
  playbackRequire(library.writes==writes,@"A burst of position changes does not write synchronously");
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.7]];
  playbackRequire(library.writes==expectedWrites && fabs([library playbackSecondsForVideo:video]-250)<0.1,@"Paused seeks debounce into one write of the final position");
  [controller saveProgress]; [controller saveProgress];
  playbackRequire(library.writes==expectedWrites,@"An unchanged paused position is not written repeatedly");
  [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  playbackRequire([[controller queue] isAudioOnly] && [[controller playerViewController] isAudioOnly] &&
    [[controller player] rate]==0,@"Inactivity enters Audio Only without starting paused playback");
  [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
  [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  playbackRequire(![[controller queue] isAudioOnly] && ![[controller playerViewController] isAudioOnly] &&
    [[controller player] rate]==0,@"Repeated inactivity notifications preserve automatic video restoration and paused state");
  [controller playerViewController:[controller playerViewController] didRequestAudioOnly:YES];
  [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
  [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  playbackRequire([[controller queue] isAudioOnly],@"User-selected Audio Only survives a background/foreground cycle");
  [controller playerViewController:[controller playerViewController] didRequestAudioOnly:NO];
  [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  [controller.player play]; playbackSeek(controller.player,300); [controller saveProgress];
  playbackRequire(fabs([library playbackSecondsForVideo:video]-300)<1,@"Background playback advances the bookmark");
  [controller playerViewController:controller.playerViewController didRequestAudioOnly:YES];
  playbackRequire(controller.playerViewController.audioOnly && controller.queue.audioOnly && controller.player.rate==1,@"Audio Only changes presentation and queue without pausing");
  for(AVPlayerItemTrack *track in controller.player.currentItem.tracks)
    if([track.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) playbackRequire([track isEnabled],@"Audio Only leaves video tracks enabled");
  [controller playerViewController:controller.playerViewController didRequestAudioOnly:NO];
  [controller.player pause];
  double positions[]={50,60,60.1,539.9,540,550};
  double expected[]={0,0,60.1,539.9,0,0};
  for(NSUInteger i=0;i<sizeof(positions)/sizeof(positions[0]);++i) {
    playbackSeek(controller.player,positions[i]); [controller saveProgress];
    playbackRequire(fabs([library playbackSecondsForVideo:video]-expected[i])<0.01,@"First/last ten percent (including boundaries) saves zero; middle positions survive");
  }
  playbackSeek(controller.player,600);
  [center postNotificationName:AVPlayerItemDidPlayToEndTimeNotification object:controller.player.currentItem];
  playbackRequire([library playbackSecondsForVideo:video]==0,@"Background completion resets the bookmark");
  [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  playbackSeek(controller.player,350);
  [controller stop];
  playbackRequire(![controller valueForKey:@"remoteCommands"] &&
    ![[playbackCommandCenter() valueForKeyPath:@"skipBackwardCommand.enabled"] boolValue] &&
    ![[playbackCommandCenter() valueForKeyPath:@"playCommand.enabled"] boolValue],
    @"Stopping playback removes the registration and disables system commands");
  playbackRequire(fabs([library playbackSecondsForVideo:video]-350)<0.1,@"Dismissal flushes a pending paused seek immediately");
  [library savePlaybackSeconds:70 forVideo:video];
  [controller saveProgress]; playbackRemote(controller,UIEventSubtypeRemoteControlPlay);
  playbackRequire(controller.player.rate==0 && [library playbackSecondsForVideo:video]==70,@"Stopped controllers cannot restart or overwrite progress");
  [controller release]; [library release];
  library=[[RDLPPlaybackTestLibrary alloc] initWithPath:path];
  controller=playbackController(library,job);
  playbackRequire(fabs(CMTimeGetSeconds(controller.player.currentTime)-70)<1,@"A new presentation restores persisted progress");
  [controller stop]; [controller release];
  for(NSNumber *position in [NSArray arrayWithObjects:@50,@550,nil]) {
    [library savePlaybackSeconds:position.doubleValue forVideo:video];
    NSUInteger bookmarkWrites=[library writes];
    controller=playbackController(library,job);
    playbackRequire(CMTimeGetSeconds(controller.player.currentTime)<1,@"Old bookmarks near either end restart at zero");
    playbackRequire([library playbackSecondsForVideo:video]==0 && [library writes]==bookmarkWrites+1,
      @"Ignored long-content bookmarks are cleared once during preparation");
    [controller stop]; [controller release];
  }
  /* Existing short-track bookmarks are discarded, including in audio-only mode. */
  [library savePlaybackSeconds:25 forVideo:video];
  NSUInteger shortWrites=[library writes];
  controller=playbackControllerWithResource(library,job,@"playback-fixture");
  playbackRequire(![[controller playerViewController] longContent] &&
    CMTimeGetSeconds([[controller player] currentTime])<1,@"Short content ignores an old bookmark");
  playbackRequire([library playbackSecondsForVideo:video]==0 && [library writes]==shortWrites+1,
    @"Short content clears its old bookmark once before playback starts");
  [[controller player] pause];
  [controller saveProgress];
  playbackRequire([library playbackSecondsForVideo:video]==0,@"Short content clears its old bookmark");
  playbackCheckNavigation(controller,NO);
  playbackRequire([library writes]==shortWrites+1,@"Pause and navigation do not repeat the bookmark reset");
  shortWrites=[library writes];
  playbackSeek([controller player],25); [controller saveProgress];
  [controller playerViewController:[controller playerViewController] didRequestAudioOnly:YES];
  playbackSeek([controller player],35); [controller saveProgress];
  [controller stop];
  playbackRequire([library playbackSecondsForVideo:video]==0 && [library writes]==shortWrites,
    @"Short video and audio-only playback keep zero without repeated writes");
  [controller release];
  controller=playbackControllerWithResource(library,job,@"playback-fixture");
  playbackRequire(CMTimeGetSeconds([[controller player] currentTime])<1,@"Reopening short content starts at zero");
  [controller stop]; [controller release];
  [library release];
}
static void testIOSPlaylistPlayback(NSString *directory) {
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  RDLPPlaybackTestLibrary *library=[[RDLPPlaybackTestLibrary alloc] initWithPath:[directory stringByAppendingPathComponent:@"playlist.sqlite"]];
  [library savePlaybackSeconds:120 forVideo:@"AAAAAAAAAAA"];
  [library savePlaybackSeconds:240 forVideo:@"BBBBBBBBBBB"];
  [library savePlaybackSeconds:360 forVideo:@"CCCCCCCCCCC"];
  NSMutableArray *jobs=[NSMutableArray array];
  for(NSString *video in [NSArray arrayWithObjects:@"AAAAAAAAAAA",@"BBBBBBBBBBB",@"CCCCCCCCCCC",nil])
    [jobs addObject:[NSDictionary dictionaryWithObjectsAndKeys:video,@"video_id",video,@"title",nil]];
  NSURL *URL=[[NSBundle mainBundle] URLForResource:@"playback-long-fixture" withExtension:@"mp4"];
  NSArray *URLs=[NSArray arrayWithObjects:URL,URL,URL,nil];
  RDLPDownloadedPlayerViewController *controller=[[RDLPDownloadedPlayerViewController alloc]
    initWithLibrary:(RDLPLibrary *)library jobs:jobs URLs:URLs startingAtIndex:1];
  [jobs removeAllObjects];
  [controller viewWillAppear:NO]; [controller viewDidAppear:NO]; playbackWait(controller);
  playbackRequire(controller.queue.currentIndex==1 && controller.queue.playlist.count==3 &&
    controller.playerViewController.canSkipToPreviousItem && controller.playerViewController.canSkipToNextItem && controller.player.rate==1 &&
    fabs(CMTimeGetSeconds(controller.player.currentTime)-240)<1,@"Playlist snapshot starts at the tapped entry's bookmark and autoplays");
  [controller.player pause]; playbackSeek(controller.player,300);
  AVPlayerItem *old=[controller.player.currentItem retain];
  [controller selectIndex:2]; playbackWait(controller);
  playbackRequire(controller.queue.currentIndex==2 && !controller.playerViewController.canSkipToNextItem && controller.player.rate==0 &&
    fabs(CMTimeGetSeconds(controller.player.currentTime)-360)<0.1 &&
    fabs([library playbackSecondsForVideo:@"BBBBBBBBBBB"]-300)<0.1,@"Next flushes the outgoing seek and restores the next bookmark while paused");
  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  [center postNotificationName:AVPlayerItemDidPlayToEndTimeNotification object:old];
  [center postNotificationName:AVPlayerItemTimeJumpedNotification object:old];
  [old release];
  playbackRequire(fabs([library playbackSecondsForVideo:@"CCCCCCCCCCC"]-360)<0.1,@"Late outgoing-item events cannot overwrite the new bookmark");
  [controller selectIndex:1]; playbackWait(controller);
  playbackRequire(controller.queue.currentIndex==1 && fabs(CMTimeGetSeconds(controller.player.currentTime)-300)<0.1,@"Previous restores the outgoing entry's newly saved position");
  /* A second skip can arrive while the first item's resume seek is in flight. */
  [controller selectIndex:2];
  [controller selectIndex:1]; playbackWait(controller);
  playbackRequire(controller.queue.currentIndex==1 && controller.player.rate==0 &&
    fabs(CMTimeGetSeconds(controller.player.currentTime)-300)<0.1,@"Rapid navigation ignores stale seek completions");
  [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
  playbackRequire([[controller queue] isAudioOnly],@"Backgrounding selects Audio Only before automatic advancement");
  playbackSeek(controller.player,599.8); playbackRemote(controller,UIEventSubtypeRemoteControlPlay);
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
  while((controller.queue.currentIndex!=2 || ![[controller valueForKey:@"ready"] boolValue]) && [deadline timeIntervalSinceNow]>0) playbackPump();
  playbackRequire(controller.queue.currentIndex==2 && [[controller valueForKey:@"ready"] boolValue] &&
    controller.player.rate==1 && fabs(CMTimeGetSeconds(controller.player.currentTime)-360)<2,@"Natural advancement restores the following bookmark and autoplays while inactive");
  playbackRequire([library playbackSecondsForVideo:@"BBBBBBBBBBB"]==0 &&
    [library playbackSecondsForVideo:@"AAAAAAAAAAA"]==120,@"Completion resets only the outgoing video's bookmark");
  playbackRequire(controller.playerViewController.audioOnly && controller.queue.audioOnly,@"Audio-only mode survives item transitions");
  for(AVPlayerItemTrack *track in controller.player.currentItem.tracks)
    if([track.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) playbackRequire([track isEnabled],@"Next item's video tracks stay enabled");
  [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  playbackRequire(![[controller queue] isAudioOnly] && ![[controller playerViewController] isAudioOnly] &&
    [[controller player] rate]==1,@"Foreground restores video after inactive playlist advancement without pausing");
  for(AVPlayerItemTrack *track in [[[controller player] currentItem] tracks])
    if([[[track assetTrack] mediaType] isEqualToString:AVMediaTypeVideo])
      playbackRequire([track isEnabled],@"The advanced item's current video track is restored");
  [controller playerViewController:[controller playerViewController] didRequestAudioOnly:YES];
  [controller playerViewController:[controller playerViewController] didRequestAudioOnly:NO];
  for(AVPlayerItemTrack *track in [[[controller player] currentItem] tracks])
    if([[[track assetTrack] mediaType] isEqualToString:AVMediaTypeVideo])
      playbackRequire([track isEnabled],@"Manual Audio Only round trip also restores the advanced item");
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.1]];
  playbackRequire([[[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo objectForKey:MPMediaItemPropertyTitle] isEqualToString:@"CCCCCCCCCCC"],@"Now Playing follows the current playlist item");
  playbackSeek(controller.player,599.8);
  deadline=[NSDate dateWithTimeIntervalSinceNow:5];
  while(controller.player.rate!=0 && [deadline timeIntervalSinceNow]>0) playbackPump();
  playbackRequire(controller.queue.currentIndex==2 && controller.player.rate==0 &&
    [library playbackSecondsForVideo:@"CCCCCCCCCCC"]==0,@"Final item stops at the end without wrapping");
  [controller stop]; [controller release];
  URL=[[NSBundle mainBundle] URLForResource:@"playback-fixture" withExtension:@"mp4"];
  for(NSString *video in [NSArray arrayWithObjects:@"AAAAAAAAAAA",@"BBBBBBBBBBB",@"CCCCCCCCCCC",nil])
    [jobs addObject:[NSDictionary dictionaryWithObject:video forKey:@"video_id"]];
  controller=[[RDLPDownloadedPlayerViewController alloc] initWithLibrary:(RDLPLibrary *)library
    jobs:jobs URLs:[NSArray arrayWithObjects:URL,URL,URL,nil] startingAtIndex:1];
  [controller viewWillAppear:NO]; [controller viewDidAppear:NO]; playbackWait(controller);
  [[controller player] pause];
  for(NSUInteger route=0;route<([controller valueForKey:@"remoteCommands"]?3:2);++route) {
    if(route) [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    for(NSNumber *position in [NSArray arrayWithObjects:@4.9,@5,@5.1,nil]) {
      [controller selectIndex:1]; playbackWait(controller);
      playbackSeek([controller player],[position doubleValue]);
      if(route==2) playbackModernRemote(controller,YES);
      else if(route) playbackRemote(controller,UIEventSubtypeRemoteControlPreviousTrack);
      else [controller playerViewControllerDidRequestBack:[controller playerViewController]];
      playbackWait(controller);
      playbackRequire([[controller queue] currentIndex]==([position doubleValue]>5?1:0),
        @"Both routes restart after five seconds and select the previous short track otherwise");
    }
    [controller selectIndex:1]; playbackWait(controller);
    if(route==2) playbackModernRemote(controller,NO);
    else if(route) playbackRemote(controller,UIEventSubtypeRemoteControlNextTrack);
    else [controller playerViewControllerDidRequestForward:[controller playerViewController]];
    playbackWait(controller);
    playbackRequire([[controller queue] currentIndex]==2,@"Both routes select the next short track");
    if(route) [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  }
  NSURL *longURL=[[NSBundle mainBundle] URLForResource:@"playback-long-fixture" withExtension:@"mp4"];
  [[controller queue] setPlaylist:[NSArray arrayWithObjects:URL,longURL,URL,nil] startingAtIndex:0];
  playbackWait(controller); playbackCheckCommandConfiguration(controller,NO);
  [controller selectIndex:1]; playbackWait(controller); playbackCheckCommandConfiguration(controller,YES);
  [controller selectIndex:2]; playbackWait(controller); playbackCheckCommandConfiguration(controller,NO);
  [controller stop]; [controller release]; [library release];
  [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
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
  [controller endInterruptionWithFlags:1 /* ShouldResume has the same value on iOS 5 and newer. */];
  playbackRequire(controller.player.rate==1,@"Allowed interruption recovery resumes previously playing audio");
  [controller beginInterruption];
  [controller endInterruptionWithFlags:0];
  playbackRequire(controller.player.rate==0,@"Interruption without permission to resume stays paused");
  playbackRemote(controller,UIEventSubtypeRemoteControlPause);
  [controller beginInterruption]; [controller endInterruptionWithFlags:1 /* ShouldResume has the same value on iOS 5 and newer. */];
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
