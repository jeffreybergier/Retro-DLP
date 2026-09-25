#import "RDLPPlayerViewController.h"
#import "RDLPPlayerControls.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

/* A backing layer resizes with the view without a separate layout observer. */
@interface RDLPPlayerSurface : UIView
@end
@implementation RDLPPlayerSurface
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

static void *RDLPPlayerObservation=&RDLPPlayerObservation;
static NSArray *RDLPPlayerKeys(void) { return [NSArray arrayWithObjects:@"currentItem",@"rate",@"status",nil]; }
static NSArray *RDLPItemKeys(void) { return [NSArray arrayWithObjects:@"status",@"duration",nil]; }

@interface RDLPPlayerViewController () <UIGestureRecognizerDelegate> {
  RDLPPlayerControls *_controls;
  AVPlayerItem *_observedItem, *_scrubItem;
  id _timeObserver;
  BOOL _visible, _active, _observing, _chromeVisible, _failedToEnd;
  BOOL _scrubbing, _seeking;
  CMTime _scrubTime;
  NSUInteger _seekGeneration;
}
- (void)configure;
- (void)refresh;
- (void)refreshTime;
- (void)updatePresentation;
- (void)startObserving;
- (void)stopObserving;
- (void)observeCurrentItem;
- (void)showControls;
- (void)setChromeVisible:(BOOL)visible animated:(BOOL)animated;
- (void)scheduleHide;
- (void)layoutToolbar;
- (void)resetScrubbing;
- (void)seekToScrubTime;
- (void)finishScrubbing;
@end

@implementation RDLPPlayerViewController
@synthesize player=_player, delegate=_delegate, videoGravity=_videoGravity;
@synthesize showsPlaybackControls=_showsPlaybackControls, audioOnly=_audioOnly;
@synthesize canSkipToPreviousItem=_canSkipToPreviousItem, canSkipToNextItem=_canSkipToNextItem;

