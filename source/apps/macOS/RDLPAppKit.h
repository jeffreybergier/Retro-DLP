#import <AppKit/AppKit.h>
#import <AIFontAwesome.h>

/* Runtime and drawing compatibility for Tiger through modern macOS. */
@interface RDLPAppKit : NSObject
+ (CGFloat)backingScaleForWindow:(NSWindow *)window;
+ (void)useExpandedToolbar:(NSWindow *)window;
+ (void)beginSheet:(NSWindow *)sheet forWindow:(NSWindow *)window delegate:(id)delegate didEnd:(SEL)didEnd;
+ (void)styleButton:(NSButton *)button;
+ (void)setApplication:(NSApplication *)application delegate:(id)delegate;
+ (void)showAlert:(NSString *)message;
+ (void)beginAlertSheet:(NSAlert *)alert forWindow:(NSWindow *)window delegate:(id)delegate didEnd:(SEL)didEnd;
+ (NSImage *)controlIcon:(AIFontAwesomeIcon)icon style:(AIFontAwesomeStyle)style iconSize:(CGFloat)iconSize canvasSize:(CGFloat)canvasSize scale:(CGFloat)scale;
+ (NSImage *)youTubeIconForScale:(CGFloat)scale;
+ (NSString *)chooseCookieFile;
+ (void)revealInFinder:(NSString *)path;
/* Automatic playback prefers VLC; explicit Default App commands remain separate. */
+ (NSString *)VLCApplication;
+ (NSString *)preferredPlaybackApplication:(NSString *)path;
+ (void)openPreferredPlayback:(NSString *)path;
+ (NSString *)defaultApplication:(NSString *)path;
+ (void)openInVLC:(NSString *)path;
+ (void)openDefaultApplication:(NSString *)path;
@end
