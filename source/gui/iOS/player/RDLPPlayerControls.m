/* Layout and artwork adapted from ALMoviePlayerController.
 * Copyright (c) 2013 Anthony Lobianco. See RDLPPlayer.bundle/LICENSE-ALMoviePlayerController.txt. */
#import "RDLPPlayerControls.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

/* UITextAlignment is required by the iOS 5 SDK/runtime. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface RDLPPlayerControls () {
  UIView *_topBar, *_bottomBar;
  UILabel *_elapsedLabel, *_durationLabel, *_messageLabel;
  MPVolumeView *_volumeView;
}
@end

static UIButton *RDLPButton(UIView *bar, NSString *title, NSString *imageName, NSString *label) {
  UIButton *button=[[UIButton alloc] initWithFrame:CGRectZero];
  button.showsTouchWhenHighlighted=YES;
  button.titleLabel.font=[UIFont systemFontOfSize:14];
  button.titleLabel.shadowOffset=CGSizeMake(1,1);
  [button setTitleShadowColor:[UIColor blackColor] forState:UIControlStateNormal];
  [button setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
  [button setTitle:title forState:UIControlStateNormal];
  if(imageName) [button setImage:[UIImage imageNamed:[@"RDLPPlayer.bundle/" stringByAppendingString:imageName]] forState:UIControlStateNormal];
  button.accessibilityLabel=label;
  [bar addSubview:button];
  return button;
}

static UILabel *RDLPTimeLabel(UIView *bar, UITextAlignment alignment) {
  UILabel *label=[[UILabel alloc] initWithFrame:CGRectZero];
  label.backgroundColor=[UIColor clearColor];
  label.font=[UIFont systemFontOfSize:12];
  label.textColor=[UIColor lightTextColor];
  label.textAlignment=(__typeof__(label.textAlignment))alignment;
  label.layer.shadowColor=[UIColor blackColor].CGColor;
  label.layer.shadowRadius=1;
  label.layer.shadowOffset=CGSizeMake(1,1);
  label.layer.shadowOpacity=0.8f;
  [bar addSubview:label];
  return label;
}

static NSString *RDLPTimeText(double seconds) {
  if(!isfinite(seconds) || seconds<0) return @"--:--";
  double minutes=floor(seconds/60);
  if(minutes>=60) return [NSString stringWithFormat:@"%.0f:%02.0f:%02.0f",floor(minutes/60),fmod(minutes,60),floor(fmod(seconds,60))];
  return [NSString stringWithFormat:@"%.0f:%02.0f",minutes,floor(fmod(seconds,60))];
}

static BOOL RDLPViewIsTracking(UIView *view) {
  if([view isKindOfClass:[UIControl class]] && [(UIControl *)view isTracking]) return YES;
  for(UIView *child in view.subviews) if(RDLPViewIsTracking(child)) return YES;
  return NO;
}

@implementation RDLPPlayerControls
@synthesize doneButton=_doneButton, playButton=_playButton, previousButton=_previousButton;
@synthesize nextButton=_nextButton, playlistButton=_playlistButton, audioButton=_audioButton;
@synthesize scaleButton=_scaleButton, slider=_slider;

- (id)initWithFrame:(CGRect)frame {
  self=[super initWithFrame:frame]; if(!self) return nil;
  self.backgroundColor=[UIColor clearColor];
  _topBar=[[UIView alloc] initWithFrame:CGRectZero];
  _bottomBar=[[UIView alloc] initWithFrame:CGRectZero];
  for(UIView *bar in [NSArray arrayWithObjects:_topBar,_bottomBar,nil]) {
    bar.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.5];
    [self addSubview:bar];
  }
  _doneButton=RDLPButton(_topBar,@"Done",nil,@"Done");
  _scaleButton=RDLPButton(_topBar,nil,@"movieFullscreen.png",@"Fill screen");
  [_scaleButton setImage:[UIImage imageNamed:@"RDLPPlayer.bundle/movieEndFullscreen.png"] forState:UIControlStateSelected];
  _elapsedLabel=RDLPTimeLabel(_topBar,UITextAlignmentRight);
  _durationLabel=RDLPTimeLabel(_topBar,UITextAlignmentLeft);
  _slider=[[UISlider alloc] initWithFrame:CGRectZero];
  _slider.maximumValue=1;
  _slider.accessibilityLabel=@"Playback position";
  [_topBar addSubview:_slider];
  _playButton=RDLPButton(_bottomBar,nil,@"moviePlay.png",@"Play");
  [_playButton setImage:[UIImage imageNamed:@"RDLPPlayer.bundle/moviePause.png"] forState:UIControlStateSelected];
  _previousButton=RDLPButton(_bottomBar,nil,@"movieBackward.png",@"Previous item");
  _nextButton=RDLPButton(_bottomBar,nil,@"movieForward.png",@"Next item");
  _playlistButton=RDLPButton(_bottomBar,@"Playlist",nil,@"Show playlist");
  _audioButton=RDLPButton(_bottomBar,@"Audio Only",nil,@"Use audio only");
  [_audioButton setTitle:@"Show Video" forState:UIControlStateSelected];
  _volumeView=[[MPVolumeView alloc] initWithFrame:CGRectZero];
  [_bottomBar addSubview:_volumeView];
  _messageLabel=[[UILabel alloc] initWithFrame:CGRectZero];
  _messageLabel.backgroundColor=[UIColor clearColor];
  _messageLabel.textColor=[UIColor whiteColor];
  _messageLabel.textAlignment=(__typeof__(_messageLabel.textAlignment))UITextAlignmentCenter;
  _messageLabel.numberOfLines=2;
  _messageLabel.font=[UIFont systemFontOfSize:18];
  [self addSubview:_messageLabel];
  [self setElapsedTime:0 duration:NAN];
  return self;
}

- (void)dealloc {
  [_topBar release]; [_bottomBar release];
  [_doneButton release]; [_scaleButton release]; [_playButton release];
  [_previousButton release]; [_nextButton release]; [_playlistButton release]; [_audioButton release];
  [_elapsedLabel release]; [_durationLabel release]; [_slider release];
  [_volumeView release]; [_messageLabel release];
  [super dealloc];
}

- (void)setElapsedTime:(double)elapsed duration:(double)duration {
  NSString *current=RDLPTimeText(elapsed), *total=RDLPTimeText(duration);
  if(![_elapsedLabel.text isEqualToString:current]) _elapsedLabel.text=current;
  if(![_durationLabel.text isEqualToString:total]) _durationLabel.text=total;
  _slider.accessibilityValue=[NSString stringWithFormat:@"%@ of %@",current,total];
}

- (void)setMessage:(NSString *)message {
  _messageLabel.text=message;
}

- (void)setChromeVisible:(BOOL)visible animated:(BOOL)animated {
  /* Disabling hit testing immediately also prevents taps on fading controls. */
  _topBar.userInteractionEnabled=_bottomBar.userInteractionEnabled=visible;
  _topBar.accessibilityElementsHidden=_bottomBar.accessibilityElementsHidden=!visible;
  if(!animated) {
    [_topBar.layer removeAllAnimations]; [_bottomBar.layer removeAllAnimations];
    _topBar.alpha=_bottomBar.alpha=visible?1:0;
    return;
  }
  [UIView animateWithDuration:0.25 delay:0
                     options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
                  animations:^{ _topBar.alpha=_bottomBar.alpha=visible?1:0; } completion:nil];
}

