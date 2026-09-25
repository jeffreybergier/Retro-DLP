#import "queue_tests.h"
#import "RDLPPlayerQueue.h"
#import "RDLPPlayerViewController.h"
#import "RDLPPlayerControls.h"
#import <math.h>

static void Check(BOOL value, NSString *message) {
  if(!value) [NSException raise:@"Queue test failure" format:@"%@",message];
}

/* A minimal client connects the independent queue and player UI. */
@interface RDLPQueueTests : NSObject <RDLPPlayerViewControllerDelegate> {
@public
  NSURL *URL;
  void (^completion)(NSString *);
@private
  RDLPPlayerQueue *_queue;
  RDLPPlayerViewController *_view;
  NSUInteger _phase, _attempts, _changes;
  BOOL _finished;
}
- (void)start;
@end

@implementation RDLPQueueTests
- (void)start {
  @try {
    _queue=[[RDLPPlayerQueue alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(queueChanged:)
                                                name:RDLPPlayerQueueDidChangeNotification object:_queue];
    Check(_queue.currentIndex==NSNotFound && !_queue.player.currentItem,@"Empty initial queue");
    NSMutableArray *URLs=[NSMutableArray arrayWithObjects:URL,URL,URL,nil];
    Check([_queue setPlaylist:URLs startingAtIndex:1],@"Load playlist at selected index");
    [URLs removeAllObjects];
    Check(_queue.playlist.count==3 && _queue.currentIndex==1,@"Full URL list is copied, including duplicate entries");
    Check(_queue.player.items.count==2 && _queue.player.rate==0,@"Only current and next are prepared, initially paused");
    AVPlayerItem *original=[_queue.player.currentItem retain];
    Check(![_queue setPlaylist:[NSArray arrayWithObject:URL] startingAtIndex:1],@"Invalid start index rejected");
    Check(![_queue setPlaylist:[NSArray arrayWithObject:@"not a URL"] startingAtIndex:0],@"Invalid entry rejected");
    Check(![_queue selectItemAtIndex:NSNotFound] && _queue.player.currentItem==original,@"Invalid operations leave playback intact");
    Check([_queue skipToPreviousItem] && _queue.currentIndex==0 && _queue.player.rate==0,@"Previous preserves paused state");
    Check(![_queue skipToPreviousItem],@"No previous item at start");
    Check([_queue selectItemAtIndex:1] && _queue.player.currentItem!=original,@"Revisiting an entry uses a fresh AVPlayerItem");
    [original release];
    _queue.player.rate=1;
    Check([_queue skipToNextItem] && _queue.currentIndex==2 && _queue.player.rate==1,@"Next preserves playing state");
    [_queue.player pause];
    Check(![_queue skipToNextItem] && _queue.player.items.count==1,@"Last item remains selected at playlist edge");

    _view=[[RDLPPlayerViewController alloc] init];
    _view.player=_queue.player;
    _view.delegate=self;
    [self queueChanged:nil];
    [_view beginAppearanceTransition:YES animated:NO]; [_view endAppearanceTransition];
    RDLPPlayerControls *controls=[_view valueForKey:@"controls"];
    [controls.previousButton.target performSelector:controls.previousButton.action withObject:controls.previousButton];
    Check(_queue.currentIndex==1 && controls.nextButton.enabled,@"UI previous request changes the real queue and updates availability");
    [controls.nextButton.target performSelector:controls.nextButton.action withObject:controls.nextButton];
    Check(_queue.currentIndex==2 && !controls.nextButton.enabled,@"UI next request reaches the playlist end");
    [controls.audioButton.target performSelector:controls.audioButton.action withObject:controls.audioButton];
    Check(_queue.audioOnly && _view.audioOnly,@"Audio-only request updates queue and UI together");
    NSUInteger changes=_changes;
    _queue.audioOnly=YES;
    Check(_changes==changes,@"No duplicate notification for unchanged audio mode");
    [_queue removeAllItems];
    Check(_queue.playlist.count==0 && _queue.currentIndex==NSNotFound && !_queue.player.currentItem &&
          !_queue.canSkipToPreviousItem && !_queue.canSkipToNextItem,@"Clear releases the playlist and disables navigation");

    [_queue setPlaylist:[NSArray arrayWithObjects:URL,URL,URL,nil] startingAtIndex:0];
    Check(_queue.audioOnly,@"Audio preference survives playlist replacement");
    /* Queue must advance after the UI is gone, without any UI polling. */
    [_view beginAppearanceTransition:NO animated:NO]; [_view endAppearanceTransition];
    _view.delegate=nil; [_view release]; _view=nil;
    [self performSelector:@selector(poll) withObject:nil afterDelay:0.1];
  } @catch(NSException *exception) { [self finish:exception.reason]; }
}
- (void)queueChanged:(NSNotification *)notification {
  (void)notification; _changes++;
  _view.canSkipToPreviousItem=_queue.canSkipToPreviousItem;
  _view.canSkipToNextItem=_queue.canSkipToNextItem;
  _view.audioOnly=_queue.audioOnly;
}
- (void)playerViewControllerDidRequestPreviousItem:(RDLPPlayerViewController *)controller {
  (void)controller; [_queue skipToPreviousItem];
}
- (void)playerViewControllerDidRequestNextItem:(RDLPPlayerViewController *)controller {
  (void)controller; [_queue skipToNextItem];
}
- (void)playerViewController:(RDLPPlayerViewController *)controller didRequestAudioOnly:(BOOL)audioOnly {
  (void)controller; _queue.audioOnly=audioOnly;
}
- (void)checkTracks:(AVPlayerItem *)item {
  BOOL videoFound=NO, audioFound=NO;
  for(AVPlayerItemTrack *track in item.tracks) {
    if([track.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) {
      videoFound=YES; Check(!track.enabled,@"Video track disabled on this playlist entry");
    }
    if([track.assetTrack.mediaType isEqualToString:AVMediaTypeAudio]) {
      audioFound=YES; Check(track.enabled,@"Audio remains enabled");
    }
  }
  Check(videoFound && audioFound,@"Fixture has both media tracks");
}
- (void)poll {
  if(_finished) return;
  @try {
    Check(_attempts++<150,@"Timed out waiting for native queue advancement");
    AVPlayerItem *item=_queue.player.currentItem;
    Check(item && item.status!=AVPlayerItemStatusFailed,@"Current playlist entry exists and has not failed");
    Check(_queue.player.items.count<=2,@"Queue preparation stays bounded during automatic advancement");
    if((_phase%2)==0 && item.status==AVPlayerItemStatusReadyToPlay) {
      Check(_queue.currentIndex==_phase/2,@"Playlist advances in order, including duplicate URLs");
      [self checkTracks:item];
      if(_phase==0) {
        _queue.audioOnly=NO;
        for(AVPlayerItemTrack *track in item.tracks)
          if([track.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) Check(track.enabled,@"Video restored when leaving audio-only mode");
        _queue.audioOnly=YES;
      }
      double duration=CMTimeGetSeconds(item.duration);
      Check(isfinite(duration) && duration>1,@"Valid fixture duration");
      _phase++;
      [_queue.player seekToTime:CMTimeMakeWithSeconds(duration-0.2,600)
               toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        if(finished && !_finished && item==_queue.player.currentItem) [_queue.player play];
      }];
    } else if(_phase==1 && _queue.currentIndex==1) _phase=2;
    else if(_phase==3 && _queue.currentIndex==2) _phase=4;
    else if(_phase==5 && _queue.player.rate==0 &&
            CMTimeGetSeconds(item.currentTime)>=CMTimeGetSeconds(item.duration)-0.05) {
      Check(_queue.currentIndex==2 && _queue.player.currentItem==item && !_queue.canSkipToNextItem,
            @"Final item pauses at end and stays selected for replay");
      [_queue removeAllItems];
      [self finish:nil]; return;
    }
    [self performSelector:@selector(poll) withObject:nil afterDelay:0.1];
  } @catch(NSException *exception) { [self finish:exception.reason]; }
}
- (void)finish:(NSString *)error {
  _finished=YES;
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [_queue.player pause];
  completion(error?[@"FAIL: queue: " stringByAppendingString:error]:
             @"PASS: playlist selection, UI binding, bounded loading, automatic advancement without a view, and audio-only tracks");
}
- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _view.delegate=nil;
  [_view release]; [_queue release]; [URL release]; [completion release];
  [super dealloc];
}
@end

void RDLPStartQueueTests(NSURL *URL, void (^completion)(NSString *)) {
  RDLPQueueTests *tests=[[RDLPQueueTests alloc] init];
  tests->URL=[URL retain]; tests->completion=[completion copy];
  [tests start]; [tests release];
}
