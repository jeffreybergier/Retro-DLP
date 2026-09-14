#import <AICookieCutterWindowController.h>
#import "RetroDLPLibrary.h"
#import "RDQueueOutline.h"
@interface LibraryWindow : AICookieCutterWindowController {
  RetroDLPLibrary *library_;
  NSOutlineView *sidebar_;
  NSTableView *table_;
  NSTableColumn *qualityColumn_;
  RDQueueOutlineView *queue_;
  RDQueueTree *queueTree_;
  NSMutableSet *queueCollapsed_;
  NSMutableDictionary *sidebarItems_;
  BOOL sidebarLoaded_;
  NSTextField *input_, *status_, *customFormat_, *customError_, *customSummary_;
  NSProgressIndicator *queueProgress_;
  NSMutableDictionary *toolbarItems_;
  NSAlert *confirmation_;
  NSDictionary *confirmationRequest_;
  NSPanel *addSheet_, *downloadSheet_;
  NSArray *playlists_, *rows_, *jobs_;
  NSString *selectedPlaylist_, *downloadFormat_;
  NSDictionary *downloadRequest_;
  int mode_, context_;
  BOOL refreshing_;
  BOOL didRestoreWindowFrame_;
}
- (id)initWithLibrary:(RetroDLPLibrary *)library;
- (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier;
- (NSMenu *)menuForMenuBarTitle:(NSString *)title;
- (void)importCookies:(id)sender;
- (void)clearCookies:(id)sender;
@end
