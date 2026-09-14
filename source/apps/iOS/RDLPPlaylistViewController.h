#import <UIKit/UIKit.h>
#import "RDLPLibrarySections.h"
#import "RDLPStatusBarView.h"

@interface RDLPPlaylistViewController : UITableViewController <UIAlertViewDelegate> {
  RDLPLibrary *library_;
  RDLPDownloadPolicy *policy_;
  RDLPLibrarySections *model_;
  NSDictionary *playlist_;
  NSArray *sections_;
  UIAlertView *alert_;
  NSDictionary *retryRequest_;
  RDLPStatusBarView *statusBar_;
  BOOL visible_;
}
- (id)initWithLibrary:(RDLPLibrary *)library playlist:(NSDictionary *)playlist;
- (void)refresh:(id)sender;
- (void)sync:(id)sender;
- (void)queue:(id)sender;
@end
