#import "LibraryController.h"
#import "XPUIKit.h"
#import <AIFontAwesome.h>
static UIBarButtonItem *item(NSString *title,id target,SEL action) {
  return [[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:target action:action] autorelease];
}
@implementation LibraryController
- (id)initWithLibrary:(RDLPLibrary *)library mode:(int)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
{
  self=[super initWithStyle:UITableViewStyleGrouped]; if(!self) return nil;
  library_=[library retain]; mode_=mode; playlist_=[playlist copy]; video_=[video copy];
  NSString *saved=[RDLPLibrary preferredFormat];
  format_=[(saved?saved:@"18") copy];
  self.title=mode==0?@"RetroDLP":(mode==1?[playlist objectForKey:@"title"]:(mode==2?@"Download Queue":(mode==3?@"Downloads":(mode==4?@"Settings":@"Video"))));
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RDLPLibraryDidChange object:library_]; return self;
}
- (void)dealloc;
{ [[NSNotificationCenter defaultCenter] removeObserver:self]; [library_ release]; [playlist_ release]; [video_ release]; [rows_ release]; [status_ release]; [format_ release]; [pendingRemoval_ release]; [super dealloc]; }
- (void)viewDidLoad;
{
  [super viewDidLoad];
  status_=[[UILabel alloc] initWithFrame:CGRectMake(12,0,296,65)]; status_.numberOfLines=3;
  status_.font=[UIFont systemFontOfSize:12]; status_.backgroundColor=[UIColor clearColor];
  status_.autoresizingMask=UIViewAutoresizingFlexibleWidth; self.tableView.tableFooterView=status_;
  if(mode_==0) {
    self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add:)] autorelease];
    self.toolbarItems=[NSArray arrayWithObjects:item(@"My Playlists",self,@selector(discover:)),item(@"Sync All",self,@selector(syncAll:)),item(@"Queue",self,@selector(queue:)),nil];
  } else if(mode_==1) {
    self.toolbarItems=[NSArray arrayWithObjects:item(@"Sync",self,@selector(sync:)),item(@"Download All",self,@selector(downloadAll:)),item(@"Remove",self,@selector(removePlaylist:)),nil];
    self.navigationItem.rightBarButtonItem=item(@"Quality",self,@selector(settings:));
  } else if(mode_==2 || mode_==3) {
    self.navigationItem.rightBarButtonItem=item(@"Pause/Resume",self,@selector(pause:));
  }
  [self refresh:nil];
}
- (void)viewWillAppear:(BOOL)animated;
{
  [super viewWillAppear:animated];
  [self.navigationController setToolbarHidden:![self.toolbarItems count] animated:animated];
  NSString *saved=[RDLPLibrary preferredFormat];
  if(saved) { [format_ release]; format_=[saved copy]; }
  [self refresh:nil];
}
- (void)refresh:(id)sender;
{
  (void)sender; if(![self isViewLoaded]) return;
  [rows_ release];
  if(mode_==0) rows_=[[library_ playlists] copy];
  else if(mode_==1) rows_=[[library_ entriesForPlaylist:[playlist_ objectForKey:@"id"]] copy];
  else if(mode_==2 || mode_==3 || mode_==5) {
    NSArray *jobs=[library_ jobsForPlaylist:mode_==5?[playlist_ objectForKey:@"id"]:nil completedOnly:mode_==3];
    if(mode_==5) {
      NSMutableArray *selected=[NSMutableArray array]; unsigned int i;
      for(i=0;i<[jobs count];++i) if([[[jobs objectAtIndex:i] objectForKey:@"video_id"] isEqualToString:[video_ objectForKey:@"video_id"]]) [selected addObject:[jobs objectAtIndex:i]];
      rows_=[selected copy];
    } else rows_=[jobs copy];
  } else rows_=[[NSArray alloc] init];
  status_.text=[library_ status]; [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)view;
{ (void)view; return mode_==0 || mode_==4 || mode_==5?2:1; }
- (NSInteger)tableView:(UITableView *)view numberOfRowsInSection:(NSInteger)section;
{
  (void)view;
  if(mode_==0 && section==0) return 3;
  if(mode_==4) return section==0?4:2;
  if(mode_==5 && section==0) return 1;
  return (NSInteger)[rows_ count];
}
- (NSString *)tableView:(UITableView *)view titleForHeaderInSection:(NSInteger)section;
{
  (void)view;
  if(mode_==0) return section==0?@"Library":@"Playlists — tap + to add a URL";
  if(mode_==4) return section==0?@"Download quality":@"Account cookies";
  if(mode_==5) return section==0?[video_ objectForKey:@"title"]:@"Downloads — tap for actions";
  return mode_==1?@"Videos — tap to download or play":@"Tap a job for playback, retry, or removal";
}
- (NSString *)tableView:(UITableView *)view titleForFooterInSection:(NSInteger)section;
{
  (void)view;
  if(mode_==4 && section==1) return @"Copy an exported Netscape cookies.txt file into RetroDLP using iTunes File Sharing, then Import. You can also open a text file in RetroDLP from another app. Import copies the file; the original remains in Documents.";
  if(mode_==4 && section==0) return @"360p = 18; 720p = 136+140; 1080p = 137+140. Unsupported qualities fail explicitly. Downloads run while RetroDLP is active; backgrounding pauses the queue.";
  return nil;
}
- (UITableViewCell *)tableView:(UITableView *)view cellForRowAtIndexPath:(NSIndexPath *)index;
{
  UITableViewCell *cell=[view dequeueReusableCellWithIdentifier:@"row"];
  if(!cell) cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"] autorelease];
  cell.textLabel.numberOfLines=2; cell.detailTextLabel.numberOfLines=2; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
  cell.detailTextLabel.text=@""; cell.imageView.image=nil;
  if(mode_==0 && index.section==0) {
    cell.textLabel.text=[[NSArray arrayWithObjects:@"Download Queue",@"All Downloads",@"Settings",nil] objectAtIndex:(NSUInteger)index.row];
    cell.textLabel.font=[UIFont boldSystemFontOfSize:17];
  } else if(mode_==4) {
    if(index.section==0) {
      NSArray *titles=[RDLPLibrary qualityTitles];
      NSArray *formats=[RDLPLibrary qualityFormats];
      cell.textLabel.text=[titles objectAtIndex:(NSUInteger)index.row];
      BOOL selected=index.row<3?[format_ isEqualToString:[formats objectAtIndex:(NSUInteger)index.row]]:![formats containsObject:format_];
      cell.accessoryType=selected?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
      if(index.row==3) cell.detailTextLabel.text= format_;
    } else { cell.textLabel.text=index.row==0?@"Import Documents/cookies.txt":@"Clear Cookies"; }
  } else if(mode_==5 && index.section==0) {
    cell.textLabel.text=@"Download this video"; cell.detailTextLabel.text=[NSString stringWithFormat:@"Requested format: %@",format_];
  } else {
    NSDictionary *row=[rows_ objectAtIndex:(NSUInteger)index.row]; cell.textLabel.text=[row objectForKey:@"title"];
    if(mode_==0) cell.detailTextLabel.text=[[row objectForKey:@"synced_at"] length]?[NSString stringWithFormat:@"%@ entries • saved offline",[row objectForKey:@"count"]]:@"Not synced — open and tap Sync";
    else cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@ %@",[row objectForKey:@"state"],[row objectForKey:mode_==1?@"quality":@"format"],([row objectForKey:@"error"]?[row objectForKey:@"error"]:@"")];
  }
  return cell;
}
- (CGFloat)tableView:(UITableView *)view heightForRowAtIndexPath:(NSIndexPath *)index;
{ (void)view; (void)index; return 76; }
- (void)pushMode:(int)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
{
  LibraryController *controller=[[LibraryController alloc] initWithLibrary:library_ mode:mode playlist:playlist video:video];
  [self.navigationController pushViewController:controller animated:YES]; [controller release];
}
- (void)tableView:(UITableView *)view didSelectRowAtIndexPath:(NSIndexPath *)index;
{
  [view deselectRowAtIndexPath:index animated:YES];
  if(mode_==0) {
    if(index.section==0) [self pushMode:index.row==0?2:(index.row==1?3:4) playlist:nil video:nil];
    else [self pushMode:1 playlist:[rows_ objectAtIndex:(NSUInteger)index.row] video:nil];
  } else if(mode_==1) [self pushMode:5 playlist:playlist_ video:[rows_ objectAtIndex:(NSUInteger)index.row]];
  else if(mode_==4) {
    if(index.section==0) {
      if(index.row==3) {
        UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"Exact format" message:@"Example: 136+140 or 137+140/136+140" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Save",nil];
        alert.tag=2; alert.alertViewStyle=UIAlertViewStylePlainTextInput; [alert textFieldAtIndex:0].text=format_; [alert show]; [alert release];
      } else [self saveFormat:[[RDLPLibrary qualityFormats] objectAtIndex:(NSUInteger)index.row]];
    } else if(index.row==0) {
      NSString *documents=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0];
      [library_ importCookies:[documents stringByAppendingPathComponent:@"cookies.txt"]]; RDShowMessage([library_ status]);
    } else { [library_ clearCookies]; RDShowMessage([library_ status]); }
  } else if(mode_==5 && index.section==0) {
    [library_ enqueuePlaylist:[playlist_ objectForKey:@"id"] video:[video_ objectForKey:@"video_id"] format:format_];
  } else {
    [pendingRemoval_ release]; pendingRemoval_=[[rows_ objectAtIndex:(NSUInteger)index.row] copy];
    NSString *details=[NSString stringWithFormat:@"%@\n%@\nFormat: %@",[pendingRemoval_ objectForKey:@"state"],[pendingRemoval_ objectForKey:@"error"],[pendingRemoval_ objectForKey:@"format"]];
    UIAlertView *alert=[[UIAlertView alloc] initWithTitle:[pendingRemoval_ objectForKey:@"title"] message:details delegate:self cancelButtonTitle:@"Close" otherButtonTitles:@"Play",@"Retry",@"Cancel Download",@"Remove File…",nil];
    alert.tag=3; [alert show]; [alert release];
  }
}
- (void)saveFormat:(NSString *)format;
{
  if(![RDLPLibrary savePreferredFormat:format]) { RDShowMessage(@"Enter an exact format such as 18 or 136+140."); return; }
  [format_ release]; format_=[format copy]; [self refresh:nil];
}
- (void)add:(id)sender;
{
  (void)sender; UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"Add Playlist" message:@"YouTube playlist URL or ID" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Sync",nil];
  alert.tag=1; alert.alertViewStyle=UIAlertViewStylePlainTextInput; [alert textFieldAtIndex:0].autocapitalizationType=UITextAutocapitalizationTypeNone; [alert show]; [alert release];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index;
{
  if(index==0) return;
  if(alert.tag==1) [library_ syncPlaylistInput:[alert textFieldAtIndex:0].text];
  else if(alert.tag==2) [self saveFormat:[alert textFieldAtIndex:0].text];
  else if(alert.tag==3) {
    if(index==1) {
      if([[pendingRemoval_ objectForKey:@"state"] isEqualToString:@"complete"]) RDPresentPlayer(self,[library_ fileForJob:pendingRemoval_]);
      else RDShowMessage(@"Finish the download before playing this video.");
    } else if(index==2) [library_ retryJob:[pendingRemoval_ objectForKey:@"id"]];
    else if(index==3) [library_ cancelJob:[pendingRemoval_ objectForKey:@"id"]];
    else {
      UIAlertView *confirmation=[[UIAlertView alloc] initWithTitle:@"Remove downloaded file?" message:@"Playlist membership is retained." delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Remove",nil];
      confirmation.tag=4; [confirmation show]; [confirmation release];
    }
  } else if(alert.tag==4) [library_ removeDownload:pendingRemoval_];
  else if(alert.tag==5) { [library_ removePlaylist:playlist_]; RDShowMessage([library_ status]); }
}
- (void)discover:(id)sender; { (void)sender; [library_ discoverPlaylists]; }
- (void)syncAll:(id)sender; { (void)sender; [library_ syncAll]; }
- (void)sync:(id)sender; { (void)sender; [library_ syncPlaylistInput:[playlist_ objectForKey:@"service_id"]]; }
- (void)downloadAll:(id)sender; { (void)sender; [library_ enqueuePlaylist:[playlist_ objectForKey:@"id"] video:nil format:format_]; }
- (void)queue:(id)sender; { (void)sender; [self pushMode:2 playlist:nil video:nil]; }
- (void)settings:(id)sender; { (void)sender; [self pushMode:4 playlist:nil video:nil]; }
- (void)pause:(id)sender; { (void)sender; [library_ setPaused:![library_ isPaused]]; }
- (void)removePlaylist:(id)sender;
{
  (void)sender; UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"Remove this playlist?" message:@"First cancel its queued jobs and remove its downloaded files." delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Remove",nil];
  alert.tag=5; [alert show]; [alert release];
}
@end
