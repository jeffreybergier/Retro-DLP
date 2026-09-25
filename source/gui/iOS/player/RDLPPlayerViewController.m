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
static NSArray *RDLPItemKeys(void) { return [NSArray arrayWithObjects:@"status",@"duration",@"playbackBufferEmpty",nil]; }

@interface RDLPPlayerViewController () <UIGestureRecognizerDelegate> {
  RDLPPlayerControls *_controls;
  AVPlayerItem *_observedItem, *_scrubItem;
  id _timeObserver;
  BOOL _visible, _active, _observing, _chromeVisible, _failedToEnd;
}
- (void)configure;
- (void)refresh;
- (void)refreshTime;
- (void)updatePresentation;
- (void)startObserving;
- (void)stopObserving;
- (void)observeCurrentItem;
- (void)showControls;
- (void)scheduleHide;
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
  /* Match the app's iOS 5-compatible extended-edge configuration. */
  if([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
    [self setValue:[NSNumber numberWithUnsignedInteger:0] forKey:@"edgesForExtendedLayout"];
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
                    _controls.nextButton,_controls.playlistButton,_controls.audioButton,_controls.scaleButton,nil];
  for(UIButton *button in buttons) {
    [button addTarget:self action:@selector(buttonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(cancelHide) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(scheduleHide) forControlEvents:UIControlEventTouchUpOutside|UIControlEventTouchCancel];
  }
  [_controls.slider addTarget:self action:@selector(scrubBegan:) forControlEvents:UIControlEventTouchDown];
  [_controls.slider addTarget:self action:@selector(scrubChanged:) forControlEvents:UIControlEventValueChanged];
  [_controls.slider addTarget:self action:@selector(scrubEnded:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
  [_controls.slider addTarget:self action:@selector(scrubCancelled:) forControlEvents:UIControlEventTouchCancel];
  UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleControls:)];
  tap.delegate=self;
  [self.view addGestureRecognizer:tap]; [tap release];
  [self updatePresentation];
  [self refresh];
  [self showControls];
}
- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  _visible=YES;
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
}
- (void)viewDidUnload {
  [self cancelHide];
  [self stopObserving];
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
  [self refresh];
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
  [_scrubItem release]; _scrubItem=nil;
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
  [_scrubItem release]; _scrubItem=nil;
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
  if([notification.name isEqualToString:AVPlayerItemFailedToPlayToEndTimeNotification]) _failedToEnd=YES;
  [self refresh];
}

- (void)refresh {
  if(_observing) [self observeCurrentItem];
  if(!_controls) return;
  AVPlayerItem *item=_player.currentItem;
  BOOL failed=_player.status==AVPlayerStatusFailed || item.status==AVPlayerItemStatusFailed || _failedToEnd;
  BOOL ready=item && item.status==AVPlayerItemStatusReadyToPlay && !failed;
  _controls.playButton.enabled=ready;
  _controls.playButton.selected=_player.rate!=0;
  _controls.playButton.accessibilityLabel=_player.rate!=0?@"Pause":@"Play";
  _controls.previousButton.enabled=_player && _canSkipToPreviousItem && [_delegate respondsToSelector:@selector(playerViewControllerDidRequestPreviousItem:)];
  _controls.nextButton.enabled=_player && _canSkipToNextItem && [_delegate respondsToSelector:@selector(playerViewControllerDidRequestNextItem:)];
  _controls.playlistButton.hidden=![_delegate respondsToSelector:@selector(playerViewControllerDidRequestPlaylist:)];
  _controls.audioButton.hidden=![_delegate respondsToSelector:@selector(playerViewController:didRequestAudioOnly:)];
  _controls.audioButton.enabled=_player!=nil;
  _controls.audioButton.selected=_audioOnly;
  _controls.audioButton.accessibilityLabel=_audioOnly?@"Show video":@"Use audio only";
  _controls.doneButton.hidden=![_delegate respondsToSelector:@selector(playerViewControllerDidRequestDismissal:)] &&
                             !(self.presentingViewController && !self.parentViewController);
  _controls.scaleButton.hidden=_audioOnly;
  _controls.scaleButton.enabled=ready;
  _controls.scaleButton.selected=[_videoGravity isEqualToString:AVLayerVideoGravityResizeAspectFill];
  _controls.scaleButton.accessibilityLabel=_controls.scaleButton.selected?@"Fit video":@"Fill screen";
  BOOL loading=item && !failed && (!ready || (_player.rate!=0 && item.playbackBufferEmpty));
  NSString *message=failed?@"Unable to play this item":(!item?@"No media":(_audioOnly?@"Audio Only":nil));
  [_controls setMessage:loading?nil:message loading:loading];
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
  [_controls setChromeVisible:_chromeVisible animated:NO];
  [self scheduleHide];
}
- (void)hideControls {
  if([_controls isTracking]) { [self scheduleHide]; return; }
  _chromeVisible=NO;
  [_controls setChromeVisible:NO animated:YES];
}
- (void)toggleControls:(UITapGestureRecognizer *)tap {
  (void)tap;
  if(!_showsPlaybackControls) return;
  if(_chromeVisible) { [self cancelHide]; [self hideControls]; } else [self showControls];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
  (void)recognizer;
  return ![touch.view isDescendantOfView:_controls];
}

