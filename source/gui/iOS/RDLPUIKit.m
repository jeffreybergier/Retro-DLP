#import "RDLPUIKit.h"
#import "RDLPStatusBarView.h"
#import "RDLPLibrary.h"
#import <AIFontAwesome.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
/* Check public control state without attaching handlers to native controls. */
static BOOL RDLPPlayerIsTracking(UIView *view) {
  if([view isKindOfClass:[UIControl class]] && [(UIControl *)view isTracking]) return YES;
  for(UIView *child in view.subviews) if(RDLPPlayerIsTracking(child)) return YES;
  return NO;
}
/* A child receives the native player's appearance lifecycle on iOS 5 and up.
   It owns progress tracking without changing the player's controls. */
@interface RDLPPlaybackProgress : UIViewController {
  RDLPLibrary *library_;
  NSString *video_;
  MPMoviePlayerController *movie_;
  NSTimer *timer_;
  NSTimer *nowPlayingTimer_;
  NSDictionary *metadata_;
  double publishedTime_, publishedRate_, publishedDuration_;
  NSTimeInterval publishedAt_;
  BOOL published_, finished_;
  double resume_;
  BOOL ready_, preparing_, stopped_, foregroundActive_;
}
- (id)initWithLibrary:(RDLPLibrary *)library video:(NSString *)video movie:(MPMoviePlayerController *)movie;
- (void)preparePlayback;
- (void)saveProgress:(id)sender;
- (void)configureNowPlayingWithJob:(NSDictionary *)job;
- (void)updateNowPlaying:(id)sender;
- (void)clearNowPlaying;
@end
/* Nonretained: an older player's teardown must not erase its replacement. */
static RDLPPlaybackProgress *RDLPNowPlayingOwner=nil;
/* NSTimer retains its target; this forwarding target avoids retaining the
   child controller after its native player has been released. */
