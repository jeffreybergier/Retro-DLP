#import "RDLPPlaylistViewController.h"
#import "RDLPUIKit.h"

@implementation RDLPPlaylistViewController
- (id)initWithLibrary:(RDLPLibrary *)library playlist:(NSDictionary *)playlist;
{ self=[super initWithLibrary:library title:[playlist objectForKey:@"title"]]; if(self) playlist_=[playlist copy]; return self; }
- (void)dealloc; { [playlist_ release]; [super dealloc]; }
- (NSArray *)listSections;
{ return [model_ sectionsForScreen:RDLPScreenPlaylist playlist:playlist_ video:nil collapsed:nil]; }
- (BOOL)containsEntryForRetry:(NSDictionary *)entry;
{ return [library_ playlist:[playlist_ objectForKey:@"id"] containsVideo:[entry objectForKey:@"video_id"]]; }
- (void)playJob:(NSDictionary *)job entry:(NSDictionary *)entry;
{ [RDLPUIKit presentPlayer:self library:library_ playlist:[playlist_ objectForKey:@"id"] entry:entry job:job]; }
- (NSString *)downloadFormatForJob:(NSDictionary *)job;
{
  /* A deliberately deleted download is a new request from the playlist.
     Missing files and failed attempts still retry their exact quality. */
  if([RDLPDownloadPolicy job:job hasState:@"removed"] && ![[job objectForKey:@"error"] length])
    return [RDLPLibrary preferredFormat];
  return [super downloadFormatForJob:job];
}
- (void)viewDidLoad;
{
  [super viewDidLoad];
  if([[playlist_ objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID]) [self configureAddVideoButton];
  else {
    self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithImage:[RDLPUIKit syncIcon] style:UIBarButtonItemStylePlain target:self action:@selector(sync:)] autorelease];
    self.navigationItem.rightBarButtonItem.accessibilityLabel=@"Sync";
  }
  [self refresh:nil];
}
- (void)refresh:(id)sender;
{
  if(![self isViewLoaded]) return;
  NSDictionary *playlist=[library_ playlistForID:[playlist_ objectForKey:@"id"]];
  if(playlist) {
    [playlist retain]; [playlist_ release]; playlist_=playlist; self.title=[playlist objectForKey:@"title"];
  }
  self.navigationItem.rightBarButtonItem.enabled=[[playlist_ objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID] || ([RDLPLibrary canSyncPlaylist:playlist_] && ![library_ isSyncPendingForInput:[playlist_ objectForKey:@"service_id"]]);
  [super refresh:sender];
}
- (void)sync:(id)sender;
{
  (void)sender; NSString *input=[playlist_ objectForKey:@"service_id"];
  if([RDLPLibrary canSyncPlaylist:playlist_] && ![library_ isSyncPendingForInput:input]) [library_ syncPlaylistInput:input];
  [self refresh:nil];
}
@end
