#import <UIKit/UIKit.h>
@class RDLPStatusBarView, RDLPLibrary;
@interface RDLPUIKit : NSObject
+ (void)configureContentEdges:(UIViewController *)controller;
+ (UIImage *)statusIcon:(NSString *)status;
+ (UIImage *)queueActionIcon:(BOOL)stop;
+ (UIImage *)settingsIcon;
+ (UIImage *)plusIcon;
+ (UIImage *)syncIcon;
+ (UIImage *)queueToolbarIcon;
+ (NSArray *)statusToolbarItems:(RDLPStatusBarView *)status target:(id)target queueAction:(SEL)action;
+ (void)showMessage:(NSString *)message;
+ (void)presentPlayer:(UIViewController *)owner library:(RDLPLibrary *)library job:(NSDictionary *)job;
+ (void)presentPlayer:(UIViewController *)owner library:(RDLPLibrary *)library playlist:(NSString *)playlist entry:(NSDictionary *)entry job:(NSDictionary *)job;
+ (UIBarButtonItem *)item:(NSString *)title target:(id)target action:(SEL)action;
@end
