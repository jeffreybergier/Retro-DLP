#import "RDLPAsyncTableViewController.h"
#import "RDLPLibrarySections.h"
#import "RDLPStatusBarView.h"

@interface RDLPVideoListViewController : RDLPAsyncTableViewController <UIAlertViewDelegate> {
  RDLPLibrary *library_;
  RDLPDownloadPolicy *policy_;
  RDLPLibrarySections *model_;
  UIAlertView *alert_;
  NSDictionary *retryRequest_;
  NSString *swipeJobID_;
  RDLPStatusBarView *statusBar_;
  BOOL visible_;
}
- (id)initWithLibrary:(RDLPLibrary *)library title:(NSString *)title;
- (BOOL)containsEntryForRetry:(NSDictionary *)entry;
- (NSString *)downloadFormatForJob:(NSDictionary *)job;
- (void)playJob:(NSDictionary *)job entry:(NSDictionary *)entry;
- (void)queue:(id)sender;
- (void)configureAddVideoButton;
- (void)addVideo:(id)sender;
/* Shared native list presentation hooks. */
- (BOOL)showsQueueButton;
- (BOOL)shouldHideToolbar;
- (UIImage *)statusIcon:(NSString *)status;
@end
