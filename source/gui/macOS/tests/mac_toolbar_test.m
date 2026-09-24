/* Run in an isolated app bundle WITHOUT cacert.pem, using a fresh
   prepare_native_fixture.py library at /tmp/retrodlp-toolbar-fixture.
   Exercises real AppKit controls and sheets; never approves network work. */
#import "../RDLPLibraryWindowController.h"
#import "../RDLPToolbarButton.h"
#import "../RDLPQueueWindowController.h"
#import "../RDLPAppKit.h"
#import "../RDLPLibraryViews.h"
#import "../RDLPAppDelegate.h"
#import "../../shared/rdapp_store.h"
#import "../../shared/RDLP_Foundation.h"
#import <math.h>
#include <sys/resource.h>
#include <stdlib.h>
@interface RDLPLibraryWindowController (RDLPToolbarTest)
- (void)tableWasUsed:(NSTableView *)view;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)refresh:(id)sender;
- (void)showJobInQueue:(NSDictionary *)job;
- (void)hideQueue:(id)sender;
- (void)showQueue:(id)sender;
- (NSDictionary *)selectedJob;
- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
- (NSString *)tableView:(NSTableView *)view toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column row:(NSInteger)row mouseLocation:(NSPoint)point;
- (void)dismissDownload:(id)sender;
- (void)clearCookies:(id)sender;
- (void)addVideo:(id)sender;
- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item;
@end
#import "../../shared/tests/shared_status_test.h"
#import "../../shared/tests/shared_worker_test.h"
#import "../../shared/tests/shared_metadata_test.h"
#import "../../shared/tests/shared_video_rows_test.h"