- (BOOL)isTracking { return RDLPViewIsTracking(self); }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView *hit=[super hitTest:point withEvent:event];
  return hit==self?nil:hit;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat width=self.bounds.size.width, height=self.bounds.size.height;
  CGFloat barHeight=([[[UIDevice currentDevice] systemVersion] floatValue]>=7)?70:50;
  CGFloat padding=width<=320?8:20;
  _topBar.frame=CGRectMake(0,0,width,barHeight);
  _bottomBar.frame=CGRectMake(0,MAX(barHeight,height-barHeight),width,barHeight);
  CGFloat y=(barHeight-44)/2;
  _doneButton.frame=CGRectMake(padding,y,44,44);
  _scaleButton.frame=CGRectMake(width-padding-44,y,44,44);
  CGFloat left=_doneButton.hidden?padding:padding+48;
  CGFloat right=_scaleButton.hidden?width-padding:width-padding-48;
  _elapsedLabel.frame=CGRectMake(left,0,50,barHeight);
  _durationLabel.frame=CGRectMake(right-50,0,50,barHeight);
  _slider.frame=CGRectMake(left+56,(barHeight-34)/2,MAX(0,right-left-112),34);
  _playButton.frame=CGRectMake(width/2-22,y,44,44);
  _previousButton.frame=CGRectMake(width/2-72,y,44,44);
  _nextButton.frame=CGRectMake(width/2+28,y,44,44);
  _playlistButton.frame=CGRectMake(padding,y,60,44);
  _audioButton.frame=CGRectMake(width-padding-80,y,80,44);
  CGFloat volumeX=_playlistButton.hidden?padding:padding+68;
  CGFloat volumeWidth=MIN(210,width/2-80-volumeX);
  _volumeView.hidden=volumeWidth<100;
  _volumeView.frame=CGRectMake(volumeX,(barHeight-22)/2,MAX(0,volumeWidth),22);
  CGFloat messageHeight=MIN(60,MAX(0,height-2*barHeight));
  _messageLabel.frame=CGRectMake(20,(height-messageHeight)/2,MAX(0,width-40),messageHeight);
}
@end
#pragma clang diagnostic pop
