#import "RDLPLibraryViewController.h"
#import "RDLPUIKit.h"
#import "RDLPPlaylistViewController.h"
#import "RDLPDownloadsViewController.h"
#import "RDLPQueueViewController.h"

@implementation RDLPLibraryViewController
@synthesize tableView=tableView_;
- (id)initWithLibrary:(RDLPLibrary *)library mode:(RDLPScreen)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
{
  self=[super init]; if(!self) return nil;
  library_=[library retain]; mode_=mode; playlist_=[playlist copy]; video_=[video copy];
  policy_=[[RDLPDownloadPolicy alloc] initWithLibrary:library]; model_=[[RDLPLibrarySections alloc] initWithLibrary:library];
  self.title=mode==RDLPScreenLibrary?@"Playlists":(mode==RDLPScreenPlaylist?[playlist objectForKey:@"title"]:(mode==RDLPScreenQueue?@"Download Queue":(mode==RDLPScreenDownloads?@"All Downloads":(mode==RDLPScreenSettings?@"Settings":@"Video"))));
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RDLPLibraryDidChange object:library_];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshStatus:) name:RDLPLibraryStatusDidChange object:library_]; return self;
}
- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self]; alert_.delegate=nil; [alert_ dismissWithClickedButtonIndex:0 animated:NO];
  playlistActions_.delegate=nil; [playlistActions_ dismissWithClickedButtonIndex:playlistActions_.cancelButtonIndex animated:NO]; [playlistActions_ release];
  [alert_ release]; [request_ release]; [alertActions_ release];
  tableView_.delegate=nil; tableView_.dataSource=nil; [tableView_ release];
  [library_ release]; [policy_ release]; [model_ release]; [playlist_ release]; [video_ release]; [sections_ release]; [statusBar_ release]; [status_ release]; [progress_ release]; [super dealloc];
}
- (void)viewDidLoad;
{
  [super viewDidLoad];
  [RDLPUIKit configureContentEdges:self];
  self.view.backgroundColor=[UIColor groupTableViewBackgroundColor];
  tableView_=[[UITableView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,self.view.bounds.size.height-(mode_==RDLPScreenLibrary?0:56)) style:mode_==RDLPScreenLibrary?UITableViewStylePlain:UITableViewStyleGrouped];
  tableView_.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; tableView_.delegate=self; tableView_.dataSource=self; [self.view addSubview:tableView_];
  if(mode_!=RDLPScreenLibrary) {
  UIView *footer=[[[UIView alloc] initWithFrame:CGRectMake(0,self.view.bounds.size.height-56,self.view.bounds.size.width,56)] autorelease];
  footer.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin;
  status_=[[UILabel alloc] initWithFrame:CGRectMake(12,0,footer.bounds.size.width-24,44)];
  status_.numberOfLines=3; status_.font=[UIFont systemFontOfSize:12]; status_.backgroundColor=[UIColor clearColor]; status_.autoresizingMask=UIViewAutoresizingFlexibleWidth; [footer addSubview:status_];
  progress_=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault]; progress_.frame=CGRectMake(12,48,footer.bounds.size.width-24,4); progress_.autoresizingMask=UIViewAutoresizingFlexibleWidth; [footer addSubview:progress_]; [self.view addSubview:footer];
  }
  if(mode_==RDLPScreenLibrary) {
    statusBar_=[[RDLPStatusBarView alloc] initWithFrame:CGRectZero];
    statusBar_.maximumWidth=MAX(0,self.view.bounds.size.width-112);
    self.toolbarItems=[RDLPUIKit statusToolbarItems:statusBar_ target:self queueAction:@selector(queue:)];
    self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithImage:[RDLPUIKit plusIcon] style:UIBarButtonItemStylePlain target:self action:@selector(showPlaylistActions:)] autorelease];
    self.navigationItem.leftBarButtonItem=[[[UIBarButtonItem alloc] initWithImage:[RDLPUIKit settingsIcon] style:UIBarButtonItemStylePlain target:self action:@selector(settings:)] autorelease];
    self.navigationItem.leftBarButtonItem.accessibilityLabel=@"Settings";
    self.navigationItem.rightBarButtonItem.accessibilityLabel=@"Playlist Actions";
  }
  [self refresh:nil];
}
- (void)viewWillAppear:(BOOL)animated;
{ [super viewWillAppear:animated]; [self.navigationController setToolbarHidden:![self.toolbarItems count] animated:animated]; [self refresh:nil]; }
- (void)viewDidLayoutSubviews;
{
  [super viewDidLayoutSubviews];
  statusBar_.maximumWidth=MAX(0,self.view.bounds.size.width-112);
}
- (void)refresh:(id)sender;
{
  (void)sender; if(![self isViewLoaded]) return;
  /* Keep the displayed playlist current after sync or discovery promotion. */
  NSDictionary *playlist=[library_ playlistForID:[playlist_ objectForKey:@"id"]];
  if(playlist) {
    [playlist retain]; [playlist_ release]; playlist_=playlist;
    if(mode_==RDLPScreenPlaylist) self.title=[playlist objectForKey:@"title"];
  }
  NSArray *sections=[model_ sectionsForScreen:mode_ playlist:playlist_ video:video_ collapsed:nil]; [sections_ release]; sections_=[sections copy];
  [self refreshStatus:nil];
  for(UIBarButtonItem *item in self.toolbarItems) {
    if(item.action==@selector(sync:)) item.enabled=[self enabled:@"sync"];
    if(item.action==@selector(syncAll:)) item.enabled=[self enabled:@"syncAll"];
    if(item.action==@selector(discover:)) item.enabled=[self enabled:@"discover"];
    if(item.action==@selector(downloadAll:)) item.enabled=[self enabled:@"bulk"];
    if(item.action==@selector(removePlaylist:)) item.enabled=[self enabled:@"removePlaylist"];
  }
  [self.tableView reloadData];
}
- (void)refreshStatus:(id)sender;
{
  (void)sender; if(![self isViewLoaded]) return;
  NSDictionary *progress=[library_ activityProgress];
  [statusBar_ setStatus:[library_ status] progress:progress busy:[library_ isBusy]];
  double expected=[[progress objectForKey:@"expected"] doubleValue];
  progress_.hidden=![[progress objectForKey:@"active"] boolValue] || expected<=0;
  progress_.progress=expected>0?(float)MIN(1.0,[[progress objectForKey:@"completed"] doubleValue]/expected):0;
  progress_.accessibilityLabel=[library_ status]; status_.text=[library_ status];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)view; { (void)view; return (NSInteger)[sections_ count]; }
