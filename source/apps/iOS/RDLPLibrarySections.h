#import "RDLPDownloadPolicy.h"

typedef enum {
  RDLPScreenLibrary, RDLPScreenPlaylist, RDLPScreenQueue,
  RDLPScreenDownloads, RDLPScreenSettings, RDLPScreenVideo
} RDLPScreen;

/* Read-only table snapshots. Stable keys preserve collapsed queue branches. */
@interface RDLPLibrarySections : NSObject {
  RDLPLibrary *library_;
  RDLPDownloadPolicy *policy_;
}
- (id)initWithLibrary:(RDLPLibrary *)library;
- (NSArray *)sectionsForScreen:(RDLPScreen)screen playlist:(NSDictionary *)playlist video:(NSDictionary *)video collapsed:(NSSet *)collapsed;
- (NSDictionary *)currentJob:(NSString *)key;
- (NSDictionary *)jobForPlaylist:(NSString *)playlist video:(NSString *)video format:(NSString *)format;
- (NSArray *)missingPlanForPlaylist:(NSString *)playlist format:(NSString *)format;
- (BOOL)canRemovePlaylist:(NSDictionary *)playlist;
- (NSString *)queueGroupForJob:(NSDictionary *)job;
- (NSArray *)actionsForJob:(NSDictionary *)job;
@end
