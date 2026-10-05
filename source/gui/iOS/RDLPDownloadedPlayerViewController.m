#import "RDLPDownloadedPlayerViewController.h"
#import "RDLPLibrary.h"
#import "RDLPUIKit.h"
#import "player/RDLPPlayerContent.h"
#import <MediaPlayer/MediaPlayer.h>
#import <math.h>

static void *RDLPDownloadObservation=&RDLPDownloadObservation;
static RDLPDownloadedPlayerViewController *RDLPActivePlayback=nil; // nonretained
static NSArray *RDLPDownloadItemKeys(void) {
  return [NSArray arrayWithObjects:@"status",@"duration",@"playbackBufferEmpty",nil];
}
@interface RDLPDownloadedPlayerViewController () <RDLPPlaybackRemoteTarget> {
  RDLPLibrary *_library;
  NSArray *_jobs;
  NSString *_video;
  NSDictionary *_metadata;
  AVPlayerItem *_item;
  id _checkpointObserver, _remoteCommands;
  double _resume, _savedPosition;
  float _observedRate;
  BOOL _started, _stopped, _ready, _preparing, _finished, _observingRate;
  BOOL _wantsPlay, _resumeAfterInterruption, _selecting, _changingItem;
  BOOL _restoreVideoWhenActive;
}
- (void)refreshPlayback;
- (void)playbackRateChanged;
- (void)saveProgress;
- (void)scheduleProgressSave;
- (void)updateNowPlaying;
- (void)play;
- (void)queueChanged:(NSNotification *)notification;
- (void)unobserveItem;
- (void)selectIndex:(NSUInteger)index;
- (void)navigateBackward:(BOOL)backward;
@end

