#import "RDLPVideoListViewController.h"

@interface RDLPQueueViewController : RDLPVideoListViewController {
  NSString *selectedJobID_;
  NSArray *jobActions_;
}
- (id)initWithLibrary:(RDLPLibrary *)library;
- (void)showJobInQueue:(NSDictionary *)job;
- (void)dismissQueue:(id)sender;
@end
