#import "RDLPPlayerControls.h"
#import <math.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface RDLPPlayerTimeline : UISlider
@end
@implementation RDLPPlayerTimeline
- (CGRect)trackRectForBounds:(CGRect)bounds {
  CGRect track=[super trackRectForBounds:bounds];
  /* Center the artwork, leaving the native control's touch bounds in place. */
  track.origin.y=CGRectGetMidY(bounds)-track.size.height/2+1;
  return track;
}
@end

@interface RDLPPlayerControls () {
  RDLPPlayerTimeline *_timeline;
  UIBarButtonItem *_timelineItem;
  UILabel *_messageLabel;
  CGSize _toolbarSize;
}
@end

static UIBarButtonItem *RDLPImageButton(NSString *name, NSString *label) {
  UIImage *image=[UIImage imageNamed:[@"RDLPPlayer.bundle/" stringByAppendingString:name]];
  UIBarButtonItem *item=[[UIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:nil action:NULL];
  [item setAccessibilityLabel:label];
  return item;
}
static UIBarButtonItem *RDLPToolbarSpace(BOOL flexible) {
  UIBarButtonItem *space=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:
    flexible?UIBarButtonSystemItemFlexibleSpace:UIBarButtonSystemItemFixedSpace target:nil action:NULL] autorelease];
  if(!flexible) [space setWidth:-8]; // Reduce the legacy toolbar's outer margins.
  return space;
}
static NSString *RDLPTimeText(double seconds) {
  if(!isfinite(seconds) || seconds<0) return @"--:--";
  double minutes=floor(seconds/60);
  if(minutes>=60) return [NSString stringWithFormat:@"%.0f:%02.0f:%02.0f",floor(minutes/60),fmod(minutes,60),floor(fmod(seconds,60))];
  return [NSString stringWithFormat:@"%.0f:%02.0f",minutes,floor(fmod(seconds,60))];
}

@implementation RDLPPlayerControls
@synthesize doneButton=_doneButton, playButton=_playButton, previousButton=_previousButton;
@synthesize nextButton=_nextButton, audioButton=_audioButton, toolbarItems=_toolbarItems;
- (UIView *)timeline { return _timeline; }
- (UISlider *)slider { return _timeline; }

- (id)initWithFrame:(CGRect)frame {
  self=[super initWithFrame:frame]; if(!self) return nil;
  [self setUserInteractionEnabled:NO];
  _doneButton=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:nil action:NULL];
  _audioButton=RDLPImageButton(@"headphones.png",@"Use audio only");
  [_audioButton setStyle:UIBarButtonItemStyleBordered];
  _previousButton=RDLPImageButton(@"backward-fast.png",@"Previous item");
  _nextButton=RDLPImageButton(@"forward-fast.png",@"Next item");
  [_previousButton setWidth:32]; [_nextButton setWidth:32];
  /* Align the plain artwork with the neighboring bordered play button. */
  [_previousButton setImageInsets:UIEdgeInsetsMake(2,0,-2,0)]; [_nextButton setImageInsets:UIEdgeInsetsMake(2,0,-2,0)];
  [_previousButton setLandscapeImagePhoneInsets:UIEdgeInsetsMake(2,0,-2,0)]; [_nextButton setLandscapeImagePhoneInsets:UIEdgeInsetsMake(2,0,-2,0)];
  _playButton=RDLPImageButton(@"play.png",@"Play");
  [_playButton setStyle:UIBarButtonItemStyleBordered];
  _timeline=[[RDLPPlayerTimeline alloc] initWithFrame:CGRectMake(0,0,164,40)];
  [_timeline setContinuous:YES];
  [_timeline setAccessibilityLabel:@"Playback position"];
  _timelineItem=[[UIBarButtonItem alloc] initWithCustomView:_timeline];
  /* Keep spare space beside the scrubber, with transport buttons at the edges. */
  _toolbarItems=[[NSArray alloc] initWithObjects:RDLPToolbarSpace(NO),_previousButton,
    RDLPToolbarSpace(YES),_timelineItem,RDLPToolbarSpace(YES),_nextButton,_playButton,RDLPToolbarSpace(NO),nil];
  _messageLabel=[[UILabel alloc] initWithFrame:CGRectZero];
  [_messageLabel setBackgroundColor:[UIColor clearColor]];
  [_messageLabel setTextColor:[UIColor whiteColor]];
  [_messageLabel setTextAlignment:(__typeof__([_messageLabel textAlignment]))UITextAlignmentCenter];
  [_messageLabel setNumberOfLines:2];
  [_messageLabel setFont:[UIFont systemFontOfSize:18]];
  [self addSubview:_messageLabel];
  [self setElapsedTime:0 duration:NAN];
  return self;
}
- (void)dealloc {
  [_toolbarItems release]; [_timelineItem release]; [_timeline release]; [_messageLabel release];
  [_doneButton release]; [_playButton release]; [_previousButton release]; [_nextButton release]; [_audioButton release];
  [super dealloc];
}
- (BOOL)sizeForToolbar:(CGSize)size {
  /* UIKit may adjust the custom view's frame; only rebuild for a bar resize. */
  if(CGSizeEqualToSize(_toolbarSize,size)) return NO;
  _toolbarSize=size;
  /* Give the scrubber the width recovered from the two smaller outer margins. */
  CGSize timelineSize=CGSizeMake(MAX(100,size.width-156),MIN(40,size.height));
  [_timeline setFrame:(CGRect){[_timeline frame].origin,timelineSize}];
  [_timelineItem setWidth:timelineSize.width];
  return YES;
}
- (void)setElapsedTime:(double)elapsed duration:(double)duration {
  NSString *current=RDLPTimeText(elapsed), *total=RDLPTimeText(duration);
  [[self slider] setAccessibilityValue:[NSString stringWithFormat:@"%@ of %@",current,total]];
}
- (void)setMessage:(NSString *)message { [_messageLabel setText:message]; }
- (BOOL)isTracking { return [[self slider] isTracking]; }
- (void)layoutSubviews {
  [super layoutSubviews];
  [_messageLabel setFrame:CGRectMake(20,([self bounds].size.height-60)/2,MAX(0,[self bounds].size.width-40),60)];
}
@end
#pragma clang diagnostic pop
