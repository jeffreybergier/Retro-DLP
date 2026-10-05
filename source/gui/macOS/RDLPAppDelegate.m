#import "RDLPAppDelegate.h"
#import "RDLPAppKit.h"

@interface RDLPAppDelegate (Errors)
- (void)errorsChanged:(id)sender;
- (void)showNextError;
@end
@implementation RDLPAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
  (void)notification;
  NSString *home=NSHomeDirectory();
  NSString *testDirectory=[[NSUserDefaults standardUserDefaults] stringForKey:@"RetroDLPTestDirectory"];
  if(!testDirectory) testDirectory=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"RetroDLPTestDirectory"];
  NSString *support=testDirectory?[testDirectory stringByAppendingPathComponent:@"Support"]:[home stringByAppendingPathComponent:@"Library/Application Support/RetroDLP"];
  NSString *downloads=testDirectory?[testDirectory stringByAppendingPathComponent:@"Downloads"]:[home stringByAppendingPathComponent:@"Documents/RetroDLP"];
  library_=[[RDLPLibrary alloc] initWithSupportDirectory:support downloadDirectory:downloads];
  if(!library_) { [RDLPAppKit showAlert:NSLocalizedString(@"Could not open the RetroDLP library. Check permissions and free space in Documents and Application Support.", nil)]; [NSApp terminate:nil]; return; }
  window_=[[RDLPLibraryWindowController alloc] initWithLibrary:library_];
  NSMenu *mainMenu=[[[NSMenu alloc] initWithTitle:@""] autorelease]; NSMenu *app=[[[NSMenu alloc] initWithTitle:@""] autorelease];
  NSMenuItem *item=[mainMenu addItemWithTitle:@"" action:NULL keyEquivalent:@""]; [mainMenu setSubmenu:app forItem:item];
  if([NSApp respondsToSelector:@selector(setAppleMenu:)]) [NSApp performSelector:@selector(setAppleMenu:) withObject:app];
  [[app addItemWithTitle:NSLocalizedString(@"About RetroDLP", nil) action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""] setTarget:NSApp];
  [app addItem:[NSMenuItem separatorItem]];
  NSMenu *qualities=[window_ menuForMenuBarTitle:@"Download Quality"];
  item=[app addItemWithTitle:NSLocalizedString(@"Download Quality", nil) action:NULL keyEquivalent:@""]; [app setSubmenu:qualities forItem:item];
  NSMenu *players=[window_ menuForMenuBarTitle:@"Video Player"];
  item=[app addItemWithTitle:NSLocalizedString(@"Video Player", nil) action:NULL keyEquivalent:@""]; [app setSubmenu:players forItem:item];
  NSMenu *cookies=[window_ menuForMenuBarTitle:@"Cookies"];
  item=[app addItemWithTitle:NSLocalizedString(@"Cookies", nil) action:NULL keyEquivalent:@""]; [app setSubmenu:cookies forItem:item];
  [app addItem:[NSMenuItem separatorItem]];
  [app addItemWithTitle:NSLocalizedString(@"Quit RetroDLP", nil) action:@selector(terminate:) keyEquivalent:@"q"];
  NSArray *titles=[NSArray arrayWithObjects:@"File",@"Edit",@"View",@"Window",@"Help",nil];
  unsigned int index;
  for(index=0;index<[titles count];++index) {
    NSString *title=[titles objectAtIndex:index];
    NSMenu *menu=[window_ menuForMenuBarTitle:title];
    if([title isEqualToString:@"Window"]) {
      [[menu addItemWithTitle:NSLocalizedString(@"Download Queue", nil) action:@selector(showQueue:) keyEquivalent:@""] setTarget:window_];
      [menu addItem:[NSMenuItem separatorItem]];
      [menu addItemWithTitle:NSLocalizedString(@"Minimize", nil) action:@selector(performMiniaturize:) keyEquivalent:@"m"];
      [menu addItemWithTitle:NSLocalizedString(@"Zoom", nil) action:@selector(performZoom:) keyEquivalent:@""];
      [menu addItem:[NSMenuItem separatorItem]];
      [menu addItemWithTitle:NSLocalizedString(@"Bring All to Front", nil) action:@selector(arrangeInFront:) keyEquivalent:@""];
      [NSApp setWindowsMenu:menu];
    }
    item=[mainMenu addItemWithTitle:NSLocalizedString(title, nil) action:NULL keyEquivalent:@""]; [mainMenu setSubmenu:menu forItem:item];
  }
  [NSApp setMainMenu:mainMenu]; [window_ showWindow:nil]; [NSApp activateIgnoringOtherApps:YES];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(errorsChanged:) name:RDLPLibraryErrorDidOccur object:library_];
  [self errorsChanged:nil]; [library_ startDownloads];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible;
{ (void)application; (void)visible; [window_ showWindow:nil]; return YES; }
- (void)applicationWillTerminate:(NSNotification *)notification;
{ (void)notification; [library_ shutdown]; }
- (void)errorsChanged:(id)sender;
{
  (void)sender;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showNextError) object:nil];
  [self performSelector:@selector(showNextError) withObject:nil afterDelay:0.1];
}
- (void)showNextError;
{
  if(showingError_ || ![library_ hasErrors]) return;
  if([window_ hasAttachedSheet] || [NSApp modalWindow]) { [self errorsChanged:nil]; return; }
  NSDictionary *error=[library_ takeError]; if(!error) return;
  showingError_=YES;
  NSAlert *alert=[[[NSAlert alloc] init] autorelease];
  [alert setMessageText:[error objectForKey:@"title"]];
  [alert setInformativeText:[error objectForKey:@"detail"]];
  [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)]; [alert runModal];
  showingError_=NO; [self errorsChanged:nil];
}
- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [window_ release]; [library_ release]; [super dealloc];
}
@end
