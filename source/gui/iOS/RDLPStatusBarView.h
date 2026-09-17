#import <UIKit/UIKit.h>

/* Adapted from ENIL's SyncMiniBarView. Hosted in a real UIToolbar so UIKit
 * supplies the appropriate iOS 5/6 or iOS 7+ chrome. */
@interface RDLPStatusBarView : UIView {
  UILabel *label_;
  UIProgressView *progress_;
  CGFloat maximumWidth_;
  UIActivityIndicatorView *spinner_;
}
@property(nonatomic,assign) CGFloat maximumWidth;
@property(nonatomic,readonly) BOOL hasStatus;
@property(nonatomic,readonly) UIActivityIndicatorView *spinner;
- (void)setStatus:(NSString *)status progress:(NSDictionary *)progress busy:(BOOL)busy;
@end
