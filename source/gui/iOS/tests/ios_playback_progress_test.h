/* Exercise foreground checkpoint policy and SQLite persistence with controlled
   legacy player readings during seeks, pauses, and app lifecycle changes. */
@interface RDLPPlaybackProgress : UIViewController
- (id)initWithLibrary:(RDLPLibrary *)library video:(NSString *)video movie:(MPMoviePlayerController *)movie;
- (void)preparePlayback;
- (void)saveProgress:(id)sender;
- (void)configureNowPlayingWithJob:(NSDictionary *)job;
- (void)updateNowPlaying:(id)sender;
@end
@interface RDLPPlaybackTestLibrary : NSObject { rdapp_store *store_; }
- (id)initWithPath:(NSString *)path;
- (double)playbackSecondsForVideo:(NSString *)video;
- (void)savePlaybackSeconds:(double)seconds forVideo:(NSString *)video;
@end
@implementation RDLPPlaybackTestLibrary
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
}
@end
@interface RDLPPlaybackTestSlider : UISlider { BOOL testTracking_; }
@property(nonatomic) BOOL testTracking;
@end
@implementation RDLPPlaybackTestSlider
@synthesize testTracking=testTracking_;
- (BOOL)isTracking; { return testTracking_; }
@end
@interface RDLPPlaybackTestMovie : NSObject {
  double time_, initial_;
  BOOL autoplay_, started_;
  BOOL reentrantLoad_;
  NSUInteger seeks_;
  MPMoviePlaybackState state_;
  UIView *view_;
}
@property(nonatomic,retain) UIView *view;
@property(nonatomic) double currentPlaybackTime, initialPlaybackTime;
@property(nonatomic) BOOL shouldAutoplay;
@property(nonatomic) BOOL reentrantLoad;
@property(nonatomic,readonly) NSUInteger seeks;
@property(nonatomic) MPMoviePlaybackState playbackState;
- (double)duration;
- (float)currentPlaybackRate;
- (MPMovieLoadState)loadState;
- (void)play;
- (void)notifyState;
@end
@implementation RDLPPlaybackTestMovie
@synthesize view=view_;
- (void)dealloc; { [view_ release]; [super dealloc]; }
@synthesize initialPlaybackTime=initial_, shouldAutoplay=autoplay_, playbackState=state_, reentrantLoad=reentrantLoad_, seeks=seeks_;
- (double)currentPlaybackTime; { return time_; }
- (void)setCurrentPlaybackTime:(double)seconds;
{
  time_=seconds; ++seeks_;
  if(reentrantLoad_ && seeks_<3)
    [[NSNotificationCenter defaultCenter] postNotificationName:MPMoviePlayerLoadStateDidChangeNotification object:self];
}
- (double)duration; { return 120; }
- (float)currentPlaybackRate; { return 1; }
- (MPMovieLoadState)loadState; { return MPMovieLoadStatePlayable; }
- (void)play;
{ if(!started_) { time_=initial_; started_=YES; } state_=MPMoviePlaybackStatePlaying; [self notifyState]; }
- (void)notifyState;
{ [[NSNotificationCenter defaultCenter] postNotificationName:MPMoviePlayerPlaybackStateDidChangeNotification object:self]; }
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
static void testIOSPlaybackProgress(NSString *directory) {
  [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  NSString *path=[directory stringByAppendingPathComponent:@"playback.sqlite"], *video=@"AAAAAAAAAAA";
  RDLPPlaybackTestLibrary *library=[[RDLPPlaybackTestLibrary alloc] initWithPath:path];
  RDLPPlaybackTestMovie *movie=[[RDLPPlaybackTestMovie alloc] init];
  movie.reentrantLoad=YES;
  RDLPPlaybackProgress *progress=[[RDLPPlaybackProgress alloc] initWithLibrary:(RDLPLibrary *)library video:video movie:(MPMoviePlayerController *)movie];
  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  [progress preparePlayback];
  playbackRequire(movie.seeks==1,@"A synchronous load notification cannot repeat the startup seek");
  playbackRequire(!movie.shouldAutoplay && movie.playbackState!=MPMoviePlaybackStatePlaying,@"Preparing the movie waits for the user's Play action");
  [movie play];
  movie.reentrantLoad=NO;
  movie.currentPlaybackTime=42; [movie notifyState];
  playbackRequire([library playbackSecondsForVideo:video]==0,@"State notifications do not save positions");
  [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"Foreground playback saves on a timer tick");
  [progress viewDidAppear:NO];
  NSTimer *timer=[progress valueForKey:@"timer_"];
  movie.currentPlaybackTime=43; [timer setFireDate:[NSDate distantPast]];
  [[NSRunLoop currentRunLoop] runMode:UITrackingRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"Touch tracking suppresses timer saves even if the player still reports Playing");
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  playbackRequire([library playbackSecondsForVideo:video]==43,@"Timer resumes after touch tracking ends");
  [timer invalidate];
  movie.currentPlaybackTime=42; [progress saveProgress:nil];
  movie.view=[[[UIView alloc] initWithFrame:CGRectZero] autorelease];
  RDLPPlaybackTestSlider *slider=[[[RDLPPlaybackTestSlider alloc] initWithFrame:CGRectZero] autorelease];
  [movie.view addSubview:slider]; slider.testTracking=YES;
  movie.currentPlaybackTime=110; [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"A held scrubber prevents saves even outside tracking run-loop mode");
  slider.testTracking=NO;
  movie.playbackState=MPMoviePlaybackStateSeekingForward; movie.currentPlaybackTime=110;
  [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"Scrubbing into the final ten percent cannot reset a checkpoint");
  movie.playbackState=MPMoviePlaybackStateSeekingBackward; movie.currentPlaybackTime=5;
  [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"Backward scrubbing does not save");
  movie.playbackState=MPMoviePlaybackStatePaused; movie.currentPlaybackTime=0; [movie notifyState];
  [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"Paused readings do not save");
  movie.playbackState=MPMoviePlaybackStatePlaying;
  [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"Becoming inactive does not save a transient zero");
  movie.currentPlaybackTime=55;
  [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
  [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"Background audio does not advance the bookmark");
  NSDictionary *finished=[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:MPMovieFinishReasonPlaybackEnded] forKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
  [center postNotificationName:MPMoviePlayerPlaybackDidFinishNotification object:movie userInfo:finished];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"Background completion does not change the bookmark");
  [progress viewWillDisappear:NO]; [progress viewDidDisappear:NO];
  [progress release]; [movie release]; [library release];

  library=[[RDLPPlaybackTestLibrary alloc] initWithPath:path];
  movie=[[RDLPPlaybackTestMovie alloc] init];
  progress=[[RDLPPlaybackProgress alloc] initWithLibrary:(RDLPLibrary *)library video:video movie:(MPMoviePlayerController *)movie];
  playbackRequire(movie.initialPlaybackTime==42,@"Reopened database restores the last foreground checkpoint");
  [progress preparePlayback];
  playbackRequire(movie.currentPlaybackTime==42 && movie.playbackState!=MPMoviePlaybackStatePlaying,@"Restoring the bookmark does not start playback");
  [movie play];
  [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  movie.currentPlaybackTime=5; [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==5,@"Foreground playback after a backward seek saves its new position");
  movie.currentPlaybackTime=0; [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==0,@"Foreground playback can save the beginning");
  movie.currentPlaybackTime=107.9; [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==107.9,@"A position before ninety percent still resumes");
  movie.currentPlaybackTime=108; [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==0,@"Exactly ninety percent restarts next time");
  movie.currentPlaybackTime=119; [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==0,@"Later playback keeps saving zero");
  movie.currentPlaybackTime=60; [progress saveProgress:nil];
  [center postNotificationName:MPMoviePlayerPlaybackDidFinishNotification object:movie];
  playbackRequire([library playbackSecondsForVideo:video]==60,@"Missing finish reason does not mean playback ended");
  movie.playbackState=MPMoviePlaybackStateStopped;
  [center postNotificationName:MPMoviePlayerPlaybackDidFinishNotification object:movie userInfo:finished];
  playbackRequire([library playbackSecondsForVideo:video]==0,@"Foreground natural completion resets the bookmark even between timer ticks");
  [progress viewDidDisappear:NO];
  movie.playbackState=MPMoviePlaybackStatePlaying; movie.currentPlaybackTime=70; [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==0,@"Dismissed player cannot save again");
  [progress release]; [movie release];

  [library savePlaybackSeconds:110 forVideo:video];
  movie=[[RDLPPlaybackTestMovie alloc] init];
  progress=[[RDLPPlaybackProgress alloc] initWithLibrary:(RDLPLibrary *)library video:video movie:(MPMoviePlayerController *)movie];
  [progress preparePlayback];
  playbackRequire(movie.initialPlaybackTime==0 && movie.currentPlaybackTime==0,@"Old checkpoints in the final ten percent also start over");
  [progress release]; [movie release]; [library release];
}

static NSDictionary *playbackNowPlayingInfo(void) {
  /* Legacy MediaPlayer coalesces metadata writes; allow its update to settle. */
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.1]];
  return [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo;
}
/* Metadata must follow background transport independently of saved bookmarks. */
static void testIOSNowPlaying(NSString *directory) {
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  RDLPPlaybackTestLibrary *library=[[RDLPPlaybackTestLibrary alloc] initWithPath:[directory stringByAppendingPathComponent:@"now-playing.sqlite"]];
  RDLPPlaybackTestMovie *movie=[[RDLPPlaybackTestMovie alloc] init];
  RDLPPlaybackProgress *progress=[[RDLPPlaybackProgress alloc] initWithLibrary:(RDLPLibrary *)library video:@"AAAAAAAAAAA" movie:(MPMoviePlayerController *)movie];
  [progress configureNowPlayingWithJob:[NSDictionary dictionaryWithObjectsAndKeys:@"Video title",@"title",@"Channel name",@"channel",nil]];
  [progress preparePlayback];
  [movie play];
  NSNotificationCenter *notifications=[NSNotificationCenter defaultCenter];
  [notifications postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  movie.currentPlaybackTime=42; [movie notifyState];
  playbackRequire([[playbackNowPlayingInfo() objectForKey:MPMediaItemPropertyTitle] isEqualToString:@"Video title"] &&
    [[playbackNowPlayingInfo() objectForKey:MPMediaItemPropertyArtist] isEqualToString:@"Channel name"],@"Background metadata retains title and channel");
  playbackRequire([[playbackNowPlayingInfo() objectForKey:MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue]==42 &&
    [[playbackNowPlayingInfo() objectForKey:MPNowPlayingInfoPropertyPlaybackRate] doubleValue]==1,@"Background playback publishes live position and rate");
  [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:@"AAAAAAAAAAA"]==0,@"Now Playing does not change the background bookmark policy");
  movie.playbackState=MPMoviePlaybackStatePaused; [movie notifyState];
  playbackRequire([[playbackNowPlayingInfo() objectForKey:MPNowPlayingInfoPropertyPlaybackRate] doubleValue]==0,@"Background pause freezes elapsed time");
  movie.currentPlaybackTime=12;
  NSTimer *tick=[NSTimer timerWithTimeInterval:1 target:progress selector:@selector(updateNowPlaying:) userInfo:nil repeats:NO];
  [progress updateNowPlaying:tick];
  playbackRequire([[playbackNowPlayingInfo() objectForKey:MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue]==12,@"A seek without a state notification refreshes elapsed time");
  movie.currentPlaybackTime=NAN; [movie notifyState];
  playbackRequire([[playbackNowPlayingInfo() objectForKey:MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue]==12,@"Invalid time readings preserve the last valid position");
  NSDictionary *ended=[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:MPMovieFinishReasonPlaybackEnded] forKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
  [notifications postNotificationName:MPMoviePlayerPlaybackDidFinishNotification object:movie userInfo:ended];
  [progress updateNowPlaying:tick];
  playbackRequire(![playbackNowPlayingInfo() count],@"Completion clears metadata and timer ticks cannot republish it");
  movie.currentPlaybackTime=0; [movie play];
  playbackRequire([playbackNowPlayingInfo() count]>0,@"Replaying a finished movie restores metadata");
  RDLPPlaybackTestMovie *nextMovie=[[RDLPPlaybackTestMovie alloc] init];
  RDLPPlaybackProgress *next=[[RDLPPlaybackProgress alloc] initWithLibrary:(RDLPLibrary *)library video:@"AAAAAAAAAAA" movie:(MPMoviePlayerController *)nextMovie];
  [next configureNowPlayingWithJob:[NSDictionary dictionary]];
  [progress viewDidDisappear:NO]; [progress release]; [movie release];
  playbackRequire([[playbackNowPlayingInfo() objectForKey:MPMediaItemPropertyTitle] isEqualToString:@"AAAAAAAAAAA"] &&
    ![playbackNowPlayingInfo() objectForKey:MPMediaItemPropertyArtist],@"Replacement survives old-player teardown, falls back to video ID, and drops old artist");
  NSDictionary *error=[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:MPMovieFinishReasonPlaybackError] forKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
  [notifications postNotificationName:MPMoviePlayerPlaybackDidFinishNotification object:nextMovie userInfo:error];
  playbackRequire(![playbackNowPlayingInfo() count],@"Playback errors clear metadata");
  [next release]; [nextMovie release]; [library release];
  [notifications postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
}
