#import "LibraryWindow.h"
#import "XPAppKit.h"
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
  NSTableView *t=[[[NSTableView alloc] initWithFrame:[scroll bounds]] autorelease]; unsigned int i;
  for(i=0;i<[names count];++i) {
    NSTableColumn *c=[[[NSTableColumn alloc] initWithIdentifier:[names objectAtIndex:i]] autorelease];
    [[c headerCell] setStringValue:[labels objectAtIndex:i]]; [c setWidth:i==0?240:130]; [c setEditable:NO]; [t addTableColumn:c];
  }
  [t setDataSource:owner]; [t setDelegate:owner]; [t setAllowsMultipleSelection:NO];
  [scroll setDocumentView:t]; [scroll setHasVerticalScroller:YES]; [scroll setHasHorizontalScroller:YES];
  [scroll setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable]; [view addSubview:scroll]; return t;
}
@interface LibraryWindow (Private)
- (void)refresh:(id)sender;
@end
@implementation LibraryWindow
- (id)initWithLibrary:(RetroDLPLibrary *)library;
{
  self=[super initWithTitle:@"RetroDLP" autosaveName:@"RetroDLPLibraryWindow"]; if(!self) return nil;
  library_=[library retain]; mode_=1;
  AIViewController *left=[[[AIViewController alloc] init] autorelease];
  NSView *sidebar=[[[RDLayoutView alloc] initWithFrame:NSMakeRect(0,0,220,640)] autorelease];
  sidebar_=table(sidebar,[sidebar bounds],self,[NSArray arrayWithObject:@"title"],[NSArray arrayWithObject:@"Library"]);
  [left setView:sidebar]; [self setSidebarViewController:left];
  AIViewController *right=[[[AIViewController alloc] init] autorelease];
  NSView *detail=[[[RDLayoutView alloc] initWithFrame:NSMakeRect(0,0,850,640)] autorelease];
  input_=field(detail,NSMakeRect(10,605,580,24),YES); [input_ setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];
  [[input_ cell] setPlaceholderString:@"Playlist URL or ID"];
  NSButton *add=button(detail,@"Add Playlist",@selector(addPlaylist:),self,NSMakeRect(600,603,125,28)); [add setAutoresizingMask:NSViewMinXMargin|NSViewMinYMargin];
  button(detail,@"Sync",@selector(sync:),self,NSMakeRect(10,568,75,28));
  button(detail,@"Sync All",@selector(syncAll:),self,NSMakeRect(90,568,95,28));
  button(detail,@"Load My Playlists",@selector(discover:),self,NSMakeRect(190,568,145,28));
  button(detail,@"Import Cookies…",@selector(importCookies:),self,NSMakeRect(340,568,145,28));
  pause_=button(detail,@"Resume Queue",@selector(pause:),self,NSMakeRect(490,568,135,28));
  NSArray *children=[detail subviews]; unsigned int i;
  for(i=0;i<[children count];++i) if([[children objectAtIndex:i] isKindOfClass:[NSButton class]]) [(NSView *)[children objectAtIndex:i] setAutoresizingMask:NSViewMinYMargin];
  [add setAutoresizingMask:NSViewMinXMargin|NSViewMinYMargin];
  table_=table(detail,NSMakeRect(10,115,820,445),self,[NSArray arrayWithObjects:@"title",@"quality",@"state",@"error",nil],[NSArray arrayWithObjects:@"Video / Playlist",@"Quality",@"Status",@"Details",nil]);
  [table_ setTarget:self]; [table_ setDoubleAction:@selector(play:)];
  quality_=[[[NSPopUpButton alloc] initWithFrame:NSMakeRect(10,76,145,28) pullsDown:NO] autorelease];
  [quality_ addItemsWithTitles:[RetroDLPLibrary qualityTitles]];
  [quality_ setTarget:self]; [quality_ setAction:@selector(qualityChanged:)]; [detail addSubview:quality_];
  format_=field(detail,NSMakeRect(160,79,115,24),YES); [format_ setStringValue:@"18"]; [format_ setEnabled:NO];
  button(detail,@"Download Video",@selector(download:),self,NSMakeRect(280,76,140,28));
  button(detail,@"Download Playlist",@selector(downloadAll:),self,NSMakeRect(425,76,155,28));
  button(detail,@"Open in VLC",@selector(play:),self,NSMakeRect(585,76,125,28));
  button(detail,@"Retry",@selector(retry:),self,NSMakeRect(10,42,80,28));
  button(detail,@"Cancel Job",@selector(cancel:),self,NSMakeRect(95,42,105,28));
  button(detail,@"Remove Download",@selector(removeDownload:),self,NSMakeRect(205,42,160,28));
  button(detail,@"Remove Playlist",@selector(removePlaylist:),self,NSMakeRect(370,42,150,28));
  status_=field(detail,NSMakeRect(10,5,820,32),NO); [status_ setAutoresizingMask:NSViewWidthSizable];
  [right setView:detail]; [self setDetailViewController:right];
  [[self window] setContentSize:NSMakeSize(1080,640)]; [[self window] setMinSize:NSMakeSize(1040,500)]; [[self window] center];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RetroDLPLibraryDidChange object:library_];
  [self refresh:nil]; return self;
}
- (void)dealloc;
{ [[NSNotificationCenter defaultCenter] removeObserver:self]; [library_ release]; [playlists_ release]; [rows_ release]; [selectedPlaylist_ release]; [super dealloc]; }
- (NSDictionary *)selectedRow;
{ NSInteger row=[table_ selectedRow]; return row>=0 && (NSUInteger)row<[rows_ count]?[rows_ objectAtIndex:(NSUInteger)row]:nil; }
- (NSDictionary *)selectedPlaylist;
{ unsigned int i; for(i=0;i<[playlists_ count];++i) if([[[playlists_ objectAtIndex:i] objectForKey:@"id"] isEqualToString:selectedPlaylist_]) return [playlists_ objectAtIndex:i]; return nil; }
- (void)refresh:(id)sender;
{
  (void)sender;
  if(refreshing_) return;
  refreshing_=YES;
  NSDictionary *selection=[[self selectedRow] retain];
  [playlists_ release]; playlists_=[[library_ playlists] copy];
  [rows_ release]; rows_=[(mode_==0?[library_ entriesForPlaylist:selectedPlaylist_]:[library_ jobsForPlaylist:nil completedOnly:mode_==1]) copy];
  [sidebar_ reloadData]; [table_ reloadData]; [status_ setStringValue:[library_ status]];
  NSUInteger selectedSidebar=mode_==1?0:1; unsigned int i;
  if(mode_==0) {
    selectedSidebar=NSNotFound;
    for(i=0;i<[playlists_ count];++i) if([[[playlists_ objectAtIndex:i] objectForKey:@"id"] isEqualToString:selectedPlaylist_]) selectedSidebar=i+2;
  }
  if(selectedSidebar!=NSNotFound) [sidebar_ selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedSidebar] byExtendingSelection:NO];
  else [sidebar_ deselectAll:nil];
  [table_ deselectAll:nil];
  for(i=0;selection && i<[rows_ count];++i) {
    NSDictionary *row=[rows_ objectAtIndex:i];
    NSString *key=mode_==0?@"position":@"id";
    if([[row objectForKey:key] isEqualToString:[selection objectForKey:key]]) {
      [table_ selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO]; break;
    }
  }
  [selection release];
  [pause_ setTitle:[library_ isPaused]?@"Resume Queue":@"Pause Queue"];
  refreshing_=NO;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)view;
{ return (NSInteger)(view==sidebar_?[playlists_ count]+2:[rows_ count]); }
- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
{
  if(view==sidebar_) {
    if(row==0) return @"All Downloads"; if(row==1) return @"Download Queue";
    NSDictionary *p=[playlists_ objectAtIndex:(NSUInteger)row-2];
    return [NSString stringWithFormat:@"%@ (%@)",[p objectForKey:@"title"],[p objectForKey:@"count"]];
  }
  NSDictionary *item=[rows_ objectAtIndex:(NSUInteger)row]; NSString *key=[column identifier];
  if([key isEqualToString:@"quality"] && mode_!=0) return [[item objectForKey:@"actual_format"] length]?[item objectForKey:@"actual_format"]:[item objectForKey:@"format"];
  return [item objectForKey:key];
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
{
  if(refreshing_) return;
  if([notification object]==sidebar_) {
    NSInteger row=[sidebar_ selectedRow]; if(row<0) return;
    mode_=row==0?1:(row==1?2:0); [selectedPlaylist_ release];
    selectedPlaylist_=row>=2?[[[playlists_ objectAtIndex:(NSUInteger)row-2] objectForKey:@"id"] copy]:nil;
    [self refresh:nil];
  } else {
    NSString *error=[[self selectedRow] objectForKey:@"error"];
    [status_ setStringValue:[error length]?error:[library_ status]];
  }
}
- (void)addPlaylist:(id)sender; { (void)sender; [library_ syncPlaylistInput:[input_ stringValue]]; }
- (void)sync:(id)sender; { (void)sender; if([self selectedPlaylist]) [library_ syncPlaylistInput:[[self selectedPlaylist] objectForKey:@"service_id"]]; }
- (void)syncAll:(id)sender; { (void)sender; [library_ syncAll]; }
- (void)discover:(id)sender; { (void)sender; [library_ discoverPlaylists]; }
- (void)importCookies:(id)sender; { (void)sender; NSString *path=RDChooseCookieFile(); if(path) [library_ importCookies:path]; }
- (void)clearCookies:(id)sender; { (void)sender; [library_ clearCookies]; }
- (void)pause:(id)sender; { (void)sender; [library_ setPaused:![library_ isPaused]]; }
- (void)qualityChanged:(id)sender;
{ (void)sender; NSInteger index=[quality_ indexOfSelectedItem]; [format_ setEnabled:index==3]; if(index<3) [format_ setStringValue:[[RetroDLPLibrary qualityFormats] objectAtIndex:(NSUInteger)index]]; }
- (void)download:(id)sender;
{ (void)sender; NSDictionary *row=[self selectedRow]; if(mode_==0 && row) [library_ enqueuePlaylist:selectedPlaylist_ video:[row objectForKey:@"video_id"] format:[format_ stringValue]]; }
- (void)downloadAll:(id)sender; { (void)sender; [library_ enqueuePlaylist:selectedPlaylist_ video:nil format:[format_ stringValue]]; }
- (void)retry:(id)sender; { (void)sender; if(mode_!=0 && [self selectedRow]) [library_ retryJob:[[self selectedRow] objectForKey:@"id"]]; }
- (void)cancel:(id)sender; { (void)sender; if(mode_!=0 && [self selectedRow]) [library_ cancelJob:[[self selectedRow] objectForKey:@"id"]]; }
- (void)removeDownload:(id)sender;
{ (void)sender; if(mode_!=0 && [self selectedRow] && RDConfirm(@"Remove this downloaded file? Playlist membership is retained.")) [library_ removeDownload:[self selectedRow]]; }
- (void)removePlaylist:(id)sender;
{ (void)sender; if([self selectedPlaylist] && RDConfirm(@"Remove this playlist from the local library?")) [library_ removePlaylist:[self selectedPlaylist]]; }
- (void)play:(id)sender;
{ (void)sender; if(mode_==0 && [self selectedPlaylist]) RDOpenVLC([library_ playlistFile:[self selectedPlaylist]]); else if([[[self selectedRow] objectForKey:@"state"] isEqualToString:@"complete"]) RDOpenVLC([library_ fileForJob:[self selectedRow]]); }
@end
