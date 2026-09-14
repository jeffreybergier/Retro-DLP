#import "LibraryWindow.h"
#import "XPAppKit.h"
#import "RDToolbarButton.h"
#import <AIFontAwesome.h>
#import <CoreFoundation/CoreFoundation.h>
/* Declarations for runtime-guarded APIs absent from the Tiger SDK. */
@interface NSWindow (RDStatusBarCompatibility)
- (void)setAutorecalculatesContentBorderThickness:(BOOL)flag forEdge:(NSRectEdge)edge;
- (void)setContentBorderThickness:(CGFloat)thickness forEdge:(NSRectEdge)edge;
- (void)setCollectionBehavior:(NSUInteger)behavior;
@end

/* Preserve spoken status text even though the visible cell contains only an icon. */
@interface RDStatusCell : NSImageCell
@end
@implementation RDStatusCell
- (id)accessibilityAttributeValue:(NSString *)attribute;
{
  if([attribute isEqualToString:NSAccessibilityDescriptionAttribute] || [attribute isEqualToString:NSAccessibilityValueAttribute]) return [self representedObject];
  return [super accessibilityAttributeValue:attribute];
}
@end

static const CGFloat RDStatusBarHeight=32.0;

/* AltivecCocoa may resize a pane through a zero-sized intermediate frame.
   Recompute from design rectangles so AppKit's clamped intermediate sizes do
   not permanently displace the toolbar or scroll view on Tiger. */
