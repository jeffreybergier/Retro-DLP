#import <AICookieCutterWindowController.h>
#import "RetroDLPLibrary.h"
@interface LibraryWindow : AICookieCutterWindowController {
  RetroDLPLibrary *library_;
  NSTableView *sidebar_, *table_;
  NSTextField *input_, *format_, *status_;
  NSPopUpButton *quality_;
  NSButton *pause_;
  NSArray *playlists_, *rows_;
  NSString *selectedPlaylist_;
  int mode_;
  BOOL refreshing_;
}
- (id)initWithLibrary:(RetroDLPLibrary *)library;
- (void)importCookies:(id)sender;
- (void)clearCookies:(id)sender;
@end
