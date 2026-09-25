#import "RDLPUIKit.h"
#import "RDLPStatusBarView.h"
#import "RDLPLibrary.h"
#import "RDLPDownloadPolicy.h"
#import <AIFontAwesome.h>
#import "RDLPDownloadedPlayerViewController.h"
#import <math.h>
/* Keep raster pixels and UIImage.scale tied to the same display scale.
   AIFontAwesome also accepts zero for this, but the cache needs the resolved
   value so images created at another screen scale cannot be reused. */
static CGFloat RDLPMainScreenScale(void) {
  CGFloat scale=[[UIScreen mainScreen] scale];
  return isfinite(scale) && scale>=1.0?scale:1.0;
}
/* Preserve the glyph color for iOS 5/6, where template rendering is unavailable.
   The selector guard keeps explicit iOS 7 template mode safe on those systems. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
static UIImage *RDLPFontAwesomeImageWithOffset(AIFontAwesomeIcon icon,CGFloat size,CGFloat canvas,CGFloat scale,UIColor *color,CGFloat verticalOffset) {
  UIImage *image=[AIFontAwesome imageForIcon:icon style:AIFontAwesomeStyleSolid
    iconSize:size canvasSize:canvas color:color scale:scale];
  if(image && verticalOffset!=0) {
    UIGraphicsBeginImageContextWithOptions(image.size,NO,image.scale);
    [image drawAtPoint:CGPointMake(0,verticalOffset)];
    image=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
  }
  if([image respondsToSelector:@selector(imageWithRenderingMode:)])
    image=[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
  return image;
}
#pragma clang diagnostic pop
static UIImage *RDLPFontAwesomeImage(AIFontAwesomeIcon icon,CGFloat size,CGFloat canvas,CGFloat scale,UIColor *color) {
  return RDLPFontAwesomeImageWithOffset(icon,size,canvas,scale,color,0);
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
  UIImage *image=RDLPFontAwesomeImage(icon,14,18,scale,[UIColor blackColor]);
  if(image) [images setObject:image forKey:key]; return image;
}
+ (UIImage *)queueActionIcon:(BOOL)stop;
{ return RDLPFontAwesomeImage(stop?AIFAPause:AIFARotateRight,14,20,RDLPMainScreenScale(),[UIColor whiteColor]); }

+ (UIImage *)settingsIcon;
{ return RDLPFontAwesomeImageWithOffset(AIFAGear,18,26,RDLPMainScreenScale(),[UIColor whiteColor],-1); }

+ (UIImage *)plusIcon;
{
  /* Font Awesome "plus"; this bundled header names U+F067 AIFAStd12. */
  return RDLPFontAwesomeImageWithOffset((AIFontAwesomeIcon)0xF067,18,26,RDLPMainScreenScale(),[UIColor whiteColor],-1); }

+ (UIImage *)queueToolbarIcon;
{
  /* Lift the glyph within its canvas to align with the legacy bordered button.
   * Keep the same optical adjustment on every iOS version. */
  return RDLPFontAwesomeImageWithOffset(AIFAListCheck,18,28,RDLPMainScreenScale(),[UIColor whiteColor],-1);
}

+ (UIImage *)syncIcon;
{ return RDLPFontAwesomeImageWithOffset(AIFAArrowsRotate,18,26,RDLPMainScreenScale(),[UIColor whiteColor],-1); }

+ (NSArray *)statusToolbarItems:(RDLPStatusBarView *)status target:(id)target queueAction:(SEL)action;
{
  /* Reserve the spinner slot even when it is hidden so hidesWhenStopped never
   * changes the message layout. Let UIKit size the native Queue button. */
  UIView *spinnerSlot=[[[UIView alloc] initWithFrame:CGRectMake(0,0,36,30)] autorelease];
  status.spinner.center=CGPointMake(18,15);
  [spinnerSlot addSubview:status.spinner];
  UIBarButtonItem *activity=[[[UIBarButtonItem alloc] initWithCustomView:spinnerSlot] autorelease];
  UIBarButtonItem *left=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
  UIBarButtonItem *right=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
  UIBarButtonItem *message=[[[UIBarButtonItem alloc] initWithCustomView:status] autorelease];
  if(!action) {
    UIView *emptySlot=[[[UIView alloc] initWithFrame:CGRectMake(0,0,36,30)] autorelease];
    UIBarButtonItem *empty=[[[UIBarButtonItem alloc] initWithCustomView:emptySlot] autorelease];
    return [NSArray arrayWithObjects:activity,left,message,right,empty,nil];
  }
  UIBarButtonItem *queue=[[[UIBarButtonItem alloc] initWithImage:[self queueToolbarIcon] style:UIBarButtonItemStyleBordered target:target action:action] autorelease];
  queue.accessibilityLabel=@"Download Queue";
  return [NSArray arrayWithObjects:activity,left,message,right,queue,nil];
}

