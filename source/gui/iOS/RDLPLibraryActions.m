#import "RDLPLibraryViewController.h"
#import "RDLPUIKit.h"
#import "RDLPSettingsViewController.h"

@implementation RDLPLibraryViewController (Actions)
- (BOOL)enabled:(NSString *)action;
{
  if([action isEqualToString:@"import"]) return ![library_ isBusy] && ![[library_ cookieStatus] isEqualToString:NSLocalizedString(@"Imported", nil)];
  if([action isEqualToString:@"clearCookies"]) return ![library_ isBusy] && ![[library_ cookieStatus] isEqualToString:NSLocalizedString(@"Not Imported", nil)];
  if([action isEqualToString:@"discover"]) return ![library_ isBusy] && ![library_ isDiscoveryPending];
  if([action isEqualToString:@"sync"]) return playlist_ && [RDLPLibrary canSyncPlaylist:playlist_] && ![library_ isSyncPendingForInput:[playlist_ objectForKey:@"service_id"]];
  if([action isEqualToString:@"syncAll"]) return [library_ hasPlaylistsToSync];
  if([action isEqualToString:@"removePlaylist"]) return [model_ canRemovePlaylist:playlist_];
  if([action isEqualToString:@"bulk"]) return [library_ hasMissingEntriesForPlaylist:[playlist_ objectForKey:@"id"] format:[RDLPLibrary preferredFormat]];
  if([action isEqualToString:@"delete"]) return ![library_ isBusy];
  return YES;
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
- (void)confirmJob:(NSDictionary *)job operation:(NSString *)operation;
{
  if([operation isEqualToString:@"delete"]?![policy_ canRemove:job]:![policy_ canCancel:job]) return;
  [self confirm:[NSDictionary dictionaryWithObjectsAndKeys:operation,@"operation",[job objectForKey:@"id"],@"job",nil]
    title:[NSString stringWithFormat:NSLocalizedString(@"%@ %@ — %@?", nil),[operation isEqualToString:@"delete"]?NSLocalizedString(@"Delete", nil):NSLocalizedString(@"Stop", nil),[job objectForKey:@"title"],[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]]]
    detail:[operation isEqualToString:@"delete"]?NSLocalizedString(@"Deletes this quality and its partial files. Other qualities and playlist membership are retained.", nil):NSLocalizedString(@"Retry restarts this quality from the beginning. Other queued downloads continue.", nil)
    button:[operation isEqualToString:@"delete"]?NSLocalizedString(@"Delete", nil):NSLocalizedString(@"Stop", nil)];
}
- (void)performRow:(NSDictionary *)row;
{
  NSString *action=[row objectForKey:@"action"]; NSDictionary *job=[model_ currentJob:[[row objectForKey:@"job"] objectForKey:@"id"]];
  if([action isEqualToString:@"playlist"]) [self pushMode:RDLPScreenPlaylist playlist:[row objectForKey:@"playlist"] video:nil];
  else if([action isEqualToString:@"video"]) [self pushMode:RDLPScreenVideo playlist:playlist_ video:[row objectForKey:@"video"]];
  else if([action isEqualToString:@"queue"]) [self queue:nil];
  else if([action isEqualToString:@"downloads"]) [self pushMode:RDLPScreenDownloads playlist:nil video:nil];
  else if([action isEqualToString:@"settings"]) [self settings:nil];
  else if([action isEqualToString:@"quality"]) { [RDLPLibrary savePreferredFormat:[row objectForKey:@"format"]]; [self refresh:nil]; }
  else if([action isEqualToString:@"custom"]) [self showAlert:NSLocalizedString(@"Custom Format", nil) detail:NSLocalizedString(@"Example: 18 or 136+140", nil) request:[NSDictionary dictionaryWithObject:@"quality" forKey:@"operation"] buttons:[NSArray arrayWithObject:NSLocalizedString(@"Save", nil)] input:[RDLPLibrary preferredFormat]];
  else if([action isEqualToString:@"download"]) {
    [self showJobInQueue:[self enqueue:[NSDictionary dictionaryWithObjectsAndKeys:[playlist_ objectForKey:@"id"],@"playlist",[video_ objectForKey:@"video_id"],@"video",[RDLPLibrary preferredFormat],@"format",nil] allowRetry:YES]];
  } else if([action isEqualToString:@"play"]) { if([policy_ playable:job]) [RDLPUIKit presentPlayer:self library:library_ job:job]; }
  else if([action isEqualToString:@"delete"]) [self confirmJob:job operation:@"delete"];
  else if([action isEqualToString:@"showQueue"]) [self showJobInQueue:job];
  else if([action isEqualToString:@"job"] && job) [self showAlert:[job objectForKey:@"title"] detail:[NSString stringWithFormat:NSLocalizedString(@"%@·%@\n%@", nil),[policy_ statusForJob:job],[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]],([job objectForKey:@"error"]?[job objectForKey:@"error"]:@"")] request:[NSDictionary dictionaryWithObjectsAndKeys:@"jobActions",@"operation",[job objectForKey:@"id"],@"job",nil] buttons:[model_ actionsForJob:job] input:nil];
  else if([action isEqualToString:@"import"]) { if([self enabled:@"import"]) [self requestCookieImport:[self documentsCookiePath] discover:NO]; }
  else if([action isEqualToString:@"clearCookies"]) [self confirm:[NSDictionary dictionaryWithObject:@"clearCookies" forKey:@"operation"] title:NSLocalizedString(@"Remove imported cookies?", nil) detail:NSLocalizedString(@"Only the app’s working copy is removed. Your original export is retained.", nil) button:NSLocalizedString(@"Remove", nil)];
  else if([action isEqualToString:@"guide"]) [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/yt-dlp/yt-dlp/wiki/Extractors"]];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index;
{
  if(alert!=alert_) return;
  NSDictionary *request=[[request_ retain] autorelease]; NSArray *actions=[[alertActions_ retain] autorelease];
  NSString *text=[alert alertViewStyle]==UIAlertViewStylePlainTextInput?[[[[alert textFieldAtIndex:0] text] copy] autorelease]:nil;
  [alert_ setDelegate:nil]; [alert_ release]; alert_=nil; [request_ release]; request_=nil; [alertActions_ release]; alertActions_=nil;
  if(index==0) return;
  NSString *op=[request objectForKey:@"operation"];
  if([op isEqualToString:@"add"]) [library_ addPlaylistInput:text];
  else if([op isEqualToString:@"addVideo"]) [library_ addVideoInput:text];
  else if([op isEqualToString:@"quality"]) {
    if(![RDLPLibrary savePreferredFormat:text]) [RDLPUIKit showMessage:NSLocalizedString(@"Enter an exact format such as 18 or 136+140.", nil)];
  } else if([op isEqualToString:@"jobActions"]) {
    NSDictionary *job=[model_ currentJob:[request objectForKey:@"job"]]; if(!job) return;
    NSString *action=[actions objectAtIndex:(NSUInteger)index-1];
    if([action isEqualToString:NSLocalizedString(@"Play", nil)] && [policy_ playable:job]) [RDLPUIKit presentPlayer:self library:library_ job:job];
    else if([action isEqualToString:NSLocalizedString(@"Download Video", nil)] && ([policy_ canRetry:job] || [policy_ canDownloadAgain:job])) { [library_ retryJob:[job objectForKey:@"id"]]; [self showJobInQueue:job]; }
    else if([action isEqualToString:NSLocalizedString(@"Stop Download…", nil)]) [self confirmJob:job operation:@"stop"];
    else if([action isEqualToString:NSLocalizedString(@"Delete Download…", nil)]) [self confirmJob:job operation:@"delete"];
    else if([action isEqualToString:NSLocalizedString(@"Show in Queue", nil)]) [self showJobInQueue:job];
  } else [self performConfirmed:request];
  [self refresh:nil];
}
- (NSDictionary *)enqueue:(NSDictionary *)request allowRetry:(BOOL)retry;
{
  NSString *pid=[request objectForKey:@"playlist"], *vid=[request objectForKey:@"video"], *format=[request objectForKey:@"format"];
  NSDictionary *job=[model_ jobForPlaylist:pid video:vid format:format];
  if(!job) [library_ enqueuePlaylist:pid video:vid format:format];
  else if([policy_ canDownloadAgain:job] || (retry && [policy_ canRetry:job])) [library_ retryJob:[job objectForKey:@"id"]];
  else return job;
  return [model_ jobForPlaylist:pid video:vid format:format];
}
- (void)performConfirmed:(NSDictionary *)request;
{
  NSString *op=[request objectForKey:@"operation"];
  if([op isEqualToString:@"bulk"]) {
    NSDictionary *last=nil;
    for(NSDictionary *item in [request objectForKey:@"plan"]) {
      /* Membership, exact quality and job state can change while the alert is open. */
      NSArray *eligible=[model_ missingPlanForPlaylist:[item objectForKey:@"playlist"] format:[item objectForKey:@"format"]];
      if([eligible containsObject:item]) last=[self enqueue:item allowRetry:NO];
    }
    if(last) [self showJobInQueue:last];
  } else if([op isEqualToString:@"syncAll"]) {
    for(NSString *input in [request objectForKey:@"inputs"]) if(![library_ isSyncPendingForInput:input]) [library_ syncPlaylistInput:input];
  } else if([op isEqualToString:@"discover"]) {
    if(![self enabled:@"discover"]) return;
    if([[library_ cookieStatus] isEqualToString:NSLocalizedString(@"Imported", nil)]) [library_ discoverPlaylists];
    else [self requestCookieImport:[self documentsCookiePath] discover:YES];
  } else if([op isEqualToString:@"import"]) {
    if([library_ isBusy]) return;
    if([library_ importCookies:[request objectForKey:@"path"]] && [[request objectForKey:@"discover"] boolValue]) [library_ discoverPlaylists];
  } else if([op isEqualToString:@"clearCookies"]) { if([self enabled:@"clearCookies"]) [library_ clearCookies]; }
  else if([op isEqualToString:@"removePlaylist"]) {
    NSDictionary *playlist=[request objectForKey:@"playlist"];
    if([model_ canRemovePlaylist:playlist]) { [library_ removePlaylist:playlist]; [[self navigationController] popViewControllerAnimated:YES]; }
  } else {
    NSDictionary *job=[model_ currentJob:[request objectForKey:@"job"]];
    if([op isEqualToString:@"delete"] && [policy_ canRemove:job] && ![policy_ canCancel:job]) [library_ removeDownload:job];
    if([op isEqualToString:@"stop"] && [policy_ canCancel:job]) [library_ cancelJob:[job objectForKey:@"id"]];
  }
}
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
- (void)sync:(id)sender; { (void)sender; if([self enabled:@"sync"]) [library_ syncPlaylistInput:[playlist_ objectForKey:@"service_id"]]; }
- (void)downloadAll:(id)sender;
{
  (void)sender; NSString *format=[RDLPLibrary preferredFormat]; NSArray *plan=[model_ missingPlanForPlaylist:[playlist_ objectForKey:@"id"] format:format];
  if([plan count]) [self confirm:[NSDictionary dictionaryWithObjectsAndKeys:@"bulk",@"operation",plan,@"plan",nil] title:[NSString stringWithFormat:NSLocalizedString(@"Download %lu missing videos?", nil),(unsigned long)[plan count]] detail:[NSString stringWithFormat:NSLocalizedString(@"Quality: %@. Existing failed, interrupted and stopped downloads are not retried.", nil),[RDLPLibrary qualityLabelForFormat:format]] button:NSLocalizedString(@"Download", nil)];
}
- (void)removePlaylist:(id)sender;
{ (void)sender; if([model_ canRemovePlaylist:playlist_]) [self confirm:[NSDictionary dictionaryWithObjectsAndKeys:@"removePlaylist",@"operation",playlist_,@"playlist",nil] title:NSLocalizedString(@"Remove playlist?", nil) detail:NSLocalizedString(@"Removes the playlist from your library. Downloads and unfinished jobs are retained. Your YouTube playlist is unchanged.", nil) button:NSLocalizedString(@"Remove", nil)]; }
- (void)queue:(id)sender; { (void)sender; [self showJobInQueue:nil]; }
- (void)settings:(id)sender;
{
  (void)sender;
  if(mode_==RDLPScreenSettings || [[self navigationController] presentedViewController] || alert_ || playlistActions_) return;
  RDLPSettingsViewController *settings=[[[RDLPSettingsViewController alloc] initWithLibrary:library_] autorelease];
  UINavigationController *modal=[[[UINavigationController alloc] initWithRootViewController:settings] autorelease];
  [[self navigationController] presentViewController:modal animated:YES completion:nil];
}
@end
