#import "RDLPStatusBarView.h"

/* ENIL's content sizing and optical alignment: 15pt steady text, 13pt active
 * text, a 100pt progress track, and a 2pt gap in a 30pt custom view. */
@implementation RDLPStatusBarView
@synthesize maximumWidth=maximumWidth_;
- (id)initWithFrame:(CGRect)frame;
{
  self=[super initWithFrame:frame]; if(!self) return nil;
  self.backgroundColor=[UIColor clearColor]; maximumWidth_=240;
  label_=[[UILabel alloc] initWithFrame:CGRectZero];
  label_.backgroundColor=[UIColor clearColor]; label_.textAlignment=1;
  label_.font=[UIFont boldSystemFontOfSize:15];
  /* Middle truncation is value 5 in both the iOS 5 and iOS 6+ enums. */
  label_.lineBreakMode=5;
  BOOL modern=[self respondsToSelector:@selector(tintColor)];
  label_.textColor=modern?[UIColor blackColor]:[UIColor whiteColor];
  if(!modern) {
    label_.shadowColor=[UIColor colorWithWhite:0 alpha:0.5f];
    label_.shadowOffset=CGSizeMake(0,-1);
  }
  [self addSubview:label_];
  progress_=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
  progress_.hidden=YES; [self addSubview:progress_];
  spinner_=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:modern?UIActivityIndicatorViewStyleGray:UIActivityIndicatorViewStyleWhite];
  spinner_.hidesWhenStopped=YES; [self addSubview:spinner_];
  return self;
}
- (void)dealloc;
{
  [spinner_ release]; [label_ release]; [progress_ release]; [super dealloc];
}
- (void)resizeToContent;
{
  [label_ sizeToFit];
  CGFloat width=label_.bounds.size.width;
  if([spinner_ isAnimating]) width+=26;
  if(!progress_.hidden) width=MAX(width,100);
  width=MIN(width,maximumWidth_);
  BOOL changed=self.frame.size.width!=width;
  CGRect frame=self.frame; frame.size=CGSizeMake(width,30); self.frame=frame;
  [self setNeedsLayout];
  if(changed) {
    UIView *view=self.superview;
    while(view && ![view isKindOfClass:[UIToolbar class]]) view=view.superview;
    /* Like ENIL, remeasure the custom item when its content width changes. */
    if(view) [(UIToolbar *)view setItems:[(UIToolbar *)view items] animated:NO];
  }
}
- (void)setMaximumWidth:(CGFloat)width;
{
  width=MAX(0,width); if(maximumWidth_==width) return;
  maximumWidth_=width; [self resizeToContent];
}
- (BOOL)hasStatus; { return [label_.text length]>0; }
- (void)setStatus:(NSString *)status progress:(NSDictionary *)progress busy:(BOOL)busy;
{
  (void)busy;
  label_.text=status?status:@"";
  BOOL active=[[progress objectForKey:@"active"] boolValue] && [label_.text length]>0;
  double completed=[[progress objectForKey:@"completed"] doubleValue];
  double expected=[[progress objectForKey:@"expected"] doubleValue];
  label_.font=[UIFont boldSystemFontOfSize:active?13:15];
  progress_.hidden=!active || expected<=0;
  progress_.progress=expected>0?(float)MIN(1.0,completed/expected):0;
  progress_.accessibilityLabel=label_.text;
  if(active && expected<=0) [spinner_ startAnimating]; else [spinner_ stopAnimating];
  spinner_.accessibilityLabel=label_.text;
  [self resizeToContent];
}
- (void)layoutSubviews;
{
  [super layoutSubviews];
  CGFloat width=self.bounds.size.width, height=self.bounds.size.height;
  CGFloat labelHeight=label_.font.lineHeight;
  CGFloat descender=label_.font.descender;
  if(progress_.hidden) {
    CGFloat inset=[spinner_ isAnimating]?26:0;
    spinner_.frame=CGRectMake(0,(height-20)*0.5f,20,20);
    label_.frame=CGRectMake(inset,(height-labelHeight)*0.5f+descender*0.3f,MAX(0,width-inset),labelHeight);
  } else {
    CGFloat progressHeight=progress_.bounds.size.height;
    CGFloat top=(height-(labelHeight+2+progressHeight))*0.5f;
    label_.frame=CGRectMake(0,top+descender*0.8f,width,labelHeight);
    CGFloat trackWidth=MIN(100,width);
    progress_.frame=CGRectMake((width-trackWidth)*0.5f,top+labelHeight+2,trackWidth,progressHeight);
  }
}
@end
