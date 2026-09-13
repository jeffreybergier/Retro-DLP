#import <AppKit/AppKit.h>
NSString *RDChooseCookieFile(void);
void RDBeginAlertSheet(NSAlert *alert, NSWindow *window, id delegate, SEL didEnd);
NSImage *RDYouTubeIcon(CGFloat scale);
NSString *RDDefaultApplication(NSString *path);
void RDOpenDefaultApplication(NSString *path);
void RDRevealInFinder(NSString *path);
void RDAlert(NSString *message);

void RDStyleButton(NSButton *button);
void RDSetAppDelegate(NSApplication *application, id delegate);

void RDBeginSheet(NSWindow *sheet, NSWindow *window, id delegate, SEL didEnd);

CGFloat RDWindowBackingScale(NSWindow *window);

void RDUseExpandedToolbar(NSWindow *window);

void RDOpenInVLC(NSString *path);
