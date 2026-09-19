#import "RDLPLibraryViews.h"
#import "RDLPLibrary.h"

@implementation RDLPLibrarySplitView
- (CGFloat)dividerThickness; { return 1; }
- (void)drawDividerInRect:(NSRect)rect;
{ [[NSColor grayColor] set]; NSRectFill(rect); }
@end

/* Preserve spoken status text even though the visible cell contains only an icon. */

@implementation RDLPStatusCell
- (id)accessibilityAttributeValue:(NSString *)attribute;
{
  if([attribute isEqualToString:NSAccessibilityDescriptionAttribute] || [attribute isEqualToString:NSAccessibilityValueAttribute]) return [self representedObject];
  return [super accessibilityAttributeValue:attribute];
}
@end

/* AltivecCocoa may resize a pane through a zero-sized intermediate frame.
   Recompute from design rectangles so AppKit's clamped intermediate sizes do
   not permanently displace the toolbar or scroll view on Tiger. */

@implementation RDLPLayoutView
- (id)initWithFrame:(NSRect)frame;
{
  self=[super initWithFrame:frame];
  if(self) { designSize_=frame.size; designFrames_=[[NSMutableArray alloc] init]; }
  return self;
}
- (void)dealloc; { [designFrames_ release]; [super dealloc]; }
- (void)addSubview:(NSView *)view;
{
  [designFrames_ addObject:[NSValue valueWithRect:[view frame]]];
  [super addSubview:view];
}
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize;
{
  (void)oldSize;
  NSArray *children=[self subviews]; unsigned int i;
  CGFloat dx=[self bounds].size.width-designSize_.width;
  CGFloat dy=[self bounds].size.height-designSize_.height;
  for(i=0;i<[children count] && i<[designFrames_ count];++i) {
    NSView *view=[children objectAtIndex:i];
    NSRect frame=[[designFrames_ objectAtIndex:i] rectValue];
    NSUInteger mask=[view autoresizingMask];
    if(mask & NSViewWidthSizable) frame.size.width=MAX(0,frame.size.width+dx);
    if(mask & NSViewHeightSizable) frame.size.height=MAX(0,frame.size.height+dy);
    if(mask & NSViewMinXMargin) frame.origin.x+=dx;
    if(mask & NSViewMinYMargin) frame.origin.y+=dy;
    [view setFrame:frame];
  }
}
@end
/* A context menu acts on the row under the pointer, not an older selection. */

