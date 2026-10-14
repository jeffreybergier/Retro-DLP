#import "../RDLPLibraryWindowController.h"
#import "../../shared/tests/native_performance.h"
@interface RDLPLibraryWindowController (Performance)
- (void)refresh:(id)sender;
@end
@interface RDLPPerfMac : NSObject <RDLPPerfTable> { RDLPLibraryWindowController *controller_; }
@end
@implementation RDLPPerfMac
- (void)openLibrary:(RDLPLibrary *)library playlist:(NSDictionary *)playlist;
{
  controller_=[[RDLPLibraryWindowController alloc] initWithLibrary:library];
  [controller_ showWindow:nil];
  NSOutlineView *outline=[controller_ valueForKey:@"sidebar_"];
  [outline expandItem:@"Added Playlists"];
  NSInteger row=[outline rowForItem:[[controller_ valueForKey:@"sidebarItems_"] objectForKey:[playlist objectForKey:@"id"]]];
  perfRequire(row>=0,@"Find fixture in real sidebar");
  [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  perfWait(self); [[controller_ window] displayIfNeeded];
}
- (void)scrollToRow:(NSUInteger)row;
{
  NSTableView *table=[controller_ valueForKey:@"table_"];
  [table scrollRowToVisible:(NSInteger)row]; [table displayIfNeeded];
  perfRequire(NSIntersectsRect([table rectOfRow:(NSInteger)row],[table visibleRect]),@"Requested Mac row is visible");
}
- (void)refresh; { [controller_ refresh:nil]; }
- (BOOL)loading; { return [[controller_ valueForKey:@"listLoading_"] boolValue]; }
- (NSArray *)displayRows; { return [controller_ valueForKey:@"videoRows_"]; }
- (void)validateRun; {}
- (void)close; { [controller_ close]; [controller_ release]; controller_=nil; }
- (void)applicationDidFinishLaunching:(NSNotification *)note;
{ (void)note; [self performSelector:@selector(run) withObject:nil afterDelay:0.2]; }
- (void)run;
{
  @try {
    runNativePerformance(self,@"/tmp/retrodlp-performance",@"/tmp/retrodlp-performance.plist");
  } @catch(NSException *exception) {
    [[exception description] writeToFile:@"/tmp/retrodlp-performance-error.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSLog(@"%@",exception); exit(1);
  }
  [NSApp terminate:nil];
}
@end
int main(void) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  [NSApplication sharedApplication]; RDLPPerfMac *delegate=[[RDLPPerfMac alloc] init];
  [NSApp setDelegate:delegate]; [NSApp run]; [delegate release]; [pool drain]; return 0;
}
