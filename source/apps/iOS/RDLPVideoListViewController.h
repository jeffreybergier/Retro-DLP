#import <UIKit/UIKit.h>
#import "RDLPLibrarySections.h"
#import "RDLPStatusBarView.h"

@interface RDLPVideoListViewController : UITableViewController <UIAlertViewDelegate> {
  RDLPLibrary *library_;
  RDLPDownloadPolicy *policy_;
  RDLPLibrarySections *model_;
  NSDictionary *playlist_;
  RDLPScreen mode_;
  NSArray *sections_;
  UIAlertView *alert_;
  NSDictionary *retryRequest_;
  NSString *swipeJobID_;
  RDLPStatusBarView *statusBar_;
  BOOL visible_;
}
- (id)initWithLibrary:(RDLPLibrary *)library mode:(RDLPScreen)mode playlist:(NSDictionary *)playlist;
- (void)refresh:(id)sender;
- (void)queue:(id)sender;
@end
