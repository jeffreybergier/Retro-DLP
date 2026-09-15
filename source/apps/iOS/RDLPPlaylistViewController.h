#import "RDLPVideoListViewController.h"

@interface RDLPPlaylistViewController : RDLPVideoListViewController {
  NSDictionary *playlist_;
}
- (id)initWithLibrary:(RDLPLibrary *)library playlist:(NSDictionary *)playlist;
- (void)sync:(id)sender;
@end
