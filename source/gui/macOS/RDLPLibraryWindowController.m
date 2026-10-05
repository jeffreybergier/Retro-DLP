#import "RDLPDownloadSections.h"
#import "RDLP_Foundation.h"
#import "RDLPLibraryWindowController.h"
#import "RDLPQueueWindowController.h"
#import "RDLPAppKit.h"
#import "RDLPToolbarButton.h"
#import <AIFontAwesome.h>
#import "RDLPLibraryViews.h"
#import "RDLPDownloadPolicy.h"
#import "RDLPVideoRows.h"
#import "RDLPLibraryMenus.h"
/* Declarations for runtime-guarded APIs absent from the Tiger SDK. */
@interface NSWindow (RDLPStatusBarCompatibility)
- (void)setAutorecalculatesContentBorderThickness:(BOOL)flag forEdge:(NSRectEdge)edge;
- (void)setContentBorderThickness:(CGFloat)thickness forEdge:(NSRectEdge)edge;
- (void)setCollectionBehavior:(NSUInteger)behavior;
@end

static const CGFloat RDLPStatusBarHeight=32.0;

@interface RDLPLibraryWindowController (Private)
- (id)initWithLibrary:(RDLPLibrary *)library;
- (void)windowDidLoad;
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)insert;
- (void)toolbarWillAddItem:(NSNotification *)notification;
- (void)toolbarDidRemoveItem:(NSNotification *)notification;
- (void)customizeToolbar:(id)sender;
- (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier;
- (void)menuNeedsUpdate:(NSMenu *)menu;
- (NSDictionary *)contextPlaylist;
- (NSString *)selectionPlayFile;
- (void)playSelection:(id)sender;
- (void)chooseVideoPlayer:(NSMenuItem *)sender;
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
- (void)showQueueError:(id)sender;
- (NSDictionary *)selectedJob;
- (NSDictionary *)selectedPlaylist;
- (NSDictionary *)jobForEntry:(NSDictionary *)entry;
- (NSString *)statusForJob:(NSDictionary *)job;
- (NSString *)queueStatusForJob:(NSDictionary *)job;
- (BOOL)playable:(NSDictionary *)job;
- (void)refresh:(id)sender;
- (void)tableWasUsed:(NSTableView *)view;
- (BOOL)hasTargetVideo;
- (BOOL)hasMultipleTargetVideos;
- (NSArray *)selectedRequestsForRemoval:(BOOL)remove firstOnly:(BOOL)firstOnly;
- (void)updateBulkAvailability;
- (void)downloadSelectedVideos;
- (void)removeSelectedVideos;
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
- (NSArray *)syncPlan;
- (NSUInteger)queuedCount;
- (void)setToolbarItem:(NSString *)key title:(NSString *)title tip:(NSString *)tip icon:(NSImage *)icon enabled:(BOOL)enabled;
- (void)updateToolbar;
- (void)refreshIconScale:(NSNotification *)notification;
- (void)refreshStatus:(id)sender;
- (void)updateControls;
- (NSInteger)numberOfRowsInTableView:(NSTableView *)view;
- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
- (BOOL)validateToolbarItem:(NSToolbarItem *)item;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)addPlaylist:(id)sender;
- (void)addVideo:(id)sender;
- (void)dismissAdd:(id)sender;
- (void)addSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code contextInfo:(void *)context;
- (void)confirmRequest:(NSDictionary *)request title:(NSString *)title detail:(NSString *)detail action:(NSString *)action;
- (void)confirmationDidEnd:(NSAlert *)alert returnCode:(NSInteger)code contextInfo:(void *)context;
- (void)performConfirmed:(NSDictionary *)request;
- (void)confirmJob:(NSDictionary *)job remove:(BOOL)remove;
- (BOOL)canRemovePlaylist:(NSDictionary *)playlist;
- (void)retryDownloadJob:(NSDictionary *)job;
- (void)enqueueSingle:(NSDictionary *)request allowRetry:(BOOL)allowRetry;
- (void)enqueueRequest:(NSDictionary *)request;
- (void)downloadSelectedVideo:(id)sender;
- (void)sync:(id)sender;
- (void)syncAll:(id)sender;
- (void)discover:(id)sender;
- (void)openCookieExportGuide:(id)sender;
- (void)importCookies:(id)sender;
- (void)replaceCookies:(id)sender;
- (void)clearCookies:(id)sender;
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
@implementation RDLPLibraryWindowController
- (id)initWithLibrary:(RDLPLibrary *)library;
{
  self=[super initWithWindowNibName:@"RetroDLPLibraryWindow"]; if(!self) return nil;
  library_=[library retain]; downloadPolicy_=[[RDLPDownloadPolicy alloc] initWithLibrary:library]; mode_=1;
  split_=[[RDLPLibrarySplitView alloc] initWithFrame:NSMakeRect(0,0,800,600)];
  [split_ setVertical:YES]; [split_ setDelegate:(id)self];
  sidebarWidth_=[[NSUserDefaults standardUserDefaults] floatForKey:@"RetroDLPLibrarySidebarWidth"];
  if(sidebarWidth_<150 || sidebarWidth_>260) sidebarWidth_=200;
  NSView *sidebar=[[[RDLPLayoutView alloc] initWithFrame:NSMakeRect(0,0,200,600)] autorelease];
  sidebarItems_=[[NSMutableDictionary alloc] init];
  sidebar_=[RDLPLibraryViews sidebarInView:sidebar owner:self];
  [split_ addSubview:sidebar];
  NSView *detail=[[[RDLPLayoutView alloc] initWithFrame:NSMakeRect(0,0,540,600)] autorelease];
  table_=[RDLPLibraryViews tableInView:detail frame:[detail bounds] owner:self
    names:[NSArray arrayWithObjects:@"state",@"size",@"quality",@"title",@"channel",nil]
    labels:[NSArray arrayWithObjects:@"",NSLocalizedString(@"Size", nil),NSLocalizedString(@"Quality", nil),NSLocalizedString(@"Video", nil),NSLocalizedString(@"Channel", nil),nil]];
  NSTableColumn *stateColumn=[table_ tableColumnWithIdentifier:@"state"];
  [stateColumn setMinWidth:24]; [stateColumn setMaxWidth:24]; [stateColumn setWidth:24];
  [stateColumn setResizingMask:NSTableColumnNoResizing];
  [stateColumn setDataCell:[[[RDLPStatusCell alloc] initImageCell:nil] autorelease]];
  NSTableColumn *sizeColumn=[table_ tableColumnWithIdentifier:@"size"];
  [sizeColumn setMinWidth:48]; [sizeColumn setWidth:48];
  [sizeColumn setResizingMask:NSTableColumnUserResizingMask];
  [[sizeColumn dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
  [[sizeColumn dataCell] setAlignment:RDLPTextAlignmentRight];
  NSArray *videoTextColumns=[NSArray arrayWithObjects:@"quality",@"title",@"channel",nil];
  CGFloat widths[]={48,240,140}, minimums[]={48,120,80};
  NSUInteger videoColumnIndex;
  for(videoColumnIndex=0;videoColumnIndex<[videoTextColumns count];++videoColumnIndex) {
    NSTableColumn *column=[table_ tableColumnWithIdentifier:[videoTextColumns objectAtIndex:videoColumnIndex]];
    [column setWidth:widths[videoColumnIndex]]; [column setMinWidth:minimums[videoColumnIndex]];
    [column setResizingMask:NSTableColumnUserResizingMask];
    [[column dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
  }
  [table_ setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
  [table_ setAllowsColumnReordering:NO];
  [table_ setAllowsMultipleSelection:YES];
  [[table_ enclosingScrollView] setHasHorizontalScroller:YES];
  [[table_ enclosingScrollView] setAutohidesScrollers:YES];
  [[table_ enclosingScrollView] setBorderType:NSNoBorder];
  [table_ setTarget:self]; [table_ setDoubleAction:@selector(openVideo:)];
  NSMenu *videoMenu=[[[NSMenu alloc] initWithTitle:@"videos"] autorelease];
  [videoMenu setDelegate:(id)self];
  [RDLPLibraryMenus addItemToMenu:videoMenu title:NSLocalizedString(@"Download Video", nil) action:@selector(chooseDownload:) target:self];
  [RDLPLibraryMenus addItemToMenu:videoMenu title:NSLocalizedString(@"Delete Download…", nil) action:@selector(removeTarget:) target:self];
  [table_ setMenu:videoMenu];
  downloadFormat_=[[RDLPLibrary preferredFormat] copy];
  [split_ addSubview:detail];
  queueWindow_=[[RDLPQueueWindowController alloc] initWithLibrary:library_ owner:self];
  queue_=[queueWindow_ tableView];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(queueWindowClosed:)
    name:NSWindowWillCloseNotification object:[queueWindow_ window]];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowBecameKey:)
    name:NSWindowDidBecomeKeyNotification object:[queueWindow_ window]];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RDLPLibraryDidChange object:library_];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadDateChanged:) name:RDLPDateBoundariesDidChange object:nil];
  [NSCalendar RDLP_monitorDateBoundaries];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshStatus:) name:RDLPLibraryStatusDidChange object:library_];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
  [self refresh:nil]; return self;
}
- (NSSplitView *)AI_splitView; { return split_; }
- (BOOL)isSidebarCollapsed; { return sidebarCollapsed_; }
- (void)toggleSidebar:(id)sender;
{
  (void)sender; sidebarCollapsed_=!sidebarCollapsed_;
  [[[split_ subviews] objectAtIndex:0] setHidden:sidebarCollapsed_];
  [self splitView:split_ resizeSubviewsWithOldSize:[split_ bounds].size];
}
- (void)splitView:(NSSplitView *)split resizeSubviewsWithOldSize:(NSSize)oldSize;
{
  (void)oldSize; if([[split subviews] count]!=2) return;
  NSRect bounds=[split bounds]; CGFloat width=sidebarCollapsed_?0:MIN(sidebarWidth_,MAX(0,bounds.size.width-320));
  CGFloat divider=sidebarCollapsed_?0:[split dividerThickness];
  [[[split subviews] objectAtIndex:0] setFrame:NSMakeRect(0,0,width,bounds.size.height)];
  [[[split subviews] objectAtIndex:1] setFrame:NSMakeRect(width+divider,0,MAX(0,bounds.size.width-width-divider),bounds.size.height)];
}
- (CGFloat)splitView:(NSSplitView *)split constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index;
{ (void)split; (void)proposed; (void)index; return 150; }
- (CGFloat)splitView:(NSSplitView *)split constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index;
{ (void)proposed; (void)index; return MIN(260,NSWidth([split bounds])-320); }
- (void)splitViewDidResizeSubviews:(NSNotification *)notification;
{
  (void)notification; if(sidebarCollapsed_ || ![[split_ subviews] count]) return;
  CGFloat width=NSWidth([[[split_ subviews] objectAtIndex:0] frame]);
  if(width>=150 && width<=260) {
    sidebarWidth_=width; [[NSUserDefaults standardUserDefaults] setFloat:width forKey:@"RetroDLPLibrarySidebarWidth"];
  }
}
- (BOOL)hasAttachedSheet;
{ return [[self window] attachedSheet]!=nil || [[queueWindow_ window] attachedSheet]!=nil; }
- (NSWindow *)actionWindow;
{ return context_==2 && [[queueWindow_ window] isVisible]?[queueWindow_ window]:[self window]; }
- (void)windowBecameKey:(NSNotification *)notification;
{
  context_=[notification object]==[queueWindow_ window]?2:libraryContext_;
  [self updateControls];
}
- (void)queueWindowClosed:(NSNotification *)notification;
{ (void)notification; context_=libraryContext_; [self updateControls]; }
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
  NSWindow *window=[[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,800,600)
    styleMask:RDLPTexturedWindowStyleMask backing:NSBackingStoreBuffered defer:NO] autorelease];
  [window setTitle:NSLocalizedString(@"RetroDLP", nil)]; [window setReleasedWhenClosed:NO];
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
  /* String name keeps the 10.4 SDK path free of the 10.7+ constant. */
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshIconScale:)
    name:@"NSWindowDidChangeBackingPropertiesNotification" object:window];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshIconScale:)
    name:NSWindowDidChangeScreenNotification object:window];
  NSRect frame=[window frame];
  NSSplitView *split=[self AI_splitView];
  NSRect bounds=[[window contentView] bounds];
  NSView *root=[[[RDLPLayoutView alloc] initWithFrame:bounds] autorelease];
  [root setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  [window setContentView:root];
  [split removeFromSuperview];
  [split setFrame:NSMakeRect(0,RDLPStatusBarHeight,bounds.size.width,
                            MAX(0,bounds.size.height-RDLPStatusBarHeight))];
  [split setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  [root addSubview:split]; [self splitView:split resizeSubviewsWithOldSize:NSZeroSize];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowBecameKey:)
    name:NSWindowDidBecomeKeyNotification object:window];
  status_=[RDLPLibraryViews fieldInView:root frame:NSMakeRect(12,7,MAX(0,bounds.size.width-190),18) editable:NO];
  [status_ setAutoresizingMask:NSViewWidthSizable];
  queueProgress_=[[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(bounds.size.width-160,10,140,12)] autorelease];
  [queueProgress_ setIndeterminate:NO]; [queueProgress_ setMinValue:0]; [queueProgress_ setHidden:YES];
  [queueProgress_ setAutoresizingMask:NSViewMinXMargin]; [root addSubview:queueProgress_];
  [[status_ cell] setLineBreakMode:NSLineBreakByTruncatingTail];
  if([window respondsToSelector:@selector(setContentBorderThickness:forEdge:)]) {
    [window setAutorecalculatesContentBorderThickness:NO forEdge:NSMinYEdge];
    [window setContentBorderThickness:RDLPStatusBarHeight forEdge:NSMinYEdge];
  }
  [window setFrame:frame display:NO];
  NSToolbar *toolbar=[[[NSToolbar alloc] initWithIdentifier:@"RetroDLPLibraryToolbar"] autorelease];
  [toolbar setDelegate:(id)self]; [toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
  [toolbar setSizeMode:NSToolbarSizeModeRegular];
  [toolbar setAllowsUserCustomization:YES]; [toolbar setAutosavesConfiguration:YES];
  [[self window] setToolbar:toolbar]; [RDLPAppKit useExpandedToolbar:[self window]];
  /* Toolbar installation changes frame constraints on Tiger. Keep outer sizes. */
  [window setMinSize:NSMakeSize(640,480)];
  [window setFrame:frame display:NO];
}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
{ (void)toolbar; return [NSArray arrayWithObjects:@"library",@"download",@"play",@"remove",NSToolbarFlexibleSpaceItemIdentifier,@"cookies",@"downloads",nil]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
{ (void)toolbar; return [NSArray arrayWithObjects:@"library",@"download",@"play",@"remove",@"cookies",@"downloads",NSToolbarSpaceItemIdentifier,NSToolbarFlexibleSpaceItemIdentifier,NSToolbarSeparatorItemIdentifier,nil]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)insert;
{
  (void)toolbar; (void)insert;
  NSArray *ids=[NSArray arrayWithObjects:@"library",@"play",@"cookies",@"downloads",@"download",@"remove",nil];
  NSUInteger index=[ids indexOfObject:identifier]; if(index==NSNotFound) return nil;
  NSArray *labels=[NSArray arrayWithObjects:NSLocalizedString(@"Library", nil),NSLocalizedString(@"Play", nil),NSLocalizedString(@"Cookies", nil),NSLocalizedString(@"Queue", nil),NSLocalizedString(@"Download", nil),NSLocalizedString(@"Remove", nil),nil];
  NSArray *icons=[NSArray arrayWithObjects:[NSNumber numberWithInt:0x2b],
    [NSNumber numberWithInt:AIFAPlay],[NSNumber numberWithInt:AIFACookie],
    [NSNumber numberWithInt:AIFAListCheck],[NSNumber numberWithInt:AIFADownload],[NSNumber numberWithInt:AIFATrash],nil];
  NSToolbarItem *item=[[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
  RDLPToolbarButton *view=[[[RDLPToolbarButton alloc] initWithFrame:NSMakeRect(0,0,40,32)] autorelease];
  [view setTitle:[labels objectAtIndex:index]]; [view setTag:(NSInteger)index];
  [view setImage:[RDLPLibraryViews toolbarIcon:(AIFontAwesomeIcon)[[icons objectAtIndex:index] intValue] window:[self window]]];
  [view setCaretImage:[RDLPAppKit controlIcon:AIFACaretDown style:AIFontAwesomeStyleSolid iconSize:8 canvasSize:10 scale:[RDLPAppKit backingScaleForWindow:[self window]]]];
  [view setTarget:self]; [view setAction:@selector(toolbarDefault:)];
  if(![identifier isEqualToString:@"downloads"]) [view setMenu:[self menuForToolbarIdentifier:identifier]];
  [item setLabel:[labels objectAtIndex:index]]; [item setPaletteLabel:[labels objectAtIndex:index]];
  [item setView:view]; [item setMinSize:NSMakeSize(40,32)]; [item setMaxSize:NSMakeSize(40,32)];
  [item setTarget:self]; [item setAction:@selector(toolbarDefault:)]; [item setTag:(NSInteger)index];
  if([identifier isEqualToString:@"library"] || [identifier isEqualToString:@"cookies"]) {
    [view setTarget:view]; [view setAction:@selector(showOptions:)];
    [item setTarget:view]; [item setAction:@selector(showOptions:)];
  }
  [item setAutovalidates:NO];
  return item;
}
- (void)toolbarWillAddItem:(NSNotification *)notification;
{
  NSToolbarItem *item=[[notification userInfo] objectForKey:@"item"];
  if(![[item view] isKindOfClass:[RDLPToolbarButton class]]) return;
  RDLPToolbarButton *view=(RDLPToolbarButton *)[item view];
  if([view action]==@selector(showOptions:)) {
    /* A customization-palette copy must open the installed view's menu. */
    [view setTarget:view]; [item setTarget:view];
  }
  if(!toolbarItems_) toolbarItems_=[[NSMutableDictionary alloc] init];
  [toolbarItems_ setObject:item forKey:[item itemIdentifier]];
  [self updateToolbar];
}
- (void)toolbarDidRemoveItem:(NSNotification *)notification;
{
  NSToolbarItem *item=[[notification userInfo] objectForKey:@"item"];
  if([toolbarItems_ objectForKey:[item itemIdentifier]]==item)
    [toolbarItems_ removeObjectForKey:[item itemIdentifier]];
}
- (void)customizeToolbar:(id)sender;
{
  if([self hasAttachedSheet]) return;
  [[self window] makeKeyAndOrderFront:sender];
  [[[self window] toolbar] runCustomizationPalette:sender];
}
/* Menu-bar commands keep stable positions; toolbar menus remain task-oriented. */
- (NSMenu *)menuForMenuBarTitle:(NSString *)title;
{ return [RDLPLibraryMenus menuForMenuBarTitle:title target:self]; }
- (void)downloadFromMenu:(NSMenuItem *)sender;
{
  if(![self validateMenuItem:sender]) return;
  if(context_==2 && [self selectedJob]) { [self retryQueueJob:sender]; return; }
  NSMenuItem *command=[[[NSMenuItem alloc] initWithTitle:@"" action:@selector(chooseDownload:) keyEquivalent:@""] autorelease];
  [command setTag:0]; [self chooseDownload:command];
}
- (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier;
{ return [RDLPLibraryMenus menuForToolbarIdentifier:identifier target:self]; }
- (void)menuNeedsUpdate:(NSMenu *)menu;
{
  /* These menus belong to the library toolbar, even when opened by a
     secondary click while the queue window is key. */
  [[self window] makeKeyAndOrderFront:nil]; context_=libraryContext_;
  [RDLPLibraryMenus updateMenu:menu target:self];
}
- (NSDictionary *)contextPlaylist;
{
  if([self hasMultipleTargetVideos]) return mode_==0?[self selectedPlaylist]:nil;
  return [self hasTargetVideo]?[self targetPlaylist]:(context_==2?[self targetPlaylist]:[self selectedPlaylist]);
}
- (NSString *)selectionPlayFile;
{ return [self hasMultipleTargetVideos]?nil:([self hasTargetVideo]?([self playable:[self targetJob]]?[library_ fileForJob:[self targetJob]]:nil):[self playFileForPlaylist:[self contextPlaylist]]); }
- (void)playSelection:(id)sender;
{
  NSString *path=[self selectionPlayFile]; if(!path) return;
  (void)sender;
  if([RDLPAppKit preferredPlaybackApplication:path]) [RDLPAppKit openPreferredPlayback:path];
}
- (void)chooseVideoPlayer:(NSMenuItem *)sender;
{
  if(![self validateMenuItem:sender]) return;
  [RDLPAppKit saveVideoPlayer:[sender representedObject]];
  [self updateControls];
}
- (void)revealSelection:(id)sender;
{ if([self hasTargetVideo]) [self revealTarget:sender]; else if([self contextPlaylist]) [self revealPlaylistFolder:sender]; }
- (void)toolbarDefault:(id)sender;
{
  if([self hasAttachedSheet]) return;
  if([sender isKindOfClass:[NSToolbarItem class]] && ![(RDLPToolbarButton *)[(NSToolbarItem *)sender view] isDefaultEnabled]) return;
  [[self window] makeKeyAndOrderFront:sender]; context_=libraryContext_;
  switch([sender tag]) {
    case 1: [self playSelection:sender]; break;
    case 3: [self showQueue:sender]; break;
    case 4: [self downloadSelectedVideo:sender]; break;
    case 5: if([self hasTargetVideo]) [self removeTarget:sender]; else [self removePlaylist:sender]; break;
  }
}
- (void)chooseDownload:(NSMenuItem *)sender;
{
  if(![self validateMenuItem:sender] || downloadSheet_) return;
  NSUInteger index=(NSUInteger)[sender tag];
  if(index>0 && index<4) { [self saveDownloadQuality:[[RDLPLibrary qualityFormats] objectAtIndex:index-1]]; return; }
  if(index==0) {
    if([self hasMultipleTargetVideos]) { [self downloadSelectedVideos]; return; }
    NSDictionary *playlist=[self contextPlaylist];
    NSMutableDictionary *request=[NSMutableDictionary dictionaryWithObjectsAndKeys:[playlist objectForKey:@"id"],@"playlist",[playlist objectForKey:@"title"],@"title",downloadFormat_,@"format",nil];
    [request setObject:[self targetVideoID] forKey:@"video"];
    [self enqueueRequest:request]; return;
  }
  downloadSheet_=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,500,220) styleMask:AIWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [downloadSheet_ setTitle:NSLocalizedString(@"Custom Download Quality", nil)];
  NSView *view=[downloadSheet_ contentView];
  [[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,182,460,28) editable:NO] setStringValue:NSLocalizedString(@"Choose the quality for future downloads.", nil)];
  customSummary_=[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,146,460,32) editable:NO];
  [[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,115,460,24) editable:NO] setStringValue:NSLocalizedString(@"Format expression (for example, 18 or 136+140)", nil)];
  customFormat_=[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,83,460,24) editable:YES]; [customFormat_ setStringValue:downloadFormat_]; [customFormat_ setDelegate:(id)self];
  customError_=[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,47,460,28) editable:NO];
  NSButton *cancel=[RDLPLibraryViews buttonInView:view title:NSLocalizedString(@"Cancel", nil) action:@selector(dismissDownload:) target:self frame:NSMakeRect(240,10,105,28)]; [cancel setTag:0]; [cancel setKeyEquivalent:@"\033"];
  NSButton *download=[RDLPLibraryViews buttonInView:view title:NSLocalizedString(@"Save", nil) action:@selector(dismissDownload:) target:self frame:NSMakeRect(350,10,130,28)]; [download setTag:1]; [download setKeyEquivalent:@"\r"];
  [self updateCustomSummary];
  [RDLPAppKit beginSheet:downloadSheet_ forWindow:[self actionWindow] delegate:self didEnd:@selector(downloadSheetDidEnd:returnCode:contextInfo:)];
  [downloadSheet_ makeFirstResponder:customFormat_];
}
- (void)saveDownloadQuality:(NSString *)format;
{
  if(![RDLPLibrary savePreferredFormat:format]) return;
  [downloadFormat_ release]; downloadFormat_=[format copy]; [self refresh:nil];
}
- (void)updateCustomSummary;
{
  if(downloadSheet_) [customSummary_ setStringValue:NSLocalizedString(@"Saving this quality does not start a download.", nil)];
}
- (void)controlTextDidChange:(NSNotification *)notification;
{ if([notification object]==customFormat_) { [customError_ setStringValue:@""]; [self updateCustomSummary]; } }
- (void)dismissDownload:(id)sender;
{
  if([sender tag]) {
    NSString *format=[customFormat_ stringValue];
    if(![RDLPLibrary validFormat:format]) { [customError_ setStringValue:NSLocalizedString(@"Enter a valid format such as 18 or 136+140.", nil)]; return; }
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
  [sidebar_ setDelegate:nil]; [sidebar_ setDataSource:nil];
  [table_ setDelegate:nil]; [table_ setDataSource:nil];
  [split_ setDelegate:nil]; [split_ release]; [queueWindow_ close]; [queueWindow_ release];
  [sidebarItems_ release]; [downloadPolicy_ release]; [library_ release]; [playlists_ release]; [rows_ release]; [videoRows_ release]; [addedPlaylists_ release]; [accountPlaylists_ release]; [unsupportedPlaylists_ release]; [adhocPlaylist_ release]; [selectedPlaylist_ release];
  [addSheet_ release]; [downloadSheet_ release]; [downloadRequest_ release]; [downloadFormat_ release]; [queueRows_ release]; [queueStatusCache_ release]; [toolbarItems_ release]; [confirmation_ release]; [confirmationRequest_ release]; [super dealloc];
}
- (NSDictionary *)selectedRow;
{ NSInteger row=[table_ selectedRow];
  NSDictionary *entry=row>=0 && (NSUInteger)row<[rows_ count]?[rows_ objectAtIndex:(NSUInteger)row]:nil;
  return [[entry objectForKey:@"action"] isEqualToString:@"section"]?nil:entry;
}
- (NSDictionary *)selectedJob;
{ NSInteger row=[queue_ selectedRow]; return row>=0 && (NSUInteger)row<[queueRows_ count]?[queueRows_ objectAtIndex:(NSUInteger)row]:nil; }

- (NSDictionary *)selectedPlaylist;
{ return [(RDLPLibraryRows *)playlists_ playlistForID:selectedPlaylist_]; }
- (NSDictionary *)jobForEntry:(NSDictionary *)entry;
{ return [downloadPolicy_ representativeJobForEntry:entry playlist:selectedPlaylist_ jobs:[library_ jobsForPlaylist:selectedPlaylist_ video:[entry objectForKey:@"video_id"]]]; }
- (NSString *)statusForJob:(NSDictionary *)job;
{ return [downloadPolicy_ statusForJob:job]; }
- (NSString *)queueStatusForJob:(NSDictionary *)job;
{
  NSString *key=[job objectForKey:@"id"];
  NSString *status=key?[queueStatusCache_ objectForKey:key]:nil;
  if(status) return status;
  status=[self statusForJob:job];
  if(key && status) {
    if(!queueStatusCache_) queueStatusCache_=[[NSMutableDictionary alloc] init];
    if([queueStatusCache_ count]>=128) [queueStatusCache_ removeAllObjects];
    [queueStatusCache_ setObject:status forKey:key];
  }
  return status;
}

- (BOOL)playable:(NSDictionary *)job;
{ return [downloadPolicy_ playable:job]; }
- (void)downloadDateChanged:(id)sender;
{ if(mode_!=0 || [selectedPlaylist_ isEqualToString:[adhocPlaylist_ objectForKey:@"id"]]) [self refresh:sender]; }
- (void)refresh:(id)sender;
{
  (void)sender; if(refreshing_) return; refreshing_=YES;
  NSString *key=mode_==0?@"position":@"id";
  NSMutableArray *selection=[[NSMutableArray alloc] init];
  NSIndexSet *selectedIndexes=[table_ selectedRowIndexes];
  NSUInteger selectedIndex=[selectedIndexes firstIndex];
  while(selectedIndex!=NSNotFound) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    if(selectedIndex<[rows_ count]) {
      NSString *identity=[[rows_ objectAtIndex:selectedIndex] objectForKey:key];
      if(identity) [selection addObject:identity];
    }
    [pool drain]; selectedIndex=[selectedIndexes indexGreaterThanIndex:selectedIndex];
  }
  NSString *queueSelection=[[[self selectedJob] objectForKey:@"id"] copy];
  NSString *oldGroup=selectedPlaylist_?[RDLPLibraryViews groupForPlaylist:[self selectedPlaylist]]:nil;
  [playlists_ release]; playlists_=[[library_ playlists] copy];
  [addedPlaylists_ release]; addedPlaylists_=[[library_ playlistIDsFromAccount:NO] copy];
  [accountPlaylists_ release]; accountPlaylists_=[[library_ playlistIDsFromAccount:YES] copy];
  [unsupportedPlaylists_ release]; unsupportedPlaylists_=[[library_ unsupportedPlaylistIDs] copy];
  [adhocPlaylist_ release]; adhocPlaylist_=[[library_ adhocPlaylist] retain];
  if(mode_==0 && ![self selectedPlaylist]) { mode_=1; [selectedPlaylist_ release]; selectedPlaylist_=nil; [selection release]; selection=nil; }
  BOOL added=mode_==0 && [selectedPlaylist_ isEqualToString:[adhocPlaylist_ objectForKey:@"id"]];
  [rows_ release]; rows_=[(added?[library_ addedVideos]:(mode_==0?[library_ entriesForPlaylist:selectedPlaylist_]:[library_ allDownloads])) copy];
  if(mode_!=0 || added) {
    RDLPDownloadSections *groups=[[[RDLPDownloadSections alloc] initWithRows:(RDLPLibraryRows *)rows_ date:[NSDate date] calendar:[NSCalendar currentCalendar]] autorelease];
    NSArray *grouped=[[groups tableRows:rows_] retain]; [rows_ release]; rows_=grouped;
  }
  [queueRows_ release]; queueRows_=[[library_ queueRows] copy];
  [queueStatusCache_ removeAllObjects];
  [videoRows_ release]; videoRows_=[[RDLPVideoRows alloc] initWithRows:rows_ library:library_ playlist:mode_==0?selectedPlaylist_:nil];
  [sidebar_ reloadData]; [table_ reloadData]; [queue_ reloadData];
  if(!sidebarLoaded_) {
    [sidebar_ expandItem:@"System"]; [sidebar_ expandItem:@"Added Playlists"]; [sidebar_ expandItem:@"My Playlists"]; [sidebar_ expandItem:@"Unsupported Playlists"]; sidebarLoaded_=YES;
  } else if(selectedPlaylist_ && ![oldGroup isEqualToString:[RDLPLibraryViews groupForPlaylist:[self selectedPlaylist]]]) {
    [sidebar_ expandItem:[RDLPLibraryViews groupForPlaylist:[self selectedPlaylist]]];
  }
  id selectedItem=mode_==0?(selectedPlaylist_?[sidebarItems_ objectForKey:selectedPlaylist_]:nil):@"All Downloads";
  NSInteger selectedSidebar=[sidebar_ rowForItem:selectedItem];
  if(selectedSidebar>=0) [sidebar_ selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)selectedSidebar] byExtendingSelection:NO];
  else [sidebar_ deselectAll:nil];
  NSMutableIndexSet *restored=[NSMutableIndexSet indexSet];
  NSEnumerator *identities=[selection objectEnumerator]; NSString *identity;
  while((identity=[identities nextObject])) {
    NSUInteger index=[(RDLPLibraryRows *)rows_ indexForIdentity:identity];
    if(index!=NSNotFound) [restored addIndex:index];
  }
  [table_ selectRowIndexes:restored byExtendingSelection:NO];
  [RDLPLibraryViews restoreSelection:queue_ rows:queueRows_ key:@"id" value:queueSelection];
  [selection release]; [queueSelection release]; refreshing_=NO; bulkAvailabilityValid_=NO; [self updateCustomSummary]; [self updateControls];
}
- (void)tableWasUsed:(NSTableView *)view;
{
  if(refreshing_) return;
  context_=view==sidebar_?0:(view==queue_?2:1);
  if(context_!=2) libraryContext_=context_;
  [self updateControls];
}
- (BOOL)hasTargetVideo;
{ return context_==2?[self selectedJob]!=nil:(context_==1 && [self selectedRow]!=nil); }
- (BOOL)hasMultipleTargetVideos;
{ return context_==1 && [table_ numberOfSelectedRows]>1; }
- (NSDictionary *)targetJob;
{ return [self hasMultipleTargetVideos]?nil:(context_==2?[self selectedJob]:(context_==1?(mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow]):nil)); }
- (NSDictionary *)targetPlaylist;
{
  NSDictionary *job=[self targetJob];
  NSString *key=job?[job objectForKey:@"playlist_id"]:selectedPlaylist_;
  if(context_==2) key=[[self selectedJob] objectForKey:@"playlist_id"];
  if(!key) return nil;
  return [library_ playlistForID:key];
}
- (NSString *)targetVideoID;
{ return context_==2?[[self selectedJob] objectForKey:@"video_id"]:(context_==1?[[self selectedRow] objectForKey:@"video_id"]:nil); }
- (NSString *)targetFormat;
{ NSDictionary *job=[self targetJob]; return (context_==2 || (context_==1 && mode_==1))?([job objectForKey:@"format"]?:downloadFormat_):downloadFormat_; }
- (NSDictionary *)jobForPlaylist:(NSString *)playlist video:(NSString *)video format:(NSString *)format;
{
  return [library_ jobForPlaylist:playlist video:video format:format];
}
- (BOOL)canRetry:(NSDictionary *)job;
{ return [downloadPolicy_ canRetry:job]; }
- (BOOL)canDownloadAgain:(NSDictionary *)job;
{ return [downloadPolicy_ canDownloadAgain:job]; }
- (BOOL)canRemove:(NSDictionary *)job;
{ return [downloadPolicy_ canRemove:job]; }
- (BOOL)canCancel:(NSDictionary *)job;
{ return [downloadPolicy_ canCancel:job]; }
- (NSDictionary *)currentJob:(NSString *)key;
{
  return [library_ jobForID:key];
}
- (NSString *)playFileForPlaylist:(NSDictionary *)playlist;
{
  if(!playlist) return nil;
  NSString *path=[library_ playlistFile:playlist];
  if([[RDLPAppKit videoPlayer] isEqualToString:@"VLC"]) path=[RDLPAppKit VLCPlaybackPath:path];
  if(![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
  /* Recovery/export maintains this file. Toolbar validation only needs a count. */
  return [[library_ jobsForPlaylist:[playlist objectForKey:@"id"] completedOnly:YES] count]?path:nil;
}
/* Snapshot selected rows only. Duplicate playlist occurrences share one job;
   All Downloads rows identify exact jobs and qualities. */
- (NSArray *)selectedRequestsForRemoval:(BOOL)remove firstOnly:(BOOL)firstOnly;
{
  if(remove && [library_ isBusy]) return [NSArray array];
  NSMutableArray *requests=[NSMutableArray array];
  NSMutableSet *seen=[NSMutableSet set];
  NSIndexSet *indexes=[table_ selectedRowIndexes];
  NSUInteger index=[indexes firstIndex];
  while(index!=NSNotFound) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    if(index<[rows_ count]) {
      NSDictionary *row=[rows_ objectAtIndex:index];
      NSString *playlist=mode_==0?selectedPlaylist_:[row objectForKey:@"playlist_id"];
      if([[row objectForKey:@"action"] isEqualToString:@"section"]) { /* Headers have no job identity. */ }
      else if(remove) {
        NSDictionary *job=mode_==0?[self jobForEntry:row]:[self currentJob:[row objectForKey:@"id"]];
        NSString *key=[job objectForKey:@"id"];
        if([self canRemove:job] && ![seen containsObject:key]) {
          [seen addObject:key]; [requests addObject:key];
        }
      } else if(playlist) {
        NSString *video=[row objectForKey:@"video_id"];
        NSString *key=[NSString stringWithFormat:@"%@/%@",playlist,video];
        NSDictionary *job=[self jobForPlaylist:playlist video:video format:downloadFormat_];
        if((!job || [self canRetry:job] || [self canDownloadAgain:job]) && ![seen containsObject:key]) {
          [seen addObject:key];
          [requests addObject:[NSDictionary dictionaryWithObjectsAndKeys:playlist,@"playlist",video,@"video",downloadFormat_,@"format",nil]];
        }
      }
    }
    [pool drain];
    if(firstOnly && [requests count]) break;
    index=[indexes indexGreaterThanIndex:index];
  }
  return requests;
}
- (void)updateBulkAvailability;
{
  if(bulkAvailabilityValid_) return;
  bulkCanDownload_=[[self selectedRequestsForRemoval:NO firstOnly:YES] count]>0;
  bulkCanRemove_=[[self selectedRequestsForRemoval:YES firstOnly:YES] count]>0;
  bulkAvailabilityValid_=YES;
}
- (void)downloadSelectedVideos;
{
  if([self hasAttachedSheet] || ![self hasMultipleTargetVideos]) return;
  NSArray *requests=[[self selectedRequestsForRemoval:NO firstOnly:NO] retain];
  /* Mutations notify synchronously. Refresh once, preserving the original
     snapshot and selection until all selected requests have been processed. */
  refreshing_=YES;
  NSEnumerator *e=[requests objectEnumerator]; NSDictionary *request;
  while((request=[e nextObject])) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    [self enqueueSingle:request allowRetry:YES]; [pool drain];
  }
  refreshing_=NO; [requests release]; [self refresh:nil];
}
- (void)removeSelectedVideos;
{
  if([self hasAttachedSheet] || ![self hasMultipleTargetVideos]) return;
  NSArray *keys=[self selectedRequestsForRemoval:YES firstOnly:NO];
  if(![keys count]) return;
  NSString *noun=[keys count]==1?NSLocalizedString(@"download", nil):NSLocalizedString(@"downloads", nil);
  [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:@"removeMany",@"operation",keys,@"jobs",nil]
    title:[NSString stringWithFormat:NSLocalizedString(@"Move %lu %@ to the Trash?", nil),(unsigned long)[keys count],noun]
    detail:NSLocalizedString(@"This moves the selected downloads and their partial files to the Trash. Playlist membership and other downloaded qualities are retained.", nil)
    action:[NSString stringWithFormat:NSLocalizedString(@"Delete %lu %@", nil),(unsigned long)[keys count],[noun capitalizedString]]];
}
- (NSString *)targetPlaylistFolder;
{
  NSDictionary *playlist=[self selectedPlaylist];
  NSString *path=playlist?[[library_ playlistFile:playlist] stringByDeletingLastPathComponent]:nil;
  BOOL directory=NO;
  return path && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && directory?path:nil;
}
- (NSArray *)syncPlan;
{
  NSMutableArray *inputs=[NSMutableArray array]; NSEnumerator *e=[[library_ playlistsFromAccount:NO] objectEnumerator]; NSDictionary *playlist;
  while((playlist=[e nextObject])) if([RDLPLibrary canSyncPlaylist:playlist] && ![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]]) [inputs addObject:[playlist objectForKey:@"service_id"]];
  return inputs;
}
- (NSUInteger)queuedCount;
{
  return [library_ queuedCount];
}
- (void)setToolbarItem:(NSString *)key title:(NSString *)title tip:(NSString *)tip icon:(NSImage *)icon enabled:(BOOL)enabled;
{
  NSToolbarItem *item=[toolbarItems_ objectForKey:key]; RDLPToolbarButton *view=(RDLPToolbarButton *)[item view];
  [item setLabel:title]; [item setToolTip:tip]; [view setTitle:title]; [view setToolTip:tip];
  if(icon) [view setImage:icon];
  [view setDefaultEnabled:enabled && ![self hasAttachedSheet]];
}
- (void)refreshIconScale:(NSNotification *)notification;
{
  (void)notification;
  [self updateToolbar];
  NSImage *caret=[RDLPAppKit controlIcon:AIFACaretDown style:AIFontAwesomeStyleSolid
    iconSize:8 canvasSize:10 scale:[RDLPAppKit backingScaleForWindow:[self window]]];
  NSEnumerator *e=[toolbarItems_ objectEnumerator]; NSToolbarItem *item;
  while((item=[e nextObject])) [(RDLPToolbarButton *)[item view] setCaretImage:caret];
  /* Cell images are requested lazily again at the owning window's new scale. */
  [table_ reloadData]; [queue_ reloadData];
}
- (void)updateToolbar;
{
  /* The menu bar follows the active window; this toolbar always describes
     the library's own selection. Queue focus must not change its buttons. */
  NSDictionary *row=[self selectedRow];
  BOOL video=libraryContext_==1 && row!=nil;
  BOOL multiple=video && [table_ numberOfSelectedRows]>1;
  if(multiple) [self updateBulkAvailability];
  NSDictionary *job=video && !multiple?(mode_==0?[self jobForEntry:row]:row):nil;
  NSDictionary *playlist=job?[library_ playlistForID:[job objectForKey:@"playlist_id"]]:[self selectedPlaylist];
  [self setToolbarItem:@"library" title:NSLocalizedString(@"Library", nil) tip:NSLocalizedString(@"Add videos and playlists, or sync your library", nil) icon:[RDLPLibraryViews toolbarIcon:(AIFontAwesomeIcon)0x2b window:[self window]] enabled:YES];
  BOOL cancellable=video && [self canCancel:job];
  BOOL retry=video && ([self canRetry:job] || [self canDownloadAgain:job]);
  NSDictionary *matching=video && !multiple?[self jobForPlaylist:[playlist objectForKey:@"id"] video:[row objectForKey:@"video_id"] format:downloadFormat_]:nil;
  BOOL canDownload=multiple?bulkCanDownload_:(video && (!matching || [self canRetry:matching] || [self canDownloadAgain:matching]));
  NSString *quality=[RDLPLibrary qualityLabelForFormat:retry?[job objectForKey:@"format"]:downloadFormat_];
  NSString *downloadTip=cancellable?NSLocalizedString(@"Cancel the selected download…", nil):[NSString stringWithFormat:NSLocalizedString(@"%@ — %@", nil),retry?NSLocalizedString(@"Retry the selected download", nil):NSLocalizedString(@"Download the selected video", nil),quality];
  if(multiple) downloadTip=[NSString stringWithFormat:NSLocalizedString(@"Download selected videos — %@", nil),quality];
  [self setToolbarItem:@"download" title:NSLocalizedString(@"Download", nil) tip:downloadTip icon:[RDLPLibraryViews toolbarIcon:cancellable?AIFAOctagon:AIFADownload window:[self window]] enabled:cancellable || retry || canDownload];
  [self setToolbarItem:@"remove" title:NSLocalizedString(@"Remove", nil) tip:multiple?NSLocalizedString(@"Move selected downloads to the Trash…", nil):NSLocalizedString(@"Delete the selected download or remove the selected playlist…", nil) icon:[RDLPLibraryViews toolbarIcon:AIFATrash window:[self window]] enabled:multiple?bulkCanRemove_:(video?[self canRemove:job]:[self canRemovePlaylist:playlist])];
  NSString *path=video?([self playable:job]?[library_ fileForJob:job]:nil):[self playFileForPlaylist:playlist];
  [self setToolbarItem:@"play" title:NSLocalizedString(@"Play", nil) tip:NSLocalizedString(@"Play the selected video or playlist", nil) icon:[RDLPAppKit youTubeIconForScale:[RDLPAppKit backingScaleForWindow:[self window]]] enabled:[RDLPAppKit preferredPlaybackApplication:path]!=nil];
  [self setToolbarItem:@"cookies" title:NSLocalizedString(@"Cookies", nil) tip:NSLocalizedString(@"Manage cookies and view the export guide", nil) icon:[RDLPLibraryViews toolbarIcon:AIFACookie window:[self window]] enabled:YES];
  [self setToolbarItem:@"downloads" title:NSLocalizedString(@"Queue", nil) tip:NSLocalizedString(@"Show Download Queue", nil) icon:[RDLPLibraryViews toolbarIcon:AIFAListCheck window:[self window]] enabled:YES];
}
- (void)updateControls;
{ [self updateToolbar]; [queueWindow_ updateControls]; [self refreshStatus:nil]; }
- (void)refreshStatus:(id)sender;
{
  (void)sender;
  [status_ setStringValue:[library_ status]];
  [status_ setToolTip:[library_ status]];
  NSDictionary *progress=[library_ activityProgress];
  BOOL active=[[progress objectForKey:@"active"] boolValue];
  double expected=[[progress objectForKey:@"expected"] doubleValue];
  [queueProgress_ setHidden:!active];
  [queueProgress_ setIndeterminate:expected<=0];
  if(active && expected<=0) [queueProgress_ startAnimation:nil]; else [queueProgress_ stopAnimation:nil];
  [queueProgress_ setMaxValue:MAX(expected,1)];
  [queueProgress_ setDoubleValue:MIN(expected,[[progress objectForKey:@"completed"] doubleValue])];
  [queueProgress_ setToolTip:[library_ status]];
  [queueWindow_ refreshStatus];
}

- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item;
{
  (void)outline;
  if(!item) return 4; if([item isEqual:@"System"]) return adhocPlaylist_?2:1;
  return (NSInteger)[([item isEqual:@"Unsupported Playlists"]?unsupportedPlaylists_:([item isEqual:@"My Playlists"]?accountPlaylists_:addedPlaylists_)) count];
}
- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item;
{
  (void)outline;
  if(!item) return [[NSArray arrayWithObjects:@"System",@"Added Playlists",@"My Playlists",@"Unsupported Playlists",nil] objectAtIndex:(NSUInteger)index];
  if([item isEqual:@"System"]) {
    if(index==0) return @"All Downloads";
    NSString *key=[adhocPlaylist_ objectForKey:@"id"]; if(![sidebarItems_ objectForKey:key]) [sidebarItems_ setObject:key forKey:key]; return [sidebarItems_ objectForKey:key];
  }
  NSDictionary *playlist=[([item isEqual:@"Unsupported Playlists"]?unsupportedPlaylists_:([item isEqual:@"My Playlists"]?accountPlaylists_:addedPlaylists_)) objectAtIndex:(NSUInteger)index];
  NSString *key=[playlist objectForKey:@"id"];
  if(![sidebarItems_ objectForKey:key]) [sidebarItems_ setObject:key forKey:key];
  return [sidebarItems_ objectForKey:key];
}
- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item;
{ (void)outline; return [RDLPLibraryViews isSidebarGroup:item]; }
- (BOOL)outlineView:(NSOutlineView *)outline shouldSelectItem:(id)item;
{ (void)outline; return ![RDLPLibraryViews isSidebarGroup:item]; }
- (id)outlineView:(NSOutlineView *)outline objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item;
{
  (void)outline; (void)column;
  if([RDLPLibraryViews isSidebarGroup:item] || [item isEqual:@"All Downloads"]) return NSLocalizedString(item, nil);
  NSDictionary *playlist=[library_ playlistForID:item];
  return playlist?[NSString stringWithFormat:NSLocalizedString(@"%@ (%@)", nil),[playlist objectForKey:@"title"],[playlist objectForKey:@"count"]]:@"";
}
- (void)outlineView:(NSOutlineView *)outline willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column item:(id)item;
{
  (void)outline; (void)column;
  BOOL bold=[RDLPLibraryViews isSidebarGroup:item];
  [cell setFont:bold?[NSFont boldSystemFontOfSize:12]:[NSFont systemFontOfSize:12]];
}
- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
{ [self tableViewSelectionDidChange:notification]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)view;
{ return (NSInteger)[(view==queue_?queueRows_:rows_) count]; }
- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
{
  BOOL queue=view==queue_;
  NSDictionary *entry=[(queue?queueRows_:videoRows_) objectAtIndex:(NSUInteger)row]; NSString *key=[column identifier];
  if(!queue && [[entry objectForKey:@"action"] isEqualToString:@"section"]) return (!column || [key isEqualToString:@"state"] || [key isEqualToString:@"title"])?[entry objectForKey:@"title"]:nil;
  NSDictionary *job=entry;
  if(!queue && ![key isEqualToString:@"state"]) return [entry objectForKey:key];
  if(queue && [key isEqualToString:@"number"]) return [job objectForKey:@"id"];
  if(queue && ([key isEqualToString:@"enqueueDate"] || [key isEqualToString:@"latestDownloadDate"])) {
    NSTimeInterval seconds=[[job objectForKey:key] doubleValue];
    return seconds>0?[NSDate dateWithTimeIntervalSince1970:seconds]:nil;
  }
  if(queue && [key isEqualToString:@"quality"]) {
    NSString *format=[job objectForKey:@"format"], *actual=[job objectForKey:@"actual_format"];
    NSString *label=[RDLPLibrary qualityLabelForFormat:format];
    return [actual length] && ![actual isEqualToString:format]?[label stringByAppendingFormat:NSLocalizedString(@" → %@", nil),[RDLPLibrary qualityLabelForFormat:actual]]:label;
  }
  if([key isEqualToString:@"state"]) {
    NSString *status=queue?[self queueStatusForJob:job]:[entry objectForKey:@"status"]; AIFontAwesomeIcon icon=0;
    if([status isEqualToString:NSLocalizedString(@"Downloaded", nil)]) icon=AIFACircleCheck;
    else if([status isEqualToString:NSLocalizedString(@"Downloading", nil)]) icon=AIFAArrowDown;
    else if([status isEqualToString:NSLocalizedString(@"Queued", nil)]) icon=AIFAClock;
    else if([status isEqualToString:NSLocalizedString(@"Cancelled", nil)]) icon=AIFACirclePause;
    else if(![status isEqualToString:NSLocalizedString(@"Not downloaded", nil)]) icon=AIFATriangleExclamation;
    return icon?[AIFontAwesome imageForIcon:icon style:AIFontAwesomeStyleSolid iconSize:12 canvasSize:16 scale:[RDLPAppKit backingScaleForWindow:[view window]]]:nil;
  }
  return [entry objectForKey:key];
}
- (NSIndexSet *)nonselectableRowsInTableView:(NSTableView *)view;
{ return view==table_ && [rows_ respondsToSelector:@selector(downloadHeaderIndexes)]?[rows_ downloadHeaderIndexes]:nil; }
- (BOOL)tableView:(NSTableView *)view RDLP_isSectionRow:(NSInteger)row;
{
  return view==table_ && row>=0 && (NSUInteger)row<[rows_ count] &&
    [rows_ respondsToSelector:@selector(isSectionAtIndex:)] && [(id)rows_ isSectionAtIndex:(NSUInteger)row];
}
- (BOOL)tableView:(NSTableView *)view isGroupRow:(NSInteger)row;
{ return [view RDLP_supportsGroupRows] && [self tableView:view RDLP_isSectionRow:row]; }
- (BOOL)tableView:(NSTableView *)view shouldSelectRow:(NSInteger)row;
{ return ![self tableView:view RDLP_isSectionRow:row]; }
- (NSCell *)tableView:(NSTableView *)view dataCellForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
{
  if([self tableView:view RDLP_isSectionRow:row]) {
    NSTextFieldCell *cell=[[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
    [cell setFont:[NSFont boldSystemFontOfSize:12]]; return cell;
  }
  return [column dataCell];
}
- (void)tableView:(NSTableView *)view willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row;
{
  if([[column identifier] isEqualToString:@"state"]) {
    NSDictionary *entry=[(view==queue_?queueRows_:videoRows_) objectAtIndex:(NSUInteger)row];
    [cell setRepresentedObject:view==queue_?[self queueStatusForJob:entry]:[entry objectForKey:@"status"]];
  }
}
- (NSString *)tableView:(NSTableView *)view toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column row:(NSInteger)row mouseLocation:(NSPoint)point;
{
  (void)cell; (void)rect; (void)point;
  NSDictionary *entry=[(view==queue_?queueRows_:videoRows_) objectAtIndex:(NSUInteger)row];
  if(view==table_) return [entry objectForKey:[[column identifier] isEqualToString:@"title"]?@"tooltip":([[column identifier] isEqualToString:@"state"]?@"status_tooltip":[column identifier])];
  if(![[column identifier] isEqualToString:@"state"]) {
    id value=[self tableView:view objectValueForTableColumn:column row:row];
    NSFormatter *formatter=[[column dataCell] formatter];
    if(formatter) return value?[formatter stringForObjectValue:value]:nil;
    return [value isKindOfClass:[NSString class]]?value:[value description];
  }
  NSDictionary *job=entry;
  NSString *status=[self queueStatusForJob:job], *error=[job objectForKey:@"error"];
  return [error length]?[NSString stringWithFormat:NSLocalizedString(@"%@: %@", nil),status,error]:status;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
{
  if(refreshing_) return;
  bulkAvailabilityValid_=NO;
  context_=[notification object]==sidebar_?0:([notification object]==queue_?2:1);
  if(context_!=2) libraryContext_=context_;
  if([notification object]==sidebar_) {
    NSInteger row=[sidebar_ selectedRow]; if(row<0) return;
    refreshing_=YES; [table_ deselectAll:nil]; refreshing_=NO;
    id item=[sidebar_ itemAtRow:row]; if([RDLPLibraryViews isSidebarGroup:item]) return;
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
  BOOL multiple=[self hasMultipleTargetVideos];
  if(visibilityAction==@selector(downloadFromMenu:) || (visibilityAction==@selector(chooseDownload:) && [item tag]==0))
    [item setTitle:multiple?NSLocalizedString(@"Download Selected Videos", nil):NSLocalizedString(@"Download Video", nil)];
  if(visibilityAction==@selector(removeTarget:)) [item setTitle:multiple?NSLocalizedString(@"Delete Selected Downloads…", nil):([[[item menu] title] isEqualToString:@"remove"]?NSLocalizedString(@"Delete Download", nil):NSLocalizedString(@"Delete Download…", nil))];
  if(visibilityAction==@selector(togglePlaylists:)) [item setTitle:[self isSidebarCollapsed]?NSLocalizedString(@"Show Playlists", nil):NSLocalizedString(@"Hide Playlists", nil)];
  if([[item menu] title] && [[[item menu] title] isEqualToString:NSLocalizedString(@"File", nil)]) {
    NSString *object=[self hasTargetVideo]?NSLocalizedString(@"Video", nil):NSLocalizedString(@"Playlist", nil);
    if(visibilityAction==@selector(playSelection:)) [item setTitle:[NSString stringWithFormat:NSLocalizedString(@"Play %@", nil),object]];
  }
  if(visibilityAction==@selector(chooseVideoPlayer:)) {
    NSString *player=[item representedObject];
    [item setState:[[RDLPAppKit videoPlayer] isEqualToString:player]?NSOnState:NSOffState];
    return ![self hasAttachedSheet] && [RDLPAppKit videoPlayerAvailable:player];
  }
  if([self hasAttachedSheet]) return NO;
  if(visibilityAction==@selector(downloadFromMenu:)) {
    if(context_==2 && [self selectedJob]) return [self canRetry:[self selectedJob]] || [self canDownloadAgain:[self selectedJob]];
    NSMenuItem *command=[[[NSMenuItem alloc] initWithTitle:@"" action:@selector(chooseDownload:) keyEquivalent:@""] autorelease];
    [command setTag:0]; return [self validateMenuItem:command];
  }
  SEL action=[item action]; NSDictionary *job=[self targetJob], *playlist=[self contextPlaylist], *queued=[self selectedJob];
  BOOL noCookies=[[library_ cookieStatus] isEqualToString:NSLocalizedString(@"Not Imported", nil)];
  if(action==@selector(importCookies:)) return ![library_ isBusy] && noCookies;
  if(action==@selector(replaceCookies:) || action==@selector(clearCookies:)) return ![library_ isBusy] && !noCookies;
  if(action==@selector(discover:)) return ![library_ isBusy] && ![library_ isDiscoveryPending];
  if(action==@selector(sync:)) return playlist && [RDLPLibrary canSyncPlaylist:playlist] && ![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]];
  if(action==@selector(syncAll:)) return [library_ hasPlaylistsToSync];
  if(action==@selector(chooseDownload:)) {
    NSUInteger index=(NSUInteger)[item tag];
    if(index>4) return NO;
    if(index>0) {
      NSString *format=index<4?[[RDLPLibrary qualityFormats] objectAtIndex:index-1]:nil;
      BOOL custom=![[RDLPLibrary qualityFormats] containsObject:downloadFormat_];
      [item setState:(index==4?custom:[format isEqualToString:downloadFormat_])?NSOnState:NSOffState];
      return YES;
    }
    [item setState:NSOffState];
    if(multiple) { [self updateBulkAvailability]; return bulkCanDownload_; }
    playlist=[self contextPlaylist];
    if(!playlist || ![self hasTargetVideo]) return NO;
    NSString *format=downloadFormat_;
    NSDictionary *matching=[self jobForPlaylist:[playlist objectForKey:@"id"] video:[self targetVideoID] format:format];
    return !matching || [self canRetry:matching] || [self canDownloadAgain:matching];
  }
  if(action==@selector(retryTarget:)) return [self canRetry:job];
  if(action==@selector(againTarget:)) return [self canDownloadAgain:job];
  if(action==@selector(cancelTarget:)) return [self canCancel:job];
  if(action==@selector(removeTarget:)) {
    if(multiple) { [self updateBulkAvailability]; return bulkCanRemove_; }
    return [self canRemove:job];
  }
  if(action==@selector(showTargetInQueue:)) return job!=nil;
  if(action==@selector(playSelection:)) return [RDLPAppKit preferredPlaybackApplication:[self selectionPlayFile]]!=nil;
  if(action==@selector(revealSelection:)) return [self hasTargetVideo]?[self playable:job]:([self contextPlaylist]!=nil && [self targetPlaylistFolder]!=nil);
  if(action==@selector(playTargetVideo:)) return [self playable:job] && [RDLPAppKit preferredPlaybackApplication:[library_ fileForJob:job]]!=nil;
  if(action==@selector(playTargetPlaylist:)) return [RDLPAppKit preferredPlaybackApplication:[self playFileForPlaylist:[self contextPlaylist]]]!=nil;
  if(action==@selector(revealTarget:)) return [self playable:job];
  if(action==@selector(revealPlaylistFolder:)) return [self targetPlaylistFolder]!=nil;
  if(action==@selector(openDownloadsFolder:)) return [[NSFileManager defaultManager] fileExistsAtPath:[library_ downloadsDirectory]];
  if(action==@selector(showQueue:)) return YES;
  if(action==@selector(hideQueue:)) return [[queueWindow_ window] isVisible];
  if(action==@selector(showQueueError:)) return [[queued objectForKey:@"error"] length]>0;
  if(action==@selector(retryQueueJob:)) return [self canRetry:queued] || [self canDownloadAgain:queued];
  if(action==@selector(againQueueJob:)) return [self canDownloadAgain:queued];
  if(action==@selector(cancelQueueJob:)) return [self canCancel:queued];
  if(action==@selector(removeJob:)) return [self canRemove:queued];
  if(action==@selector(openJob:)) return [self playable:queued] && [RDLPAppKit preferredPlaybackApplication:[library_ fileForJob:queued]]!=nil;
  if(action==@selector(removeDownload:)) {
    if(multiple) { [self updateBulkAvailability]; return bulkCanRemove_; }
    return [self canRemove:mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow]];
  }
  if(action==@selector(removePlaylist:)) return [self canRemovePlaylist:[self contextPlaylist]];
  if(action==@selector(playPlaylist:)) return [RDLPAppKit preferredPlaybackApplication:[self playFileForPlaylist:[self selectedPlaylist]]]!=nil;
  return YES;
}
- (void)addPlaylist:(id)sender;
{
  (void)sender; if(addSheet_ || [self hasAttachedSheet]) return;
  addingVideo_=NO;
  addSheet_=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,460,135) styleMask:AIWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [addSheet_ setTitle:NSLocalizedString(@"Add Playlist", nil)];
  NSView *view=[addSheet_ contentView]; [[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,95,420,24) editable:NO] setStringValue:NSLocalizedString(@"Playlist URL or ID", nil)];
  input_=[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,62,420,24) editable:YES];
  NSButton *cancel=[RDLPLibraryViews buttonInView:view title:NSLocalizedString(@"Cancel", nil) action:@selector(dismissAdd:) target:self frame:NSMakeRect(230,15,100,28)]; [cancel setTag:0]; [cancel setKeyEquivalent:@"\033"];
  NSButton *add=[RDLPLibraryViews buttonInView:view title:NSLocalizedString(@"Add Playlist", nil) action:@selector(dismissAdd:) target:self frame:NSMakeRect(335,15,110,28)]; [add setTag:1]; [add setKeyEquivalent:@"\r"];
  [RDLPAppKit beginSheet:addSheet_ forWindow:[self actionWindow] delegate:self didEnd:@selector(addSheetDidEnd:returnCode:contextInfo:)];
  [addSheet_ makeFirstResponder:input_];
}
- (void)addVideo:(id)sender;
{
  (void)sender;
  if([self hasAttachedSheet] || addSheet_) return;
  addSheet_=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,460,135) styleMask:AIWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [addSheet_ setTitle:NSLocalizedString(@"Add Video", nil)];
  NSView *view=[addSheet_ contentView]; [[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,95,420,24) editable:NO] setStringValue:NSLocalizedString(@"YouTube video URL or ID", nil)];
  addingVideo_=YES; input_=[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,62,420,24) editable:YES];
  NSButton *cancel=[RDLPLibraryViews buttonInView:view title:NSLocalizedString(@"Cancel", nil) action:@selector(dismissAdd:) target:self frame:NSMakeRect(230,15,100,28)]; [cancel setTag:0]; [cancel setKeyEquivalent:@"\033"];
  NSButton *add=[RDLPLibraryViews buttonInView:view title:NSLocalizedString(@"Add Video", nil) action:@selector(dismissAdd:) target:self frame:NSMakeRect(335,15,110,28)]; [add setTag:1]; [add setKeyEquivalent:@"\r"];
  [RDLPAppKit beginSheet:addSheet_ forWindow:[self actionWindow] delegate:self didEnd:@selector(addSheetDidEnd:returnCode:contextInfo:)]; [addSheet_ makeFirstResponder:input_];
}
- (void)dismissAdd:(id)sender;
{ [NSApp endSheet:addSheet_ returnCode:[sender tag]]; }
- (void)addSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code contextInfo:(void *)context;
{
  (void)context; NSString *input=[[input_ stringValue] copy]; BOOL addingVideo=addingVideo_; [sheet orderOut:nil];
  [addSheet_ release]; addSheet_=nil; input_=nil;
  if(code==1) { if(addingVideo) [library_ addVideoInput:input]; else [library_ addPlaylistInput:input]; } [input release];
}
- (void)confirmRequest:(NSDictionary *)request title:(NSString *)title detail:(NSString *)detail action:(NSString *)action;
{
  if([self hasAttachedSheet] || confirmation_) return;
  confirmationRequest_=[request copy]; confirmation_=[[NSAlert alloc] init];
  [confirmation_ setMessageText:title]; [confirmation_ setInformativeText:detail];
  [[confirmation_ addButtonWithTitle:action] setKeyEquivalent:@"\r"];
  [[confirmation_ addButtonWithTitle:NSLocalizedString(@"Cancel", nil)] setKeyEquivalent:@"\033"];
  [RDLPAppKit beginAlertSheet:confirmation_ forWindow:[self actionWindow] delegate:self didEnd:@selector(confirmationDidEnd:returnCode:contextInfo:)];
  [self updateControls];
}
- (void)confirmationDidEnd:(NSAlert *)alert returnCode:(NSInteger)code contextInfo:(void *)context;
{
  (void)context; NSDictionary *request=[[confirmationRequest_ retain] autorelease];
  [[alert window] orderOut:nil]; [confirmation_ release]; confirmation_=nil;
  [confirmationRequest_ release]; confirmationRequest_=nil;
  if(code==NSAlertFirstButtonReturn) [self performSelector:@selector(performConfirmed:) withObject:request afterDelay:0];
  [self updateControls];
}
- (void)performConfirmed:(NSDictionary *)request;
{
  NSString *op=[request objectForKey:@"operation"];
  if([op isEqualToString:@"removeMany"]) {
    refreshing_=YES;
    NSEnumerator *e=[[request objectForKey:@"jobs"] objectEnumerator]; NSString *key;
    while((key=[e nextObject])) {
      NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
      NSDictionary *job=[self currentJob:key];
      if([self canRemove:job]) [library_ removeDownload:job];
      [pool drain];
    }
    refreshing_=NO;
  } else if([op isEqualToString:@"syncAll"]) {
    NSEnumerator *e=[[request objectForKey:@"inputs"] objectEnumerator]; NSString *input;
    while((input=[e nextObject])) [library_ syncPlaylistInput:input];
  } else if([op isEqualToString:@"discover"]) {
    if([library_ isBusy] || [library_ isDiscoveryPending]) return;
    if(![[library_ cookieStatus] isEqualToString:NSLocalizedString(@"Imported", nil)]) {
      NSString *path=[RDLPAppKit chooseCookieFile]; if(!path) return;
      if(![[library_ cookieStatus] isEqualToString:NSLocalizedString(@"Not Imported", nil)]) {
        [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:@"import",@"operation",path,@"path",@"yes",@"discover",nil] title:NSLocalizedString(@"Replace cookies and sync playlists?", nil) detail:NSLocalizedString(@"Replace the app’s working cookie copy, then sync your account playlists. Local downloads are retained. No videos will be downloaded.", nil) action:NSLocalizedString(@"Replace and Sync", nil)]; return;
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
  NSString *title=[NSString stringWithFormat:NSLocalizedString(@"%@ ‘%@’ — %@?", nil),remove?NSLocalizedString(@"Delete download for", nil):NSLocalizedString(@"Cancel download for", nil),[job objectForKey:@"title"],[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]]];
  [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:remove?@"remove":@"cancel",@"operation",[job objectForKey:@"id"],@"job",nil] title:title detail:remove?NSLocalizedString(@"This moves this download and its partial files to the Trash. Playlist membership and other downloaded qualities are retained.", nil):NSLocalizedString(@"Retrying this job restarts the transfer; it does not resume from where it stopped.", nil) action:remove?NSLocalizedString(@"Delete Download", nil):NSLocalizedString(@"Cancel Download", nil)];
}
- (BOOL)canRemovePlaylist:(NSDictionary *)playlist;
{
  return [library_ canRemovePlaylist:playlist];
}
- (void)retryDownloadJob:(NSDictionary *)job;
{
  if(![self canRetry:job] && ![self canDownloadAgain:job]) return;
  NSString *key=[[[job objectForKey:@"id"] copy] autorelease];
  [library_ retryJob:key]; [self refresh:nil];
}
- (void)enqueueSingle:(NSDictionary *)request allowRetry:(BOOL)allowRetry;
{
  NSString *playlist=[request objectForKey:@"playlist"], *video=[request objectForKey:@"video"], *format=[request objectForKey:@"format"];
  NSDictionary *job=[library_ jobForPlaylist:playlist video:video format:format];
  if(!job) {
    [library_ enqueuePlaylist:playlist video:video format:format];
    [self refresh:nil];
  } else if([self canDownloadAgain:job] || (allowRetry && [self canRetry:job])) [self retryDownloadJob:job];
}
- (void)enqueueRequest:(NSDictionary *)request;
{
  if(![request objectForKey:@"video"]) return;
  NSString *format=[request objectForKey:@"format"];
  if(![RDLPLibrary savePreferredFormat:format]) return;
  [downloadFormat_ release]; downloadFormat_=[format copy];
  [self enqueueSingle:request allowRetry:YES];
  [self refresh:nil];
}
- (void)downloadSelectedVideo:(id)sender;
{
  if([self hasAttachedSheet] || ![self hasTargetVideo]) return;
  if([self hasMultipleTargetVideos]) { [self downloadSelectedVideos]; return; }
  NSDictionary *job=[self targetJob], *playlist=[self contextPlaylist];
  if([self canCancel:job]) [self cancelTarget:sender];
  else if([self canRetry:job] || [self canDownloadAgain:job]) [self retryDownloadJob:job];
  else if(playlist) {
    NSMenuItem *command=[[[NSMenuItem alloc] initWithTitle:@"" action:@selector(chooseDownload:) keyEquivalent:@""] autorelease];
    [self chooseDownload:command];
  }
}
- (void)sync:(id)sender;
{ (void)sender; NSDictionary *playlist=[self contextPlaylist]; if(playlist && [RDLPLibrary canSyncPlaylist:playlist]) [library_ syncPlaylistInput:[playlist objectForKey:@"service_id"]]; }
- (void)syncAll:(id)sender;
{
  (void)sender; NSArray *inputs=[self syncPlan]; if(![inputs count]) return;
  [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:@"syncAll",@"operation",inputs,@"inputs",nil] title:[NSString stringWithFormat:NSLocalizedString(@"Sync %lu added playlists?", nil),(unsigned long)[inputs count]] detail:NSLocalizedString(@"Refresh your manually added playlists and their videos from YouTube. Local downloads are retained. This does not download videos.", nil) action:[NSString stringWithFormat:NSLocalizedString(@"Sync %lu Added Playlists", nil),(unsigned long)[inputs count]]];
}
- (void)discover:(id)sender;
{
  (void)sender; if([library_ isBusy] || [library_ isDiscoveryPending]) return;
  [self confirmRequest:[NSDictionary dictionaryWithObject:@"discover" forKey:@"operation"] title:NSLocalizedString(@"Sync My Playlists?", nil) detail:NSLocalizedString(@"Refresh your account playlists and their videos. Playlists no longer in your account are removed locally; downloads and unfinished jobs are retained. You will be asked to import cookies if needed. No videos will be downloaded.", nil) action:NSLocalizedString(@"Sync My Playlists", nil)];
}
- (void)openCookieExportGuide:(id)sender;
{
  (void)sender;
  if(![[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/yt-dlp/yt-dlp/wiki/Extractors"]]) [RDLPAppKit showAlert:NSLocalizedString(@"Could not open the cookie export guide in your browser.", nil)];
}
- (void)importCookies:(id)sender;
{
  (void)sender; if([library_ isBusy] || [self hasAttachedSheet]) return;
  if(![[library_ cookieStatus] isEqualToString:NSLocalizedString(@"Not Imported", nil)]) { [self replaceCookies:nil]; return; }
  NSString *path=[RDLPAppKit chooseCookieFile]; if(path) [library_ importCookies:path];
}
- (void)replaceCookies:(id)sender;
{
  (void)sender; if([library_ isBusy] || [self hasAttachedSheet]) return;
  NSString *path=[RDLPAppKit chooseCookieFile]; if(!path) return;
  [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:@"import",@"operation",path,@"path",nil] title:NSLocalizedString(@"Replace imported cookies?", nil) detail:NSLocalizedString(@"Replace the app’s working cookie copy with the selected file. The original exported files are retained.", nil) action:NSLocalizedString(@"Replace", nil)];
}
- (void)clearCookies:(id)sender;
{
  (void)sender; if([library_ isBusy] || [[library_ cookieStatus] isEqualToString:NSLocalizedString(@"Not Imported", nil)]) return;
  [self confirmRequest:[NSDictionary dictionaryWithObject:@"clearCookies" forKey:@"operation"] title:NSLocalizedString(@"Remove imported cookies?", nil) detail:NSLocalizedString(@"Remove the app’s working cookie copy. The original exported file is retained.", nil) action:NSLocalizedString(@"Remove", nil)];
}
- (void)showQueueError:(id)sender;
{ (void)sender; NSString *error=[[self selectedJob] objectForKey:@"error"]; if([error length]) [RDLPAppKit showAlert:error]; }
- (void)togglePlaylists:(id)sender;
{ if([self hasAttachedSheet]) return; [self toggleSidebar:sender]; [self updateControls]; }
- (void)showQueue:(id)sender;
{ [queueWindow_ showWindow:sender]; context_=2; [self updateControls]; }
- (void)hideQueue:(id)sender;
{
  (void)sender; if([[queueWindow_ window] attachedSheet]) return;
  [queueWindow_ close]; context_=libraryContext_; [self updateControls];
}
- (void)revealDownloads; { [self showQueue:nil]; }
- (void)showJobInQueue:(NSDictionary *)job;
{
  if(!job) return;
  NSString *key=[[[job objectForKey:@"id"] copy] autorelease];
  [self revealDownloads]; refreshing_=YES;
  [RDLPLibraryViews restoreSelection:queue_ rows:queueRows_ key:@"id" value:key];
  refreshing_=NO;
  if([queue_ selectedRow]>=0) [queue_ scrollRowToVisible:[queue_ selectedRow]];
  [self updateControls];
}
- (void)showTargetInQueue:(id)sender; { (void)sender; [self showJobInQueue:[self targetJob]]; }
- (void)retryTarget:(id)sender;
{ (void)sender; NSDictionary *job=[self targetJob]; if([self canRetry:job]) [self retryDownloadJob:job]; }
- (void)againTarget:(id)sender;
{ (void)sender; NSDictionary *job=[self targetJob]; if([self canDownloadAgain:job]) [self retryDownloadJob:job]; }
- (void)cancelTarget:(id)sender; { (void)sender; [self confirmJob:[self targetJob] remove:NO]; }
- (void)removeTarget:(id)sender; { (void)sender; if([self hasMultipleTargetVideos]) [self removeSelectedVideos]; else [self confirmJob:[self targetJob] remove:YES]; }
- (void)retryQueueJob:(id)sender;
{ (void)sender; NSDictionary *job=[self selectedJob]; if([self canRetry:job] || [self canDownloadAgain:job]) [self retryDownloadJob:job]; }
- (void)againQueueJob:(id)sender;
{ (void)sender; NSDictionary *job=[self selectedJob]; if([self canDownloadAgain:job]) [self retryDownloadJob:job]; }
- (void)cancelQueueJob:(id)sender; { (void)sender; [self confirmJob:[self selectedJob] remove:NO]; }
- (void)jobAction:(id)sender;
{
  NSDictionary *job=[self selectedJob];
  if([self canCancel:job]) [self cancelQueueJob:sender];
  else if([self canDownloadAgain:job]) [self againQueueJob:sender]; else [self retryQueueJob:sender];
}
- (void)removeDownload:(id)sender;
{ [self removeTarget:sender]; }
- (void)removeJob:(id)sender; { (void)sender; [self confirmJob:[self selectedJob] remove:YES]; }
- (void)removePlaylist:(id)sender;
{
  (void)sender; NSDictionary *playlist=[self contextPlaylist]; if(![self canRemovePlaylist:playlist]) return;
  [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:@"removePlaylist",@"operation",playlist,@"playlist",nil] title:[NSString stringWithFormat:NSLocalizedString(@"Remove ‘%@’ from the library?", nil),[playlist objectForKey:@"title"]] detail:NSLocalizedString(@"Removes the playlist from your library. Downloads and unfinished jobs are retained. Your YouTube playlist is unchanged.", nil) action:NSLocalizedString(@"Remove Playlist", nil)];
}
- (void)playTargetVideo:(id)sender;
{ (void)sender; NSDictionary *job=[self targetJob]; if([self playable:job]) [RDLPAppKit openPreferredPlayback:[library_ fileForJob:job]]; }
- (void)playTargetPlaylist:(id)sender;
{ (void)sender; NSString *path=[self playFileForPlaylist:[self contextPlaylist]]; if(path) [RDLPAppKit openPreferredPlayback:path]; }
- (void)revealTarget:(id)sender;
{ (void)sender; NSDictionary *job=[self targetJob]; if([self playable:job]) [RDLPAppKit revealInFinder:[library_ fileForJob:job]]; }
- (void)revealPlaylistFolder:(id)sender;
{ (void)sender; NSString *path=[self targetPlaylistFolder]; if(path) [RDLPAppKit revealInFinder:path]; }
- (void)openDownloadsFolder:(id)sender;
{ (void)sender; [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:[library_ downloadsDirectory]]]; }
- (void)openVideo:(id)sender;
{ (void)sender; if([table_ numberOfSelectedRows]!=1) return; NSDictionary *job=mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow]; if([self playable:job]) [RDLPAppKit openPreferredPlayback:[library_ fileForJob:job]]; }
- (void)openJob:(id)sender;
{ (void)sender; if([self playable:[self selectedJob]]) [RDLPAppKit openPreferredPlayback:[library_ fileForJob:[self selectedJob]]]; }
- (void)playPlaylist:(id)sender;
{ (void)sender; NSString *path=[self playFileForPlaylist:[self selectedPlaylist]]; if(path) [RDLPAppKit openPreferredPlayback:path]; }
@end
