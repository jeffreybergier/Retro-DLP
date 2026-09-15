#import <UIKit/UIKit.h>
#import "RDLPLibrary.h"
@interface RDLPAppDelegate : UIResponder <UIApplicationDelegate, UIAlertViewDelegate> {
  UIWindow *window_; RDLPLibrary *library_;
  UIAlertView *errorAlert_;
}
@property(nonatomic,retain) UIWindow *window;
@end
