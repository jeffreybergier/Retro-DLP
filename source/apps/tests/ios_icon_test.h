#import "../iOS/RDLPUIKit.h"
#import <AIFontAwesome.h>
#import <math.h>

static void testIOSIconDimensions(UIImage *image,CGFloat canvas,CGFloat scale) {
  if(!image || image.scale!=scale || image.size.width!=canvas || image.size.height!=canvas ||
     CGImageGetWidth(image.CGImage)!=(size_t)ceil(canvas*scale) ||
     CGImageGetHeight(image.CGImage)!=(size_t)ceil(canvas*scale))
    [NSException raise:@"RDLPIOSIconTest" format:@"Icon must preserve point size and screen-resolution pixels (%gpt @%gx)",canvas,scale];
}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
static void testIOSIconImage(UIImage *image,CGFloat canvas,CGFloat scale,BOOL expectWhite) {
  testIOSIconDimensions(image,canvas,scale);
  if([image respondsToSelector:@selector(renderingMode)] && image.renderingMode!=UIImageRenderingModeAlwaysTemplate)
    [NSException raise:@"RDLPIOSIconTest" format:@"Every app icon must use template rendering on iOS 7+"];
  size_t width=CGImageGetWidth(image.CGImage), height=CGImageGetHeight(image.CGImage), i;
  unsigned char *pixels=calloc(width*height,4);
  CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();
  CGContextRef context=CGBitmapContextCreate(pixels,width,height,8,width*4,colors,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
  if(!pixels || !context) [NSException raise:@"RDLPIOSIconTest" format:@"Create icon pixel probe"];
  CGContextDrawImage(context,CGRectMake(0,0,width,height),image.CGImage);
  BOOL correctColor=YES, ink=NO, clear=NO;
  for(i=0;i<width*height;++i) {
    unsigned char *pixel=pixels+i*4;
    if(pixel[3]) {
      ink=YES;
      int expected=expectWhite?pixel[3]:0;
      if(abs((int)pixel[0]-expected)>1 || abs((int)pixel[1]-expected)>1 || abs((int)pixel[2]-expected)>1) correctColor=NO;
    } else clear=YES;
  }
  CGContextRelease(context); CGColorSpaceRelease(colors); free(pixels);
  if(!correctColor || !ink || !clear)
    [NSException raise:@"RDLPIOSIconTest" format:@"Icon must contain only %@ glyph pixels and transparency",expectWhite?@"white":@"black"];
}
#pragma clang diagnostic pop
static void testIOSIconScale(void) {
  CGFloat scale=[[UIScreen mainScreen] scale];
  testIOSIconImage([RDLPUIKit plusIcon],26,scale,YES);
  testIOSIconImage([RDLPUIKit settingsIcon],26,scale,YES);
  testIOSIconImage([RDLPUIKit syncIcon],26,scale,YES);
  testIOSIconImage([RDLPUIKit queueToolbarIcon],28,scale,YES);
  testIOSIconImage([RDLPUIKit queueActionIcon:NO],20,scale,YES);
  testIOSIconImage([RDLPUIKit queueActionIcon:YES],20,scale,YES);
  for(NSString *status in [NSArray arrayWithObjects:@"Downloaded",@"Downloading",@"Queued",@"Not downloaded",@"Failed",nil]) {
    UIImage *image=[RDLPUIKit statusIcon:status];
    testIOSIconImage(image,18,scale,NO);
    if(image!=[RDLPUIKit statusIcon:status])
      [NSException raise:@"RDLPIOSIconTest" format:@"Status icons must reuse the same-scale cache"];
  }
  /* Pin the dependency contract, including the previous scale:0 call path. */
  unsigned int factor;
  for(factor=0;factor<=3;++factor)
    testIOSIconDimensions([AIFontAwesome imageForIcon:(AIFontAwesomeIcon)0xf067
      style:AIFontAwesomeStyleSolid iconSize:22 canvasSize:26 color:[UIColor blackColor]
      scale:factor],26,factor?factor:scale);
}
