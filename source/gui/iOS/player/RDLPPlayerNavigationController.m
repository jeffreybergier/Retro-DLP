#import "RDLPPlayerNavigationController.h"

/* The UIApplication status bar API is required on iOS 5/6. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
@interface RDLPPlayerNavigationController () {
  BOOL _savedStatusBarHidden, _ownsLegacyStatusBar;
}
@end

@implementation RDLPPlayerNavigationController
- (void)viewWillAppear:(BOOL)animated {
  /* Hide before UIKit lays out the player, and leave it hidden for the session. */
  if(![self respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)] && !_ownsLegacyStatusBar) {
    UIApplication *application=[UIApplication sharedApplication];
    _savedStatusBarHidden=application.statusBarHidden;
    _ownsLegacyStatusBar=YES;
    [application setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
  }
  [super viewWillAppear:animated];
}
- (void)viewWillDisappear:(BOOL)animated {
  if(_ownsLegacyStatusBar) {
    _ownsLegacyStatusBar=NO;
    UIApplication *application=[UIApplication sharedApplication];
    [application setStatusBarHidden:_savedStatusBarHidden withAnimation:UIStatusBarAnimationNone];
  }
  [super viewWillDisappear:animated];
}
/* On iOS 7+ UIKit restores the presenting controller's status bar on dismissal. */
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation { return UIStatusBarAnimationNone; }
- (UIViewController *)childViewControllerForStatusBarHidden { return nil; }
@end
#pragma clang diagnostic pop
