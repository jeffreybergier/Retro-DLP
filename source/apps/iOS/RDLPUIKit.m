#import "RDLPUIKit.h"
#import <AIFontAwesome.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
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
  UIImage *cached=[images objectForKey:status]; if(cached) return cached;
  AIFontAwesomeIcon icon=AIFACircle;
  if([status isEqualToString:@"Downloaded"]) icon=AIFACircleCheck;
  else if([status isEqualToString:@"Downloading"]) icon=AIFADownload;
  else if([status isEqualToString:@"Queued"]) icon=AIFAHourglass;
  else if([status isEqualToString:@"Cancelled"]) icon=AIFACirclePause;
  else if(![status isEqualToString:@"Not downloaded"]) icon=AIFATriangleExclamation;
  UIImage *image=[AIFontAwesome imageForIcon:icon style:AIFontAwesomeStyleSolid iconSize:14 canvasSize:18 color:[UIColor darkGrayColor] scale:0];
  if(image) [images setObject:image forKey:status]; return image;
}
+ (UIImage *)queueActionIcon:(BOOL)stop;
{ return [AIFontAwesome imageForIcon:stop?AIFAPause:AIFARotateRight style:AIFontAwesomeStyleSolid iconSize:14 canvasSize:20 color:[UIColor blackColor] scale:0]; }

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
