#import "RDLPQueueViewController.h"
#import "RDLPUIKit.h"

@implementation RDLPQueueViewController
- (id)initWithLibrary:(RDLPLibrary *)library;
{
  self=[super initWithLibrary:library mode:RDLPScreenQueue playlist:nil];
  if(self) {
    self.title=@"Download Queue";
    self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissQueue:)] autorelease];
  }
  return self;
}
- (void)dealloc;
{ [selectedJobID_ release]; [jobActions_ release]; [super dealloc]; }
- (BOOL)showsQueueButton; { return NO; }
- (NSIndexPath *)selectedJobIndex;
{
  NSArray *rows=[[sections_ lastObject] objectForKey:@"rows"];
  if(!selectedJobID_ || ![rows count]) return nil;
  NSUInteger index=[(RDLPLibraryRows *)rows indexForIdentity:selectedJobID_];
  return index==NSNotFound?nil:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
}
- (void)refresh:(id)sender;
{
  [super refresh:sender];
  if(![self isViewLoaded] || swipeJobID_) return;
  NSIndexPath *index=[self selectedJobIndex];
  if(index) [self.tableView selectRowAtIndexPath:index animated:NO scrollPosition:UITableViewScrollPositionNone];
}
- (void)showJobInQueue:(NSDictionary *)job;
{
  [selectedJobID_ release]; selectedJobID_=[[job objectForKey:@"id"] copy];
  [self view]; [self refresh:nil];
  NSIndexPath *index=[self selectedJobIndex];
  if(index) [self.tableView selectRowAtIndexPath:index animated:NO scrollPosition:UITableViewScrollPositionMiddle];
}
- (void)dismissQueue:(id)sender;
{ (void)sender; [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index;
{
  UITableViewCell *cell=[super tableView:table cellForRowAtIndexPath:index];
  cell.accessibilityHint=@"Show download details and actions";
  return cell;
}
- (void)showJobAlert:(NSDictionary *)job operation:(NSString *)operation;
{
  if(alert_ || !job) return;
  BOOL menu=[operation isEqualToString:@"actions"], stop=[operation isEqualToString:@"stop"];
  NSMutableArray *actions=[NSMutableArray array];
  if(menu) {
    [actions addObjectsFromArray:[model_ actionsForJob:job]];
    [actions removeObject:@"Show in Queue"];
    NSUInteger retry=[actions indexOfObject:@"Download Video"];
    if(retry!=NSNotFound) [actions replaceObjectAtIndex:retry withObject:@"Retry Download"];
  } else {
    if(stop?![policy_ canCancel:job]:(![policy_ canRemove:job] || [policy_ canCancel:job])) return;
    [actions addObject:stop?@"Stop":@"Delete"];
  }
  NSString *status=[policy_ statusForJob:job]; if([status isEqualToString:@"Cancelled"]) status=@"Stopped";
  NSString *detail=menu?[NSString stringWithFormat:@"%@ · %@\n%@",status,[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]],([job objectForKey:@"error"]?[job objectForKey:@"error"]:@"")]:
    (stop?@"Retry restarts this quality from the beginning. Other queued downloads continue.":@"Deletes this quality and its partial files. Other qualities and playlist membership are retained.");
  NSString *title=menu?[job objectForKey:@"title"]:[NSString stringWithFormat:@"%@ %@ — %@?",stop?@"Stop":@"Delete",[job objectForKey:@"title"],[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]]];
  retryRequest_=[[NSDictionary alloc] initWithObjectsAndKeys:[job objectForKey:@"id"],@"job",operation,@"operation",nil];
  jobActions_=[actions copy];
  alert_=[[UIAlertView alloc] initWithTitle:title message:detail delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:nil];
  for(NSString *action in actions) [alert_ addButtonWithTitle:action];
  [alert_ show];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index;
{
  (void)table;
  if(alert_ || self.presentedViewController || self.navigationController.presentedViewController) return;
  NSString *key=[[[self rowAtIndex:index] objectForKey:@"job"] objectForKey:@"id"];
  [selectedJobID_ release]; selectedJobID_=[key copy];
  [self showJobAlert:[model_ currentJob:key] operation:@"actions"];
}
/* Present follow-on dialogs only after UIKit has dismissed the previous one. */
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index;
{ (void)alert; (void)index; }
- (void)alertView:(UIAlertView *)alert didDismissWithButtonIndex:(NSInteger)index;
{
  if(alert!=alert_) return;
  NSDictionary *request=[[retryRequest_ retain] autorelease];
  NSString *action=index>0 && (NSUInteger)index<=[jobActions_ count]?[[[jobActions_ objectAtIndex:(NSUInteger)index-1] retain] autorelease]:nil;
  alert_.delegate=nil; [alert_ release]; alert_=nil;
  [retryRequest_ release]; retryRequest_=nil; [jobActions_ release]; jobActions_=nil;
  if(!action) return;
  NSDictionary *job=[model_ currentJob:[request objectForKey:@"job"]]; if(!job) return;
  if([[request objectForKey:@"operation"] isEqualToString:@"actions"]) {
    if([action isEqualToString:@"Play"] && [policy_ playable:job]) [RDLPUIKit presentPlayer:self path:[library_ fileForJob:job]];
    else if([action isEqualToString:@"Retry Download"] && ([policy_ canRetry:job] || [policy_ canDownloadAgain:job])) [library_ retryJob:[job objectForKey:@"id"]];
    else if([action isEqualToString:@"Stop Download…"]) [self showJobAlert:job operation:@"stop"];
    else if([action isEqualToString:@"Delete Download…"]) [self showJobAlert:job operation:@"delete"];
  } else if([action isEqualToString:@"Stop"] && [policy_ canCancel:job]) [library_ cancelJob:[job objectForKey:@"id"]];
  else if([action isEqualToString:@"Delete"] && [policy_ canRemove:job] && ![policy_ canCancel:job]) [library_ removeDownload:job];
  [self refresh:nil];
}
@end
