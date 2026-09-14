#import <UIKit/UIKit.h>
@interface RDLPUIKit : NSObject
+ (void)configureContentEdges:(UIViewController *)controller;
+ (UIImage *)statusIcon:(NSString *)status;
+ (UIImage *)queueActionIcon:(BOOL)stop;
+ (void)showMessage:(NSString *)message;
+ (void)presentPlayer:(UIViewController *)owner path:(NSString *)path;
+ (UIBarButtonItem *)item:(NSString *)title target:(id)target action:(SEL)action;
@end
