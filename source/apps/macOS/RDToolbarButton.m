#import "RDToolbarButton.h"
#import "XPAppKit.h"
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
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
- (void)setCaretImage:(NSImage *)image; { [caret_ release]; caret_=[image retain]; [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)dirty;
{
  (void)dirty;
  NSRect bounds=[self bounds];
  NSRect icon=NSMakeRect((bounds.size.width-32)/2,(bounds.size.height-32)/2,32,32);
  /* Let AppKit tint template images, including in modern dark appearances. */
  BOOL enabled=[[self cell] isEnabled];
  [[self cell] setEnabled:defaultEnabled_];
  [(NSButtonCell *)[self cell] drawImage:[self image] withFrame:icon inView:self];
  [[self cell] setEnabled:enabled];
  if([self menu]) {
    NSRect badge=NSMakeRect(NSMaxX(icon)-10,[self isFlipped]?NSMaxY(icon)-10:NSMinY(icon),10,10);
    [[NSColor windowBackgroundColor] set]; NSRectFill(badge);
    [(NSButtonCell *)[self cell] drawImage:caret_ withFrame:badge inView:self];
  }
}
- (void)mouseDown:(NSEvent *)event;
{
  NSPoint point=[self convertPoint:[event locationInWindow] fromView:nil];
  if(([event modifierFlags]&NSControlKeyMask) || ([self menu] && point.x>=[self bounds].size.width/2+6 && ([self isFlipped]?point.y>=[self bounds].size.height-12:point.y<=12))) {
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
