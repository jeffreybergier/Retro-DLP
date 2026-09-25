#import <UIKit/UIKit.h>

/* Internal native bar items, scrubber, and playback message. */
@interface RDLPPlayerControls : UIView
@property(nonatomic,readonly) UIBarButtonItem *doneButton;
@property(nonatomic,readonly) UIBarButtonItem *playButton;
@property(nonatomic,readonly) UIBarButtonItem *previousButton;
@property(nonatomic,readonly) UIBarButtonItem *nextButton;
@property(nonatomic,readonly) UIBarButtonItem *audioButton;
@property(nonatomic,readonly) UIView *timeline;
@property(nonatomic,readonly) NSArray *toolbarItems;
@property(nonatomic,readonly) UISlider *slider;
- (BOOL)sizeForToolbar:(CGSize)size;
- (void)setElapsedTime:(double)elapsed duration:(double)duration;
- (void)setMessage:(NSString *)message;
- (BOOL)isTracking;
@end
