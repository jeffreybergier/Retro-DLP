#import "RDLPLibrary.h"

/* Shared interpretation of persisted job states and local file availability.
   This object reads the library; commands and confirmations belong to the controller. */
@interface RDLPDownloadPolicy : NSObject {
  RDLPLibrary *library_;
}
- (id)initWithLibrary:(RDLPLibrary *)library;
+ (BOOL)job:(NSDictionary *)job hasState:(NSString *)state;
- (NSString *)statusForJob:(NSDictionary *)job;
/* A single stat for a completed file supplies availability and its byte size.
   Row snapshots reuse this result; commands still recheck live availability. */
- (NSDictionary *)localFileForJob:(NSDictionary *)job;
- (NSString *)statusForJob:(NSDictionary *)job localFile:(NSDictionary *)file;
- (BOOL)playable:(NSDictionary *)job;
- (BOOL)canRetry:(NSDictionary *)job;
- (BOOL)canDownloadAgain:(NSDictionary *)job;
- (BOOL)canRemove:(NSDictionary *)job;
- (BOOL)canCancel:(NSDictionary *)job;
- (NSDictionary *)representativeJobForEntry:(NSDictionary *)entry playlist:(NSString *)playlist jobs:(NSArray *)jobs;
- (NSDictionary *)representativeJobForEntry:(NSDictionary *)entry playlist:(NSString *)playlist jobs:(NSArray *)jobs localFile:(NSDictionary **)file;
@end
