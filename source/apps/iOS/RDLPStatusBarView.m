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
  BOOL modern=[self respondsToSelector:@selector(tintColor)];
  label_.textColor=modern?[UIColor blackColor]:[UIColor whiteColor];
  if(!modern) {
    label_.shadowColor=[UIColor colorWithWhite:0 alpha:0.5f];
    label_.shadowOffset=CGSizeMake(0,-1);
  }
  [self addSubview:label_];
  progress_=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
  progress_.hidden=YES; [self addSubview:progress_];
  return self;
}
- (void)dealloc;
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [lastStatus_ release]; [label_ release]; [progress_ release]; [super dealloc];
}
- (void)resizeToContent;
{
  [label_ sizeToFit];
  CGFloat width=label_.bounds.size.width;
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
- (void)clearIdleStatus;
{
  hideStatusAt_=0;
  label_.text=@"";
  [self resizeToContent];
}
- (void)updateStatus:(NSString *)status active:(BOOL)active;
{
  NSString *message=status?status:@"";
  BOOL ready=![message length] || [message isEqualToString:@"Ready"];
  BOOL changed=![lastStatus_ isEqualToString:message];
  [lastStatus_ release]; lastStatus_=[message copy];
  if(active) {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearIdleStatus) object:nil];
    hideStatusAt_=0;
    if(!ready) label_.text=message;
  } else {
    /* Refreshes repeat the same library status; they must not restart the
     * dwell time or resurrect a message that has already expired. */
    if(!ready && (changed || wasActive_)) label_.text=message;
    if([label_.text length] && (wasActive_ || (!ready && changed))) {
      [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearIdleStatus) object:nil];
      hideStatusAt_=[NSDate timeIntervalSinceReferenceDate]+10;
      [self performSelector:@selector(clearIdleStatus) withObject:nil afterDelay:10 inModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    }
    if(hideStatusAt_>0 && [NSDate timeIntervalSinceReferenceDate]>=hideStatusAt_) {
      [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearIdleStatus) object:nil];
      [self clearIdleStatus];
    }
  }
  wasActive_=active;
}
- (void)setStatus:(NSString *)status progress:(NSDictionary *)progress busy:(BOOL)busy;
{
  NSUInteger total=[[progress objectForKey:@"total"] unsignedIntegerValue];
  NSUInteger processed=[[progress objectForKey:@"processed"] unsignedIntegerValue];
  BOOL running=[[progress objectForKey:@"active"] boolValue];
  BOOL active=running || busy;
  [self updateStatus:status active:active];
  label_.font=[UIFont boldSystemFontOfSize:active?13:15];
  progress_.hidden=!active;
  progress_.progress=running && total?MIN(1.0f,(float)processed/(float)total):0.5f;
  progress_.accessibilityLabel=running && total?[NSString stringWithFormat:@"%@ processed of %@; %@ failed; %@ stopped",[progress objectForKey:@"processed"],[progress objectForKey:@"total"],[progress objectForKey:@"failed"],[progress objectForKey:@"cancelled"]]:@"In progress";
  [self resizeToContent];
}
- (void)layoutSubviews;
{
  [super layoutSubviews];
  CGFloat width=self.bounds.size.width, height=self.bounds.size.height;
  CGFloat labelHeight=label_.font.lineHeight;
  CGFloat descender=label_.font.descender;
  if(progress_.hidden) {
    label_.frame=CGRectMake(0,(height-labelHeight)*0.5f+descender*0.3f,width,labelHeight);
  } else {
    CGFloat progressHeight=progress_.bounds.size.height;
    CGFloat top=(height-(labelHeight+2+progressHeight))*0.5f;
    label_.frame=CGRectMake(0,top+descender*0.8f,width,labelHeight);
    CGFloat trackWidth=MIN(100,width);
    progress_.frame=CGRectMake((width-trackWidth)*0.5f,top+labelHeight+2,trackWidth,progressHeight);
  }
}
@end
