#import "RDLPQueueOutlineView.h"
#import "RDLPAppKit.h"
#import "RDLPDownloadPolicy.h"
#import <AIFontAwesome.h>

@implementation RDLPQueueNode
- (id)init;
{ self=[super init]; if(self) children=[[NSMutableArray alloc] init]; return self; }
- (void)dealloc;
{ [key release]; [title release]; [parentKey release]; [playlistID release]; [videoID release]; [children release]; [job release]; [super dealloc]; }
@end

@implementation RDLPQueueTree
- (id)init;
{ self=[super init]; if(self) nodes_=[[NSMutableDictionary alloc] init]; return self; }
- (void)dealloc; { [nodes_ release]; [roots_ release]; [super dealloc]; }
- (NSArray *)roots; { return roots_; }
- (RDLPQueueNode *)nodeForKey:(NSString *)key; { return key?[nodes_ objectForKey:key]:nil; }
- (RDLPQueueNode *)node:(NSString *)key title:(NSString *)title kind:(NSInteger)kind;
{
  RDLPQueueNode *node=[nodes_ objectForKey:key];
  if(!node) { node=[[[RDLPQueueNode alloc] init] autorelease]; node->key=[key copy]; [nodes_ setObject:node forKey:key]; }
  [node->title release]; node->title=[title copy]; node->kind=kind; return node;
}
- (void)attach:(RDLPQueueNode *)node to:(RDLPQueueNode *)parent;
{
  if(![parent->children containsObject:node]) [parent->children addObject:node];
  [node->parentKey release]; node->parentKey=[parent->key copy];
}
- (void)rebuildJobs:(NSArray *)jobs library:(RDLPLibrary *)library;
{
  RDLPDownloadPolicy *policy=[[[RDLPDownloadPolicy alloc] initWithLibrary:library] autorelease];
  NSEnumerator *e=[nodes_ objectEnumerator]; RDLPQueueNode *node;
  while((node=[e nextObject])) [node->children removeAllObjects];
  NSArray *names=[NSArray arrayWithObjects:@"Done",@"Downloading",@"Queued",@"Needs Attention",nil];
  NSMutableArray *roots=[NSMutableArray array]; NSMutableSet *used=[NSMutableSet set]; NSUInteger i;
  for(i=0;i<[names count];++i) {
    node=[self node:[NSString stringWithFormat:@"status:%lu",(unsigned long)i] title:[names objectAtIndex:i] kind:RDLPQueueGroup];
    [roots addObject:node]; [used addObject:node->key];
  }
  e=[jobs objectEnumerator]; NSDictionary *job;
  while((job=[e nextObject])) {
    NSString *state=[job objectForKey:@"state"];
    BOOL complete=[policy playable:job];
    NSUInteger group=complete?0:([state isEqualToString:@"running"]?1:([state isEqualToString:@"queued"]?2:3));
    RDLPQueueNode *root=[roots objectAtIndex:group];
    NSString *pid=[job objectForKey:@"playlist_id"], *vid=[job objectForKey:@"video_id"];
    NSString *playlistKey=[NSString stringWithFormat:@"%@/playlist:%@",root->key,pid];
    RDLPQueueNode *playlist=[self node:playlistKey title:[job objectForKey:@"playlist_title"] kind:RDLPQueuePlaylist];
    [playlist->playlistID release]; playlist->playlistID=[pid copy]; [self attach:playlist to:root];
    RDLPQueueNode *video=[self node:[NSString stringWithFormat:@"%@/video:%@",playlistKey,vid] title:[job objectForKey:@"title"] kind:RDLPQueueVideo];
    [video->playlistID release]; video->playlistID=[pid copy]; [video->videoID release]; video->videoID=[vid copy]; [self attach:video to:playlist];
    NSString *format=[job objectForKey:@"format"];
    NSString *quality=[format isEqualToString:@"18"]?@"Low · 360p":([format isEqualToString:@"136+140"]?@"Medium · 720p":([format isEqualToString:@"137+140"]?@"High · 1080p":@"Exact format"));
    NSString *label=[NSString stringWithFormat:@"%@ (%@)",quality,format];
    NSString *actual=[job objectForKey:@"actual_format"];
    if([actual length] && ![actual isEqualToString:format]) label=[label stringByAppendingFormat:@" → %@",actual];
    if(group==3) label=[label stringByAppendingFormat:@" — %@",([state isEqualToString:@"removed"] || [state isEqualToString:@"complete"])?@"Missing file":([state isEqualToString:@"cancelled"]?@"Stopped":([state isEqualToString:@"interrupted"]?@"Interrupted":@"Failed"))];
    node=[self node:[@"job:" stringByAppendingString:[job objectForKey:@"id"]] title:label kind:RDLPQueueQuality];
    [node->playlistID release]; node->playlistID=[pid copy]; [node->videoID release]; node->videoID=[vid copy];
    [node->job release]; node->job=[job retain]; node->action=complete?RDLPQueueNoAction:(group==3?RDLPQueueRetry:RDLPQueueStop);
    [self attach:node to:video];
    [used addObject:playlist->key]; [used addObject:video->key]; [used addObject:node->key];
  }
  [roots_ release]; roots_=[roots copy];
  NSArray *keys=[[nodes_ allKeys] copy]; e=[keys objectEnumerator]; NSString *key;
  while((key=[e nextObject])) if(![used containsObject:key]) [nodes_ removeObjectForKey:key];
  [keys release];
}
@end

