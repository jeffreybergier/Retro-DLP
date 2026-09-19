#import "RDLPAppKit.h"

@interface RDLPStatusCell : NSImageCell
@end
@interface RDLPLayoutView : NSView {
  NSMutableArray *designFrames_;
  NSSize designSize_;
}
@end
@interface RDLPTableView : NSTableView
@end
@interface RDLPOutlineView : NSOutlineView
@end
@interface RDLPLibrarySplitView : NSSplitView
@end

@interface RDLPLibraryViews : NSObject
+ (BOOL)isSidebarGroup:(id)item;
+ (NSString *)groupForPlaylist:(NSDictionary *)playlist;
+ (NSOutlineView *)sidebarInView:(NSView *)view owner:(id)owner;
+ (NSButton *)buttonInView:(NSView *)view title:(NSString *)title action:(SEL)action target:(id)target frame:(NSRect)frame;
+ (NSTextField *)fieldInView:(NSView *)view frame:(NSRect)frame editable:(BOOL)editable;
+ (NSTableView *)tableInView:(NSView *)view frame:(NSRect)frame owner:(id)owner names:(NSArray *)names labels:(NSArray *)labels;
+ (NSImage *)toolbarIcon:(AIFontAwesomeIcon)icon window:(NSWindow *)window;
+ (void)restoreSelection:(NSTableView *)view rows:(NSArray *)rows key:(NSString *)key value:(NSString *)value;
@end
