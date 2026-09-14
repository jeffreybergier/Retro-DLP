#import <UIKit/UIKit.h>
@interface RDLPUIKit : NSObject
+ (void)configureContentEdges:(UIViewController *)controller;
+ (UIImage *)statusIcon:(NSString *)status;
+ (UIImage *)queueActionIcon:(BOOL)stop;
+ (UIImage *)settingsIcon;
+ (UIImage *)plusIcon;
+ (UIImage *)queueToolbarIcon;
+ (void)showMessage:(NSString *)message;
+ (void)presentPlayer:(UIViewController *)owner path:(NSString *)path;
+ (UIBarButtonItem *)item:(NSString *)title target:(id)target action:(SEL)action;
@end
