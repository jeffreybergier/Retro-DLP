#import <UIKit/UIKit.h>
#import "RDLPLibrarySections.h"
#import "RDLPStatusBarView.h"

@interface RDLPLibraryViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate, UIActionSheetDelegate> {
  RDLPLibrary *library_;
  RDLPDownloadPolicy *policy_;
  RDLPLibrarySections *model_;
  NSDictionary *playlist_, *video_;
  NSArray *sections_;
  UITableView *tableView_;
  RDLPStatusBarView *statusBar_;
  UILabel *status_;
  UIProgressView *progress_;
  RDLPScreen mode_;
  UIAlertView *alert_;
  UIActionSheet *playlistActions_;
  NSDictionary *request_;
  NSArray *alertActions_;
}
@property(nonatomic,readonly) UITableView *tableView;
- (id)initWithLibrary:(RDLPLibrary *)library mode:(RDLPScreen)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
- (void)refresh:(id)sender;
- (void)pushMode:(RDLPScreen)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
- (void)showJobInQueue:(NSDictionary *)job;
@end

/* Commands own immutable alert requests and revalidate them before execution. */
@interface RDLPLibraryViewController (Actions)
- (BOOL)requestCookieImport:(NSString *)path discover:(BOOL)discover;
- (BOOL)enabled:(NSString *)action;
- (void)performRow:(NSDictionary *)row;
- (void)showPlaylistActions:(id)sender;
- (void)add:(id)sender;
- (void)addVideo:(id)sender;
- (void)discover:(id)sender;
- (void)syncAll:(id)sender;
- (void)sync:(id)sender;
- (void)downloadAll:(id)sender;
- (void)removePlaylist:(id)sender;
- (void)queue:(id)sender;
- (void)settings:(id)sender;
- (void)confirm:(NSDictionary *)request title:(NSString *)title detail:(NSString *)detail button:(NSString *)button;
- (void)performConfirmed:(NSDictionary *)request;
- (NSDictionary *)enqueue:(NSDictionary *)request allowRetry:(BOOL)retry;
@end