- (NSInteger)tableView:(UITableView *)view numberOfRowsInSection:(NSInteger)section;
{ (void)view; return (NSInteger)[[[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"rows"] count]; }
- (CGFloat)tableView:(UITableView *)view heightForHeaderInSection:(NSInteger)section;
{ (void)section; return mode_==RDLPScreenLibrary?view.sectionHeaderHeight:40; }
- (NSString *)tableView:(UITableView *)view titleForHeaderInSection:(NSInteger)section;
{ (void)view; return [[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"title"]; }
- (NSString *)tableView:(UITableView *)view titleForFooterInSection:(NSInteger)section;
{
  (void)view;
  if(mode_==RDLPScreenLibrary || mode_==RDLPScreenSettings) return nil;
  if(![[[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"rows"] count]) return @"No items";
  return nil;
}
- (NSDictionary *)rowAtIndex:(NSIndexPath *)index;
{ return [[[sections_ objectAtIndex:(NSUInteger)index.section] objectForKey:@"rows"] objectAtIndex:(NSUInteger)index.row]; }
- (UITableViewCell *)tableView:(UITableView *)view cellForRowAtIndexPath:(NSIndexPath *)index;
{
  NSDictionary *row=[self rowAtIndex:index]; NSString *action=[row objectForKey:@"action"];
  if(mode_==RDLPScreenPlaylist || mode_==RDLPScreenLibrary) {
    UITableViewCell *cell=[view dequeueReusableCellWithIdentifier:@"playlistRow"];
    if(!cell) cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"playlistRow"] autorelease];
    cell.textLabel.text=[row objectForKey:@"title"];
    cell.detailTextLabel.text=[row objectForKey:@"detail"];
    cell.imageView.image=[row objectForKey:@"status"]?[RDLPUIKit statusIcon:[row objectForKey:@"status"]]:nil;
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
  }
  if(mode_==RDLPScreenSettings && [action isEqualToString:@"custom"]) {
    UITableViewCell *cell=[view dequeueReusableCellWithIdentifier:@"exactFormat"];
    if(!cell) cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"exactFormat"] autorelease];
    cell.textLabel.text=[row objectForKey:@"title"];
    cell.detailTextLabel.text=[row objectForKey:@"detail"];
    cell.accessoryType=[[row objectForKey:@"checked"] boolValue]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    return cell;
  }
  UITableViewCell *cell=[view dequeueReusableCellWithIdentifier:@"row"];
  if(!cell) cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"] autorelease];
  BOOL enabled=[self enabled:action];
  cell.textLabel.text=[row objectForKey:@"title"]; cell.detailTextLabel.text=[row objectForKey:@"detail"];
  cell.textLabel.numberOfLines=2; cell.detailTextLabel.numberOfLines=2; cell.detailTextLabel.font=[UIFont systemFontOfSize:12]; cell.textLabel.font=[UIFont systemFontOfSize:16];
  cell.textLabel.textColor=enabled?[UIColor blackColor]:[UIColor grayColor]; cell.selectionStyle=enabled?UITableViewCellSelectionStyleBlue:UITableViewCellSelectionStyleNone;
  cell.accessoryView=nil; cell.imageView.image=[row objectForKey:@"status"]?[RDLPUIKit statusIcon:[row objectForKey:@"status"]]:nil; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
  if(mode_==RDLPScreenSettings && ([action isEqualToString:@"import"] || [action isEqualToString:@"clearCookies"] || [action isEqualToString:@"guide"])) cell.accessoryType=UITableViewCellAccessoryNone;
  if([row objectForKey:@"checked"]) cell.accessoryType=[[row objectForKey:@"checked"] boolValue]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
  cell.accessibilityLabel=[NSString stringWithFormat:@"%@, %@",cell.textLabel.text,cell.detailTextLabel.text]; return cell;
}
- (CGFloat)tableView:(UITableView *)view heightForRowAtIndexPath:(NSIndexPath *)index;
{
  (void)index;
  /* UIKit asks heights for offscreen rows too. Never load their payloads here. */
  if(mode_==RDLPScreenPlaylist || mode_==RDLPScreenLibrary || mode_==RDLPScreenSettings) return view.rowHeight;
  return 64;
}
- (void)tableView:(UITableView *)view didSelectRowAtIndexPath:(NSIndexPath *)index;
{
  NSDictionary *row=[[[self rowAtIndex:index] retain] autorelease]; [view deselectRowAtIndexPath:index animated:YES];
  if([self enabled:[row objectForKey:@"action"]]) [self performRow:row];
}
- (void)pushMode:(RDLPScreen)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
{
  if(mode==RDLPScreenQueue) { [self showJobInQueue:nil]; return; }
  UIViewController *controller=mode==RDLPScreenPlaylist?
    (UIViewController *)[[RDLPPlaylistViewController alloc] initWithLibrary:library_ playlist:playlist]:
    (mode==RDLPScreenDownloads?(UIViewController *)[[RDLPDownloadsViewController alloc] initWithLibrary:library_]:
    [[RDLPLibraryViewController alloc] initWithLibrary:library_ mode:mode playlist:playlist video:video]);
  [self.navigationController pushViewController:controller animated:YES]; [controller release];
}
- (void)showJobInQueue:(NSDictionary *)job;
{
  RDLPQueueViewController *queue=nil;
  UINavigationController *navigation=self.navigationController;
  UIViewController *presented=navigation.presentedViewController;
  if([presented isKindOfClass:[UINavigationController class]]) {
    UIViewController *root=[[(UINavigationController *)presented viewControllers] objectAtIndex:0];
    if([root isKindOfClass:[RDLPQueueViewController class]]) queue=(RDLPQueueViewController *)root;
  }
  if(!queue) {
    if(presented || alert_ || playlistActions_) return;
    queue=[[[RDLPQueueViewController alloc] initWithLibrary:library_] autorelease];
    UINavigationController *modal=[[[UINavigationController alloc] initWithRootViewController:queue] autorelease];
    [navigation presentViewController:modal animated:YES completion:nil];
  }
  [queue showJobInQueue:job];
}
@end
