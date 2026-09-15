#import "RDLPUIKit.h"
#import "RDLPStatusBarView.h"
#import <AIFontAwesome.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
/* Keep raster pixels and UIImage.scale tied to the same display scale.
   AIFontAwesome also accepts zero for this, but the cache needs the resolved
   value so images created at another screen scale cannot be reused. */
static CGFloat RDLPMainScreenScale(void) {
  CGFloat scale=[[UIScreen mainScreen] scale];
  return isfinite(scale) && scale>=1.0?scale:1.0;
}
@implementation RDLPUIKit
+ (void)configureContentEdges:(UIViewController *)controller;
{
  /* iOS 7 introduced extended edges. KVC preserves the iOS 5 deployment path. */
  if([controller respondsToSelector:@selector(setEdgesForExtendedLayout:)])
    [controller setValue:[NSNumber numberWithUnsignedInteger:0] forKey:@"edgesForExtendedLayout"];
}
+ (UIImage *)statusIcon:(NSString *)status;
{
  static NSMutableDictionary *images=nil;
  if(!images) images=[[NSMutableDictionary alloc] init];
  CGFloat scale=RDLPMainScreenScale();
  NSArray *key=[NSArray arrayWithObjects:status,[NSNumber numberWithDouble:scale],nil];
  UIImage *cached=[images objectForKey:key]; if(cached) return cached;
  AIFontAwesomeIcon icon=AIFATriangleExclamation;
  if([status isEqualToString:@"Downloaded"]) icon=AIFACircleCheck;
  else if([status isEqualToString:@"Downloading"] || [status isEqualToString:@"Queued"]) icon=AIFAHourglass;
  else if([status isEqualToString:@"Not downloaded"]) icon=AIFADownload;
  UIImage *image=[AIFontAwesome imageForIcon:icon style:AIFontAwesomeStyleSolid iconSize:14 canvasSize:18 color:[UIColor darkGrayColor] scale:scale];
  if(image) [images setObject:image forKey:key]; return image;
}
+ (UIImage *)queueActionIcon:(BOOL)stop;
{ return [AIFontAwesome imageForIcon:stop?AIFAPause:AIFARotateRight style:AIFontAwesomeStyleSolid iconSize:14 canvasSize:20 color:[UIColor blackColor] scale:RDLPMainScreenScale()]; }

+ (UIImage *)settingsIcon;
{ return [AIFontAwesome imageForIcon:AIFAGear style:AIFontAwesomeStyleSolid iconSize:22 canvasSize:26 color:[UIColor blackColor] scale:RDLPMainScreenScale()]; }

+ (UIImage *)plusIcon;
{
  /* Font Awesome "plus"; this bundled header names U+F067 AIFAStd12. */
  return [AIFontAwesome imageForIcon:(AIFontAwesomeIcon)0xF067 style:AIFontAwesomeStyleSolid iconSize:22 canvasSize:26 color:[UIColor blackColor] scale:RDLPMainScreenScale()]; }

+ (UIImage *)queueToolbarIcon;
{
  /* ENIL's toolbar glyph geometry; UIKit supplies tint on iOS 7+. */
  return [AIFontAwesome imageForIcon:AIFAListCheck style:AIFontAwesomeStyleSolid iconSize:18 canvasSize:28 color:[UIColor whiteColor] scale:RDLPMainScreenScale()];
}

+ (UIImage *)syncIcon;
{ return [AIFontAwesome imageForIcon:AIFAArrowsRotate style:AIFontAwesomeStyleSolid iconSize:22 canvasSize:26 color:[UIColor blackColor] scale:RDLPMainScreenScale()]; }

+ (NSArray *)statusToolbarItems:(RDLPStatusBarView *)status target:(id)target queueAction:(SEL)action;
{
  UIBarButtonItem *left=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
  UIBarButtonItem *right=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
  UIBarButtonItem *message=[[[UIBarButtonItem alloc] initWithCustomView:status] autorelease];
  if(!action) return [NSArray arrayWithObjects:left,message,right,nil];
  UIBarButtonItem *queue=[[[UIBarButtonItem alloc] initWithImage:[self queueToolbarIcon] style:UIBarButtonItemStyleBordered target:target action:action] autorelease];
  queue.accessibilityLabel=@"Download Queue";
  return [NSArray arrayWithObjects:left,message,right,queue,nil];
}

+ (void)showMessage:(NSString *)message; {
  UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"RetroDLP" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
  [alert show]; [alert release];
}
+ (void)presentPlayer:(UIViewController *)owner path:(NSString *)path; {
  if(!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { [self showMessage:@"The downloaded file is missing. Retry its download from Queue."]; return; }
  NSURL *url=[NSURL fileURLWithPath:path];
  Class modern=NSClassFromString(@"AVPlayerViewController");
  if(modern) {
    UIViewController *controller=[[modern alloc] init]; AVPlayer *player=[AVPlayer playerWithURL:url];
    [controller performSelector:@selector(setPlayer:) withObject:player];
    [owner presentModalViewController:controller animated:YES]; [player play]; [controller release];
  } else {
    MPMoviePlayerViewController *controller=[[MPMoviePlayerViewController alloc] initWithContentURL:url];
    [owner presentMoviePlayerViewControllerAnimated:controller]; [controller release];
  }
}
+ (UIBarButtonItem *)item:(NSString *)title target:(id)target action:(SEL)action;
{ return [[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:target action:action] autorelease]; }
@end
#pragma clang diagnostic pop
