#import "RDLPPlaylistsViewController.h"
#import "RDLPLibraryViewController.h"
#import "RDLPQueueViewController.h"
#import "RDLPPlaylistViewController.h"
#import "RDLPDownloadsViewController.h"
#import "RDLPSettingsViewController.h"
#import "RDLPUIKit.h"
#import "RDLPDownloadedPlayerViewController.h"

@implementation RDLPPlaylistsViewController
- (id)initWithLibrary:(RDLPLibrary *)library;
{
  self=[super initWithStyle:UITableViewStylePlain]; if(!self) return nil;
  library_=[library retain]; model_=[[RDLPLibrarySections alloc] initWithLibrary:library];
  [self setTitle:NSLocalizedString(@"Playlists", nil)];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RDLPLibraryDidChange object:library];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshStatus:) name:RDLPPlaybackVisibilityDidChangeNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshStatus:) name:RDLPLibraryStatusDidChange object:library_];
  return self;
}
- (void)dealloc;
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [alert_ setDelegate:nil]; [alert_ dismissWithClickedButtonIndex:0 animated:NO];
  [playlistActions_ setDelegate:nil]; [playlistActions_ dismissWithClickedButtonIndex:[playlistActions_ cancelButtonIndex] animated:NO];
  [alert_ release]; [playlistActions_ release]; [request_ release]; [alertActions_ release];
  [swipePlaylistID_ release]; [sections_ release]; [statusBar_ release]; [model_ release]; [library_ release]; [super dealloc];
}
- (void)viewDidLoad;
{
  [super viewDidLoad]; [RDLPUIKit configureContentEdges:self];
  [[self navigationItem] setLeftBarButtonItem:[[[UIBarButtonItem alloc] initWithImage:[RDLPUIKit settingsIcon] style:UIBarButtonItemStylePlain target:self action:@selector(settings:)] autorelease]];
  [[[self navigationItem] leftBarButtonItem] setAccessibilityLabel:NSLocalizedString(@"Settings", nil)];
  [[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc] initWithImage:[RDLPUIKit plusIcon] style:UIBarButtonItemStylePlain target:self action:@selector(showPlaylistActions:)] autorelease]];
  [[[self navigationItem] rightBarButtonItem] setAccessibilityLabel:NSLocalizedString(@"Library Actions", nil)];
  statusBar_=[[RDLPStatusBarView alloc] initWithFrame:CGRectZero];
  [statusBar_ setMaximumWidth:MAX(0,[[self view] bounds].size.width-112)];
  [self setToolbarItems:[RDLPUIKit statusToolbarItems:statusBar_ target:self queueAction:@selector(queue:)]];
  [self refresh:nil];
}
- (void)viewWillAppear:(BOOL)animated;
{ [super viewWillAppear:animated]; [[self navigationController] setToolbarHidden:NO animated:animated]; [self refresh:nil]; }
- (void)viewWillDisappear:(BOOL)animated;
{
  [[self tableView] setEditing:NO animated:NO];
  [swipePlaylistID_ release]; swipePlaylistID_=nil; [super viewWillDisappear:animated];
}
- (void)viewDidLayoutSubviews;
{ [super viewDidLayoutSubviews]; [statusBar_ setMaximumWidth:MAX(0,[[self view] bounds].size.width-112)]; }
- (void)refresh:(id)sender;
{
  (void)sender; if(![self isViewLoaded]) return;
  /* Keep the row under UIKit's Delete confirmation stable during refreshes. */
  if(!swipePlaylistID_) {
    NSArray *sections=[model_ sectionsForScreen:RDLPScreenLibrary playlist:nil video:nil collapsed:nil];
    [sections_ release]; sections_=[sections copy];
  }
  [self refreshStatus:nil];
  if(!swipePlaylistID_) [[self tableView] reloadData];
}
- (void)reopenPlayer:(id)sender;
{ (void)sender; [RDLPUIKit reopenPlayer:self]; }
- (void)refreshStatus:(id)sender;
{
  (void)sender; if(![self isViewLoaded]) return;
  UIBarButtonItem *trailing=[[self toolbarItems] lastObject];
  BOOL showsPlayer=[trailing action]==@selector(reopenPlayer:);
  if(statusBar_ && showsPlayer!=[RDLPUIKit hasHiddenPlayback]) [self setToolbarItems:[RDLPUIKit statusToolbarItems:statusBar_ target:self queueAction:@selector(queue:)]];
  [statusBar_ setStatus:[library_ status] progress:[library_ activityProgress] busy:[library_ isBusy]];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table;
{ (void)table; return (NSInteger)[sections_ count]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{ (void)table; return (NSInteger)[[[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"rows"] count]; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section;
{ (void)table; return [[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"title"]; }
- (NSDictionary *)rowAtIndex:(NSIndexPath *)index;
{ return [[[sections_ objectAtIndex:(NSUInteger)[index section]] objectForKey:@"rows"] objectAtIndex:(NSUInteger)[index row]]; }
- (BOOL)canDeletePlaylist:(NSDictionary *)playlist;
{
  return !alert_ && !playlistActions_ && ![self presentedViewController] &&
    ![[self navigationController] presentedViewController] && [model_ canRemovePlaylist:playlist];
}
- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)index;
{
  (void)table;
  NSArray *rows=[[sections_ objectAtIndex:(NSUInteger)[index section]] objectForKey:@"rows"];
  /* Avoid materializing every offscreen row when UIKit asks for editability. */
  NSDictionary *row=[rows respondsToSelector:@selector(cachedObjectAtIndex:)]?
    [(RDLPLibraryRows *)rows cachedObjectAtIndex:(NSUInteger)[index row]]:[rows objectAtIndex:(NSUInteger)[index row]];
  return [self canDeletePlaylist:[row objectForKey:@"playlist"]];
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)index;
{ return [self tableView:table canEditRowAtIndexPath:index]?UITableViewCellEditingStyleDelete:UITableViewCellEditingStyleNone; }
- (void)tableView:(UITableView *)table willBeginEditingRowAtIndexPath:(NSIndexPath *)index;
{
  (void)table; [swipePlaylistID_ release];
  swipePlaylistID_=[[[[self rowAtIndex:index] objectForKey:@"playlist"] objectForKey:@"id"] copy];
}
- (void)tableView:(UITableView *)table didEndEditingRowAtIndexPath:(NSIndexPath *)index;
{
  (void)table; (void)index;
  [swipePlaylistID_ release]; swipePlaylistID_=nil;
  /* Reload after UIKit finishes dismissing its confirmation controls (iOS 8). */
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refresh:) object:nil];
  [self performSelector:@selector(refresh:) withObject:nil afterDelay:0];
}
- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)index;
{
  (void)table; if(style!=UITableViewCellEditingStyleDelete) return;
  NSString *key=[(swipePlaylistID_?swipePlaylistID_:[[[self rowAtIndex:index] objectForKey:@"playlist"] objectForKey:@"id"]) copy];
  [self performSelector:@selector(deletePlaylist:) withObject:key afterDelay:0]; [key release];
}
- (void)deletePlaylist:(NSString *)key;
{
  [[self tableView] setEditing:NO animated:YES];
  [swipePlaylistID_ release]; swipePlaylistID_=nil;
  /* Delete confirms local removal; recheck the captured identity and blockers. */
  NSDictionary *playlist=[library_ playlistForID:key];
  if([self canDeletePlaylist:playlist]) [library_ removePlaylist:playlist];
  [self refresh:nil];
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index;
{
  UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"playlist"];
  if(!cell) cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"playlist"] autorelease];
  NSDictionary *row=[self rowAtIndex:index];
  [[cell textLabel] setText:[row objectForKey:@"title"]]; [[cell detailTextLabel] setText:[row objectForKey:@"detail"]];
  [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator]; return cell;
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
  UIViewController *controller=[action isEqualToString:@"playlist"]?
    (UIViewController *)[[[RDLPPlaylistViewController alloc] initWithLibrary:library_ playlist:[row objectForKey:@"playlist"]] autorelease]:
    [[[RDLPDownloadsViewController alloc] initWithLibrary:library_] autorelease];
  [[self navigationController] pushViewController:controller animated:YES];
}
- (BOOL)enabled:(NSString *)action;
{
  if([action isEqualToString:@"discover"]) return ![library_ isBusy] && ![library_ isDiscoveryPending];
  if([action isEqualToString:@"syncAll"]) return [library_ hasPlaylistsToSync];
  return ![action isEqualToString:@"removePlaylist"];
}
- (void)settings:(id)sender;
{
  (void)sender; if([[self navigationController] presentedViewController] || alert_ || playlistActions_) return;
  RDLPSettingsViewController *settings=[[[RDLPSettingsViewController alloc] initWithLibrary:library_] autorelease];
  UINavigationController *modal=[[[UINavigationController alloc] initWithRootViewController:settings] autorelease];
  [[self navigationController] presentViewController:modal animated:YES completion:nil];
}
- (void)queue:(id)sender;
{
  (void)sender; if([[self navigationController] presentedViewController] || alert_ || playlistActions_) return;
  RDLPQueueViewController *queue=[[[RDLPQueueViewController alloc] initWithLibrary:library_] autorelease];
  UINavigationController *modal=[[[UINavigationController alloc] initWithRootViewController:queue] autorelease];
  [[self navigationController] presentViewController:modal animated:YES completion:nil];
}
- (void)performConfirmed:(NSDictionary *)request;
{
  NSString *operation=[request objectForKey:@"operation"];
  if([operation isEqualToString:@"syncAll"]) {
    for(NSString *input in [request objectForKey:@"inputs"]) if(![library_ isSyncPendingForInput:input]) [library_ syncPlaylistInput:input];
  } else if([operation isEqualToString:@"discover"] && [self enabled:@"discover"]) {
    if([[library_ cookieStatus] isEqualToString:NSLocalizedString(@"Imported", nil)]) [library_ discoverPlaylists];
    else [self requestCookieImport:[self documentsCookiePath] discover:YES];
  } else if([operation isEqualToString:@"import"] && ![library_ isBusy]) {
    if([library_ importCookies:[request objectForKey:@"path"]] && [[request objectForKey:@"discover"] boolValue]) [library_ discoverPlaylists];
  }
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index;
{
  if(alert!=alert_) return;
  NSDictionary *request=[[request_ retain] autorelease];
  NSString *text=[alert alertViewStyle]==UIAlertViewStylePlainTextInput?[[[[alert textFieldAtIndex:0] text] copy] autorelease]:nil;
  [alert_ setDelegate:nil]; [alert_ release]; alert_=nil; [request_ release]; request_=nil; [alertActions_ release]; alertActions_=nil;
  if(index==0) return;
  if([[request objectForKey:@"operation"] isEqualToString:@"add"]) [library_ addPlaylistInput:text];
  else if([[request objectForKey:@"operation"] isEqualToString:@"addVideo"]) [library_ addVideoInput:text];
  else [self performConfirmed:request];
  [self refresh:nil];
}
- (void)showAlert:(NSString *)title detail:(NSString *)detail request:(NSDictionary *)request buttons:(NSArray *)buttons input:(NSString *)input;
{
  if(alert_) return;
  request_=[request copy]; alertActions_=[buttons copy];
  alert_=[[UIAlertView alloc] initWithTitle:title message:detail delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", nil) otherButtonTitles:nil];
  for(NSString *button in buttons) [alert_ addButtonWithTitle:button];
  if(input) {
    [alert_ setAlertViewStyle:UIAlertViewStylePlainTextInput];
    UITextField *field=[alert_ textFieldAtIndex:0]; [field setText:input]; [field setAutocapitalizationType:UITextAutocapitalizationTypeNone]; [field setAutocorrectionType:UITextAutocorrectionTypeNo];
  }
  [alert_ show];
}
- (void)confirm:(NSDictionary *)request title:(NSString *)title detail:(NSString *)detail button:(NSString *)button;
{ [self showAlert:title detail:detail request:request buttons:[NSArray arrayWithObject:button] input:nil]; }
- (NSString *)documentsCookiePath;
{ return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0] stringByAppendingPathComponent:@"cookies.txt"]; }
- (BOOL)requestCookieImport:(NSString *)path discover:(BOOL)discover;
{
  if([library_ isBusy] || alert_) { [RDLPUIKit showMessage:NSLocalizedString(@"Finish the current operation or dialog before importing cookies.", nil)]; return NO; }
  NSDictionary *request=[NSDictionary dictionaryWithObjectsAndKeys:@"import",@"operation",path,@"path",[NSNumber numberWithBool:discover],@"discover",nil];
  if(![[library_ cookieStatus] isEqualToString:NSLocalizedString(@"Not Imported", nil)])
    [self confirm:request title:discover?NSLocalizedString(@"Replace cookies and sync playlists?", nil):NSLocalizedString(@"Replace imported cookies?", nil) detail:NSLocalizedString(@"Replace the working cookie copy. Your original export is retained.", nil) button:discover?NSLocalizedString(@"Replace and Sync", nil):NSLocalizedString(@"Replace", nil)];
  else if([[NSFileManager defaultManager] fileExistsAtPath:path]) [self performConfirmed:request];
  else { [RDLPUIKit showMessage:NSLocalizedString(@"Copy cookies.txt into RetroDLP with iTunes File Sharing, or open your exported text file in RetroDLP. Then use Sync My Playlists again.", nil)]; return NO; }
  return YES;
}
/* UIActionSheet keeps the playlist menu available on iOS 5 and 6. Dispatch
 * after dismissal so the next alert or pushed screen does not overlap it. */
