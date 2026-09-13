/* Run in an isolated app bundle WITHOUT cacert.pem, using a fresh
   prepare_native_fixture.py library at /tmp/retrodlp-toolbar-fixture.
   Exercises real AppKit controls and sheets; never approves network work. */
#import "../macOS/LibraryWindow.h"
#import "../macOS/RDToolbarButton.h"
#import "../macOS/XPAppKit.h"
#import "../shared/rdapp_store.h"
@interface LibraryWindow (ToolbarTest)
- (void)tableWasUsed:(NSTableView *)view;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)refresh:(id)sender;
- (void)pause:(id)sender;
- (void)hideQueue:(id)sender;
- (void)dismissDownload:(id)sender;
- (void)clearCookies:(id)sender;
@end
static void requireCondition(BOOL condition,NSString *message) {
  if(!condition) [NSException raise:@"ToolbarTest" format:@"%@",message];
}
static void pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]]; }
static RDToolbarButton *toolbarButton(LibraryWindow *window,NSString *key) {
  return (RDToolbarButton *)[[[window valueForKey:@"toolbarItems_"] objectForKey:key] view];
}
static void selectRow(LibraryWindow *window,NSString *key,NSUInteger row) {
  NSTableView *table=[window valueForKey:key];
  if([table isKindOfClass:[NSOutlineView class]]) {
    NSOutlineView *outline=(NSOutlineView *)table;
    id item=row==0?@"All Downloads":[[[window valueForKey:@"playlists_"] objectAtIndex:row-1] objectForKey:@"id"];
    if(row>0) item=[[window valueForKey:@"sidebarItems_"] objectForKey:item];
    [outline expandItem:@"System"]; [outline expandItem:@"Added Playlists"]; [outline expandItem:@"My Playlists"];
    row=(NSUInteger)[outline rowForItem:item];
  }
  [window tableWasUsed:table]; [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; [window tableWasUsed:table];
}
static NSMenuItem *choice(NSMenu *menu,NSString *title) {
  NSMenuItem *item=[menu itemWithTitle:title]; requireCondition(item!=nil,[NSString stringWithFormat:@"Missing fixed menu item %@",title]); return item;
}
static void invoke(LibraryWindow *window,NSMenuItem *item) {
  requireCondition([window validateMenuItem:item],[NSString stringWithFormat:@"Unexpected disabled action %@",[item title]]);
  [[item target] performSelector:[item action] withObject:item]; pump();
}
static void confirm(LibraryWindow *window,BOOL accept) {
  NSAlert *alert=[window valueForKey:@"confirmation_"];
  requireCondition(alert!=nil && [[window window] attachedSheet]!=nil,@"Expected attached confirmation sheet");
  [[[alert buttons] objectAtIndex:accept?1:0] performClick:nil]; pump();
  requireCondition([window valueForKey:@"confirmation_"]==nil,@"Sheet did not dismiss");
}
static NSArray *titles(NSMenu *menu) {
  NSMutableArray *result=[NSMutableArray array]; NSEnumerator *e=[[menu itemArray] objectEnumerator]; NSMenuItem *item;
  while((item=[e nextObject])) { [result addObject:[item title]]; if([item submenu]) [result addObject:titles([item submenu])]; }
  return result;
}
@interface ToolbarTest : NSObject { RetroDLPLibrary *library_; LibraryWindow *window_; }
@end
@implementation ToolbarTest
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
  (void)notification;
  [self performSelector:@selector(run:) withObject:nil afterDelay:0.2];
}
- (void)run:(id)sender;
{
  (void)sender; NSString *report=@"PASS";
  @try {
    requireCondition([[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"]==nil,@"Test bundle must have no network CA resource");
    [[NSUserDefaults standardUserDefaults] setObject:@"18" forKey:@"downloadFormat"];
    library_=[[RetroDLPLibrary alloc] initWithSupportDirectory:@"/tmp/retrodlp-toolbar-fixture/Support" downloadDirectory:@"/tmp/retrodlp-toolbar-fixture/Downloads"];
    requireCondition(library_!=nil,@"Fixture failed to open");
    requireCondition([[library_ playlists] count]==1 && [[library_ jobsForPlaylist:nil completedOnly:NO] count]==3,@"Use a fresh fixture");
    window_=[[LibraryWindow alloc] initWithLibrary:library_]; [window_ showWindow:nil]; [NSApp activateIgnoringOtherApps:YES]; pump();
    NSOutlineView *outline=[window_ valueForKey:@"sidebar_"];
    requireCondition([outline isKindOfClass:[NSOutlineView class]],@"Sidebar must be an outline");
    requireCondition([outline numberOfRows]==5 && [[outline itemAtRow:0] isEqual:@"System"] && [[outline itemAtRow:2] isEqual:@"Added Playlists"] && [[outline itemAtRow:4] isEqual:@"My Playlists"],@"Expected three groups and fixture children");
    [outline collapseItem:@"Added Playlists"]; [window_ refresh:nil];
    requireCondition(![outline isItemExpanded:@"Added Playlists"],@"Refresh must retain collapsed group");
    [outline expandItem:@"Added Playlists"];
    NSDictionary *items=[window_ valueForKey:@"toolbarItems_"];
    requireCondition([items count]==4 && [items objectForKey:@"download"] && [items objectForKey:@"play"],@"Expected Download and Play toolbar items");
    requireCondition(![toolbarButton(window_,@"play") isDefaultEnabled],@"No selection must disable Play");
    requireCondition(RDYouTubeIcon(1)!=nil,@"YouTube Brands icon missing");
    NSMenu *download=[window_ menuForToolbarIdentifier:@"download"];
    NSMenu *play=[window_ menuForToolbarIdentifier:@"play"];
    requireCondition([download itemWithTitle:@"Add Playlist…"]!=nil,@"Global Add must remain available");
    requireCondition([play itemWithTitle:@"Open With…"]==nil,@"Open With must remain absent");
    selectRow(window_,@"sidebar_",1);
    download=[window_ menuForToolbarIdentifier:@"download"]; play=[window_ menuForToolbarIdentifier:@"play"];
    NSArray *playlistTitles=[[titles(download) copy] autorelease];
    requireCondition([download itemWithTitle:@"Remove Playlist…"]!=nil && ![download itemWithTitle:@"Delete Download…"],@"Sidebar must expose playlist operations");
    requireCondition([window_ validateMenuItem:choice(play,@"Reveal Playlist in Finder")],@"Playlist folder must reveal");
    requireCondition([window_ validateMenuItem:choice(play,@"Play Playlist in Default App")]==(RDDefaultApplication([library_ playlistFile:[[library_ playlists] objectAtIndex:0]])!=nil),@"Playlist playback must use its exported file");
    NSMenu *bulk=[choice(download,@"Download Quality") submenu];
    invoke(window_,choice(bulk,@"High"));
    requireCondition(![[window_ window] attachedSheet] && [[library_ jobsForPlaylist:nil completedOnly:NO] count]==3,@"Choosing High must only save the preference");
    invoke(window_,choice(download,@"Download Missing Videos")); confirm(window_,NO);
    invoke(window_,choice(bulk,@"Low"));
    requireCondition([[library_ jobsForPlaylist:nil completedOnly:NO] count]==3 && [library_ isPaused],@"Cancelled playlist download mutated jobs or Pause");
    selectRow(window_,@"table_",0);
    download=[window_ menuForToolbarIdentifier:@"download"]; play=[window_ menuForToolbarIdentifier:@"play"];
    requireCondition(![playlistTitles isEqual:titles(download)],@"Download menu must adapt to video selection");
    requireCondition([choice(download,@"Download Video") submenu]==nil && [choice(download,@"Download Video") action]!=NULL,@"Download Video must be a direct command");
    NSMenu *qualityMenu=[choice(download,@"Download Quality") submenu];
    requireCondition([qualityMenu numberOfItems]==4 && ![qualityMenu itemWithTitle:@"Last Used Quality"],@"Quality submenu must contain only presets and custom");
    requireCondition([download itemWithTitle:@"Delete Download…"]!=nil && ![download itemWithTitle:@"Remove Playlist…"],@"Video operations must replace playlist operations");
    requireCondition([window_ validateMenuItem:choice(play,@"Reveal Video in Finder")],@"Completed video must reveal");
    requireCondition([play itemWithTitle:@"Play Playlist in Default App"]!=nil && [play itemWithTitle:@"Play Playlist in VLC"]!=nil,@"Video selection must retain containing-playlist playback");
    [toolbarButton(window_,@"download") performClick:nil]; pump();
    requireCondition([[toolbarButton(window_,@"download") title] isEqualToString:@"Delete"],@"Completed selection must show Delete");
    confirm(window_,NO);
    requireCondition([[library_ jobsForPlaylist:nil completedOnly:YES] count]==1,@"Cancelling default deletion must preserve the file");
    selectRow(window_,@"table_",1);
    requireCondition(![toolbarButton(window_,@"play") isDefaultEnabled],@"Queued video must not play the whole playlist");
    [toolbarButton(window_,@"download") performClick:nil]; pump();
    selectRow(window_,@"queue_",1);
    download=[window_ menuForToolbarIdentifier:@"download"];
    requireCondition(![download itemWithTitle:@"Retry Download"] && ![download itemWithTitle:@"Download Again"],@"Redundant retry entries must be removed");
    invoke(window_,choice([choice(download,@"Download Quality") submenu],@"Medium"));
    requireCondition([window_ validateMenuItem:choice(download,@"Download Video")],@"Download Video must allow failed jobs at the selected quality");
    invoke(window_,choice(download,@"Download Video"));
    requireCondition(![window_ validateMenuItem:choice(download,@"Download Video")] && [window_ validateMenuItem:choice(download,@"Cancel Download…")],@"Queued job must disable duplicate Download Video");
    requireCondition([library_ isPaused] && ![library_ isBusy],@"Explicit retry must preserve Pause");
    invoke(window_,choice(download,@"Cancel Download…")); confirm(window_,NO);
    requireCondition([window_ validateMenuItem:choice(download,@"Cancel Download…")],@"Cancelled sheet changed job");
    invoke(window_,choice(download,@"Cancel Download…")); confirm(window_,YES);
    [window_ hideQueue:nil];
    NSMenu *queueMenu=[window_ menuForToolbarIdentifier:@"downloads"];
    invoke(window_,choice(queueMenu,@"Download Selected Queue Video"));
    requireCondition(![window_ isInspectorCollapsed] && [library_ isPaused],@"Explicit retry must reopen hidden Queue and preserve Pause");
    selectRow(window_,@"sidebar_",0); selectRow(window_,@"queue_",1);
    download=[window_ menuForToolbarIdentifier:@"download"];
    requireCondition([download itemWithTitle:@"Download Video"]!=nil && [download itemWithTitle:@"Download Missing Videos"]==nil,@"Queue must retain video scope with All Downloads selected");
    play=[window_ menuForToolbarIdentifier:@"play"];
    requireCondition([play itemWithTitle:@"Play Playlist in VLC"]!=nil,@"Queue video must retain containing-playlist options without sidebar selection");
    requireCondition([window_ validateMenuItem:choice(play,@"Play Playlist in Default App")]==(RDDefaultApplication([library_ playlistFile:[[library_ playlists] objectAtIndex:0]])!=nil),@"Playlist playback must use the Queue video’s playlist rather than sidebar");
    requireCondition([[toolbarButton(window_,@"download") toolTip] rangeOfString:@"(136+140)"].location!=NSNotFound,@"Queue must retain exact selected quality");
    [window_ hideQueue:nil];
    requireCondition(![toolbarButton(window_,@"play") isDefaultEnabled],@"Hidden Queue must not remain the playback target");
    selectRow(window_,@"sidebar_",1);
    download=[window_ menuForToolbarIdentifier:@"download"];
    requireCondition([playlistTitles isEqual:titles(download)],@"Returning to sidebar must restore playlist menu");
    NSMenu *toolbarMenu=[toolbarButton(window_,@"download") menu];
    [window_ performSelector:@selector(menuNeedsUpdate:) withObject:toolbarMenu];
    requireCondition([titles(toolbarMenu) isEqual:titles(download)],@"Toolbar and menu bar must share the context menu definition");
    selectRow(window_,@"table_",1);
    download=[window_ menuForToolbarIdentifier:@"download"];
    invoke(window_,choice([choice(download,@"Download Quality") submenu],@"High"));
    requireCondition([[library_ jobsForPlaylist:nil completedOnly:NO] count]==3,@"Quality selection started a download");
    NSMenu *quality=[choice(download,@"Download Quality") submenu];
    invoke(window_,choice(quality,@"Custom Format…"));
    [[window_ valueForKey:@"customFormat_"] setStringValue:@"invalid-format"];
    NSButton *save=[[[NSButton alloc] init] autorelease]; [save setTag:1]; [window_ dismissDownload:save];
    requireCondition([[window_ window] attachedSheet]!=nil,@"Invalid quality must keep the sheet open");
    [[window_ valueForKey:@"customFormat_"] setStringValue:@"22"];
    [window_ dismissDownload:save]; pump();
    requireCondition([[RetroDLPLibrary preferredFormat] isEqualToString:@"22"] && [[library_ jobsForPlaylist:nil completedOnly:NO] count]==3,@"Saving custom quality must not enqueue");
    invoke(window_,choice(quality,@"Custom Format…"));
    [[window_ valueForKey:@"customFormat_"] setStringValue:@"18"]; [save setTag:0]; [window_ dismissDownload:save]; pump();
    requireCondition([[RetroDLPLibrary preferredFormat] isEqualToString:@"22"],@"Cancelling custom quality changed preference");
    invoke(window_,choice(quality,@"High"));
    selectRow(window_,@"table_",0);
    download=[window_ menuForToolbarIdentifier:@"download"];
    invoke(window_,choice(download,@"Download Video"));
    requireCondition([[library_ jobsForPlaylist:nil completedOnly:NO] count]==4 && [[RetroDLPLibrary preferredFormat] isEqualToString:@"137+140"] && [library_ isPaused],@"Direct Download Video must reuse last selected High quality and preserve Pause");
    selectRow(window_,@"sidebar_",1);
    NSString *selectedKey=[[[window_ valueForKey:@"selectedPlaylist_"] copy] autorelease];
    [outline collapseItem:@"My Playlists"];
    rdapp_store *discoveryStore=NULL;
    requireCondition(rdapp_store_open("/tmp/retrodlp-toolbar-fixture/Support/retrodlp.sqlite",&discoveryStore),@"Could not open isolated discovery store");
    requireCondition(rdapp_store_discovered_playlist(discoveryStore,"PLfixture","Offline test playlist"),@"Discovery promotion failed");
    rdapp_store_close(discoveryStore); [window_ refresh:nil];
    requireCondition([[window_ valueForKey:@"playlists_"] count]==1 && [outline numberOfRows]==5,@"Discovery must not duplicate playlist");
    requireCondition([[outline itemAtRow:3] isEqual:@"My Playlists"] && [[outline itemAtRow:4] isEqual:selectedKey],@"Discovered playlist must move to My Playlists");
    requireCondition([[window_ valueForKey:@"selectedPlaylist_"] isEqual:selectedKey] && [outline selectedRow]==4,@"Promotion must preserve selected playlist");
    report=@"PASS: outline groups, collapse persistence, discovery promotion with selection preserved, Download/Play targeting, adaptive menus, playlist bulk cancellation, completed default confirms Delete; failed default retries and reveals Queue, exact Queue quality, explicit paused retry, confirmation cancellation, and no playback fallback to another selection; no network work.";

  } @catch(NSException *exception) { report=[NSString stringWithFormat:@"FAIL: %@",exception]; }
  [report writeToFile:@"/tmp/retrodlp-toolbar-test.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  [library_ shutdown];
  [NSApp terminate:nil];
}
@end
int main(void) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSApplication *app=[RDApplication sharedApplication]; ToolbarTest *delegate=[[ToolbarTest alloc] init];
  RDSetAppDelegate(app,delegate); [app run]; [delegate release]; [pool drain]; return 0;
}