@implementation RDLPTableView
- (void)mouseDown:(NSEvent *)event;
{
  [[self delegate] performSelector:@selector(tableWasUsed:) withObject:self];
  [super mouseDown:event];
  [[self delegate] performSelector:@selector(tableWasUsed:) withObject:self];
}
- (BOOL)becomeFirstResponder;
{
  BOOL result=[super becomeFirstResponder];
  if(result) [[self delegate] performSelector:@selector(tableWasUsed:) withObject:self];
  return result;
}
- (NSMenu *)menuForEvent:(NSEvent *)event;
{
  [[self delegate] performSelector:@selector(tableWasUsed:) withObject:self];
  NSInteger row=[self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
  if(row>=0) [self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  else [self deselectAll:nil];
  return [super menuForEvent:event];
}
@end

@implementation RDLPOutlineView
- (void)mouseDown:(NSEvent *)event;
{
  [super mouseDown:event];
  [[self delegate] performSelector:@selector(tableWasUsed:) withObject:self];
}
- (BOOL)becomeFirstResponder;
{
  BOOL result=[super becomeFirstResponder];
  if(result) [[self delegate] performSelector:@selector(tableWasUsed:) withObject:self];
  return result;
}
@end

@implementation RDLPLibraryViews
+ (BOOL)isSidebarGroup:(id)item {
  return [item isEqual:@"System"] || [item isEqual:@"Added Playlists"] || [item isEqual:@"My Playlists"];
}
+ (NSString *)groupForPlaylist:(NSDictionary *)playlist {
  return [[playlist objectForKey:@"source"] isEqualToString:@"account"]?@"My Playlists":@"Added Playlists";
}
+ (NSOutlineView *)sidebarInView:(NSView *)view owner:(id)owner {
  NSScrollView *scroll=[[[NSScrollView alloc] initWithFrame:[view bounds]] autorelease];
  NSOutlineView *outline=[[[RDLPOutlineView alloc] initWithFrame:[scroll bounds]] autorelease];
  NSTableColumn *column=[[[NSTableColumn alloc] initWithIdentifier:@"title"] autorelease];
  [column setMinWidth:0]; [column setResizingMask:NSTableColumnAutoresizingMask];
  [column setEditable:NO]; [[column dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
  [outline addTableColumn:column];
  [outline setColumnAutoresizingStyle:NSTableViewFirstColumnOnlyAutoresizingStyle];
  [outline setOutlineTableColumn:column]; [[column headerCell] setStringValue:@"Playlists"];
  [outline setAllowsMultipleSelection:NO]; [outline setDataSource:owner]; [outline setDelegate:owner];
  [scroll setDocumentView:outline]; [scroll setHasVerticalScroller:YES]; [scroll setHasHorizontalScroller:NO];
  [scroll setAutohidesScrollers:YES];
  [outline sizeToFit];
  [scroll setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable]; [view addSubview:scroll]; return outline;
}
+ (NSButton *)buttonInView:(NSView *)view title:(NSString *)title action:(SEL)action target:(id)target frame:(NSRect)frame {
  NSButton *b=[[[NSButton alloc] initWithFrame:frame] autorelease];
  [b setTitle:title]; [b setTarget:target]; [b setAction:action]; [RDLPAppKit styleButton:b]; [view addSubview:b]; return b;
}
+ (NSTextField *)fieldInView:(NSView *)view frame:(NSRect)frame editable:(BOOL)editable {
  NSTextField *f=[[[NSTextField alloc] initWithFrame:frame] autorelease];
  [f setEditable:editable]; [f setSelectable:YES];
  if(!editable) { [f setBezeled:NO]; [f setDrawsBackground:NO]; }
  [view addSubview:f]; return f;
}
+ (NSTableView *)tableInView:(NSView *)view frame:(NSRect)frame owner:(id)owner names:(NSArray *)names labels:(NSArray *)labels {
  NSScrollView *scroll=[[[NSScrollView alloc] initWithFrame:frame] autorelease];
  NSTableView *t=[[[RDLPTableView alloc] initWithFrame:[scroll bounds]] autorelease]; unsigned int i;
  for(i=0;i<[names count];++i) {
    NSTableColumn *c=[[[NSTableColumn alloc] initWithIdentifier:[names objectAtIndex:i]] autorelease];
    [[c headerCell] setStringValue:[labels objectAtIndex:i]]; [c setWidth:i==0?240:130]; [c setEditable:NO]; [t addTableColumn:c];
  }
  [t setDataSource:owner]; [t setDelegate:owner]; [t setAllowsMultipleSelection:NO];
  [scroll setDocumentView:t]; [scroll setHasVerticalScroller:YES]; [scroll setHasHorizontalScroller:YES];
  [scroll setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable]; [view addSubview:scroll]; return t;
}
/* Toolbar glyphs use a 24-point image inside the standard 32-point slot. */
+ (NSImage *)toolbarIcon:(AIFontAwesomeIcon)icon window:(NSWindow *)window {
  return [RDLPAppKit controlIcon:icon style:AIFontAwesomeStyleSolid iconSize:24 canvasSize:32 scale:[RDLPAppKit backingScaleForWindow:window]];
}
+ (void)restoreSelection:(NSTableView *)view rows:(NSArray *)rows key:(NSString *)key value:(NSString *)value {
  [view deselectAll:nil];
  if([rows isKindOfClass:[RDLPLibraryRows class]]) {
    NSUInteger index=[(RDLPLibraryRows *)rows indexForIdentity:value];
    if(index!=NSNotFound) [view selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    return;
  }
  unsigned int i;
  for(i=0;value && i<[rows count];++i) if([[[rows objectAtIndex:i] objectForKey:key] isEqualToString:value]) {
    [view selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO]; break;
  }
}
@end
