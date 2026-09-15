#import "RDLPPlaylistViewController.h"
#import "RDLPUIKit.h"

@implementation RDLPPlaylistViewController
- (id)initWithLibrary:(RDLPLibrary *)library playlist:(NSDictionary *)playlist;
{ return [super initWithLibrary:library mode:RDLPScreenPlaylist playlist:playlist]; }
- (void)viewDidLoad;
{
  [super viewDidLoad];
  self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithImage:[RDLPUIKit syncIcon] style:UIBarButtonItemStylePlain target:self action:@selector(sync:)] autorelease];
  self.navigationItem.rightBarButtonItem.accessibilityLabel=@"Sync";
  [self refresh:nil];
}
- (void)refresh:(id)sender;
{
  if(![self isViewLoaded]) return;
  for(NSDictionary *playlist in [library_ playlists]) if([[playlist objectForKey:@"id"] isEqualToString:[playlist_ objectForKey:@"id"]]) {
    [playlist retain]; [playlist_ release]; playlist_=playlist; self.title=[playlist objectForKey:@"title"]; break;
  }
  self.navigationItem.rightBarButtonItem.enabled=![library_ isSyncPendingForInput:[playlist_ objectForKey:@"service_id"]];
  [super refresh:sender];
}
- (void)sync:(id)sender;
{
  (void)sender; NSString *input=[playlist_ objectForKey:@"service_id"];
  if(![library_ isSyncPendingForInput:input]) [library_ syncPlaylistInput:input];
  [self refresh:nil];
}
@end