@interface RDLPPlaybackTimerTarget : NSObject {
@public
  RDLPPlaybackProgress *progress;
}
- (void)tick:(NSTimer *)timer;
- (void)nowPlayingTick:(NSTimer *)timer;
@end
@implementation RDLPPlaybackTimerTarget
- (void)tick:(NSTimer *)timer; { [progress saveProgress:timer]; }
- (void)nowPlayingTick:(NSTimer *)timer; { [progress updateNowPlaying:timer]; }
@end
@implementation RDLPPlaybackProgress
- (id)initWithLibrary:(RDLPLibrary *)library video:(NSString *)video movie:(MPMoviePlayerController *)movie;
{
  self=[super initWithNibName:nil bundle:nil]; if(!self) return nil;
  library_=[library retain]; video_=[video copy]; movie_=[movie retain];
  resume_=[library playbackSecondsForVideo:video];
  foregroundActive_=([UIApplication sharedApplication].applicationState==UIApplicationStateActive);
  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(willResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
  [center addObserver:self selector:@selector(didBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
  movie_.shouldAutoplay=NO;
  movie_.initialPlaybackTime=resume_;
  [center addObserver:self selector:@selector(movieLoaded:) name:MPMoviePlayerLoadStateDidChangeNotification object:movie_];
  [center addObserver:self selector:@selector(movieFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:movie_];
  [center addObserver:self selector:@selector(movieStateChanged:) name:MPMoviePlayerPlaybackStateDidChangeNotification object:movie_];
  [center addObserver:self selector:@selector(updateNowPlaying:) name:MPMovieDurationAvailableNotification object:movie_];
  [center addObserver:self selector:@selector(updateNowPlaying:) name:UIApplicationDidEnterBackgroundNotification object:nil];
  return self;
}
- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [timer_ invalidate]; [timer_ release];
  [nowPlayingTimer_ invalidate]; [nowPlayingTimer_ release];
  [self clearNowPlaying]; [metadata_ release];
  [library_ release]; [video_ release]; [movie_ release];
  [super dealloc];
}
- (void)loadView;
{
  self.view=[[[UIView alloc] initWithFrame:CGRectZero] autorelease];
  self.view.userInteractionEnabled=NO;
}
- (void)viewDidAppear:(BOOL)animated;
{
  [super viewDidAppear:animated];
  if(!timer_ && !stopped_) {
    RDLPPlaybackTimerTarget *target=[[[RDLPPlaybackTimerTarget alloc] init] autorelease];
    target->progress=self;
    timer_=[[NSTimer timerWithTimeInterval:10 target:target selector:@selector(tick:) userInfo:nil repeats:YES] retain];
    /* Also suspend timer delivery whenever UIKit uses touch-tracking mode. */
    [[NSRunLoop mainRunLoop] addTimer:timer_ forMode:NSDefaultRunLoopMode];
  }
  if(metadata_ && !nowPlayingTimer_ && !stopped_) {
    RDLPPlaybackTimerTarget *target=[[[RDLPPlaybackTimerTarget alloc] init] autorelease];
    target->progress=self;
    /* MPMoviePlayer has no public seek-completed notification. Check for
       discontinuities, including paused scrubs, without republishing each tick. */
    nowPlayingTimer_=[[NSTimer timerWithTimeInterval:1 target:target selector:@selector(nowPlayingTick:) userInfo:nil repeats:YES] retain];
    [[NSRunLoop mainRunLoop] addTimer:nowPlayingTimer_ forMode:NSRunLoopCommonModes];
  }
  [self updateNowPlaying:nil];
}
- (void)viewWillDisappear:(BOOL)animated;
{
  [self saveProgress:nil];
  [super viewWillDisappear:animated];
}
- (void)viewDidDisappear:(BOOL)animated;
{
  stopped_=YES;
  [timer_ invalidate]; [timer_ release]; timer_=nil;
  [nowPlayingTimer_ invalidate]; [nowPlayingTimer_ release]; nowPlayingTimer_=nil;
  [self clearNowPlaying];
  [super viewDidDisappear:animated];
}
- (void)movieLoaded:(NSNotification *)notification;
{ [self preparePlayback]; [self updateNowPlaying:notification]; }
- (void)preparePlayback;
{
  if(stopped_ || ready_ || preparing_) return;
  if(!(movie_.loadState & MPMovieLoadStatePlayable)) return;
  double duration=movie_.duration;
  preparing_=YES;
  if(isfinite(duration) && duration>0 && resume_>=duration*0.9) {
    resume_=0; movie_.initialPlaybackTime=0;
  }
  /* The controller can start loading before initialPlaybackTime is set.
     Apply one seek when playable; preparing_ prevents load-event reentry
     without saving a transient position from its synchronous notifications. */
  movie_.currentPlaybackTime=resume_;
  ready_=YES; preparing_=NO;
  /* The native Play button starts playback after the resume position is ready. */
  [self updateNowPlaying:nil];
}
- (void)willResignActive:(NSNotification *)notification;
{
  (void)notification; foregroundActive_=NO;
  [self updateNowPlaying:nil];
}
- (void)didBecomeActive:(NSNotification *)notification;
{
  (void)notification; foregroundActive_=YES;
  [self updateNowPlaying:nil];
}
- (void)configureNowPlayingWithJob:(NSDictionary *)job;
{
  NSString *title=[job objectForKey:@"title"], *channel=[job objectForKey:@"channel"];
  if(![title length]) title=[video_ length]?video_:@"Video";
  NSMutableDictionary *info=[NSMutableDictionary dictionaryWithObject:title forKey:MPMediaItemPropertyTitle];
  if([channel length]) [info setObject:channel forKey:MPMediaItemPropertyArtist];
  [metadata_ release]; metadata_=[info copy];
  RDLPNowPlayingOwner=self;
  [self updateNowPlaying:nil];
}
- (void)clearNowPlaying;
{
  if(RDLPNowPlayingOwner==self) {
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo=nil;
    RDLPNowPlayingOwner=nil;
  }
  published_=NO;
}
- (void)movieStateChanged:(NSNotification *)notification;
{
  if(movie_.playbackState==MPMoviePlaybackStatePlaying) {
    if(finished_ && !stopped_ && !RDLPNowPlayingOwner) RDLPNowPlayingOwner=self;
    finished_=NO;
  }
  [self updateNowPlaying:notification];
}
- (void)updateNowPlaying:(id)sender;
{
  if(stopped_ || preparing_ || finished_ || !metadata_ || RDLPNowPlayingOwner!=self) return;
  double seconds=ready_?movie_.currentPlaybackTime:resume_, duration=movie_.duration;
  if(!isfinite(seconds) || seconds<0) seconds=published_?publishedTime_:resume_;
  if(!isfinite(duration) || duration<=0) duration=0;
  if(duration>0) seconds=MIN(seconds,duration);
  double rate=0;
  if(movie_.playbackState==MPMoviePlaybackStatePlaying && !(movie_.loadState & MPMovieLoadStateStalled)) {
    rate=movie_.currentPlaybackRate;
    if(!isfinite(rate)) rate=0;
  }
  NSTimeInterval now=[NSProcessInfo processInfo].systemUptime;
  double expected=publishedTime_+(now-publishedAt_)*publishedRate_;
  if([sender isKindOfClass:[NSTimer class]] && published_ && rate==publishedRate_ &&
     duration==publishedDuration_ && fabs(seconds-expected)<0.75) return;
  NSMutableDictionary *info=[[metadata_ mutableCopy] autorelease];
  [info setObject:[NSNumber numberWithDouble:seconds] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
  [info setObject:[NSNumber numberWithDouble:rate] forKey:MPNowPlayingInfoPropertyPlaybackRate];
  if(duration>0) [info setObject:[NSNumber numberWithDouble:duration] forKey:MPMediaItemPropertyPlaybackDuration];
  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo=info;
  published_=YES; publishedTime_=seconds; publishedRate_=rate; publishedDuration_=duration; publishedAt_=now;
}
- (void)saveProgress:(id)sender;
{
  (void)sender;
  if(stopped_ || !ready_ || !foregroundActive_ ||
     [UIApplication sharedApplication].applicationState!=UIApplicationStateActive ||
     movie_.playbackState!=MPMoviePlaybackStatePlaying || RDLPPlayerIsTracking(movie_.view)) return;
  double seconds=movie_.currentPlaybackTime;
  double duration=movie_.duration;
  if(!isfinite(seconds) || seconds<0) return;
  /* Treat the final ten percent as watched, including credits. */
  if(isfinite(duration) && duration>0 && seconds>=duration*0.9) seconds=0;
  [library_ savePlaybackSeconds:seconds forVideo:video_];
}
- (void)playbackEnded:(NSNotification *)notification;
{
  (void)notification;
  if(stopped_ || !ready_ || !foregroundActive_ ||
     [UIApplication sharedApplication].applicationState!=UIApplicationStateActive || RDLPPlayerIsTracking(movie_.view)) return;
  movie_.initialPlaybackTime=0; [library_ savePlaybackSeconds:0 forVideo:video_];
}
- (void)movieFinished:(NSNotification *)notification;
{
  NSNumber *reason=[[notification userInfo] objectForKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
  if(reason && [reason integerValue]==MPMovieFinishReasonPlaybackEnded)
    [self playbackEnded:notification];
  finished_=YES;
  [self clearNowPlaying];
}
@end
static void RDLPTrackPlayback(MPMoviePlayerViewController *controller,RDLPLibrary *library,NSDictionary *job) {
  MPMoviePlayerController *movie=controller.moviePlayer;
  RDLPPlaybackProgress *progress=[[RDLPPlaybackProgress alloc] initWithLibrary:library video:[job objectForKey:@"video_id"] movie:movie];
  [progress configureNowPlayingWithJob:job];
  [controller addChildViewController:progress];
  [controller.view addSubview:progress.view];
  [progress didMoveToParentViewController:controller];
  [movie prepareToPlay];
  [progress preparePlayback];
  [progress release];
}
/* Keep raster pixels and UIImage.scale tied to the same display scale.
   AIFontAwesome also accepts zero for this, but the cache needs the resolved
   value so images created at another screen scale cannot be reused. */
static CGFloat RDLPMainScreenScale(void) {
  CGFloat scale=[[UIScreen mainScreen] scale];
  return isfinite(scale) && scale>=1.0?scale:1.0;
}
/* Preserve the glyph color for iOS 5/6, where template rendering is unavailable.
   The selector guard keeps explicit iOS 7 template mode safe on those systems. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
static UIImage *RDLPFontAwesomeImageWithOffset(AIFontAwesomeIcon icon,CGFloat size,CGFloat canvas,CGFloat scale,UIColor *color,CGFloat verticalOffset) {
  UIImage *image=[AIFontAwesome imageForIcon:icon style:AIFontAwesomeStyleSolid
    iconSize:size canvasSize:canvas color:color scale:scale];
  if(image && verticalOffset!=0) {
    UIGraphicsBeginImageContextWithOptions(image.size,NO,image.scale);
    [image drawAtPoint:CGPointMake(0,verticalOffset)];
    image=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
  }
  if([image respondsToSelector:@selector(imageWithRenderingMode:)])
    image=[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
  return image;
}
#pragma clang diagnostic pop
static UIImage *RDLPFontAwesomeImage(AIFontAwesomeIcon icon,CGFloat size,CGFloat canvas,CGFloat scale,UIColor *color) {
  return RDLPFontAwesomeImageWithOffset(icon,size,canvas,scale,color,0);
}
@implementation RDLPUIKit
+ (void)configureContentEdges:(UIViewController *)controller;
{
  /* iOS 7 introduced extended edges. KVC preserves the iOS 5 deployment path. */
  if([controller respondsToSelector:@selector(setEdgesForExtendedLayout:)])
    [controller setValue:[NSNumber numberWithUnsignedInteger:0] forKey:@"edgesForExtendedLayout"];
}
+ (UIImage *)statusIcon:(NSString *)status;
{
  static NSMutableDictionary *images=nil;
  if(!images) images=[[NSMutableDictionary alloc] init];
  CGFloat scale=RDLPMainScreenScale();
  NSArray *key=[NSArray arrayWithObjects:status,[NSNumber numberWithDouble:scale],nil];
  UIImage *cached=[images objectForKey:key]; if(cached) return cached;
  AIFontAwesomeIcon icon=AIFATriangleExclamation;
  if([status isEqualToString:@"Downloaded"]) icon=AIFACircleCheck;
  else if([status isEqualToString:@"Downloading"] || [status isEqualToString:@"Queued"]) icon=AIFAHourglass;
  else if([status isEqualToString:@"Not downloaded"]) icon=AIFADownload;
  UIImage *image=RDLPFontAwesomeImage(icon,14,18,scale,[UIColor blackColor]);
  if(image) [images setObject:image forKey:key]; return image;
}
+ (UIImage *)queueActionIcon:(BOOL)stop;
{ return RDLPFontAwesomeImage(stop?AIFAPause:AIFARotateRight,14,20,RDLPMainScreenScale(),[UIColor whiteColor]); }

+ (UIImage *)settingsIcon;
{ return RDLPFontAwesomeImageWithOffset(AIFAGear,18,26,RDLPMainScreenScale(),[UIColor whiteColor],-1); }

+ (UIImage *)plusIcon;
{
  /* Font Awesome "plus"; this bundled header names U+F067 AIFAStd12. */
  return RDLPFontAwesomeImageWithOffset((AIFontAwesomeIcon)0xF067,18,26,RDLPMainScreenScale(),[UIColor whiteColor],-1); }

+ (UIImage *)queueToolbarIcon;
{
  /* Lift the glyph within its canvas to align with the legacy bordered button.
   * Keep the same optical adjustment on every iOS version. */
  return RDLPFontAwesomeImageWithOffset(AIFAListCheck,18,28,RDLPMainScreenScale(),[UIColor whiteColor],-1);
}

+ (UIImage *)syncIcon;
{ return RDLPFontAwesomeImageWithOffset(AIFAArrowsRotate,18,26,RDLPMainScreenScale(),[UIColor whiteColor],-1); }

+ (NSArray *)statusToolbarItems:(RDLPStatusBarView *)status target:(id)target queueAction:(SEL)action;
{
  /* Reserve the spinner slot even when it is hidden so hidesWhenStopped never
   * changes the message layout. Let UIKit size the native Queue button. */
  UIView *spinnerSlot=[[[UIView alloc] initWithFrame:CGRectMake(0,0,36,30)] autorelease];
  status.spinner.center=CGPointMake(18,15);
  [spinnerSlot addSubview:status.spinner];
  UIBarButtonItem *activity=[[[UIBarButtonItem alloc] initWithCustomView:spinnerSlot] autorelease];
  UIBarButtonItem *left=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
  UIBarButtonItem *right=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
  UIBarButtonItem *message=[[[UIBarButtonItem alloc] initWithCustomView:status] autorelease];
  if(!action) {
    UIView *emptySlot=[[[UIView alloc] initWithFrame:CGRectMake(0,0,36,30)] autorelease];
    UIBarButtonItem *empty=[[[UIBarButtonItem alloc] initWithCustomView:emptySlot] autorelease];
    return [NSArray arrayWithObjects:activity,left,message,right,empty,nil];
  }
  UIBarButtonItem *queue=[[[UIBarButtonItem alloc] initWithImage:[self queueToolbarIcon] style:UIBarButtonItemStyleBordered target:target action:action] autorelease];
  queue.accessibilityLabel=@"Download Queue";
  return [NSArray arrayWithObjects:activity,left,message,right,queue,nil];
}

+ (void)showMessage:(NSString *)message; {
  UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"RetroDLP" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
  [alert show]; [alert release];
}
+ (void)presentPlayer:(UIViewController *)owner library:(RDLPLibrary *)library job:(NSDictionary *)job; {
  NSString *path=[library fileForJob:job];
  if(!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { [self showMessage:@"The downloaded file is missing. Retry its download from Queue."]; return; }
  /* Activate only when opening a video, so browsing the library does not
     interrupt other audio. Keep the session available in the background for
     the native player's system playback controls. Both calls support iOS 5. */
  AVAudioSession *session=[AVAudioSession sharedInstance]; NSError *error=nil;
  if(![session setCategory:AVAudioSessionCategoryPlayback error:&error])
    NSLog(@"Could not configure playback audio session: %@",error);
  error=nil;
  if(![session setActive:YES error:&error])
    NSLog(@"Could not activate playback audio session: %@",error);
  NSURL *url=[NSURL fileURLWithPath:path];
  MPMoviePlayerViewController *controller=[[MPMoviePlayerViewController alloc] initWithContentURL:url];
  RDLPTrackPlayback(controller,library,job);
  [owner presentMoviePlayerViewControllerAnimated:controller]; [controller release];
}
+ (UIBarButtonItem *)item:(NSString *)title target:(id)target action:(SEL)action;
{ return [[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:target action:action] autorelease]; }
@end
#pragma clang diagnostic pop
