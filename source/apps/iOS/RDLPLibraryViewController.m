#import "RDLPLibraryViewController.h"
#import "RDLPUIKit.h"

@implementation RDLPLibraryViewController
@synthesize tableView=tableView_;
- (id)initWithLibrary:(RDLPLibrary *)library mode:(RDLPScreen)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
{
  self=[super init]; if(!self) return nil;
  library_=[library retain]; mode_=mode; playlist_=[playlist copy]; video_=[video copy];
  policy_=[[RDLPDownloadPolicy alloc] initWithLibrary:library]; model_=[[RDLPLibrarySections alloc] initWithLibrary:library]; collapsed_=[[NSMutableSet alloc] init];
  self.title=mode==RDLPScreenLibrary?@"RetroDLP":(mode==RDLPScreenPlaylist?[playlist objectForKey:@"title"]:(mode==RDLPScreenQueue?@"Download Queue":(mode==RDLPScreenDownloads?@"All Downloads":(mode==RDLPScreenSettings?@"Settings":@"Video"))));
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RDLPLibraryDidChange object:library_]; return self;
}
- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self]; alert_.delegate=nil; [alert_ dismissWithClickedButtonIndex:0 animated:NO];
  [alert_ release]; [request_ release]; [alertActions_ release]; [revealJobID_ release]; [revealGroup_ release];
  tableView_.delegate=nil; tableView_.dataSource=nil; [tableView_ release];
  [library_ release]; [policy_ release]; [model_ release]; [playlist_ release]; [video_ release]; [sections_ release]; [collapsed_ release]; [status_ release]; [progress_ release]; [super dealloc];
}
- (void)viewDidLoad;
{
  [super viewDidLoad];
  [RDLPUIKit configureContentEdges:self];
  self.view.backgroundColor=[UIColor groupTableViewBackgroundColor];
  tableView_=[[UITableView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,self.view.bounds.size.height-56) style:UITableViewStyleGrouped];
  tableView_.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; tableView_.delegate=self; tableView_.dataSource=self; [self.view addSubview:tableView_];
  UIView *footer=[[[UIView alloc] initWithFrame:CGRectMake(0,self.view.bounds.size.height-56,self.view.bounds.size.width,56)] autorelease];
  footer.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin;
  status_=[[UILabel alloc] initWithFrame:CGRectMake(12,0,footer.bounds.size.width-24,44)];
  status_.numberOfLines=3; status_.font=[UIFont systemFontOfSize:12]; status_.backgroundColor=[UIColor clearColor]; status_.autoresizingMask=UIViewAutoresizingFlexibleWidth; [footer addSubview:status_];
  progress_=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault]; progress_.frame=CGRectMake(12,48,footer.bounds.size.width-24,4); progress_.autoresizingMask=UIViewAutoresizingFlexibleWidth; [footer addSubview:progress_]; [self.view addSubview:footer];
  if(mode_==RDLPScreenLibrary) {
    self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add:)] autorelease];
    self.toolbarItems=[NSArray arrayWithObjects:[RDLPUIKit item:@"My Playlists" target:self action:@selector(discover:)],[RDLPUIKit item:@"Sync All" target:self action:@selector(syncAll:)],[RDLPUIKit item:@"Queue" target:self action:@selector(queue:)],nil];
  } else if(mode_==RDLPScreenPlaylist) {
    self.toolbarItems=[NSArray arrayWithObjects:[RDLPUIKit item:@"Sync" target:self action:@selector(sync:)],[RDLPUIKit item:@"Download Missing" target:self action:@selector(downloadAll:)],[RDLPUIKit item:@"Remove" target:self action:@selector(removePlaylist:)],nil];
    self.navigationItem.rightBarButtonItem=[RDLPUIKit item:@"Quality" target:self action:@selector(settings:)];
  }
  [self refresh:nil];
}
- (void)viewWillAppear:(BOOL)animated;
{ [super viewWillAppear:animated]; [self.navigationController setToolbarHidden:![self.toolbarItems count] animated:animated]; [self refresh:nil]; }
- (void)refresh:(id)sender;
{
  (void)sender; if(![self isViewLoaded]) return;
  /* Keep the displayed playlist current after sync or discovery promotion. */
  for(NSDictionary *playlist in [library_ playlists]) if([[playlist objectForKey:@"id"] isEqualToString:[playlist_ objectForKey:@"id"]]) {
    [playlist retain]; [playlist_ release]; playlist_=playlist; if(mode_==RDLPScreenPlaylist) self.title=[playlist objectForKey:@"title"]; break;
  }
  BOOL scrollToSelection=NO;
  if(mode_==RDLPScreenQueue && revealJobID_) {
    NSDictionary *selected=[model_ currentJob:revealJobID_]; NSString *group=selected?[model_ queueGroupForJob:selected]:nil;
    if(group && ![group isEqualToString:revealGroup_]) {
      scrollToSelection=YES;
      NSString *key=[NSString stringWithFormat:@"%@/playlist:%@",group,[selected objectForKey:@"playlist_id"]];
      [collapsed_ removeObject:[@"section:" stringByAppendingString:group]];
      [collapsed_ removeObject:key]; [collapsed_ removeObject:[key stringByAppendingFormat:@"/video:%@",[selected objectForKey:@"video_id"]]];
    }
    [revealGroup_ release]; revealGroup_=[group copy];
  }
  NSArray *sections=[model_ sectionsForScreen:mode_ playlist:playlist_ video:video_ collapsed:collapsed_]; [sections_ release]; sections_=[sections copy];
  NSDictionary *progress=[library_ queueProgress]; NSUInteger total=[[progress objectForKey:@"total"] unsignedIntegerValue], processed=[[progress objectForKey:@"processed"] unsignedIntegerValue];
  progress_.hidden=![[progress objectForKey:@"active"] boolValue] || !total;
  progress_.progress=total?(float)processed/(float)total:0;
  progress_.accessibilityLabel=[NSString stringWithFormat:@"%@ processed of %@; %@ failed; %@ stopped",[progress objectForKey:@"processed"],[progress objectForKey:@"total"],[progress objectForKey:@"failed"],[progress objectForKey:@"cancelled"]];
  status_.text=progress_.hidden?[library_ status]:[NSString stringWithFormat:@"%@\n%@",[library_ status],progress_.accessibilityLabel];
  for(UIBarButtonItem *item in self.toolbarItems) {
    if(item.action==@selector(sync:)) item.enabled=[self enabled:@"sync"];
    if(item.action==@selector(syncAll:)) item.enabled=[self enabled:@"syncAll"];
    if(item.action==@selector(discover:)) item.enabled=[self enabled:@"discover"];
    if(item.action==@selector(downloadAll:)) item.enabled=[self enabled:@"bulk"];
    if(item.action==@selector(removePlaylist:)) item.enabled=[self enabled:@"removePlaylist"];
  }
  [self.tableView reloadData];
  if(revealJobID_) for(NSUInteger s=0;s<[sections_ count];++s) {
    if([collapsed_ containsObject:[self sectionKey:(NSInteger)s]]) continue;
    NSArray *rows=[[sections_ objectAtIndex:s] objectForKey:@"rows"];
    for(NSUInteger r=0;r<[rows count];++r) if([[[[rows objectAtIndex:r] objectForKey:@"job"] objectForKey:@"id"] isEqualToString:revealJobID_]) {
      NSIndexPath *index=[NSIndexPath indexPathForRow:(NSInteger)r inSection:(NSInteger)s];
      [self.tableView selectRowAtIndexPath:index animated:NO scrollPosition:scrollToSelection?UITableViewScrollPositionMiddle:UITableViewScrollPositionNone]; return;
    }
  }
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)view; { (void)view; return (NSInteger)[sections_ count]; }
- (NSString *)sectionKey:(NSInteger)section;
{ return [@"section:" stringByAppendingString:[[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"title"]]; }
- (NSInteger)tableView:(UITableView *)view numberOfRowsInSection:(NSInteger)section;
{ (void)view; return [collapsed_ containsObject:[self sectionKey:section]]?0:(NSInteger)[[[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"rows"] count]; }
- (UIView *)tableView:(UITableView *)view viewForHeaderInSection:(NSInteger)section;
{
  (void)view; if(mode_!=RDLPScreenLibrary && mode_!=RDLPScreenQueue) return nil;
  UIButton *header=[UIButton buttonWithType:UIButtonTypeCustom]; header.tag=section;
  header.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft; header.contentEdgeInsets=UIEdgeInsetsMake(8,12,0,12); header.titleLabel.font=[UIFont boldSystemFontOfSize:14];
  [header setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
  NSString *title=[[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"title"];
  BOOL collapsed=[collapsed_ containsObject:[self sectionKey:section]];
  [header setTitle:[NSString stringWithFormat:@"%@ %@",collapsed?@"▸":@"▾",title] forState:UIControlStateNormal];
  header.accessibilityLabel=[NSString stringWithFormat:@"%@ %@",collapsed?@"Expand":@"Collapse",title];
  [header addTarget:self action:@selector(toggleSection:) forControlEvents:UIControlEventTouchUpInside]; return header;
}
- (CGFloat)tableView:(UITableView *)view heightForHeaderInSection:(NSInteger)section;
{ (void)view; (void)section; return 40; }
- (void)toggleSection:(UIButton *)sender;
{
  NSString *key=[self sectionKey:sender.tag];
  if([collapsed_ containsObject:key]) [collapsed_ removeObject:key]; else [collapsed_ addObject:key]; [self refresh:nil];
}
- (NSString *)tableView:(UITableView *)view titleForHeaderInSection:(NSInteger)section;
{ (void)view; return [[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"title"]; }
- (NSString *)tableView:(UITableView *)view titleForFooterInSection:(NSInteger)section;
{
  (void)view;
  if(mode_==RDLPScreenSettings) return section==0?@"Choosing quality saves your preference. Use Download Video or Download Missing to start. Downloads run while the app is in the foreground.":@"Cookies status describes the local file, not whether your account session is valid. Import copies the file; your original is retained. Use iTunes File Sharing or open a text file in RetroDLP.";
  if(![[[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"rows"] count]) return @"No items";
  return nil;
}
- (NSDictionary *)rowAtIndex:(NSIndexPath *)index;
{ return [[[sections_ objectAtIndex:(NSUInteger)index.section] objectForKey:@"rows"] objectAtIndex:(NSUInteger)index.row]; }
- (UITableViewCell *)tableView:(UITableView *)view cellForRowAtIndexPath:(NSIndexPath *)index;
{
  UITableViewCell *cell=[view dequeueReusableCellWithIdentifier:@"row"];
  if(!cell) cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"] autorelease];
  NSDictionary *row=[self rowAtIndex:index]; NSString *action=[row objectForKey:@"action"];
  BOOL enabled=[self enabled:action];
  cell.textLabel.text=[row objectForKey:@"title"]; cell.detailTextLabel.text=[row objectForKey:@"detail"];
  cell.textLabel.numberOfLines=2; cell.detailTextLabel.numberOfLines=mode_==RDLPScreenQueue?1:2; cell.detailTextLabel.font=[UIFont systemFontOfSize:12]; cell.textLabel.font=[UIFont systemFontOfSize:16];
  cell.textLabel.textColor=enabled?[UIColor blackColor]:[UIColor grayColor]; cell.selectionStyle=enabled?UITableViewCellSelectionStyleBlue:UITableViewCellSelectionStyleNone;
  cell.indentationLevel=[[row objectForKey:@"depth"] integerValue]; cell.indentationWidth=12;
  cell.accessoryView=nil; cell.imageView.image=[row objectForKey:@"status"]?[RDLPUIKit statusIcon:[row objectForKey:@"status"]]:nil; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
  if([row objectForKey:@"checked"]) cell.accessoryType=[[row objectForKey:@"checked"] boolValue]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
  if([action isEqualToString:@"collapse"]) {
    cell.textLabel.font=[UIFont boldSystemFontOfSize:16];
    cell.textLabel.text=[NSString stringWithFormat:@"%@ %@",[collapsed_ containsObject:[row objectForKey:@"key"]]?@"▸":@"▾",[row objectForKey:@"title"]];
    cell.detailTextLabel.text=@""; cell.accessoryType=UITableViewCellAccessoryNone;
  }
  NSDictionary *job=[row objectForKey:@"job"];
  if(mode_==RDLPScreenQueue && job && ([policy_ canCancel:job] || [policy_ canRetry:job] || [policy_ canDownloadAgain:job])) {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeRoundedRect]; button.frame=CGRectMake(0,0,54,40);
    [button setImage:[RDLPUIKit queueActionIcon:[policy_ canCancel:job]] forState:UIControlStateNormal];
    button.accessibilityIdentifier=[job objectForKey:@"id"];
    button.accessibilityLabel=[NSString stringWithFormat:@"%@ %@, %@",[policy_ canCancel:job]?@"Stop":@"Retry",[job objectForKey:@"title"],[job objectForKey:@"format"]];
    [button addTarget:self action:@selector(queueAction:) forControlEvents:UIControlEventTouchUpInside]; cell.accessoryView=button;
  }
  cell.accessibilityLabel=[NSString stringWithFormat:@"%@, %@",cell.textLabel.text,cell.detailTextLabel.text]; return cell;
}
- (CGFloat)tableView:(UITableView *)view heightForRowAtIndexPath:(NSIndexPath *)index;
{ (void)view; NSDictionary *row=[self rowAtIndex:index]; return [[row objectForKey:@"action"] isEqualToString:@"collapse"]?44:([[row objectForKey:@"detail"] length]?64:44); }
- (void)tableView:(UITableView *)view didSelectRowAtIndexPath:(NSIndexPath *)index;
{
  NSDictionary *row=[[[self rowAtIndex:index] retain] autorelease]; [view deselectRowAtIndexPath:index animated:YES];
  if(mode_==RDLPScreenQueue) { [revealJobID_ release]; revealJobID_=[[[row objectForKey:@"job"] objectForKey:@"id"] copy]; }
  if([self enabled:[row objectForKey:@"action"]]) [self performRow:row];
}
- (void)queueAction:(UIButton *)sender;
{
  /* Use stable identity even if a progress refresh has moved/detached the row. */
  NSDictionary *job=[model_ currentJob:sender.accessibilityIdentifier]; if(!job) return;
  if([policy_ canCancel:job]) [self confirm:[NSDictionary dictionaryWithObjectsAndKeys:@"stop",@"operation",[job objectForKey:@"id"],@"job",nil] title:@"Stop download?" detail:@"Retry restarts this quality from the beginning." button:@"Stop"];
  else if([policy_ canRetry:job] || [policy_ canDownloadAgain:job]) { [library_ retryJob:[job objectForKey:@"id"]]; [self showJobInQueue:job]; }
}
- (void)pushMode:(RDLPScreen)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
{
  RDLPLibraryViewController *controller=[[RDLPLibraryViewController alloc] initWithLibrary:library_ mode:mode playlist:playlist video:video];
  [self.navigationController pushViewController:controller animated:YES]; [controller release];
}
- (void)showJobInQueue:(NSDictionary *)job;
{
  RDLPLibraryViewController *queue=nil;
  for(UIViewController *candidate in self.navigationController.viewControllers) if([candidate isKindOfClass:[RDLPLibraryViewController class]] && ((RDLPLibraryViewController *)candidate)->mode_==RDLPScreenQueue) { queue=(RDLPLibraryViewController *)candidate; break; }
  if(!queue) { [self pushMode:RDLPScreenQueue playlist:nil video:nil]; queue=(RDLPLibraryViewController *)self.navigationController.topViewController; }
  else [self.navigationController popToViewController:queue animated:YES];
  [queue->revealJobID_ release]; queue->revealJobID_=[[job objectForKey:@"id"] copy];
  [queue->revealGroup_ release]; queue->revealGroup_=nil;
  [queue refresh:nil];
}
@end
