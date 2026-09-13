#import <AppKit/AppKit.h>
NSString *RDChooseCookieFile(void);
BOOL RDConfirm(NSString *message);
void RDOpenVLC(NSString *path);
void RDAlert(NSString *message);

void RDStyleButton(NSButton *button);
void RDSetAppDelegate(NSApplication *application, id delegate);
