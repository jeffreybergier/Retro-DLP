#import "RDLPPlayerQueue.h"

NSString *const RDLPPlayerQueueDidChangeNotification=@"RDLPPlayerQueueDidChangeNotification";
static void *RDLPQueueObservation=&RDLPQueueObservation;

/* Private bookkeeping for at most two loaded entries. Keep track objects we
 * disabled so switching back to video does not enable other, inactive tracks. */
@interface RDLPQueuedItem : NSObject {
@public
  AVPlayerItem *item;
  NSUInteger index;
  NSMutableArray *disabledTracks;
}
@end
@implementation RDLPQueuedItem
- (void)dealloc { [item release]; [disabledTracks release]; [super dealloc]; }
@end

@interface RDLPPlayerQueue () {
  NSMutableArray *_entries;
  BOOL _changing;
}
- (void)removeEntry:(RDLPQueuedItem *)entry;
- (void)appendItemAtIndex:(NSUInteger)index;
- (void)prepareIndex:(NSUInteger)index rate:(float)rate;
- (void)synchronize;
- (void)applyAudioMode;
- (void)publishChange;
@end

@implementation RDLPPlayerQueue
@synthesize player=_player, playlist=_playlist, currentIndex=_currentIndex, audioOnly=_audioOnly;

- (id)init {
  self=[super init]; if(!self) return nil;
  _playlist=[[NSArray alloc] init];
  _entries=[[NSMutableArray alloc] initWithCapacity:2];
  _currentIndex=NSNotFound;
  _player=[[AVQueuePlayer alloc] initWithItems:[NSArray array]];
  [_player addObserver:self forKeyPath:@"currentItem" options:0 context:RDLPQueueObservation];
  return self;
}
- (void)dealloc {
  [_player removeObserver:self forKeyPath:@"currentItem" context:RDLPQueueObservation];
  while([_entries count]) [self removeEntry:[_entries lastObject]];
  [_player pause]; [_player removeAllItems]; [_player release];
  [_entries release]; [_playlist release];
  [super dealloc];
}
- (BOOL)canSkipToPreviousItem { return _currentIndex!=NSNotFound && _currentIndex>0; }
- (BOOL)canSkipToNextItem { return _currentIndex!=NSNotFound && _currentIndex+1<[_playlist count]; }

- (BOOL)setPlaylist:(NSArray *)URLs startingAtIndex:(NSUInteger)index {
  if([URLs count] && index>=[URLs count]) return NO;
  for(id URL in URLs) if(![URL isKindOfClass:[NSURL class]]) return NO;
  NSArray *copy=URLs?[URLs copy]:[[NSArray alloc] init];
  [_playlist release]; _playlist=copy;
  [self prepareIndex:[URLs count]?index:NSNotFound rate:0];
  return YES;
}
- (BOOL)selectItemAtIndex:(NSUInteger)index {
  if(index>=[_playlist count]) return NO;
  [self prepareIndex:index rate:[_player rate]];
  return YES;
}
- (BOOL)skipToPreviousItem {
  return [self canSkipToPreviousItem] && [self selectItemAtIndex:_currentIndex-1];
}
- (BOOL)skipToNextItem {
  if(![self canSkipToNextItem]) return NO;
  /* Reuse the already prepared next item. Keep notifications atomic for
   * clients, including when AVFoundation sends synchronous KVO callbacks. */
  float rate=[_player rate];
  _changing=YES;
  [_player advanceToNextItem];
  [_player setRate:rate];
  _changing=NO;
  [self synchronize];
  return YES;
}
- (void)removeAllItems { [self setPlaylist:nil startingAtIndex:0]; }
- (void)setAudioOnly:(BOOL)audioOnly {
  if(_audioOnly==audioOnly) return;
  _audioOnly=audioOnly;
  [self applyAudioMode];
  [self publishChange];
}

- (void)prepareIndex:(NSUInteger)index rate:(float)rate {
  _changing=YES;
  [_player pause];
  [_player removeAllItems];
  while([_entries count]) [self removeEntry:[_entries lastObject]];
  _currentIndex=index;
  if(index!=NSNotFound) {
    [self appendItemAtIndex:index];
    if(index+1<[_playlist count]) [self appendItemAtIndex:index+1];
  }
  [_player setActionAtItemEnd:[self canSkipToNextItem]?AVPlayerActionAtItemEndAdvance:AVPlayerActionAtItemEndPause];
  [self applyAudioMode];
  if(index!=NSNotFound) [_player setRate:rate];
  _changing=NO;
  [self publishChange];
}
- (void)appendItemAtIndex:(NSUInteger)index {
  RDLPQueuedItem *entry=[[RDLPQueuedItem alloc] init];
  entry->index=index;
  entry->item=[[AVPlayerItem alloc] initWithURL:[_playlist objectAtIndex:index]];
  entry->disabledTracks=[[NSMutableArray alloc] init];
  [_entries addObject:entry];
  [entry->item addObserver:self forKeyPath:@"status" options:0 context:RDLPQueueObservation];
  [entry->item addObserver:self forKeyPath:@"tracks" options:0 context:RDLPQueueObservation];
  [_player insertItem:entry->item afterItem:nil];
  [entry release];
}
- (void)removeEntry:(RDLPQueuedItem *)entry {
  [entry->item removeObserver:self forKeyPath:@"status" context:RDLPQueueObservation];
  [entry->item removeObserver:self forKeyPath:@"tracks" context:RDLPQueueObservation];
  [_entries removeObjectIdenticalTo:entry];
}
- (void)synchronize {
  if(_changing) return;
  AVPlayerItem *current=[_player currentItem];
  NSUInteger selected=NSNotFound;
  for(RDLPQueuedItem *entry in _entries) if(entry->item==current) { selected=entry->index; break; }
  BOOL changed=selected!=_currentIndex;
  _changing=YES;
  _currentIndex=selected;
  while([_entries count] && ((RDLPQueuedItem *)[_entries objectAtIndex:0])->item!=current)
    [self removeEntry:[_entries objectAtIndex:0]];
  if(selected!=NSNotFound && [_entries count]<2 && [self canSkipToNextItem])
    [self appendItemAtIndex:selected+1];
  [_player setActionAtItemEnd:[self canSkipToNextItem]?AVPlayerActionAtItemEndAdvance:AVPlayerActionAtItemEndPause];
  [self applyAudioMode];
  _changing=NO;
  if(changed) [self publishChange];
}
- (void)applyAudioMode {
  for(RDLPQueuedItem *entry in _entries) {
    if(_audioOnly) {
      for(AVPlayerItemTrack *track in [entry->item tracks]) {
        if([[[track assetTrack] mediaType] isEqualToString:AVMediaTypeVideo] && [track isEnabled]) {
          if(![entry->disabledTracks containsObject:track]) [entry->disabledTracks addObject:track];
          [track setEnabled:NO];
        }
      }
    } else {
      for(AVPlayerItemTrack *track in entry->disabledTracks) [track setEnabled:YES];
      [entry->disabledTracks removeAllObjects];
    }
  }
}
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  if(context!=RDLPQueueObservation) { [super observeValueForKeyPath:key ofObject:object change:change context:context]; return; }
  if([NSThread isMainThread]) [self synchronize];
  else [self performSelectorOnMainThread:@selector(synchronize) withObject:nil waitUntilDone:NO];
}
- (void)publishChange {
  [[NSNotificationCenter defaultCenter] postNotificationName:RDLPPlayerQueueDidChangeNotification object:self];
}
@end