- (void)showPlaylistActions:(id)sender;
{
  (void)sender; if(playlistActions_ || alert_) return;
  playlistActions_=[[UIActionSheet alloc] initWithTitle:nil delegate:self
    cancelButtonTitle:NSLocalizedString(@"Cancel", nil) destructiveButtonTitle:nil
    otherButtonTitles:NSLocalizedString(@"Add Video…", nil),NSLocalizedString(@"Add Playlist…", nil),NSLocalizedString(@"Sync Added Playlists…", nil),NSLocalizedString(@"Sync My Playlists…", nil),nil];
  [playlistActions_ showFromBarButtonItem:[[self navigationItem] rightBarButtonItem] animated:YES];
}
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index;
{
  if(sheet!=playlistActions_) return;
  BOOL cancelled=index==[sheet cancelButtonIndex] || index<0;
  [playlistActions_ setDelegate:nil]; [playlistActions_ release]; playlistActions_=nil;
  if(cancelled) return;
  switch(index) {
    case 0: [self addVideo:nil]; break;
    case 1: [self add:nil]; break;
    case 2: [self syncAll:nil]; break;
    case 3: [self discover:nil]; break;
    default: break;
  }
}
- (void)add:(id)sender;
{ (void)sender; [self showAlert:NSLocalizedString(@"Add Playlist", nil) detail:NSLocalizedString(@"YouTube playlist URL or ID", nil) request:[NSDictionary dictionaryWithObject:@"add" forKey:@"operation"] buttons:[NSArray arrayWithObject:NSLocalizedString(@"Sync", nil)] input:@""]; }
- (void)addVideo:(id)sender;
{ (void)sender; [self showAlert:NSLocalizedString(@"Add Video", nil) detail:NSLocalizedString(@"YouTube video URL or ID", nil) request:[NSDictionary dictionaryWithObject:@"addVideo" forKey:@"operation"] buttons:[NSArray arrayWithObject:NSLocalizedString(@"Add", nil)] input:@""]; }
- (void)discover:(id)sender;
{ (void)sender; if([self enabled:@"discover"]) [self confirm:[NSDictionary dictionaryWithObject:@"discover" forKey:@"operation"] title:NSLocalizedString(@"Sync My Playlists?", nil) detail:NSLocalizedString(@"Refresh your account playlists and their videos. Playlists no longer in your account are removed locally; downloads and unfinished jobs are retained. Cookies are required. No videos will be downloaded.", nil) button:NSLocalizedString(@"Sync My Playlists", nil)]; }
- (void)syncAll:(id)sender;
{
  (void)sender; NSMutableArray *inputs=[NSMutableArray array];
  for(NSDictionary *playlist in [library_ playlistsFromAccount:NO]) if([RDLPLibrary canSyncPlaylist:playlist] && ![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]]) [inputs addObject:[playlist objectForKey:@"service_id"]];
  if([inputs count]) [self confirm:[NSDictionary dictionaryWithObjectsAndKeys:@"syncAll",@"operation",inputs,@"inputs",nil] title:NSLocalizedString(@"Sync Added Playlists?", nil) detail:NSLocalizedString(@"Refresh your manually added playlists and their videos from YouTube. Local downloads are retained. No videos will be downloaded.", nil) button:NSLocalizedString(@"Sync Added Playlists", nil)];
}
@end
