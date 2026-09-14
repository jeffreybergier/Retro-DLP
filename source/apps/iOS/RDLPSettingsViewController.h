#import <UIKit/UIKit.h>
#import "RDLPLibrarySections.h"

@interface RDLPSettingsViewController : UITableViewController <UIAlertViewDelegate> {
  RDLPLibrary *library_;
  RDLPLibrarySections *model_;
  NSArray *sections_;
  UIAlertView *alert_;
  NSDictionary *request_;
}
- (id)initWithLibrary:(RDLPLibrary *)library;
- (void)refresh:(id)sender;
- (BOOL)enabled:(NSString *)action;
- (void)performRow:(NSDictionary *)row;
- (BOOL)requestCookieImport:(NSString *)path discover:(BOOL)discover;
- (void)dismissSettings:(id)sender;
@end
