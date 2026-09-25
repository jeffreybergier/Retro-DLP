#import "RDLPPlayerViewController.h"
#import "RDLPPlayerControls.h"
#import "queue_tests.h"
#import <QuartzCore/QuartzCore.h>

/* Standalone device regression app. No Retro-DLP app or library dependencies. */
static void Require(BOOL condition, NSString *message) {
  if(!condition) [NSException raise:@"Player test failure" format:@"%@",message];
}
static NSUInteger controllersReleased;
@interface TestController : RDLPPlayerViewController
@end
@implementation TestController
- (void)dealloc { controllersReleased++; [super dealloc]; }
@end

/* Real AVFoundation playback with counters for UI-issued transport operations. */
@interface TestQueue : AVQueuePlayer {
@public
  NSUInteger playCalls, pauseCalls, seekCalls;
}
@end
@implementation TestQueue
- (void)play { playCalls++; [super play]; }
- (void)pause { pauseCalls++; [super pause]; }
- (void)seekToTime:(CMTime)time { seekCalls++; [super seekToTime:time]; }
@end

@interface PlayerTests : UIResponder <UIApplicationDelegate, RDLPPlayerViewControllerDelegate> {
  UIWindow *_window;
  TestController *_controller;
  TestQueue *_queue;
  NSMutableString *_report;
  NSUInteger _attempts, _previous, _next, _playlist, _audio, _dismiss;
  BOOL _started, _requestedAudioOnly;
}
@end

