#import "RDLPPlaylistsViewController.h"
#import "RDLPLibraryViewController.h"
#import "RDLPSettingsViewController.h"
#import "RDLPUIKit.h"

@implementation RDLPPlaylistsViewController
- (id)initWithLibrary:(RDLPLibrary *)library;
{
  self=[super initWithStyle:UITableViewStylePlain]; if(!self) return nil;
  library_=[library retain]; model_=[[RDLPLibrarySections alloc] initWithLibrary:library];
  self.title=@"Playlists";
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RDLPLibraryDidChange object:library];
  return self;
}
- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  alert_.delegate=nil; [alert_ dismissWithClickedButtonIndex:0 animated:NO];
  playlistActions_.delegate=nil; [playlistActions_ dismissWithClickedButtonIndex:playlistActions_.cancelButtonIndex animated:NO];
  [alert_ release]; [playlistActions_ release]; [request_ release]; [alertActions_ release];
  [sections_ release]; [statusBar_ release]; [model_ release]; [library_ release]; [super dealloc];
}
- (void)viewDidLoad;
{
  [super viewDidLoad]; [RDLPUIKit configureContentEdges:self];
  self.navigationItem.leftBarButtonItem=[[[UIBarButtonItem alloc] initWithImage:[RDLPUIKit settingsIcon] style:UIBarButtonItemStylePlain target:self action:@selector(settings:)] autorelease];
  self.navigationItem.leftBarButtonItem.accessibilityLabel=@"Settings";
  self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithImage:[RDLPUIKit plusIcon] style:UIBarButtonItemStylePlain target:self action:@selector(showPlaylistActions:)] autorelease];
  self.navigationItem.rightBarButtonItem.accessibilityLabel=@"Playlist Actions";
  statusBar_=[[RDLPStatusBarView alloc] initWithFrame:CGRectZero];
  statusBar_.maximumWidth=MAX(0,self.view.bounds.size.width-80);
  UIBarButtonItem *left=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
  UIBarButtonItem *right=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
  UIBarButtonItem *status=[[[UIBarButtonItem alloc] initWithCustomView:statusBar_] autorelease];
  UIBarButtonItem *queue=[[[UIBarButtonItem alloc] initWithImage:[RDLPUIKit queueToolbarIcon] style:UIBarButtonItemStyleBordered target:self action:@selector(queue:)] autorelease];
  queue.accessibilityLabel=@"Download Queue";
  self.toolbarItems=[NSArray arrayWithObjects:left,status,right,queue,nil];
  [self refresh:nil];
}
- (void)viewWillAppear:(BOOL)animated;
{ [super viewWillAppear:animated]; [self.navigationController setToolbarHidden:NO animated:animated]; [self refresh:nil]; }
- (void)viewDidLayoutSubviews;
{ [super viewDidLayoutSubviews]; statusBar_.maximumWidth=MAX(0,self.view.bounds.size.width-80); }
- (void)refresh:(id)sender;
{
  (void)sender; if(![self isViewLoaded]) return;
  NSArray *sections=[model_ sectionsForScreen:RDLPScreenLibrary playlist:nil video:nil collapsed:nil];
  [sections_ release]; sections_=[sections copy];
  [statusBar_ setStatus:[library_ status] progress:[library_ queueProgress] busy:[library_ isBusy]];
  [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table;
{ (void)table; return (NSInteger)[sections_ count]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{ (void)table; return (NSInteger)[[[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"rows"] count]; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section;
{ (void)table; return [[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"title"]; }
- (NSDictionary *)rowAtIndex:(NSIndexPath *)index;
{ return [[[sections_ objectAtIndex:(NSUInteger)index.section] objectForKey:@"rows"] objectAtIndex:(NSUInteger)index.row]; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index;
{
  UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"playlist"];
  if(!cell) cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"playlist"] autorelease];
  NSDictionary *row=[self rowAtIndex:index];
  cell.textLabel.text=[row objectForKey:@"title"]; cell.detailTextLabel.text=[row objectForKey:@"detail"];
  cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index;
{
  NSDictionary *row=[[[self rowAtIndex:index] retain] autorelease];
  [table deselectRowAtIndexPath:index animated:YES]; [self performRow:row];
}
- (void)performRow:(NSDictionary *)row;
{
  NSString *action=[row objectForKey:@"action"];
  if(![action isEqualToString:@"playlist"] && ![action isEqualToString:@"downloads"]) return;
  RDLPLibraryViewController *controller=[[[RDLPLibraryViewController alloc] initWithLibrary:library_ mode:[action isEqualToString:@"playlist"]?RDLPScreenPlaylist:RDLPScreenDownloads playlist:[row objectForKey:@"playlist"] video:nil] autorelease];
  [self.navigationController pushViewController:controller animated:YES];
}
- (BOOL)enabled:(NSString *)action;
{
  if([action isEqualToString:@"discover"]) return ![library_ isBusy] && ![library_ isDiscoveryPending];
  if([action isEqualToString:@"syncAll"]) {
    for(NSDictionary *playlist in [library_ playlists]) if(![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]]) return YES;
    return NO;
  }
  return ![action isEqualToString:@"removePlaylist"];
}
- (void)settings:(id)sender;
{
  (void)sender; if(self.navigationController.presentedViewController || alert_ || playlistActions_) return;
  RDLPSettingsViewController *settings=[[[RDLPSettingsViewController alloc] initWithLibrary:library_] autorelease];
  UINavigationController *modal=[[[UINavigationController alloc] initWithRootViewController:settings] autorelease];
  [self.navigationController presentViewController:modal animated:YES completion:nil];
}
- (void)queue:(id)sender;
{
  (void)sender; if(self.navigationController.presentedViewController || alert_ || playlistActions_) return;
  RDLPLibraryViewController *queue=[[[RDLPLibraryViewController alloc] initWithLibrary:library_ mode:RDLPScreenQueue playlist:nil video:nil] autorelease];
  queue.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:queue action:@selector(dismissQueue:)] autorelease];
  UINavigationController *modal=[[[UINavigationController alloc] initWithRootViewController:queue] autorelease];
  [self.navigationController presentViewController:modal animated:YES completion:nil];
}
- (void)performConfirmed:(NSDictionary *)request;
{
  NSString *operation=[request objectForKey:@"operation"];
  if([operation isEqualToString:@"syncAll"]) {
    for(NSString *input in [request objectForKey:@"inputs"]) if(![library_ isSyncPendingForInput:input]) [library_ syncPlaylistInput:input];
  } else if([operation isEqualToString:@"discover"] && [self enabled:@"discover"]) {
    if([[library_ cookieStatus] isEqualToString:@"Imported"]) [library_ discoverPlaylists];
    else [self requestCookieImport:[self documentsCookiePath] discover:YES];
  } else if([operation isEqualToString:@"import"] && ![library_ isBusy]) {
    if([library_ importCookies:[request objectForKey:@"path"]] && [[request objectForKey:@"discover"] boolValue]) [library_ discoverPlaylists];
    [RDLPUIKit showMessage:[library_ status]];
  }
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index;
{
  if(alert!=alert_) return;
  NSDictionary *request=[[request_ retain] autorelease];
  NSString *text=alert.alertViewStyle==UIAlertViewStylePlainTextInput?[[[alert textFieldAtIndex:0].text copy] autorelease]:nil;
  alert_.delegate=nil; [alert_ release]; alert_=nil; [request_ release]; request_=nil; [alertActions_ release]; alertActions_=nil;
  if(index==0) return;
  if([[request objectForKey:@"operation"] isEqualToString:@"add"]) [library_ syncPlaylistInput:text];
  else [self performConfirmed:request];
  [self refresh:nil];
}
- (void)showAlert:(NSString *)title detail:(NSString *)detail request:(NSDictionary *)request buttons:(NSArray *)buttons input:(NSString *)input;
{
  if(alert_) return;
  request_=[request copy]; alertActions_=[buttons copy];
  alert_=[[UIAlertView alloc] initWithTitle:title message:detail delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:nil];
  for(NSString *button in buttons) [alert_ addButtonWithTitle:button];
  if(input) {
    alert_.alertViewStyle=UIAlertViewStylePlainTextInput;
    UITextField *field=[alert_ textFieldAtIndex:0]; field.text=input; field.autocapitalizationType=UITextAutocapitalizationTypeNone; field.autocorrectionType=UITextAutocorrectionTypeNo;
  }
  [alert_ show];
}
- (void)confirm:(NSDictionary *)request title:(NSString *)title detail:(NSString *)detail button:(NSString *)button;
{ [self showAlert:title detail:detail request:request buttons:[NSArray arrayWithObject:button] input:nil]; }
- (NSString *)documentsCookiePath;
{ return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0] stringByAppendingPathComponent:@"cookies.txt"]; }
- (BOOL)requestCookieImport:(NSString *)path discover:(BOOL)discover;
{
  if([library_ isBusy] || alert_) { [RDLPUIKit showMessage:@"Finish the current operation or dialog before importing cookies."]; return NO; }
  NSDictionary *request=[NSDictionary dictionaryWithObjectsAndKeys:@"import",@"operation",path,@"path",[NSNumber numberWithBool:discover],@"discover",nil];
  if(![[library_ cookieStatus] isEqualToString:@"Not Imported"])
    [self confirm:request title:discover?@"Replace cookies and load playlists?":@"Replace imported cookies?" detail:@"Replace the working cookie copy. Your original export is retained." button:discover?@"Replace and Load":@"Replace"];
  else if([[NSFileManager defaultManager] fileExistsAtPath:path]) [self performConfirmed:request];
  else { [RDLPUIKit showMessage:@"Copy cookies.txt into RetroDLP with iTunes File Sharing, or open your exported text file in RetroDLP. Then use Load My Playlists again."]; return NO; }
  return YES;
}
/* UIActionSheet keeps the playlist menu available on iOS 5 and 6. Dispatch
 * after dismissal so the next alert or pushed screen does not overlap it. */
- (void)showPlaylistActions:(id)sender;
{
  (void)sender; if(playlistActions_ || alert_) return;
  playlistActions_=[[UIActionSheet alloc] initWithTitle:nil delegate:self
    cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil
    otherButtonTitles:@"Add Playlist…",@"Sync All Playlists…",@"Load My Playlists…",nil];
  [playlistActions_ showFromBarButtonItem:self.navigationItem.rightBarButtonItem animated:YES];
}
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index;
{
  if(sheet!=playlistActions_) return;
  BOOL cancelled=index==sheet.cancelButtonIndex || index<0;
  playlistActions_.delegate=nil; [playlistActions_ release]; playlistActions_=nil;
  if(cancelled) return;
  switch(index) {
    case 0: [self add:nil]; break;
    case 1: [self syncAll:nil]; break;
    case 2: [self discover:nil]; break;
    default: break;
  }
}
- (void)add:(id)sender;
{ (void)sender; [self showAlert:@"Add Playlist" detail:@"YouTube playlist URL or ID" request:[NSDictionary dictionaryWithObject:@"add" forKey:@"operation"] buttons:[NSArray arrayWithObject:@"Sync"] input:@""]; }
- (void)discover:(id)sender;
{ (void)sender; if([self enabled:@"discover"]) [self confirm:[NSDictionary dictionaryWithObject:@"discover" forKey:@"operation"] title:@"Load My Playlists?" detail:@"Discover your YouTube account playlists and save their metadata. Cookies are required. No videos will be downloaded." button:@"Load Playlists"]; }
- (void)syncAll:(id)sender;
{
  (void)sender; NSMutableArray *inputs=[NSMutableArray array];
  for(NSDictionary *playlist in [library_ playlists]) if(![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]]) [inputs addObject:[playlist objectForKey:@"service_id"]];
  if([inputs count]) [self confirm:[NSDictionary dictionaryWithObjectsAndKeys:@"syncAll",@"operation",inputs,@"inputs",nil] title:@"Sync all playlists?" detail:@"Refresh playlist metadata from YouTube. Local downloads are retained." button:@"Sync All"];
}
@end
