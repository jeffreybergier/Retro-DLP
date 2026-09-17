#import "RDLPUIKit.h"
#import "RDLPStatusBarView.h"
#import "RDLPLibrary.h"
#import <AIFontAwesome.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
/* A child receives the native player's appearance lifecycle on iOS 5 and up.
   It owns progress tracking without changing either player's controls. */
@interface RDLPPlaybackProgress : UIViewController {
  RDLPLibrary *library_;
  NSString *video_;
  AVPlayer *player_;
  MPMoviePlayerController *movie_;
  NSTimer *timer_;
  MPMoviePlaybackState lastMovieState_;
  double resume_, lastPosition_;
  BOOL ready_, preparing_, stopped_, ended_, preservePausedPosition_;
}
- (id)initWithLibrary:(RDLPLibrary *)library video:(NSString *)video player:(AVPlayer *)player movie:(MPMoviePlayerController *)movie;
- (void)preparePlayback;
- (void)seekFinished:(NSNumber *)finished;
- (void)saveProgress:(id)sender;
@end
/* NSTimer retains its target; this forwarding target avoids retaining the
   child controller after its native player has been released. */
@interface RDLPPlaybackTimerTarget : NSObject {
@public
  RDLPPlaybackProgress *progress;
}
- (void)tick:(NSTimer *)timer;
@end
@implementation RDLPPlaybackTimerTarget
- (void)tick:(NSTimer *)timer; { [progress saveProgress:timer]; }
@end
@implementation RDLPPlaybackProgress
- (id)initWithLibrary:(RDLPLibrary *)library video:(NSString *)video player:(AVPlayer *)player movie:(MPMoviePlayerController *)movie;
{
  self=[super initWithNibName:nil bundle:nil]; if(!self) return nil;
  library_=[library retain]; video_=[video copy]; player_=[player retain]; movie_=[movie retain];
  resume_=lastPosition_=[library playbackSecondsForVideo:video];
  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(willResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
  [center addObserver:self selector:@selector(saveProgress:) name:UIApplicationDidEnterBackgroundNotification object:nil];
  if(movie_) {
    movie_.shouldAutoplay=NO;
    movie_.initialPlaybackTime=resume_;
    [center addObserver:self selector:@selector(movieLoaded:) name:MPMoviePlayerLoadStateDidChangeNotification object:movie_];
    [center addObserver:self selector:@selector(movieFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:movie_];
    [center addObserver:self selector:@selector(movieStateChanged:) name:MPMoviePlayerPlaybackStateDidChangeNotification object:movie_];
  } else {
    [player_.currentItem addObserver:self forKeyPath:@"status" options:0 context:NULL];
    [center addObserver:self selector:@selector(playbackEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:player_.currentItem];
  }
  return self;
}
- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  if(player_) [player_.currentItem removeObserver:self forKeyPath:@"status"];
  [timer_ invalidate]; [timer_ release];
  [library_ release]; [video_ release]; [player_ release]; [movie_ release];
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
    [[NSRunLoop mainRunLoop] addTimer:timer_ forMode:NSRunLoopCommonModes];
  }
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
  [super viewDidDisappear:animated];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
  (void)keyPath; (void)object; (void)change; (void)context;
  [self performSelectorOnMainThread:@selector(preparePlayback) withObject:nil waitUntilDone:NO];
}
- (void)movieLoaded:(NSNotification *)notification;
{ (void)notification; [self preparePlayback]; }
- (void)preparePlayback;
{
  if(stopped_ || ready_ || preparing_) return;
  if(movie_) {
    if(!(movie_.loadState & MPMovieLoadStatePlayable)) return;
    double duration=movie_.duration;
    if(isfinite(duration) && duration>0 && resume_>=duration) resume_=0;
    movie_.initialPlaybackTime=resume_;
    movie_.currentPlaybackTime=resume_;
    ready_=YES; [movie_ play];
  } else {
    if(player_.currentItem.status!=AVPlayerItemStatusReadyToPlay) return;
    double duration=CMTimeGetSeconds(player_.currentItem.duration);
    if(isfinite(duration) && duration>0 && resume_>=duration) resume_=0;
    /* Mark the seek in flight, but do not persist the initial zero position. */
    preparing_=YES;
    [player_ seekToTime:CMTimeMakeWithSeconds(resume_,600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
      [self performSelectorOnMainThread:@selector(seekFinished:) withObject:[NSNumber numberWithBool:finished] waitUntilDone:NO];
    }];
  }
}
- (void)seekFinished:(NSNumber *)finished;
{
  preparing_=NO;
  if(stopped_ || ![finished boolValue]) return;
  ready_=YES; [player_ play];
}
- (void)willResignActive:(NSNotification *)notification;
{
  /* The legacy player can report an earlier keyframe (including zero) while
     pausing/backgrounding or returning to the foreground. Keep its checkpoint
     until playback or an explicit seek makes its position reliable again. */
  preservePausedPosition_=YES;
  [self saveProgress:notification];
}
- (void)movieStateChanged:(NSNotification *)notification;
{
  MPMoviePlaybackState state=movie_.playbackState;
  if(state==MPMoviePlaybackStateSeekingForward || state==MPMoviePlaybackStateSeekingBackward) {
    /* The initial seeking notification still contains the old position. */
    preservePausedPosition_=NO; lastMovieState_=state; return;
  }
  if(state==MPMoviePlaybackStatePlaying)
    preservePausedPosition_=NO;
  else if(lastMovieState_!=MPMoviePlaybackStateSeekingForward && lastMovieState_!=MPMoviePlaybackStateSeekingBackward &&
          (!isfinite(movie_.currentPlaybackTime) || movie_.currentPlaybackTime<lastPosition_))
    /* iOS 6 may deliver its pause before WillResignActive. Only a seek should
       move a paused checkpoint backwards; a system pause must not do so. */
    preservePausedPosition_=YES;
  /* Checkpoint seek completion and pause immediately: the user can background
     and force-quit before the next ten-second timer fires. */
  [self saveProgress:notification];
  lastMovieState_=state;
}
- (void)saveProgress:(id)sender;
{
  (void)sender;
  if(stopped_ || !ready_) return;
  double seconds=movie_?movie_.currentPlaybackTime:CMTimeGetSeconds(player_.currentTime);
  double duration=movie_?movie_.duration:CMTimeGetSeconds(player_.currentItem.duration);
  if(movie_ && movie_.playbackState!=MPMoviePlaybackStatePlaying &&
     movie_.playbackState!=MPMoviePlaybackStateSeekingForward && movie_.playbackState!=MPMoviePlaybackStateSeekingBackward &&
     lastMovieState_!=MPMoviePlaybackStateSeekingForward && lastMovieState_!=MPMoviePlaybackStateSeekingBackward &&
     (preservePausedPosition_ || [UIApplication sharedApplication].applicationState!=UIApplicationStateActive)) {
    if(!isfinite(seconds) || seconds<lastPosition_) seconds=lastPosition_;
  }
  if(!isfinite(seconds) || seconds<0) return;
  if(ended_) {
    BOOL playing=movie_?movie_.playbackState==MPMoviePlaybackStatePlaying:player_.rate>0;
    if(!playing || seconds>=duration) return;
    ended_=NO;
  }
  /* Keep a resume point when stopped early; a completed video starts over. */
  lastPosition_=(isfinite(duration) && duration>0 && seconds>=duration)?0:seconds;
  [library_ savePlaybackSeconds:lastPosition_ forVideo:video_];
}
- (void)playbackEnded:(NSNotification *)notification;
{
  (void)notification; if(stopped_) return;
  ended_=YES; lastPosition_=0; movie_.initialPlaybackTime=0; [library_ savePlaybackSeconds:0 forVideo:video_];
}
- (void)movieFinished:(NSNotification *)notification;
{
  NSNumber *reason=[[notification userInfo] objectForKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
  if(reason && [reason integerValue]==MPMovieFinishReasonPlaybackEnded)
    [self playbackEnded:notification];
  else [self saveProgress:nil];
}
@end
static void RDLPTrackPlayback(UIViewController *controller,RDLPLibrary *library,NSString *video,AVPlayer *player,MPMoviePlayerController *movie) {
  RDLPPlaybackProgress *progress=[[RDLPPlaybackProgress alloc] initWithLibrary:library video:video player:player movie:movie];
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
+ (void)presentPlayer:(UIViewController *)owner library:(RDLPLibrary *)library job:(NSDictionary *)job legacy:(BOOL)legacy; {
  NSString *path=[library fileForJob:job];
  if(!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { [self showMessage:@"The downloaded file is missing. Retry its download from Queue."]; return; }
  NSURL *url=[NSURL fileURLWithPath:path];
  Class modern=legacy?Nil:NSClassFromString(@"AVPlayerViewController");
  if(modern) {
    UIViewController *controller=[[modern alloc] init]; AVPlayer *player=[AVPlayer playerWithURL:url];
    [controller performSelector:@selector(setPlayer:) withObject:player];
    RDLPTrackPlayback(controller,library,[job objectForKey:@"video_id"],player,nil);
    [owner presentModalViewController:controller animated:YES]; [controller release];
  } else {
    MPMoviePlayerViewController *controller=[[MPMoviePlayerViewController alloc] initWithContentURL:url];
    RDLPTrackPlayback(controller,library,[job objectForKey:@"video_id"],nil,controller.moviePlayer);
    [owner presentMoviePlayerViewControllerAnimated:controller]; [controller release];
  }
}
+ (UIBarButtonItem *)item:(NSString *)title target:(id)target action:(SEL)action;
{ return [[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:target action:action] autorelease]; }
@end
#pragma clang diagnostic pop
