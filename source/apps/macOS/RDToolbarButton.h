#import <AppKit/AppKit.h>
/* The primary action and the menu have independent availability. */
@interface RDToolbarButton : NSButton {
  BOOL defaultEnabled_;
  NSImage *caret_;
  NSRect caretInkBounds_;
}
- (BOOL)isDefaultEnabled;
- (void)setDefaultEnabled:(BOOL)enabled;
- (void)setCaretImage:(NSImage *)image;
- (void)showOptions:(id)sender;
@end

/* Tiger's toolbar host consumes secondary clicks before the custom view. */
@interface RDApplication : NSApplication {
  RDToolbarButton *pendingMenuButton_;
}
@end
