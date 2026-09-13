#import "LibraryWindow.h"
#import "XPAppKit.h"
#import "RDToolbarButton.h"
#import <AIFontAwesome.h>
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
  [column setWidth:240]; [column setEditable:NO]; [outline addTableColumn:column];
  [outline setOutlineTableColumn:column]; [outline setHeaderView:nil];
  [outline setAllowsMultipleSelection:NO]; [outline setDataSource:owner]; [outline setDelegate:owner];
  [scroll setDocumentView:outline]; [scroll setHasVerticalScroller:YES]; [scroll setHasHorizontalScroller:YES];
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
/* Match ENIL's standard toolbar items: a 24pt glyph in the native 32pt
   image slot. AIFontAwesome marks images as templates where supported. */
static NSImage *toolbarIcon(AIFontAwesomeIcon icon,NSWindow *window) {
  static NSMutableDictionary *cache=nil;
  if(!cache) cache=[[NSMutableDictionary alloc] init];
  CGFloat scale=RDWindowBackingScale(window);
  NSString *key=[NSString stringWithFormat:@"%u:%g",(unsigned int)icon,(double)scale];
  NSImage *image=[cache objectForKey:key];
  if(!image) {
    image=[AIFontAwesome imageForIcon:icon style:AIFontAwesomeStyleSolid iconSize:24.0 canvasSize:32.0 scale:scale];
    if(image) [cache setObject:image forKey:key];
  }
  return image;
}
static BOOL stateIs(NSDictionary *job,NSString *state) { return [[job objectForKey:@"state"] isEqualToString:state]; }
static BOOL retryable(NSDictionary *job) {
  return stateIs(job,@"failed") || stateIs(job,@"cancelled") || stateIs(job,@"interrupted") || stateIs(job,@"removed");
}
static void restoreSelection(NSTableView *view,NSArray *rows,NSString *key,NSString *value) {
  unsigned int i; [view deselectAll:nil];
  for(i=0;value && i<[rows count];++i) if([[[rows objectAtIndex:i] objectForKey:key] isEqualToString:value]) {
    [view selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO]; break;
  }
}
static void menuItem(NSMenu *menu,NSString *title,SEL action,id target) {
  [[menu addItemWithTitle:title action:action keyEquivalent:@""] setTarget:target];
}
static NSPopUpButton *actions(NSView *view,NSString *title,NSRect frame) {
  NSPopUpButton *popup=[[[NSPopUpButton alloc] initWithFrame:frame pullsDown:YES] autorelease];
  [popup addItemWithTitle:title]; if(view) [view addSubview:popup]; return popup;
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
- (NSDictionary *)selectedJob;
- (NSDictionary *)selectedPlaylist;
- (NSDictionary *)jobForEntry:(NSDictionary *)entry;
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
- (void)pause:(id)sender;
- (void)pauseQueue:(id)sender;
- (void)resumeQueue:(id)sender;
- (void)toggleDownloads:(id)sender;
- (void)togglePlaylists:(id)sender;
- (void)showQueue:(id)sender;
- (void)hideQueue:(id)sender;
- (void)revealDownloads;
- (void)showJobInQueue:(NSDictionary *)job;
- (void)showTargetInQueue:(id)sender;
- (void)primaryAction:(id)sender;
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
  title_=field(detail,NSMakeRect(10,568,320,24),NO); [title_ setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];
  NSPopUpButton *playlistActions=actions(detail,@"Actions",NSMakeRect(400,565,130,28));
  [playlistActions setAutoresizingMask:NSViewMinXMargin|NSViewMinYMargin];
  menuItem([playlistActions menu],@"Play Playlist",@selector(playPlaylist:),self);
  menuItem([playlistActions menu],@"Delete Download…",@selector(removeDownload:),self);
  menuItem([playlistActions menu],@"Remove Playlist…",@selector(removePlaylist:),self);
  table_=table(detail,NSMakeRect(10,74,520,481),self,[NSArray arrayWithObjects:@"title",@"quality",@"state",nil],[NSArray arrayWithObjects:@"Video",@"Quality",@"Status",nil]);
  [table_ setTarget:self]; [table_ setDoubleAction:@selector(openVideo:)];
  downloadFormat_=[[RetroDLPLibrary preferredFormat] copy];
  primary_=button(detail,@"Show in Queue",@selector(primaryAction:),self,NSMakeRect(365,38,165,28));
  [primary_ setAutoresizingMask:NSViewMinXMargin];
  status_=field(detail,NSMakeRect(10,5,520,28),NO); [status_ setAutoresizingMask:NSViewWidthSizable];
  [middle setView:detail]; [self setDetailViewController:middle];
  AIViewController *inspector=[[[AIViewController alloc] init] autorelease];
  NSView *queue=[[[RDLayoutView alloc] initWithFrame:NSMakeRect(0,0,300,600)] autorelease];
  queueTitle_=field(queue,NSMakeRect(10,568,280,24),NO); [queueTitle_ setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];
  queue_=table(queue,NSMakeRect(10,144,280,411),self,[NSArray arrayWithObject:@"summary"],[NSArray arrayWithObject:@"Downloads"]);
  [queue_ setHeaderView:nil]; [queue_ setRowHeight:58];
  [[[queue_ tableColumns] objectAtIndex:0] setWidth:280];
  [[[[queue_ tableColumns] objectAtIndex:0] dataCell] setWraps:YES];
  pause_=button(queue,@"Resume Queue",@selector(pause:),self,NSMakeRect(10,104,135,28));
  jobAction_=button(queue,@"Download Video",@selector(jobAction:),self,NSMakeRect(150,104,140,28));
  [jobAction_ setAutoresizingMask:NSViewMinXMargin];
  NSMenu *jobMenu=[[[NSMenu alloc] initWithTitle:@"Queue Actions"] autorelease];
  menuItem(jobMenu,@"Play",@selector(openJob:),self);
  menuItem(jobMenu,@"Delete Download…",@selector(removeJob:),self);
  [queue_ setMenu:jobMenu]; [queue_ setTarget:self]; [queue_ setDoubleAction:@selector(openJob:)];
  queueStatus_=field(queue,NSMakeRect(10,5,280,94),NO); [queueStatus_ setAutoresizingMask:NSViewWidthSizable];
  [inspector setView:queue]; [self setInspectorViewController:inspector];
  [self setSidebarWidthLimits:AIMinMidMaxMake(150,200,260)];
  [self setInspectorWidthLimits:AIMinMidMaxMake(300,320,400)];
  [self setSplitViewAutosaveName:@"RetroDLPThreePaneDividers"];
  [[self window] setContentSize:NSMakeSize(1100,600)]; [[self window] setMinSize:NSMakeSize(1000,480)]; [[self window] center];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RetroDLPLibraryDidChange object:library_];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
  [self refresh:nil]; return self;
}
- (void)windowDidLoad;
{
  [super windowDidLoad];
  NSToolbar *toolbar=[[[NSToolbar alloc] initWithIdentifier:@"RetroDLPLibraryToolbar"] autorelease];
  [toolbar setDelegate:(id)self]; [toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
  [toolbar setSizeMode:NSToolbarSizeModeRegular];
  [[self window] setToolbar:toolbar]; RDUseExpandedToolbar([self window]);
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
  NSArray *labels=[NSArray arrayWithObjects:@"Download",@"Play",@"Cookies",@"Queue (0)",nil];
  AIFontAwesomeIcon icons[]={AIFADownload,AIFAPlay,AIFACookieBite,AIFAListUl};
  NSToolbarItem *item=[[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
  RDToolbarButton *view=[[[RDToolbarButton alloc] initWithFrame:NSMakeRect(0,0,40,32)] autorelease];
  [view setTitle:[labels objectAtIndex:index]]; [view setTag:(NSInteger)index];
  [view setImage:toolbarIcon(icons[index],[self window])];
  [view setCaretImage:[AIFontAwesome imageForIcon:AIFACaretDown style:AIFontAwesomeStyleSolid iconSize:8 canvasSize:10 scale:RDWindowBackingScale([self window])]];
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
    menuItem(menu,@"Pause Queue",@selector(pauseQueue:),self);
    menuItem(menu,@"Resume Queue…",@selector(resumeQueue:),self);
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
{ return [self hasTargetVideo]?[self targetPlaylist]:(context_==2?nil:[self selectedPlaylist]); }
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
  [addSheet_ release]; [downloadSheet_ release]; [downloadRequest_ release]; [downloadFormat_ release];  [toolbarItems_ release]; [confirmation_ release]; [confirmationRequest_ release]; [super dealloc];
}
- (NSDictionary *)selectedRow;
{ NSInteger row=[table_ selectedRow]; return row>=0 && (NSUInteger)row<[rows_ count]?[rows_ objectAtIndex:(NSUInteger)row]:nil; }
- (NSDictionary *)selectedJob;
{ NSInteger row=[queue_ selectedRow]; return row>=0 && (NSUInteger)row<[jobs_ count]?[jobs_ objectAtIndex:(NSUInteger)row]:nil; }
- (NSDictionary *)selectedPlaylist;
{ unsigned int i; for(i=0;i<[playlists_ count];++i) if([[[playlists_ objectAtIndex:i] objectForKey:@"id"] isEqualToString:selectedPlaylist_]) return [playlists_ objectAtIndex:i]; return nil; }
- (NSDictionary *)jobForEntry:(NSDictionary *)entry;
{
  unsigned int i;
  for(i=0;entry && i<[jobs_ count];++i) {
    NSDictionary *job=[jobs_ objectAtIndex:i];
    if([[job objectForKey:@"playlist_id"] isEqualToString:selectedPlaylist_] &&
       [[job objectForKey:@"video_id"] isEqualToString:[entry objectForKey:@"video_id"]] &&
       [[job objectForKey:@"format"] isEqualToString:downloadFormat_]) return job;
  }
  return nil;
}
- (BOOL)playable:(NSDictionary *)job;
{ return stateIs(job,@"complete") && [[NSFileManager defaultManager] fileExistsAtPath:[library_ fileForJob:job]]; }
- (void)refresh:(id)sender;
{
  (void)sender; if(refreshing_) return; refreshing_=YES;
  NSString *key=mode_==0?@"position":@"id";
  NSString *selection=[[[self selectedRow] objectForKey:key] copy];
  NSString *queueSelection=[[[self selectedJob] objectForKey:@"id"] copy];
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
  [sidebar_ reloadData]; [table_ reloadData]; [queue_ reloadData];
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
  restoreSelection(queue_,jobs_,@"id",queueSelection);
  [selection release]; [queueSelection release]; refreshing_=NO; [self updateCustomSummary]; [self updateControls];
}
- (void)tableWasUsed:(NSTableView *)view;
{
  if(refreshing_) return;
  context_=view==sidebar_?0:(view==queue_?2:1); [self updateControls];
}
- (BOOL)hasTargetVideo;
{ return context_==2?[self selectedJob]!=nil:(context_==1 && [self selectedRow]!=nil); }
- (NSDictionary *)targetJob;
{ return context_==2?[self selectedJob]:(context_==1?(mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow]):nil); }
- (NSDictionary *)targetPlaylist;
{
  NSDictionary *job=[self targetJob];
  NSString *key=job?[job objectForKey:@"playlist_id"]:selectedPlaylist_;
  if(context_==2 && !job) return nil;
  NSEnumerator *e=[playlists_ objectEnumerator]; NSDictionary *playlist;
  while((playlist=[e nextObject])) if([[playlist objectForKey:@"id"] isEqualToString:key]) return playlist;
  return nil;
}
- (NSString *)targetVideoID;
{ return context_==2?[[self selectedJob] objectForKey:@"video_id"]:(context_==1?[[self selectedRow] objectForKey:@"video_id"]:nil); }
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
    tip=[NSString stringWithFormat:@"%@ — %@ (%@)",delete?@"Delete downloaded video…":([self canCancel:job]?@"Show in Queue":@"Download video"),job?[job objectForKey:@"title"]:[[self selectedRow] objectForKey:@"title"],[self targetFormat]];
  } else if(playlist) {
    icon=AIFAArrowsRotate;
    enabled=![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]];
    tip=[NSString stringWithFormat:@"Sync ‘%@’",[playlist objectForKey:@"title"]];
  } else { icon=(AIFontAwesomeIcon)0x2b; tip=@"Add a playlist…"; }
  [self setToolbarItem:@"download" title:delete?@"Delete":(!video && playlist?@"Sync":@"Download") tip:tip icon:toolbarIcon(icon,[self window]) enabled:enabled];
  NSString *path=[self selectionPlayFile], *application=RDDefaultApplication(path);
  NSString *object=video?@"video":@"playlist";
  NSString *playTip=path?(application?[NSString stringWithFormat:@"Play %@ in %@",object,[[[NSFileManager defaultManager] displayNameAtPath:application] stringByDeletingPathExtension]]:[NSString stringWithFormat:@"Reveal %@ in Finder",object]):@"Select a downloaded video or playlist to play";
  [self setToolbarItem:@"play" title:@"Play" tip:playTip icon:RDYouTubeIcon(RDWindowBackingScale([self window])) enabled:path!=nil];
  BOOL cookies=[[library_ cookieStatus] isEqualToString:@"Imported"];
  [self setToolbarItem:@"cookies" title:@"Cookies" tip:[[library_ cookieStatus] isEqualToString:@"Not Imported"]?@"Import cookies…":@"Replace cookies…" icon:toolbarIcon(cookies?AIFACookie:AIFACookieBite,[self window]) enabled:![library_ isBusy]];
  NSUInteger pending=[self queuedCount]; NSEnumerator *e=[jobs_ objectEnumerator];
  while((job=[e nextObject])) if(stateIs(job,@"running")) ++pending;
  [self setToolbarItem:@"downloads" title:[NSString stringWithFormat:@"Queue (%lu)",(unsigned long)pending] tip:[self isInspectorCollapsed]?@"Show Queue. Right-click for queue actions.":@"Hide Queue. Right-click for queue actions." icon:nil enabled:YES];
}
- (void)updateControls;
{
  NSDictionary *row=[self selectedRow], *job=mode_==0?[self jobForEntry:row]:row;
  BOOL showInQueue=mode_==0 && row && (stateIs(job,@"queued") || stateIs(job,@"running") || retryable(job));
  [primary_ setEnabled:showInQueue]; [primary_ setHidden:!showInQueue];
  [self updateToolbar];
  [title_ setStringValue:mode_==0?[[self selectedPlaylist] objectForKey:@"title"]:@"All Downloads"];
  [status_ setStringValue:[rows_ count]?[library_ status]:(mode_==0?@"No videos yet. Use Sync This Playlist to load its videos.":@"No completed downloads. Add or select a playlist to get started.")];
  NSDictionary *selected=[self selectedJob];
  BOOL cancellable=stateIs(selected,@"queued") || stateIs(selected,@"running");
  [jobAction_ setTitle:cancellable?@"Cancel Download…":@"Download Video"];
  [jobAction_ setEnabled:cancellable || [self canRetry:selected] || [self canDownloadAgain:selected]];
  [pause_ setTitle:[library_ isPaused]?@"Resume Queue":@"Pause Queue"];
  NSUInteger pending=0; unsigned int i;
  for(i=0;i<[jobs_ count];++i) if(stateIs([jobs_ objectAtIndex:i],@"queued") || stateIs([jobs_ objectAtIndex:i],@"running")) ++pending;
  [queueTitle_ setStringValue:[NSString stringWithFormat:@"Queue — %lu pending",(unsigned long)pending]];
  NSString *error=[selected objectForKey:@"error"];
  [queueStatus_ setStringValue:[error length]?error:([library_ isPaused]?@"Queue paused. Pausing stops active transfers; Download Video restarts them.":([jobs_ count]?[library_ status]:@"No downloads queued."))];

}
- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item;
{
  (void)outline; if(!item) return 3; if([item isEqual:@"System"]) return 1;
  NSInteger count=0; NSEnumerator *e=[playlists_ objectEnumerator]; NSDictionary *playlist;
  while((playlist=[e nextObject])) if([playlistGroup(playlist) isEqual:item]) ++count;
  return count;
}
- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item;
{
  (void)outline;
  if(!item) return [[NSArray arrayWithObjects:@"System",@"Added Playlists",@"My Playlists",nil] objectAtIndex:(NSUInteger)index];
  if([item isEqual:@"System"]) return @"All Downloads";
  NSEnumerator *e=[playlists_ objectEnumerator]; NSDictionary *playlist;
  while((playlist=[e nextObject])) if([playlistGroup(playlist) isEqual:item] && index--==0) return [sidebarItems_ objectForKey:[playlist objectForKey:@"id"]];
  return nil;
}
- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item;
{ (void)outline; return sidebarGroup(item); }
- (BOOL)outlineView:(NSOutlineView *)outline shouldSelectItem:(id)item;
{ (void)outline; return !sidebarGroup(item); }
- (id)outlineView:(NSOutlineView *)outline objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item;
{
  (void)outline; (void)column; if(sidebarGroup(item) || [item isEqual:@"All Downloads"]) return item;
  NSEnumerator *e=[playlists_ objectEnumerator]; NSDictionary *playlist;
  while((playlist=[e nextObject])) if([[playlist objectForKey:@"id"] isEqual:item]) return [NSString stringWithFormat:@"%@ (%@)",[playlist objectForKey:@"title"],[playlist objectForKey:@"count"]];
  return @"";
}
- (void)outlineView:(NSOutlineView *)outline willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column item:(id)item;
{ (void)outline; (void)column; [cell setFont:sidebarGroup(item)?[NSFont boldSystemFontOfSize:12]:[NSFont systemFontOfSize:12]]; }
- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
{ [self tableViewSelectionDidChange:notification]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)view;
{ return (NSInteger)(view==queue_?[jobs_ count]:[rows_ count]); }
- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
{
  if(view==queue_) {
    NSDictionary *job=[jobs_ objectAtIndex:(NSUInteger)row];
    return [NSString stringWithFormat:@"%@\n%@\n%@ · %@",[job objectForKey:@"title"],[job objectForKey:@"playlist_title"],[job objectForKey:@"format"],[job objectForKey:@"state"]];
  }
  NSDictionary *entry=[rows_ objectAtIndex:(NSUInteger)row]; NSString *key=[column identifier];
  NSDictionary *job=mode_==0?[self jobForEntry:entry]:entry;
  if([key isEqualToString:@"quality"]) return mode_==0?downloadFormat_:([[job objectForKey:@"actual_format"] length]?[job objectForKey:@"actual_format"]:[job objectForKey:@"format"]);
  if([key isEqualToString:@"state"]) return job?[job objectForKey:@"state"]:@"not downloaded";
  return [entry objectForKey:key];
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
  if([[self window] attachedSheet]) return NO;
  SEL action=[item action]; NSDictionary *job=[self targetJob], *playlist=[self selectedPlaylist], *queued=[self selectedJob];
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
  if(action==@selector(pauseQueue:)) return ![library_ isPaused];
  if(action==@selector(resumeQueue:)) return [library_ isPaused];
  if(action==@selector(retryQueueJob:)) return [self canRetry:queued] || [self canDownloadAgain:queued];
  if(action==@selector(againQueueJob:)) return [self canDownloadAgain:queued];
  if(action==@selector(cancelQueueJob:)) return [self canCancel:queued];
  if(action==@selector(removeJob:)) return [self canRemove:queued];
  if(action==@selector(openJob:)) return [self playable:queued] && RDDefaultApplication([library_ fileForJob:queued])!=nil;
  if(action==@selector(removeDownload:)) return [self canRemove:mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow]];
  if(action==@selector(removePlaylist:)) return [self canRemovePlaylist:[self selectedPlaylist]];
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
  } else if([op isEqualToString:@"pause"]) [library_ setPaused:YES];
  else if([op isEqualToString:@"resume"]) [library_ setPaused:NO];
  else if([op isEqualToString:@"removePlaylist"]) {
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
  NSString *detail=[NSString stringWithFormat:@"Playlist: %@\nQuality: %@\nExisting failed or cancelled jobs will not be retried.%@",[request objectForKey:@"title"]?:playlist,format,[library_ isPaused]?@"\nThe queue will remain paused.":@""];
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
{ (void)sender; NSDictionary *playlist=[self selectedPlaylist]; if(playlist) [library_ syncPlaylistInput:[playlist objectForKey:@"service_id"]]; }
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
- (void)pause:(id)sender;
{ if([library_ isPaused]) [self resumeQueue:sender]; else [self pauseQueue:sender]; }
- (void)pauseQueue:(id)sender;
{
  (void)sender; if([library_ isPaused]) return;
  NSEnumerator *e=[jobs_ objectEnumerator]; NSDictionary *job;
  while((job=[e nextObject])) if(stateIs(job,@"running")) {
    [self confirmRequest:[NSDictionary dictionaryWithObject:@"pause" forKey:@"operation"] title:@"Pause the queue and stop the active transfer?" detail:@"The active job will need an explicit retry, which restarts the transfer rather than resuming it." action:@"Pause Queue"]; return;
  }
  [library_ setPaused:YES];
}
- (void)resumeQueue:(id)sender;
{
  (void)sender; if(![library_ isPaused]) return;
  NSUInteger count=[self queuedCount];
  if(!count) { [library_ setPaused:NO]; return; }
  [self confirmRequest:[NSDictionary dictionaryWithObject:@"resume" forKey:@"operation"] title:[NSString stringWithFormat:@"Resume %lu queued downloads?",(unsigned long)count] detail:@"Queued videos will become eligible to download from YouTube. Failed and cancelled jobs still need an explicit retry." action:@"Resume Queue"];
}
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
  [self revealDownloads]; refreshing_=YES; restoreSelection(queue_,jobs_,@"id",key); refreshing_=NO;
  if([queue_ selectedRow]>=0) [queue_ scrollRowToVisible:[queue_ selectedRow]];
  [self updateControls];
}
- (void)showTargetInQueue:(id)sender; { (void)sender; [self showJobInQueue:[self targetJob]]; }
- (void)primaryAction:(id)sender;
{ (void)sender; [self showJobInQueue:mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow]]; }
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
  (void)sender; NSDictionary *playlist=[self selectedPlaylist]; if(![self canRemovePlaylist:playlist]) return;
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
