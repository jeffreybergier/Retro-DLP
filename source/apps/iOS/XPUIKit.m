#import "XPUIKit.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
void RDShowMessage(NSString *message) {
  UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"RetroDLP" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
  [alert show]; [alert release];
}
void RDPresentPlayer(UIViewController *owner,NSString *path) {
  if(!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { RDShowMessage(@"The downloaded file is missing. Retry its download from Queue."); return; }
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
#pragma clang diagnostic pop
