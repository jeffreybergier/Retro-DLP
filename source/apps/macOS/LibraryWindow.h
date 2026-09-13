#import <AICookieCutterWindowController.h>
#import "RetroDLPLibrary.h"
@interface LibraryWindow : AICookieCutterWindowController {
  RetroDLPLibrary *library_;
  NSTableView *sidebar_, *table_, *queue_;
  NSTextField *input_, *status_, *title_, *queueTitle_, *queueStatus_, *customFormat_, *customError_, *customSummary_;
  NSButton *pause_, *primary_, *jobAction_;
  NSMutableDictionary *toolbarItems_;
  NSAlert *confirmation_;
  NSDictionary *confirmationRequest_;
  NSPanel *addSheet_, *downloadSheet_;
  NSArray *playlists_, *rows_, *jobs_;
  NSString *selectedPlaylist_, *downloadFormat_;
  NSDictionary *downloadRequest_;
  int mode_, context_;
  BOOL refreshing_;
}
- (id)initWithLibrary:(RetroDLPLibrary *)library;
- (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier;
- (void)importCookies:(id)sender;
- (void)clearCookies:(id)sender;
@end
