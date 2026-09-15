/* Run in an isolated app bundle WITHOUT cacert.pem, using a fresh
   prepare_native_fixture.py library at /tmp/retrodlp-toolbar-fixture.
   Exercises real AppKit controls and sheets; never approves network work. */
#import "../macOS/RDLPLibraryWindowController.h"
#import "../macOS/RDLPToolbarButton.h"
#import "../macOS/RDLPAppKit.h"
#import "../macOS/RDLPAppDelegate.h"
#import "../shared/rdapp_store.h"
#import <math.h>
#include <sys/resource.h>
@interface RDLPLibraryWindowController (RDLPToolbarTest)
- (void)tableWasUsed:(NSTableView *)view;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)refresh:(id)sender;
- (void)showJobInQueue:(NSDictionary *)job;
- (void)hideQueue:(id)sender;
- (NSDictionary *)selectedJob;
- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
- (NSString *)tableView:(NSTableView *)view toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column row:(NSInteger)row mouseLocation:(NSPoint)point;
- (void)dismissDownload:(id)sender;
- (void)clearCookies:(id)sender;
@end
#import "shared_status_test.h"
#import "shared_metadata_test.h"
#import "shared_video_rows_test.h"

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
static BOOL probeVLC, probeDefault;
static NSString *probeOpened;
@interface RDLPPlaybackProbe : RDLPAppKit
+ (void)checkFile:(NSString *)path;
@end
@implementation RDLPPlaybackProbe
+ (NSString *)VLCApplication { return probeVLC?@"/Applications/VLC.app":nil; }
+ (NSString *)defaultApplication:(NSString *)path { (void)path; return probeDefault?@"/Applications/QuickTime Player.app":nil; }
+ (void)openInVLC:(NSString *)path { (void)path; probeOpened=@"VLC"; }
+ (void)openDefaultApplication:(NSString *)path { (void)path; probeOpened=@"Default"; }
+ (void)checkFile:(NSString *)path {
  probeVLC=YES; probeDefault=YES;
  requireCondition([[self preferredPlaybackApplication:path] isEqual:[self VLCApplication]],@"Installed VLC must take priority over the system association");
  probeOpened=nil; [self openPreferredPlayback:path];
  requireCondition([probeOpened isEqual:@"VLC"],@"Automatic playback must dispatch to VLC only");
  probeDefault=NO;
  requireCondition([[self preferredPlaybackApplication:path] isEqual:[self VLCApplication]],@"VLC must work without a system file association");
  probeVLC=NO; probeDefault=YES;
  requireCondition([[self preferredPlaybackApplication:path] isEqual:[self defaultApplication:path]],@"Absent VLC must select the system default");
  probeOpened=nil; [self openPreferredPlayback:path];
  requireCondition([probeOpened isEqual:@"Default"],@"Absent VLC must dispatch to the system default");
  probeDefault=NO;
  requireCondition([self preferredPlaybackApplication:path]==nil,@"No installed handler must preserve Finder fallback");
  probeVLC=YES; probeOpened=nil;
  [self openPreferredPlayback:nil]; [self openPreferredPlayback:[path stringByAppendingString:@".missing"]];
  requireCondition(probeOpened==nil && [self preferredPlaybackApplication:nil]==nil &&
    [self preferredPlaybackApplication:[path stringByAppendingString:@".missing"]]==nil,@"Missing media must not launch a player");
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
    [outline expandItem:@"System"]; [outline expandItem:@"Added Playlists"]; [outline expandItem:@"My Playlists"];
    row=(NSUInteger)[outline rowForItem:item];
  }
  [window tableWasUsed:table]; [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; [window tableWasUsed:table];
}
static NSMenuItem *choice(NSMenu *menu,NSString *title) {
  NSMenuItem *item=[menu itemWithTitle:title]; requireCondition(item!=nil,[NSString stringWithFormat:@"Missing fixed menu item %@",title]); return item;
}
static void invoke(RDLPLibraryWindowController *window,NSMenuItem *item) {
  requireCondition([window validateMenuItem:item],[NSString stringWithFormat:@"Unexpected disabled action %@",[item title]]);
  [[item target] performSelector:[item action] withObject:item]; pump();
}
static void confirm(RDLPLibraryWindowController *window,BOOL accept) {
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
    library_=[[RDLPLibrary alloc] initWithSupportDirectory:@"/tmp/retrodlp-toolbar-fixture/Support" downloadDirectory:@"/tmp/retrodlp-toolbar-fixture/Downloads"];
    requireCondition(library_!=nil,@"Fixture failed to open");
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
    [window_ toggleSidebar:nil]; [window_ toggleInspector:nil]; pump();
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
      requireCondition([[job objectForKey:@"id"] intValue]>previousID,@"Queue follows processing order"); previousID=[[job objectForKey:@"id"] intValue];
      requireCondition([[window_ tableView:queueTable objectValueForTableColumn:[queueColumns objectAtIndex:0] row:(NSInteger)queueIndex] unsignedLongValue]==queueIndex+1,@"Display numbers are consecutive");
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
    requireCondition([outline numberOfRows]==5 && [[outline itemAtRow:0] isEqual:@"System"] && [[outline itemAtRow:2] isEqual:@"Added Playlists"] && [[outline itemAtRow:4] isEqual:@"My Playlists"],@"Expected three groups and fixture children");
    [outline collapseItem:@"Added Playlists"]; [window_ refresh:nil];
    requireCondition(![outline isItemExpanded:@"Added Playlists"],@"Refresh must retain collapsed group");
    [outline expandItem:@"Added Playlists"];
    NSDictionary *items=[window_ valueForKey:@"toolbarItems_"];
    requireCondition([items count]==4 && [items objectForKey:@"download"] && [items objectForKey:@"play"],@"Expected Download and Play toolbar items");
    requireCondition(![toolbarButton(window_,@"play") isDefaultEnabled],@"No selection must disable Play");
    NSMenu *fileMenu=[window_ menuForMenuBarTitle:@"File"];
    NSMenu *editMenu=[window_ menuForMenuBarTitle:@"Edit"];
    NSMenu *viewMenu=[window_ menuForMenuBarTitle:@"View"];
    requireCondition([fileMenu itemWithTitle:@"Delete Download…"]==nil && [editMenu itemWithTitle:@"Delete Download…"]!=nil,@"Deletion belongs in Edit");
    requireCondition([viewMenu itemWithTitle:@"Download Queue"]==nil && [viewMenu itemWithTitle:@"Show in Queue"]!=nil,@"View contains visibility and navigation only");
    requireCondition(![window_ validateMenuItem:choice(fileMenu,@"Play Playlist in Default App")],@"File playback is disabled without a selection");
    [fileMenu update];
    NSArray *fileTitles=[[titles(fileMenu) copy] autorelease];
    [fileMenu update];
    requireCondition([fileTitles isEqual:titles(fileMenu)],@"Unavailable File commands retain their positions");
    requireCondition([RDLPAppKit youTubeIconForScale:1]!=nil,@"YouTube Brands icon missing");
    NSMenu *download=[window_ menuForToolbarIdentifier:@"download"];
    NSMenu *play=[window_ menuForToolbarIdentifier:@"play"];
    requireCondition([download itemWithTitle:@"Add Playlist…"]!=nil,@"Global Add must remain available");
    requireCondition([play itemWithTitle:@"Open With…"]==nil,@"Open With must remain absent");
    selectRow(window_,@"sidebar_",1);
    download=[window_ menuForToolbarIdentifier:@"download"]; play=[window_ menuForToolbarIdentifier:@"play"];
    NSArray *playlistTitles=[[titles(download) copy] autorelease];
    requireCondition([download itemWithTitle:@"Remove Playlist…"]!=nil && ![download itemWithTitle:@"Delete Download…"],@"Sidebar must expose playlist operations");
    requireCondition([window_ validateMenuItem:choice(play,@"Reveal Playlist in Finder")],@"Playlist folder must reveal");
    requireCondition([window_ validateMenuItem:choice(play,@"Play Playlist in Default App")]==([RDLPAppKit defaultApplication:[library_ playlistFile:[[library_ playlists] objectAtIndex:0]]]!=nil),@"Playlist playback must use its exported file");
    NSTableView *videosTable=[window_ valueForKey:@"table_"];
    NSArray *videoColumnIDs=[NSArray arrayWithObjects:@"state",@"size",@"quality",@"title",@"channel",nil];
    requireCondition([[[videosTable tableColumns] valueForKey:@"identifier"] isEqual:videoColumnIDs],@"Playlist columns follow Status, Size, Quality, Video, Channel order");
    requireCondition([[window_ tableView:videosTable objectValueForTableColumn:[videosTable tableColumnWithIdentifier:@"channel"] row:0] isEqualToString:@"Example Channel"],@"Playlist Channel column");
    NSString *metadataTip=[window_ tableView:videosTable toolTipForCell:nil rect:NULL tableColumn:[videosTable tableColumnWithIdentifier:@"title"] row:0 mouseLocation:NSZeroPoint];
    requireCondition([metadataTip rangeOfString:@"At last sync: 1.2K views · Published 2 days ago"].location!=NSNotFound && [metadataTip rangeOfString:@"Available snippet"].location!=NSNotFound,@"Video tooltip includes original labels and snippet");
    requireCondition([[[[videosTable tableColumns] objectAtIndex:0] identifier] isEqualToString:@"state"] && [[[[[videosTable tableColumns] objectAtIndex:0] headerCell] stringValue] length]==0,@"Status must be the untitled first column");
    requireCondition([[videosTable enclosingScrollView] hasHorizontalScroller],@"Narrow panes allow scrolling to all metadata columns");
    NSMenu *bulk=[choice(download,@"Download Quality") submenu];
    invoke(window_,choice(bulk,@"High (137+140)"));
    requireCondition(![[window_ window] attachedSheet] && [[library_ jobsForPlaylist:nil completedOnly:NO] count]==3,@"Choosing High must only save the preference");
    selectRow(window_,@"table_",0);
    NSDictionary *available=[window_ performSelector:@selector(targetJob)];
    requireCondition([[available objectForKey:@"format"] isEqualToString:@"18"],@"High preference must still target the existing Low download");
    requireCondition([[window_ performSelector:@selector(statusForJob:) withObject:available] isEqualToString:@"Downloaded"],@"Any existing quality must show Downloaded");
    requireCondition([window_ performSelector:@selector(selectionPlayFile)]!=nil,@"Any existing quality must remain playable");
    NSString *preferred=[RDLPAppKit preferredPlaybackApplication:[library_ fileForJob:complete]];
    if([RDLPAppKit VLCApplication]) requireCondition([preferred isEqual:[RDLPAppKit VLCApplication]],@"Real installed VLC must be the preferred player");
    if(preferred) requireCondition([[toolbarButton(window_,@"play") toolTip] rangeOfString:
      [[[NSFileManager defaultManager] displayNameAtPath:preferred] stringByDeletingPathExtension]].location!=NSNotFound,
      @"Play tooltip must name the application that automatic playback will open");
    requireCondition([choice([window_ menuForToolbarIdentifier:@"play"],@"Play Video in Default App") action]==@selector(playSelectionInDefaultApplication:),
      @"Explicit Default App must remain separate from automatic Play");
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
    invoke(window_,choice(download,@"Download Missing Videos")); confirm(window_,NO);
    invoke(window_,choice(bulk,@"Low (18)"));
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
    invoke(window_,choice([choice(download,@"Download Quality") submenu],@"Med (136+140)"));
    requireCondition([window_ validateMenuItem:choice(download,@"Download Video")],@"Download Video must allow failed jobs at the selected quality");
    invoke(window_,choice([queueTable menu],@"Retry"));
    requireCondition([[[window_ selectedJob] objectForKey:@"id"] isEqual:failedKey] && [queueTable selectedRow]==failedRow && [[[window_ selectedJob] objectForKey:@"state"] isEqual:@"queued"],@"Retry preserves exact job identity and row position");
    requireCondition(![window_ validateMenuItem:choice(download,@"Download Video")] && [window_ validateMenuItem:choice(download,@"Cancel Download…")],@"Queued job must disable duplicate Download Video");
    requireCondition([library_ isPaused] && ![library_ isBusy],@"Explicit retry must preserve Pause");
    invoke(window_,choice([queueTable menu],@"Stop Download…")); confirm(window_,NO);
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
    requireCondition([window_ validateMenuItem:choice(play,@"Play Playlist in Default App")]==([RDLPAppKit defaultApplication:[library_ playlistFile:[[library_ playlists] objectAtIndex:0]]]!=nil),@"Playlist playback must use the Queue video’s playlist rather than sidebar");
    requireCondition([[toolbarButton(window_,@"download") toolTip] rangeOfString:@"(136+140)"].location!=NSNotFound,@"Queue must retain exact selected quality");
    [window_ hideQueue:nil];
    requireCondition(![toolbarButton(window_,@"play") isDefaultEnabled],@"Hidden Queue must not remain the playback target");
    selectRow(window_,@"sidebar_",1);
    download=[window_ menuForToolbarIdentifier:@"download"];
    requireCondition([playlistTitles isEqual:titles(download)],@"Returning to sidebar must restore playlist menu");
    NSMenu *toolbarMenu=[toolbarButton(window_,@"download") menu];
    [window_ performSelector:@selector(menuNeedsUpdate:) withObject:toolbarMenu];
    requireCondition([titles(toolbarMenu) isEqual:titles(download)],@"Toolbar caret and context menu must share the context menu definition");
    selectRow(window_,@"table_",1);
    download=[window_ menuForToolbarIdentifier:@"download"];
    invoke(window_,choice([choice(download,@"Download Quality") submenu],@"High (137+140)"));
    requireCondition([[library_ jobsForPlaylist:nil completedOnly:NO] count]==3,@"Quality selection started a download");
    NSMenu *quality=[choice(download,@"Download Quality") submenu];
    invoke(window_,choice(quality,@"Custom Format…"));
    [[window_ valueForKey:@"customFormat_"] setStringValue:@"invalid-format"];
    NSButton *save=[[[NSButton alloc] init] autorelease]; [save setTag:1]; [window_ dismissDownload:save];
    requireCondition([[window_ window] attachedSheet]!=nil,@"Invalid quality must keep the sheet open");
    [[window_ valueForKey:@"customFormat_"] setStringValue:@"22"];
    [window_ dismissDownload:save]; pump();
    requireCondition([[RDLPLibrary preferredFormat] isEqualToString:@"22"] && [[library_ jobsForPlaylist:nil completedOnly:NO] count]==3,@"Saving custom quality must not enqueue");
    invoke(window_,choice(quality,@"Custom Format…"));
    [[window_ valueForKey:@"customFormat_"] setStringValue:@"18"]; [save setTag:0]; [window_ dismissDownload:save]; pump();
    requireCondition([[RDLPLibrary preferredFormat] isEqualToString:@"22"],@"Cancelling custom quality changed preference");
    invoke(window_,choice(quality,@"High (137+140)"));
    selectRow(window_,@"table_",0);
    download=[window_ menuForToolbarIdentifier:@"download"];
    invoke(window_,choice(download,@"Download Video"));
    requireCondition([[library_ jobsForPlaylist:nil completedOnly:NO] count]==4 && [[RDLPLibrary preferredFormat] isEqualToString:@"137+140"] && [library_ isPaused],@"Direct Download Video must reuse last selected High quality and preserve Pause");
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
    [library_ syncPlaylistInput:@"PLfixture"];
    requireCondition([library_ isBusy] && ![[[library_ queueProgress] objectForKey:@"active"] boolValue] && ![[window_ valueForKey:@"queueProgress_"] isHidden],@"Metadata work uses indeterminate activity progress");
    deadline=[NSDate dateWithTimeIntervalSinceNow:20];
    while([library_ isBusy] && [deadline timeIntervalSinceNow]>0) pump();
    requireCondition(![library_ isBusy],@"Local metadata failure did not finish");
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
    testMacErrorAlert(window_);
    report=@"PASS: shared status expiry, native error alerts, VLC preference and system fallback, download policy, textured window, flat five-column queue, exact-quality menu actions, selection stability, transfer progress, queue accounting and local failures, sidebar outline groups, discovery promotion, Download/Play targeting, adaptive menus, cancellation and retry; no network requests.";

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
  NSApplication *app=[RDLPApplication sharedApplication]; RDLPToolbarTest *delegate=[[RDLPToolbarTest alloc] init];
  [RDLPAppKit setApplication:app delegate:delegate]; [app run]; [delegate release]; [pool drain]; return 0;
}