+ (void)showMessage:(NSString *)message; {
  UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"RetroDLP" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
  [alert show]; [alert release];
}
+ (void)presentPlayer:(UIViewController *)owner library:(RDLPLibrary *)library job:(NSDictionary *)job; {
  NSString *path=[library fileForJob:job];
  if(!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { [self showMessage:@"The downloaded file is missing. Retry its download from Queue."]; return; }
  RDLPDownloadedPlayerViewController *controller=[[RDLPDownloadedPlayerViewController alloc]
    initWithLibrary:library job:job URL:[NSURL fileURLWithPath:path]];
  [owner presentViewController:controller animated:YES completion:nil]; [controller release];
}
+ (void)presentPlayer:(UIViewController *)owner library:(RDLPLibrary *)library playlist:(NSString *)playlist entry:(NSDictionary *)entry job:(NSDictionary *)selectedJob;
{
  RDLPDownloadPolicy *policy=[[[RDLPDownloadPolicy alloc] initWithLibrary:library] autorelease];
  NSDictionary *selectedFile=[policy localFileForJob:selectedJob];
  if(!selectedFile) { [self showMessage:@"The downloaded file is missing. Retry its download from Queue."]; return; }
  /* Query completed jobs once, newest first, instead of querying every entry.
   * Keep the same representative-quality policy as the playlist's rows. */
  NSMutableDictionary *jobsByVideo=[NSMutableDictionary dictionary], *URLsByVideo=[NSMutableDictionary dictionary];
  for(NSDictionary *job in [library jobsForPlaylist:playlist completedOnly:YES]) {
    NSString *video=[job objectForKey:@"video_id"];
    if([jobsByVideo objectForKey:video]) continue;
    NSDictionary *file=[policy localFileForJob:job];
    if(!file) continue;
    [jobsByVideo setObject:job forKey:video];
    [URLsByVideo setObject:[NSURL fileURLWithPath:[file objectForKey:@"path"]] forKey:video];
  }
  NSMutableArray *jobs=[NSMutableArray array], *URLs=[NSMutableArray array];
  NSUInteger selected=NSNotFound;
  for(NSDictionary *candidate in [library entriesForPlaylist:playlist]) {
    NSString *video=[candidate objectForKey:@"video_id"];
    BOOL tapped=[video isEqualToString:[entry objectForKey:@"video_id"]] &&
      [[candidate objectForKey:@"position"] isEqual:[entry objectForKey:@"position"]];
    NSDictionary *job=tapped?selectedJob:[jobsByVideo objectForKey:video];
    if(!job) continue;
    if(tapped) selected=jobs.count;
    [jobs addObject:job];
    [URLs addObject:tapped?[NSURL fileURLWithPath:[selectedFile objectForKey:@"path"]]:[URLsByVideo objectForKey:video]];
  }
  /* A sync may remove/reorder the tapped occurrence while the list is visible.
   * In that case play the exact tapped file rather than selecting a different row. */
  if(selected==NSNotFound) { [self presentPlayer:owner library:library job:selectedJob]; return; }
  RDLPDownloadedPlayerViewController *controller=[[RDLPDownloadedPlayerViewController alloc]
    initWithLibrary:library jobs:jobs URLs:URLs startingAtIndex:selected];
  [owner presentViewController:controller animated:YES completion:nil]; [controller release];
}
+ (UIBarButtonItem *)item:(NSString *)title target:(id)target action:(SEL)action;
{ return [[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:target action:action] autorelease]; }
@end
