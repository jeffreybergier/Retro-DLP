/* Exercise real progress observers and SQLite persistence with controlled legacy
   player readings, including the zero/earlier keyframe reported during pauses. */
@interface RDLPPlaybackProgress : UIViewController
- (id)initWithLibrary:(RDLPLibrary *)library video:(NSString *)video player:(AVPlayer *)player movie:(MPMoviePlayerController *)movie;
- (void)preparePlayback;
- (void)saveProgress:(id)sender;
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
@interface RDLPPlaybackTestMovie : NSObject {
  double time_, initial_;
  BOOL autoplay_;
  MPMoviePlaybackState state_;
}
@property(nonatomic) double currentPlaybackTime, initialPlaybackTime;
@property(nonatomic) BOOL shouldAutoplay;
@property(nonatomic) MPMoviePlaybackState playbackState;
- (double)duration;
- (MPMovieLoadState)loadState;
- (void)play;
- (void)notifyState;
@end
@implementation RDLPPlaybackTestMovie
@synthesize currentPlaybackTime=time_, initialPlaybackTime=initial_, shouldAutoplay=autoplay_, playbackState=state_;
- (double)duration; { return 120; }
- (MPMovieLoadState)loadState; { return MPMovieLoadStatePlayable; }
- (void)play; { state_=MPMoviePlaybackStatePlaying; [self notifyState]; }
- (void)notifyState;
{ [[NSNotificationCenter defaultCenter] postNotificationName:MPMoviePlayerPlaybackStateDidChangeNotification object:self]; }
@end
static void playbackRequire(BOOL condition,NSString *message) {
  if(!condition) [NSException raise:@"PlaybackTest" format:@"%@",message];
}
static void testIOSPlaybackProgress(NSString *directory) {
  [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  NSString *path=[directory stringByAppendingPathComponent:@"playback.sqlite"], *video=@"AAAAAAAAAAA";
  RDLPPlaybackTestLibrary *library=[[RDLPPlaybackTestLibrary alloc] initWithPath:path];
  RDLPPlaybackTestMovie *movie=[[RDLPPlaybackTestMovie alloc] init];
  RDLPPlaybackProgress *progress=[[RDLPPlaybackProgress alloc] initWithLibrary:(RDLPLibrary *)library video:video player:nil movie:(MPMoviePlayerController *)movie];
  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  [progress preparePlayback];
  movie.currentPlaybackTime=42; [movie notifyState];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"Seek completion saves before the ten-second timer");
  movie.playbackState=MPMoviePlaybackStatePaused; movie.currentPlaybackTime=0; [movie notifyState];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"A system pause before WillResignActive cannot erase a checkpoint");
  [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  movie.playbackState=MPMoviePlaybackStatePaused; movie.currentPlaybackTime=0; [movie notifyState];
  [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
  [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"Background pause and timer cannot replace a checkpoint with zero");
  movie.currentPlaybackTime=30; [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==42,@"Earlier paused keyframe cannot replace a checkpoint on foregrounding");
  [progress viewWillDisappear:NO]; [progress viewDidDisappear:NO];
  [progress release]; [movie release]; [library release];

  library=[[RDLPPlaybackTestLibrary alloc] initWithPath:path];
  movie=[[RDLPPlaybackTestMovie alloc] init];
  progress=[[RDLPPlaybackProgress alloc] initWithLibrary:(RDLPLibrary *)library video:video player:nil movie:(MPMoviePlayerController *)movie];
  playbackRequire(movie.initialPlaybackTime==42,@"Reopened database restores the last reliable position");
  [progress preparePlayback];
  [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  movie.currentPlaybackTime=55; [movie play];
  playbackRequire([library playbackSecondsForVideo:video]==55,@"Resumed background audio can advance its checkpoint");
  movie.currentPlaybackTime=56; [progress saveProgress:nil];
  playbackRequire([library playbackSecondsForVideo:video]==56,@"Timer continues saving resumed audio");
  [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  movie.playbackState=MPMoviePlaybackStateSeekingBackward; [movie notifyState];
  movie.currentPlaybackTime=5;
  movie.playbackState=MPMoviePlaybackStatePaused; [movie notifyState];
  playbackRequire([library playbackSecondsForVideo:video]==5,@"Intentional backward seek is still persisted");
  movie.playbackState=MPMoviePlaybackStateSeekingBackward; [movie notifyState];
  movie.currentPlaybackTime=0;
  movie.playbackState=MPMoviePlaybackStatePaused; [movie notifyState];
  playbackRequire([library playbackSecondsForVideo:video]==0,@"Intentional seek to the beginning is still persisted");
  movie.currentPlaybackTime=60; [movie play];
  [center postNotificationName:MPMoviePlayerPlaybackDidFinishNotification object:movie];
  playbackRequire([library playbackSecondsForVideo:video]==60,@"Missing finish reason does not mean playback ended");
  movie.currentPlaybackTime=120;
  [center postNotificationName:MPMoviePlayerPlaybackDidFinishNotification object:movie userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:MPMovieFinishReasonPlaybackEnded] forKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey]];
  playbackRequire([library playbackSecondsForVideo:video]==0,@"Natural completion resets the bookmark");
  [progress viewWillDisappear:NO]; [progress viewDidDisappear:NO];
  [progress release]; [movie release]; [library release];
}
