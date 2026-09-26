#import "RDLPQueueWindowController.h"
#import "RDLPLibraryWindowController.h"
#import "RDLPLibraryViews.h"
#import "RDLPToolbarButton.h"

@interface NSObject (RDLPQueueActions)
- (void)tableWasUsed:(NSTableView *)table;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end

@implementation RDLPQueueWindowController
- (id)initWithLibrary:(RDLPLibrary *)library owner:(id)owner;
{
  self=[super initWithWindowNibName:@"DownloadQueue"];
  if(self) { library_=[library retain]; owner_=owner; toolbarItems_=[[NSMutableDictionary alloc] init]; }
  return self;
}
- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [queue_ setDelegate:nil]; [queue_ setDataSource:nil];
  [toolbarItems_ release]; [library_ release]; [super dealloc];
}
- (NSTableView *)tableView; { [self window]; return queue_; }
- (void)loadWindow;
{
  NSWindow *window=[[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,400)
    styleMask:RDLPTexturedWindowStyleMask backing:NSBackingStoreBuffered defer:NO] autorelease];
  [window setTitle:@"Download Queue"]; [window setReleasedWhenClosed:NO];
  [window setMinSize:NSMakeSize(480,300)]; [window center];
  [self setWindow:window]; [self setShouldCascadeWindows:NO];
}
- (void)windowDidLoad;
{
  [super windowDidLoad];
  NSWindow *window=[self window];
  NSRect bounds=[[window contentView] bounds];
  NSView *root=[[[RDLPLayoutView alloc] initWithFrame:bounds] autorelease];
  [root setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable]; [window setContentView:root];
  NSView *queue=[[[RDLPLayoutView alloc] initWithFrame:NSMakeRect(0,32,640,368)] autorelease];
  queue_=[RDLPLibraryViews tableInView:queue frame:[queue bounds] owner:owner_
    names:[NSArray arrayWithObjects:@"number",@"state",@"quality",@"title",@"playlist_title",nil]
    labels:[NSArray arrayWithObjects:@"",@"",@"Quality",@"Video",@"Playlist",nil]];
  NSTableColumn *numberColumn=[queue_ tableColumnWithIdentifier:@"number"];
  [numberColumn setMinWidth:36]; [numberColumn setMaxWidth:36]; [numberColumn setWidth:36];
  [numberColumn setResizingMask:NSTableColumnNoResizing];
  [[numberColumn dataCell] setAlignment:RDLPTextAlignmentRight];
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
  [RDLPLibraryMenus addItemToMenu:jobMenu title:@"Play" action:@selector(openJob:) target:owner_];
  [RDLPLibraryMenus addItemToMenu:jobMenu title:@"Retry" action:@selector(retryQueueJob:) target:owner_];
  [RDLPLibraryMenus addItemToMenu:jobMenu title:@"Stop Download…" action:@selector(cancelQueueJob:) target:owner_];
  [RDLPLibraryMenus addItemToMenu:jobMenu title:@"Show Error…" action:@selector(showQueueError:) target:owner_];
  [RDLPLibraryMenus addItemToMenu:jobMenu title:@"Delete Download…" action:@selector(removeJob:) target:owner_];
  [queue_ setMenu:jobMenu]; [queue_ setTarget:owner_]; [queue_ setDoubleAction:@selector(openJob:)];

  [queue setFrame:NSMakeRect(0,32,bounds.size.width,MAX(0,bounds.size.height-32))];
  [queue setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable]; [root addSubview:queue];
  status_=[RDLPLibraryViews fieldInView:root frame:NSMakeRect(12,7,MAX(0,bounds.size.width-190),18) editable:NO];
  [status_ setAutoresizingMask:NSViewWidthSizable]; [[status_ cell] setLineBreakMode:NSLineBreakByTruncatingTail];
  progress_=[[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(bounds.size.width-160,10,140,12)] autorelease];
  [progress_ setMinValue:0]; [progress_ setAutoresizingMask:NSViewMinXMargin]; [root addSubview:progress_];
  NSToolbar *toolbar=[[[NSToolbar alloc] initWithIdentifier:@"RetroDLPQueueToolbar"] autorelease];
  [toolbar setDelegate:(id)self]; [toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
  [window setToolbar:toolbar]; [RDLPAppKit useExpandedToolbar:window];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshIcons:)
    name:@"NSWindowDidChangeBackingPropertiesNotification" object:window];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshIcons:)
    name:NSWindowDidChangeScreenNotification object:window];
  [self refreshStatus];
}
- (void)showWindow:(id)sender;
{
  [super showWindow:sender];
  if(!didRestoreFrame_) {
    [[self window] setFrameUsingName:@"RetroDLPDownloadQueueWindow"];
    [self setWindowFrameAutosaveName:@"RetroDLPDownloadQueueWindow"]; didRestoreFrame_=YES;
  }
  if([[self window] isMiniaturized]) [[self window] deminiaturize:sender];
  [[self window] makeKeyAndOrderFront:sender];
  [self updateControls];
}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
{ (void)toolbar; return [NSArray arrayWithObjects:@"retry",@"stop",NSToolbarFlexibleSpaceItemIdentifier,@"error",@"delete",nil]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
{ return [self toolbarDefaultItemIdentifiers:toolbar]; }
- (NSArray *)actions;
{ return [NSArray arrayWithObjects:@"retryQueueJob:",@"cancelQueueJob:",@"showQueueError:",@"removeJob:",nil]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)insert;
{
  (void)toolbar;
  NSArray *ids=[NSArray arrayWithObjects:@"retry",@"stop",@"error",@"delete",nil];
  NSUInteger index=[ids indexOfObject:identifier]; if(index==NSNotFound) return nil;
  NSArray *labels=[NSArray arrayWithObjects:@"Retry",@"Stop",@"Error",@"Delete",nil];
  NSToolbarItem *item=[[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
  RDLPToolbarButton *button=[[[RDLPToolbarButton alloc] initWithFrame:NSMakeRect(0,0,40,32)] autorelease];
  [button setTitle:[labels objectAtIndex:index]]; [button setTag:(NSInteger)index];
  [button setTarget:self]; [button setAction:@selector(performQueueAction:)];
  [item setLabel:[labels objectAtIndex:index]]; [item setPaletteLabel:[labels objectAtIndex:index]];
  [item setView:button]; [item setMinSize:NSMakeSize(40,32)]; [item setMaxSize:NSMakeSize(40,32)];
  [item setAutovalidates:NO];
  if(insert) [toolbarItems_ setObject:item forKey:identifier];
  return item;
}
- (void)performQueueAction:(id)sender;
{
  [owner_ tableWasUsed:queue_];
  SEL action=NSSelectorFromString([[self actions] objectAtIndex:(NSUInteger)[sender tag]]);
  NSMenuItem *probe=[[[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:@""] autorelease];
  if([owner_ validateMenuItem:probe]) [owner_ performSelector:action withObject:sender];
}
- (void)refreshIcons:(id)sender; { (void)sender; [self updateControls]; [queue_ reloadData]; }
- (void)updateControls;
{
  AIFontAwesomeIcon icons[]={AIFARotateRight,AIFAPause,AIFACircleExclamation,AIFATrash};
  NSEnumerator *items=[toolbarItems_ objectEnumerator]; NSToolbarItem *item;
  while((item=[items nextObject])) {
    RDLPToolbarButton *button=(RDLPToolbarButton *)[item view]; NSUInteger index=(NSUInteger)[button tag];
    SEL action=NSSelectorFromString([[self actions] objectAtIndex:index]);
    NSMenuItem *probe=[[[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:@""] autorelease];
    [button setDefaultEnabled:[owner_ validateMenuItem:probe]];
    [button setImage:[RDLPLibraryViews toolbarIcon:icons[index] window:[self window]]];
    [button setToolTip:[item label]];
  }
}
- (void)refreshStatus;
{
  [status_ setStringValue:[library_ status]]; [status_ setToolTip:[library_ status]];
  NSDictionary *progress=[library_ activityProgress]; BOOL active=[[progress objectForKey:@"active"] boolValue];
  double expected=[[progress objectForKey:@"expected"] doubleValue];
  [progress_ setHidden:!active]; [progress_ setIndeterminate:expected<=0];
  if(active && expected<=0) [progress_ startAnimation:nil]; else [progress_ stopAnimation:nil];
  [progress_ setMaxValue:MAX(expected,1)]; [progress_ setDoubleValue:MIN(expected,[[progress objectForKey:@"completed"] doubleValue])];
}
@end