- (void)buttonPressed:(UIButton *)button {
  if(!button.enabled || button.hidden || !_visible || !_active) return;
  [self scheduleHide];
  if(button==_controls.playButton) {
    if(!_player.currentItem) return;
    if(_player.rate!=0) [_player pause];
    else {
      double duration=CMTimeGetSeconds(_player.currentItem.duration);
      if(isfinite(duration) && duration>0 && CMTimeGetSeconds(_player.currentTime)>=duration) [_player seekToTime:kCMTimeZero];
      [_player play];
    }
  } else if(button==_controls.scaleButton) {
    self.videoGravity=button.selected?AVLayerVideoGravityResizeAspect:AVLayerVideoGravityResizeAspectFill;
  } else if(button==_controls.previousButton && [_delegate respondsToSelector:@selector(playerViewControllerDidRequestPreviousItem:)]) {
    [_delegate playerViewControllerDidRequestPreviousItem:self];
  } else if(button==_controls.nextButton && [_delegate respondsToSelector:@selector(playerViewControllerDidRequestNextItem:)]) {
    [_delegate playerViewControllerDidRequestNextItem:self];
  } else if(button==_controls.playlistButton && [_delegate respondsToSelector:@selector(playerViewControllerDidRequestPlaylist:)]) {
    [_delegate playerViewControllerDidRequestPlaylist:self];
  } else if(button==_controls.audioButton && [_delegate respondsToSelector:@selector(playerViewController:didRequestAudioOnly:)]) {
    [_delegate playerViewController:self didRequestAudioOnly:!_audioOnly];
  } else if(button==_controls.doneButton) {
    if([_delegate respondsToSelector:@selector(playerViewControllerDidRequestDismissal:)]) [_delegate playerViewControllerDidRequestDismissal:self];
    else if(self.presentingViewController && !self.parentViewController) [self dismissViewControllerAnimated:YES completion:nil];
  }
}

- (void)scrubBegan:(UISlider *)slider {
  [self cancelHide];
  [_scrubItem release]; _scrubItem=nil;
  if(slider.enabled && _visible && _active) _scrubItem=[_player.currentItem retain];
}
- (void)scrubChanged:(UISlider *)slider {
  /* VoiceOver adjusts a slider without touch-down/up events. */
  if(!slider.tracking && !_scrubItem) { [self scrubBegan:slider]; [self scrubEnded:slider]; return; }
  if(!_scrubItem) return;
  double duration=CMTimeGetSeconds(_scrubItem.duration);
  [_controls setElapsedTime:slider.value*duration duration:duration];
}
- (void)scrubEnded:(UISlider *)slider {
  AVPlayerItem *item=_scrubItem;
  double duration=item?CMTimeGetSeconds(item.duration):NAN;
  if(item && item==_player.currentItem && item.status==AVPlayerItemStatusReadyToPlay && isfinite(duration) && duration>0)
    [_player seekToTime:CMTimeMakeWithSeconds(slider.value*duration,600)];
  [self scrubCancelled:slider];
}
- (void)scrubCancelled:(UISlider *)slider {
  (void)slider;
  [_scrubItem release]; _scrubItem=nil;
  [self refreshTime];
  [self scheduleHide];
}
@end
