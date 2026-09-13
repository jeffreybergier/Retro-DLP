#import <Foundation/Foundation.h>

extern NSString * const RetroDLPLibraryDidChange;
/* Main-thread interface. Only this class imports application C headers. */
@interface RetroDLPLibrary : NSObject {
@private
  void *store_;
  NSLock *lock_;
  NSMutableArray *commands_;
  NSString *support_, *root_, *ca_, *assets_, *cookies_, *status_;
  BOOL busy_, paused_, cancel_, stopping_;
  long long activeJob_;
  double lastProgress_;
}
+ (NSArray *)qualityTitles;
+ (NSArray *)qualityFormats;
+ (NSString *)preferredFormat;
+ (BOOL)savePreferredFormat:(NSString *)format;
- (id)initWithSupportDirectory:(NSString *)support downloadDirectory:(NSString *)root;
- (NSArray *)playlists;
- (NSArray *)entriesForPlaylist:(NSString *)key;
- (NSArray *)jobsForPlaylist:(NSString *)key completedOnly:(BOOL)completed;
- (NSString *)status;
- (BOOL)isBusy;
- (BOOL)isPaused;
- (void)setPaused:(BOOL)paused;
- (void)syncPlaylistInput:(NSString *)input;
- (void)syncAll;
- (void)discoverPlaylists;
- (void)enqueuePlaylist:(NSString *)key video:(NSString *)video format:(NSString *)format;
- (void)retryJob:(NSString *)key;
- (void)cancelJob:(NSString *)key;
- (void)removeDownload:(NSDictionary *)job;
- (void)removePlaylist:(NSDictionary *)playlist;
- (BOOL)importCookies:(NSString *)path;
- (void)clearCookies;
- (NSString *)fileForJob:(NSDictionary *)job;
- (NSString *)playlistFile:(NSDictionary *)playlist;
- (void)shutdown;
@end