- (id)init { return [self initWithNibName:nil bundle:nil]; }
- (id)initWithNibName:(NSString *)name bundle:(NSBundle *)bundle {
  self=[super initWithNibName:name bundle:bundle]; if(self) [self configure]; return self;
}
- (id)initWithCoder:(NSCoder *)coder {
  self=[super initWithCoder:coder]; if(self) [self configure]; return self;
}
- (void)configure {
  _showsPlaybackControls=YES;
  _chromeVisible=YES;
  _active=[UIApplication sharedApplication].applicationState==UIApplicationStateActive;
  _videoGravity=[AVLayerVideoGravityResizeAspect copy];
  /* Keep video underneath translucent bars on both legacy and modern UIKit. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  self.wantsFullScreenLayout=YES;
#pragma clang diagnostic pop
  /* iOS 7+ defaults to extending under all translucent bars. */
  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(willResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
  [center addObserver:self selector:@selector(didBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
  [center addObserver:self selector:@selector(showControls) name:UIAccessibilityVoiceOverStatusChanged object:nil];
}
- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [self stopObserving];
  [_player release]; [_videoGravity release]; [_controls release];
  [super dealloc];
}

- (void)loadView {
  UIView *surface=[[RDLPPlayerSurface alloc] initWithFrame:[UIScreen mainScreen].bounds];
  surface.backgroundColor=[UIColor blackColor];
  surface.clipsToBounds=YES;
  self.view=surface;
  [surface release];
  _controls=[[RDLPPlayerControls alloc] initWithFrame:self.view.bounds];
  _controls.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:_controls];
  NSArray *buttons=[NSArray arrayWithObjects:_controls.doneButton,_controls.playButton,_controls.previousButton,
                    _controls.nextButton,_controls.audioButton,nil];
  for(UIBarButtonItem *button in buttons) {
    button.target=self;
    button.action=@selector(buttonPressed:);
  }
  self.toolbarItems=_controls.toolbarItems;
  [_controls.slider addTarget:self action:@selector(scrubBegan:) forControlEvents:UIControlEventTouchDown];
  [_controls.slider addTarget:self action:@selector(scrubChanged:) forControlEvents:UIControlEventValueChanged];
  [_controls.slider addTarget:self action:@selector(scrubEnded:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
  [_controls.slider addTarget:self action:@selector(scrubEnded:) forControlEvents:UIControlEventTouchCancel];
  UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleControls:)];
  UITapGestureRecognizer *doubleTap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleVideoGravity:)];
  doubleTap.numberOfTapsRequired=2;
  doubleTap.delegate=self;
  [tap requireGestureRecognizerToFail:doubleTap];
  tap.delegate=self;
  [self.view addGestureRecognizer:tap]; [tap release];
  [self.view addGestureRecognizer:doubleTap]; [doubleTap release];
  [self updatePresentation];
  [self refresh];
  [self showControls];
}
- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  _visible=YES;
  UINavigationController *navigation=self.navigationController;
  navigation.navigationBar.barStyle=UIBarStyleBlack;
  navigation.navigationBar.translucent=YES;
  navigation.toolbar.barStyle=UIBarStyleBlack;
  navigation.toolbar.translucent=YES;
  /* On iOS 5 tintColor colors the bar itself; black barStyle is sufficient.
   * On iOS 7+ tintColor colors the buttons. */
  if([navigation.navigationBar respondsToSelector:@selector(setBarTintColor:)]) {
    navigation.navigationBar.tintColor=[UIColor whiteColor];
    navigation.toolbar.tintColor=[UIColor whiteColor];
  }
  [self startObserving];
  [self updatePresentation];
  [self showControls];
}
- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  _visible=NO;
  [self cancelHide];
  [self stopObserving];
  [self updatePresentation];
  UINavigationController *navigation=self.navigationController;
  if(navigation.topViewController!=self && !navigation.isBeingDismissed) {
    [navigation setNavigationBarHidden:NO animated:animated];
    [navigation setToolbarHidden:navigation.topViewController.toolbarItems.count==0 animated:animated];
  }
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self layoutToolbar];
}
- (void)layoutToolbar {
  UINavigationController *navigation=self.navigationController;
  if(!_controls || navigation.topViewController!=self) return;
  /* The content bounds already reflect rotation when the toolbar may still
   * have its old frame. Refresh its items after resizing the custom view. */
  CGSize size=CGSizeMake(self.view.bounds.size.width,navigation.toolbar.bounds.size.height);
  if(size.width>0 && size.height>0 && [_controls sizeForToolbar:size]) {
    [navigation.toolbar setItems:self.toolbarItems animated:NO];
    [navigation.toolbar setNeedsLayout];
  }
}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration {
  [super willAnimateRotationToInterfaceOrientation:orientation duration:duration];
  [self layoutToolbar];
}
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
  [super didRotateFromInterfaceOrientation:orientation];
  [self layoutToolbar];
}
#pragma clang diagnostic pop
- (void)viewDidUnload {
  [self cancelHide];
  [self stopObserving];
  self.navigationItem.titleView=nil;
  self.navigationItem.leftBarButtonItem=nil;
  self.navigationItem.rightBarButtonItem=nil;
  self.toolbarItems=nil;
  [_controls release]; _controls=nil;
  [super viewDidUnload];
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
  return UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad || orientation!=UIInterfaceOrientationPortraitUpsideDown;
}
- (NSUInteger)supportedInterfaceOrientations {
  return UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad?UIInterfaceOrientationMaskAll:UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)setPlayer:(AVPlayer *)player {
  if(player==_player) return;
  [self stopObserving];
  [player retain]; [_player release]; _player=player;
  [self startObserving];
  [self updatePresentation];
  [self refresh];
}
- (void)setDelegate:(id<RDLPPlayerViewControllerDelegate>)delegate {
  _delegate=delegate;
  [self refresh];
}
- (void)setShowsPlaybackControls:(BOOL)shows {
  _showsPlaybackControls=shows;
  [self showControls];
}
- (void)setVideoGravity:(NSString *)gravity {
  NSParameterAssert([gravity isEqualToString:AVLayerVideoGravityResizeAspect] ||
                    [gravity isEqualToString:AVLayerVideoGravityResizeAspectFill] ||
                    [gravity isEqualToString:AVLayerVideoGravityResize]);
  if([_videoGravity isEqualToString:gravity]) return;
  NSString *copy=[gravity copy]; [_videoGravity release]; _videoGravity=copy;
  [self updatePresentation];
}
- (void)setAudioOnly:(BOOL)audioOnly {
  _audioOnly=audioOnly;
  [self updatePresentation];
  [self refresh];
  [self showControls];
}
- (void)setCanSkipToPreviousItem:(BOOL)canSkip {
  _canSkipToPreviousItem=canSkip; [self refresh];
}
- (void)setCanSkipToNextItem:(BOOL)canSkip {
  _canSkipToNextItem=canSkip; [self refresh];
}

