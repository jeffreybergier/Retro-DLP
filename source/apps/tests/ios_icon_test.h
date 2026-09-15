#import "../iOS/RDLPUIKit.h"
#import <AIFontAwesome.h>
#import <math.h>

static void testIOSIconImage(UIImage *image,CGFloat canvas,CGFloat scale) {
  if(!image || image.scale!=scale || image.size.width!=canvas || image.size.height!=canvas ||
     CGImageGetWidth(image.CGImage)!=(size_t)ceil(canvas*scale) ||
     CGImageGetHeight(image.CGImage)!=(size_t)ceil(canvas*scale))
    [NSException raise:@"RDLPIOSIconTest" format:@"Icon must preserve point size and screen-resolution pixels (%gpt @%gx)",canvas,scale];
}
static void testIOSIconScale(void) {
  CGFloat scale=[[UIScreen mainScreen] scale];
  testIOSIconImage([RDLPUIKit plusIcon],26,scale);
  testIOSIconImage([RDLPUIKit settingsIcon],26,scale);
  testIOSIconImage([RDLPUIKit syncIcon],26,scale);
  testIOSIconImage([RDLPUIKit queueToolbarIcon],28,scale);
  testIOSIconImage([RDLPUIKit queueActionIcon:NO],20,scale);
  testIOSIconImage([RDLPUIKit queueActionIcon:YES],20,scale);
  for(NSString *status in [NSArray arrayWithObjects:@"Downloaded",@"Downloading",@"Queued",@"Not downloaded",@"Failed",nil]) {
    UIImage *image=[RDLPUIKit statusIcon:status];
    testIOSIconImage(image,18,scale);
    if(image!=[RDLPUIKit statusIcon:status])
      [NSException raise:@"RDLPIOSIconTest" format:@"Status icons must reuse the same-scale cache"];
  }
  /* Pin the dependency contract, including the previous scale:0 call path. */
  unsigned int factor;
  for(factor=0;factor<=3;++factor)
    testIOSIconImage([AIFontAwesome imageForIcon:(AIFontAwesomeIcon)0xf067
      style:AIFontAwesomeStyleSolid iconSize:22 canvasSize:26 color:[UIColor blackColor]
      scale:factor],26,factor?factor:scale);
}
