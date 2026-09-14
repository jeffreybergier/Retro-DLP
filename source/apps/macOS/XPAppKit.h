#import <AppKit/AppKit.h>
#import <AIFontAwesome.h>
NSString *RDChooseCookieFile(void);
void RDBeginAlertSheet(NSAlert *alert, NSWindow *window, id delegate, SEL didEnd);
/* Control icons use explicit black on every supported OS.
   Informational table icons should keep their normal template rendering. */
NSImage *RDControlIcon(AIFontAwesomeIcon icon, AIFontAwesomeStyle style,
                       CGFloat iconSize, CGFloat canvasSize, CGFloat scale);
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
