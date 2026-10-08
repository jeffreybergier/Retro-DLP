#import <AppKit/AppKit.h>

@protocol RDLPLibraryMenuContext
- (SEL)defaultActionForToolbarIdentifier:(NSString *)identifier;
- (BOOL)hasTargetVideo;
- (BOOL)hasMultipleTargetVideos;
- (NSDictionary *)contextPlaylist;
- (NSDictionary *)targetJob;
- (BOOL)canRetry:(NSDictionary *)job;
- (BOOL)canDownloadAgain:(NSDictionary *)job;
@end

/* Builds menus with controller action targets; does not execute commands. */
@interface RDLPLibraryMenus : NSObject
+ (void)addItemToMenu:(NSMenu *)menu title:(NSString *)title action:(SEL)action target:(id)target;
+ (NSMenu *)menuForMenuBarTitle:(NSString *)title target:(id<RDLPLibraryMenuContext>)target;
+ (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier target:(id<RDLPLibraryMenuContext>)target;
+ (void)updateMenu:(NSMenu *)menu target:(id<RDLPLibraryMenuContext>)target;
+ (void)updateDefaultAppearanceForItem:(NSMenuItem *)item target:(id<RDLPLibraryMenuContext>)target;
@end
