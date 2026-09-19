#import <UIKit/UIKit.h>
#import "RDLPLibrarySections.h"
#import "RDLPStatusBarView.h"

@interface RDLPPlaylistsViewController : UITableViewController <UIAlertViewDelegate, UIActionSheetDelegate> {
  RDLPLibrary *library_;
  RDLPLibrarySections *model_;
  NSArray *sections_;
  RDLPStatusBarView *statusBar_;
  UIAlertView *alert_;
  UIActionSheet *playlistActions_;
  NSDictionary *request_;
  NSArray *alertActions_;
  NSString *swipePlaylistID_;
}
- (id)initWithLibrary:(RDLPLibrary *)library;
- (void)refresh:(id)sender;
- (BOOL)enabled:(NSString *)action;
- (void)performRow:(NSDictionary *)row;
- (void)showPlaylistActions:(id)sender;
- (void)add:(id)sender;
- (void)addVideo:(id)sender;
- (void)discover:(id)sender;
- (void)syncAll:(id)sender;
- (void)settings:(id)sender;
- (void)queue:(id)sender;
- (BOOL)requestCookieImport:(NSString *)path discover:(BOOL)discover;
@end
