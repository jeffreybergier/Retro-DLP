#import "RDLPLibraryViewController.h"
#import "RDLPUIKit.h"
#import "RDLPSettingsViewController.h"

@implementation RDLPLibraryViewController (Actions)
- (BOOL)enabled:(NSString *)action;
{
  if([action isEqualToString:@"import"]) return ![library_ isBusy] && ![[library_ cookieStatus] isEqualToString:@"Imported"];
  if([action isEqualToString:@"clearCookies"]) return ![library_ isBusy] && ![[library_ cookieStatus] isEqualToString:@"Not Imported"];
  if([action isEqualToString:@"discover"]) return ![library_ isBusy] && ![library_ isDiscoveryPending];
  if([action isEqualToString:@"sync"]) return playlist_ && ![[playlist_ objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID] && ![library_ isSyncPendingForInput:[playlist_ objectForKey:@"service_id"]];
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
- (void)confirmJob:(NSDictionary *)job operation:(NSString *)operation;
{
  if([operation isEqualToString:@"delete"]?![policy_ canRemove:job]:![policy_ canCancel:job]) return;
  [self confirm:[NSDictionary dictionaryWithObjectsAndKeys:operation,@"operation",[job objectForKey:@"id"],@"job",nil]
    title:[NSString stringWithFormat:@"%@ %@ — %@?",[operation isEqualToString:@"delete"]?@"Delete":@"Stop",[job objectForKey:@"title"],[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]]]
    detail:[operation isEqualToString:@"delete"]?@"Deletes this quality and its partial files. Other qualities and playlist membership are retained.":@"Retry restarts this quality from the beginning. Other queued downloads continue."
    button:[operation isEqualToString:@"delete"]?@"Delete":@"Stop"];
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
  else if([action isEqualToString:@"custom"]) [self showAlert:@"Custom Format" detail:@"Example: 18 or 136+140" request:[NSDictionary dictionaryWithObject:@"quality" forKey:@"operation"] buttons:[NSArray arrayWithObject:@"Save"] input:[RDLPLibrary preferredFormat]];
  else if([action isEqualToString:@"download"]) {
    [self showJobInQueue:[self enqueue:[NSDictionary dictionaryWithObjectsAndKeys:[playlist_ objectForKey:@"id"],@"playlist",[video_ objectForKey:@"video_id"],@"video",[RDLPLibrary preferredFormat],@"format",nil] allowRetry:YES]];
  } else if([action isEqualToString:@"play"]) { if([policy_ playable:job]) [RDLPUIKit presentPlayer:self library:library_ job:job legacy:NO]; }
  else if([action isEqualToString:@"delete"]) [self confirmJob:job operation:@"delete"];
  else if([action isEqualToString:@"showQueue"]) [self showJobInQueue:job];
  else if([action isEqualToString:@"job"] && job) [self showAlert:[job objectForKey:@"title"] detail:[NSString stringWithFormat:@"%@ · %@\n%@",[policy_ statusForJob:job],[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]],([job objectForKey:@"error"]?[job objectForKey:@"error"]:@"")] request:[NSDictionary dictionaryWithObjectsAndKeys:@"jobActions",@"operation",[job objectForKey:@"id"],@"job",nil] buttons:[model_ actionsForJob:job] input:nil];
  else if([action isEqualToString:@"import"]) { if([self enabled:@"import"]) [self requestCookieImport:[self documentsCookiePath] discover:NO]; }
  else if([action isEqualToString:@"clearCookies"]) [self confirm:[NSDictionary dictionaryWithObject:@"clearCookies" forKey:@"operation"] title:@"Remove imported cookies?" detail:@"Only the app’s working copy is removed. Your original export is retained." button:@"Remove"];
  else if([action isEqualToString:@"guide"]) [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/yt-dlp/yt-dlp/wiki/Extractors"]];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index;
{
  if(alert!=alert_) return;
  NSDictionary *request=[[request_ retain] autorelease]; NSArray *actions=[[alertActions_ retain] autorelease];
  NSString *text=alert.alertViewStyle==UIAlertViewStylePlainTextInput?[[[alert textFieldAtIndex:0].text copy] autorelease]:nil;
  alert_.delegate=nil; [alert_ release]; alert_=nil; [request_ release]; request_=nil; [alertActions_ release]; alertActions_=nil;
  if(index==0) return;
  NSString *op=[request objectForKey:@"operation"];
  if([op isEqualToString:@"add"]) [library_ addPlaylistInput:text];
  else if([op isEqualToString:@"addVideo"]) [library_ addVideoInput:text];
  else if([op isEqualToString:@"quality"]) {
    if(![RDLPLibrary savePreferredFormat:text]) [RDLPUIKit showMessage:@"Enter an exact format such as 18 or 136+140."];
  } else if([op isEqualToString:@"jobActions"]) {
    NSDictionary *job=[model_ currentJob:[request objectForKey:@"job"]]; if(!job) return;
    NSString *action=[actions objectAtIndex:(NSUInteger)index-1];
    if([action isEqualToString:@"Play"] && [policy_ playable:job]) [RDLPUIKit presentPlayer:self library:library_ job:job legacy:NO];
    else if([action isEqualToString:@"Download Video"] && ([policy_ canRetry:job] || [policy_ canDownloadAgain:job])) { [library_ retryJob:[job objectForKey:@"id"]]; [self showJobInQueue:job]; }
    else if([action isEqualToString:@"Stop Download…"]) [self confirmJob:job operation:@"stop"];
    else if([action isEqualToString:@"Delete Download…"]) [self confirmJob:job operation:@"delete"];
    else if([action isEqualToString:@"Show in Queue"]) [self showJobInQueue:job];
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
    if([[library_ cookieStatus] isEqualToString:@"Imported"]) [library_ discoverPlaylists];
    else [self requestCookieImport:[self documentsCookiePath] discover:YES];
  } else if([op isEqualToString:@"import"]) {
    if([library_ isBusy]) return;
    if([library_ importCookies:[request objectForKey:@"path"]] && [[request objectForKey:@"discover"] boolValue]) [library_ discoverPlaylists];
  } else if([op isEqualToString:@"clearCookies"]) { if([self enabled:@"clearCookies"]) [library_ clearCookies]; }
  else if([op isEqualToString:@"removePlaylist"]) {
    NSDictionary *playlist=[request objectForKey:@"playlist"];
    if([model_ canRemovePlaylist:playlist]) { [library_ removePlaylist:playlist]; [self.navigationController popViewControllerAnimated:YES]; }
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
    otherButtonTitles:@"Add Video…",@"Add Playlist…",@"Sync All Playlists…",@"Load My Playlists…",nil];
  [playlistActions_ showFromBarButtonItem:self.navigationItem.rightBarButtonItem animated:YES];
}
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index;
{
  if(sheet!=playlistActions_) return;
  BOOL cancelled=index==sheet.cancelButtonIndex || index<0;
  playlistActions_.delegate=nil; [playlistActions_ release]; playlistActions_=nil;
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
{ (void)sender; [self showAlert:@"Add Playlist" detail:@"YouTube playlist URL or ID" request:[NSDictionary dictionaryWithObject:@"add" forKey:@"operation"] buttons:[NSArray arrayWithObject:@"Sync"] input:@""]; }
- (void)addVideo:(id)sender;
{ (void)sender; [self showAlert:@"Add Video" detail:@"YouTube video URL or ID" request:[NSDictionary dictionaryWithObject:@"addVideo" forKey:@"operation"] buttons:[NSArray arrayWithObject:@"Add"] input:@""]; }
- (void)discover:(id)sender;
{ (void)sender; if([self enabled:@"discover"]) [self confirm:[NSDictionary dictionaryWithObject:@"discover" forKey:@"operation"] title:@"Load My Playlists?" detail:@"Discover your YouTube account playlists and save their metadata. Cookies are required. No videos will be downloaded." button:@"Load Playlists"]; }
- (void)syncAll:(id)sender;
{
  (void)sender; NSMutableArray *inputs=[NSMutableArray array];
  for(NSDictionary *playlist in [library_ playlists]) if(![[playlist objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID] && ![library_ isSyncPendingForInput:[playlist objectForKey:@"service_id"]]) [inputs addObject:[playlist objectForKey:@"service_id"]];
  if([inputs count]) [self confirm:[NSDictionary dictionaryWithObjectsAndKeys:@"syncAll",@"operation",inputs,@"inputs",nil] title:@"Sync all playlists?" detail:@"Refresh playlist metadata from YouTube. Local downloads are retained." button:@"Sync All"];
}
- (void)sync:(id)sender; { (void)sender; if([self enabled:@"sync"]) [library_ syncPlaylistInput:[playlist_ objectForKey:@"service_id"]]; }
- (void)downloadAll:(id)sender;
{
  (void)sender; NSString *format=[RDLPLibrary preferredFormat]; NSArray *plan=[model_ missingPlanForPlaylist:[playlist_ objectForKey:@"id"] format:format];
  if([plan count]) [self confirm:[NSDictionary dictionaryWithObjectsAndKeys:@"bulk",@"operation",plan,@"plan",nil] title:[NSString stringWithFormat:@"Download %lu missing videos?",(unsigned long)[plan count]] detail:[NSString stringWithFormat:@"Quality: %@. Existing failed, interrupted and stopped downloads are not retried.",[RDLPLibrary qualityLabelForFormat:format]] button:@"Download"];
}
- (void)removePlaylist:(id)sender;
{ (void)sender; if([model_ canRemovePlaylist:playlist_]) [self confirm:[NSDictionary dictionaryWithObjectsAndKeys:@"removePlaylist",@"operation",playlist_,@"playlist",nil] title:@"Remove playlist?" detail:@"Removes only the local library entry. Your YouTube playlist is unchanged." button:@"Remove"]; }
- (void)queue:(id)sender; { (void)sender; [self showJobInQueue:nil]; }
- (void)settings:(id)sender;
{
  (void)sender;
  if(mode_==RDLPScreenSettings || self.navigationController.presentedViewController || alert_ || playlistActions_) return;
  RDLPSettingsViewController *settings=[[[RDLPSettingsViewController alloc] initWithLibrary:library_] autorelease];
  UINavigationController *modal=[[[UINavigationController alloc] initWithRootViewController:settings] autorelease];
  [self.navigationController presentViewController:modal animated:YES completion:nil];
}
@end
