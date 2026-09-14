#import "RDLPLibrary.h"

/* Shared interpretation of persisted job states and local file availability.
   This object reads the library; commands and confirmations belong to the controller. */
@interface RDLPDownloadPolicy : NSObject {
  RDLPLibrary *library_;
}
- (id)initWithLibrary:(RDLPLibrary *)library;
+ (BOOL)job:(NSDictionary *)job hasState:(NSString *)state;
- (NSString *)statusForJob:(NSDictionary *)job;
- (BOOL)playable:(NSDictionary *)job;
- (BOOL)canRetry:(NSDictionary *)job;
- (BOOL)canDownloadAgain:(NSDictionary *)job;
- (BOOL)canRemove:(NSDictionary *)job;
- (BOOL)canCancel:(NSDictionary *)job;
- (NSDictionary *)representativeJobForEntry:(NSDictionary *)entry playlist:(NSString *)playlist jobs:(NSArray *)jobs;
@end