static void requireCondition(BOOL condition,NSString *message) {
  if([[[NSProcessInfo processInfo] environment] objectForKey:@"RDLPTestTrace"]) NSLog(@"%@: %@",condition?@"PASS":@"FAIL",message);
  if(!condition) {
    [[@"FAIL: " stringByAppendingString:message] writeToFile:@"/tmp/retrodlp-toolbar-test.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [NSException raise:@"RDLPToolbarTest" format:@"%@",message];
  }
}
/* Exercise the modern CGFloat-returning selector even on the Tiger runner. */
@interface RDLPBackingScaleProbe : NSObject
- (CGFloat)backingScaleFactor;
@end
@implementation RDLPBackingScaleProbe
- (CGFloat)backingScaleFactor; { return 2.0; }
@end
/* Exercise native-selector dispatch even when the runner is Tiger. */
@interface RDLPModernThreadProbe : NSThread
@end
@implementation RDLPModernThreadProbe
+ (BOOL)isMainThread { return NO; }
@end
@interface RDLPThreadProbe : NSObject {
@public
  BOOL backgroundIsMain;
}
- (void)check:(NSConditionLock *)gate;
@end
@implementation RDLPThreadProbe
- (void)check:(NSConditionLock *)gate {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  [gate lock]; backgroundIsMain=[NSThread RLDP_isMainThread]; [gate unlockWithCondition:1];
  [pool drain];
}
@end
static void testMainThreadCompatibility(void) {
  requireCondition([NSThread RLDP_isMainThread],@"Main-thread compatibility query recognizes AppKit's main thread");
  requireCondition(![RDLPModernThreadProbe RLDP_isMainThread],@"Compatibility query uses the native selector when available");
  RDLPThreadProbe *probe=[[[RDLPThreadProbe alloc] init] autorelease];
  NSConditionLock *gate=[[[NSConditionLock alloc] initWithCondition:0] autorelease];
  [NSThread detachNewThreadSelector:@selector(check:) toTarget:probe withObject:gate];
  requireCondition([gate lockWhenCondition:1 beforeDate:[NSDate dateWithTimeIntervalSinceNow:5]],@"Background thread query completes");
  BOOL backgroundIsMain=probe->backgroundIsMain; [gate unlock];
  requireCondition(!backgroundIsMain,@"Main-thread compatibility query rejects a background thread");
}
@interface RDLPErrorAlertProbe : NSObject {
@public
  BOOL appeared;
}
- (void)dismiss:(NSTimer *)timer;
@end
@implementation RDLPErrorAlertProbe
- (void)dismiss:(NSTimer *)timer;
{
  if([NSApp modalWindow]) { appeared=YES; [timer invalidate]; [[[NSApp modalWindow] defaultButtonCell] performClick:nil]; }
}
@end
static void testMacErrorAlert(RDLPLibraryWindowController *window) {
  RDLPStatusTestLibrary *errors=[[[RDLPStatusTestLibrary alloc]
    initWithSupportDirectory:@"/tmp/retrodlp-toolbar-fixture/Alerts/Support"
    downloadDirectory:@"/tmp/retrodlp-toolbar-fixture/Alerts/Downloads"] autorelease];
  RDLPAppDelegate *presenter=[[RDLPAppDelegate alloc] init];
  [presenter setValue:errors forKey:@"library_"]; [presenter setValue:window forKey:@"window_"];
  [errors showStatus:@"Downloading"]; [errors importCookies:@"/synthetic-missing-cookie-file"];
  RDLPErrorAlertProbe *probe=[[[RDLPErrorAlertProbe alloc] init] autorelease];
  NSTimer *timer=[NSTimer timerWithTimeInterval:0.1 target:probe selector:@selector(dismiss:) userInfo:nil repeats:YES];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
  [presenter performSelector:@selector(showNextError)]; [timer invalidate];
  requireCondition(probe->appeared && ![errors hasErrors],@"Shared error becomes a native Mac alert");
  requireCondition([[errors status] isEqualToString:@"Downloading"],@"Native alert leaves download status alone");
  [NSObject cancelPreviousPerformRequestsWithTarget:presenter]; [presenter release];
}
/* Exercise VLC-present/absent branches without changing installed applications. */
static BOOL probeVLC, probeQuickTime, probeDefault;
static NSString *probeOpened, *probeOpenedPath, *probeVersion;
@interface RDLPPlaybackProbe : RDLPAppKit
+ (void)checkFile:(NSString *)path;
+ (void)checkPlaylistsInDirectory:(NSString *)directory;
@end
@implementation RDLPPlaybackProbe
+ (NSString *)VLCApplication { return probeVLC?@"/Applications/VLC.app":nil; }
+ (NSString *)VLCVersion { return probeVersion; }
+ (NSString *)QuickTimeApplication { return probeQuickTime?@"/Applications/QuickTime Player.app":nil; }
+ (NSString *)defaultApplication:(NSString *)path { (void)path; return probeDefault?@"/Applications/QuickTime Player.app":nil; }
+ (void)openInVLC:(NSString *)path { probeOpenedPath=path; probeOpened=@"VLC"; }
+ (void)openInQuickTime:(NSString *)path { (void)path; probeOpened=@"QuickTime"; }
+ (void)openDefaultApplication:(NSString *)path { (void)path; probeOpened=@"Default"; }
+ (void)checkPlaylistsInDirectory:(NSString *)directory {
  NSString *xspf=[directory stringByAppendingPathComponent:@"Playlist.xspf"];
  NSString *m3u=[directory stringByAppendingPathComponent:@"Playlist.m3u8"];
  NSString *video=[directory stringByAppendingPathComponent:@"video.mp4"];
  [@"fixture" writeToFile:xspf atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  [@"fixture" writeToFile:m3u atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  [@"fixture" writeToFile:video atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  [self checkFile:xspf];
  NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
  NSString *saved=[[defaults stringForKey:@"RetroDLPVideoPlayer"] copy];
  probeVLC=YES; [self saveVideoPlayer:@"VLC"];
  NSArray *versions=[NSArray arrayWithObjects:@"0.9.10",@"1.1.9",@"1.1.11",@"1.1",@"",@"unknown",@"1..12",@"1.1.12-rc1",@"1.1.12",@"1.1.13",@"1.10.0",@"2.0.0",@"3.0.21",nil];
  unsigned int i;
  for(i=0;i<[versions count]+1;++i) {
    probeVersion=i<[versions count]?[versions objectAtIndex:i]:nil;
    NSString *expected=i>=8 && i<[versions count]?xspf:m3u;
    requireCondition([[self VLCPlaybackPath:xspf] isEqual:expected] && [[self VLCPlaybackPath:m3u] isEqual:expected],@"VLC versions must select the correct playlist numerically");
    probeOpenedPath=nil; [self openPreferredPlayback:xspf];
    requireCondition([probeOpenedPath isEqual:expected],@"Dispatch must receive the compatible playlist");
    probeOpenedPath=nil; [self openPreferredPlayback:video];
    requireCondition([probeOpenedPath isEqual:video],@"VLC version selection must preserve single-video playback");
  }
  probeVersion=@"0.9.10";
  [[NSFileManager defaultManager] removeFileAtPath:m3u handler:nil];
  probeOpenedPath=nil; [self openPreferredPlayback:xspf];
  requireCondition(!probeOpenedPath && ![self preferredPlaybackApplication:xspf],@"Missing legacy playlist must never fall through to unsafe XSPF");
  if(saved) [defaults setObject:saved forKey:@"RetroDLPVideoPlayer"];
  else [defaults removeObjectForKey:@"RetroDLPVideoPlayer"];
  [defaults synchronize]; [saved release];
}
+ (void)checkFile:(NSString *)path {
  NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
  NSString *saved=[[defaults stringForKey:@"RetroDLPVideoPlayer"] copy];
  [defaults removeObjectForKey:@"RetroDLPVideoPlayer"];
  probeVLC=YES; probeQuickTime=YES; probeDefault=YES;
  requireCondition([[self preferredPlaybackApplication:path] isEqual:[self VLCApplication]],@"Installed VLC must take priority over the system association");
  probeOpened=nil; [self openPreferredPlayback:path];
  requireCondition([probeOpened isEqual:@"VLC"],@"Automatic playback must dispatch to VLC only");
  probeDefault=NO;
  requireCondition([[self preferredPlaybackApplication:path] isEqual:[self VLCApplication]],@"VLC must work without a system file association");
  probeVLC=NO; probeDefault=YES;
  requireCondition([[self preferredPlaybackApplication:path] isEqual:[self defaultApplication:path]],@"Absent VLC must select the system default");
  probeOpened=nil; [self openPreferredPlayback:path];
  requireCondition([probeOpened isEqual:@"Default"],@"Absent VLC must dispatch to the system default");
  probeVLC=YES;
  [self saveVideoPlayer:@"Default App"]; probeOpened=nil; [self openPreferredPlayback:path];
  requireCondition([probeOpened isEqual:@"Default"] && [[self videoPlayer] isEqual:@"Default App"],@"Explicit Default App overrides installed VLC");
  [self saveVideoPlayer:@"QuickTime"]; probeOpened=nil; [self openPreferredPlayback:path];
  requireCondition([probeOpened isEqual:@"QuickTime"] && [[self preferredPlaybackApplication:path] isEqual:[self QuickTimeApplication]],@"QuickTime choice controls application resolution and dispatch");
  [defaults synchronize];
  requireCondition([[defaults stringForKey:@"RetroDLPVideoPlayer"] isEqual:@"QuickTime"],@"Player choice is persisted");
  probeQuickTime=NO; probeOpened=nil; [self openPreferredPlayback:path];
  requireCondition([probeOpened isEqual:@"Default"] && [[self videoPlayer] isEqual:@"Default App"],@"Removed QuickTime falls back to Default App");
  [self saveVideoPlayer:@"VLC"]; probeOpened=nil; [self openPreferredPlayback:path];
  requireCondition([probeOpened isEqual:@"VLC"],@"Explicit VLC choice overrides earlier preference");
  probeVLC=NO; probeOpened=nil; [self openPreferredPlayback:path];
  requireCondition([probeOpened isEqual:@"Default"],@"Removed VLC falls back to Default App");
  [self saveVideoPlayer:@"QuickTime"];
  requireCondition([[defaults stringForKey:@"RetroDLPVideoPlayer"] isEqual:@"VLC"],@"Unavailable player cannot overwrite saved choice");
  probeDefault=NO;
  requireCondition([self preferredPlaybackApplication:path]==nil,@"No installed handler must preserve Finder fallback");
  probeVLC=YES; probeOpened=nil;
  [self openPreferredPlayback:nil]; [self openPreferredPlayback:[path stringByAppendingString:@".missing"]];
  requireCondition(probeOpened==nil && [self preferredPlaybackApplication:nil]==nil &&
    [self preferredPlaybackApplication:[path stringByAppendingString:@".missing"]]==nil,@"Missing media must not launch a player");
  if(saved) [defaults setObject:saved forKey:@"RetroDLPVideoPlayer"];
  else [defaults removeObjectForKey:@"RetroDLPVideoPlayer"];
  [defaults synchronize]; [saved release];
}
@end
static void pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]]; }
static RDLPToolbarButton *toolbarButton(RDLPLibraryWindowController *window,NSString *key) {
  return (RDLPToolbarButton *)[[[window valueForKey:@"toolbarItems_"] objectForKey:key] view];
}
static void selectRow(RDLPLibraryWindowController *window,NSString *key,NSUInteger row) {
  NSTableView *table=[window valueForKey:key];
  if([key isEqualToString:@"queue_"]) {
    [window showJobInQueue:[[window valueForKey:@"queueRows_"] objectAtIndex:row]];
    [window tableWasUsed:table]; return;
  }
  if([table isKindOfClass:[NSOutlineView class]]) {
    NSOutlineView *outline=(NSOutlineView *)table;
    id item=row==0?@"All Downloads":[[[window valueForKey:@"playlists_"] objectAtIndex:row-1] objectForKey:@"id"];
    if(row>0) item=[[window valueForKey:@"sidebarItems_"] objectForKey:item];
    [outline expandItem:@"System"]; [outline expandItem:@"Added Playlists"]; [outline expandItem:@"My Playlists"]; [outline expandItem:@"Unsupported Playlists"];
    row=(NSUInteger)[outline rowForItem:item];
  }
  [[window window] makeKeyAndOrderFront:nil];
  [window tableWasUsed:table]; [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; [window tableWasUsed:table];
}
static NSMenuItem *menuChoice(NSMenu *menu,NSString *title) {
  NSMenuItem *item=[menu itemWithTitle:title];
  if(item) return item;
  NSString *base=[title hasSuffix:@"…"]?[title substringToIndex:[title length]-1]:title;
  NSString *prefix=[base stringByAppendingString:@" — "];
  NSEnumerator *e=[[menu itemArray] objectEnumerator];
  while((item=[e nextObject])) if([[item title] hasPrefix:prefix]) return item;
  return nil;
}
static NSMenuItem *choice(NSMenu *menu,NSString *title) {
  NSMenuItem *item=menuChoice(menu,title); requireCondition(item!=nil,[NSString stringWithFormat:@"Missing fixed menu item %@",title]); return item;
}
static void invoke(RDLPLibraryWindowController *window,NSMenuItem *item) {
  requireCondition([window validateMenuItem:item],[NSString stringWithFormat:@"Unexpected disabled action %@ (context=%@, queue job=%@)",[item title],[window valueForKey:@"context_"],[window selectedJob]]);
  [[item target] performSelector:[item action] withObject:item]; pump();
}
static void confirm(RDLPLibraryWindowController *window,BOOL accept) {
  NSAlert *alert=[window valueForKey:@"confirmation_"];
  requireCondition(alert!=nil && [window hasAttachedSheet],@"Expected attached confirmation sheet");
  NSDictionary *request=[[[window valueForKey:@"confirmationRequest_"] copy] autorelease];
  [[[alert buttons] objectAtIndex:accept?1:0] performClick:nil]; pump();
  requireCondition([window valueForKey:@"confirmation_"]==nil,@"Sheet did not dismiss");
  if(accept && [[request objectForKey:@"operation"] isEqual:@"cancel"]) {
    /* The confirmed mutation is deferred until after AppKit closes the sheet. */
    RDLPLibrary *library=[window valueForKey:@"library_"];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
    while([[[library jobForID:[request objectForKey:@"job"]] objectForKey:@"state"] isEqual:@"queued"] && [deadline timeIntervalSinceNow]>0) pump();
  }
}
static NSArray *titles(NSMenu *menu) {
  NSMutableArray *result=[NSMutableArray array]; NSEnumerator *e=[[menu itemArray] objectEnumerator]; NSMenuItem *item;
  while((item=[e nextObject])) { [result addObject:[item title]]; if([item submenu]) [result addObject:titles([item submenu])]; }
  return result;
}
static RDLPToolbarButton *queueButton(RDLPQueueWindowController *queue,NSString *identifier) {
  return (RDLPToolbarButton *)[[[queue valueForKey:@"toolbarItems_"] objectForKey:identifier] view];
}
static NSArray *libraryToolbarState(RDLPLibraryWindowController *owner) {
  NSMutableArray *state=[NSMutableArray array];
  NSEnumerator *identifiers=[[NSArray arrayWithObjects:@"library",@"download",@"play",@"remove",@"cookies",@"downloads",nil] objectEnumerator]; NSString *identifier;
  while((identifier=[identifiers nextObject])) {
    RDLPToolbarButton *button=toolbarButton(owner,identifier);
    [state addObject:[NSArray arrayWithObjects:[button title],[button toolTip],
      [NSNumber numberWithBool:[button isDefaultEnabled]],[[button image] TIFFRepresentation],nil]];
  }
  return state;
}
static NSArray *libraryToolbarAppearance(RDLPLibraryWindowController *owner) {
  NSMutableArray *appearance=[NSMutableArray array];
  NSEnumerator *e=[libraryToolbarState(owner) objectEnumerator]; NSArray *item;
  while((item=[e nextObject])) {
    /* Download's label stays fixed; its icon and tooltip describe the action. */
    [appearance addObject:[[item objectAtIndex:0] isEqualToString:@"Download"]?[item objectAtIndex:0]:
      [NSArray arrayWithObjects:[item objectAtIndex:0],[item objectAtIndex:1],[item objectAtIndex:3],nil]];
  }
  return appearance;
}
static void testToolbarCustomization(RDLPLibrary *library,BOOL restoring) {
  RDLPLibraryWindowController *owner=[[RDLPLibraryWindowController alloc] initWithLibrary:library];
  [owner showWindow:nil]; pump();
  NSToolbar *toolbar=[[owner window] toolbar];
  NSArray *custom=[NSArray arrayWithObjects:@"download",@"cookies",@"library",NSToolbarSpaceItemIdentifier,NSToolbarSeparatorItemIdentifier,@"remove",NSToolbarFlexibleSpaceItemIdentifier,@"downloads",nil];
  requireCondition([toolbar allowsUserCustomization] && [toolbar autosavesConfiguration],@"Main toolbar enables native customization and autosaving");
  requireCondition(![[[[owner valueForKey:@"queueWindow_"] window] toolbar] allowsUserCustomization],@"Queue toolbar keeps its existing behavior");
  if(!restoring) {
    selectRow(owner,@"sidebar_",1); selectRow(owner,@"table_",1);
    [toolbar removeItemAtIndex:1];
    requireCondition(toolbarButton(owner,@"download")==nil,@"Removing an item clears its cached view");
    [toolbar insertItemWithItemIdentifier:@"download" atIndex:0];
    requireCondition([toolbarButton(owner,@"download") isDefaultEnabled] &&
      [[toolbarButton(owner,@"download") image] isEqual:[RDLPLibraryViews toolbarIcon:AIFAOctagon window:[owner window]]],@"Reinserted Download immediately reflects the queued selection");
    [toolbarButton(owner,@"download") performClick:nil]; pump(); confirm(owner,NO);
    [toolbar removeItemAtIndex:2];
    [toolbar insertItemWithItemIdentifier:NSToolbarSpaceItemIdentifier atIndex:2];
    [toolbar insertItemWithItemIdentifier:NSToolbarSeparatorItemIdentifier atIndex:3];
    [toolbar removeItemAtIndex:6];
    [toolbar insertItemWithItemIdentifier:@"cookies" atIndex:1];
    RDLPToolbarButton *cookies=toolbarButton(owner,@"cookies");
    requireCondition([cookies target]==cookies && [cookies action]==@selector(showOptions:),@"Reinserted Cookies opens its own menu");
    [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
    [toolbar setSizeMode:NSToolbarSizeModeSmall];
    [[NSUserDefaults standardUserDefaults] synchronize];
  }
  requireCondition([[[toolbar items] valueForKey:@"itemIdentifier"] isEqual:custom],@"Custom item order, removals, spacing and separators survive relaunch");
  requireCondition([toolbar displayMode]==NSToolbarDisplayModeIconOnly && [toolbar sizeMode]==NSToolbarSizeModeSmall,@"Toolbar display settings survive relaunch");
  requireCondition([[[owner valueForKey:@"toolbarItems_"] allKeys] count]==5 && toolbarButton(owner,@"play")==nil,@"Only installed app items are cached");
  if(restoring) {
    NSMenuItem *customize=choice([owner menuForMenuBarTitle:@"View"],@"Customize Toolbar…");
    invoke(owner,customize);
    requireCondition([toolbar customizationPaletteIsRunning],@"View command opens the native customization palette");
    NSWindow *sheet=[[owner window] attachedSheet];
    requireCondition(sheet!=nil && [sheet defaultButtonCell]!=nil,@"Native palette has a Done button");
    [[sheet defaultButtonCell] performClick:nil]; pump();
    requireCondition(![toolbar customizationPaletteIsRunning],@"Done closes the customization palette");
    requireCondition([toolbarButton(owner,@"library") isDefaultEnabled],@"Toolbar buttons remain usable after customization");
    [toolbar setAutosavesConfiguration:NO];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NSToolbar Configuration RetroDLPLibraryToolbar"];
    [[NSUserDefaults standardUserDefaults] synchronize];
  }
  [owner close]; [owner release];
}
static void testFixedToolbar(RDLPLibraryWindowController *owner,RDLPLibrary *library) {
  /* Release this batch's read snapshots before the rest of the synchronous
     suite; real AppKit events drain their pools between user actions. */
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSArray *appearance=[[libraryToolbarAppearance(owner) copy] autorelease];
  NSEnumerator *menuButtons=[[NSArray arrayWithObjects:@"library",@"cookies",nil] objectEnumerator]; NSString *identifier;
  while((identifier=[menuButtons nextObject])) {
    RDLPToolbarButton *button=toolbarButton(owner,identifier);
    requireCondition([button target]==button && [button action]==@selector(showOptions:),@"Library and Cookies primary clicks open their menus");
  }
  requireCondition([toolbarButton(owner,@"downloads") menu]==nil,@"Queue is a navigation button without a menu");
  requireCondition([[toolbarButton(owner,@"remove") image] isEqual:[RDLPLibraryViews toolbarIcon:AIFATrash window:[owner window]]],@"Remove owns the fixed trash icon");
  NSUInteger scope;
  for(scope=0;scope<4;++scope) {
    selectRow(owner,@"sidebar_",scope==0?0:1);
    if(scope>=2) selectRow(owner,@"table_",scope-2);
    requireCondition([appearance isEqual:libraryToolbarAppearance(owner)],@"All labels and all other toolbar appearances stay fixed");
    requireCondition([toolbarButton(owner,@"library") isDefaultEnabled],@"Library remains available in every selection");
    BOOL cancellable=scope==3;
    NSData *expectedIcon=[[RDLPLibraryViews toolbarIcon:cancellable?AIFAOctagon:AIFADownload window:[owner window]] TIFFRepresentation];
    requireCondition([expectedIcon isEqual:[[toolbarButton(owner,@"download") image] TIFFRepresentation]],@"Download uses a stop sign for queued work and an arrow otherwise; deletion has its own button");
    requireCondition([toolbarButton(owner,@"download") isDefaultEnabled]==cancellable,@"Download disables completed preferred-quality videos and enables cancellation for queued jobs");
    NSMenu *libraryMenu=[toolbarButton(owner,@"library") menu];
    [owner performSelector:@selector(menuNeedsUpdate:) withObject:libraryMenu];
    requireCondition([libraryMenu numberOfItems]==6 && ![libraryMenu itemWithTitle:@"Show Download Queue"],@"Library contains only add, discovery and sync commands");
    requireCondition([toolbarButton(owner,@"remove") isDefaultEnabled]==(scope>=2),@"Remove follows the video or removable playlist and never All Downloads");
    invoke(owner,choice(libraryMenu,@"Add Video…"));
    requireCondition([[[owner valueForKey:@"addSheet_"] title] isEqualToString:@"Add Video"],@"Library’s Add Video command opens its sheet in every selection");
    [NSApp endSheet:[owner valueForKey:@"addSheet_"] returnCode:0]; pump();
  }
  requireCondition([[library jobsForPlaylist:nil completedOnly:NO] count]==3,@"Cancelling Add leaves existing downloads untouched");
  rdapp_store *store=NULL; int64_t pid=0;
  rdapp_entry entry; memset(&entry,0,sizeof(entry)); entry.video_id="CCCCCCCCCCC"; entry.title="New toolbar video";
  requireCondition(rdapp_store_open("/tmp/retrodlp-toolbar-fixture/Support/retrodlp.sqlite",&store) &&
    rdapp_store_snapshot(store,"PLdelete","Disposable playlist",&entry,1,&pid),@"Create removable local playlist");
  rdapp_store_close(store); [owner refresh:nil];
  NSString *key=[NSString stringWithFormat:@"%lld",(long long)pid];
  NSOutlineView *outline=[owner valueForKey:@"sidebar_"];
  id item=[[owner valueForKey:@"sidebarItems_"] objectForKey:key];
  [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[outline rowForItem:item]] byExtendingSelection:NO];
  [owner tableWasUsed:outline];
  requireCondition(![toolbarButton(owner,@"download") isDefaultEnabled] && [appearance isEqual:libraryToolbarAppearance(owner)],@"Download stays disabled when only a playlist is selected");
  selectRow(owner,@"table_",0);
  requireCondition([toolbarButton(owner,@"download") isDefaultEnabled],@"An undownloaded video enables Download");
  NSString *format=[[RDLPLibrary preferredFormat] copy];
  [toolbarButton(owner,@"download") performClick:nil]; pump();
  NSDictionary *job=[library jobForPlaylist:key video:@"CCCCCCCCCCC" format:format];
  requireCondition([[job objectForKey:@"state"] isEqual:@"queued"],@"Download enqueues a new video at the preferred quality");
  NSString *jobID=[[job objectForKey:@"id"] copy];
  NSMenu *quality=[owner menuForMenuBarTitle:@"Download Quality"];
  invoke(owner,choice(quality,@"High (137+140)"));
  requireCondition(rdapp_store_open("/tmp/retrodlp-toolbar-fixture/Support/retrodlp.sqlite",&store),@"Open retry fixture");
  NSArray *retryStates=[NSArray arrayWithObjects:@"failed",@"interrupted",@"cancelled",@"removed",@"complete",nil];
  NSEnumerator *states=[retryStates objectEnumerator]; NSString *state;
  while((state=[states nextObject])) {
    requireCondition(rdapp_store_finish(store,strtoll([jobID UTF8String],NULL,10),[state UTF8String],[format UTF8String],""),@"Set retry or missing-file state");
    [owner refresh:nil]; selectRow(owner,@"table_",0);
    NSMenu *downloads=[owner menuForToolbarIdentifier:@"download"];
    requireCondition([[choice(downloads,@"Download Video") title] isEqualToString:@"Download Video"] &&
      [[choice(downloads,@"Retry Download") title] isEqualToString:@"Retry Download — Low (18)"],@"Download Video keeps its short title while retry names the original quality");
    requireCondition([toolbarButton(owner,@"download") isDefaultEnabled] &&
      [[toolbarButton(owner,@"download") image] isEqual:[RDLPLibraryViews toolbarIcon:AIFADownload window:[owner window]]],@"Failed, stopped, removed and missing-file videos offer the download arrow");
    [toolbarButton(owner,@"download") performClick:nil]; pump();
    requireCondition([[[library jobForID:jobID] objectForKey:@"state"] isEqual:@"queued"] && [[library jobsForPlaylist:key completedOnly:NO] count]==1,@"Toolbar retry preserves exact job identity without duplicate downloads");
  }
  NSArray *cancelStates=[NSArray arrayWithObjects:@"queued",@"running",nil];
  states=[cancelStates objectEnumerator];
  while((state=[states nextObject])) {
    requireCondition(rdapp_store_finish(store,strtoll([jobID UTF8String],NULL,10),[state UTF8String],[format UTF8String],""),@"Set cancellable state");
    [owner refresh:nil]; selectRow(owner,@"table_",0);
    RDLPToolbarButton *button=toolbarButton(owner,@"download");
    requireCondition([button isDefaultEnabled] && [[button image] isEqual:[RDLPLibraryViews toolbarIcon:AIFAOctagon window:[owner window]]] &&
      [[button toolTip] isEqualToString:@"Cancel the selected download…"],@"Queued and running downloads offer an enabled stop sign and cancellation tooltip");
    [button performClick:nil]; pump();
    NSDictionary *request=[owner valueForKey:@"confirmationRequest_"];
    requireCondition([[request objectForKey:@"operation"] isEqual:@"cancel"] && [[request objectForKey:@"job"] isEqual:jobID],@"Stop sign confirms cancellation of the selected job");
    confirm(owner,NO);
    requireCondition([[[library jobForID:jobID] objectForKey:@"state"] isEqual:state],@"Dismissing toolbar cancellation preserves the job");
    if([state isEqual:@"queued"]) {
      [button performClick:nil]; pump(); confirm(owner,YES);
      /* Confirmation dispatches the action on the next AppKit event turn. */
      NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
      while(![[[library jobForID:jobID] objectForKey:@"state"] isEqual:@"cancelled"] && [deadline timeIntervalSinceNow]>0) pump();
      NSDictionary *cancelledJob=[library jobForID:jobID];
      requireCondition([[cancelledJob objectForKey:@"state"] isEqual:@"cancelled"],
        [NSString stringWithFormat:@"Stop-sign toolbar action cancels the selected job (job=%@, active=%@, errors=%@)",cancelledJob,[library valueForKey:@"activeJob_"],[library valueForKey:@"errors_"]]);
      requireCondition([[button image] isEqual:[RDLPLibraryViews toolbarIcon:AIFADownload window:[owner window]]],@"Cancelled download returns to the download arrow");
    }
  }
  /* The synthetic running row has no worker to acknowledge cancellation. */
  requireCondition(rdapp_store_finish(store,strtoll([jobID UTF8String],NULL,10),"cancelled",[format UTF8String],""),@"Finish synthetic running job");
  rdapp_store_close(store); [library removeDownload:[library jobForID:jobID]];
  invoke(owner,choice(quality,@"Low (18)"));
  [jobID release]; [format release]; [owner hideQueue:nil];
  [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[outline rowForItem:item]] byExtendingSelection:NO]; [owner tableWasUsed:outline];
  NSMenu *deletion=[toolbarButton(owner,@"remove") menu];
  [owner performSelector:@selector(menuNeedsUpdate:) withObject:deletion];
  requireCondition(menuChoice(deletion,@"Remove Playlist…")!=nil,@"Remove menu names the selected local playlist");
  requireCondition([toolbarButton(owner,@"remove") isDefaultEnabled],@"An empty local playlist enables Remove");
  [toolbarButton(owner,@"remove") performClick:nil]; pump(); confirm(owner,NO);
  requireCondition([library playlistForID:key]!=nil,@"Cancelling Delete preserves the playlist");
  invoke(owner,choice(deletion,@"Remove Playlist…")); confirm(owner,YES);
  requireCondition([library playlistForID:key]==nil,@"Delete removes the selected local playlist");
  selectRow(owner,@"sidebar_",0);
  [pool drain];
}
static void testQueueWindow(RDLPLibrary *library) {
  RDLPLibraryWindowController *owner=[[RDLPLibraryWindowController alloc] initWithLibrary:library];
  [owner showWindow:nil]; pump();
  RDLPQueueWindowController *queue=[owner valueForKey:@"queueWindow_"];
  NSTableView *table=[queue tableView]; NSWindow *window=[queue window];
  requireCondition([[[owner AI_splitView] subviews] count]==2,@"Library has exactly two panes and no inspector");
  requireCondition(![window isVisible] && window!=[owner window],@"Queue starts closed in a separate window");
  requireCondition(([window styleMask]&NSTexturedBackgroundWindowMask)!=0,@"Queue uses brushed metal window style");
  [toolbarButton(owner,@"downloads") performClick:nil]; pump();
  requireCondition([window isVisible] && [window isKeyWindow] && [table window]==window,@"Main Queue button opens and focuses the separate queue");
  requireCondition([[table tableColumns] count]==5 && [table numberOfRows]==3,@"Queue retains its five columns and all job qualities");
  requireCondition([[queue valueForKey:@"toolbarItems_"] count]==4 && queueButton(queue,@"play")==nil,@"Queue has Retry, Stop, Error, and Delete controls without Play");
  NSUInteger scope, jobIndex;
  for(scope=0;scope<3;++scope) {
    selectRow(owner,@"sidebar_",scope==0?0:1);
    if(scope==2) selectRow(owner,@"table_",0);
    NSArray *libraryState=[[libraryToolbarState(owner) copy] autorelease];
    for(jobIndex=0;jobIndex<3;++jobIndex) {
      selectRow(owner,@"queue_",jobIndex); [owner refresh:nil];
      requireCondition([libraryState isEqual:libraryToolbarState(owner)],@"Queue selection and refresh preserve library toolbar labels, tooltips, icons, and enabled state");
    }
  }
  selectRow(owner,@"queue_",1);
  NSMenu *fileMenu=[owner menuForMenuBarTitle:@"File"];
  requireCondition([owner validateMenuItem:choice(fileMenu,@"Download Video")],@"Menu-bar actions still target the active queue's failed job");
  NSMenu *mainDownloadMenu=[toolbarButton(owner,@"remove") menu];
  [owner performSelector:@selector(menuNeedsUpdate:) withObject:mainDownloadMenu];
  requireCondition([owner actionWindow]==[owner window] && menuChoice(mainDownloadMenu,@"Delete Download")!=nil,@"Library toolbar menu restores the library video target when opened from Queue");
  selectRow(owner,@"queue_",1);
  [toolbarButton(owner,@"remove") performClick:nil]; pump();
  requireCondition([[owner window] attachedSheet]!=nil && [window attachedSheet]==nil,@"Library toolbar click targets its downloaded video while Queue was key");
  confirm(owner,NO);
  if([[[NSProcessInfo processInfo] environment] objectForKey:@"RDQueueWindowScreenshot"])
    [[NSTask launchedTaskWithLaunchPath:@"/usr/sbin/screencapture" arguments:[NSArray arrayWithObjects:@"-x",@"/tmp/retrodlp-queue-window.png",nil]] waitUntilExit];
  selectRow(owner,@"queue_",1); NSString *failedKey=[[[[owner selectedJob] objectForKey:@"id"] copy] autorelease];
  requireCondition([queueButton(queue,@"retry") isDefaultEnabled] && [queueButton(queue,@"error") isDefaultEnabled] && ![queueButton(queue,@"stop") isDefaultEnabled],@"Failed job enables Retry and Error but not Stop");
  [queueButton(queue,@"retry") performClick:nil]; pump();
  requireCondition([[[owner selectedJob] objectForKey:@"id"] isEqual:failedKey] && [[[owner selectedJob] objectForKey:@"state"] isEqual:@"queued"],@"Queue Retry preserves exact quality and selected job");
  requireCondition([queueButton(queue,@"stop") isDefaultEnabled] && ![queueButton(queue,@"retry") isDefaultEnabled],@"Queued job enables Stop without duplicate retry");
  [queueButton(queue,@"stop") performClick:nil]; pump();
  requireCondition([window attachedSheet]!=nil && [[owner window] attachedSheet]==nil,@"Queue confirmation attaches to the queue window");
  confirm(owner,NO);
  requireCondition([[[owner selectedJob] objectForKey:@"state"] isEqual:@"queued"],@"Cancelling queue stop leaves the job queued");
  [queueButton(queue,@"stop") performClick:nil]; pump(); confirm(owner,YES);
  requireCondition([[[owner selectedJob] objectForKey:@"state"] isEqual:@"cancelled"],@"Queue Stop changes only the selected job");
  [queueButton(queue,@"delete") performClick:nil]; pump();
  requireCondition([window attachedSheet]!=nil,@"Queue deletion uses its own window sheet"); confirm(owner,NO);
  selectRow(owner,@"sidebar_",1); selectRow(owner,@"table_",0);
  requireCondition([owner actionWindow]==[owner window],@"Returning to library restores library action targeting");
  NSRect libraryFrame=[[owner window] frame], queueFrame=[window frame];
  queueFrame.size=NSMakeSize(700,450); [window setFrame:queueFrame display:YES];
  [owner showJobInQueue:[library jobForID:failedKey]]; pump();
  requireCondition([window isKeyWindow] && [[[owner selectedJob] objectForKey:@"id"] isEqual:failedKey],@"Show in Queue focuses the exact job in the queue window");
  BOOL paused=[library isPaused]; NSUInteger jobs=[[library queueRows] count];
  [window performClose:nil]; pump();
  requireCondition(![window isVisible] && [library isPaused]==paused && [[library queueRows] count]==jobs,@"Closing Queue preserves downloads and pause state");
  requireCondition(NSEqualRects([[owner window] frame],libraryFrame),@"Queue resize and close do not resize the library");
  [owner showQueue:nil]; pump();
  requireCondition(NSEqualRects([window frame],queueFrame) && [[[owner selectedJob] objectForKey:@"id"] isEqual:failedKey],@"Reopening Queue preserves its frame and selection");
  [[owner window] performClose:nil]; pump();
  requireCondition([window isVisible],@"Queue stays open when the library closes");
  [queueButton(queue,@"retry") performClick:nil]; pump();
  requireCondition([[[owner selectedJob] objectForKey:@"state"] isEqual:@"queued"],@"Queue controls work while the library window is closed");
  [owner showWindow:nil]; [owner hideQueue:nil];
  [owner close]; [owner release]; pump();
  owner=[[RDLPLibraryWindowController alloc] initWithLibrary:library]; [owner showWindow:nil]; [owner showQueue:nil]; pump();
  queue=[owner valueForKey:@"queueWindow_"];
  requireCondition(NSEqualRects([[queue window] frame],queueFrame),@"Queue frame autosave survives controller recreation");
  [owner hideQueue:nil]; [owner close]; [owner release];
}
@interface RDLPToolbarTest : NSObject { RDLPLibrary *library_; RDLPLibraryWindowController *window_; }
@end
@implementation RDLPToolbarTest
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
    NSString *customization=[[[NSProcessInfo processInfo] environment] objectForKey:@"RDToolbarCustomizationTest"];
    if(![customization isEqualToString:@"restore"])
      [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NSToolbar Configuration RetroDLPLibraryToolbar"];
    if([[[NSProcessInfo processInfo] environment] objectForKey:@"RDIconTestOnly"]) {
      RDLPBackingScaleProbe *scaleProbe=[[[RDLPBackingScaleProbe alloc] init] autorelease];
      requireCondition([RDLPAppKit backingScaleForWindow:(NSWindow *)scaleProbe]==2.0,
        @"Backing scale must preserve CGFloat through the runtime compatibility bridge");
      AIFontAwesomeIcon icons[]={AIFADownload,AIFACaretDown,AIFAPause,(AIFontAwesomeIcon)0xf167};
      CGFloat sizes[]={24,8,10,24}, canvases[]={32,10,10,32};
      unsigned int i,scale;
      for(i=0;i<4;++i) for(scale=1;scale<=2;++scale) {
        AIFontAwesomeStyle style=i==3?AIFontAwesomeStyleBrands:AIFontAwesomeStyleSolid;
        NSImage *icon=[RDLPAppKit controlIcon:icons[i] style:style iconSize:sizes[i] canvasSize:canvases[i] scale:scale];
        requireCondition(icon!=nil && icon==[RDLPAppKit controlIcon:icons[i] style:style iconSize:sizes[i] canvasSize:canvases[i] scale:scale],@"Control icons must render and reuse cached images");
        NSBitmapImageRep *bitmap=[[icon representations] objectAtIndex:0];
        requireCondition([bitmap pixelsWide]==canvases[i]*scale && [icon size].width==canvases[i],@"Control icons must preserve logical size and backing resolution");
        NSInteger x,y; BOOL opaque=NO,transparent=NO;
        CGFloat expected=0.0;
        for(y=0;y<[bitmap pixelsHigh];++y) for(x=0;x<[bitmap pixelsWide];++x) {
          NSColor *color=[[bitmap colorAtX:x y:y] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
          CGFloat r,g,b,a; [color getRed:&r green:&g blue:&b alpha:&a];
          if(a<0.01) transparent=YES;
          if(a>0.95) { opaque=YES; requireCondition(fabs(r-expected)<0.02 && fabs(g-expected)<0.02 && fabs(b-expected)<0.02,@"Control icon must be black"); }
        }
        requireCondition(opaque && transparent,@"Control icon must retain both its glyph and transparent canvas");
      }
      library_=[[RDLPLibrary alloc] initWithSupportDirectory:@"/tmp/retrodlp-icon-scale-test/Support"
        downloadDirectory:@"/tmp/retrodlp-icon-scale-test/Downloads"];
      requireCondition(library_!=nil,@"Icon test library failed to open");
      window_=[[RDLPLibraryWindowController alloc] initWithLibrary:library_]; [window_ showWindow:nil]; pump();
      CGFloat backingScale=[RDLPAppKit backingScaleForWindow:[window_ window]];
      RDLPToolbarButton *queue=toolbarButton(window_,@"downloads");
      NSImage *wrongScale=[RDLPAppKit controlIcon:AIFACaretDown style:AIFontAwesomeStyleSolid
        iconSize:8 canvasSize:10 scale:backingScale==1?2:1];
      [queue setImage:wrongScale]; [queue setCaretImage:wrongScale];
      [[NSNotificationCenter defaultCenter] postNotificationName:@"NSWindowDidChangeBackingPropertiesNotification" object:nil];
      requireCondition([queue image]==wrongScale,@"Other windows must not refresh these icons");
      [[NSNotificationCenter defaultCenter] postNotificationName:@"NSWindowDidChangeBackingPropertiesNotification" object:[window_ window]];
      NSBitmapImageRep *queueBitmap=[[[queue image] representations] objectAtIndex:0];
      NSBitmapImageRep *caretBitmap=[[[queue valueForKey:@"caret_"] representations] objectAtIndex:0];
      requireCondition([queueBitmap pixelsWide]==32*backingScale && [caretBitmap pixelsWide]==10*backingScale,
        @"Window backing notification must replace both the static Queue glyph and caret at the current scale");
      requireCondition([RDLPAppKit backingScaleForWindow:nil]==1,@"Unattached or legacy windows use 1x");
      [@"PASS: control icon colors, transparency, cache reuse, 1x/2x resolution, YouTube fallback, and window backing refresh" writeToFile:@"/tmp/retrodlp-icon-test.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
      [NSApp terminate:nil]; return;
    }
    if([[[NSProcessInfo processInfo] environment] objectForKey:@"RDWindowTestOnly"]) {
      NSString *frameName=@"AICCWindow-RetroDLPLibraryWindow";
      [[NSUserDefaults standardUserDefaults] removeObjectForKey:[@"NSWindow Frame " stringByAppendingString:frameName]];
      library_=[[RDLPLibrary alloc] initWithSupportDirectory:@"/tmp/retrodlp-window-size-test/Support" downloadDirectory:@"/tmp/retrodlp-window-size-test/Downloads"];
      requireCondition(library_!=nil,@"Window test library failed to open");
      window_=[[RDLPLibraryWindowController alloc] initWithLibrary:library_]; [window_ showWindow:nil]; pump();
      NSWindow *window=[window_ window];
      requireCondition(NSEqualSizes([window frame].size,NSMakeSize(800,600)),[NSString stringWithFormat:@"Wrong default frame: %@",NSStringFromRect([window frame])]);
      requireCondition(NSEqualSizes([window minSize],NSMakeSize(640,480)),[NSString stringWithFormat:@"Wrong minimum window size: %@",NSStringFromSize([window minSize])]);
      requireCondition([[window frameAutosaveName] isEqualToString:frameName],@"Frame autosaving must remain enabled");
      NSRect frame=[window frame]; frame.size=NSMakeSize(640,480); [window setFrame:frame display:YES]; pump();
      requireCondition(NSEqualSizes([window frame].size,frame.size),@"Window must support 640x480");
      frame.size=NSMakeSize(720,520); [window setFrame:frame display:YES]; pump();
      NSRect remembered=[window frame]; [window close]; pump(); [window_ release]; window_=nil;
      window_=[[RDLPLibraryWindowController alloc] initWithLibrary:library_]; [window_ showWindow:nil]; pump();
      requireCondition(NSEqualRects([[window_ window] frame],remembered),[NSString stringWithFormat:@"Saved frame was overridden: %@",NSStringFromRect([[window_ window] frame])]);
      [@"PASS: 800x600 default, 640x480 minimum, live frame autosave, and restored size/position" writeToFile:@"/tmp/retrodlp-window-test.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
      [NSApp terminate:nil]; return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:@"18" forKey:@"downloadFormat"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"RetroDLPVideoPlayer"];
    testMainThreadCompatibility();
    testSharedWorker(@"/tmp/retrodlp-toolbar-fixture/Worker");
    library_=[[RDLPLibrary alloc] initWithSupportDirectory:@"/tmp/retrodlp-toolbar-fixture/Support" downloadDirectory:@"/tmp/retrodlp-toolbar-fixture/Downloads"];
    requireCondition(library_!=nil,@"Fixture failed to open");
    pump();
    NSDate *startupDeadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while([library_ isBusy] && [startupDeadline timeIntervalSinceNow]>0) pump();
    requireCondition(![library_ isBusy] && [library_ operationCount]==0 && ![library_ hasErrors],@"Startup reconciliation completes and releases its operation reference");
    if(customization) {
      testToolbarCustomization(library_,[customization isEqualToString:@"restore"]);
      [@"PASS: native toolbar customization, reinserted actions, saved ordering and display settings" writeToFile:@"/tmp/retrodlp-toolbar-test.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
      [library_ shutdown]; [NSApp terminate:nil]; return;
    }
    if([[[NSProcessInfo processInfo] environment] objectForKey:@"RDToolbarPreview"]) {
      window_=[[RDLPLibraryWindowController alloc] initWithLibrary:library_];
      [window_ showWindow:nil]; [NSApp activateIgnoringOtherApps:YES];
      return; /* Keep the paused offline fixture available for accessibility tests. */
    }
    if([[[NSProcessInfo processInfo] environment] objectForKey:@"RDQueueWindowTestOnly"]) {
      testQueueWindow(library_);
      [@"PASS: two-pane library, brushed-metal queue window, queue toolbar actions and sheets, exact-job targeting, independent close/reopen, continued queue management with library closed, and frame persistence" writeToFile:@"/tmp/retrodlp-toolbar-test.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
      [library_ shutdown]; [NSApp terminate:nil]; return;
    }
    testSharedStatus(@"/tmp/retrodlp-toolbar-fixture/Status");
    requireCondition([[library_ playlists] count]==1 && [[library_ jobsForPlaylist:nil completedOnly:NO] count]==3,@"Use a fresh fixture");
    testSharedLists(library_);
    testSharedMetadata();
    testSharedVideoRows(@"/tmp/retrodlp-toolbar-fixture/Rows");
    RDLPDownloadPolicy *policy=[[[RDLPDownloadPolicy alloc] initWithLibrary:library_] autorelease];
    requireCondition(![policy playable:nil] && ![policy canRetry:nil] && ![policy canCancel:nil] &&
      ![policy canDownloadAgain:nil] && ![policy canRemove:nil],@"No selection must enable no job actions");
    NSArray *fixtureJobs=[library_ jobsForPlaylist:nil completedOnly:NO];
    NSDictionary *complete=nil; NSEnumerator *policyJobs=[fixtureJobs objectEnumerator]; NSDictionary *policyJob;
    while((policyJob=[policyJobs nextObject])) if([policy playable:policyJob]) complete=policyJob;
    requireCondition(complete!=nil,@"Policy fixture needs a playable copy");
    [RDLPPlaybackProbe checkFile:[library_ fileForJob:complete]];
    [RDLPPlaybackProbe checkFile:[library_ playlistFile:[[library_ playlists] objectAtIndex:0]]];
    NSMutableDictionary *variant=[[complete mutableCopy] autorelease];
    [variant setObject:@"running" forKey:@"state"];
    NSDictionary *entry=[NSDictionary dictionaryWithObject:[complete objectForKey:@"video_id"] forKey:@"video_id"];
    NSString *playlistID=[complete objectForKey:@"playlist_id"];
    requireCondition([policy representativeJobForEntry:entry playlist:playlistID jobs:
      [NSArray arrayWithObjects:variant,complete,nil]]==complete,@"Playable quality must outrank newer running quality");
    requireCondition([policy canCancel:variant] && ![policy canRemove:variant],@"Running jobs can stop but cannot be deleted");
    [variant setObject:@"complete" forKey:@"state"]; [variant setObject:@"missing-policy-fixture.mp4" forKey:@"path"];
    requireCondition(![policy playable:variant] && [policy canDownloadAgain:variant] &&
      [[policy statusForJob:variant] isEqualToString:@"File missing"],@"A missing file must allow download again without appearing playable");
    [variant setObject:@"failed" forKey:@"state"];
    requireCondition([policy canRetry:variant] && ![policy canDownloadAgain:variant] && ![policy canCancel:variant],
      @"Failed jobs require explicit retry and stay out of missing-only bulk downloads");
    NSDictionary *newest=[[variant copy] autorelease];
    requireCondition([policy representativeJobForEntry:entry playlist:playlistID jobs:
      [NSArray arrayWithObjects:newest,variant,nil]]==newest,@"Equal states must retain newest-first ordering");
    requireCondition([policy representativeJobForEntry:entry playlist:@"unrelated" jobs:fixtureJobs]==nil,
      @"Representative jobs must stay within the requested playlist");
    window_=[[RDLPLibraryWindowController alloc] initWithLibrary:library_]; [window_ showWindow:nil]; [NSApp activateIgnoringOtherApps:YES]; pump();
    NSMenu *cookiesMenu=[window_ menuForMenuBarTitle:@"Cookies"];
    NSData *cookieIcon=[[[toolbarButton(window_,@"cookies") image] TIFFRepresentation] retain];
    requireCondition([toolbarButton(window_,@"cookies") isDefaultEnabled] &&
      [window_ validateMenuItem:choice(cookiesMenu,@"Import Cookies…")],@"Startup leaves cookie import enabled in toolbar and menu");
    requireCondition([library_ importCookies:@"/tmp/retrodlp-toolbar-fixture/synthetic-cookies.txt"],@"Import isolated synthetic cookies");
    requireCondition([cookieIcon isEqual:[[toolbarButton(window_,@"cookies") image] TIFFRepresentation]],@"Cookie import does not change the toolbar icon"); [cookieIcon release];
    requireCondition([toolbarButton(window_,@"cookies") isDefaultEnabled] &&
      ![window_ validateMenuItem:choice(cookiesMenu,@"Import Cookies…")] &&
      [window_ validateMenuItem:choice(cookiesMenu,@"Replace Cookies…")] &&
      [window_ validateMenuItem:choice(cookiesMenu,@"Remove Cookies…")],@"Imported cookies enable replacement and removal");
    [library_ clearCookies];
    if([[[NSProcessInfo processInfo] environment] objectForKey:@"RDScrollTestOnly"]) {
      NSTableView *table=[window_ valueForKey:@"table_"];
      NSScrollView *scroll=[table enclosingScrollView];
      NSArray *originalRows=[[[window_ valueForKey:@"rows_"] copy] autorelease];
      unsigned int counts[]={0,2,200,2}; unsigned int index;
      for(index=0;index<4;++index) {
        NSMutableArray *rows=[NSMutableArray array]; unsigned int row;
        for(row=0;row<counts[index];++row) [rows addObject:[NSDictionary dictionaryWithObject:@"Synthetic sizing row" forKey:@"title"]];
        [window_ setValue:rows forKey:@"rows_"]; [table reloadData]; pump();
        BOOL overflow=NSHeight([table bounds])>NSHeight([[scroll contentView] bounds])+1;
        requireCondition(overflow==(counts[index]==200),[NSString stringWithFormat:@"Wrong content height for %u rows: table=%g clip=%g",counts[index],NSHeight([table bounds]),NSHeight([[scroll contentView] bounds])]);
        requireCondition(([scroll hasVerticalScroller] && ![[scroll verticalScroller] isHidden])==overflow,@"Vertical scrollbar must track actual content overflow");
      }
      [window_ setValue:originalRows forKey:@"rows_"]; [table reloadData];
      [@"PASS: empty/short/overflowing/short table heights and automatic scrollbar visibility" writeToFile:@"/tmp/retrodlp-scroll-test.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
      [NSApp terminate:nil]; return;
    }
    NSWindow *nativeWindow=[window_ window];
    NSTextField *status=[window_ valueForKey:@"status_"];
    NSSplitView *split=[window_ AI_splitView];
    requireCondition(([nativeWindow styleMask]&NSTexturedBackgroundWindowMask)!=0,@"Window must use the textured style");
    requireCondition([status superview]==[nativeWindow contentView] && [split superview]==[status superview],@"Status must belong to the window outside all panes");
    requireCondition([[status stringValue] isEqualToString:[library_ status]],@"Window must display the shared library status");
    NSSize sizes[]={NSMakeSize(1000,480),NSMakeSize(1250,720),NSMakeSize(1100,600)};
    unsigned int sizeIndex;
    for(sizeIndex=0;sizeIndex<3;++sizeIndex) {
      [nativeWindow setContentSize:sizes[sizeIndex]]; pump();
      NSRect splitFrame=[split frame], statusFrame=[status frame], contentBounds=[[nativeWindow contentView] bounds];
      requireCondition(NSMinY(splitFrame)==32 && NSMaxY(statusFrame)<=NSMinY(splitFrame),@"Split panes must stay above the status bar after resizing");
      requireCondition(NSWidth(splitFrame)==NSWidth(contentBounds) && NSMaxX(statusFrame)<=NSWidth(contentBounds),@"Status bar must fit the full window width");
    }
    NSRect visibleScreen=[[nativeWindow screen] visibleFrame];
    [nativeWindow setFrameTopLeftPoint:NSMakePoint(NSMinX(visibleScreen),NSMaxY(visibleScreen))];
    [window_ toggleSidebar:nil]; [window_ showQueue:nil]; pump();
    NSTableView *queueTable=[window_ valueForKey:@"queue_"];
    NSScrollView *queueScroll=[queueTable enclosingScrollView];
    requireCondition([queueTable isKindOfClass:[NSTableView class]] && ![queueTable isKindOfClass:[NSOutlineView class]],@"Queue must be a flat native table");
    requireCondition(NSEqualRects([queueScroll frame],[[queueScroll superview] bounds]),@"Queue scroll view fills its pane");
    NSArray *queueColumns=[queueTable tableColumns];
    NSArray *identifiers=[NSArray arrayWithObjects:@"number",@"state",@"quality",@"title",@"playlist_title",nil];
    NSArray *headings=[NSArray arrayWithObjects:@"",@"",@"Quality",@"Video",@"Playlist",nil];
    requireCondition([queueColumns count]==5,@"Queue has exactly five columns");
    NSUInteger columnIndex;
    for(columnIndex=0;columnIndex<[identifiers count];++columnIndex) {
      NSTableColumn *column=[queueColumns objectAtIndex:columnIndex];
      requireCondition([[column identifier] isEqual:[identifiers objectAtIndex:columnIndex]] && [[[column headerCell] stringValue] isEqual:[headings objectAtIndex:columnIndex]],@"Queue columns and blank headers follow requested order");
      requireCondition(![column isEditable],@"Queue status and text cells are read-only");
    }
    requireCondition([[window_ valueForKey:@"queueProgress_"] superview]==[status superview] && [[window_ valueForKey:@"queueProgress_"] isHidden],@"Idle queue progress stays in the app-wide status bar");
    NSArray *ordered=[window_ valueForKey:@"queueRows_"];
    requireCondition([ordered count]==3 && [queueTable numberOfRows]==3,@"Each download quality gets one row with no group rows");
    NSUInteger queueIndex; long long previousID=0;
    for(queueIndex=0;queueIndex<[ordered count];++queueIndex) {
      NSDictionary *job=[ordered objectAtIndex:queueIndex];
      long long jobID=strtoll([[job objectForKey:@"id"] UTF8String],NULL,10);
      requireCondition(queueIndex==0 || jobID<previousID,@"Queue shows newest items first"); previousID=jobID;
      requireCondition([[window_ tableView:queueTable objectValueForTableColumn:[queueColumns objectAtIndex:0] row:(NSInteger)queueIndex] isEqual:[job objectForKey:@"id"]],@"Queue numbers show permanent database job IDs");
      requireCondition([[window_ tableView:queueTable objectValueForTableColumn:[queueColumns objectAtIndex:3] row:(NSInteger)queueIndex] isEqual:[job objectForKey:@"title"]] && [[window_ tableView:queueTable objectValueForTableColumn:[queueColumns objectAtIndex:4] row:(NSInteger)queueIndex] isEqual:[job objectForKey:@"playlist_title"]],@"Queue exposes video and playlist in their own columns");
      requireCondition([[window_ tableView:queueTable objectValueForTableColumn:[queueColumns objectAtIndex:2] row:(NSInteger)queueIndex] rangeOfString:[job objectForKey:@"format"]].location!=NSNotFound,@"Quality identifies the exact requested format");
    }
    selectRow(window_,@"queue_",1);
    NSString *failedKey=[[[[window_ selectedJob] objectForKey:@"id"] copy] autorelease];
    NSInteger failedRow=[queueTable selectedRow];
    requireCondition([[[window_ selectedJob] objectForKey:@"state"] isEqual:@"failed"],@"Failed job is directly selectable");
    NSString *failureTip=[window_ tableView:queueTable toolTipForCell:nil rect:NULL tableColumn:[queueColumns objectAtIndex:1] row:failedRow mouseLocation:NSZeroPoint];
    requireCondition([failureTip rangeOfString:@"Synthetic failure"].location!=NSNotFound,@"Status tooltip retains the full failure reason");
    [window_ refresh:nil];
    requireCondition([queueTable selectedRow]==failedRow && [[[window_ selectedJob] objectForKey:@"id"] isEqual:failedKey],@"Refresh preserves the selected download");
    selectRow(window_,@"queue_",2);
    requireCondition(![[[queueColumns objectAtIndex:1] dataCellForRow:[queueTable selectedRow]] isKindOfClass:[NSButtonCell class]],@"Status column uses the playlist image cell, with actions in menus");
    NSMenu *initialQueueMenu=[window_ menuForToolbarIdentifier:@"downloads"];
    requireCondition(![initialQueueMenu itemWithTitle:@"Pause Queue"] && ![initialQueueMenu itemWithTitle:@"Resume Queue…"],@"Global pause and resume must be removed");
    [window_ hideQueue:nil];
    requireCondition(![status isHiddenOrHasHiddenAncestor] && [[status stringValue] isEqualToString:[library_ status]],@"Status must stay visible when panels toggle");
    [window_ toggleSidebar:nil]; pump();
    NSOutlineView *outline=[window_ valueForKey:@"sidebar_"];
    requireCondition([outline isKindOfClass:[NSOutlineView class]],@"Sidebar must be an outline");
    requireCondition([outline numberOfRows]==6 && [[outline itemAtRow:0] isEqual:@"System"] && [[outline itemAtRow:2] isEqual:@"Added Playlists"] && [[outline itemAtRow:4] isEqual:@"My Playlists"],@"Expected four groups and fixture children");
    [outline collapseItem:@"Added Playlists"]; [window_ refresh:nil];
    requireCondition(![outline isItemExpanded:@"Added Playlists"],@"Refresh must retain collapsed group");
    [outline expandItem:@"Added Playlists"];
    NSDictionary *items=[window_ valueForKey:@"toolbarItems_"];
    requireCondition([items count]==6 && [items objectForKey:@"library"] && [items objectForKey:@"download"] && [items objectForKey:@"remove"] && [items objectForKey:@"play"],@"Expected Library, Download, Play, Remove, Cookies and Queue toolbar items");
    requireCondition(![toolbarButton(window_,@"play") isDefaultEnabled],@"No selection must disable Play");
    requireCondition([[[items objectForKey:@"library"] label] isEqualToString:@"Library"],@"Toolbar label is always Library");
    invoke(window_,choice([toolbarButton(window_,@"library") menu],@"Add Video…"));
    requireCondition([[[window_ valueForKey:@"addSheet_"] title] isEqualToString:@"Add Video"],@"Library menu opens Add Video without a selection");
    [NSApp endSheet:[window_ valueForKey:@"addSheet_"] returnCode:0]; pump();
    testFixedToolbar(window_,library_);
    NSMenu *fileMenu=[window_ menuForMenuBarTitle:@"File"];
    requireCondition([[fileMenu itemAtIndex:0] action]==@selector(addVideo:) && [[fileMenu itemAtIndex:1] action]==@selector(addPlaylist:),@"File menu puts Add Video before Add Playlist");
    NSMenu *editMenu=[window_ menuForMenuBarTitle:@"Edit"];
    NSMenu *viewMenu=[window_ menuForMenuBarTitle:@"View"];
    requireCondition(menuChoice(fileMenu,@"Delete Download…")==nil && menuChoice(editMenu,@"Delete Download…")!=nil,@"Deletion belongs in Edit");
    requireCondition([viewMenu numberOfItems]==4 && [viewMenu itemWithTitle:@"Show Download Queue"]!=nil && [viewMenu itemWithTitle:@"Customize Toolbar…"]!=nil && [viewMenu itemWithTitle:@"Show in Queue"]==nil,@"View contains visibility commands and toolbar customization");
    requireCondition(![window_ validateMenuItem:choice(fileMenu,@"Play Playlist")],@"File playback is disabled without a selection");
    [fileMenu update];
    NSArray *fileTitles=[[titles(fileMenu) copy] autorelease];
    [fileMenu update];
    requireCondition([fileTitles isEqual:titles(fileMenu)],@"Unavailable File commands retain their positions");
    requireCondition([RDLPAppKit youTubeIconForScale:1]!=nil,@"YouTube Brands icon missing");
    NSMenu *download=[window_ menuForToolbarIdentifier:@"library"];
    NSMenu *play=[window_ menuForToolbarIdentifier:@"play"];
    requireCondition([download itemWithTitle:@"Add Playlist…"]!=nil && [download itemWithTitle:@"Add Video…"]!=nil,@"Global Add commands must remain available");
    requireCondition([download indexOfItemWithTitle:@"Add Video…"]<[download indexOfItemWithTitle:@"Add Playlist…"],@"Library menu puts Add Video before Add Playlist");
    requireCondition([download itemWithTitle:@"Download Missing Videos"]==nil && ![window_ validateMenuItem:choice(fileMenu,@"Download Video")],@"No selection must expose no bulk download and disable File download");
    requireCondition([play itemWithTitle:@"Open With…"]==nil,@"Open With must remain absent");
    selectRow(window_,@"sidebar_",1);
    download=[window_ menuForToolbarIdentifier:@"library"]; play=[window_ menuForToolbarIdentifier:@"play"];
    NSArray *playlistTitles=[[titles(download) copy] autorelease];
    requireCondition([download itemWithTitle:@"Sync Current Playlist"]!=nil && !menuChoice(download,@"Delete Download") && !menuChoice(download,@"Remove Playlist…"),@"Library owns sync and excludes destructive commands");
    requireCondition([download itemWithTitle:@"Download Missing Videos"]==nil && menuChoice(download,@"Download Video")==nil,@"Playlist menu must not offer downloads");
    NSMenuItem *fileDownload=choice(fileMenu,@"Download Video");
    requireCondition(![window_ validateMenuItem:fileDownload] && [[fileDownload title] isEqualToString:@"Download Video"],@"Playlist selection keeps File download disabled with a stable title");
    requireCondition([window_ validateMenuItem:choice(play,@"Reveal Playlist in Finder")],@"Playlist folder must reveal");
    requireCondition([window_ validateMenuItem:choice(play,@"Play Playlist")]==([RDLPAppKit preferredPlaybackApplication:[library_ playlistFile:[[library_ playlists] objectAtIndex:0]]]!=nil),@"Playlist playback must use its exported file");
    NSTableView *videosTable=[window_ valueForKey:@"table_"];
    NSArray *videoColumnIDs=[NSArray arrayWithObjects:@"state",@"size",@"quality",@"title",@"channel",nil];
    requireCondition([[[videosTable tableColumns] valueForKey:@"identifier"] isEqual:videoColumnIDs],@"Playlist columns follow Status, Size, Quality, Video, Channel order");
    requireCondition([[window_ tableView:videosTable objectValueForTableColumn:[videosTable tableColumnWithIdentifier:@"channel"] row:0] isEqualToString:@"Example Channel"],@"Playlist Channel column");
    NSString *metadataTip=[window_ tableView:videosTable toolTipForCell:nil rect:NULL tableColumn:[videosTable tableColumnWithIdentifier:@"title"] row:0 mouseLocation:NSZeroPoint];
    requireCondition([metadataTip rangeOfString:@"At last sync: 1.2K views · Published 2 days ago"].location!=NSNotFound && [metadataTip rangeOfString:@"Available snippet"].location!=NSNotFound,@"Video tooltip includes original labels and snippet");
    requireCondition([[[[videosTable tableColumns] objectAtIndex:0] identifier] isEqualToString:@"state"] && [[[[[videosTable tableColumns] objectAtIndex:0] headerCell] stringValue] length]==0,@"Status must be the untitled first column");
    requireCondition([[videosTable enclosingScrollView] hasHorizontalScroller],@"Narrow panes allow scrolling to all metadata columns");
    requireCondition([download itemWithTitle:@"Download Quality"]==nil,@"Playlist toolbar menu leaves quality in the application menu");
    NSMenu *quality=[window_ menuForMenuBarTitle:@"Download Quality"];
    invoke(window_,choice(quality,@"High (137+140)"));
    requireCondition(![[window_ window] attachedSheet] && [[library_ jobsForPlaylist:nil completedOnly:NO] count]==3,@"Choosing High must only save the preference");
    selectRow(window_,@"table_",0);
    NSDictionary *available=[window_ performSelector:@selector(targetJob)];
    requireCondition([[available objectForKey:@"format"] isEqualToString:@"18"],@"High preference must still target the existing Low download");
    requireCondition([[window_ performSelector:@selector(statusForJob:) withObject:available] isEqualToString:@"Downloaded"],@"Any existing quality must show Downloaded");
    requireCondition([window_ performSelector:@selector(selectionPlayFile)]!=nil,@"Any existing quality must remain playable");
    requireCondition([toolbarButton(window_,@"download") isDefaultEnabled] &&
      [[choice([window_ menuForToolbarIdentifier:@"download"],@"Download Video") title] isEqualToString:@"Download Video"],@"A completed Low copy still allows an explicit High download");
    NSString *preferred=[RDLPAppKit preferredPlaybackApplication:[library_ fileForJob:complete]];
    if([RDLPAppKit VLCApplication]) requireCondition([preferred isEqual:[RDLPAppKit VLCApplication]],@"Real installed VLC must be the preferred player");
    requireCondition([[toolbarButton(window_,@"play") toolTip] isEqualToString:@"Play the selected video or playlist"],@"Play tooltip stays fixed across selection changes");
    NSMenu *players=[window_ menuForMenuBarTitle:@"Video Player"];
    requireCondition([titles(players) isEqual:[NSArray arrayWithObjects:@"VLC",@"QuickTime",@"Default App",nil]],@"Video Player menu contains exactly three choices");
    requireCondition([window_ validateMenuItem:choice(players,@"VLC")]==([RDLPAppKit VLCApplication]!=nil) &&
      [window_ validateMenuItem:choice(players,@"QuickTime")]==([RDLPAppKit QuickTimeApplication]!=nil),@"Uninstalled players are disabled");
    invoke(window_,choice(players,@"Default App")); [players update];
    requireCondition([choice(players,@"Default App") state]==NSOnState && [choice(players,@"VLC") state]==NSOffState &&
      [[RDLPAppKit videoPlayer] isEqual:@"Default App"],@"Player menu saves and checks the selected preference");
    if([RDLPAppKit QuickTimeApplication]) {
      invoke(window_,choice(players,@"QuickTime")); [players update];
      requireCondition([choice(players,@"QuickTime") state]==NSOnState && [choice(players,@"Default App") state]==NSOffState &&
        [[RDLPAppKit preferredPlaybackApplication:[library_ fileForJob:complete]] isEqual:[RDLPAppKit QuickTimeApplication]],@"Selecting QuickTime updates checkmarks and playback routing immediately");
    }
    if([RDLPAppKit VLCApplication]) invoke(window_,choice(players,@"VLC"));
    else invoke(window_,choice(players,@"Default App"));
    requireCondition([choice([window_ menuForToolbarIdentifier:@"play"],@"Play Video") action]==@selector(playSelection:) &&
      ![[window_ menuForToolbarIdentifier:@"play"] itemWithTitle:@"Play Video in VLC"] &&
      ![[window_ menuForToolbarIdentifier:@"play"] itemWithTitle:@"Play Video in Default App"],@"Toolbar playback uses the preference without player-specific commands");
    if([[[NSProcessInfo processInfo] environment] objectForKey:@"RDPlaybackHandoffTest"]) {
      requireCondition([RDLPAppKit VLCApplication]!=nil,@"Handoff test requires installed VLC");
      [toolbarButton(window_,@"play") performClick:nil]; pump();
      [@"PASS: toolbar Play dispatched the synthetic local video to installed VLC" writeToFile:@"/tmp/retrodlp-playback-handoff.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
      [library_ shutdown]; [NSApp terminate:nil]; return;
    }
    selectRow(window_,@"sidebar_",0);
    requireCondition([[videosTable tableColumns] count]==5 && [videosTable tableColumnWithIdentifier:@"quality"]!=nil,@"All Downloads must retain Quality");
    requireCondition([[[videosTable tableColumns] valueForKey:@"identifier"] isEqual:videoColumnIDs],@"All Downloads shares the same column order");
    requireCondition([[window_ tableView:videosTable objectValueForTableColumn:[videosTable tableColumnWithIdentifier:@"channel"] row:0] isEqualToString:@"Example Channel"],@"All Downloads uses persisted job metadata");
    requireCondition([[window_ tableView:videosTable objectValueForTableColumn:[videosTable tableColumnWithIdentifier:@"size"] row:0] length]>0,@"All Downloads exposes completed file size");
    selectRow(window_,@"sidebar_",1);
    [window_ performSelector:@selector(downloadFromMenu:) withObject:fileDownload];
    invoke(window_,choice(quality,@"Low (18)"));
    requireCondition(![[window_ window] attachedSheet] && [[library_ jobsForPlaylist:nil completedOnly:NO] count]==3 && [library_ isPaused],@"Playlist selection cannot start downloads or a bulk confirmation");
    selectRow(window_,@"table_",0);
    download=[window_ menuForToolbarIdentifier:@"download"]; play=[window_ menuForToolbarIdentifier:@"play"];
    requireCondition([playlistTitles isEqual:titles([window_ menuForToolbarIdentifier:@"library"])],@"Library menu keeps its commands across selections");
    requireCondition([choice(download,@"Download Video") submenu]==nil && [choice(download,@"Download Video") action]!=NULL,@"Download Video must be a direct command");
    requireCondition([choice(download,@"Download Quality") submenu]!=nil && [download itemWithTitle:@"Show in Queue"]==nil,@"Download owns its quality submenu");
    requireCondition([quality numberOfItems]==4 && ![quality itemWithTitle:@"Last Used Quality"],@"Application quality submenu must contain only presets and custom");
    NSMenu *deletion=[window_ menuForToolbarIdentifier:@"remove"];
    NSMenu *add=[window_ menuForToolbarIdentifier:@"library"];
    requireCondition(!menuChoice(add,@"Download Video") && !menuChoice(add,@"Delete Download") && ![add itemWithTitle:@"Cancel Download…"] &&
      menuChoice(download,@"Download Video") && [download itemWithTitle:@"Cancel Download…"] && !menuChoice(download,@"Delete Download") &&
      menuChoice(deletion,@"Delete Download") && !menuChoice(deletion,@"Download Video") && ![deletion itemWithTitle:@"Cancel Download…"],@"Library, Download and Remove have separate responsibilities");
    requireCondition([window_ validateMenuItem:choice(play,@"Reveal Video in Finder")],@"Completed video must reveal");
    requireCondition([play itemWithTitle:@"Play Playlist"]!=nil && [choice(play,@"Play Playlist") action]==@selector(playTargetPlaylist:),@"Video selection must retain containing-playlist playback");
    requireCondition(![toolbarButton(window_,@"download") isDefaultEnabled],@"A completed preferred-quality video disables Download");
    [toolbarButton(window_,@"remove") performClick:nil]; pump();
    requireCondition([[toolbarButton(window_,@"library") title] isEqualToString:@"Library"] && [[toolbarButton(window_,@"download") title] isEqualToString:@"Download"],@"Completed selection keeps the Library and Download labels");
    confirm(window_,NO);
    requireCondition([[library_ jobsForPlaylist:nil completedOnly:YES] count]==1,@"Cancelling default deletion must preserve the file");
    selectRow(window_,@"table_",1);
    requireCondition(![toolbarButton(window_,@"play") isDefaultEnabled],@"Queued video must not play the whole playlist");
    [toolbarButton(window_,@"downloads") performClick:nil]; pump();
    selectRow(window_,@"queue_",1);
    download=[window_ menuForToolbarIdentifier:@"download"];
    requireCondition([[choice(download,@"Retry Download") title] isEqualToString:@"Retry Download — Med (136+140)"],@"Retry explicitly names the original job quality");
    requireCondition([choice(download,@"Download Quality") submenu]!=nil,@"Download quality is accessible in the toolbar menu");
    invoke(window_,choice(quality,@"Med (136+140)"));
    requireCondition([window_ validateMenuItem:choice(download,@"Download Video")],@"Download Video must allow failed jobs at the selected quality");
    invoke(window_,choice([queueTable menu],@"Retry"));
    requireCondition([[[window_ selectedJob] objectForKey:@"id"] isEqual:failedKey] && [queueTable selectedRow]==failedRow && [[[window_ selectedJob] objectForKey:@"state"] isEqual:@"queued"],@"Retry preserves exact job identity and row position");
    requireCondition(![window_ validateMenuItem:choice(download,@"Download Video")] && [window_ validateMenuItem:choice(download,@"Cancel Download…")],@"Queued job must disable duplicate Download Video");
    requireCondition([library_ isPaused] && ![library_ isBusy],@"Explicit retry must preserve Pause");
    invoke(window_,choice([queueTable menu],@"Stop Download…")); confirm(window_,NO);
    requireCondition([window_ validateMenuItem:choice(download,@"Cancel Download…")],@"Cancelled sheet changed job");
    invoke(window_,choice(download,@"Cancel Download…")); confirm(window_,YES);
    [window_ hideQueue:nil];
    [window_ showQueue:nil];
    invoke(window_,choice([queueTable menu],@"Retry"));
    requireCondition([[[window_ valueForKey:@"queueWindow_"] window] isVisible] && [library_ isPaused],@"Explicit retry must reopen hidden Queue and preserve Pause");
    selectRow(window_,@"sidebar_",0); selectRow(window_,@"queue_",1);
    download=[window_ menuForToolbarIdentifier:@"download"];
    requireCondition(menuChoice(download,@"Download Video")!=nil && [download itemWithTitle:@"Download Missing Videos"]==nil,@"Queue must retain video scope with All Downloads selected");
    play=[window_ menuForToolbarIdentifier:@"play"];
    requireCondition([play itemWithTitle:@"Play Playlist"]!=nil,@"Queue video must retain containing-playlist options without sidebar selection");
    requireCondition([window_ validateMenuItem:choice(play,@"Play Playlist")]==([RDLPAppKit preferredPlaybackApplication:[library_ playlistFile:[[library_ playlists] objectAtIndex:0]]]!=nil),@"Playlist playback must use the Queue video’s playlist rather than sidebar");
    requireCondition([[toolbarButton(window_,@"library") title] isEqualToString:@"Library"],@"Queue selection must not change the Library label");
    [window_ hideQueue:nil];
    requireCondition(![toolbarButton(window_,@"play") isDefaultEnabled],@"Hidden Queue must not remain the playback target");
    selectRow(window_,@"sidebar_",1);
    download=[window_ menuForToolbarIdentifier:@"library"];
    requireCondition([playlistTitles isEqual:titles(download)],@"Returning to sidebar must restore playlist menu");
    NSMenu *toolbarMenu=[toolbarButton(window_,@"library") menu];
    [window_ performSelector:@selector(menuNeedsUpdate:) withObject:toolbarMenu];
    requireCondition([titles(toolbarMenu) isEqual:titles(download)],@"Toolbar caret and context menu must share the context menu definition");
    selectRow(window_,@"table_",1);
    download=[window_ menuForToolbarIdentifier:@"library"];
    invoke(window_,choice(quality,@"High (137+140)"));
    requireCondition([[library_ jobsForPlaylist:nil completedOnly:NO] count]==3,@"Quality selection started a download");
    invoke(window_,choice(quality,@"Custom Format…"));
    [[window_ valueForKey:@"customFormat_"] setStringValue:@"invalid-format"];
    NSButton *save=[[[NSButton alloc] init] autorelease]; [save setTag:1]; [window_ dismissDownload:save];
    requireCondition([window_ hasAttachedSheet],@"Invalid quality must keep the sheet open");
    [[window_ valueForKey:@"customFormat_"] setStringValue:@"22"];
    [window_ dismissDownload:save]; pump();
    requireCondition([[RDLPLibrary preferredFormat] isEqualToString:@"22"] && [[library_ jobsForPlaylist:nil completedOnly:NO] count]==3,@"Saving custom quality must not enqueue");
    invoke(window_,choice(quality,@"Custom Format…"));
    [[window_ valueForKey:@"customFormat_"] setStringValue:@"18"]; [save setTag:0]; [window_ dismissDownload:save]; pump();
    requireCondition([[RDLPLibrary preferredFormat] isEqualToString:@"22"],@"Cancelling custom quality changed preference");
    invoke(window_,choice(quality,@"High (137+140)"));
    selectRow(window_,@"table_",0);
    download=[window_ menuForToolbarIdentifier:@"download"];
    [toolbarButton(window_,@"download") performClick:nil]; pump();
    requireCondition([[library_ jobsForPlaylist:nil completedOnly:NO] count]==4 && [[RDLPLibrary preferredFormat] isEqualToString:@"137+140"] && [library_ isPaused],@"Download primary click adds the preferred High quality without deleting the existing Low file");
    selectRow(window_,@"sidebar_",1);
    NSString *selectedKey=[[[window_ valueForKey:@"selectedPlaylist_"] copy] autorelease];
    [outline collapseItem:@"My Playlists"];
    rdapp_store *discoveryStore=NULL;
    requireCondition(rdapp_store_open("/tmp/retrodlp-toolbar-fixture/Support/retrodlp.sqlite",&discoveryStore),@"Could not open isolated discovery store");
    requireCondition(rdapp_store_discovered_playlist(discoveryStore,"PLfixture","Offline test playlist"),@"Discovery promotion failed");
    rdapp_store_close(discoveryStore); [window_ refresh:nil];
    requireCondition([[window_ valueForKey:@"playlists_"] count]==1 && [outline numberOfRows]==6,@"Discovery must not duplicate playlist");
    requireCondition([[outline itemAtRow:3] isEqual:@"My Playlists"] && [[outline itemAtRow:4] isEqual:selectedKey],@"Discovered playlist must move to My Playlists");
    requireCondition([[window_ valueForKey:@"selectedPlaylist_"] isEqual:selectedKey] && [outline selectedRow]==4,@"Promotion must preserve selected playlist");
    requireCondition(rdapp_store_open("/tmp/retrodlp-toolbar-fixture/Support/retrodlp.sqlite",&discoveryStore),@"Open unsupported playlist fixture");
    requireCondition(rdapp_store_discovered_playlist(discoveryStore,"WL","Watch Later") && rdapp_store_discovered_playlist(discoveryStore,"HL","History"),@"Discover unsupported playlists");
    rdapp_store_close(discoveryStore); [window_ refresh:nil];
    requireCondition([window_ outlineView:outline numberOfChildrenOfItem:@"My Playlists"]==1 && [window_ outlineView:outline numberOfChildrenOfItem:@"Unsupported Playlists"]==2,@"Unsupported types have a separate outline group");
    [outline expandItem:@"Unsupported Playlists"];
    NSArray *unsupported=[library_ unsupportedPlaylists];
    NSDictionary *unsupportedPlaylist=[unsupported objectAtIndex:0];
    [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[outline rowForItem:[[window_ valueForKey:@"sidebarItems_"] objectForKey:[unsupportedPlaylist objectForKey:@"id"]]]] byExtendingSelection:NO];
    [window_ tableWasUsed:outline];
    requireCondition([[window_ valueForKey:@"selectedPlaylist_"] isEqual:[unsupportedPlaylist objectForKey:@"id"]],@"Unsupported playlist is selected by its outline identity");
    NSMenuItem *unsupportedSyncItem=[[[NSMenuItem alloc] initWithTitle:@"Sync" action:@selector(sync:) keyEquivalent:@""] autorelease];
    requireCondition(![window_ validateMenuItem:unsupportedSyncItem],@"Unsupported playlist disables manual Sync");
    NSArray *syncInputs=[window_ performSelector:@selector(syncPlan)];
    requireCondition([syncInputs count]==1 && ![syncInputs containsObject:@"WL"] && ![syncInputs containsObject:@"HL"],@"Bulk sync skips unsupported types");
    NSUInteger commandsBefore=[[library_ valueForKey:@"commands_"] count];
    [library_ syncPlaylistInput:@"WL"]; [library_ syncPlaylistInput:@"https://www.youtube.com/playlist?list=HL"];
    requireCondition([[library_ valueForKey:@"commands_"] count]==commandsBefore && ![library_ isBusy],@"Direct and automatic submissions cannot schedule unsupported syncs");
    [library_ removePlaylist:[unsupported objectAtIndex:0]]; [library_ removePlaylist:[unsupported objectAtIndex:1]];
    [window_ refresh:nil]; selectRow(window_,@"sidebar_",1);
    /* Missing CA makes these real worker attempts fail locally before networking. */
    NSUInteger attempts=0; NSEnumerator *jobEnumerator=[[library_ jobsForPlaylist:nil completedOnly:NO] objectEnumerator]; NSDictionary *pendingJob;
    while((pendingJob=[jobEnumerator nextObject])) if([[pendingJob objectForKey:@"state"] isEqualToString:@"queued"]) ++attempts;
    requireCondition(attempts>0,@"Progress test needs queued jobs");
    [library_ startDownloads];
    requireCondition(![library_ isPaused],@"Mac startup must enable automatic processing");
    NSDictionary *progress=[library_ queueProgress];
    requireCondition([[progress objectForKey:@"active"] boolValue] && [[progress objectForKey:@"running"] boolValue] && [[progress objectForKey:@"total"] unsignedLongValue]==attempts && [[progress objectForKey:@"processed"] unsignedLongValue]==0,@"New queue run must exclude historical jobs");
    requireCondition(![[window_ valueForKey:@"queueProgress_"] isHidden],@"Processing must show the progress bar");
    [library_ setPaused:YES]; pump();
    requireCondition([[window_ valueForKey:@"queueProgress_"] isHidden],@"Stopped work hides transfer progress even while the queue remains paused");
    [library_ setPaused:NO];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:20];
    while(([[[library_ queueProgress] objectForKey:@"active"] boolValue] || [library_ isBusy]) && [deadline timeIntervalSinceNow]>0) pump();
    progress=[library_ queueProgress];
    requireCondition(![[progress objectForKey:@"active"] boolValue] && [[progress objectForKey:@"processed"] unsignedLongValue]==attempts && [[progress objectForKey:@"failed"] unsignedLongValue]==attempts,@"Queue must count failed attempts separately and finish the run");
    requireCondition([[window_ valueForKey:@"queueProgress_"] isHidden],@"Drained queue must hide the progress area");
    selectRow(window_,@"sidebar_",1);
    NSMenuItem *syncItem=[[[NSMenuItem alloc] initWithTitle:@"Sync" action:@selector(sync:) keyEquivalent:@""] autorelease];
    requireCondition([toolbarButton(window_,@"library") isDefaultEnabled] && [window_ validateMenuItem:syncItem],
      [NSString stringWithFormat:@"Idle playlist can sync from toolbar and menu (Add=%d, Sync=%d, sheet=%d, context=%@, playlist=%@, pending=%d)",
        [toolbarButton(window_,@"library") isDefaultEnabled], [window_ validateMenuItem:syncItem], [window_ hasAttachedSheet],
        [window_ valueForKey:@"context_"], [window_ valueForKey:@"selectedPlaylist_"], [library_ isSyncPendingForInput:@"PLfixture"]]);
    /* Sync lives in Library’s menu; dispatch without click animation so the
       local worker cannot finish before inspecting its in-flight state. */
    NSMenuItem *toolbarSync=choice([window_ menuForToolbarIdentifier:@"library"],@"Sync Current Playlist");
    [NSApp sendAction:[toolbarSync action] to:[toolbarSync target] from:toolbarSync];
    requireCondition([library_ isBusy] && ![[[library_ queueProgress] objectForKey:@"active"] boolValue] && ![[window_ valueForKey:@"queueProgress_"] isHidden],@"Metadata work uses indeterminate activity progress");
    requireCondition([toolbarButton(window_,@"library") isDefaultEnabled] && ![window_ validateMenuItem:syncItem] && ![toolbarButton(window_,@"remove") isDefaultEnabled],@"Active sync disables duplicate sync and deletion while Library remains available");
    requireCondition([library_ operationCount]==1 && [toolbarButton(window_,@"cookies") isDefaultEnabled] &&
      ![window_ validateMenuItem:choice(cookiesMenu,@"Import Cookies…")],@"Active sync disables cookie changes while its menu and export guide remain available");
    deadline=[NSDate dateWithTimeIntervalSinceNow:20];
    while([library_ isBusy] && [deadline timeIntervalSinceNow]>0) pump();
    requireCondition(![library_ isBusy],@"Local metadata failure did not finish");
    requireCondition([toolbarButton(window_,@"library") isDefaultEnabled] && [window_ validateMenuItem:syncItem],@"Finished playlist sync restores toolbar and menu actions");
    requireCondition([library_ operationCount]==0 && ![library_ isSyncPendingForInput:@"PLfixture"] &&
      [toolbarButton(window_,@"cookies") isDefaultEnabled] &&
      [window_ validateMenuItem:choice(cookiesMenu,@"Import Cookies…")],@"Finished sync releases its operation and restores cookie controls");
    [library_ setPaused:YES];
    jobEnumerator=[[library_ jobsForPlaylist:nil completedOnly:NO] objectEnumerator];
    while((pendingJob=[jobEnumerator nextObject])) if([[pendingJob objectForKey:@"state"] isEqualToString:@"failed"]) break;
    requireCondition(pendingJob!=nil,@"Expected a failed attempt to retry");
    [library_ retryJob:[pendingJob objectForKey:@"id"]]; [library_ setPaused:NO];
    progress=[library_ queueProgress];
    requireCondition([[progress objectForKey:@"total"] unsignedLongValue]==1 && [[progress objectForKey:@"processed"] unsignedLongValue]==0 && [[progress objectForKey:@"failed"] unsignedLongValue]==0,@"A later run must reset all progress counters");
    deadline=[NSDate dateWithTimeIntervalSinceNow:20];
    while(([[[library_ queueProgress] objectForKey:@"active"] boolValue] || [library_ isBusy]) && [deadline timeIntervalSinceNow]>0) pump();
    requireCondition(![[[library_ queueProgress] objectForKey:@"active"] boolValue],@"Retried run did not drain");
    requireCondition(rdapp_store_open("/tmp/retrodlp-toolbar-fixture/Support/retrodlp.sqlite",&discoveryStore),@"Open Ad-Hoc fixture");
    requireCondition(rdapp_store_add_adhoc(discoveryStore,"ABCDEFGHIJK","Individual video",NULL),@"Add Ad-Hoc fixture");
    rdapp_store_close(discoveryStore); [window_ refresh:nil];
    NSDictionary *adhoc=[library_ adhocPlaylist];
    requireCondition(adhoc!=nil && [[library_ playlistsFromAccount:NO] count]==0 && [[library_ playlistsFromAccount:YES] count]==1,@"Ad-Hoc stays outside playlist groups");
    requireCondition([window_ outlineView:outline numberOfChildrenOfItem:@"System"]==2,@"System contains Ad-Hoc");
    id adhocItem=[[window_ valueForKey:@"sidebarItems_"] objectForKey:[adhoc objectForKey:@"id"]];
    [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[outline rowForItem:adhocItem]] byExtendingSelection:NO];
    [window_ tableWasUsed:outline];
    requireCondition([toolbarButton(window_,@"library") isDefaultEnabled] && ![toolbarButton(window_,@"remove") isDefaultEnabled],@"Ad-Hoc keeps Library available and cannot be deleted");
    requireCondition(![window_ validateMenuItem:[[[NSMenuItem alloc] initWithTitle:@"Sync" action:@selector(sync:) keyEquivalent:@""] autorelease]],@"Ad-Hoc menu sync is disabled");
    [window_ addVideo:nil]; pump();
    requireCondition([[[window_ valueForKey:@"addSheet_"] title] isEqualToString:@"Add Video"],@"Mac Add Video sheet opens");
    [library_ setPaused:YES];
    [[window_ valueForKey:@"input_"] setStringValue:@"https://youtu.be/LMNOPQRSTUV"];
    [NSApp endSheet:[window_ valueForKey:@"addSheet_"] returnCode:1]; pump();
    NSDictionary *addedJob=[library_ jobForPlaylist:[adhoc objectForKey:@"id"] video:@"LMNOPQRSTUV" format:[RDLPLibrary preferredFormat]];
    requireCondition([[addedJob objectForKey:@"state"] isEqualToString:@"queued"] && [[addedJob objectForKey:@"title"] isEqualToString:@"LMNOPQRSTUV"],@"Mac Add Video sheet queues immediately without network access");
    testMacErrorAlert(window_);
    report=@"PASS: Ad-Hoc grouping and disabled sync, Add Video sheet, shared status expiry, native error alerts, saved VLC/QuickTime/Default App preference and unavailable-player fallback, download policy, textured window, flat five-column queue, exact-quality menu actions, selection stability, transfer progress, queue accounting and local failures, sidebar outline groups, discovery promotion, fixed toolbar labels, six toolbar responsibilities, download/stop states and separate removal, contextual menus, cancellation and retry; no network requests.";

  } @catch(NSException *exception) { report=[NSString stringWithFormat:@"FAIL: %@",exception]; }
  [report writeToFile:@"/tmp/retrodlp-toolbar-test.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  [library_ shutdown];
  [NSApp terminate:nil];
}
@end
int main(void) {
  /* This synchronous test keeps autoreleased read snapshots across many UI
     actions. Real AppKit events drain their pools between actions. Tiger's
     default 256 descriptors cannot hold the entire test callback's snapshots. */
  struct rlimit files;
  if(getrlimit(RLIMIT_NOFILE,&files)==0 && files.rlim_cur<4096) {
    files.rlim_cur=files.rlim_max<4096?files.rlim_max:4096;
    setrlimit(RLIMIT_NOFILE,&files); /* Test process only; leave the hard limit intact. */
  }
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  if(getenv("RDPlaybackTestOnly")) {
    char directory[]="/tmp/retrodlp-playback-test.XXXXXX";
    int result=0;
    if(!mkdtemp(directory)) { [pool drain]; return 1; }
    @try {
      [RDLPPlaybackProbe checkPlaylistsInDirectory:[NSString stringWithUTF8String:directory]];
      NSString *application=[RDLPAppKit VLCApplication];
      if(application) requireCondition([[RDLPAppKit VLCVersion] isEqual:[[[NSBundle bundleWithPath:application] infoDictionary] objectForKey:@"CFBundleShortVersionString"]],@"Read installed VLC version from its bundle");
      printf("PASS: native VLC version selection, playlist dispatch, missing-file safety, and video playback paths\n");
    } @catch(NSException *exception) { fprintf(stderr,"FAIL: %s\n",[[exception description] UTF8String]); result=1; }
    [[NSFileManager defaultManager] removeFileAtPath:[NSString stringWithUTF8String:directory] handler:nil];
    [pool drain]; return result;
  }
  NSApplication *app=[RDLPApplication sharedApplication]; RDLPToolbarTest *delegate=[[RDLPToolbarTest alloc] init];
  [RDLPAppKit setApplication:app delegate:delegate]; [app run]; [delegate release]; [pool drain]; return 0;
}
