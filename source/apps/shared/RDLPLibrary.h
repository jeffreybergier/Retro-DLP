#import <Foundation/Foundation.h>
#import "rdapp_store.h"

/* Immutable, count-first database list. Row payloads are loaded on demand and
   cached in a bounded working set. Each list holds its own WAL read snapshot. */
@class RDLPLibrary;
@interface RDLPLibraryRows : NSArray {
@private
  void *reader_;
  RDLPLibrary *owner_;
  BOOL readFailed_;
  int query_;
  long long key_;
  NSString *video_, *format_;
  NSUInteger count_, lastIndex_;
  long long lastIdentity_;
  NSMutableDictionary *cache_;
}
- (NSUInteger)indexForIdentity:(NSString *)identity;
- (id)cachedObjectAtIndex:(NSUInteger)index;
/* Resolve a playlist within this list's snapshot, preserving sidebar selection. */
- (NSDictionary *)playlistForID:(NSString *)key;
@end
extern NSString * const RDLPLibraryDidChange;
extern NSString * const RDLPLibraryStatusDidChange;
extern NSString * const RDLPLibraryErrorDidOccur;
extern NSString * const RDLPLibraryActivityDidChange;
/* Posted on the main thread before releasing the operation reference, only
   for a successful download persisted as complete. userInfo is the final job. */
extern NSString * const RDLPLibraryDownloadDidComplete;
/* Main-thread interface. Only this class imports application C headers. */
@interface RDLPLibrary : NSObject {
@private
  void *store_;
  NSLock *lock_, *cancelLock_;
  NSMutableArray *commands_;
  NSDictionary *activeCommand_;
  NSString *support_, *root_, *ca_, *assets_, *cookies_, *status_;
  BOOL busy_, paused_, cancel_, stopping_;
  BOOL operationsSuspended_;
  NSUInteger operationCount_;
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
/* Optional numbers arrive from SQLite as strings; empty means absent, not zero. */
+ (NSString *)durationLabelForEntry:(NSDictionary *)entry;
+ (NSString *)spokenDurationForEntry:(NSDictionary *)entry;
+ (NSString *)metadataSummaryForEntry:(NSDictionary *)entry;
+ (NSString *)metadataTooltipForEntry:(NSDictionary *)entry;
+ (NSString *)fileSizeLabelForBytes:(unsigned long long)bytes;
+ (NSString *)preferredFormat;
+ (BOOL)validFormat:(NSString *)format;
+ (BOOL)savePreferredFormat:(NSString *)format;
- (id)initWithSupportDirectory:(NSString *)support downloadDirectory:(NSString *)root;
- (NSArray *)playlists;
- (NSDictionary *)adhocPlaylist;
- (NSArray *)playlistsFromAccount:(BOOL)account;
- (NSArray *)playlistIDsFromAccount:(BOOL)account;
- (NSDictionary *)playlistForID:(NSString *)key;
- (NSDictionary *)jobForID:(NSString *)key;
- (NSArray *)jobsForPlaylist:(NSString *)key video:(NSString *)video;
- (NSDictionary *)jobForPlaylist:(NSString *)key video:(NSString *)video format:(NSString *)format;
- (RDLPLibraryRows *)queueRows;
- (NSUInteger)queuedCount;
- (BOOL)hasBlockingJobsForPlaylist:(NSString *)key;
- (BOOL)hasPlaylistsToSync;
/* Menu validation uses stored states; explicit bulk planning also checks files. */
- (BOOL)hasMissingEntriesForPlaylist:(NSString *)key format:(NSString *)format;
- (NSArray *)missingPlanForPlaylist:(NSString *)key format:(NSString *)format;
- (NSArray *)entriesForPlaylist:(NSString *)key;
- (BOOL)playlist:(NSString *)key containsVideo:(NSString *)video;
- (NSArray *)jobsForPlaylist:(NSString *)key completedOnly:(BOOL)completed;
- (NSString *)status;
/* Current transfer, separate from queue attempt counts. Empty status is idle.
   Every new status expires after ten seconds, even if its text is unchanged. */
- (NSDictionary *)activityProgress;
/* Main-thread alert queue; errors never replace status text. */
- (NSDictionary *)takeError;
- (BOOL)hasErrors;
- (BOOL)isBusy;
/* Main-thread operation references, including completion and queue handoff.
   Observers can hold platform background execution while this is nonzero. */
- (NSUInteger)operationCount;
/* Stop admitting any worker and cancel active network work without waiting.
   startDownloads clears suspension when the app returns to the foreground. */
- (void)suspendOperations;
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
- (void)addVideoInput:(NSString *)input;
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
