#import "RDLPPlaylistViewController.h"
#import "RDLPUIKit.h"
#import "RDLPLibraryViewController.h"
#import <MediaPlayer/MediaPlayer.h>

@implementation RDLPPlaylistViewController
- (id)initWithLibrary:(RDLPLibrary *)library playlist:(NSDictionary *)playlist;
{
  self=[super initWithStyle:UITableViewStylePlain]; if(!self) return nil;
  library_=[library retain]; playlist_=[playlist copy];
  policy_=[[RDLPDownloadPolicy alloc] initWithLibrary:library];
  model_=[[RDLPLibrarySections alloc] initWithLibrary:library];
  self.title=[playlist objectForKey:@"title"];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RDLPLibraryDidChange object:library_];
  return self;
}
- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  alert_.delegate=nil; [alert_ dismissWithClickedButtonIndex:alert_.cancelButtonIndex animated:NO];
  [alert_ release]; [retryRequest_ release]; [sections_ release]; [statusBar_ release];
  [playlist_ release]; [model_ release]; [policy_ release]; [library_ release]; [super dealloc];
}
- (void)viewDidLoad;
{
  [super viewDidLoad]; [RDLPUIKit configureContentEdges:self];
  self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithImage:[RDLPUIKit syncIcon] style:UIBarButtonItemStylePlain target:self action:@selector(sync:)] autorelease];
  self.navigationItem.rightBarButtonItem.accessibilityLabel=@"Sync";
  statusBar_=[[RDLPStatusBarView alloc] initWithFrame:CGRectZero];
  statusBar_.maximumWidth=MAX(0,self.view.bounds.size.width-80);
  self.toolbarItems=[RDLPUIKit statusToolbarItems:statusBar_ target:self queueAction:@selector(queue:)];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusCleared:) name:RDLPStatusBarDidClearStatus object:statusBar_];
  [self refresh:nil];
}
- (void)viewWillAppear:(BOOL)animated;
{
  [super viewWillAppear:animated];
  [self refresh:nil]; visible_=YES; [self updateToolbarAnimated:animated];
}
- (void)viewWillDisappear:(BOOL)animated;
{ visible_=NO; [super viewWillDisappear:animated]; }
- (void)viewDidLayoutSubviews;
{ [super viewDidLayoutSubviews]; statusBar_.maximumWidth=MAX(0,self.view.bounds.size.width-80); }
- (void)updateToolbarAnimated:(BOOL)animated;
{
  if(!visible_ || self.navigationController.topViewController!=self) return;
  NSString *status=[library_ status];
  BOOL hidden=![status length] || [status isEqualToString:@"Ready"] || !statusBar_.hasStatus;
  if(self.navigationController.toolbarHidden!=hidden) [self.navigationController setToolbarHidden:hidden animated:animated];
}
- (void)statusCleared:(NSNotification *)notification;
{ (void)notification; [self updateToolbarAnimated:YES]; }
- (void)refresh:(id)sender;
{
  (void)sender; if(![self isViewLoaded]) return;
  for(NSDictionary *playlist in [library_ playlists]) if([[playlist objectForKey:@"id"] isEqualToString:[playlist_ objectForKey:@"id"]]) {
    [playlist retain]; [playlist_ release]; playlist_=playlist; self.title=[playlist objectForKey:@"title"]; break;
  }
  NSArray *sections=[model_ sectionsForScreen:RDLPScreenPlaylist playlist:playlist_ video:nil collapsed:nil];
  [sections_ release]; sections_=[sections copy];
  self.navigationItem.rightBarButtonItem.enabled=![library_ isSyncPendingForInput:[playlist_ objectForKey:@"service_id"]];
  [statusBar_ setStatus:[library_ status] progress:[library_ queueProgress] busy:[library_ isBusy]];
  [self updateToolbarAnimated:YES];
  [self.tableView reloadData];
}
- (void)sync:(id)sender;
{
  (void)sender; NSString *input=[playlist_ objectForKey:@"service_id"];
  if(![library_ isSyncPendingForInput:input]) [library_ syncPlaylistInput:input];
  [self refresh:nil];
}
- (void)queue:(id)sender;
{
  (void)sender; if(self.presentedViewController || self.navigationController.presentedViewController || alert_) return;
  RDLPLibraryViewController *queue=[[[RDLPLibraryViewController alloc] initWithLibrary:library_ mode:RDLPScreenQueue playlist:nil video:nil] autorelease];
  queue.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:queue action:@selector(dismissQueue:)] autorelease];
  UINavigationController *modal=[[[UINavigationController alloc] initWithRootViewController:queue] autorelease];
  [self.navigationController presentViewController:modal animated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table;
{ (void)table; return (NSInteger)[sections_ count]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{ (void)table; return (NSInteger)[[[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"rows"] count]; }
- (NSDictionary *)rowAtIndex:(NSIndexPath *)index;
{ return [[[sections_ objectAtIndex:(NSUInteger)index.section] objectForKey:@"rows"] objectAtIndex:(NSUInteger)index.row]; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section;
{ return [self tableView:table numberOfRowsInSection:section]?nil:@"No items"; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index;
{
  UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"video"];
  if(!cell) cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"video"] autorelease];
  NSDictionary *row=[self rowAtIndex:index]; NSString *status=[row objectForKey:@"status"];
  cell.textLabel.text=[row objectForKey:@"title"];
  cell.detailTextLabel.text=[row objectForKey:@"detail"];
  cell.accessoryType=UITableViewCellAccessoryNone;
  UIImageView *accessory=[[[UIImageView alloc] initWithImage:[RDLPUIKit statusIcon:status]] autorelease];
  accessory.isAccessibilityElement=NO; cell.accessoryView=accessory;
  cell.accessibilityLabel=[NSString stringWithFormat:@"%@, %@, %@",cell.textLabel.text,cell.detailTextLabel.text,status];
  cell.accessibilityHint=[status isEqualToString:@"Downloaded"]?@"Play video":(([status isEqualToString:@"Queued"] || [status isEqualToString:@"Downloading"])?@"Download in progress":@"Download video");
  return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index;
{
  NSDictionary *row=[[[self rowAtIndex:index] retain] autorelease], *entry=[row objectForKey:@"video"];
  [table deselectRowAtIndexPath:index animated:YES];
  if(alert_ || self.presentedViewController || self.navigationController.presentedViewController) return;
  NSString *pid=[playlist_ objectForKey:@"id"];
  NSDictionary *selectedJob=[row objectForKey:@"job"];
  NSString *format=selectedJob?[selectedJob objectForKey:@"format"]:[RDLPLibrary preferredFormat];
  /* Resolve the selected quality again; another row may have queued it. */
  NSDictionary *job=[model_ jobForPlaylist:pid video:[entry objectForKey:@"video_id"] format:format];
  if([policy_ playable:job]) {
    NSURL *url=[NSURL fileURLWithPath:[library_ fileForJob:job]];
    MPMoviePlayerViewController *player=[[[MPMoviePlayerViewController alloc] initWithContentURL:url] autorelease];
    [self presentMoviePlayerViewControllerAnimated:player]; return;
  }
  if([policy_ canCancel:job]) return;
  NSString *status=[policy_ statusForJob:job];
  if([policy_ canRetry:job] || [status isEqualToString:@"File missing"]) {
    NSString *reason=[status isEqualToString:@"Failed"]?@"The previous download failed.":([status isEqualToString:@"Interrupted"]?@"The previous download was interrupted.":([status isEqualToString:@"Cancelled"]?@"The previous download was stopped.":@"The downloaded file is missing."));
    NSString *error=[job objectForKey:@"error"];
    NSString *message=[NSString stringWithFormat:@"%@%@\n\nRetry downloads this video from the beginning at the same quality (%@).",reason,[error length]?[@"\n\n" stringByAppendingString:error]:@"",[job objectForKey:@"format"]];
    retryRequest_=[[NSDictionary alloc] initWithObjectsAndKeys:[job objectForKey:@"id"],@"job",entry,@"entry",nil];
    alert_=[[UIAlertView alloc] initWithTitle:@"Retry Download?" message:message delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Retry",nil];
    [alert_ show]; return;
  }
  if([policy_ canDownloadAgain:job]) [library_ retryJob:[job objectForKey:@"id"]];
  else [library_ enqueuePlaylist:pid video:[entry objectForKey:@"video_id"] format:format];
  [self refresh:nil];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index;
{
  if(alert!=alert_) return;
  NSDictionary *request=[[retryRequest_ retain] autorelease]; BOOL retry=index!=alert.cancelButtonIndex;
  alert_.delegate=nil; [alert_ release]; alert_=nil; [retryRequest_ release]; retryRequest_=nil;
  if(!retry) return;
  /* A sync or another download can finish while the confirmation is open. */
  NSDictionary *entry=nil;
  for(NSDictionary *candidate in [library_ entriesForPlaylist:[playlist_ objectForKey:@"id"]])
    if([[candidate objectForKey:@"video_id"] isEqualToString:[[request objectForKey:@"entry"] objectForKey:@"video_id"]]) { entry=candidate; break; }
  NSDictionary *job=[model_ currentJob:[request objectForKey:@"job"]];
  if(entry && ([policy_ canRetry:job] || [policy_ canDownloadAgain:job]))
    [library_ retryJob:[job objectForKey:@"id"]];
  [self refresh:nil];
}
@end
