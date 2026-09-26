#import "RDLPStatusBarView.h"

/* ENIL's content sizing and optical alignment: 15pt steady text, 13pt active
 * text, a 100pt progress track, and a 2pt gap in a 30pt custom view. */
@implementation RDLPStatusBarView
@synthesize maximumWidth=maximumWidth_;
@synthesize spinner=spinner_;
- (id)initWithFrame:(CGRect)frame;
{
  self=[super initWithFrame:frame]; if(!self) return nil;
  [self setBackgroundColor:[UIColor clearColor]]; maximumWidth_=240;
  label_=[[UILabel alloc] initWithFrame:CGRectZero];
  [label_ setBackgroundColor:[UIColor clearColor]]; [label_ setTextAlignment:1];
  [label_ setFont:[UIFont boldSystemFontOfSize:15]];
  /* Middle truncation is value 5 in both the iOS 5 and iOS 6+ enums. */
  [label_ setLineBreakMode:5];
  BOOL modern=[self respondsToSelector:@selector(tintColor)];
  [label_ setTextColor:modern?[UIColor blackColor]:[UIColor whiteColor]];
  if(!modern) {
    [label_ setShadowColor:[UIColor colorWithWhite:0 alpha:0.5f]];
    [label_ setShadowOffset:CGSizeMake(0,-1)];
  }
  [self addSubview:label_];
  progress_=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
  [progress_ setHidden:YES]; [self addSubview:progress_];
  spinner_=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:modern?UIActivityIndicatorViewStyleGray:UIActivityIndicatorViewStyleWhite];
  [spinner_ setHidesWhenStopped:YES];
  return self;
}
- (void)dealloc;
{
  [spinner_ release]; [label_ release]; [progress_ release]; [super dealloc];
}
- (void)resizeToContent;
{
  [label_ sizeToFit];
  CGFloat width=[label_ bounds].size.width;
  if(![progress_ isHidden]) width=MAX(width,100);
  width=MIN(width,maximumWidth_);
  BOOL changed=[self frame].size.width!=width;
  CGRect frame=[self frame]; frame.size=CGSizeMake(width,30); [self setFrame:frame];
  [self setNeedsLayout];
  if(changed) {
    UIView *view=[self superview];
    while(view && ![view isKindOfClass:[UIToolbar class]]) view=[view superview];
    /* Like ENIL, remeasure the custom item when its content width changes. */
    if(view) [(UIToolbar *)view setItems:[(UIToolbar *)view items] animated:NO];
  }
}
- (void)setMaximumWidth:(CGFloat)width;
{
  width=MAX(0,width); if(maximumWidth_==width) return;
  maximumWidth_=width; [self resizeToContent];
}
- (BOOL)hasStatus; { return [[label_ text] length]>0; }
- (void)setStatus:(NSString *)status progress:(NSDictionary *)progress busy:(BOOL)busy;
{
  (void)busy;
  [label_ setText:status?status:@""];
  BOOL active=[[progress objectForKey:@"active"] boolValue] && [[label_ text] length]>0;
  double completed=[[progress objectForKey:@"completed"] doubleValue];
  double expected=[[progress objectForKey:@"expected"] doubleValue];
  [label_ setFont:[UIFont boldSystemFontOfSize:active?13:15]];
  [progress_ setHidden:!active || expected<=0];
  [progress_ setProgress:expected>0?(float)MIN(1.0,completed/expected):0];
  [progress_ setAccessibilityLabel:[label_ text]];
  if(active && expected<=0) [spinner_ startAnimating]; else [spinner_ stopAnimating];
  [spinner_ setAccessibilityLabel:[label_ text]];
  [self resizeToContent];
}
- (void)layoutSubviews;
{
  [super layoutSubviews];
  CGFloat width=[self bounds].size.width, height=[self bounds].size.height;
  CGFloat labelHeight=[[label_ font] lineHeight];
  CGFloat descender=[[label_ font] descender];
  if([progress_ isHidden]) {
    [label_ setFrame:CGRectMake(0,(height-labelHeight)*0.5f+descender*0.3f,width,labelHeight)];
  } else {
    CGFloat progressHeight=[progress_ bounds].size.height;
    CGFloat top=(height-(labelHeight+2+progressHeight))*0.5f;
    [label_ setFrame:CGRectMake(0,top+descender*0.8f,width,labelHeight)];
    CGFloat trackWidth=MIN(100,width);
    [progress_ setFrame:CGRectMake((width-trackWidth)*0.5f,top+labelHeight+2,trackWidth,progressHeight)];
  }
}
@end