- (void)updatePresentation {
  if(![self isViewLoaded]) return;
  AVPlayerLayer *layer=(AVPlayerLayer *)self.view.layer;
  BOOL display=_visible && _active && !_audioOnly;
  layer.player=display?_player:nil;
  layer.videoGravity=_videoGravity;
}
- (void)willResignActive:(NSNotification *)notification {
  (void)notification;
  _active=NO;
  /* Detach before backgrounding; no forced pause/resume on lifecycle changes. */
  if([self isViewLoaded]) [(AVPlayerLayer *)self.view.layer setPlayer:nil];
  [self cancelHide];
  [self stopObserving];
}
- (void)didBecomeActive:(NSNotification *)notification {
  (void)notification;
  _active=YES;
  [self startObserving];
  [self updatePresentation];
  [self showControls];
}

- (void)startObserving {
  if(_observing || !_visible || !_active || !_player) return;
  _observing=YES;
  for(NSString *key in RDLPPlayerKeys()) [_player addObserver:self forKeyPath:key options:0 context:RDLPPlayerObservation];
  [self observeCurrentItem];
  /* Under MRC __block is nonretaining. Removal on the main thread precedes
   * teardown, and this observer also delivers on the main thread. */
  __block RDLPPlayerViewController *controller=self;
  _timeObserver=[[_player addPeriodicTimeObserverForInterval:CMTimeMake(1,4) queue:dispatch_get_main_queue()
                                               usingBlock:^(CMTime time) { (void)time; [controller refreshTime]; }] retain];
  [self refresh];
}
- (void)stopObserving {
  if(_timeObserver) { [_player removeTimeObserver:_timeObserver]; [_timeObserver release]; _timeObserver=nil; }
  if(_observing) for(NSString *key in RDLPPlayerKeys()) [_player removeObserver:self forKeyPath:key context:RDLPPlayerObservation];
  _observing=NO;
  [self observeCurrentItem];
  [self resetScrubbing];
}
- (void)observeCurrentItem {
  AVPlayerItem *item=_observing?_player.currentItem:nil;
  if(item==_observedItem) return;
  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  if(_observedItem) {
    for(NSString *key in RDLPItemKeys()) [_observedItem removeObserver:self forKeyPath:key context:RDLPPlayerObservation];
    [center removeObserver:self name:AVPlayerItemTimeJumpedNotification object:_observedItem];
    [center removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_observedItem];
    [center removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_observedItem];
  }
  [item retain]; [_observedItem release]; _observedItem=item;
  [self resetScrubbing];
  _failedToEnd=NO;
  if(item) {
    for(NSString *key in RDLPItemKeys()) [item addObserver:self forKeyPath:key options:0 context:RDLPPlayerObservation];
    [center addObserver:self selector:@selector(itemNotification:) name:AVPlayerItemTimeJumpedNotification object:item];
    [center addObserver:self selector:@selector(itemNotification:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [center addObserver:self selector:@selector(itemNotification:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
  }
}
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  if(context!=RDLPPlayerObservation) { [super observeValueForKeyPath:key ofObject:object change:change context:context]; return; }
  if([NSThread isMainThread]) [self refresh];
  else [self performSelectorOnMainThread:@selector(refresh) withObject:nil waitUntilDone:NO];
}
- (void)itemNotification:(NSNotification *)notification {
  if(![NSThread isMainThread]) {
    [self performSelectorOnMainThread:@selector(itemNotification:) withObject:notification waitUntilDone:NO]; return;
  }
  if(notification.object!=_observedItem) return;
  /* Seeks only change the position, not the bar items or their layout. */
  if([notification.name isEqualToString:AVPlayerItemTimeJumpedNotification]) { [self refreshTime]; return; }
  if([notification.name isEqualToString:AVPlayerItemFailedToPlayToEndTimeNotification]) _failedToEnd=YES;
  [self refresh];
}

- (void)refresh {
  if(_observing) [self observeCurrentItem];
  if(!_controls) return;
  AVPlayerItem *item=_player.currentItem;
  BOOL failed=_player.status==AVPlayerStatusFailed || item.status==AVPlayerItemStatusFailed || _failedToEnd;
  if(failed) [self resetScrubbing];
  BOOL ready=item && item.status==AVPlayerItemStatusReadyToPlay && !failed;
  _controls.playButton.enabled=ready;
  _controls.playButton.image=[UIImage imageNamed:_player.rate!=0?@"RDLPPlayer.bundle/pause.png":@"RDLPPlayer.bundle/play.png"];
  _controls.playButton.accessibilityLabel=_player.rate!=0?@"Pause":@"Play";
  _controls.previousButton.enabled=_player && _canSkipToPreviousItem && [_delegate respondsToSelector:@selector(playerViewControllerDidRequestPreviousItem:)];
  _controls.nextButton.enabled=_player && _canSkipToNextItem && [_delegate respondsToSelector:@selector(playerViewControllerDidRequestNextItem:)];
  BOOL audio=[_delegate respondsToSelector:@selector(playerViewController:didRequestAudioOnly:)];
  _controls.audioButton.enabled=_player!=nil;
  _controls.audioButton.accessibilityLabel=_audioOnly?@"Show video":@"Use audio only";
  _controls.audioButton.accessibilityTraits=UIAccessibilityTraitButton|(_audioOnly?UIAccessibilityTraitSelected:0);
  _controls.audioButton.tintColor=_audioOnly?[UIColor colorWithRed:0.2 green:0.6 blue:1 alpha:1]:nil;
  BOOL modalRoot=self.navigationController.presentingViewController && [self.navigationController.viewControllers objectAtIndex:0]==self;
  BOOL done=[_delegate respondsToSelector:@selector(playerViewControllerDidRequestDismissal:)] || modalRoot;
  self.navigationItem.leftBarButtonItem=audio?_controls.audioButton:nil;
  self.navigationItem.rightBarButtonItem=done?_controls.doneButton:nil;
  NSString *message=failed?@"Unable to play this item":(!item?@"No media":(_audioOnly?@"Audio Only":nil));
  [_controls setMessage:message];
  [_controls setNeedsLayout];
  [self refreshTime];
  if(_player.rate==0 || failed) [self showControls]; else [self scheduleHide];
}
- (void)refreshTime {
  if(!_controls || _scrubItem) return;
  AVPlayerItem *item=_player.currentItem;
  double duration=item?CMTimeGetSeconds(item.duration):NAN;
  double elapsed=item?CMTimeGetSeconds(item.currentTime):0;
  _controls.slider.enabled=item.status==AVPlayerItemStatusReadyToPlay && !_failedToEnd &&
                           _player.status!=AVPlayerStatusFailed && isfinite(duration) && duration>0;
  _controls.slider.value=_controls.slider.enabled && isfinite(elapsed)?(float)MAX(0,MIN(1,elapsed/duration)):0;
  [_controls setElapsedTime:elapsed duration:duration];
}

- (void)cancelHide { [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideControls) object:nil]; }
- (void)scheduleHide {
  [self cancelHide];
  if(_visible && _showsPlaybackControls && _chromeVisible && !_audioOnly && _player.rate!=0 &&
     !_scrubItem && _active && !UIAccessibilityIsVoiceOverRunning())
    [self performSelector:@selector(hideControls) withObject:nil afterDelay:5];
}
- (void)showControls {
  _chromeVisible=_showsPlaybackControls;
  [self setChromeVisible:_chromeVisible animated:NO];
  [self scheduleHide];
}
- (void)setChromeVisible:(BOOL)visible animated:(BOOL)animated {
  UINavigationController *navigation=self.navigationController;
  if(!_visible || navigation.topViewController!=self) return;
  [navigation setNavigationBarHidden:!visible animated:animated];
  [navigation setToolbarHidden:!visible animated:animated];
}
- (void)hideControls {
  if([_controls isTracking]) { [self scheduleHide]; return; }
  _chromeVisible=NO;
  [self setChromeVisible:NO animated:YES];
}
- (void)toggleControls:(UITapGestureRecognizer *)tap {
  (void)tap;
  if(!_showsPlaybackControls) return;
  if(_chromeVisible) { [self cancelHide]; [self hideControls]; }
  else {
    _chromeVisible=YES;
    [self setChromeVisible:YES animated:YES];
    [self scheduleHide];
  }
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
  (void)recognizer;
  return ![touch.view isDescendantOfView:_controls];
}
- (void)toggleVideoGravity:(UITapGestureRecognizer *)tap {
  (void)tap;
  if(!_visible || !_active || _audioOnly || !self.view.userInteractionEnabled ||
     _player.currentItem.status!=AVPlayerItemStatusReadyToPlay) return;
  self.videoGravity=[_videoGravity isEqualToString:AVLayerVideoGravityResizeAspectFill]?
    AVLayerVideoGravityResizeAspect:AVLayerVideoGravityResizeAspectFill;
}

- (void)buttonPressed:(UIBarButtonItem *)button {
  if(!button.enabled || !_visible || !_active) return;
  if(button!=_controls.doneButton && !self.view.userInteractionEnabled) return;
  [self scheduleHide];
  if(button==_controls.playButton) {
    if(!_player.currentItem) return;
    if(_player.rate!=0) [_player pause];
    else {
      double duration=CMTimeGetSeconds(_player.currentItem.duration);
      if(isfinite(duration) && duration>0 && CMTimeGetSeconds(_player.currentTime)>=duration) [_player seekToTime:kCMTimeZero];
      [_player play];
    }
  } else if(button==_controls.previousButton && [_delegate respondsToSelector:@selector(playerViewControllerDidRequestPreviousItem:)]) {
    [_delegate playerViewControllerDidRequestPreviousItem:self];
  } else if(button==_controls.nextButton && [_delegate respondsToSelector:@selector(playerViewControllerDidRequestNextItem:)]) {
    [_delegate playerViewControllerDidRequestNextItem:self];
  } else if(button==_controls.audioButton && [_delegate respondsToSelector:@selector(playerViewController:didRequestAudioOnly:)]) {
    [_delegate playerViewController:self didRequestAudioOnly:!_audioOnly];
  } else if(button==_controls.doneButton) {
    if([_delegate respondsToSelector:@selector(playerViewControllerDidRequestDismissal:)]) [_delegate playerViewControllerDidRequestDismissal:self];
    else if(self.navigationController.presentingViewController) [self.navigationController dismissViewControllerAnimated:YES completion:nil];
  }
}

- (void)scrubBegan:(UISlider *)slider {
  if(!slider.enabled || !_visible || !_active || !self.view.userInteractionEnabled) return;
  [self cancelHide];
  if(!_scrubItem) {
    _scrubItem=[_player.currentItem retain];
    _scrubTime=kCMTimeInvalid;
  }
  _scrubbing=YES;
}
- (void)scrubChanged:(UISlider *)slider {
  /* VoiceOver adjusts a slider without touch-down/up events. */
  BOOL accessibility=!slider.tracking && !_scrubbing;
  if(accessibility) [self scrubBegan:slider];
  if(!_scrubItem) return;
  double duration=CMTimeGetSeconds(_scrubItem.duration);
  if(_scrubItem==_player.currentItem && _scrubItem.status==AVPlayerItemStatusReadyToPlay && isfinite(duration) && duration>0) {
    CMTime time=CMTimeMakeWithSeconds(slider.value*duration,600);
    if(!CMTIME_IS_VALID(_scrubTime) || CMTimeCompare(time,_scrubTime)!=0) {
      _scrubTime=time;
      [_controls setElapsedTime:slider.value*duration duration:duration];
      if(!_seeking) [self seekToScrubTime];
    }
  }
  if(accessibility) { _scrubbing=NO; [self finishScrubbing]; }
}
- (void)scrubEnded:(UISlider *)slider {
  if(!_scrubbing) return;
  [self scrubChanged:slider];
  _scrubbing=NO;
  [self finishScrubbing];
}
- (void)seekToScrubTime {
  /* One seek in flight, one latest target. Never queue every drag event.
   * https://developer.apple.com/library/archive/qa/qa1820/_index.html */
  _seeking=YES;
  CMTime time=_scrubTime;
  NSUInteger generation=++_seekGeneration;
  [_player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
    (void)finished;
    dispatch_async(dispatch_get_main_queue(), ^{
      /* Item/lifecycle changes invalidate completions, including same-item reentry. */
      if(generation!=_seekGeneration) return;
      _seeking=NO;
      if(CMTimeCompare(time,_scrubTime)!=0) [self seekToScrubTime];
      else [self finishScrubbing];
    });
  }];
}
- (void)resetScrubbing {
  ++_seekGeneration;
  _scrubbing=_seeking=NO;
  [_scrubItem release]; _scrubItem=nil;
}
- (void)finishScrubbing {
  /* Do not read the old player time while the final seek is still pending. */
  if(_scrubbing || _seeking) return;
  [self resetScrubbing];
  [self refreshTime];
  [self scheduleHide];
}
@end
