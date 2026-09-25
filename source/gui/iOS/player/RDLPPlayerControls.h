#import <UIKit/UIKit.h>

/* Internal view. Layout and artwork adapted from ALMoviePlayerController.
 * Copyright (c) 2013 Anthony Lobianco. See RDLPPlayer.bundle/LICENSE-ALMoviePlayerController.txt. */
@interface RDLPPlayerControls : UIView
@property(nonatomic,readonly) UIButton *doneButton;
@property(nonatomic,readonly) UIButton *playButton;
@property(nonatomic,readonly) UIButton *previousButton;
@property(nonatomic,readonly) UIButton *nextButton;
@property(nonatomic,readonly) UIButton *playlistButton;
@property(nonatomic,readonly) UIButton *audioButton;
@property(nonatomic,readonly) UIButton *scaleButton;
@property(nonatomic,readonly) UISlider *slider;
- (void)setElapsedTime:(double)elapsed duration:(double)duration;
- (void)setMessage:(NSString *)message loading:(BOOL)loading;
- (void)setChromeVisible:(BOOL)visible animated:(BOOL)animated;
- (BOOL)isTracking;
@end
