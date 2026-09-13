#import <AppKit/AppKit.h>
#import "LibraryWindow.h"
#import "XPAppKit.h"
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
  NSMenu *mainMenu=[[[NSMenu alloc] initWithTitle:@""] autorelease]; NSMenu *app=[[[NSMenu alloc] initWithTitle:@"RetroDLP"] autorelease];
  NSMenuItem *item=[mainMenu addItemWithTitle:@"RetroDLP" action:NULL keyEquivalent:@""]; [mainMenu setSubmenu:app forItem:item];
  [[app addItemWithTitle:@"Import Cookies…" action:@selector(importCookies:) keyEquivalent:@"i"] setTarget:window_];
  [[app addItemWithTitle:@"Clear Cookies" action:@selector(clearCookies:) keyEquivalent:@""] setTarget:window_];
  [app addItem:[NSMenuItem separatorItem]]; [app addItemWithTitle:@"Quit RetroDLP" action:@selector(terminate:) keyEquivalent:@"q"];
  NSMenu *edit=[[[NSMenu alloc] initWithTitle:@"Edit"] autorelease]; item=[mainMenu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""]; [mainMenu setSubmenu:edit forItem:item];
  [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"]; [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"]; [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
  [NSApp setMainMenu:mainMenu]; [window_ showWindow:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible;
{ (void)application; (void)visible; [window_ showWindow:nil]; return YES; }
- (void)applicationWillTerminate:(NSNotification *)notification;
{ (void)notification; [library_ shutdown]; }
- (void)dealloc; { [window_ release]; [library_ release]; [super dealloc]; }
@end
int main(int argc,char **argv) {
  (void)argc; (void)argv; NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSApplication *app=[NSApplication sharedApplication]; AppDelegate *delegate=[[AppDelegate alloc] init];
  RDSetAppDelegate(app,delegate); [app run]; [delegate release]; [pool drain]; return 0;
}
