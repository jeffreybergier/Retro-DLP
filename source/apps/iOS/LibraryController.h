#import <UIKit/UIKit.h>
#import "RetroDLPLibrary.h"
/* mode: 0 playlists, 1 entries, 2 queue, 3 downloads, 4 settings, 5 video */
@interface LibraryController : UITableViewController <UIAlertViewDelegate> {
  RetroDLPLibrary *library_;
  NSDictionary *playlist_, *video_;
  NSArray *rows_;
  UILabel *status_;
  int mode_;
  NSString *format_;
  NSDictionary *pendingRemoval_;
}
- (id)initWithLibrary:(RetroDLPLibrary *)library mode:(int)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
@end
