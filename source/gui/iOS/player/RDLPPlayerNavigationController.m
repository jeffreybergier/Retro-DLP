#import "RDLPPlayerNavigationController.h"
#import "../RDLPUIKit.h"

/* The UIApplication status bar API is required on iOS 5/6. */
@interface RDLPPlayerNavigationController () {
  BOOL _savedStatusBarHidden, _ownsLegacyStatusBar;
}
@end

@implementation RDLPPlayerNavigationController
- (void)viewWillAppear:(BOOL)animated {
  /* Hide before UIKit lays out the player, and leave it hidden for the session. */
  if(![self respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)] && !_ownsLegacyStatusBar) {
    _savedStatusBarHidden=[RDLPUIKit legacyStatusBarHidden];
    _ownsLegacyStatusBar=YES;
    [RDLPUIKit setLegacyStatusBarHidden:YES];
  }
  [super viewWillAppear:animated];
}
- (void)viewWillDisappear:(BOOL)animated {
  if(_ownsLegacyStatusBar) {
    _ownsLegacyStatusBar=NO;
    [RDLPUIKit setLegacyStatusBarHidden:_savedStatusBarHidden];
  }
  [super viewWillDisappear:animated];
}
/* On iOS 7+ UIKit restores the presenting controller's status bar on dismissal. */
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation { return UIStatusBarAnimationNone; }
- (UIViewController *)childViewControllerForStatusBarHidden { return nil; }
@end
