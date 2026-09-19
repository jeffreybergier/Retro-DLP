#import <AppKit/AppKit.h>
#import "RDLPLibrary.h"

/* Owns the queue window; library actions and row data remain with its owner. */
@interface RDLPQueueWindowController : NSWindowController {
  id owner_;
  RDLPLibrary *library_;
  NSTableView *queue_;
  NSTextField *status_;
  NSProgressIndicator *progress_;
  NSMutableDictionary *toolbarItems_;
  BOOL didRestoreFrame_;
}
- (id)initWithLibrary:(RDLPLibrary *)library owner:(id)owner;
- (NSTableView *)tableView;
- (void)updateControls;
- (void)refreshStatus;
@end
