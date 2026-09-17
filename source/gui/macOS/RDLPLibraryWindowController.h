#import <AICookieCutterWindowController.h>
#import "RDLPLibrary.h"
#import "RDLPDownloadPolicy.h"
#import "RDLPLibraryMenus.h"
@interface RDLPLibraryWindowController : AICookieCutterWindowController <RDLPLibraryMenuContext> {
  RDLPLibrary *library_;
  RDLPDownloadPolicy *downloadPolicy_;
  NSOutlineView *sidebar_;
  NSTableView *table_;
  NSTableView *queue_;
  NSArray *queueRows_, *videoRows_;
  NSMutableDictionary *sidebarItems_;
  BOOL sidebarLoaded_;
  NSTextField *input_, *status_, *customFormat_, *customError_, *customSummary_;
  NSProgressIndicator *queueProgress_;
  NSMutableDictionary *toolbarItems_;
  NSAlert *confirmation_;
  NSDictionary *confirmationRequest_;
  NSPanel *addSheet_, *downloadSheet_;
  NSArray *playlists_, *rows_, *addedPlaylists_, *accountPlaylists_; NSDictionary *adhocPlaylist_;
  NSString *selectedPlaylist_, *downloadFormat_;
  NSDictionary *downloadRequest_;
  int mode_, context_;
  BOOL refreshing_, addingVideo_;
  BOOL didRestoreWindowFrame_;
}
- (id)initWithLibrary:(RDLPLibrary *)library;
- (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier;
- (NSMenu *)menuForMenuBarTitle:(NSString *)title;
- (void)importCookies:(id)sender;
- (void)clearCookies:(id)sender;
@end
