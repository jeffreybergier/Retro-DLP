#import "RDLPQueueViewController.h"
#import "RDLPUIKit.h"

@implementation RDLPQueueViewController
- (id)initWithLibrary:(RDLPLibrary *)library;
{
  self=[super initWithLibrary:library title:NSLocalizedString(@"Download Queue", nil)];
  if(self) {
    [self setTitle:NSLocalizedString(@"Download Queue", nil)];
    [[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissQueue:)] autorelease]];
  }
  return self;
}
- (void)dealloc;
{ [selectedJobID_ release]; [jobActions_ release]; [super dealloc]; }
- (BOOL)showsQueueButton; { return NO; }
- (NSArray *)listSections;
{ return [model_ sectionsForScreen:RDLPScreenQueue playlist:nil video:nil collapsed:nil]; }
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
  if(index) [[self tableView] selectRowAtIndexPath:index animated:NO scrollPosition:UITableViewScrollPositionNone];
}
- (void)showJobInQueue:(NSDictionary *)job;
{
  [selectedJobID_ release]; selectedJobID_=[[job objectForKey:@"id"] copy];
  [self view]; [self refresh:nil];
  NSIndexPath *index=[self selectedJobIndex];
  if(index) [[self tableView] selectRowAtIndexPath:index animated:NO scrollPosition:UITableViewScrollPositionMiddle];
}
- (void)dismissQueue:(id)sender;
{ (void)sender; [[self navigationController] dismissViewControllerAnimated:YES completion:nil]; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index;
{
  UITableViewCell *cell=[super tableView:table cellForRowAtIndexPath:index];
  [[cell detailTextLabel] setNumberOfLines:1];
  [RDLPUIKit truncateMiddleInLabel:[cell detailTextLabel]];
  [cell setAccessibilityHint:NSLocalizedString(@"Show download details and actions", nil)];
  return cell;
}
- (void)showJobAlert:(NSDictionary *)job operation:(NSString *)operation;
{
  if(alert_ || !job) return;
  BOOL menu=[operation isEqualToString:@"actions"], stop=[operation isEqualToString:@"stop"];
  NSMutableArray *actions=[NSMutableArray array];
  if(menu) {
    [actions addObjectsFromArray:[model_ actionsForJob:job]];
    [actions removeObject:NSLocalizedString(@"Show in Queue", nil)];
    NSUInteger retry=[actions indexOfObject:NSLocalizedString(@"Download Video", nil)];
    if(retry!=NSNotFound) [actions replaceObjectAtIndex:retry withObject:NSLocalizedString(@"Retry", nil)];
  } else {
    if(stop?![policy_ canCancel:job]:(![policy_ canRemove:job] || [policy_ canCancel:job])) return;
    [actions addObject:stop?NSLocalizedString(@"Stop", nil):NSLocalizedString(@"Delete", nil)];
  }
  NSString *status=[policy_ statusForJob:job]; if([status isEqualToString:NSLocalizedString(@"Cancelled", nil)]) status=NSLocalizedString(@"Stopped", nil);
  NSString *item=[NSString stringWithFormat:NSLocalizedString(@"%@ — %@", nil),[job objectForKey:@"title"],[RDLPLibrary qualityDetailForFormat:[job objectForKey:@"format"]]];
  NSString *explanation=stop?NSLocalizedString(@"Retry restarts this quality from the beginning. Other queued downloads continue.", nil):NSLocalizedString(@"Deletes this quality and its partial files. Other qualities and playlist membership are retained.", nil);
  NSString *detail=menu?[NSString stringWithFormat:NSLocalizedString(@"%@·%@\n%@", nil),status,[RDLPLibrary qualityDetailForFormat:[job objectForKey:@"format"]],([job objectForKey:@"error"]?[job objectForKey:@"error"]:@"")]:[NSString stringWithFormat:NSLocalizedString(@"%@\n\n%@", nil),item,explanation];
  NSString *title=menu?[job objectForKey:@"title"]:(stop?NSLocalizedString(@"Stop Download?", nil):NSLocalizedString(@"Delete Download?", nil));
  retryRequest_=[[NSDictionary alloc] initWithObjectsAndKeys:[job objectForKey:@"id"],@"job",operation,@"operation",nil];
  jobActions_=[actions copy];
  alert_=[[UIAlertView alloc] initWithTitle:title message:detail delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", nil) otherButtonTitles:nil];
  for(NSString *action in actions) [alert_ addButtonWithTitle:action];
  [alert_ show];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index;
{
  (void)table;
  if(alert_ || [self presentedViewController] || [[self navigationController] presentedViewController]) return;
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
  [alert_ setDelegate:nil]; [alert_ release]; alert_=nil;
  [retryRequest_ release]; retryRequest_=nil; [jobActions_ release]; jobActions_=nil;
  if(!action) return;
  NSDictionary *job=[model_ currentJob:[request objectForKey:@"job"]]; if(!job) return;
  if([[request objectForKey:@"operation"] isEqualToString:@"actions"]) {
    if([action isEqualToString:NSLocalizedString(@"Play", nil)] && [policy_ playable:job]) [RDLPUIKit presentPlayer:self library:library_ job:job];
    else if([action isEqualToString:NSLocalizedString(@"Retry", nil)] && ([policy_ canRetry:job] || [policy_ canDownloadAgain:job])) [library_ retryJob:[job objectForKey:@"id"]];
    else if([action isEqualToString:NSLocalizedString(@"Stop…", nil)]) [self showJobAlert:job operation:@"stop"];
    else if([action isEqualToString:NSLocalizedString(@"Delete…", nil)]) [self showJobAlert:job operation:@"delete"];
  } else if([action isEqualToString:NSLocalizedString(@"Stop", nil)] && [policy_ canCancel:job]) [library_ cancelJob:[job objectForKey:@"id"]];
  else if([action isEqualToString:NSLocalizedString(@"Delete", nil)] && [policy_ canRemove:job] && ![policy_ canCancel:job]) [library_ removeDownload:job];
  [self refresh:nil];
}
@end
