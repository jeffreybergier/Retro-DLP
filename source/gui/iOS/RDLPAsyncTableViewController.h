#import <UIKit/UIKit.h>
#import "RDLPLibrarySections.h"
/* Shared UIKit lifecycle and identity restoration for all library list screens. */
@interface RDLPAsyncTableViewController : UITableViewController {
  NSArray *sections_;
  RDLPListLoader *listLoader_;
  BOOL listSuspended_, listClosed_;
}
- (NSDictionary *)listRequest;
- (BOOL)canApplyList;
- (void)refresh:(id)sender;
- (void)refreshStatus:(id)sender;
- (void)didLoadList:(NSDictionary *)result;
- (NSDictionary *)rowAtIndex:(NSIndexPath *)index;
@end
