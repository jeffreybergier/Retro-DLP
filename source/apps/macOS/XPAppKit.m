#import "XPAppKit.h"
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
void RDStyleButton(NSButton *button) { [button setBezelStyle:NSRoundedBezelStyle]; }
void RDSetAppDelegate(NSApplication *application,id delegate) { [application setDelegate:delegate]; }
void RDAlert(NSString *message) {
  NSAlert *alert=[[[NSAlert alloc] init] autorelease]; [alert setMessageText:message]; [alert addButtonWithTitle:@"OK"]; [alert runModal];
}
BOOL RDConfirm(NSString *message) {
  NSAlert *alert=[[[NSAlert alloc] init] autorelease]; [alert setMessageText:message];
  [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Remove"]; return [alert runModal]==NSAlertSecondButtonReturn;
}
NSString *RDChooseCookieFile(void) {
  NSOpenPanel *panel=[NSOpenPanel openPanel]; [panel setCanChooseDirectories:NO]; [panel setAllowsMultipleSelection:NO];
  if([panel runModalForDirectory:nil file:nil types:nil]==NSOKButton) return [panel filename];
  return nil;
}
void RDOpenVLC(NSString *path) {
  if(!path || ![[NSWorkspace sharedWorkspace] openFile:path withApplication:@"VLC"])
    RDAlert(@"Could not open this file in VLC. Install VLC and check that the download exists.");
}
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
