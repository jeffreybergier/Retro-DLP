#import <AppKit/AppKit.h>
#import "LibraryWindow.h"
#import "XPAppKit.h"
#import "RDToolbarButton.h"
@interface AppDelegate : NSObject {
  RetroDLPLibrary *library_; LibraryWindow *window_;
}
@end
@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
  (void)notification;
  NSString *home=NSHomeDirectory();
  NSString *testDirectory=[[NSUserDefaults standardUserDefaults] stringForKey:@"RetroDLPTestDirectory"];
  if(!testDirectory) testDirectory=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"RetroDLPTestDirectory"];
  NSString *support=testDirectory?[testDirectory stringByAppendingPathComponent:@"Support"]:[home stringByAppendingPathComponent:@"Library/Application Support/RetroDLP"];
  NSString *downloads=testDirectory?[testDirectory stringByAppendingPathComponent:@"Downloads"]:[home stringByAppendingPathComponent:@"Documents/RetroDLP"];
  library_=[[RetroDLPLibrary alloc] initWithSupportDirectory:support downloadDirectory:downloads];
  if(!library_) { RDAlert(@"Could not open the RetroDLP library. Check permissions and free space in Documents and Application Support."); [NSApp terminate:nil]; return; }
  window_=[[LibraryWindow alloc] initWithLibrary:library_];
  NSMenu *mainMenu=[[[NSMenu alloc] initWithTitle:@""] autorelease]; NSMenu *app=[[[NSMenu alloc] initWithTitle:@""] autorelease];
  NSMenuItem *item=[mainMenu addItemWithTitle:@"" action:NULL keyEquivalent:@""]; [mainMenu setSubmenu:app forItem:item];
  if([NSApp respondsToSelector:@selector(setAppleMenu:)]) [NSApp performSelector:@selector(setAppleMenu:) withObject:app];
  [[app addItemWithTitle:@"About RetroDLP" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""] setTarget:NSApp];
  [app addItem:[NSMenuItem separatorItem]];
  NSMenu *qualities=[window_ menuForMenuBarTitle:@"Download Quality"];
  item=[app addItemWithTitle:@"Download Quality" action:NULL keyEquivalent:@""]; [app setSubmenu:qualities forItem:item];
  NSMenu *cookies=[window_ menuForMenuBarTitle:@"Cookies"];
  item=[app addItemWithTitle:@"Cookies" action:NULL keyEquivalent:@""]; [app setSubmenu:cookies forItem:item];
  [app addItem:[NSMenuItem separatorItem]];
  [app addItemWithTitle:@"Quit RetroDLP" action:@selector(terminate:) keyEquivalent:@"q"];
  NSArray *titles=[NSArray arrayWithObjects:@"File",@"Edit",@"View",@"Window",@"Help",nil];
  unsigned int index;
  for(index=0;index<[titles count];++index) {
    NSString *title=[titles objectAtIndex:index];
    NSMenu *menu=[window_ menuForMenuBarTitle:title];
    if([title isEqualToString:@"Window"]) {
      [menu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
      [menu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
      [menu addItem:[NSMenuItem separatorItem]];
      [menu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
      [NSApp setWindowsMenu:menu];
    }
    item=[mainMenu addItemWithTitle:title action:NULL keyEquivalent:@""]; [mainMenu setSubmenu:menu forItem:item];
  }
  [NSApp setMainMenu:mainMenu]; [window_ showWindow:nil]; [NSApp activateIgnoringOtherApps:YES];
  [library_ startDownloads];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible;
{ (void)application; (void)visible; [window_ showWindow:nil]; return YES; }
- (void)applicationWillTerminate:(NSNotification *)notification;
{ (void)notification; [library_ shutdown]; }
- (void)dealloc; { [window_ release]; [library_ release]; [super dealloc]; }
@end
int main(int argc,char **argv) {
  (void)argc; (void)argv; NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSApplication *app=[RDApplication sharedApplication]; AppDelegate *delegate=[[AppDelegate alloc] init];
  RDSetAppDelegate(app,delegate); [app run]; [delegate release]; [pool drain]; return 0;
}
