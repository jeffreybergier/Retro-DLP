#import <UIKit/UIKit.h>
#import "RDLPLibrary.h"
/* mode: 0 playlists, 1 entries, 2 queue, 3 downloads, 4 settings, 5 video */
@interface LibraryController : UITableViewController <UIAlertViewDelegate> {
  RDLPLibrary *library_;
  NSDictionary *playlist_, *video_;
  NSArray *rows_;
  UILabel *status_;
  int mode_;
  NSString *format_;
  NSDictionary *pendingRemoval_;
}
- (id)initWithLibrary:(RDLPLibrary *)library mode:(int)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
@end