@implementation RDLPQueueOutlineView
- (void)dealloc; { [actionJobID_ release]; [super dealloc]; }
- (NSString *)actionJobID; { return actionJobID_; }
- (BOOL)isTrackingAction; { return actionJobID_!=nil; }
- (void)mouseDown:(NSEvent *)event;
{
  NSPoint point=[self convertPoint:[event locationInWindow] fromView:nil];
  NSInteger row=[self rowAtPoint:point], column=[self columnAtPoint:point];
  RDLPQueueNode *node=row>=0?[self itemAtRow:row]:nil;
  if(node && node->kind==RDLPQueueQuality && node->action!=RDLPQueueNoAction && column==1)
    actionJobID_=[[node->job objectForKey:@"id"] copy];
  [[self delegate] performSelector:@selector(tableWasUsed:) withObject:self];
  [super mouseDown:event];
  [actionJobID_ release]; actionJobID_=nil;
  [[self delegate] performSelector:@selector(refresh:) withObject:nil];
}
- (BOOL)becomeFirstResponder;
{ BOOL result=[super becomeFirstResponder]; if(result) [[self delegate] performSelector:@selector(tableWasUsed:) withObject:self]; return result; }
- (NSMenu *)menuForEvent:(NSEvent *)event;
{
  NSInteger row=[self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
  if(row>=0) [self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO]; else [self deselectAll:nil];
  [[self delegate] performSelector:@selector(tableWasUsed:) withObject:self];
  return [super menuForEvent:event];
}
@end

@interface RDLPQueueButtonCell : NSButtonCell
@end
@implementation RDLPQueueButtonCell
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view;
{
  /* Keep the glyph legible inside the compact bezel without enlarging rows. */
  [self drawImage:[self image] withFrame:NSMakeRect(NSMidX(frame)-5,NSMidY(frame)-5,10,10) inView:view];
}
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view;
{
  CGFloat diameter=MIN(18,MAX(0,NSHeight(frame)-2));
  NSRect circle=NSMakeRect(NSMidX(frame)-diameter/2,NSMidY(frame)-diameter/2,diameter,diameter);
  [NSGraphicsContext saveGraphicsState]; [[NSBezierPath bezierPathWithOvalInRect:circle] addClip];
  [super drawWithFrame:circle inView:view]; [NSGraphicsContext restoreGraphicsState];
#if MAC_OS_X_VERSION_MIN_REQUIRED >= 110000
  [[NSColor separatorColor] set];
#else
  [[NSColor controlShadowColor] set];
#endif
  [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circle,0.5,0.5)] stroke];
}
@end
@implementation RDLPQueueActionColumn
- (id)initWithTarget:(id)target;
{
  self=[super initWithIdentifier:@"action"]; if(!self) return nil;
  actionTarget_=target; button_=[[RDLPQueueButtonCell alloc] initTextCell:@""]; blank_=[[NSTextFieldCell alloc] initTextCell:@""];
  [blank_ setEditable:NO]; [blank_ setDrawsBackground:NO];
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200
  [button_ setBezelStyle:NSBezelStyleTexturedRounded]; [button_ setButtonType:NSButtonTypeMomentaryPushIn];
#else
  [button_ setBezelStyle:NSTexturedRoundedBezelStyle]; [button_ setButtonType:NSMomentaryPushInButton];
#endif
  [button_ setImagePosition:NSImageOnly]; [button_ setTarget:target]; [button_ setAction:@selector(queueCellAction:)];
  [self setDataCell:button_]; [self setEditable:YES]; [self setResizingMask:NSTableColumnNoResizing]; [self setWidth:26]; [self setMinWidth:26]; [self setMaxWidth:26];
  return self;
}
- (void)dealloc; { [button_ release]; [blank_ release]; [super dealloc]; }
- (id)dataCellForRow:(NSInteger)row;
{
  NSOutlineView *outline=(NSOutlineView *)[self tableView];
  RDLPQueueNode *node=row>=0?[outline itemAtRow:row]:nil;
  if(!node || node->kind!=RDLPQueueQuality || node->action==RDLPQueueNoAction) return blank_;
  [button_ setImage:[RDLPAppKit controlIcon:node->action==RDLPQueueStop?AIFAPause:AIFARotateRight style:AIFontAwesomeStyleSolid iconSize:10 canvasSize:10 scale:[RDLPAppKit backingScaleForWindow:[outline window]]]];
  [button_ setEnabled:YES]; [button_ setTarget:actionTarget_]; return button_;
}
@end
