#import "RDLPLibraryWindowController.h"
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
- (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier;
- (void)playVideoInVLC:(id)sender;
- (void)playPlaylistInVLC:(id)sender;
- (void)menuNeedsUpdate:(NSMenu *)menu;
- (NSDictionary *)contextPlaylist;
- (NSString *)selectionPlayFile;
- (void)playSelection:(id)sender;
- (void)playSelectionInDefaultApplication:(id)sender;
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
@implementation RDLPLibraryWindowController
- (id)initWithLibrary:(RDLPLibrary *)library;
{
  self=[super initWithTitle:@"RetroDLP" autosaveName:@"RetroDLPLibraryWindow"]; if(!self) return nil;
  library_=[library retain]; downloadPolicy_=[[RDLPDownloadPolicy alloc] initWithLibrary:library]; mode_=1;
  AIViewController *left=[[[AIViewController alloc] init] autorelease];
  NSView *sidebar=[[[RDLPLayoutView alloc] initWithFrame:NSMakeRect(0,0,200,600)] autorelease];
  sidebarItems_=[[NSMutableDictionary alloc] init];
  sidebar_=[RDLPLibraryViews sidebarInView:sidebar owner:self];
  [left setView:sidebar]; [self setSidebarViewController:left];
  AIViewController *middle=[[[AIViewController alloc] init] autorelease];
  NSView *detail=[[[RDLPLayoutView alloc] initWithFrame:NSMakeRect(0,0,540,600)] autorelease];
  table_=[RDLPLibraryViews tableInView:detail frame:[detail bounds] owner:self
    names:[NSArray arrayWithObjects:@"state",@"size",@"quality",@"title",@"channel",nil]
    labels:[NSArray arrayWithObjects:@"",@"Size",@"Quality",@"Video",@"Channel",nil]];
  NSTableColumn *stateColumn=[table_ tableColumnWithIdentifier:@"state"];
  [stateColumn setMinWidth:24]; [stateColumn setMaxWidth:24]; [stateColumn setWidth:24];
  [stateColumn setResizingMask:NSTableColumnNoResizing];
  [stateColumn setDataCell:[[[RDLPStatusCell alloc] initImageCell:nil] autorelease]];
  NSTableColumn *sizeColumn=[table_ tableColumnWithIdentifier:@"size"];
  [sizeColumn setMinWidth:48]; [sizeColumn setWidth:48];
  [sizeColumn setResizingMask:NSTableColumnUserResizingMask];
  [[sizeColumn dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200
  [[sizeColumn dataCell] setAlignment:NSTextAlignmentRight];
#else
  [[sizeColumn dataCell] setAlignment:NSRightTextAlignment];
#endif
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
  [[table_ enclosingScrollView] setHasHorizontalScroller:YES];
  [[table_ enclosingScrollView] setAutohidesScrollers:YES];
  [[table_ enclosingScrollView] setBorderType:NSNoBorder];
  [table_ setTarget:self]; [table_ setDoubleAction:@selector(openVideo:)];
  downloadFormat_=[[RDLPLibrary preferredFormat] copy];
  [middle setView:detail]; [self setDetailViewController:middle];
  AIViewController *inspector=[[[AIViewController alloc] init] autorelease];
  NSView *queue=[[[RDLPLayoutView alloc] initWithFrame:NSMakeRect(0,0,300,600)] autorelease];
  queue_=[RDLPLibraryViews tableInView:queue frame:[queue bounds] owner:self
    names:[NSArray arrayWithObjects:@"number",@"state",@"quality",@"title",@"playlist_title",nil]
    labels:[NSArray arrayWithObjects:@"",@"",@"Quality",@"Video",@"Playlist",nil]];
  NSTableColumn *numberColumn=[queue_ tableColumnWithIdentifier:@"number"];
  [numberColumn setMinWidth:36]; [numberColumn setMaxWidth:36]; [numberColumn setWidth:36];
  [numberColumn setResizingMask:NSTableColumnNoResizing];
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200
  [[numberColumn dataCell] setAlignment:NSTextAlignmentRight];
#else
  [[numberColumn dataCell] setAlignment:NSRightTextAlignment];
#endif
  NSTableColumn *queueState=[queue_ tableColumnWithIdentifier:@"state"];
  [queueState setMinWidth:24]; [queueState setMaxWidth:24]; [queueState setWidth:24];
  [queueState setResizingMask:NSTableColumnNoResizing];
  [queueState setDataCell:[[[RDLPStatusCell alloc] initImageCell:nil] autorelease]];
  NSArray *textColumns=[NSArray arrayWithObjects:@"quality",@"title",@"playlist_title",nil];
  NSEnumerator *columns=[textColumns objectEnumerator]; NSString *identifier;
  while((identifier=[columns nextObject])) {
    NSTableColumn *column=[queue_ tableColumnWithIdentifier:identifier];
    [column setWidth:[identifier isEqualToString:@"title"]?180:140]; [column setMinWidth:60];
    [column setResizingMask:NSTableColumnUserResizingMask];
    [[column dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
  }
  [queue_ setAllowsColumnReordering:NO];
  [queue_ setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
  NSScrollView *queueScroll=[queue_ enclosingScrollView];
  [queueScroll setBorderType:NSNoBorder]; [queueScroll setAutohidesScrollers:YES];
  NSMenu *jobMenu=[[[NSMenu alloc] initWithTitle:@"Queue Actions"] autorelease];
  [RDLPLibraryMenus addItemToMenu:jobMenu title:@"Play" action:@selector(openJob:) target:self];
  [RDLPLibraryMenus addItemToMenu:jobMenu title:@"Retry" action:@selector(retryQueueJob:) target:self];
  [RDLPLibraryMenus addItemToMenu:jobMenu title:@"Stop Download…" action:@selector(cancelQueueJob:) target:self];
  [RDLPLibraryMenus addItemToMenu:jobMenu title:@"Show Error…" action:@selector(showQueueError:) target:self];
  [RDLPLibraryMenus addItemToMenu:jobMenu title:@"Delete Download…" action:@selector(removeJob:) target:self];
  [queue_ setMenu:jobMenu]; [queue_ setTarget:self]; [queue_ setDoubleAction:@selector(openJob:)];
  [inspector setView:queue]; [self setInspectorViewController:inspector];
  [self setSidebarWidthLimits:AIMinMidMaxMake(150,200,260)];
  [self setInspectorWidthLimits:AIMinMidMaxMake(300,520,900)];
  [self setSplitViewAutosaveName:@"RetroDLPThreePaneDividers"];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RDLPLibraryDidChange object:library_];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshStatus:) name:RDLPLibraryStatusDidChange object:library_];
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
  [split setFrame:NSMakeRect(0,RDLPStatusBarHeight,bounds.size.width,
                            MAX(0,bounds.size.height-RDLPStatusBarHeight))];
  [split setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  [root addSubview:split];
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
  [[self window] setToolbar:toolbar]; [RDLPAppKit useExpandedToolbar:[self window]];
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
  NSArray *icons=[NSArray arrayWithObjects:[NSNumber numberWithInt:AIFADownload],
    [NSNumber numberWithInt:AIFAPlay],[NSNumber numberWithInt:AIFACookieBite],
    [NSNumber numberWithInt:AIFAListCheck],nil];
  NSToolbarItem *item=[[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
  RDLPToolbarButton *view=[[[RDLPToolbarButton alloc] initWithFrame:NSMakeRect(0,0,40,32)] autorelease];
  [view setTitle:[labels objectAtIndex:index]]; [view setTag:(NSInteger)index];
  [view setImage:[RDLPLibraryViews toolbarIcon:(AIFontAwesomeIcon)[[icons objectAtIndex:index] intValue] window:[self window]]];
  [view setCaretImage:[RDLPAppKit controlIcon:AIFACaretDown style:AIFontAwesomeStyleSolid iconSize:8 canvasSize:10 scale:[RDLPAppKit backingScaleForWindow:[self window]]]];
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
{ return [RDLPLibraryMenus menuForMenuBarTitle:title target:self]; }
- (void)downloadFromMenu:(NSMenuItem *)sender;
{
  if(![self validateMenuItem:sender]) return;
  if(context_==2 && [self selectedJob]) { [self retryQueueJob:sender]; return; }
  NSMenuItem *command=[[[NSMenuItem alloc] initWithTitle:@"" action:@selector(chooseDownload:) keyEquivalent:@""] autorelease];
  [command setTag:[self hasTargetVideo]?0:5]; [self chooseDownload:command];
}
- (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier;
{ return [RDLPLibraryMenus menuForToolbarIdentifier:identifier target:self]; }
- (void)menuNeedsUpdate:(NSMenu *)menu;
{ [RDLPLibraryMenus updateMenu:menu target:self]; }
- (NSDictionary *)contextPlaylist;
{ return [self hasTargetVideo]?[self targetPlaylist]:(context_==2?[self targetPlaylist]:[self selectedPlaylist]); }
- (NSString *)selectionPlayFile;
{ return [self hasTargetVideo]?([self playable:[self targetJob]]?[library_ fileForJob:[self targetJob]]:nil):[self playFileForPlaylist:[self contextPlaylist]]; }
- (void)playSelection:(id)sender;
{
  NSString *path=[self selectionPlayFile]; if(!path) return;
  if([RDLPAppKit preferredPlaybackApplication:path]) [RDLPAppKit openPreferredPlayback:path]; else [self revealSelection:sender];
}
- (void)playSelectionInDefaultApplication:(id)sender;
{ (void)sender; NSString *path=[self selectionPlayFile]; if(path) [RDLPAppKit openDefaultApplication:path]; }
- (void)playSelectionInVLC:(id)sender;
{ (void)sender; NSString *path=[self selectionPlayFile]; if(path) [RDLPAppKit openInVLC:path]; }
- (void)revealSelection:(id)sender;
{ if([self hasTargetVideo]) [self revealTarget:sender]; else if([self contextPlaylist]) [self revealPlaylistFolder:sender]; }
- (void)toolbarDefault:(id)sender;
{
  if([[self window] attachedSheet]) return;
  if([sender isKindOfClass:[NSToolbarItem class]] && ![(RDLPToolbarButton *)[(NSToolbarItem *)sender view] isDefaultEnabled]) return;
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
  if(index>0 && index<4) { [self saveDownloadQuality:[[RDLPLibrary qualityFormats] objectAtIndex:index-1]]; return; }
  if(index==0) {
    NSDictionary *playlist=[self contextPlaylist];
    NSMutableDictionary *request=[NSMutableDictionary dictionaryWithObjectsAndKeys:[playlist objectForKey:@"id"],@"playlist",[playlist objectForKey:@"title"],@"title",downloadFormat_,@"format",nil];
    if(!all) [request setObject:[self targetVideoID] forKey:@"video"];
    if(all) [self requestBulk:request]; else [self enqueueRequest:request]; return;
  }
  downloadSheet_=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,500,220) styleMask:AIWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [downloadSheet_ setTitle:@"Custom Download Quality"];
  NSView *view=[downloadSheet_ contentView];
  [[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,182,460,28) editable:NO] setStringValue:@"Choose the quality for future downloads."];
  customSummary_=[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,146,460,32) editable:NO];
  [[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,115,460,24) editable:NO] setStringValue:@"Format expression (for example, 18 or 136+140)"];
  customFormat_=[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,83,460,24) editable:YES]; [customFormat_ setStringValue:downloadFormat_]; [customFormat_ setDelegate:(id)self];
  customError_=[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,47,460,28) editable:NO];
  NSButton *cancel=[RDLPLibraryViews buttonInView:view title:@"Cancel" action:@selector(dismissDownload:) target:self frame:NSMakeRect(240,10,105,28)]; [cancel setTag:0]; [cancel setKeyEquivalent:@"\033"];
  NSButton *download=[RDLPLibraryViews buttonInView:view title:@"Save" action:@selector(dismissDownload:) target:self frame:NSMakeRect(350,10,130,28)]; [download setTag:1]; [download setKeyEquivalent:@"\r"];
  [self updateCustomSummary];
  [RDLPAppKit beginSheet:downloadSheet_ forWindow:[self window] delegate:self didEnd:@selector(downloadSheetDidEnd:returnCode:contextInfo:)];
  [downloadSheet_ makeFirstResponder:customFormat_];
}
- (void)saveDownloadQuality:(NSString *)format;
{
  if(![RDLPLibrary savePreferredFormat:format]) return;
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
    if(![RDLPLibrary validFormat:format]) { [customError_ setStringValue:@"Enter a valid format such as 18 or 136+140."]; return; }
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
  [sidebarItems_ release]; [downloadPolicy_ release]; [library_ release]; [playlists_ release]; [rows_ release]; [videoRows_ release]; [addedPlaylists_ release]; [accountPlaylists_ release]; [adhocPlaylist_ release]; [selectedPlaylist_ release];
  [addSheet_ release]; [downloadSheet_ release]; [downloadRequest_ release]; [downloadFormat_ release]; [queueRows_ release]; [toolbarItems_ release]; [confirmation_ release]; [confirmationRequest_ release]; [super dealloc];
}
- (NSDictionary *)selectedRow;
{ NSInteger row=[table_ selectedRow]; return row>=0 && (NSUInteger)row<[rows_ count]?[rows_ objectAtIndex:(NSUInteger)row]:nil; }
- (NSDictionary *)selectedJob;
{ NSInteger row=[queue_ selectedRow]; return row>=0 && (NSUInteger)row<[queueRows_ count]?[queueRows_ objectAtIndex:(NSUInteger)row]:nil; }

- (NSDictionary *)selectedPlaylist;
{ return [(RDLPLibraryRows *)playlists_ playlistForID:selectedPlaylist_]; }
- (NSDictionary *)jobForEntry:(NSDictionary *)entry;
{ return [downloadPolicy_ representativeJobForEntry:entry playlist:selectedPlaylist_ jobs:[library_ jobsForPlaylist:selectedPlaylist_ video:[entry objectForKey:@"video_id"]]]; }
- (NSString *)statusForJob:(NSDictionary *)job;
{ return [downloadPolicy_ statusForJob:job]; }

- (BOOL)playable:(NSDictionary *)job;
{ return [downloadPolicy_ playable:job]; }
- (void)refresh:(id)sender;
{
  (void)sender; if(refreshing_) return; refreshing_=YES;
  NSString *key=mode_==0?@"position":@"id";
  NSString *selection=[[[self selectedRow] objectForKey:key] copy];
  NSString *queueSelection=[[[self selectedJob] objectForKey:@"id"] copy];
  NSString *oldGroup=selectedPlaylist_?[RDLPLibraryViews groupForPlaylist:[self selectedPlaylist]]:nil;
  [playlists_ release]; playlists_=[[library_ playlists] copy];
  [addedPlaylists_ release]; addedPlaylists_=[[library_ playlistIDsFromAccount:NO] copy];
  [accountPlaylists_ release]; accountPlaylists_=[[library_ playlistIDsFromAccount:YES] copy];
  [adhocPlaylist_ release]; adhocPlaylist_=[[library_ adhocPlaylist] retain];
  if(mode_==0 && ![self selectedPlaylist]) { mode_=1; [selectedPlaylist_ release]; selectedPlaylist_=nil; [selection release]; selection=nil; }
  [rows_ release]; rows_=[(mode_==0?[library_ entriesForPlaylist:selectedPlaylist_]:[library_ jobsForPlaylist:nil completedOnly:YES]) copy];
  [queueRows_ release]; queueRows_=[[library_ queueRows] copy];
  [videoRows_ release]; videoRows_=[[RDLPVideoRows alloc] initWithRows:rows_ library:library_ playlist:mode_==0?selectedPlaylist_:nil];
  [sidebar_ reloadData]; [table_ reloadData]; [queue_ reloadData];
  if(!sidebarLoaded_) {
    [sidebar_ expandItem:@"System"]; [sidebar_ expandItem:@"Added Playlists"]; [sidebar_ expandItem:@"My Playlists"]; sidebarLoaded_=YES;
  } else if(selectedPlaylist_ && ![oldGroup isEqualToString:[RDLPLibraryViews groupForPlaylist:[self selectedPlaylist]]]) {
    [sidebar_ expandItem:[RDLPLibraryViews groupForPlaylist:[self selectedPlaylist]]];
  }
  id selectedItem=mode_==0?(selectedPlaylist_?[sidebarItems_ objectForKey:selectedPlaylist_]:nil):@"All Downloads";
  NSInteger selectedSidebar=[sidebar_ rowForItem:selectedItem];
  if(selectedSidebar>=0) [sidebar_ selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)selectedSidebar] byExtendingSelection:NO];
  else [sidebar_ deselectAll:nil];
  [RDLPLibraryViews restoreSelection:table_ rows:rows_ key:mode_==0?@"position":@"id" value:selection];
  [RDLPLibraryViews restoreSelection:queue_ rows:queueRows_ key:@"id" value:queueSelection];
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
  if(![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
  /* Recovery/export maintains this file. Toolbar validation only needs a count. */
  return [[library_ jobsForPlaylist:[playlist objectForKey:@"id"] completedOnly:YES] count]?path:nil;
}
- (NSString *)targetPlaylistFolder;
{
  NSDictionary *playlist=[self selectedPlaylist];
  NSString *path=playlist?[[library_ playlistFile:playlist] stringByDeletingLastPathComponent]:nil;
  BOOL directory=NO;
  return path && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && directory?path:nil;
}
- (NSArray *)missingPlanForPlaylist:(NSString *)playlist format:(NSString *)format;
{ return [library_ missingPlanForPlaylist:playlist format:format];
}
- (NSArray *)syncPlan;
{
  NSMutableArray *inputs=[NSMutableArray array]; NSEnumerator *e=[playlists_ objectEnumerator]; NSDictionary *playlist;
  while((playlist=[e nextObject])) if(![[playlist objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID] && ![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]]) [inputs addObject:[playlist objectForKey:@"service_id"]];
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
  [view setDefaultEnabled:enabled && ![[self window] attachedSheet]];
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
  NSDictionary *playlist=[self contextPlaylist], *job=[self targetJob];
  BOOL video=[self hasTargetVideo], enabled=YES;
  BOOL delete=video && [self playable:job];
  AIFontAwesomeIcon icon=AIFADownload; NSString *tip=nil;
  if(video) {
    icon=delete?AIFATrash:([self canCancel:job]?AIFAHourglass:AIFADownload);
    if(delete) enabled=[self canRemove:job];
    tip=[NSString stringWithFormat:@"%@ — %@ · %@",delete?@"Delete downloaded video…":([self canCancel:job]?@"Show in Queue":@"Download video"),job?[job objectForKey:@"title"]:[[self selectedRow] objectForKey:@"title"],[RDLPLibrary qualityLabelForFormat:job?[job objectForKey:@"format"]:[self targetFormat]]];
  } else if(playlist) {
    icon=AIFAArrowsRotate;
    enabled=![[playlist objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID] && ![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]];
    tip=[NSString stringWithFormat:@"Sync ‘%@’",[playlist objectForKey:@"title"]];
  } else { icon=(AIFontAwesomeIcon)0x2b; tip=@"Add a video…"; }
  [self setToolbarItem:@"download" title:video?(delete?@"Delete":@"Download"):(playlist?@"Sync":@"Add Video") tip:tip icon:[RDLPLibraryViews toolbarIcon:icon window:[self window]] enabled:enabled];
  NSString *path=[self selectionPlayFile], *application=[RDLPAppKit preferredPlaybackApplication:path];
  NSString *object=video?@"video":@"playlist";
  NSString *playTip=path?(application?[NSString stringWithFormat:@"Play %@ in %@",object,[[[NSFileManager defaultManager] displayNameAtPath:application] stringByDeletingPathExtension]]:[NSString stringWithFormat:@"Reveal %@ in Finder",object]):@"Select a downloaded video or playlist to play";
  [self setToolbarItem:@"play" title:@"Play" tip:playTip icon:[RDLPAppKit youTubeIconForScale:[RDLPAppKit backingScaleForWindow:[self window]]] enabled:path!=nil];
  BOOL cookies=[[library_ cookieStatus] isEqualToString:@"Imported"];
  [self setToolbarItem:@"cookies" title:@"Cookies" tip:[[library_ cookieStatus] isEqualToString:@"Not Imported"]?@"Import cookies…":@"Replace cookies…" icon:[RDLPLibraryViews toolbarIcon:cookies?AIFACookie:AIFACookieBite window:[self window]] enabled:![library_ isBusy]];
  [self setToolbarItem:@"downloads" title:@"Queue" tip:[self isInspectorCollapsed]?@"Show Queue. Right-click for queue actions.":@"Hide Queue. Right-click for queue actions." icon:[RDLPLibraryViews toolbarIcon:AIFAListCheck window:[self window]] enabled:YES];
}
- (void)updateControls;
{ [self updateToolbar]; [self refreshStatus:nil]; }
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
}

- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item;
{
  (void)outline;
  if(!item) return 3; if([item isEqual:@"System"]) return adhocPlaylist_?2:1;
  return (NSInteger)[([item isEqual:@"My Playlists"]?accountPlaylists_:addedPlaylists_) count];
}
- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item;
{
  (void)outline;
  if(!item) return [[NSArray arrayWithObjects:@"System",@"Added Playlists",@"My Playlists",nil] objectAtIndex:(NSUInteger)index];
  if([item isEqual:@"System"]) {
    if(index==0) return @"All Downloads";
    NSString *key=[adhocPlaylist_ objectForKey:@"id"]; if(![sidebarItems_ objectForKey:key]) [sidebarItems_ setObject:key forKey:key]; return [sidebarItems_ objectForKey:key];
  }
  NSDictionary *playlist=[([item isEqual:@"My Playlists"]?accountPlaylists_:addedPlaylists_) objectAtIndex:(NSUInteger)index];
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
  if([RDLPLibraryViews isSidebarGroup:item] || [item isEqual:@"All Downloads"]) return item;
  NSDictionary *playlist=[library_ playlistForID:item];
  return playlist?[NSString stringWithFormat:@"%@ (%@)",[playlist objectForKey:@"title"],[playlist objectForKey:@"count"]]:@"";
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
  NSDictionary *job=entry;
  if(!queue && ![key isEqualToString:@"state"]) return [entry objectForKey:key];
  if(queue && [key isEqualToString:@"number"]) return [NSNumber numberWithLong:(long)row+1];
  if(queue && [key isEqualToString:@"quality"]) {
    NSString *format=[job objectForKey:@"format"], *actual=[job objectForKey:@"actual_format"];
    NSString *label=[RDLPLibrary qualityLabelForFormat:format];
    return [actual length] && ![actual isEqualToString:format]?[label stringByAppendingFormat:@" → %@",[RDLPLibrary qualityLabelForFormat:actual]]:label;
  }
  if([key isEqualToString:@"state"]) {
    NSString *status=queue?[self statusForJob:job]:[entry objectForKey:@"status"]; AIFontAwesomeIcon icon=0;
    if([status isEqualToString:@"Downloaded"]) icon=AIFACircleCheck;
    else if([status isEqualToString:@"Downloading"]) icon=AIFAArrowDown;
    else if([status isEqualToString:@"Queued"]) icon=AIFAClock;
    else if([status isEqualToString:@"Cancelled"]) icon=AIFACirclePause;
    else if(![status isEqualToString:@"Not downloaded"]) icon=AIFATriangleExclamation;
    return icon?[AIFontAwesome imageForIcon:icon style:AIFontAwesomeStyleSolid iconSize:12 canvasSize:16 scale:[RDLPAppKit backingScaleForWindow:[self window]]]:nil;
  }
  return [entry objectForKey:key];
}
- (void)tableView:(NSTableView *)view willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row;
{
  if([[column identifier] isEqualToString:@"state"]) {
    NSDictionary *entry=[(view==queue_?queueRows_:videoRows_) objectAtIndex:(NSUInteger)row];
    [cell setRepresentedObject:view==queue_?[self statusForJob:entry]:[entry objectForKey:@"status"]];
  }
}
- (NSString *)tableView:(NSTableView *)view toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column row:(NSInteger)row mouseLocation:(NSPoint)point;
{
  (void)cell; (void)rect; (void)point;
  NSDictionary *entry=[(view==queue_?queueRows_:videoRows_) objectAtIndex:(NSUInteger)row];
  if(view==table_) return [entry objectForKey:[[column identifier] isEqualToString:@"title"]?@"tooltip":([[column identifier] isEqualToString:@"state"]?@"status_tooltip":[column identifier])];
  if(![[column identifier] isEqualToString:@"state"]) {
    id value=[self tableView:view objectValueForTableColumn:column row:row];
    return [value isKindOfClass:[NSString class]]?value:[value description];
  }
  NSDictionary *job=entry;
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
  if(visibilityAction==@selector(togglePlaylists:)) [item setTitle:[self isSidebarCollapsed]?@"Show Playlists":@"Hide Playlists"];
  if(visibilityAction==@selector(toggleDownloads:)) [item setTitle:[self isInspectorCollapsed]?@"Show Download Queue":@"Hide Download Queue"];
  if([[item menu] title] && [[[item menu] title] isEqualToString:@"File"]) {
    NSString *object=[self hasTargetVideo]?@"Video":@"Playlist";
    if(visibilityAction==@selector(playSelectionInDefaultApplication:)) [item setTitle:[NSString stringWithFormat:@"Play %@ in Default App",object]];
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
  if(action==@selector(sync:)) return playlist && ![[playlist objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID] && ![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]];
  if(action==@selector(syncAll:)) return [library_ hasPlaylistsToSync];
  if(action==@selector(chooseDownload:)) {
    BOOL all=[item tag]>=5; NSUInteger index=(NSUInteger)[item tag]%5;
    if(index>0) {
      NSString *format=index<4?[[RDLPLibrary qualityFormats] objectAtIndex:index-1]:nil;
      BOOL custom=![[RDLPLibrary qualityFormats] containsObject:downloadFormat_];
      [item setState:(index==4?custom:[format isEqualToString:downloadFormat_])?NSOnState:NSOffState];
      return YES;
    }
    [item setState:NSOffState];
    playlist=[self contextPlaylist];
    if(!playlist || (!all && ![self hasTargetVideo])) return NO;
    NSString *format=downloadFormat_;
    if(all) return [library_ hasMissingEntriesForPlaylist:[playlist objectForKey:@"id"] format:format];
    NSDictionary *matching=[self jobForPlaylist:[playlist objectForKey:@"id"] video:[self targetVideoID] format:format];
    return !matching || [self canRetry:matching] || [self canDownloadAgain:matching];
  }
  if(action==@selector(retryTarget:)) return [self canRetry:job];
  if(action==@selector(againTarget:)) return [self canDownloadAgain:job];
  if(action==@selector(cancelTarget:)) return [self canCancel:job];
  if(action==@selector(removeTarget:)) return [self canRemove:job];
  if(action==@selector(showTargetInQueue:)) return job!=nil;
  if(action==@selector(playSelection:)) return [RDLPAppKit preferredPlaybackApplication:[self selectionPlayFile]]!=nil;
  if(action==@selector(playSelectionInDefaultApplication:)) return [RDLPAppKit defaultApplication:[self selectionPlayFile]]!=nil;
  if(action==@selector(playSelectionInVLC:)) return [self selectionPlayFile]!=nil && [RDLPAppKit VLCApplication]!=nil;
  if(action==@selector(revealSelection:)) return [self hasTargetVideo]?[self playable:job]:([self contextPlaylist]!=nil && [self targetPlaylistFolder]!=nil);
  if(action==@selector(playVideoInVLC:)) return [self playable:job] && [RDLPAppKit VLCApplication]!=nil;
  if(action==@selector(playPlaylistInVLC:)) return [self playFileForPlaylist:[self contextPlaylist]]!=nil && [RDLPAppKit VLCApplication]!=nil;
  if(action==@selector(playTargetVideo:)) return [self playable:job] && [RDLPAppKit defaultApplication:[library_ fileForJob:job]]!=nil;
  if(action==@selector(playTargetPlaylist:)) return [RDLPAppKit defaultApplication:[self playFileForPlaylist:[self contextPlaylist]]]!=nil;
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
  if(action==@selector(openJob:)) return [self playable:queued] && [RDLPAppKit preferredPlaybackApplication:[library_ fileForJob:queued]]!=nil;
  if(action==@selector(removeDownload:)) return [self canRemove:mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow]];
  if(action==@selector(removePlaylist:)) return [self canRemovePlaylist:[self contextPlaylist]];
  if(action==@selector(playPlaylist:)) return [RDLPAppKit preferredPlaybackApplication:[self playFileForPlaylist:[self selectedPlaylist]]]!=nil;
  return YES;
}
- (void)addPlaylist:(id)sender;
{
  (void)sender; if(addSheet_ || [[self window] attachedSheet]) return;
  addingVideo_=NO;
  addSheet_=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,460,135) styleMask:AIWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [addSheet_ setTitle:@"Add Playlist"];
  NSView *view=[addSheet_ contentView]; [[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,95,420,24) editable:NO] setStringValue:@"Playlist URL or ID"];
  input_=[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,62,420,24) editable:YES];
  NSButton *cancel=[RDLPLibraryViews buttonInView:view title:@"Cancel" action:@selector(dismissAdd:) target:self frame:NSMakeRect(230,15,100,28)]; [cancel setTag:0]; [cancel setKeyEquivalent:@"\033"];
  NSButton *add=[RDLPLibraryViews buttonInView:view title:@"Add Playlist" action:@selector(dismissAdd:) target:self frame:NSMakeRect(335,15,110,28)]; [add setTag:1]; [add setKeyEquivalent:@"\r"];
  [RDLPAppKit beginSheet:addSheet_ forWindow:[self window] delegate:self didEnd:@selector(addSheetDidEnd:returnCode:contextInfo:)];
  [addSheet_ makeFirstResponder:input_];
}
- (void)addVideo:(id)sender;
{
  (void)sender;
  if([[self window] attachedSheet] || addSheet_) return;
  addSheet_=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,460,135) styleMask:AIWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [addSheet_ setTitle:@"Add Video"];
  NSView *view=[addSheet_ contentView]; [[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,95,420,24) editable:NO] setStringValue:@"YouTube video URL or ID"];
  addingVideo_=YES; input_=[RDLPLibraryViews fieldInView:view frame:NSMakeRect(20,62,420,24) editable:YES];
  NSButton *cancel=[RDLPLibraryViews buttonInView:view title:@"Cancel" action:@selector(dismissAdd:) target:self frame:NSMakeRect(230,15,100,28)]; [cancel setTag:0]; [cancel setKeyEquivalent:@"\033"];
  NSButton *add=[RDLPLibraryViews buttonInView:view title:@"Add Video" action:@selector(dismissAdd:) target:self frame:NSMakeRect(335,15,110,28)]; [add setTag:1]; [add setKeyEquivalent:@"\r"];
  [RDLPAppKit beginSheet:addSheet_ forWindow:[self window] delegate:self didEnd:@selector(addSheetDidEnd:returnCode:contextInfo:)]; [addSheet_ makeFirstResponder:input_];
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
  if([[self window] attachedSheet] || confirmation_) return;
  confirmationRequest_=[request copy]; confirmation_=[[NSAlert alloc] init];
  [confirmation_ setMessageText:title]; [confirmation_ setInformativeText:detail];
  [confirmation_ addButtonWithTitle:@"Cancel"]; [confirmation_ addButtonWithTitle:action];
  [RDLPAppKit beginAlertSheet:confirmation_ forWindow:[self window] delegate:self didEnd:@selector(confirmationDidEnd:returnCode:contextInfo:)];
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
      NSString *path=[RDLPAppKit chooseCookieFile]; if(!path) return;
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
  NSString *title=[NSString stringWithFormat:@"%@ ‘%@’ — %@?",remove?@"Delete download for":@"Cancel download for",[job objectForKey:@"title"],[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]]];
  [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:remove?@"remove":@"cancel",@"operation",[job objectForKey:@"id"],@"job",nil] title:title detail:remove?@"This deletes this download and its partial files. Playlist membership and other downloaded qualities are retained.":@"Retrying this job restarts the transfer; it does not resume from where it stopped." action:remove?@"Delete Download":@"Cancel Download"];
}
- (BOOL)canRemovePlaylist:(NSDictionary *)playlist;
{
  if(!playlist || [[playlist objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID] || [library_ isBusy]) return NO;
  return ![library_ hasBlockingJobsForPlaylist:[playlist objectForKey:@"id"]];
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
  NSDictionary *job=[library_ jobForPlaylist:playlist video:video format:format];
  if(!job) {
    [library_ enqueuePlaylist:playlist video:video format:format];
    [self refresh:nil]; [self showJobInQueue:[self jobForPlaylist:playlist video:video format:format]];
  } else if([self canDownloadAgain:job] || (allowRetry && [self canRetry:job])) [self retryAndRevealJob:job];
}
- (void)enqueueRequest:(NSDictionary *)request;
{
  NSString *format=[request objectForKey:@"format"];
  if(![RDLPLibrary savePreferredFormat:format]) return;
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
  NSString *detail=[NSString stringWithFormat:@"Playlist: %@\nQuality: %@\nExisting failed or cancelled jobs will not be retried.",[request objectForKey:@"title"]?:playlist,[RDLPLibrary qualityLabelForFormat:format]];
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
  } else [self addVideo:sender];
}
- (void)sync:(id)sender;
{ (void)sender; NSDictionary *playlist=[self contextPlaylist]; if(playlist && ![[playlist objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID]) [library_ syncPlaylistInput:[playlist objectForKey:@"service_id"]]; }
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
  if(![[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/yt-dlp/yt-dlp/wiki/Extractors"]]) [RDLPAppKit showAlert:@"Could not open the cookie export guide in your browser."];
}
- (void)importCookies:(id)sender;
{
  (void)sender; if([library_ isBusy] || [[self window] attachedSheet]) return;
  if(![[library_ cookieStatus] isEqualToString:@"Not Imported"]) { [self replaceCookies:nil]; return; }
  NSString *path=[RDLPAppKit chooseCookieFile]; if(path) [library_ importCookies:path];
}
- (void)replaceCookies:(id)sender;
{
  (void)sender; if([library_ isBusy] || [[self window] attachedSheet]) return;
  NSString *path=[RDLPAppKit chooseCookieFile]; if(!path) return;
  [self confirmRequest:[NSDictionary dictionaryWithObjectsAndKeys:@"import",@"operation",path,@"path",nil] title:@"Replace imported cookies?" detail:@"Replace the app’s working cookie copy with the selected file. The original exported files are retained." action:@"Replace"];
}
- (void)clearCookies:(id)sender;
{
  (void)sender; if([library_ isBusy] || [[library_ cookieStatus] isEqualToString:@"Not Imported"]) return;
  [self confirmRequest:[NSDictionary dictionaryWithObject:@"clearCookies" forKey:@"operation"] title:@"Remove imported cookies?" detail:@"Remove the app’s working cookie copy. The original exported file is retained." action:@"Remove"];
}
- (void)showQueueError:(id)sender;
{ (void)sender; NSString *error=[[self selectedJob] objectForKey:@"error"]; if([error length]) [RDLPAppKit showAlert:error]; }
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
  [RDLPLibraryViews restoreSelection:queue_ rows:queueRows_ key:@"id" value:key];
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
{ (void)sender; NSDictionary *job=[self targetJob]; if([self playable:job]) [RDLPAppKit openDefaultApplication:[library_ fileForJob:job]]; }
- (void)playTargetPlaylist:(id)sender;
{ (void)sender; NSString *path=[self playFileForPlaylist:[self contextPlaylist]]; if(path) [RDLPAppKit openDefaultApplication:path]; }
- (void)playVideoInVLC:(id)sender;
{ (void)sender; NSDictionary *job=[self targetJob]; if([self playable:job]) [RDLPAppKit openInVLC:[library_ fileForJob:job]]; }
- (void)playPlaylistInVLC:(id)sender;
{ (void)sender; [RDLPAppKit openInVLC:[self playFileForPlaylist:[self contextPlaylist]]]; }
- (void)revealTarget:(id)sender;
{ (void)sender; NSDictionary *job=[self targetJob]; if([self playable:job]) [RDLPAppKit revealInFinder:[library_ fileForJob:job]]; }
- (void)revealPlaylistFolder:(id)sender;
{ (void)sender; NSString *path=[self targetPlaylistFolder]; if(path) [RDLPAppKit revealInFinder:path]; }
- (void)openDownloadsFolder:(id)sender;
{ (void)sender; [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:[library_ downloadsDirectory]]]; }
- (void)openVideo:(id)sender;
{ (void)sender; NSDictionary *job=mode_==0?[self jobForEntry:[self selectedRow]]:[self selectedRow]; if([self playable:job]) [RDLPAppKit openPreferredPlayback:[library_ fileForJob:job]]; }
- (void)openJob:(id)sender;
{ (void)sender; if([self playable:[self selectedJob]]) [RDLPAppKit openPreferredPlayback:[library_ fileForJob:[self selectedJob]]]; }
- (void)playPlaylist:(id)sender;
{ (void)sender; NSString *path=[self playFileForPlaylist:[self selectedPlaylist]]; if(path) [RDLPAppKit openPreferredPlayback:path]; }
@end
