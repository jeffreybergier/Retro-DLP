#import "RDLPPlayerViewController.h"
#import "RDLPPlayerNavigationController.h"
#import "RDLPPlayerControls.h"
#import "queue_tests.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

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

@interface TestItem : AVPlayerItem {
@public
  BOOL useTestTime;
  CMTime testTime;
}
@end
@implementation TestItem
- (CMTime)currentTime { return useTestTime?testTime:[super currentTime]; }
@end

/* Real readiness, with controllable seek completions for race regressions. */
@interface TestQueue : AVQueuePlayer {
@public
  NSUInteger playCalls, pauseCalls, seekCalls;
  BOOL holdSeeks;
  CMTime requestedTime;
  void (^pendingSeek)(BOOL);
  TestItem *seekItem;
}
- (void)completeSeek:(BOOL)finished;
@end
@implementation TestQueue
- (void)play { playCalls++; [super play]; }
- (void)pause { pauseCalls++; [super pause]; }
- (void)seekToTime:(CMTime)time { seekCalls++; [super seekToTime:time]; }
- (void)seekToTime:(CMTime)time toleranceBefore:(CMTime)before toleranceAfter:(CMTime)after completionHandler:(void (^)(BOOL))completion {
  seekCalls++;
  if(!holdSeeks) { [super seekToTime:time toleranceBefore:before toleranceAfter:after completionHandler:completion]; return; }
  Require(!pendingSeek,@"Only one scrub seek may be in flight");
  requestedTime=time;
  seekItem=[(TestItem *)[self currentItem] retain];
  pendingSeek=[completion copy];
}
- (void)completeSeek:(BOOL)finished {
  Require(pendingSeek!=nil,@"A seek must be pending before completion");
  if(finished) { seekItem->useTestTime=YES; seekItem->testTime=requestedTime; }
  [seekItem release]; seekItem=nil;
  void (^completion)(BOOL)=pendingSeek;
  pendingSeek=nil;
  completion(finished); [completion release];
  /* Seek callbacks marshal their state changes onto the main queue. */
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}
@end

@interface PlayerTests : UIResponder <UIApplicationDelegate, RDLPPlayerViewControllerDelegate> {
  UIWindow *_window;
  TestController *_controller;
  TestQueue *_queue;
  NSMutableString *_report;
  NSUInteger _attempts, _previous, _next, _audio, _dismiss;
  BOOL _started, _requestedAudioOnly;
}
@end

