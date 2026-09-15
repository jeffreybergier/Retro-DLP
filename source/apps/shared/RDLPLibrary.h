#import <Foundation/Foundation.h>

extern NSString * const RDLPLibraryDidChange;
extern NSString * const RDLPLibraryStatusDidChange;
extern NSString * const RDLPLibraryErrorDidOccur;
/* Main-thread interface. Only this class imports application C headers. */
@interface RDLPLibrary : NSObject {
@private
  void *store_;
  NSLock *lock_;
  NSMutableArray *commands_;
  NSDictionary *activeCommand_;
  NSString *support_, *root_, *ca_, *assets_, *cookies_, *status_;
  BOOL busy_, paused_, cancel_, stopping_;
  long long activeJob_;
  double lastProgress_;
  NSString *lastPhase_, *lastReadError_;
  double transferStarted_;
  unsigned long long transferCompleted_, transferExpected_;
  NSMutableArray *errors_;
  BOOL queueRun_;
  NSUInteger queueProcessed_, queueFailed_, queueCancelled_;
}
+ (NSArray *)qualityTitles;
+ (NSArray *)qualityFormats;
/* Preset name and exact expression, without implying measured resolution. */
+ (NSString *)qualityLabelForFormat:(NSString *)format;
+ (NSString *)preferredFormat;
+ (BOOL)validFormat:(NSString *)format;
+ (BOOL)savePreferredFormat:(NSString *)format;
- (id)initWithSupportDirectory:(NSString *)support downloadDirectory:(NSString *)root;
- (NSArray *)playlists;
- (NSArray *)entriesForPlaylist:(NSString *)key;
- (NSArray *)jobsForPlaylist:(NSString *)key completedOnly:(BOOL)completed;
- (NSString *)status;
/* Current transfer, separate from queue attempt counts. Empty status is idle.
   Every new status expires after ten seconds, even if its text is unchanged. */
- (NSDictionary *)activityProgress;
/* Main-thread alert queue; errors never replace status text. */
- (NSDictionary *)takeError;
- (BOOL)hasErrors;
- (BOOL)isBusy;
/* Item counts for this run only; historical completed jobs are excluded. */
- (NSDictionary *)queueProgress;
- (BOOL)isSyncPendingForInput:(NSString *)input;
- (BOOL)isDiscoveryPending;
- (NSString *)downloadsDirectory;
/* Local working-file availability, not account authentication. */
- (NSString *)cookieStatus;
- (BOOL)isPaused;
- (void)startDownloads;
- (void)setPaused:(BOOL)paused;
- (void)syncPlaylistInput:(NSString *)input;
- (void)addPlaylistInput:(NSString *)input;
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