@implementation PlayerTests
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
  (void)application; (void)options;
  _report=[[NSMutableString alloc] init];
  _window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  _controller=[[TestController alloc] init];
  NSURL *url=[[NSBundle mainBundle] URLForResource:@"fixture" withExtension:@"mp4"];
  _queue=[[TestQueue alloc] initWithItems:[NSArray arrayWithObjects:[AVPlayerItem playerItemWithURL:url],
                                       [AVPlayerItem playerItemWithURL:url],nil]];
  _controller.player=_queue;
  _window.rootViewController=_controller;
  [_window makeKeyAndVisible];
  return YES;
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
  (void)application;
  if(!_started) { _started=YES; [self performSelector:@selector(waitForMedia) withObject:nil afterDelay:0.1]; }
}
- (void)waitForMedia {
  if(_queue.currentItem.status==AVPlayerItemStatusFailed || _attempts++>100) {
    [self finish:@"FAIL: fixture did not become ready"]; return;
  }
  if(_queue.currentItem.status!=AVPlayerItemStatusReadyToPlay) {
    [self performSelector:@selector(waitForMedia) withObject:nil afterDelay:0.1]; return;
  }
  @try {
    [self runTests];
    RDLPStartQueueTests([[NSBundle mainBundle] URLForResource:@"fixture" withExtension:@"mp4"],
                       ^(NSString *result) { [self finish:result]; });
  }
  @catch(NSException *exception) { [self finish:[@"FAIL: " stringByAppendingString:exception.reason]]; }
}
- (void)pass:(NSString *)message { [_report appendFormat:@"PASS: %@\n",message]; }
- (void)runTests {
  RDLPPlayerControls *controls=[_controller valueForKey:@"controls"];
  AVPlayerLayer *layer=(AVPlayerLayer *)_controller.view.layer;
  Require(_controller.showsPlaybackControls && !_controller.audioOnly,@"Default control and audio mode");
  Require([_controller.videoGravity isEqualToString:AVLayerVideoGravityResizeAspect],@"Default aspect fit");
  Require(layer.player==_queue && controls.playButton.enabled,@"Ready player attaches to presentation");
  Require(_queue->playCalls==0 && _queue->pauseCalls==0,@"Assignment and presentation do not start or pause playback");
  Require(controls.playlistButton.hidden && controls.audioButton.hidden,@"Optional actions require a delegate");
  Require(!controls.previousButton.enabled && !controls.nextButton.enabled,@"Navigation is initially disabled");
  for(UIButton *button in [NSArray arrayWithObjects:controls.playButton,controls.previousButton,controls.nextButton,controls.scaleButton,nil])
    Require([button imageForState:UIControlStateNormal]!=nil,@"Original AL artwork loads from resource bundle");
  [self pass:@"Defaults, resource loading, and ready state"];

  _controller.delegate=self;
  _controller.canSkipToPreviousItem=YES;
  _controller.canSkipToNextItem=YES;
  Require(controls.previousButton.enabled && controls.nextButton.enabled,@"Owner enables navigation");
  AVPlayerItem *original=_queue.currentItem;
  [controls.previousButton sendActionsForControlEvents:UIControlEventTouchUpInside];
  [controls.nextButton sendActionsForControlEvents:UIControlEventTouchUpInside];
  [controls.playlistButton sendActionsForControlEvents:UIControlEventTouchUpInside];
  [controls.audioButton sendActionsForControlEvents:UIControlEventTouchUpInside];
  [controls.doneButton sendActionsForControlEvents:UIControlEventTouchUpInside];
  Require(_previous==1 && _next==1 && _playlist==1 && _audio==1 && _dismiss==1,@"Each request reaches the owner once");
  Require(_requestedAudioOnly && !_controller.audioOnly && _queue.currentItem==original,@"Requests do not mutate session state");
  _controller.audioOnly=YES;
  Require(layer.player==nil && controls.audioButton.selected && controls.scaleButton.hidden,@"Audio-only presentation detaches video");
  _controller.audioOnly=NO;
  Require(layer.player==_queue && _audio==1,@"Programmatic mode change does not send another request");
  Require(_queue->playCalls==0 && _queue->pauseCalls==0,@"Mode changes preserve playback state");
  [self pass:@"Delegate requests and audio-only presentation"];

  /* Keep all controls visible to check the most crowded supported layouts. */
  CGSize sizes[]={ {320,480}, {480,320}, {568,320}, {768,1024}, {1024,768} };
  for(NSUInteger i=0;i<sizeof(sizes)/sizeof(sizes[0]);i++) {
    controls.frame=(CGRect){CGPointZero,sizes[i]}; [controls setNeedsLayout]; [controls layoutIfNeeded];
    NSArray *buttons=[NSArray arrayWithObjects:controls.playlistButton,controls.previousButton,
                      controls.playButton,controls.nextButton,controls.audioButton,nil];
    for(NSUInteger j=0;j<buttons.count;j++) {
      UIButton *button=[buttons objectAtIndex:j];
      Require(CGRectContainsRect(button.superview.bounds,button.frame),@"Transport target stays inside its bar");
      Require(button.frame.size.width>=44 && button.frame.size.height>=44,@"Transport target is at least 44 points");
      for(NSUInteger k=j+1;k<buttons.count;k++)
        Require(!CGRectIntersectsRect(button.frame,[[buttons objectAtIndex:k] frame]),@"Transport targets do not overlap");
    }
    Require(controls.slider.frame.size.width>0,@"Scrubber has positive width");
  }
  controls.frame=_controller.view.bounds;
  [self pass:@"Portrait, landscape, and iPad control layout"];

  [controls.slider sendActionsForControlEvents:UIControlEventTouchDown];
  controls.slider.value=0.5f;
  [controls.slider sendActionsForControlEvents:UIControlEventValueChanged];
  Require(_queue->seekCalls==0,@"Dragging does not issue repeated seeks");
  [controls.slider sendActionsForControlEvents:UIControlEventTouchCancel];
  Require(_queue->seekCalls==0,@"Cancelled scrub does not seek");
  [controls.slider sendActionsForControlEvents:UIControlEventTouchDown];
  controls.slider.value=0.25f;
  [controls.slider sendActionsForControlEvents:UIControlEventTouchUpInside];
  Require(_queue->seekCalls==1 && _queue->playCalls==0 && _queue->pauseCalls==0,@"Released scrub seeks once without changing transport state");
  [controls.slider sendActionsForControlEvents:UIControlEventTouchDown];
  [_queue advanceToNextItem];
  [controls.slider sendActionsForControlEvents:UIControlEventTouchUpInside];
  Require(_queue->seekCalls==1,@"A scrub from the old queue item cannot seek the new item");
  [self pass:@"Cancelled, committed, and stale-item scrubbing"];

  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  [center postNotificationName:UIApplicationWillResignActiveNotification object:[UIApplication sharedApplication]];
  _controller.audioOnly=NO;
  Require(layer.player==nil && ![_controller valueForKey:@"timeObserver"],@"Inactive presentation stays detached, including after property changes");
  [center postNotificationName:UIApplicationDidBecomeActiveNotification object:[UIApplication sharedApplication]];
  Require(layer.player==_queue && [_controller valueForKey:@"timeObserver"],@"Foreground presentation and time observer restored");
  _controller.player=nil;
  Require(layer.player==nil && !controls.playButton.enabled && !controls.nextButton.enabled,@"Nil player clears presentation and disables transport");
  Require(![_controller valueForKey:@"timeObserver"] && ![_controller valueForKey:@"observedItem"],@"Player removal cleans up observers");
  [center postNotificationName:AVPlayerItemFailedToPlayToEndTimeNotification object:_queue.currentItem];
  Require(![[_controller valueForKey:@"failedToEnd"] boolValue],@"Detached player notifications are ignored");
  Require(_queue->pauseCalls==0,@"Lifecycle transitions do not pause the externally owned player");
  [self pass:@"Foreground/background lifecycle and observer cleanup"];

  NSUInteger released=controllersReleased;
  TestController *temporary=[[TestController alloc] init];
  temporary.player=_queue;
  [temporary beginAppearanceTransition:YES animated:NO]; [temporary endAppearanceTransition];
  [temporary beginAppearanceTransition:NO animated:NO]; [temporary endAppearanceTransition];
  [temporary release];
  Require(controllersReleased==released+1,@"Observers do not retain the dismissed controller");
  [_queue removeAllItems];
  [self pass:@"Dismissal releases the controller while its player survives"];
}
- (void)finish:(NSString *)result {
  [_report appendFormat:@"%@\n",result];
  NSString *path=[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0]
                  stringByAppendingPathComponent:@"player-tests.txt"];
  [_report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  NSLog(@"%@",_report);
  UITextView *text=[[UITextView alloc] initWithFrame:_window.bounds];
  text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
  text.editable=NO; text.text=_report; text.font=[UIFont systemFontOfSize:16];
  [_window addSubview:text]; [text release];
}
- (void)playerViewControllerDidRequestPreviousItem:(RDLPPlayerViewController *)controller { (void)controller; _previous++; }
- (void)playerViewControllerDidRequestNextItem:(RDLPPlayerViewController *)controller { (void)controller; _next++; }
- (void)playerViewControllerDidRequestPlaylist:(RDLPPlayerViewController *)controller { (void)controller; _playlist++; }
- (void)playerViewController:(RDLPPlayerViewController *)controller didRequestAudioOnly:(BOOL)audioOnly {
  (void)controller; _audio++; _requestedAudioOnly=audioOnly;
}
- (void)playerViewControllerDidRequestDismissal:(RDLPPlayerViewController *)controller { (void)controller; _dismiss++; }
- (void)dealloc {
  [_window release]; [_controller release]; [_queue release]; [_report release]; [super dealloc];
}
@end

int main(int argc, char **argv) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  int result=UIApplicationMain(argc,argv,nil,NSStringFromClass([PlayerTests class]));
  [pool drain]; return result;
}
