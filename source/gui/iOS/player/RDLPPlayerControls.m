#import "RDLPPlayerControls.h"
#import "../RDLPUIKit.h"
#import <math.h>
#import <QuartzCore/QuartzCore.h>

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
  UIView *_audioOnlyPlaceholder;
  UIView *_noMediaPlaceholder;
  CGSize _toolbarSize;
}
@end

static UIBarButtonItem *RDLPImageButton(RDLPPlayerIcon icon, NSString *label) {
  UIImage *image=[RDLPUIKit playerIcon:icon];
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
/* Use the toolbar glyph at native display resolution as an alpha mask. A
 * faint upper lip and a charcoal face fading downward keep the lighting
 * above the silhouette against the black playback surface. */
static UIView *RDLPAudioOnlyPlaceholder(void) {
  CGRect bounds=CGRectMake(0,0,128,128);
  UIView *view=[[[UIView alloc] initWithFrame:bounds] autorelease];
  [view setUserInteractionEnabled:NO];
  [view setIsAccessibilityElement:YES];
  [view setAccessibilityLabel:@"Audio only"];
  [view setAccessibilityTraits:UIAccessibilityTraitImage];
  UIImage *glyph=[RDLPUIKit playerIcon:RDLPPlayerIconHeadphones size:128 canvas:128];
  for(NSUInteger i=0;i<2;++i) {
    CAGradientLayer *face=[CAGradientLayer layer];
    [face setFrame:i==0?CGRectOffset(bounds,0,-1.5):bounds];
    CGFloat top=i==0?0.32f:0.15f, bottom=i==0?0.02f:0.065f;
    [face setColors:[NSArray arrayWithObjects:
      (id)[[UIColor colorWithWhite:top alpha:1] CGColor],
      (id)[[UIColor colorWithWhite:bottom alpha:1] CGColor],nil]];
    CALayer *mask=[CALayer layer];
    [mask setFrame:bounds];
    [mask setContents:(id)[glyph CGImage]];
    [mask setContentsScale:[glyph scale]];
    [face setMask:mask];
    [[view layer] addSublayer:face];
  }
  [view setHidden:YES];
  return view;
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
  _audioButton=RDLPImageButton(RDLPPlayerIconHeadphones,@"Use audio only");
  [RDLPUIKit setBorderedStyleForBarButtonItem:_audioButton];
  _previousButton=RDLPImageButton(RDLPPlayerIconPrevious,@"Previous item");
  _nextButton=RDLPImageButton(RDLPPlayerIconNext,@"Next item");
  [_previousButton setWidth:32]; [_nextButton setWidth:32];
  /* Align the plain artwork with the neighboring bordered play button. */
  [_previousButton setImageInsets:UIEdgeInsetsMake(2,0,-2,0)]; [_nextButton setImageInsets:UIEdgeInsetsMake(2,0,-2,0)];
  [_previousButton setLandscapeImagePhoneInsets:UIEdgeInsetsMake(2,0,-2,0)]; [_nextButton setLandscapeImagePhoneInsets:UIEdgeInsetsMake(2,0,-2,0)];
  _playButton=RDLPImageButton(RDLPPlayerIconPlay,@"Play");
  [RDLPUIKit setBorderedStyleForBarButtonItem:_playButton];
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
  [RDLPUIKit centerTextInLabel:_messageLabel];
  [_messageLabel setNumberOfLines:2];
  [_messageLabel setFont:[UIFont systemFontOfSize:18]];
  [self addSubview:_messageLabel];
  _audioOnlyPlaceholder=[RDLPAudioOnlyPlaceholder() retain];
  [self addSubview:_audioOnlyPlaceholder];
  _noMediaPlaceholder=[[UIView alloc] initWithFrame:CGRectMake(0,0,128,128)];
  [_noMediaPlaceholder setUserInteractionEnabled:NO];
  [_noMediaPlaceholder setIsAccessibilityElement:YES];
  [_noMediaPlaceholder setAccessibilityLabel:@"No media"];
  [_noMediaPlaceholder setAccessibilityTraits:UIAccessibilityTraitImage];
  UIImage *noMediaIcon=[RDLPUIKit playerIcon:RDLPPlayerIconVideoSlash size:128 canvas:128];
  /* Raw contents preserve the white glyph on both legacy and template-image UIKit. */
  [[_noMediaPlaceholder layer] setContents:(id)[noMediaIcon CGImage]];
  [[_noMediaPlaceholder layer] setContentsScale:[noMediaIcon scale]];
  [_noMediaPlaceholder setHidden:YES];
  [self addSubview:_noMediaPlaceholder];
  [self setElapsedTime:0 duration:NAN];
  return self;
}
- (void)dealloc {
  [_toolbarItems release]; [_timelineItem release]; [_timeline release]; [_messageLabel release]; [_audioOnlyPlaceholder release]; [_noMediaPlaceholder release];
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
- (void)setAudioOnlyPlaceholderVisible:(BOOL)visible { [_audioOnlyPlaceholder setHidden:!visible]; }
- (void)setNoMediaPlaceholderVisible:(BOOL)visible { [_noMediaPlaceholder setHidden:!visible]; }
- (BOOL)isTracking { return [[self slider] isTracking]; }
- (void)layoutSubviews {
  [super layoutSubviews];
  [_audioOnlyPlaceholder setCenter:CGPointMake(CGRectGetMidX([self bounds]),CGRectGetMidY([self bounds]))];
  [_noMediaPlaceholder setCenter:[_audioOnlyPlaceholder center]];
  [_messageLabel setFrame:CGRectMake(20,([self bounds].size.height-60)/2,MAX(0,[self bounds].size.width-40),60)];
}
@end