@interface RDLayoutView : NSView {
  NSMutableArray *designFrames_;
  NSSize designSize_;
}
@end
@implementation RDLayoutView
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
@interface RDTableView : NSTableView
@end
@implementation RDTableView
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
@interface RDOutlineView : NSOutlineView
@end
@implementation RDOutlineView
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
static BOOL sidebarGroup(id item) {
  return [item isEqual:@"System"] || [item isEqual:@"Added Playlists"] || [item isEqual:@"My Playlists"];
}
static NSString *playlistGroup(NSDictionary *playlist) {
  return [[playlist objectForKey:@"source"] isEqualToString:@"account"]?@"My Playlists":@"Added Playlists";
}
static NSOutlineView *sidebarOutline(NSView *view,id owner) {
  NSScrollView *scroll=[[[NSScrollView alloc] initWithFrame:[view bounds]] autorelease];
  NSOutlineView *outline=[[[RDOutlineView alloc] initWithFrame:[scroll bounds]] autorelease];
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
static NSButton *button(NSView *view,NSString *title,SEL action,id target,NSRect frame) {
  NSButton *b=[[[NSButton alloc] initWithFrame:frame] autorelease];
  [b setTitle:title]; [b setTarget:target]; [b setAction:action]; RDStyleButton(b); [view addSubview:b]; return b;
}
static NSTextField *field(NSView *view,NSRect frame,BOOL editable) {
  NSTextField *f=[[[NSTextField alloc] initWithFrame:frame] autorelease];
  [f setEditable:editable]; [f setSelectable:YES];
  if(!editable) { [f setBezeled:NO]; [f setDrawsBackground:NO]; }
  [view addSubview:f]; return f;
}
static NSTableView *table(NSView *view,NSRect frame,id owner,NSArray *names,NSArray *labels) {
  NSScrollView *scroll=[[[NSScrollView alloc] initWithFrame:frame] autorelease];
  NSTableView *t=[[[RDTableView alloc] initWithFrame:[scroll bounds]] autorelease]; unsigned int i;
  for(i=0;i<[names count];++i) {
    NSTableColumn *c=[[[NSTableColumn alloc] initWithIdentifier:[names objectAtIndex:i]] autorelease];
    [[c headerCell] setStringValue:[labels objectAtIndex:i]]; [c setWidth:i==0?240:130]; [c setEditable:NO]; [t addTableColumn:c];
  }
  [t setDataSource:owner]; [t setDelegate:owner]; [t setAllowsMultipleSelection:NO];
  [scroll setDocumentView:t]; [scroll setHasVerticalScroller:YES]; [scroll setHasHorizontalScroller:YES];
  [scroll setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable]; [view addSubview:scroll]; return t;
}
/* Toolbar glyphs use a 24-point image inside the standard 32-point slot. */
static NSImage *toolbarIcon(AIFontAwesomeIcon icon,NSWindow *window) {
  return RDControlIcon(icon,AIFontAwesomeStyleSolid,24,32,RDWindowBackingScale(window));
}
static BOOL stateIs(NSDictionary *job,NSString *state) { return [[job objectForKey:@"state"] isEqualToString:state]; }
static void restoreSelection(NSTableView *view,NSArray *rows,NSString *key,NSString *value) {
  unsigned int i; [view deselectAll:nil];
  for(i=0;value && i<[rows count];++i) if([[[rows objectAtIndex:i] objectForKey:key] isEqualToString:value]) {
    [view selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO]; break;
  }
}
static void menuItem(NSMenu *menu,NSString *title,SEL action,id target) {
  [[menu addItemWithTitle:title action:action keyEquivalent:@""] setTarget:target];
}
@interface LibraryWindow (Private)
- (id)initWithLibrary:(RetroDLPLibrary *)library;
- (void)windowDidLoad;
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)insert;
- (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier;
- (void)playVideoInVLC:(id)sender;
- (void)playPlaylistInVLC:(id)sender;
- (void)menuNeedsUpdate:(NSMenu *)menu;
- (NSDictionary *)contextPlaylist;
- (NSString *)selectionPlayFile;
- (void)playSelection:(id)sender;
- (void)playSelectionInVLC:(id)sender;
- (void)revealSelection:(id)sender;
- (void)toolbarDefault:(id)sender;
- (void)chooseDownload:(NSMenuItem *)sender;
- (void)saveDownloadQuality:(NSString *)format;
- (void)updateCustomSummary;
- (void)controlTextDidChange:(NSNotification *)notification;
- (void)dismissDownload:(id)sender;
- (void)downloadSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code contextInfo:(void *)context;
- (void)dealloc;
- (NSDictionary *)selectedRow;
- (RDQueueNode *)selectedQueueNode;
- (void)expandQueuePath:(RDQueueNode *)node;
- (void)restoreQueueExpansion:(NSArray *)nodes;
- (void)queueCellAction:(id)sender;
- (void)showQueueError:(id)sender;
- (NSDictionary *)selectedJob;
- (NSDictionary *)selectedPlaylist;
- (NSDictionary *)jobForEntry:(NSDictionary *)entry;
- (NSString *)statusForJob:(NSDictionary *)job;
- (BOOL)playable:(NSDictionary *)job;
- (void)refresh:(id)sender;
- (void)tableWasUsed:(NSTableView *)view;
- (BOOL)hasTargetVideo;
- (NSDictionary *)targetJob;
- (NSDictionary *)targetPlaylist;
- (NSString *)targetVideoID;
- (NSString *)targetFormat;
- (NSDictionary *)jobForPlaylist:(NSString *)playlist video:(NSString *)video format:(NSString *)format;
- (BOOL)canRetry:(NSDictionary *)job;
- (BOOL)canDownloadAgain:(NSDictionary *)job;
- (BOOL)canRemove:(NSDictionary *)job;
- (BOOL)canCancel:(NSDictionary *)job;
- (NSDictionary *)currentJob:(NSString *)key;
- (NSString *)playFileForPlaylist:(NSDictionary *)playlist;
- (NSString *)targetPlaylistFolder;
- (NSArray *)missingPlanForPlaylist:(NSString *)playlist format:(NSString *)format;
- (NSArray *)syncPlan;
- (NSUInteger)queuedCount;
- (void)setToolbarItem:(NSString *)key title:(NSString *)title tip:(NSString *)tip icon:(NSImage *)icon enabled:(BOOL)enabled;
- (void)updateToolbar;
- (void)updateControls;
- (NSInteger)numberOfRowsInTableView:(NSTableView *)view;
- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
- (BOOL)validateToolbarItem:(NSToolbarItem *)item;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)addPlaylist:(id)sender;
- (void)dismissAdd:(id)sender;
- (void)addSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code contextInfo:(void *)context;
- (void)confirmRequest:(NSDictionary *)request title:(NSString *)title detail:(NSString *)detail action:(NSString *)action;
- (void)confirmationDidEnd:(NSAlert *)alert returnCode:(NSInteger)code contextInfo:(void *)context;
- (void)performConfirmed:(NSDictionary *)request;
- (void)confirmJob:(NSDictionary *)job remove:(BOOL)remove;
- (BOOL)canRemovePlaylist:(NSDictionary *)playlist;
- (void)retryAndRevealJob:(NSDictionary *)job;
- (void)enqueueSingle:(NSDictionary *)request allowRetry:(BOOL)allowRetry;
- (void)enqueueRequest:(NSDictionary *)request;
- (void)requestBulk:(NSDictionary *)request;
- (void)downloadDefault:(id)sender;
- (void)sync:(id)sender;
- (void)syncAll:(id)sender;
- (void)discover:(id)sender;
- (void)openCookieExportGuide:(id)sender;
- (void)importCookies:(id)sender;
- (void)replaceCookies:(id)sender;
- (void)clearCookies:(id)sender;
- (void)toggleDownloads:(id)sender;
- (void)togglePlaylists:(id)sender;
- (void)showQueue:(id)sender;
- (void)hideQueue:(id)sender;
- (void)revealDownloads;
- (void)showJobInQueue:(NSDictionary *)job;
- (void)showTargetInQueue:(id)sender;
- (void)retryTarget:(id)sender;
- (void)againTarget:(id)sender;
- (void)cancelTarget:(id)sender;
- (void)removeTarget:(id)sender;
- (void)retryQueueJob:(id)sender;
- (void)againQueueJob:(id)sender;
- (void)cancelQueueJob:(id)sender;
- (void)jobAction:(id)sender;
- (void)removeDownload:(id)sender;
- (void)removeJob:(id)sender;
- (void)removePlaylist:(id)sender;
- (void)playTargetVideo:(id)sender;
- (void)playTargetPlaylist:(id)sender;
- (void)revealTarget:(id)sender;
- (void)revealPlaylistFolder:(id)sender;
- (void)openDownloadsFolder:(id)sender;
- (void)openVideo:(id)sender;
- (void)openJob:(id)sender;
- (void)playPlaylist:(id)sender;
@end
@implementation LibraryWindow
- (id)initWithLibrary:(RetroDLPLibrary *)library;
{
  self=[super initWithTitle:@"RetroDLP" autosaveName:@"RetroDLPLibraryWindow"]; if(!self) return nil;
  library_=[library retain]; mode_=1;
  AIViewController *left=[[[AIViewController alloc] init] autorelease];
  NSView *sidebar=[[[RDLayoutView alloc] initWithFrame:NSMakeRect(0,0,200,600)] autorelease];
  sidebarItems_=[[NSMutableDictionary alloc] init];
  sidebar_=sidebarOutline(sidebar,self);
  [left setView:sidebar]; [self setSidebarViewController:left];
  AIViewController *middle=[[[AIViewController alloc] init] autorelease];
  NSView *detail=[[[RDLayoutView alloc] initWithFrame:NSMakeRect(0,0,540,600)] autorelease];
  table_=table(detail,[detail bounds],self,[NSArray arrayWithObjects:@"state",@"title",@"quality",nil],[NSArray arrayWithObjects:@"",@"Video",@"Quality",nil]);
  NSTableColumn *stateColumn=[table_ tableColumnWithIdentifier:@"state"];
  [stateColumn setMinWidth:24]; [stateColumn setMaxWidth:24]; [stateColumn setWidth:24];
  [stateColumn setResizingMask:NSTableColumnNoResizing];
  [stateColumn setDataCell:[[[RDStatusCell alloc] initImageCell:nil] autorelease]];
  NSTableColumn *titleColumn=[table_ tableColumnWithIdentifier:@"title"];
  [titleColumn setMinWidth:0]; [titleColumn setResizingMask:NSTableColumnAutoresizingMask];
  [[titleColumn dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
  qualityColumn_=[[table_ tableColumnWithIdentifier:@"quality"] retain];
  [qualityColumn_ setMinWidth:100]; [qualityColumn_ setMaxWidth:100]; [qualityColumn_ setWidth:100];
  [qualityColumn_ setResizingMask:NSTableColumnNoResizing];
  [table_ setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
  [table_ setAllowsColumnReordering:NO];
  [[table_ enclosingScrollView] setHasHorizontalScroller:NO];
  [[table_ enclosingScrollView] setAutohidesScrollers:YES];
  [table_ sizeToFit];
  [[table_ enclosingScrollView] setBorderType:NSNoBorder];
  [table_ setTarget:self]; [table_ setDoubleAction:@selector(openVideo:)];
  downloadFormat_=[[RetroDLPLibrary preferredFormat] copy];
  [middle setView:detail]; [self setDetailViewController:middle];
  AIViewController *inspector=[[[AIViewController alloc] init] autorelease];
  NSView *queue=[[[RDLayoutView alloc] initWithFrame:NSMakeRect(0,0,300,600)] autorelease];
  queueTree_=[[RDQueueTree alloc] init]; queueCollapsed_=[[NSMutableSet alloc] init];
  NSScrollView *queueScroll=[[[NSScrollView alloc] initWithFrame:[queue bounds]] autorelease];
  queue_=[[[RDQueueOutlineView alloc] initWithFrame:[queueScroll bounds]] autorelease];
  NSTableColumn *summary=[[[NSTableColumn alloc] initWithIdentifier:@"summary"] autorelease];
  [summary setWidth:270]; [summary setMinWidth:100]; [summary setEditable:NO];
  [[summary dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
  [queue_ addTableColumn:summary]; [queue_ addTableColumn:[[[RDQueueActionColumn alloc] initWithTarget:self] autorelease]];
  [queue_ setOutlineTableColumn:summary]; [[summary headerCell] setStringValue:@"Queue"];
  [[[[queue_ tableColumns] objectAtIndex:1] headerCell] setStringValue:@""];
  [queue_ setAllowsMultipleSelection:NO];
  [queue_ setColumnAutoresizingStyle:NSTableViewFirstColumnOnlyAutoresizingStyle];
  [queue_ setDataSource:(id)self]; [queue_ setDelegate:(id)self];
  [queueScroll setDocumentView:queue_]; [queueScroll setBorderType:NSNoBorder];
  [queueScroll setHasVerticalScroller:YES]; [queueScroll setHasHorizontalScroller:NO];
  [queueScroll setAutohidesScrollers:YES];
  [queueScroll setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable]; [queue addSubview:queueScroll];
  NSMenu *jobMenu=[[[NSMenu alloc] initWithTitle:@"Queue Actions"] autorelease];
  menuItem(jobMenu,@"Play",@selector(openJob:),self);
  menuItem(jobMenu,@"Retry",@selector(retryQueueJob:),self);
  menuItem(jobMenu,@"Stop Download…",@selector(cancelQueueJob:),self);
  menuItem(jobMenu,@"Show Error…",@selector(showQueueError:),self);
  menuItem(jobMenu,@"Delete Download…",@selector(removeJob:),self);
  [queue_ setMenu:jobMenu]; [queue_ setTarget:self]; [queue_ setDoubleAction:@selector(openJob:)];
  [inspector setView:queue]; [self setInspectorViewController:inspector];
  [self setSidebarWidthLimits:AIMinMidMaxMake(150,200,260)];
  [self setInspectorWidthLimits:AIMinMidMaxMake(300,320,400)];
  [self setSplitViewAutosaveName:@"RetroDLPThreePaneDividers"];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RetroDLPLibraryDidChange object:library_];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
  [self refresh:nil]; return self;
}
- (void)showWindow:(id)sender;
{
  [super showWindow:sender];
  /* Derive content limits from the displayed frame, including Tiger's toolbar. */
  NSWindow *window=[self window];
  NSSize frameSize=[window frame].size,contentSize=[[window contentView] frame].size;
  [window setContentMinSize:NSMakeSize(640-(frameSize.width-contentSize.width),
                                      480-(frameSize.height-contentSize.height))];
  if(!didRestoreWindowFrame_) {
    /* Tiger saves heights without the toolbar. Restore only after it exists,
       then enable autosaving so setup cannot overwrite the saved dimensions. */
    [window setFrameUsingName:@"AICCWindow-RetroDLPLibraryWindow"];
    [self setWindowFrameAutosaveName:@"AICCWindow-RetroDLPLibraryWindow"];
    didRestoreWindowFrame_=YES;
  }
}
- (void)loadWindow;
{
  /* Tiger cannot change a window's style mask after creation. */
  AIWindowStyleMask mask=AIWindowStyleMaskTitled|AIWindowStyleMaskClosable|
    AIWindowStyleMaskMiniaturizable|AIWindowStyleMaskResizable;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200
  /* Intentional legacy appearance; newer AppKit renders its own fallback. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  mask|=NSWindowStyleMaskTexturedBackground;
#pragma clang diagnostic pop
#else
  mask|=NSTexturedBackgroundWindowMask;
#endif
  if(AICCCurrentTier()>=AICCTierMiddle) mask|=AIWindowStyleMaskFullSizeContentView;
  NSWindow *window=[[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,800,600)
    styleMask:mask backing:NSBackingStoreBuffered defer:NO] autorelease];
  [window setTitle:@"RetroDLP"]; [window setReleasedWhenClosed:NO];
  if(AICCCurrentTier()>=AICCTierMiddle)
    [window setCollectionBehavior:AIWindowCollectionBehaviorFullScreenPrimary];
  [window setMinSize:NSMakeSize(640,480)];
  NSRect frame=[window frame]; frame.size=NSMakeSize(800,600);
  [window setFrame:frame display:NO]; [window center];
  [self setWindow:window]; [self setShouldCascadeWindows:NO];
}
- (void)windowDidLoad;
{
  [super windowDidLoad];
  NSWindow *window=[self window];
  NSRect frame=[window frame];
  NSSplitView *split=[self AI_splitView];
  NSRect bounds=[[window contentView] bounds];
  NSView *root=[[[RDLayoutView alloc] initWithFrame:bounds] autorelease];
  [root setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  /* Preserve the modern split controller's containment and responder chain. */
  if(AICCCurrentTier()>=AICCTierMiddle) {
    id splitController=[[window performSelector:@selector(contentViewController)] retain];
    id container=[[NSClassFromString(@"NSViewController") alloc] init];
    [window performSelector:@selector(setContentViewController:) withObject:nil];
    [container performSelector:@selector(setView:) withObject:root];
    [container performSelector:@selector(addChildViewController:) withObject:splitController];
    [window performSelector:@selector(setContentViewController:) withObject:container];
    [splitController release]; [container release];
  } else {
    [window setContentView:root];
  }
  [split removeFromSuperview];
  [split setFrame:NSMakeRect(0,RDStatusBarHeight,bounds.size.width,
                            MAX(0,bounds.size.height-RDStatusBarHeight))];
  [split setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  [root addSubview:split];
  status_=field(root,NSMakeRect(12,7,MAX(0,bounds.size.width-190),18),NO);
  [status_ setAutoresizingMask:NSViewWidthSizable];
  queueProgress_=[[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(bounds.size.width-160,10,140,12)] autorelease];
  [queueProgress_ setIndeterminate:NO]; [queueProgress_ setMinValue:0]; [queueProgress_ setHidden:YES];
  [queueProgress_ setAutoresizingMask:NSViewMinXMargin]; [root addSubview:queueProgress_];
  [[status_ cell] setLineBreakMode:NSLineBreakByTruncatingTail];
  if([window respondsToSelector:@selector(setContentBorderThickness:forEdge:)]) {
    [window setAutorecalculatesContentBorderThickness:NO forEdge:NSMinYEdge];
    [window setContentBorderThickness:RDStatusBarHeight forEdge:NSMinYEdge];
  }
  [window setFrame:frame display:NO];
  NSToolbar *toolbar=[[[NSToolbar alloc] initWithIdentifier:@"RetroDLPLibraryToolbar"] autorelease];
  [toolbar setDelegate:(id)self]; [toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
  [toolbar setSizeMode:NSToolbarSizeModeRegular];
  [[self window] setToolbar:toolbar]; RDUseExpandedToolbar([self window]);
  /* Toolbar installation changes frame constraints on Tiger. Keep outer sizes. */
  [window setMinSize:NSMakeSize(640,480)];
  [window setFrame:frame display:NO];
}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
{ (void)toolbar; return [NSArray arrayWithObjects:@"download",@"play",NSToolbarFlexibleSpaceItemIdentifier,@"cookies",@"downloads",nil]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
{ (void)toolbar; return [NSArray arrayWithObjects:@"download",@"play",@"cookies",@"downloads",NSToolbarFlexibleSpaceItemIdentifier,nil]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)insert;
{
  (void)toolbar;
  NSArray *ids=[NSArray arrayWithObjects:@"download",@"play",@"cookies",@"downloads",nil];
  NSUInteger index=[ids indexOfObject:identifier]; if(index==NSNotFound) return nil;
  NSArray *labels=[NSArray arrayWithObjects:@"Download",@"Play",@"Cookies",@"Queue",nil];
  AIFontAwesomeIcon icons[]={AIFADownload,AIFAPlay,AIFACookieBite,AIFAListUl};
  NSToolbarItem *item=[[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
  RDToolbarButton *view=[[[RDToolbarButton alloc] initWithFrame:NSMakeRect(0,0,40,32)] autorelease];
  [view setTitle:[labels objectAtIndex:index]]; [view setTag:(NSInteger)index];
  [view setImage:toolbarIcon(icons[index],[self window])];
  [view setCaretImage:RDControlIcon(AIFACaretDown,AIFontAwesomeStyleSolid,8,10,RDWindowBackingScale([self window]))];
  [view setTarget:self]; [view setAction:@selector(toolbarDefault:)];
  [view setMenu:[self menuForToolbarIdentifier:identifier]];
  [item setLabel:[labels objectAtIndex:index]]; [item setPaletteLabel:[labels objectAtIndex:index]];
  [item setView:view]; [item setMinSize:NSMakeSize(40,32)]; [item setMaxSize:NSMakeSize(40,32)];
  [item setTarget:self]; [item setAction:@selector(toolbarDefault:)]; [item setTag:(NSInteger)index];
  [item setAutovalidates:NO];
  if(insert) {
    if(!toolbarItems_) toolbarItems_=[[NSMutableDictionary alloc] init];
    [toolbarItems_ setObject:item forKey:identifier];
  }
  return item;
}
/* Menu-bar commands keep stable positions; toolbar menus remain task-oriented. */
- (NSMenu *)menuForMenuBarTitle:(NSString *)title;
{
  NSMenu *menu=[[[NSMenu alloc] initWithTitle:title] autorelease];
  if([title isEqualToString:@"File"]) {
    menuItem(menu,@"Add Playlist…",@selector(addPlaylist:),self);
    menuItem(menu,@"Load My Playlists…",@selector(discover:),self);
    [menu addItem:[NSMenuItem separatorItem]];
    menuItem(menu,@"Sync Current Playlist",@selector(sync:),self);
    menuItem(menu,@"Sync All Playlists…",@selector(syncAll:),self);
    [menu addItem:[NSMenuItem separatorItem]];
    menuItem(menu,@"Download Video",@selector(downloadFromMenu:),self);
    menuItem(menu,@"Cancel Download…",@selector(cancelTarget:),self);
    [menu addItem:[NSMenuItem separatorItem]];
    menuItem(menu,@"Play Playlist in Default App",@selector(playSelection:),self);
    menuItem(menu,@"Play Playlist in VLC",@selector(playSelectionInVLC:),self);
    NSMenu *playlist=[[[NSMenu alloc] initWithTitle:@"Play Entire Playlist"] autorelease];
    menuItem(playlist,@"In Default App",@selector(playTargetPlaylist:),self);
    menuItem(playlist,@"In VLC",@selector(playPlaylistInVLC:),self);
    [[menu addItemWithTitle:@"Play Entire Playlist" action:NULL keyEquivalent:@""] setSubmenu:playlist];
    menuItem(menu,@"Show in Finder",@selector(revealSelection:),self);
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
  } else if([title isEqualToString:@"Edit"]) {
    [menu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [menu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [menu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [menu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [menu addItem:[NSMenuItem separatorItem]];
    menuItem(menu,@"Remove Playlist…",@selector(removePlaylist:),self);
    menuItem(menu,@"Delete Download…",@selector(removeTarget:),self);
  } else if([title isEqualToString:@"View"]) {
    menuItem(menu,@"Hide Playlists",@selector(togglePlaylists:),self);
    menuItem(menu,@"Show Download Queue",@selector(toggleDownloads:),self);
    [menu addItem:[NSMenuItem separatorItem]];
    menuItem(menu,@"Show in Queue",@selector(showTargetInQueue:),self);
  } else if([title isEqualToString:@"Download Quality"]) {
    NSArray *names=[NSArray arrayWithObjects:@"Low",@"Medium",@"High",@"Custom Format…",nil];
    unsigned int index;
    for(index=0;index<[names count];++index) {
      NSMenuItem *choice=[menu addItemWithTitle:[names objectAtIndex:index] action:@selector(chooseDownload:) keyEquivalent:@""];
      [choice setTarget:self]; [choice setTag:index+1];
    }
  } else if([title isEqualToString:@"Cookies"]) {
    menuItem(menu,@"Import Cookies…",@selector(importCookies:),self);
    menuItem(menu,@"Replace Cookies…",@selector(replaceCookies:),self);
    menuItem(menu,@"Remove Cookies…",@selector(clearCookies:),self);
  } else if([title isEqualToString:@"Help"]) {
    menuItem(menu,@"Cookie Export Guide",@selector(openCookieExportGuide:),self);
  }
  return menu;
}
- (void)downloadFromMenu:(NSMenuItem *)sender;
{
  if(![self validateMenuItem:sender]) return;
  if(context_==2 && [self selectedJob]) { [self retryQueueJob:sender]; return; }
  NSMenuItem *command=[[[NSMenuItem alloc] initWithTitle:@"" action:@selector(chooseDownload:) keyEquivalent:@""] autorelease];
  [command setTag:[self hasTargetVideo]?0:5]; [self chooseDownload:command];
}
- (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier;
{
  NSMenu *menu=[[[NSMenu alloc] initWithTitle:identifier] autorelease];
  if([identifier isEqualToString:@"download"] || [identifier isEqualToString:@"play"]) {
    [menu setDelegate:(id)self]; [self menuNeedsUpdate:menu];
  } else if([identifier isEqualToString:@"view"]) {
    menuItem(menu,@"Hide Playlists",@selector(togglePlaylists:),self);
    menuItem(menu,@"Show Download Queue",@selector(toggleDownloads:),self);
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenu *queue=[self menuForToolbarIdentifier:@"downloads"];
    /* Visibility lives directly in View; retain the queue operation menu. */
    [queue removeItemAtIndex:0]; [queue removeItemAtIndex:0]; [queue removeItemAtIndex:0];
    [queue setTitle:@"Download Queue"];
    NSMenuItem *parent=[menu addItemWithTitle:@"Download Queue" action:NULL keyEquivalent:@""];
    [parent setSubmenu:queue];
  } else if([identifier isEqualToString:@"cookies"]) {
    menuItem(menu,@"Import Cookies…",@selector(importCookies:),self);
    menuItem(menu,@"Replace Cookies…",@selector(replaceCookies:),self);
    menuItem(menu,@"Remove Cookies…",@selector(clearCookies:),self);
    [menu addItem:[NSMenuItem separatorItem]];
    menuItem(menu,@"Export Guide",@selector(openCookieExportGuide:),self);
  } else {
    menuItem(menu,@"Show Queue",@selector(showQueue:),self);
    menuItem(menu,@"Hide Queue",@selector(hideQueue:),self);
    [menu addItem:[NSMenuItem separatorItem]];
    menuItem(menu,@"Download Selected Queue Video",@selector(retryQueueJob:),self);
    menuItem(menu,@"Cancel Selected Queue Job…",@selector(cancelQueueJob:),self);
    menuItem(menu,@"Delete Selected Queue Download…",@selector(removeJob:),self);
  }
  return menu;
}
- (void)menuNeedsUpdate:(NSMenu *)menu;
{
  BOOL download=[[menu title] caseInsensitiveCompare:@"Download"]==NSOrderedSame;
  if(!download && [[menu title] caseInsensitiveCompare:@"Play"]!=NSOrderedSame) return;
  while([menu numberOfItems]) [menu removeItemAtIndex:0];
  BOOL video=[self hasTargetVideo];
  if(download) {
    NSString *title=video?@"Download Video":@"Download Missing Videos";
    NSMenuItem *command=[menu addItemWithTitle:title action:@selector(chooseDownload:) keyEquivalent:@""];
    [command setTarget:self]; [command setTag:video?0:5];
    NSMenuItem *parent=[menu addItemWithTitle:@"Download Quality" action:NULL keyEquivalent:@""];
    NSMenu *qualities=[[[NSMenu alloc] initWithTitle:@"Download Quality"] autorelease];
    NSArray *titles=[NSArray arrayWithObjects:@"Last Used Quality",@"Low",@"Medium",@"High",@"Custom Format…",nil];
    unsigned int index;
    for(index=1;index<5;++index) {
      NSMenuItem *choice=[qualities addItemWithTitle:[titles objectAtIndex:index] action:@selector(chooseDownload:) keyEquivalent:@""];
      [choice setTarget:self]; [choice setTag:(NSInteger)((video?0:5)+index)];
    }
    [parent setSubmenu:qualities];
    if(video) {
      menuItem(menu,@"Cancel Download…",@selector(cancelTarget:),self);
      menuItem(menu,@"Delete Download…",@selector(removeTarget:),self);
      menuItem(menu,@"Show in Queue",@selector(showTargetInQueue:),self);
    } else if([self contextPlaylist]) {
      menuItem(menu,@"Sync Current Playlist",@selector(sync:),self);
      menuItem(menu,@"Remove Playlist…",@selector(removePlaylist:),self);
      menuItem(menu,@"Show Download Queue",@selector(showQueue:),self);
    }
    [menu addItem:[NSMenuItem separatorItem]];
    menuItem(menu,@"Add Playlist…",@selector(addPlaylist:),self);
    menuItem(menu,@"Sync All Playlists…",@selector(syncAll:),self);
    menuItem(menu,@"Load My Playlists…",@selector(discover:),self);
  } else {
    NSString *object=video?@"Video":@"Playlist";
    menuItem(menu,[NSString stringWithFormat:@"Play %@ in VLC",object],@selector(playSelectionInVLC:),self);
    menuItem(menu,[NSString stringWithFormat:@"Play %@ in Default App",object],@selector(playSelection:),self);
    menuItem(menu,[NSString stringWithFormat:@"Reveal %@ in Finder",object],@selector(revealSelection:),self);
    if(video && [self contextPlaylist]) {
      [menu addItem:[NSMenuItem separatorItem]];
      menuItem(menu,@"Play Playlist in VLC",@selector(playPlaylistInVLC:),self);
      menuItem(menu,@"Play Playlist in Default App",@selector(playTargetPlaylist:),self);
    }
  }
}
- (NSDictionary *)contextPlaylist;
{ return [self hasTargetVideo]?[self targetPlaylist]:(context_==2?[self targetPlaylist]:[self selectedPlaylist]); }
- (NSString *)selectionPlayFile;
{ return [self hasTargetVideo]?([self playable:[self targetJob]]?[library_ fileForJob:[self targetJob]]:nil):[self playFileForPlaylist:[self contextPlaylist]]; }
- (void)playSelection:(id)sender;
{
  NSString *path=[self selectionPlayFile]; if(!path) return;
  if(RDDefaultApplication(path)) RDOpenDefaultApplication(path); else [self revealSelection:sender];
}
- (void)playSelectionInVLC:(id)sender;
{ (void)sender; NSString *path=[self selectionPlayFile]; if(path) RDOpenInVLC(path); }
- (void)revealSelection:(id)sender;
{ if([self hasTargetVideo]) [self revealTarget:sender]; else if([self contextPlaylist]) [self revealPlaylistFolder:sender]; }
- (void)toolbarDefault:(id)sender;
{
  if([[self window] attachedSheet]) return;
  if([sender isKindOfClass:[NSToolbarItem class]] && ![(RDToolbarButton *)[(NSToolbarItem *)sender view] isDefaultEnabled]) return;
  switch([sender tag]) {
    case 0: [self downloadDefault:sender]; break;
    case 1: [self playSelection:sender]; break;
    case 2: if([[library_ cookieStatus] isEqualToString:@"Not Imported"]) [self importCookies:sender]; else [self replaceCookies:sender]; break;
    case 3: [self toggleDownloads:sender]; break;
  }
}
- (void)chooseDownload:(NSMenuItem *)sender;
{
  if(![self validateMenuItem:sender] || downloadSheet_) return;
  BOOL all=[sender tag]>=5; NSUInteger index=(NSUInteger)[sender tag]%5;
  if(index>0 && index<4) { [self saveDownloadQuality:[[RetroDLPLibrary qualityFormats] objectAtIndex:index-1]]; return; }
  if(index==0) {
    NSDictionary *playlist=[self contextPlaylist];
    NSMutableDictionary *request=[NSMutableDictionary dictionaryWithObjectsAndKeys:[playlist objectForKey:@"id"],@"playlist",[playlist objectForKey:@"title"],@"title",downloadFormat_,@"format",nil];
    if(!all) [request setObject:[self targetVideoID] forKey:@"video"];
    if(all) [self requestBulk:request]; else [self enqueueRequest:request]; return;
  }
  downloadSheet_=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,500,220) styleMask:AIWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [downloadSheet_ setTitle:@"Custom Download Quality"];
  NSView *view=[downloadSheet_ contentView];
  [field(view,NSMakeRect(20,182,460,28),NO) setStringValue:@"Choose the quality for future downloads."];
  customSummary_=field(view,NSMakeRect(20,146,460,32),NO);
  [field(view,NSMakeRect(20,115,460,24),NO) setStringValue:@"Format expression (for example, 18 or 136+140)"];
  customFormat_=field(view,NSMakeRect(20,83,460,24),YES); [customFormat_ setStringValue:downloadFormat_]; [customFormat_ setDelegate:(id)self];
  customError_=field(view,NSMakeRect(20,47,460,28),NO);
  NSButton *cancel=button(view,@"Cancel",@selector(dismissDownload:),self,NSMakeRect(240,10,105,28)); [cancel setTag:0]; [cancel setKeyEquivalent:@"\033"];
  NSButton *download=button(view,@"Save",@selector(dismissDownload:),self,NSMakeRect(350,10,130,28)); [download setTag:1]; [download setKeyEquivalent:@"\r"];
  [self updateCustomSummary];
  RDBeginSheet(downloadSheet_,[self window],self,@selector(downloadSheetDidEnd:returnCode:contextInfo:));
  [downloadSheet_ makeFirstResponder:customFormat_];
}
- (void)saveDownloadQuality:(NSString *)format;
{
  if(![RetroDLPLibrary savePreferredFormat:format]) return;
  [downloadFormat_ release]; downloadFormat_=[format copy]; [self refresh:nil];
}
- (void)updateCustomSummary;
{
  if(downloadSheet_) [customSummary_ setStringValue:@"Saving this quality does not start a download."];
}
- (void)controlTextDidChange:(NSNotification *)notification;
{ if([notification object]==customFormat_) { [customError_ setStringValue:@""]; [self updateCustomSummary]; } }
- (void)dismissDownload:(id)sender;
{
  if([sender tag]) {
    NSString *format=[customFormat_ stringValue];
    if(![RetroDLPLibrary validFormat:format]) { [customError_ setStringValue:@"Enter a valid format such as 18 or 136+140."]; return; }
    [downloadRequest_ release]; downloadRequest_=[[NSDictionary dictionaryWithObject:format forKey:@"format"] retain];
  }
  [NSApp endSheet:downloadSheet_ returnCode:[sender tag]];
}
- (void)downloadSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code contextInfo:(void *)context;
{
  (void)context; NSDictionary *request=[[downloadRequest_ retain] autorelease];
  [sheet orderOut:nil]; [downloadSheet_ release]; downloadSheet_=nil; customFormat_=nil; customError_=nil; customSummary_=nil;
  [downloadRequest_ release]; downloadRequest_=nil;
  if(code==1) [self saveDownloadQuality:[request objectForKey:@"format"]];
  [self updateControls];
}
- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [sidebarItems_ release]; [library_ release]; [playlists_ release]; [rows_ release]; [jobs_ release]; [selectedPlaylist_ release];
  [qualityColumn_ release]; [addSheet_ release]; [downloadSheet_ release]; [downloadRequest_ release]; [downloadFormat_ release]; [queueTree_ release]; [queueCollapsed_ release]; [toolbarItems_ release]; [confirmation_ release]; [confirmationRequest_ release]; [super dealloc];
}
- (NSDictionary *)selectedRow;
{ NSInteger row=[table_ selectedRow]; return row>=0 && (NSUInteger)row<[rows_ count]?[rows_ objectAtIndex:(NSUInteger)row]:nil; }
- (RDQueueNode *)selectedQueueNode;
{ NSInteger row=[queue_ selectedRow]; return row>=0?[queue_ itemAtRow:row]:nil; }
- (NSDictionary *)selectedJob;
{ RDQueueNode *node=[self selectedQueueNode]; return node?node->job:nil; }
- (void)expandQueuePath:(RDQueueNode *)node;
{
  if(!node) return;
  RDQueueNode *parent=[queueTree_ nodeForKey:node->parentKey];
  if(parent) { [self expandQueuePath:parent]; [queueCollapsed_ removeObject:parent->key]; [queue_ expandItem:parent]; }
}
- (void)restoreQueueExpansion:(NSArray *)nodes;
{
  NSEnumerator *e=[nodes objectEnumerator]; RDQueueNode *node;
  while((node=[e nextObject])) if([node->children count]) {
    if([queueCollapsed_ containsObject:node->key]) [queue_ collapseItem:node];
    else { [queue_ expandItem:node]; [self restoreQueueExpansion:node->children]; }
  }
}
- (void)outlineViewItemDidCollapse:(NSNotification *)notification;
{ if([notification object]==queue_ && !refreshing_) { RDQueueNode *node=[[notification userInfo] objectForKey:@"NSObject"]; if(node) [queueCollapsed_ addObject:node->key]; } }
- (void)outlineViewItemDidExpand:(NSNotification *)notification;
{ if([notification object]==queue_ && !refreshing_) { RDQueueNode *node=[[notification userInfo] objectForKey:@"NSObject"]; if(node) [queueCollapsed_ removeObject:node->key]; } }

- (NSDictionary *)selectedPlaylist;
{ unsigned int i; for(i=0;i<[playlists_ count];++i) if([[[playlists_ objectAtIndex:i] objectForKey:@"id"] isEqualToString:selectedPlaylist_]) return [playlists_ objectAtIndex:i]; return nil; }
- (NSDictionary *)jobForEntry:(NSDictionary *)entry;
{
  NSDictionary *best=nil; int bestRank=-1;
  NSEnumerator *e=[jobs_ objectEnumerator]; NSDictionary *job;
  /* jobs_ is newest-first. A playable copy wins regardless of preference. */
  while(entry && (job=[e nextObject])) {
    if(![[job objectForKey:@"playlist_id"] isEqualToString:selectedPlaylist_] ||
       ![[job objectForKey:@"video_id"] isEqualToString:[entry objectForKey:@"video_id"]]) continue;
    int rank=[self playable:job]?6:(stateIs(job,@"running")?5:(stateIs(job,@"queued")?4:
      ((stateIs(job,@"failed") || stateIs(job,@"interrupted") || stateIs(job,@"complete") ||
        (stateIs(job,@"removed") && [[job objectForKey:@"error"] length]))?3:(stateIs(job,@"cancelled")?2:1))));
    if(rank>bestRank) { best=job; bestRank=rank; }
  }
  return best;
}
- (NSString *)statusForJob:(NSDictionary *)job;
{
  if([self playable:job]) return @"Downloaded";
  if(stateIs(job,@"running")) return @"Downloading";
  if(stateIs(job,@"queued")) return @"Queued";
  if(stateIs(job,@"failed")) return @"Failed";
  if(stateIs(job,@"interrupted")) return @"Interrupted";
  if(stateIs(job,@"cancelled")) return @"Cancelled";
  if(stateIs(job,@"complete") || (stateIs(job,@"removed") && [[job objectForKey:@"error"] length])) return @"File missing";
  return @"Not downloaded";
}

- (BOOL)playable:(NSDictionary *)job;
{ return stateIs(job,@"complete") && [[NSFileManager defaultManager] fileExistsAtPath:[library_ fileForJob:job]]; }
- (void)refresh:(id)sender;
{
  (void)sender; if(refreshing_ || [queue_ isTrackingAction]) return; refreshing_=YES;
  NSString *key=mode_==0?@"position":@"id";
  NSString *selection=[[[self selectedRow] objectForKey:key] copy];
  RDQueueNode *oldNode=[self selectedQueueNode];
  NSString *queueSelection=oldNode?[oldNode->key copy]:nil;
  NSString *oldParent=oldNode?[oldNode->parentKey copy]:nil;
  NSString *oldGroup=selectedPlaylist_?playlistGroup([self selectedPlaylist]):nil;
  [playlists_ release]; playlists_=[[library_ playlists] copy];
  NSEnumerator *pe=[playlists_ objectEnumerator]; NSDictionary *p;
  while((p=[pe nextObject])) {
    NSString *identifier=[p objectForKey:@"id"];
    if(![sidebarItems_ objectForKey:identifier]) [sidebarItems_ setObject:identifier forKey:identifier];
  }
  if(mode_==0 && ![self selectedPlaylist]) { mode_=1; [selectedPlaylist_ release]; selectedPlaylist_=nil; [selection release]; selection=nil; }
  [rows_ release]; rows_=[(mode_==0?[library_ entriesForPlaylist:selectedPlaylist_]:[library_ jobsForPlaylist:nil completedOnly:YES]) copy];
  [jobs_ release]; jobs_=[[library_ jobsForPlaylist:nil completedOnly:NO] copy];
  [queueTree_ rebuildJobs:jobs_ library:library_];
  BOOL hasQuality=[table_ tableColumnWithIdentifier:@"quality"]!=nil;
  if(mode_==0 && hasQuality) [table_ removeTableColumn:qualityColumn_];
  else if(mode_==1 && !hasQuality) [table_ addTableColumn:qualityColumn_];
  [table_ sizeToFit];
  [sidebar_ reloadData]; [table_ reloadData]; [queue_ reloadData];
  [self restoreQueueExpansion:[queueTree_ roots]];
  if(!sidebarLoaded_) {
    [sidebar_ expandItem:@"System"]; [sidebar_ expandItem:@"Added Playlists"]; [sidebar_ expandItem:@"My Playlists"]; sidebarLoaded_=YES;
  } else if(selectedPlaylist_ && ![oldGroup isEqualToString:playlistGroup([self selectedPlaylist])]) {
    [sidebar_ expandItem:playlistGroup([self selectedPlaylist])];
  }
  id selectedItem=mode_==0?[sidebarItems_ objectForKey:selectedPlaylist_]:@"All Downloads";
  NSInteger selectedSidebar=[sidebar_ rowForItem:selectedItem];
  if(selectedSidebar>=0) [sidebar_ selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)selectedSidebar] byExtendingSelection:NO];
  else [sidebar_ deselectAll:nil];
  restoreSelection(table_,rows_,mode_==0?@"position":@"id",selection);
  RDQueueNode *selectedNode=[queueTree_ nodeForKey:queueSelection];
  if(selectedNode && ![oldParent isEqualToString:selectedNode->parentKey]) [self expandQueuePath:selectedNode];
  NSInteger queueRow=selectedNode?[queue_ rowForItem:selectedNode]:-1;
  if(queueRow>=0) [queue_ selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)queueRow] byExtendingSelection:NO];
  else [queue_ deselectAll:nil];
  [oldParent release];
  [selection release]; [queueSelection release]; refreshing_=NO; [self updateCustomSummary]; [self updateControls];
}
- (void)tableWasUsed:(NSTableView *)view;
{
  if(refreshing_) return;
  context_=view==sidebar_?0:(view==queue_?2:1); [self updateControls];
}
- (BOOL)hasTargetVideo;
{ RDQueueNode *node=[self selectedQueueNode]; return context_==2?(node && node->kind>=RDQueueVideo):(context_==1 && [self selectedRow]!=nil); }
- (NSDictionary *)targetJob;
{ return context_==2?[self selectedJob]:(context_==1?(mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow]):nil); }
- (NSDictionary *)targetPlaylist;
{
  NSDictionary *job=[self targetJob];
  NSString *key=job?[job objectForKey:@"playlist_id"]:selectedPlaylist_;
  if(context_==2) { RDQueueNode *node=[self selectedQueueNode]; key=node?node->playlistID:nil; }
  if(!key) return nil;
  NSEnumerator *e=[playlists_ objectEnumerator]; NSDictionary *playlist;
  while((playlist=[e nextObject])) if([[playlist objectForKey:@"id"] isEqualToString:key]) return playlist;
  return nil;
}
- (NSString *)targetVideoID;
{ RDQueueNode *node=[self selectedQueueNode]; return context_==2?(node?node->videoID:nil):(context_==1?[[self selectedRow] objectForKey:@"video_id"]:nil); }
- (NSString *)targetFormat;
{ NSDictionary *job=[self targetJob]; return (context_==2 || (context_==1 && mode_==1))?([job objectForKey:@"format"]?:downloadFormat_):downloadFormat_; }
- (NSDictionary *)jobForPlaylist:(NSString *)playlist video:(NSString *)video format:(NSString *)format;
{
  NSEnumerator *e=[jobs_ objectEnumerator]; NSDictionary *job;
  while((job=[e nextObject])) if([[job objectForKey:@"playlist_id"] isEqualToString:playlist] && [[job objectForKey:@"video_id"] isEqualToString:video] && [[job objectForKey:@"format"] isEqualToString:format]) return job;
  return nil;
}
- (BOOL)canRetry:(NSDictionary *)job;
{ return stateIs(job,@"failed") || stateIs(job,@"cancelled") || stateIs(job,@"interrupted"); }
- (BOOL)canDownloadAgain:(NSDictionary *)job;
{ return stateIs(job,@"removed") || (stateIs(job,@"complete") && ![self playable:job]); }
- (BOOL)canRemove:(NSDictionary *)job;
{ return job && ![library_ isBusy] && !stateIs(job,@"running") && !stateIs(job,@"removed"); }
- (BOOL)canCancel:(NSDictionary *)job;
{ return stateIs(job,@"queued") || stateIs(job,@"running"); }
- (NSDictionary *)currentJob:(NSString *)key;
{
  NSEnumerator *e=[[library_ jobsForPlaylist:nil completedOnly:NO] objectEnumerator]; NSDictionary *job;
  while((job=[e nextObject])) if([[job objectForKey:@"id"] isEqualToString:key]) return job;
  return nil;
}
- (NSString *)playFileForPlaylist:(NSDictionary *)playlist;
{
  if(!playlist) return nil;
  NSString *path=[library_ playlistFile:playlist];
  if(![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
  NSEnumerator *e=[jobs_ objectEnumerator]; NSDictionary *job;
  while((job=[e nextObject])) if([[job objectForKey:@"playlist_id"] isEqualToString:[playlist objectForKey:@"id"]] && [self playable:job]) return path;
  return nil;
}
- (NSString *)targetPlaylistFolder;
{
  NSDictionary *playlist=[self selectedPlaylist];
  NSString *path=playlist?[[library_ playlistFile:playlist] stringByDeletingLastPathComponent]:nil;
  BOOL directory=NO;
  return path && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && directory?path:nil;
}
- (NSArray *)missingPlanForPlaylist:(NSString *)playlist format:(NSString *)format;
{
  NSMutableArray *plan=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
  NSEnumerator *e=[[library_ entriesForPlaylist:playlist] objectEnumerator]; NSDictionary *entry;
  while((entry=[e nextObject])) {
    NSString *video=[entry objectForKey:@"video_id"]; if([seen containsObject:video]) continue; [seen addObject:video];
    NSDictionary *job=[self jobForPlaylist:playlist video:video format:format];
    if(!job || [self canDownloadAgain:job]) {
      NSMutableDictionary *item=[NSMutableDictionary dictionaryWithObjectsAndKeys:playlist,@"playlist",video,@"video",format,@"format",nil];
      if(job) [item setObject:[job objectForKey:@"id"] forKey:@"job"];
      [plan addObject:item];
    }
  }
  return plan;
}
- (NSArray *)syncPlan;
{
  NSMutableArray *inputs=[NSMutableArray array]; NSEnumerator *e=[playlists_ objectEnumerator]; NSDictionary *playlist;
  while((playlist=[e nextObject])) if(![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]]) [inputs addObject:[playlist objectForKey:@"service_id"]];
  return inputs;
}
- (NSUInteger)queuedCount;
{
  NSUInteger count=0; NSEnumerator *e=[jobs_ objectEnumerator]; NSDictionary *job;
  while((job=[e nextObject])) if(stateIs(job,@"queued")) ++count;
  return count;
}
- (void)setToolbarItem:(NSString *)key title:(NSString *)title tip:(NSString *)tip icon:(NSImage *)icon enabled:(BOOL)enabled;
{
  NSToolbarItem *item=[toolbarItems_ objectForKey:key]; RDToolbarButton *view=(RDToolbarButton *)[item view];
  [item setLabel:title]; [item setToolTip:tip]; [view setTitle:title]; [view setToolTip:tip];
  if(icon) [view setImage:icon];
  [view setDefaultEnabled:enabled && ![[self window] attachedSheet]];
}
- (void)updateToolbar;
{
  NSDictionary *playlist=[self contextPlaylist], *job=[self targetJob];
  BOOL video=[self hasTargetVideo], enabled=YES;
  BOOL delete=video && [self playable:job];
  AIFontAwesomeIcon icon=AIFADownload; NSString *tip=nil;
  if(video) {
    icon=delete?AIFATrash:([self canCancel:job]?AIFAHourglass:AIFADownload);
    if(delete) enabled=[self canRemove:job];
    tip=[NSString stringWithFormat:@"%@ — %@ (%@)",delete?@"Delete downloaded video…":([self canCancel:job]?@"Show in Queue":@"Download video"),job?[job objectForKey:@"title"]:(context_==2?[self selectedQueueNode]->title:[[self selectedRow] objectForKey:@"title"]),job?[job objectForKey:@"format"]:[self targetFormat]];
  } else if(playlist) {
    icon=AIFAArrowsRotate;
    enabled=![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]];
    tip=[NSString stringWithFormat:@"Sync ‘%@’",[playlist objectForKey:@"title"]];
  } else { icon=(AIFontAwesomeIcon)0x2b; tip=@"Add a playlist…"; }
  [self setToolbarItem:@"download" title:video?(delete?@"Delete":@"Download"):(playlist?@"Sync":@"Add Playlist") tip:tip icon:toolbarIcon(icon,[self window]) enabled:enabled];
  NSString *path=[self selectionPlayFile], *application=RDDefaultApplication(path);
  NSString *object=video?@"video":@"playlist";
  NSString *playTip=path?(application?[NSString stringWithFormat:@"Play %@ in %@",object,[[[NSFileManager defaultManager] displayNameAtPath:application] stringByDeletingPathExtension]]:[NSString stringWithFormat:@"Reveal %@ in Finder",object]):@"Select a downloaded video or playlist to play";
  [self setToolbarItem:@"play" title:@"Play" tip:playTip icon:RDYouTubeIcon(RDWindowBackingScale([self window])) enabled:path!=nil];
  BOOL cookies=[[library_ cookieStatus] isEqualToString:@"Imported"];
  [self setToolbarItem:@"cookies" title:@"Cookies" tip:[[library_ cookieStatus] isEqualToString:@"Not Imported"]?@"Import cookies…":@"Replace cookies…" icon:toolbarIcon(cookies?AIFACookie:AIFACookieBite,[self window]) enabled:![library_ isBusy]];
  [self setToolbarItem:@"downloads" title:@"Queue" tip:[self isInspectorCollapsed]?@"Show Queue. Right-click for queue actions.":@"Hide Queue. Right-click for queue actions." icon:nil enabled:YES];
}
- (void)updateControls;
{
  [self updateToolbar];
  [status_ setStringValue:[library_ status]];
  [status_ setToolTip:[library_ status]];
  NSDictionary *progress=[library_ queueProgress];
  NSUInteger processed=[[progress objectForKey:@"processed"] unsignedLongValue];
  NSUInteger total=[[progress objectForKey:@"total"] unsignedLongValue];
  [queueProgress_ setHidden:![[progress objectForKey:@"active"] boolValue]];
  [queueProgress_ setMaxValue:(double)MAX(total,1)]; [queueProgress_ setDoubleValue:(double)processed];
  [queueProgress_ setToolTip:[NSString stringWithFormat:@"%lu of %lu processed · %@ failed · %@ stopped",(unsigned long)processed,(unsigned long)total,[progress objectForKey:@"failed"],[progress objectForKey:@"cancelled"]]];
}

- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item;
{
  if(outline==queue_) return (NSInteger)[(item?((RDQueueNode *)item)->children:[queueTree_ roots]) count];
  if(!item) return 3; if([item isEqual:@"System"]) return 1;
  NSInteger count=0; NSEnumerator *e=[playlists_ objectEnumerator]; NSDictionary *playlist;
  while((playlist=[e nextObject])) if([playlistGroup(playlist) isEqual:item]) ++count;
  return count;
}
- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item;
{
  if(outline==queue_) return [(item?((RDQueueNode *)item)->children:[queueTree_ roots]) objectAtIndex:(NSUInteger)index];
  if(!item) return [[NSArray arrayWithObjects:@"System",@"Added Playlists",@"My Playlists",nil] objectAtIndex:(NSUInteger)index];
  if([item isEqual:@"System"]) return @"All Downloads";
  NSEnumerator *e=[playlists_ objectEnumerator]; NSDictionary *playlist;
  while((playlist=[e nextObject])) if([playlistGroup(playlist) isEqual:item] && index--==0) return [sidebarItems_ objectForKey:[playlist objectForKey:@"id"]];
  return nil;
}
- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item;
{ return outline==queue_?[((RDQueueNode *)item)->children count]>0:sidebarGroup(item); }
- (BOOL)outlineView:(NSOutlineView *)outline shouldSelectItem:(id)item;
{ return outline==queue_?((RDQueueNode *)item)->kind!=RDQueueGroup:!sidebarGroup(item); }
- (id)outlineView:(NSOutlineView *)outline objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item;
{
  if(outline==queue_) {
    RDQueueNode *node=item;
    if([[column identifier] isEqualToString:@"action"]) return @"";
    if(node->kind==RDQueueGroup) {
      if([node->key isEqualToString:@"status:1"] && [[[library_ queueProgress] objectForKey:@"active"] boolValue])
        return [NSString stringWithFormat:@"Downloading · %@ of %@ processed",[[library_ queueProgress] objectForKey:@"processed"],[[library_ queueProgress] objectForKey:@"total"]];
      return node->title;
    }
    return node->title;
  }
  if(sidebarGroup(item) || [item isEqual:@"All Downloads"]) return item;
  NSEnumerator *e=[playlists_ objectEnumerator]; NSDictionary *playlist;
  while((playlist=[e nextObject])) if([[playlist objectForKey:@"id"] isEqual:item]) return [NSString stringWithFormat:@"%@ (%@)",[playlist objectForKey:@"title"],[playlist objectForKey:@"count"]];
  return @"";
}
- (void)outlineView:(NSOutlineView *)outline willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column item:(id)item;
{
  if(outline==queue_) {
    if([[column identifier] isEqualToString:@"action"]) return;
    [cell setFont:((RDQueueNode *)item)->kind==RDQueueGroup?[NSFont boldSystemFontOfSize:12]:[NSFont systemFontOfSize:0]];
    return;
  }
  BOOL bold=sidebarGroup(item);
  [cell setFont:bold?[NSFont boldSystemFontOfSize:12]:[NSFont systemFontOfSize:12]];
}
- (NSString *)outlineView:(NSOutlineView *)outline toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column item:(id)item mouseLocation:(NSPoint)point;
{
  (void)cell; (void)rect; (void)point; if(outline!=queue_) return nil;
  RDQueueNode *node=item;
  if([[column identifier] isEqualToString:@"action"]) return node->action==RDQueueStop?@"Stop this download. Retrying starts it again.":(node->action==RDQueueRetry?@"Retry this quality":nil);
  NSString *error=[node->job objectForKey:@"error"];
  return [error length]?[NSString stringWithFormat:@"%@\n%@",node->title,error]:node->title;
}
- (void)outlineView:(NSOutlineView *)outline setObjectValue:(id)value forTableColumn:(NSTableColumn *)column byItem:(id)item;
{ (void)outline; (void)value; (void)column; (void)item; /* Momentary action cells have no stored value. */ }
- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
{ [self tableViewSelectionDidChange:notification]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)view;
{ (void)view; return (NSInteger)[rows_ count]; }
- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
{
  (void)view;
  NSDictionary *entry=[rows_ objectAtIndex:(NSUInteger)row]; NSString *key=[column identifier];
  NSDictionary *job=mode_==0?[self jobForEntry:entry]:entry;
  if([key isEqualToString:@"quality"]) return mode_==0?downloadFormat_:([[job objectForKey:@"actual_format"] length]?[job objectForKey:@"actual_format"]:[job objectForKey:@"format"]);
  if([key isEqualToString:@"state"]) {
    NSString *status=[self statusForJob:job]; AIFontAwesomeIcon icon=0;
    if([status isEqualToString:@"Downloaded"]) icon=AIFACircleCheck;
    else if([status isEqualToString:@"Downloading"]) icon=AIFAArrowDown;
    else if([status isEqualToString:@"Queued"]) icon=AIFAClock;
    else if([status isEqualToString:@"Cancelled"]) icon=AIFACirclePause;
    else if(![status isEqualToString:@"Not downloaded"]) icon=AIFATriangleExclamation;
    return icon?[AIFontAwesome imageForIcon:icon style:AIFontAwesomeStyleSolid iconSize:12 canvasSize:16 scale:RDWindowBackingScale([self window])]:nil;
  }
  return [entry objectForKey:key];
}
- (void)tableView:(NSTableView *)view willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row;
{
  (void)view;
  if([[column identifier] isEqualToString:@"state"]) {
    NSDictionary *entry=[rows_ objectAtIndex:(NSUInteger)row];
    [cell setRepresentedObject:[self statusForJob:mode_==0?[self jobForEntry:entry]:entry]];
  }
}
- (NSString *)tableView:(NSTableView *)view toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column row:(NSInteger)row mouseLocation:(NSPoint)point;
{
  (void)view; (void)cell; (void)rect; (void)point;
  NSDictionary *entry=[rows_ objectAtIndex:(NSUInteger)row];
  if(![[column identifier] isEqualToString:@"state"]) return [entry objectForKey:@"title"];
  NSDictionary *job=mode_==0?[self jobForEntry:entry]:entry;
  NSString *status=[self statusForJob:job], *error=[job objectForKey:@"error"];
  return [error length]?[NSString stringWithFormat:@"%@: %@",status,error]:status;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
{
  if(refreshing_) return;
  context_=[notification object]==sidebar_?0:([notification object]==queue_?2:1);
  if([notification object]==sidebar_) {
    NSInteger row=[sidebar_ selectedRow]; if(row<0) return;
    refreshing_=YES; [table_ deselectAll:nil]; refreshing_=NO;
    id item=[sidebar_ itemAtRow:row]; if(sidebarGroup(item)) return;
    mode_=[item isEqual:@"All Downloads"]?1:0; [selectedPlaylist_ release];
    selectedPlaylist_=mode_==0?[item copy]:nil;
    [self refresh:nil];
  } else [self updateControls];
}
- (BOOL)validateToolbarItem:(NSToolbarItem *)item;
{ (void)item; [self updateToolbar]; return YES; }
- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
  SEL visibilityAction=[item action];
  if(visibilityAction==@selector(togglePlaylists:)) [item setTitle:[self isSidebarCollapsed]?@"Show Playlists":@"Hide Playlists"];
  if(visibilityAction==@selector(toggleDownloads:)) [item setTitle:[self isInspectorCollapsed]?@"Show Download Queue":@"Hide Download Queue"];
  if([[item menu] title] && [[[item menu] title] isEqualToString:@"File"]) {
    NSString *object=[self hasTargetVideo]?@"Video":@"Playlist";
    if(visibilityAction==@selector(playSelection:)) [item setTitle:[NSString stringWithFormat:@"Play %@ in Default App",object]];
    if(visibilityAction==@selector(playSelectionInVLC:)) [item setTitle:[NSString stringWithFormat:@"Play %@ in VLC",object]];
    if(visibilityAction==@selector(downloadFromMenu:)) [item setTitle:[self hasTargetVideo]?@"Download Video":@"Download Missing Videos"];
  }
  if([[self window] attachedSheet]) return NO;
  if(visibilityAction==@selector(downloadFromMenu:)) {
    if(context_==2 && [self selectedJob]) return [self canRetry:[self selectedJob]] || [self canDownloadAgain:[self selectedJob]];
    NSMenuItem *command=[[[NSMenuItem alloc] initWithTitle:@"" action:@selector(chooseDownload:) keyEquivalent:@""] autorelease];
    [command setTag:[self hasTargetVideo]?0:5]; return [self validateMenuItem:command];
  }
  SEL action=[item action]; NSDictionary *job=[self targetJob], *playlist=[self contextPlaylist], *queued=[self selectedJob];
  BOOL noCookies=[[library_ cookieStatus] isEqualToString:@"Not Imported"];
  if(action==@selector(importCookies:)) return ![library_ isBusy] && noCookies;
  if(action==@selector(replaceCookies:) || action==@selector(clearCookies:)) return ![library_ isBusy] && !noCookies;
  if(action==@selector(discover:)) return ![library_ isBusy] && ![library_ isDiscoveryPending];
  if(action==@selector(sync:)) return playlist && ![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]];
  if(action==@selector(syncAll:)) return [[self syncPlan] count]>0;
  if(action==@selector(chooseDownload:)) {
    BOOL all=[item tag]>=5; NSUInteger index=(NSUInteger)[item tag]%5;
    if(index>0) {
      NSString *format=index<4?[[RetroDLPLibrary qualityFormats] objectAtIndex:index-1]:nil;
      BOOL custom=![[RetroDLPLibrary qualityFormats] containsObject:downloadFormat_];
      [item setState:(index==4?custom:[format isEqualToString:downloadFormat_])?NSOnState:NSOffState];
      return YES;
    }
    [item setState:NSOffState];
    playlist=[self contextPlaylist];
    if(!playlist || (!all && ![self hasTargetVideo])) return NO;
    NSString *format=downloadFormat_;
    if(all) return [[self missingPlanForPlaylist:[playlist objectForKey:@"id"] format:format] count]>0;
    NSDictionary *matching=[self jobForPlaylist:[playlist objectForKey:@"id"] video:[self targetVideoID] format:format];
    return !matching || [self canRetry:matching] || [self canDownloadAgain:matching];
  }
  if(action==@selector(retryTarget:)) return [self canRetry:job];
  if(action==@selector(againTarget:)) return [self canDownloadAgain:job];
  if(action==@selector(cancelTarget:)) return [self canCancel:job];
  if(action==@selector(removeTarget:)) return [self canRemove:job];
  if(action==@selector(showTargetInQueue:)) return job!=nil;
  if(action==@selector(playSelection:)) return RDDefaultApplication([self selectionPlayFile])!=nil;
  if(action==@selector(playSelectionInVLC:)) return [self selectionPlayFile]!=nil && [[NSWorkspace sharedWorkspace] fullPathForApplication:@"VLC"]!=nil;
  if(action==@selector(revealSelection:)) return [self hasTargetVideo]?[self playable:job]:([self contextPlaylist]!=nil && [self targetPlaylistFolder]!=nil);
  if(action==@selector(playVideoInVLC:)) return [self playable:job] && [[NSWorkspace sharedWorkspace] fullPathForApplication:@"VLC"]!=nil;
  if(action==@selector(playPlaylistInVLC:)) return [self playFileForPlaylist:[self contextPlaylist]]!=nil && [[NSWorkspace sharedWorkspace] fullPathForApplication:@"VLC"]!=nil;
  if(action==@selector(playTargetVideo:)) return [self playable:job] && RDDefaultApplication([library_ fileForJob:job])!=nil;
  if(action==@selector(playTargetPlaylist:)) return RDDefaultApplication([self playFileForPlaylist:[self contextPlaylist]])!=nil;
  if(action==@selector(revealTarget:)) return [self playable:job];
  if(action==@selector(revealPlaylistFolder:)) return [self targetPlaylistFolder]!=nil;
  if(action==@selector(openDownloadsFolder:)) return [[NSFileManager defaultManager] fileExistsAtPath:[library_ downloadsDirectory]];
  if(action==@selector(showQueue:)) return [self isInspectorCollapsed];
  if(action==@selector(hideQueue:)) return ![self isInspectorCollapsed];
  if(action==@selector(showQueueError:)) return [[queued objectForKey:@"error"] length]>0;
  if(action==@selector(retryQueueJob:)) return [self canRetry:queued] || [self canDownloadAgain:queued];
  if(action==@selector(againQueueJob:)) return [self canDownloadAgain:queued];
  if(action==@selector(cancelQueueJob:)) return [self canCancel:queued];
  if(action==@selector(removeJob:)) return [self canRemove:queued];
  if(action==@selector(openJob:)) return [self playable:queued] && RDDefaultApplication([library_ fileForJob:queued])!=nil;
  if(action==@selector(removeDownload:)) return [self canRemove:mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow]];
  if(action==@selector(removePlaylist:)) return [self canRemovePlaylist:[self contextPlaylist]];
  if(action==@selector(playPlaylist:)) return RDDefaultApplication([self playFileForPlaylist:[self selectedPlaylist]])!=nil;
  return YES;
}
- (void)addPlaylist:(id)sender;
{
  (void)sender; if(addSheet_ || [[self window] attachedSheet]) return;
  addSheet_=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,460,135) styleMask:AIWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [addSheet_ setTitle:@"Add Playlist"];
  NSView *view=[addSheet_ contentView]; [field(view,NSMakeRect(20,95,420,24),NO) setStringValue:@"Playlist URL or ID"];
  input_=field(view,NSMakeRect(20,62,420,24),YES);
  NSButton *cancel=button(view,@"Cancel",@selector(dismissAdd:),self,NSMakeRect(230,15,100,28)); [cancel setTag:0]; [cancel setKeyEquivalent:@"\033"];
  NSButton *add=button(view,@"Add Playlist",@selector(dismissAdd:),self,NSMakeRect(335,15,110,28)); [add setTag:1]; [add setKeyEquivalent:@"\r"];
  RDBeginSheet(addSheet_,[self window],self,@selector(addSheetDidEnd:returnCode:contextInfo:));
  [addSheet_ makeFirstResponder:input_];
}
- (void)dismissAdd:(id)sender;
{ [NSApp endSheet:addSheet_ returnCode:[sender tag]]; }
- (void)addSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code contextInfo:(void *)context;
{
  (void)context; NSString *input=[[input_ stringValue] copy]; [sheet orderOut:nil];
  [addSheet_ release]; addSheet_=nil; input_=nil;
  if(code==1) [library_ syncPlaylistInput:input]; [input release];
}
- (void)confirmRequest:(NSDictionary *)request title:(NSString *)title detail:(NSString *)detail action:(NSString *)action;
{
  if([[self window] attachedSheet] || confirmation_) return;
  confirmationRequest_=[request copy]; confirmation_=[[NSAlert alloc] init];
  [confirmation_ setMessageText:title]; [confirmation_ setInformativeText:detail];
  [confirmation_ addButtonWithTitle:@"Cancel"]; [confirmation_ addButtonWithTitle:action];
  RDBeginAlertSheet(confirmation_,[self window],self,@selector(confirmationDidEnd:returnCode:contextInfo:));
  [self updateControls];
}
- (void)confirmationDidEnd:(NSAlert *)alert returnCode:(NSInteger)code contextInfo:(void *)context;
{
  (void)context; NSDictionary *request=[[confirmationRequest_ retain] autorelease];
  [[alert window] orderOut:nil]; [confirmation_ release]; confirmation_=nil;
  [confirmationRequest_ release]; confirmationRequest_=nil;
  if(code==NSAlertSecondButtonReturn) [self performSelector:@selector(performConfirmed:) withObject:request afterDelay:0];
  [self updateControls];
}
- (void)performConfirmed:(NSDictionary *)request;
{
  NSString *op=[request objectForKey:@"operation"];
  if([op isEqualToString:@"bulkDownload"]) { [self enqueueRequest:request]; return; }
  if([op isEqualToString:@"bulk"]) {
    /* The sheet captures its exact plan; revalidate each job before acting. */
    NSEnumerator *e=[[request objectForKey:@"plan"] objectEnumerator]; NSDictionary *item;
    while((item=[e nextObject])) [self enqueueSingle:item allowRetry:NO];
  } else if([op isEqualToString:@"syncAll"]) {
    NSEnumerator *e=[[request objectForKey:@"inputs"] objectEnumerator]; NSString *input;
    while((input=[e nextObject])) [library_ syncPlaylistInput:input];
  } else if([op isEqualToString:@"discover"]) {
    if([library_ isBusy] || [library_ isDiscoveryPending]) return;
    if(![[library_ cookieStatus] isEqualToString:@"Imported"]) {
      NSString *path=RDChooseCookieFile(); if(!path) return;
      if(![[library_ cookieStatus] isEqualToString:@"Not Imported"]) {
        [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:@"import",@"operation",path,@"path",@"yes",@"discover",nil] title:@"Replace cookies and load playlists?" detail:@"Replace the app’s working cookie copy, then discover your account playlists. No videos will be downloaded." action:@"Replace and Load"]; return;
      }
      if(![library_ importCookies:path]) return;
    }
    [library_ discoverPlaylists];
  } else if([op isEqualToString:@"import"]) {
    if(![library_ isBusy] && [library_ importCookies:[request objectForKey:@"path"]] && [request objectForKey:@"discover"]) [library_ discoverPlaylists];
  } else if([op isEqualToString:@"clearCookies"]) {
    if(![library_ isBusy]) [library_ clearCookies];
  } else if([op isEqualToString:@"removePlaylist"]) {
    NSDictionary *playlist=[request objectForKey:@"playlist"];
    if([self canRemovePlaylist:playlist]) [library_ removePlaylist:playlist];
  } else {
    NSDictionary *job=[self currentJob:[request objectForKey:@"job"]];
    if([op isEqualToString:@"cancel"] && [self canCancel:job]) [library_ cancelJob:[job objectForKey:@"id"]];
    if([op isEqualToString:@"remove"] && [self canRemove:job]) [library_ removeDownload:job];
  }
  [self refresh:nil];
}
- (void)confirmJob:(NSDictionary *)job remove:(BOOL)remove;
{
  if(remove?![self canRemove:job]:![self canCancel:job]) return;
  NSString *title=[NSString stringWithFormat:@"%@ ‘%@’ (%@)?",remove?@"Delete download for":@"Cancel download for",[job objectForKey:@"title"],[job objectForKey:@"format"]];
  [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:remove?@"remove":@"cancel",@"operation",[job objectForKey:@"id"],@"job",nil] title:title detail:remove?@"This deletes this download and its partial files. Playlist membership and other downloaded qualities are retained.":@"Retrying this job restarts the transfer; it does not resume from where it stopped." action:remove?@"Delete Download":@"Cancel Download"];
}
- (BOOL)canRemovePlaylist:(NSDictionary *)playlist;
{
  if(!playlist || [library_ isBusy]) return NO;
  NSEnumerator *e=[[library_ jobsForPlaylist:[playlist objectForKey:@"id"] completedOnly:NO] objectEnumerator]; NSDictionary *job;
  while((job=[e nextObject])) if([self canCancel:job] || stateIs(job,@"complete")) return NO;
  return YES;
}
- (void)retryAndRevealJob:(NSDictionary *)job;
{
  if(![self canRetry:job] && ![self canDownloadAgain:job]) return;
  NSString *key=[[[job objectForKey:@"id"] copy] autorelease];
  [library_ retryJob:key]; [self refresh:nil]; [self showJobInQueue:[self currentJob:key]];
}
- (void)enqueueSingle:(NSDictionary *)request allowRetry:(BOOL)allowRetry;
{
  NSString *playlist=[request objectForKey:@"playlist"], *video=[request objectForKey:@"video"], *format=[request objectForKey:@"format"];
  NSDictionary *job=nil; NSEnumerator *e=[[library_ jobsForPlaylist:playlist completedOnly:NO] objectEnumerator]; NSDictionary *candidate;
  while((candidate=[e nextObject])) if([[candidate objectForKey:@"video_id"] isEqualToString:video] && [[candidate objectForKey:@"format"] isEqualToString:format]) { job=candidate; break; }
  if(!job) {
    [library_ enqueuePlaylist:playlist video:video format:format];
    [self refresh:nil]; [self showJobInQueue:[self jobForPlaylist:playlist video:video format:format]];
  } else if([self canDownloadAgain:job] || (allowRetry && [self canRetry:job])) [self retryAndRevealJob:job];
}
- (void)enqueueRequest:(NSDictionary *)request;
{
  NSString *format=[request objectForKey:@"format"];
  if(![RetroDLPLibrary savePreferredFormat:format]) return;
  [downloadFormat_ release]; downloadFormat_=[format copy];
  [self revealDownloads];
  if([request objectForKey:@"video"]) [self enqueueSingle:request allowRetry:YES];
  else [self performConfirmed:[NSDictionary dictionaryWithObjectsAndKeys:@"bulk",@"operation",[request objectForKey:@"plan"],@"plan",nil]];
  [self refresh:nil];
}
- (void)requestBulk:(NSDictionary *)request;
{
  NSString *playlist=[request objectForKey:@"playlist"], *format=[request objectForKey:@"format"];
  NSArray *plan=[self missingPlanForPlaylist:playlist format:format]; if(![plan count]) return;
  NSMutableDictionary *captured=[NSMutableDictionary dictionaryWithDictionary:request];
  [captured setObject:plan forKey:@"plan"]; [captured setObject:@"bulkDownload" forKey:@"operation"];
  NSString *title=[NSString stringWithFormat:@"Download %lu missing videos?",(unsigned long)[plan count]];
  NSString *detail=[NSString stringWithFormat:@"Playlist: %@\nQuality: %@\nExisting failed or cancelled jobs will not be retried.",[request objectForKey:@"title"]?:playlist,format];
  [self confirmRequest:captured title:title detail:detail action:[NSString stringWithFormat:@"Download %lu Videos",(unsigned long)[plan count]]];
}
- (void)downloadDefault:(id)sender;
{
  if([[self window] attachedSheet]) return;
  NSDictionary *playlist=[self contextPlaylist], *job=[self targetJob];
  if([self hasTargetVideo]) {
    if([self playable:job]) { [self removeTarget:sender]; return; }
    if([self canRetry:job] || [self canDownloadAgain:job]) { [self retryAndRevealJob:job]; return; }
    if(job) { [self showTargetInQueue:sender]; return; }
    if(playlist) [self enqueueRequest:[NSDictionary dictionaryWithObjectsAndKeys:[playlist objectForKey:@"id"],@"playlist",[self targetVideoID],@"video",[self targetFormat],@"format",nil]];
  } else if(playlist) {
    [self sync:sender];
  } else [self addPlaylist:sender];
}
- (void)sync:(id)sender;
{ (void)sender; NSDictionary *playlist=[self contextPlaylist]; if(playlist) [library_ syncPlaylistInput:[playlist objectForKey:@"service_id"]]; }
- (void)syncAll:(id)sender;
{
  (void)sender; NSArray *inputs=[self syncPlan]; if(![inputs count]) return;
  [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:@"syncAll",@"operation",inputs,@"inputs",nil] title:[NSString stringWithFormat:@"Sync %lu playlists?",(unsigned long)[inputs count]] detail:@"Refresh playlist metadata from YouTube. This does not download videos." action:[NSString stringWithFormat:@"Sync %lu Playlists",(unsigned long)[inputs count]]];
}
- (void)discover:(id)sender;
{
  (void)sender; if([library_ isBusy] || [library_ isDiscoveryPending]) return;
  [self confirmRequest:[NSDictionary dictionaryWithObject:@"discover" forKey:@"operation"] title:@"Load your account playlists?" detail:@"Discover playlists from YouTube and save their metadata locally. You will be asked to import cookies if needed. No videos will be downloaded." action:@"Load Playlists"];
}
- (void)openCookieExportGuide:(id)sender;
{
  (void)sender;
  if(![[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/yt-dlp/yt-dlp/wiki/Extractors"]]) RDAlert(@"Could not open the cookie export guide in your browser.");
}
- (void)importCookies:(id)sender;
{
  (void)sender; if([library_ isBusy] || [[self window] attachedSheet]) return;
  if(![[library_ cookieStatus] isEqualToString:@"Not Imported"]) { [self replaceCookies:nil]; return; }
  NSString *path=RDChooseCookieFile(); if(path) [library_ importCookies:path];
}
- (void)replaceCookies:(id)sender;
{
  (void)sender; if([library_ isBusy] || [[self window] attachedSheet]) return;
  NSString *path=RDChooseCookieFile(); if(!path) return;
  [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:@"import",@"operation",path,@"path",nil] title:@"Replace imported cookies?" detail:@"Replace the app’s working cookie copy with the selected file. The original exported files are retained." action:@"Replace"];
}
- (void)clearCookies:(id)sender;
{
  (void)sender; if([library_ isBusy] || [[library_ cookieStatus] isEqualToString:@"Not Imported"]) return;
  [self confirmRequest:[NSDictionary dictionaryWithObject:@"clearCookies" forKey:@"operation"] title:@"Remove imported cookies?" detail:@"Remove the app’s working cookie copy. The original exported file is retained." action:@"Remove"];
}
- (void)queueCellAction:(id)sender;
{
  (void)sender; if([[self window] attachedSheet]) return;
  NSString *key=[queue_ actionJobID];
  RDQueueNode *node=key?[queueTree_ nodeForKey:[@"job:" stringByAppendingString:key]]:nil;
  NSDictionary *job=node?node->job:nil;
  if([self canCancel:job]) [self confirmJob:job remove:NO];
  else if([self canRetry:job] || [self canDownloadAgain:job]) [self retryAndRevealJob:job];
}
- (void)showQueueError:(id)sender;
{ (void)sender; NSString *error=[[self selectedJob] objectForKey:@"error"]; if([error length]) RDAlert(error); }
- (void)togglePlaylists:(id)sender;
{ if([[self window] attachedSheet]) return; [self toggleSidebar:sender]; [self updateControls]; }
- (void)toggleDownloads:(id)sender;
{ if([self isInspectorCollapsed]) [self showQueue:sender]; else [self hideQueue:sender]; }
- (void)showQueue:(id)sender;
{ if([self isInspectorCollapsed]) [self toggleInspector:sender]; [self updateControls]; }
- (void)hideQueue:(id)sender;
{
  if(![self isInspectorCollapsed]) [self toggleInspector:sender];
  if(context_==2) context_=[self selectedRow]?1:0; [self updateControls];
}
- (void)revealDownloads; { [self showQueue:nil]; }
- (void)showJobInQueue:(NSDictionary *)job;
{
  if(!job) return;
  NSString *key=[[[job objectForKey:@"id"] copy] autorelease];
  [self revealDownloads]; refreshing_=YES;
  RDQueueNode *node=[queueTree_ nodeForKey:[@"job:" stringByAppendingString:key]];
  [self expandQueuePath:node]; NSInteger row=node?[queue_ rowForItem:node]:-1;
  if(row>=0) [queue_ selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  refreshing_=NO;
  if([queue_ selectedRow]>=0) [queue_ scrollRowToVisible:[queue_ selectedRow]];
  [self updateControls];
}
- (void)showTargetInQueue:(id)sender; { (void)sender; [self showJobInQueue:[self targetJob]]; }
- (void)retryTarget:(id)sender;
{ (void)sender; NSDictionary *job=[self targetJob]; if([self canRetry:job]) [self retryAndRevealJob:job]; }
- (void)againTarget:(id)sender;
{ (void)sender; NSDictionary *job=[self targetJob]; if([self canDownloadAgain:job]) [self retryAndRevealJob:job]; }
- (void)cancelTarget:(id)sender; { (void)sender; [self confirmJob:[self targetJob] remove:NO]; }
- (void)removeTarget:(id)sender; { (void)sender; [self confirmJob:[self targetJob] remove:YES]; }
- (void)retryQueueJob:(id)sender;
{ (void)sender; NSDictionary *job=[self selectedJob]; if([self canRetry:job] || [self canDownloadAgain:job]) [self retryAndRevealJob:job]; }
- (void)againQueueJob:(id)sender;
{ (void)sender; NSDictionary *job=[self selectedJob]; if([self canDownloadAgain:job]) [self retryAndRevealJob:job]; }
- (void)cancelQueueJob:(id)sender; { (void)sender; [self confirmJob:[self selectedJob] remove:NO]; }
- (void)jobAction:(id)sender;
{
  NSDictionary *job=[self selectedJob];
  if([self canCancel:job]) [self cancelQueueJob:sender];
  else if([self canDownloadAgain:job]) [self againQueueJob:sender]; else [self retryQueueJob:sender];
}
- (void)removeDownload:(id)sender;
{ (void)sender; [self confirmJob:mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow] remove:YES]; }
- (void)removeJob:(id)sender; { (void)sender; [self confirmJob:[self selectedJob] remove:YES]; }
- (void)removePlaylist:(id)sender;
{
  (void)sender; NSDictionary *playlist=[self contextPlaylist]; if(![self canRemovePlaylist:playlist]) return;
  [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:@"removePlaylist",@"operation",playlist,@"playlist",nil] title:[NSString stringWithFormat:@"Remove ‘%@’ from the library?",[playlist objectForKey:@"title"]] detail:@"Remove local playlist metadata and remaining partial files. This does not delete the playlist from YouTube." action:@"Remove Playlist"];
}
- (void)playTargetVideo:(id)sender;
{ (void)sender; NSDictionary *job=[self targetJob]; if([self playable:job]) RDOpenDefaultApplication([library_ fileForJob:job]); }
- (void)playTargetPlaylist:(id)sender;
{ (void)sender; NSString *path=[self playFileForPlaylist:[self contextPlaylist]]; if(path) RDOpenDefaultApplication(path); }
- (void)playVideoInVLC:(id)sender;
{ (void)sender; NSDictionary *job=[self targetJob]; if([self playable:job]) RDOpenInVLC([library_ fileForJob:job]); }
- (void)playPlaylistInVLC:(id)sender;
{ (void)sender; RDOpenInVLC([self playFileForPlaylist:[self contextPlaylist]]); }
- (void)revealTarget:(id)sender;
{ (void)sender; NSDictionary *job=[self targetJob]; if([self playable:job]) RDRevealInFinder([library_ fileForJob:job]); }
- (void)revealPlaylistFolder:(id)sender;
{ (void)sender; NSString *path=[self targetPlaylistFolder]; if(path) RDRevealInFinder(path); }
- (void)openDownloadsFolder:(id)sender;
{ (void)sender; [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:[library_ downloadsDirectory]]]; }
- (void)openVideo:(id)sender;
{ (void)sender; NSDictionary *job=mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow]; if([self playable:job]) RDOpenDefaultApplication([library_ fileForJob:job]); }
- (void)openJob:(id)sender;
{ (void)sender; if([self playable:[self selectedJob]]) RDOpenDefaultApplication([library_ fileForJob:[self selectedJob]]); }
- (void)playPlaylist:(id)sender;
{ (void)sender; NSString *path=[self playFileForPlaylist:[self selectedPlaylist]]; if(path) RDOpenDefaultApplication(path); }
@end