@implementation PlayerTests
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
  (void)application; (void)options;
  _report=[[NSMutableString alloc] init];
  _window=[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  _controller=[[TestController alloc] init];
  NSURL *url=[[NSBundle mainBundle] URLForResource:@"fixture" withExtension:@"mp4"];
  _queue=[[TestQueue alloc] initWithItems:[NSArray arrayWithObjects:[[[TestItem alloc] initWithURL:url] autorelease],
                                       [[[TestItem alloc] initWithURL:url] autorelease],nil]];
  [_controller setPlayer:_queue];
  [_controller setTitle:@"Fixture video"];
  [_window setRootViewController:[[[RDLPPlayerNavigationController alloc] initWithRootViewController:_controller] autorelease]];
  [_window makeKeyAndVisible];
  return YES;
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
  (void)application;
  if(!_started) { _started=YES; [self performSelector:@selector(waitForMedia) withObject:nil afterDelay:0.1]; }
}
- (void)waitForMedia {
  if([[_queue currentItem] status]==AVPlayerItemStatusFailed || _attempts++>100) {
    [self finish:@"FAIL: fixture did not become ready"]; return;
  }
  if([[_queue currentItem] status]!=AVPlayerItemStatusReadyToPlay) {
    [self performSelector:@selector(waitForMedia) withObject:nil afterDelay:0.1]; return;
  }
  @try {
    [self runTests];
    RDLPStartQueueTests([[NSBundle mainBundle] URLForResource:@"fixture" withExtension:@"mp4"],
                       ^(NSString *result) { [self finish:result]; });
  }
  @catch(NSException *exception) { [self finish:[@"FAIL: " stringByAppendingString:[exception reason]]]; }
}
- (void)pass:(NSString *)message { [_report appendFormat:@"PASS: %@\n",message]; }
- (void)runTests {
  RDLPPlayerControls *controls=[_controller valueForKey:@"controls"];
  AVPlayerLayer *layer=(AVPlayerLayer *)[[_controller view] layer];
  Require([_controller showsPlaybackControls] && ![_controller isAudioOnly],@"Default control and audio mode");
  Require([[_controller videoGravity] isEqualToString:AVLayerVideoGravityResizeAspect],@"Default aspect fit");
  Require([layer player]==_queue && [[controls playButton] isEnabled],@"Ready player attaches to presentation");
  Require(_queue->playCalls==0 && _queue->pauseCalls==0,@"Assignment and presentation do not start or pause playback");
  Require(![[_controller navigationItem] leftBarButtonItem],@"Headphones require an audio-only delegate");
  Require(![[controls previousButton] isEnabled] && ![[controls nextButton] isEnabled],@"Navigation is initially disabled");
  for(UIBarButtonItem *button in [NSArray arrayWithObjects:[controls playButton],[controls previousButton],[controls nextButton],[controls audioButton],nil])
    Require([button image]!=nil,@"Font Awesome artwork loads from resource bundle");
  [self pass:@"Defaults, resource loading, and ready state"];

  [_controller setDelegate:self];
  [_controller setCanSkipToPreviousItem:YES];
  [_controller setCanSkipToNextItem:YES];
  Require([[controls previousButton] isEnabled] && [[controls nextButton] isEnabled],@"Owner enables navigation");
  AVPlayerItem *original=[_queue currentItem];
  [[[controls previousButton] target] performSelector:[[controls previousButton] action] withObject:[controls previousButton]];
  [[[controls nextButton] target] performSelector:[[controls nextButton] action] withObject:[controls nextButton]];
  [[[controls audioButton] target] performSelector:[[controls audioButton] action] withObject:[controls audioButton]];
  [[[controls doneButton] target] performSelector:[[controls doneButton] action] withObject:[controls doneButton]];
  Require(_previous==1 && _next==1 && _audio==1 && _dismiss==1,@"Each request reaches the owner once");
  Require(_requestedAudioOnly && ![_controller isAudioOnly] && [_queue currentItem]==original,@"Requests do not mutate session state");
  [_controller setAudioOnly:YES];
  Require([layer player]==nil && ([[controls audioButton] accessibilityTraits]&UIAccessibilityTraitSelected),@"Audio-only presentation detaches video and selects headphones");
  [_controller setAudioOnly:NO];
  Require([layer player]==_queue && _audio==1,@"Programmatic mode change does not send another request");
  Require(_queue->playCalls==0 && _queue->pauseCalls==0,@"Mode changes preserve playback state");
  [self pass:@"Delegate requests and audio-only presentation"];

  UINavigationController *navigation=[_controller navigationController];
  [[navigation view] layoutIfNeeded];
  Require([[navigation navigationBar] topItem]==[_controller navigationItem] &&
          ![[_controller navigationItem] titleView] && [[[_controller navigationItem] title] isEqualToString:@"Fixture video"],@"Native navigation bar displays the video title");
  Require([[_controller navigationItem] leftBarButtonItem]==[controls audioButton] &&
          [[_controller navigationItem] rightBarButtonItem]==[controls doneButton],@"Headphones left, Done right");
  NSMutableArray *items=[NSMutableArray array];
  for(UIBarButtonItem *item in [[navigation toolbar] items])
    if([item image] || [item customView]) [items addObject:item];
  Require([items count]==4 && [items objectAtIndex:0]==[controls previousButton] &&
          [[items objectAtIndex:1] customView]==[controls timeline] &&
          [items objectAtIndex:2]==[controls nextButton] && [items objectAtIndex:3]==[controls playButton],@"Toolbar order is previous, timeline, next, play");
  Require([[navigation navigationBar] isTranslucent] && [[navigation toolbar] isTranslucent],@"Bars overlay the video");
  Require([[controls slider] bounds].size.width>0,@"Scrubber has space between transport items");
  CGRect track=[[controls slider] trackRectForBounds:[[controls slider] bounds]];
  CGRect thumb=[[controls slider] thumbRectForBounds:[[controls slider] bounds] trackRect:track value:[[controls slider] value]];
  CGPoint thumbPoint=[[controls slider] convertPoint:CGPointMake(CGRectGetMidX(thumb),CGRectGetMidY(thumb)) toView:_window];
  UIView *hit=[_window hitTest:thumbPoint withEvent:nil];
  Require(hit==[controls slider] || [hit isDescendantOfView:[controls slider]],@"Portrait thumb reaches the slider through the full window hierarchy");
  RDLPPlayerControls *sizing=[[[RDLPPlayerControls alloc] initWithFrame:CGRectZero] autorelease];
  UIToolbar *bar=[[[UIToolbar alloc] initWithFrame:CGRectMake(0,0,320,44)] autorelease];
  CGFloat portraitWidth=0;
  for(NSValue *value in [NSArray arrayWithObjects:[NSValue valueWithCGSize:CGSizeMake(320,44)],
                         [NSValue valueWithCGSize:CGSizeMake(568,32)], [NSValue valueWithCGSize:CGSizeMake(320,44)],nil]) {
    CGSize size=[value CGSizeValue];
    [bar setFrame:(CGRect){CGPointZero,size}];
    Require([sizing sizeForToolbar:size],@"Rotation resizes the slider");
    [bar setItems:[sizing toolbarItems] animated:NO]; [bar layoutIfNeeded];
    Require(![sizing sizeForToolbar:size],@"UIKit layout must not cause the toolbar items to be rebuilt repeatedly");
    CGFloat width=[[sizing slider] bounds].size.width;
    if(size.width==320) portraitWidth=width;
    else Require(width>portraitWidth,@"Landscape slider grows with the toolbar");
    for(NSNumber *position in [NSArray arrayWithObjects:@0, @0.5, @1, nil]) {
      [[sizing slider] setValue:[position floatValue]];
      CGRect r=[[sizing slider] trackRectForBounds:[[sizing slider] bounds]];
      Require(fabs(CGRectGetMidY(r)-CGRectGetMidY([[sizing slider] bounds])-1)<0.01,@"Track keeps its approved one-point vertical offset");
      r=[[sizing slider] thumbRectForBounds:[[sizing slider] bounds] trackRect:r value:[[sizing slider] value]];
      CGPoint point=[[sizing slider] convertPoint:CGPointMake(CGRectGetMidX(r),CGRectGetMidY(r)) toView:bar];
      UIView *target=[bar hitTest:point withEvent:nil];
      Require(target==[sizing slider] || [target isDescendantOfView:[sizing slider]],@"Slider thumb is touchable across its range in both toolbar sizes");
    }
  }
  CGRect videoFrame=[[_controller view] frame];
  [_controller setShowsPlaybackControls:NO];
  [[navigation view] layoutIfNeeded];
  Require([navigation isNavigationBarHidden] && [navigation isToolbarHidden],@"Both native bars hide together");
  Require(CGRectEqualToRect(videoFrame,[[_controller view] frame]),@"Hiding bars does not resize video");
  [_controller setShowsPlaybackControls:YES];
  [[navigation view] layoutIfNeeded];
  Require(![navigation isNavigationBarHidden] && ![navigation isToolbarHidden],@"Both native bars return");
  [self pass:@"Native bars, scrubber placement, and stable video geometry"];

  [_controller performSelector:@selector(toggleVideoGravity:) withObject:nil];
  Require([[_controller videoGravity] isEqualToString:AVLayerVideoGravityResizeAspectFill],@"Video double tap fills the screen");
  [_controller performSelector:@selector(toggleVideoGravity:) withObject:nil];
  Require([[_controller videoGravity] isEqualToString:AVLayerVideoGravityResizeAspect],@"Second double tap restores aspect fit");

  _queue->holdSeeks=YES;
  [[controls slider] sendActionsForControlEvents:UIControlEventTouchDown];
  [[controls slider] setValue:0.5f];
  [[controls slider] sendActionsForControlEvents:UIControlEventValueChanged];
  Require(_queue->seekCalls==1,@"Dragging seeks before release");
  [[controls slider] setValue:0.75f];
  [[controls slider] sendActionsForControlEvents:UIControlEventValueChanged];
  [[controls slider] setValue:0.25f];
  [[controls slider] sendActionsForControlEvents:UIControlEventValueChanged];
  Require(_queue->seekCalls==1,@"Intermediate drag positions coalesce while a seek is pending");
  [[controls slider] sendActionsForControlEvents:UIControlEventTouchUpInside];
  [_controller performSelector:@selector(refreshTime)];
  Require([[controls slider] value]==0.25f,@"Release and periodic updates cannot snap back to the old player time");
  [_queue completeSeek:YES];
  Require(_queue->seekCalls==2 && [[controls slider] value]==0.25f,@"Completion seeks only the newest requested position without moving the thumb");
  [_queue completeSeek:YES];
  Require(fabs([[controls slider] value]-0.25f)<0.001 && ![_controller valueForKey:@"scrubItem"],@"Final completion resumes normal position updates");
  Require(_queue->playCalls==0 && _queue->pauseCalls==0,@"Scrubbing preserves playback state");

  [[controls slider] setValue:0.6f];
  [[controls slider] sendActionsForControlEvents:UIControlEventValueChanged];
  [[controls slider] setValue:0.4f];
  [[controls slider] sendActionsForControlEvents:UIControlEventValueChanged];
  Require(_queue->seekCalls==3,@"VoiceOver adjustments also coalesce");
  [_queue completeSeek:YES]; [_queue completeSeek:YES];
  Require(![_controller valueForKey:@"scrubItem"],@"VoiceOver does not leave scrubbing active");

  [[controls slider] sendActionsForControlEvents:UIControlEventTouchDown];
  [[controls slider] setValue:0.3f];
  [[controls slider] sendActionsForControlEvents:UIControlEventValueChanged];
  [_queue completeSeek:YES];
  [_controller performSelector:@selector(refreshTime)];
  Require([[controls slider] value]==0.3f && [_controller valueForKey:@"scrubItem"],@"A held finger keeps ownership after its seek completes");
  [[controls slider] sendActionsForControlEvents:UIControlEventTouchCancel];
  Require(_queue->seekCalls==5 && ![_controller valueForKey:@"scrubItem"],@"Cancellation keeps the last scrubbed position without a redundant seek");

  [[controls slider] sendActionsForControlEvents:UIControlEventTouchDown];
  [[controls slider] setValue:0.2f];
  [[controls slider] sendActionsForControlEvents:UIControlEventValueChanged];
  [[controls slider] sendActionsForControlEvents:UIControlEventTouchUpInside];
  [_queue completeSeek:NO];
  Require(![_controller valueForKey:@"scrubItem"],@"An interrupted seek releases the slider without retrying forever");

  [[controls slider] sendActionsForControlEvents:UIControlEventTouchDown];
  [[controls slider] setValue:0.7f];
  [[controls slider] sendActionsForControlEvents:UIControlEventValueChanged];
  [[controls slider] setValue:0.8f];
  [[controls slider] sendActionsForControlEvents:UIControlEventValueChanged];
  [_queue advanceToNextItem];
  [[controls slider] sendActionsForControlEvents:UIControlEventTouchUpInside];
  [_queue completeSeek:YES];
  Require(_queue->seekCalls==7 && ![_controller valueForKey:@"scrubItem"],@"Old drag events and completions cannot seek the next item");
  _queue->holdSeeks=NO;
  [self pass:@"Continuous, coalesced scrubbing, no release snap-back, VoiceOver, cancellation, and stale-item completion"];

  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  [center postNotificationName:UIApplicationWillResignActiveNotification object:[UIApplication sharedApplication]];
  [_controller setAudioOnly:NO];
  Require([layer player]==nil && ![_controller valueForKey:@"timeObserver"],@"Inactive presentation stays detached, including after property changes");
  [center postNotificationName:UIApplicationDidBecomeActiveNotification object:[UIApplication sharedApplication]];
  Require([layer player]==_queue && [_controller valueForKey:@"timeObserver"],@"Foreground presentation and time observer restored");
  [_controller setPlayer:nil];
  Require([layer player]==nil && ![[controls playButton] isEnabled] && ![[controls nextButton] isEnabled],@"Nil player clears presentation and disables transport");
  Require(![_controller valueForKey:@"timeObserver"] && ![_controller valueForKey:@"observedItem"],@"Player removal cleans up observers");
  [center postNotificationName:AVPlayerItemFailedToPlayToEndTimeNotification object:[_queue currentItem]];
  Require(![[_controller valueForKey:@"failedToEnd"] boolValue],@"Detached player notifications are ignored");
  Require(_queue->pauseCalls==0,@"Lifecycle transitions do not pause the externally owned player");
  [self pass:@"Foreground/background lifecycle and observer cleanup"];

  NSUInteger released=controllersReleased;
  TestController *temporary=[[TestController alloc] init];
  [temporary setPlayer:_queue];
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
  UITextView *text=[[UITextView alloc] initWithFrame:[_window bounds]];
  [text setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
  [text setEditable:NO]; [text setText:_report]; [text setFont:[UIFont systemFontOfSize:16]];
  [_window addSubview:text]; [text release];
}
- (void)playerViewControllerDidRequestPreviousItem:(RDLPPlayerViewController *)controller { (void)controller; _previous++; }
- (void)playerViewControllerDidRequestNextItem:(RDLPPlayerViewController *)controller { (void)controller; _next++; }
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
