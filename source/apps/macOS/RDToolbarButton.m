#import "RDToolbarButton.h"
#import "XPAppKit.h"
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
/* Measure once when the image changes, in logical, bottom-left coordinates. */
static NSRect caretInkBounds(NSImage *image) {
  NSSize size=[image size];
  NSEnumerator *e=[[image representations] objectEnumerator]; NSImageRep *rep;
  while((rep=[e nextObject])) if([rep isKindOfClass:[NSBitmapImageRep class]]) {
    NSBitmapImageRep *bitmap=(NSBitmapImageRep *)rep;
    NSInteger width=[bitmap pixelsWide],height=[bitmap pixelsHigh];
    NSInteger minX=width,minY=height,maxX=-1,maxY=-1,x,y;
    for(y=0;y<height;++y) for(x=0;x<width;++x) {
      if([[bitmap colorAtX:x y:y] alphaComponent]<=0.01) continue;
      minX=MIN(minX,x); minY=MIN(minY,y); maxX=MAX(maxX,x); maxY=MAX(maxY,y);
    }
    if(maxX>=minX && maxY>=minY) return NSMakeRect(minX*size.width/width,
      (height-maxY-1)*size.height/height,(maxX-minX+1)*size.width/width,(maxY-minY+1)*size.height/height);
  }
  return NSMakeRect(0,0,size.width,size.height);
}
typedef struct {
  NSRect icon,caret;
  NSBezierPath *background;
} RDToolbarLayout;
static RDToolbarLayout toolbarLayout(NSView *view,NSImage *caret,NSRect ink) {
  const CGFloat radius=12.0,margin=1.0;
  NSRect bounds=[view bounds]; NSSize size=[caret size];
  RDToolbarLayout layout;
  layout.icon=NSMakeRect(NSMidX(bounds)-16,NSMidY(bounds)-16,32,32);
  NSPoint corner=NSMakePoint(NSMaxX(layout.icon),[view isFlipped]?NSMaxY(layout.icon):NSMinY(layout.icon));
  layout.background=[NSBezierPath bezierPath];
  [layout.background moveToPoint:NSZeroPoint]; [layout.background lineToPoint:NSMakePoint(0,radius)];
  [layout.background appendBezierPathWithArcWithCenter:NSZeroPoint radius:radius startAngle:90 endAngle:180];
  [layout.background closePath];
  NSAffineTransform *transform=[NSAffineTransform transform];
  [transform translateXBy:corner.x yBy:corner.y];
  [transform scaleXBy:1 yBy:[view isFlipped]?-1:1];
  [layout.background transformUsingAffineTransform:transform];
  /* Align the visible triangle, not the transparent image canvas. */
  CGFloat y=[view isFlipped]?corner.y-margin-size.height+NSMinY(ink):corner.y+margin-NSMinY(ink);
  layout.caret=NSMakeRect(corner.x-margin-NSMaxX(ink),y,size.width,size.height);
  return layout;
}
static void trackOptions(RDToolbarButton *view,NSMenu *menu,NSEvent *event) {
  NSString *tip=[[view toolTip] copy];
  [view setToolTip:nil];
  [NSMenu popUpContextMenu:menu withEvent:event forView:view];
  [view setToolTip:tip]; [tip release];
}
@implementation RDApplication
- (void)dealloc; { [pendingMenuButton_ release]; [super dealloc]; }
- (void)sendEvent:(NSEvent *)event;
{
  /* Control-click uses a left-button release. Open after that release so
     AppKit does not treat it as an outside click and dismiss the menu. */
  if([event type]==NSLeftMouseUp && pendingMenuButton_) {
    RDToolbarButton *button=[[pendingMenuButton_ retain] autorelease];
    [pendingMenuButton_ release]; pendingMenuButton_=nil;
    if([button window]) [button showOptions:nil];
    return;
  }
  if([event type]==NSLeftMouseDown) { [pendingMenuButton_ release]; pendingMenuButton_=nil; }
  BOOL secondary=[event type]==NSRightMouseDown || ([event type]==NSLeftMouseDown && ([event modifierFlags]&NSControlKeyMask));
  NSWindow *window=[event window];
  if(secondary && ![window attachedSheet]) {
    NSEnumerator *e=[[[window toolbar] items] objectEnumerator]; NSToolbarItem *item;
    while((item=[e nextObject])) {
      NSView *view=[item view];
      if(![view isKindOfClass:[RDToolbarButton class]] || ![view menu]) continue;
      NSPoint point=[view convertPoint:[event locationInWindow] fromView:nil];
      NSRect hit=[view bounds];
      /* Include the native label immediately below this icon. */
      if(![view isFlipped]) hit.origin.y-=20;
      hit.size.height+=20;
      if(NSPointInRect(point,hit)) {
        if([event type]==NSLeftMouseDown) pendingMenuButton_=[(RDToolbarButton *)view retain];
        else [view rightMouseDown:event];
        return;
      }
    }
  }
  [super sendEvent:event];
}
@end
@implementation RDToolbarButton
- (id)initWithFrame:(NSRect)frame;
{
  self=[super initWithFrame:frame];
  if(self) { defaultEnabled_=YES; [self setBordered:NO]; [self setImagePosition:NSImageOnly]; }
  return self;
}
- (void)dealloc; { [caret_ release]; [super dealloc]; }
- (BOOL)isDefaultEnabled; { return defaultEnabled_; }
- (void)setDefaultEnabled:(BOOL)enabled; { defaultEnabled_=enabled; [self setNeedsDisplay:YES]; }
- (void)setCaretImage:(NSImage *)image;
{
  [image retain]; [caret_ release]; caret_=image;
  caretInkBounds_=caretInkBounds(image); [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirty;
{
  (void)dirty;
  RDToolbarLayout layout=toolbarLayout(self,caret_,caretInkBounds_);
  /* Keep native pressed/disabled feedback for the explicitly colored images. */
  BOOL enabled=[[self cell] isEnabled];
  [[self cell] setEnabled:defaultEnabled_];
  [(NSButtonCell *)[self cell] drawImage:[self image] withFrame:layout.icon inView:self];
  [[self cell] setEnabled:enabled];
  if([self menu]) {
    [[NSColor windowBackgroundColor] set]; [layout.background fill];
    [(NSButtonCell *)[self cell] drawImage:caret_ withFrame:layout.caret inView:self];
  }
}
- (void)mouseDown:(NSEvent *)event;
{
  NSPoint point=[self convertPoint:[event locationInWindow] fromView:nil];
  RDToolbarLayout layout=toolbarLayout(self,caret_,caretInkBounds_);
  if(([event modifierFlags]&NSControlKeyMask) || ([self menu] && [layout.background containsPoint:point])) {
    [self showOptions:nil]; return;
  }
  if(defaultEnabled_) [super mouseDown:event];
}
- (void)rightMouseDown:(NSEvent *)event;
{
  /* Track real mouse events directly so the matching mouse-up does not
     dismiss a menu created later from a synthetic event. */
  if([self menu] && ![[self window] attachedSheet]) trackOptions(self,[self menu],event);
}
- (void)performClick:(id)sender; { if(defaultEnabled_) [super performClick:sender]; }
- (void)showOptions:(id)sender;
{
  (void)sender;
  /* AX actions must return before entering menu tracking on Tiger. */
  if([self menu]) [self performSelector:@selector(presentOptions:) withObject:[self menu] afterDelay:0.05];
}
- (void)presentOptions:(NSMenu *)menu;
{
  NSPoint point=[self convertPoint:[self isFlipped]?NSMakePoint(0,[self bounds].size.height):NSZeroPoint toView:nil];
  NSEvent *event=[NSEvent mouseEventWithType:NSRightMouseDown location:point modifierFlags:0
    timestamp:0 windowNumber:[[self window] windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1];
  if(![[self window] attachedSheet]) trackOptions(self,menu,event);
}
- (NSArray *)accessibilityActionNames;
{
  NSMutableArray *names=[NSMutableArray arrayWithArray:[super accessibilityActionNames]];
  if([self menu] && ![names containsObject:NSAccessibilityShowMenuAction]) [names addObject:NSAccessibilityShowMenuAction];
  return names;
}
- (void)accessibilityPerformAction:(NSString *)action;
{
  if([action isEqualToString:NSAccessibilityShowMenuAction]) [self showOptions:nil];
  else if(![action isEqualToString:NSAccessibilityPressAction] || defaultEnabled_) [super accessibilityPerformAction:action];
}
@end
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
