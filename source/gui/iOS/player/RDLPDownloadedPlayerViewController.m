#import "RDLPDownloadedPlayerViewController.h"
#import "RDLPLibrary.h"
#import <MediaPlayer/MediaPlayer.h>
#import <math.h>

/* AVAudioSessionDelegate is the interruption API available on iOS 5. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static void *RDLPDownloadObservation=&RDLPDownloadObservation;
static RDLPDownloadedPlayerViewController *RDLPActivePlayback=nil; // nonretained
static NSArray *RDLPDownloadItemKeys(void) {
  return [NSArray arrayWithObjects:@"status",@"duration",@"playbackBufferEmpty",nil];
}
static double RDLPResumePosition(double seconds,double duration) {
  if(isfinite(duration) && duration>0 && (seconds<=duration*0.1 || seconds>=duration*0.9)) return 0;
  return seconds;
}
@interface RDLPDownloadedPlayerViewController () {
  RDLPLibrary *_library;
  NSString *_video;
  NSDictionary *_metadata;
  AVPlayerItem *_item;
  id _checkpointObserver;
  double _resume, _savedPosition;
  float _observedRate;
  BOOL _started, _stopped, _ready, _preparing, _finished;
  BOOL _wantsPlay, _resumeAfterInterruption;
}
- (void)refreshPlayback;
- (void)playbackRateChanged;
- (void)saveProgress;
- (void)scheduleProgressSave;
- (void)updateNowPlaying;
- (void)play;
@end

@implementation RDLPDownloadedPlayerViewController
@synthesize queue=_queue;
- (id)initWithLibrary:(RDLPLibrary *)library job:(NSDictionary *)job URL:(NSURL *)URL {
  self=[super init]; if(!self) return nil;
  _library=[library retain]; _video=[[job objectForKey:@"video_id"] copy];
  _resume=[library playbackSecondsForVideo:_video];
  if(!isfinite(_resume) || _resume<0) _resume=0;
  _savedPosition=_resume;
  NSString *title=[job objectForKey:@"title"], *channel=[job objectForKey:@"channel"];
  if(!title.length) title=_video.length?_video:@"Video";
  NSMutableDictionary *metadata=[NSMutableDictionary dictionaryWithObject:title forKey:MPMediaItemPropertyTitle];
  if(channel.length) [metadata setObject:channel forKey:MPMediaItemPropertyArtist];
  _metadata=[metadata copy];
  _queue=[[RDLPPlayerQueue alloc] init];
  [_queue setPlaylist:[NSArray arrayWithObject:URL] startingAtIndex:0];
  self.player=_queue.player; self.delegate=self;
  _item=[self.player.currentItem retain];
  for(NSString *key in RDLPDownloadItemKeys())
    [_item addObserver:self forKeyPath:key options:0 context:RDLPDownloadObservation];
  [self.player addObserver:self forKeyPath:@"rate" options:0 context:RDLPDownloadObservation];
  NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
  [center addObserver:self selector:@selector(itemFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:_item];
  [center addObserver:self selector:@selector(timeChanged:) name:AVPlayerItemTimeJumpedNotification object:_item];
  [center addObserver:self selector:@selector(applicationInactive:) name:UIApplicationWillResignActiveNotification object:nil];
  [center addObserver:self selector:@selector(applicationInactive:) name:UIApplicationDidEnterBackgroundNotification object:nil];
  [center addObserver:self selector:@selector(applicationActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
  [center addObserver:self selector:@selector(applicationTerminating:) name:UIApplicationWillTerminateNotification object:nil];
  return self;
}
- (void)dealloc {
  [self stop];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  for(NSString *key in RDLPDownloadItemKeys())
    [_item removeObserver:self forKeyPath:key context:RDLPDownloadObservation];
  [self.player removeObserver:self forKeyPath:@"rate" context:RDLPDownloadObservation];
  self.delegate=nil;
  [_item release]; [_queue release]; [_library release]; [_video release]; [_metadata release];
  [super dealloc];
}
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if(_started || _stopped) return;
  [RDLPActivePlayback stop]; RDLPActivePlayback=self;
  _started=YES; _wantsPlay=YES;
  AVAudioSession *session=[AVAudioSession sharedInstance]; NSError *error=nil;
  session.delegate=self;
  if(![session setCategory:AVAudioSessionCategoryPlayback error:&error] || ![session setActive:YES error:&error])
    NSLog(@"Could not activate playback audio session: %@",error);
  [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
  [self becomeFirstResponder];
  __block RDLPDownloadedPlayerViewController *owner=self; // MRC: observer must not retain its owner
  _checkpointObserver=[[self.player addPeriodicTimeObserverForInterval:CMTimeMake(10,1)
    queue:dispatch_get_main_queue() usingBlock:^(CMTime time) { (void)time; [owner scheduleProgressSave]; }] retain];
  [self refreshPlayback];
}
- (void)viewWillDisappear:(BOOL)animated {
  [self stop];
  [super viewWillDisappear:animated];
}
- (void)stop {
  if(_stopped) return;
  [self saveProgress]; _stopped=YES; _wantsPlay=NO; _resumeAfterInterruption=NO;
  if(_checkpointObserver) {
    [self.player removeTimeObserver:_checkpointObserver]; [_checkpointObserver release]; _checkpointObserver=nil;
  }
  [self.player pause]; [_item cancelPendingSeeks];
  if(RDLPActivePlayback==self) {
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo=nil;
    RDLPActivePlayback=nil;
    [self resignFirstResponder];
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    AVAudioSession *session=[AVAudioSession sharedInstance];
    if(session.delegate==self) session.delegate=nil;
    [session setActive:NO withFlags:AVAudioSessionSetActiveFlags_NotifyOthersOnDeactivation error:NULL];
  }
}
- (void)refreshPlayback {
  if(!_started || _stopped) return;
  if(!_ready && !_preparing && _item.status==AVPlayerItemStatusReadyToPlay) {
    double duration=CMTimeGetSeconds(_item.duration);
    _resume=RDLPResumePosition(_resume,duration);
    _preparing=YES;
    /* Prevent a Play tap or scrub racing the single initial resume seek. */
    self.view.userInteractionEnabled=NO;
    [self.player seekToTime:CMTimeMakeWithSeconds(_resume,600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero
      completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
          self.view.userInteractionEnabled=YES;
          _preparing=NO;
          if(_stopped) return;
          _ready=finished;
          if(_ready && _wantsPlay) [self.player play];
          [self scheduleProgressSave];
          [self updateNowPlaying];
        });
      }];
  }
  if(self.player.rate!=0) _finished=NO;
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
  BOOL paused=_observedRate!=0 && self.player.rate==0;
  _observedRate=self.player.rate;
  [self refreshPlayback];
  if(paused) [self saveProgress];
}
- (void)updateNowPlaying {
  if(!_started || _stopped || RDLPActivePlayback!=self) return;
  if(_finished || _item.status==AVPlayerItemStatusFailed || self.player.status==AVPlayerStatusFailed) {
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo=nil; return;
  }
  double seconds=_ready?CMTimeGetSeconds(self.player.currentTime):_resume;
  double duration=CMTimeGetSeconds(_item.duration);
  if(!isfinite(seconds) || seconds<0) seconds=_resume;
  if(isfinite(duration) && duration>0) seconds=MIN(seconds,duration);
  NSMutableDictionary *info=[[_metadata mutableCopy] autorelease];
  [info setObject:[NSNumber numberWithDouble:seconds] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
  [info setObject:[NSNumber numberWithFloat:_ready && !_item.playbackBufferEmpty?self.player.rate:0]
          forKey:MPNowPlayingInfoPropertyPlaybackRate];
  if(isfinite(duration) && duration>0)
    [info setObject:[NSNumber numberWithDouble:duration] forKey:MPMediaItemPropertyPlaybackDuration];
  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo=info;
}
- (void)scheduleProgressSave {
  if(!_ready || _preparing || _stopped) return;
  /* Seeks (including paused seeks) may arrive in bursts. Sample the final
   * position after settling; ordinary playback checkpoints every ten seconds. */
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveProgress) object:nil];
  [self performSelector:@selector(saveProgress) withObject:nil afterDelay:0.5];
}
- (void)saveProgress {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveProgress) object:nil];
  if(!_ready || _preparing || _stopped || _item.status!=AVPlayerItemStatusReadyToPlay) return;
  double seconds=CMTimeGetSeconds(self.player.currentTime), duration=CMTimeGetSeconds(_item.duration);
  if(!isfinite(seconds) || seconds<0) return;
  seconds=RDLPResumePosition(seconds,duration);
  if(seconds==_savedPosition) return;
  _savedPosition=seconds;
  [_library savePlaybackSeconds:seconds forVideo:_video];
}
- (void)itemEnded:(NSNotification *)notification {
  (void)notification;
  if(_stopped) return;
  [self saveProgress];
  _finished=YES; [self updateNowPlaying];
}
- (void)itemFailed:(NSNotification *)notification {
  (void)notification; _finished=YES; [self updateNowPlaying];
}
- (void)timeChanged:(NSNotification *)notification { (void)notification; [self scheduleProgressSave]; [self updateNowPlaying]; }
- (void)applicationInactive:(NSNotification *)notification { (void)notification; [self saveProgress]; [self updateNowPlaying]; }
- (void)applicationActive:(NSNotification *)notification { (void)notification; [self updateNowPlaying]; }
- (void)applicationTerminating:(NSNotification *)notification { (void)notification; [self stop]; }
- (void)playerViewController:(RDLPPlayerViewController *)controller didRequestAudioOnly:(BOOL)audioOnly {
  (void)controller; _queue.audioOnly=audioOnly; self.audioOnly=audioOnly;
}
- (void)playerViewControllerDidRequestDismissal:(RDLPPlayerViewController *)controller {
  (void)controller; [self stop]; [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)play {
  if(_stopped) return;
  _wantsPlay=YES;
  [[AVAudioSession sharedInstance] setActive:YES error:NULL];
  if(!_ready) return;
  double duration=CMTimeGetSeconds(_item.duration);
  if(isfinite(duration) && duration>0 && CMTimeGetSeconds(self.player.currentTime)>=duration)
    [self.player seekToTime:kCMTimeZero];
  [self.player play];
}
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
  if(_stopped || event.type!=UIEventTypeRemoteControl) return;
  switch(event.subtype) {
    case UIEventSubtypeRemoteControlPlay: [self play]; break;
    case UIEventSubtypeRemoteControlTogglePlayPause:
      if(self.player.rate==0 && !(_preparing && _wantsPlay)) { [self play]; break; }
      /* fall through */
    case UIEventSubtypeRemoteControlPause:
    case UIEventSubtypeRemoteControlStop:
      _wantsPlay=NO; _resumeAfterInterruption=NO; [self saveProgress]; [self.player pause]; break;
    default: break; // A one-item playlist has no next/previous destination.
  }
}
- (void)beginInterruption {
  _resumeAfterInterruption=self.player.rate!=0 || (_preparing && _wantsPlay);
  _wantsPlay=NO; [self.player pause]; [self updateNowPlaying];
}
- (void)endInterruptionWithFlags:(NSUInteger)flags {
  BOOL resume=_resumeAfterInterruption; _resumeAfterInterruption=NO;
  if(resume && (flags & AVAudioSessionInterruptionFlags_ShouldResume)) [self play];
}
@end
#pragma clang diagnostic pop