@implementation RDLPDownloadedPlayerViewController
@synthesize queue=_queue, playerViewController=_playerViewController;
- (AVPlayer *)player { return [_queue player]; }
- (id)initWithLibrary:(RDLPLibrary *)library job:(NSDictionary *)job URL:(NSURL *)URL {
  return [self initWithLibrary:library jobs:[NSArray arrayWithObject:job]
    URLs:[NSArray arrayWithObject:URL] startingAtIndex:0];
}
- (id)initWithLibrary:(RDLPLibrary *)library jobs:(NSArray *)jobs URLs:(NSArray *)URLs startingAtIndex:(NSUInteger)index {
  self=[super init]; if(!self) return nil;
  if(![jobs count] || [jobs count]!=[URLs count] || index>=[jobs count]) { [self release]; return nil; }
  for(id job in jobs) {
    if(![job isKindOfClass:[NSDictionary class]] ||
       ![[job objectForKey:@"video_id"] isKindOfClass:[NSString class]] ||
       ![[job objectForKey:@"video_id"] length]) { [self release]; return nil; }
  }
  _library=[library retain]; _jobs=[[NSArray alloc] initWithArray:jobs copyItems:YES];
  _queue=[[RDLPPlayerQueue alloc] init];
  if(![_queue setPlaylist:URLs startingAtIndex:index]) { [self release]; return nil; }
  _playerViewController=[[RDLPPlayerViewController alloc] init];
  [_playerViewController setPlayer:[_queue player]];
  [_playerViewController setDelegate:self];
  [self setViewControllers:[NSArray arrayWithObject:_playerViewController]];
  [[self player] addObserver:self forKeyPath:@"rate" options:0 context:RDLPDownloadObservation];
  _observingRate=YES;
  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(queueChanged:) name:RDLPPlayerQueueDidChangeNotification object:_queue];
  [center addObserver:self selector:@selector(applicationInactive:) name:UIApplicationWillResignActiveNotification object:nil];
  [center addObserver:self selector:@selector(applicationInactive:) name:UIApplicationDidEnterBackgroundNotification object:nil];
  [center addObserver:self selector:@selector(applicationActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
  [center addObserver:self selector:@selector(applicationTerminating:) name:UIApplicationWillTerminateNotification object:nil];
  [self queueChanged:nil];
  return self;
}
- (void)dealloc {
  [self stop];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self unobserveItem];
  if(_observingRate) [[self player] removeObserver:self forKeyPath:@"rate" context:RDLPDownloadObservation];
  [_playerViewController setDelegate:nil];
  [_playerViewController release];
  [_queue release]; [_jobs release]; [_library release]; [_video release]; [_metadata release];
  [super dealloc];
}
- (void)unobserveItem {
  if(!_item) return;
  for(NSString *key in RDLPDownloadItemKeys())
    [_item removeObserver:self forKeyPath:key context:RDLPDownloadObservation];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:_item];
  [_item cancelPendingSeeks]; [_item release]; _item=nil;
}
- (void)queueChanged:(NSNotification *)notification {
  (void)notification;
  [_playerViewController setCanSkipToPreviousItem:[_queue canSkipToPreviousItem]];
  [_playerViewController setCanSkipToNextItem:[_queue canSkipToNextItem]];
  [_playerViewController setAudioOnly:[_queue isAudioOnly]];
  if(_stopped || _item==[[self player] currentItem]) return;
  [self saveProgress]; // Read the outgoing item, even after AVQueuePlayer advances.
  /* The completed item may no longer expose a valid time once removed. Native
   * advancement still means completion; reset before reading the next bookmark. */
  if(!_selecting && _item && [[self player] currentItem] && _ready && _savedPosition!=0) {
    [_library savePlaybackSeconds:0 forVideo:_video]; _savedPosition=0;
  }
  _changingItem=YES;
  if(!_selecting) _wantsPlay=_started; // Native advancement continues playback.
  _ready=NO; _preparing=NO; _finished=NO;
  [[self player] pause];
  [self unobserveItem];
  [_video release]; _video=nil; [_metadata release]; _metadata=nil;
  [_playerViewController setTitle:nil];
  _item=[[[self player] currentItem] retain];
  if(_item && [_queue currentIndex]<[_jobs count]) {
    NSDictionary *job=[_jobs objectAtIndex:[_queue currentIndex]];
    _video=[[job objectForKey:@"video_id"] copy];
    _resume=[_library playbackSecondsForVideo:_video];
    if(!isfinite(_resume) || _resume<0) _resume=0;
    _savedPosition=_resume;
    NSString *title=[job objectForKey:@"title"], *channel=[job objectForKey:@"channel"];
    if(![title length]) title=[_video length]?_video:NSLocalizedString(@"Video", nil);
    [_playerViewController setTitle:title];
    NSMutableDictionary *metadata=[NSMutableDictionary dictionaryWithObject:title forKey:MPMediaItemPropertyTitle];
    if([channel length]) [metadata setObject:channel forKey:MPMediaItemPropertyArtist];
    _metadata=[metadata copy];
    for(NSString *key in RDLPDownloadItemKeys())
      [_item addObserver:self forKeyPath:key options:0 context:RDLPDownloadObservation];
    NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    [center addObserver:self selector:@selector(itemFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:_item];
    [center addObserver:self selector:@selector(timeChanged:) name:AVPlayerItemTimeJumpedNotification object:_item];
  }
  _changingItem=NO;
  if([_playerViewController isViewLoaded]) [[_playerViewController view] setUserInteractionEnabled:YES];
  [self refreshPlayback];
}
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if(_stopped) return;
  if(_started) { [self becomeFirstResponder]; return; }
  [RDLPActivePlayback stop]; RDLPActivePlayback=self;
  _started=YES; _wantsPlay=YES;
  [RDLPUIKit activatePlaybackAudioSessionForDelegate:self];
  _remoteCommands=[[RDLPUIKit playbackRemoteCommandsForTarget:self] retain];
  if(!_remoteCommands) [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
  [self becomeFirstResponder];
  __block RDLPDownloadedPlayerViewController *owner=self; // MRC: observer must not retain its owner
  _checkpointObserver=[[[self player] addPeriodicTimeObserverForInterval:CMTimeMake(10,1)
    queue:dispatch_get_main_queue() usingBlock:^(CMTime time) { (void)time; [owner scheduleProgressSave]; }] retain];
  [self refreshPlayback];
}
- (void)viewWillDisappear:(BOOL)animated {
  if([self isBeingDismissed] || [[self navigationController] isBeingDismissed] || [self isMovingFromParentViewController])
    [self stop];
  [super viewWillDisappear:animated];
}
- (void)stop {
  if(_stopped) return;
  [self saveProgress]; _stopped=YES; _wantsPlay=NO; _resumeAfterInterruption=NO;
  _restoreVideoWhenActive=NO;
  if(_checkpointObserver) {
    [[self player] removeTimeObserver:_checkpointObserver]; [_checkpointObserver release]; _checkpointObserver=nil;
  }
  [[self player] pause]; [_item cancelPendingSeeks];
  if(RDLPActivePlayback==self) {
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
    RDLPActivePlayback=nil;
    [self resignFirstResponder];
    if(_remoteCommands) {
      [RDLPUIKit stopPlaybackRemoteCommands:_remoteCommands];
      [_remoteCommands release]; _remoteCommands=nil;
    } else [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [RDLPUIKit deactivatePlaybackAudioSessionForDelegate:self];
  }
}
- (void)refreshPlayback {
  if(!_started || _stopped || _changingItem || _item!=[[self player] currentItem]) return;
  if(!_ready && !_preparing && [_item status]==AVPlayerItemStatusReadyToPlay) {
    double duration=CMTimeGetSeconds([_item duration]);
    _resume=RDLPPlayerResumePosition(_resume,duration);
    _preparing=YES;
    /* Prevent a Play tap or scrub racing the single initial resume seek. */
    [[_playerViewController view] setUserInteractionEnabled:NO];
    AVPlayerItem *item=_item;
    [item seekToTime:CMTimeMakeWithSeconds(_resume,600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero
      completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if(_stopped || item!=_item) return; // A skip can finish an older seek later.
          [[_playerViewController view] setUserInteractionEnabled:YES];
          _preparing=NO;
          _ready=finished;
          if(_ready && _wantsPlay) [[self player] play];
          [self scheduleProgressSave];
          [self updateNowPlaying];
        });
      }];
  }
  if([[self player] rate]!=0) _finished=NO;
  [self updateNowPlaying];
}
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  if(context!=RDLPDownloadObservation) { [super observeValueForKeyPath:key ofObject:object change:change context:context]; return; }
  SEL action=[key isEqualToString:@"rate"]?@selector(playbackRateChanged):@selector(refreshPlayback);
  if(![NSThread isMainThread]) {
    [self performSelectorOnMainThread:action withObject:nil waitUntilDone:NO]; return;
  }
  [self performSelector:action];
}
- (void)playbackRateChanged {
  BOOL paused=_observedRate!=0 && [[self player] rate]==0;
  _observedRate=[[self player] rate];
  [self refreshPlayback];
  if(paused) [self saveProgress];
}
- (void)updateNowPlaying {
  if(!_started || _stopped || _changingItem || RDLPActivePlayback!=self) return;
  BOOL available=_item && [_item status]!=AVPlayerItemStatusFailed && [[self player] status]!=AVPlayerStatusFailed;
  double commandDuration=_item?CMTimeGetSeconds([_item duration]):NAN;
  BOOL canSeek=available && _ready && !_preparing && isfinite(commandDuration) && commandDuration>0;
  [RDLPUIKit updatePlaybackRemoteCommands:_remoteCommands longContent:RDLPPlayerContentIsLong(commandDuration)!=0
    available:available canSeek:canSeek canPrevious:[_queue canSkipToPreviousItem] canNext:[_queue canSkipToNextItem]];
  if(!_item || _finished || [_item status]==AVPlayerItemStatusFailed || [[self player] status]==AVPlayerStatusFailed) {
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil]; return;
  }
  double seconds=_ready?CMTimeGetSeconds([_item currentTime]):_resume;
  double duration=CMTimeGetSeconds([_item duration]);
  if(!isfinite(seconds) || seconds<0) seconds=_resume;
  if(isfinite(duration) && duration>0) seconds=MIN(seconds,duration);
  NSMutableDictionary *info=[[_metadata mutableCopy] autorelease];
  [info setObject:[NSNumber numberWithDouble:seconds] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
  [info setObject:[NSNumber numberWithFloat:_ready && ![_item isPlaybackBufferEmpty]?[[self player] rate]:0]
          forKey:MPNowPlayingInfoPropertyPlaybackRate];
  if(isfinite(duration) && duration>0)
    [info setObject:[NSNumber numberWithDouble:duration] forKey:MPMediaItemPropertyPlaybackDuration];
  [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:info];
}
- (void)scheduleProgressSave {
  if(!_ready || _preparing || _stopped || _changingItem) return;
  /* Seeks (including paused seeks) may arrive in bursts. Sample the final
   * position after settling; ordinary playback checkpoints every ten seconds. */
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveProgress) object:nil];
  [self performSelector:@selector(saveProgress) withObject:nil afterDelay:0.5];
}
- (void)saveProgress {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveProgress) object:nil];
  if(!_ready || _preparing || _stopped || _changingItem || [_item status]!=AVPlayerItemStatusReadyToPlay) return;
  double seconds=CMTimeGetSeconds([_item currentTime]), duration=CMTimeGetSeconds([_item duration]);
  if(!isfinite(seconds) || seconds<0) return;
  /* Classify the item being saved, which may be the outgoing queue item. */
  seconds=RDLPPlayerResumePosition(seconds,duration);
  if(seconds==_savedPosition) return;
  _savedPosition=seconds;
  [_library savePlaybackSeconds:seconds forVideo:_video];
}
- (void)itemEnded:(NSNotification *)notification {
  if(![NSThread isMainThread]) { [self performSelectorOnMainThread:_cmd withObject:notification waitUntilDone:NO]; return; }
  if(_stopped || [notification object]!=_item) return;
  [self saveProgress];
  _finished=YES; [self updateNowPlaying];
}
- (void)itemFailed:(NSNotification *)notification {
  if(![NSThread isMainThread]) { [self performSelectorOnMainThread:_cmd withObject:notification waitUntilDone:NO]; return; }
  if([notification object]!=_item) return;
  _finished=YES; [self updateNowPlaying];
}
- (void)timeChanged:(NSNotification *)notification {
  if(![NSThread isMainThread]) { [self performSelectorOnMainThread:_cmd withObject:notification waitUntilDone:NO]; return; }
  if([notification object]!=_item) return;
  [self scheduleProgressSave]; [self updateNowPlaying];
}
- (void)applicationInactive:(NSNotification *)notification {
  (void)notification;
  if(!_started || _stopped) return;
  if(![_queue isAudioOnly]) {
    /* Use the same transition as the button, before iOS 6 locks/suspends video.
     * Repeated resign/background notifications must not lose this flag. */
    [self playerViewController:_playerViewController didRequestAudioOnly:YES];
    _restoreVideoWhenActive=YES;
  }
  [self saveProgress]; [self updateNowPlaying];
}
- (void)applicationActive:(NSNotification *)notification {
  (void)notification;
  if(!_started || _stopped) return;
  if(_restoreVideoWhenActive)
    [self playerViewController:_playerViewController didRequestAudioOnly:NO];
  [self updateNowPlaying];
}
- (void)applicationTerminating:(NSNotification *)notification { (void)notification; [self stop]; }
- (void)playerViewController:(RDLPPlayerViewController *)controller didRequestAudioOnly:(BOOL)audioOnly {
  (void)controller;
  if(_stopped) return;
  _restoreVideoWhenActive=NO; // An explicit choice supersedes automatic restoration.
  [_queue setAudioOnly:audioOnly];
}
- (void)selectIndex:(NSUInteger)index {
  if(_stopped || index>=[_jobs count] || index==[_queue currentIndex]) return;
  _wantsPlay=_ready?[[self player] rate]!=0:_wantsPlay;
  _selecting=YES;
  [self saveProgress]; [[self player] pause];
  [_queue selectItemAtIndex:index];
  _selecting=NO;
}
/* Both on-screen buttons and system remote controls use these same rules. */
- (void)navigateBackward:(BOOL)backward {
  if(_stopped) return;
  AVPlayer *player=[self player];
  AVPlayerItem *item=[player currentItem];
  if(!item) return;
  double duration=CMTimeGetSeconds([item duration]);
  double seconds=CMTimeGetSeconds([item currentTime]);
  BOOL longContent=RDLPPlayerContentIsLong(duration)!=0;
  if(longContent || (backward && isfinite(seconds) && seconds>5)) {
    if([item status]!=AVPlayerItemStatusReadyToPlay || [player status]==AVPlayerStatusFailed ||
       !isfinite(seconds) || !isfinite(duration) || duration<=0) return;
    double target=longContent?seconds+(backward?-30:60):0;
    [player seekToTime:CMTimeMakeWithSeconds(MAX(0,MIN(duration,target)),600)
      toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
  } else if(backward) {
    if([_queue canSkipToPreviousItem]) [self selectIndex:[_queue currentIndex]-1];
  } else {
    if([_queue canSkipToNextItem]) [self selectIndex:[_queue currentIndex]+1];
  }
}
- (void)playerViewControllerDidRequestBack:(RDLPPlayerViewController *)controller {
  (void)controller; [self navigateBackward:YES];
}
- (void)playerViewControllerDidRequestForward:(RDLPPlayerViewController *)controller {
  (void)controller; [self navigateBackward:NO];
}
- (void)playerViewControllerDidRequestDismissal:(RDLPPlayerViewController *)controller {
  (void)controller; [self stop];
  [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)play {
  if(_stopped) return;
  _wantsPlay=YES;
  [[AVAudioSession sharedInstance] setActive:YES error:NULL];
  if(!_ready) return;
  double duration=CMTimeGetSeconds([_item duration]);
  if(isfinite(duration) && duration>0 && CMTimeGetSeconds([[self player] currentTime])>=duration)
    [[self player] seekToTime:kCMTimeZero];
  [[self player] play];
}
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
  if(_stopped || [event type]!=UIEventTypeRemoteControl) return;
  [self handlePlaybackRemoteControl:[event subtype]];
}
- (BOOL)handlePlaybackRemoteControl:(UIEventSubtype)subtype {
  if(_stopped) return NO;
  switch(subtype) {
    case UIEventSubtypeRemoteControlPlay: [self play]; break;
    case UIEventSubtypeRemoteControlTogglePlayPause:
      if([[self player] rate]==0 && !(!_ready && _wantsPlay)) { [self play]; break; }
      /* fall through */
    case UIEventSubtypeRemoteControlPause:
    case UIEventSubtypeRemoteControlStop:
      _wantsPlay=NO; _resumeAfterInterruption=NO; [self saveProgress]; [[self player] pause]; break;
    case UIEventSubtypeRemoteControlNextTrack:
      [self navigateBackward:NO]; break;
    case UIEventSubtypeRemoteControlPreviousTrack:
      [self navigateBackward:YES]; break;
    default: return NO;
  }
  return YES;
}
- (void)beginInterruption {
  _resumeAfterInterruption=[[self player] rate]!=0 || (!_ready && _wantsPlay);
  _wantsPlay=NO; [[self player] pause]; [self updateNowPlaying];
}
- (void)endInterruptionWithFlags:(NSUInteger)flags {
  BOOL resume=_resumeAfterInterruption; _resumeAfterInterruption=NO;
  if(resume && [RDLPUIKit shouldResumePlaybackAfterInterruptionFlags:flags]) [self play];
}
@end
