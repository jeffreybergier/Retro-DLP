#import "RDLPDownloadPolicy.h"

typedef enum {
  RDLPScreenLibrary, RDLPScreenPlaylist, RDLPScreenQueue,
  RDLPScreenDownloads, RDLPScreenSettings, RDLPScreenVideo
} RDLPScreen;

/* Read-only table snapshots; each download row retains its stable job ID. */
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
- (NSArray *)actionsForJob:(NSDictionary *)job;
@end
