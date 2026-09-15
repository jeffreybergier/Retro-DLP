#import "RDLPDownloadPolicy.h"

/* Shared, lazy presentation for playlist occurrences and exact download jobs.
   A playlist ID selects representative jobs; nil means source rows are jobs.
   Renderers consume the same fields regardless of the source. */
@interface RDLPVideoRows : NSArray {
  NSArray *source_;
  RDLPLibrary *library_;
  RDLPDownloadPolicy *policy_;
  NSString *playlist_;
  NSMutableDictionary *cache_;
}
- (id)initWithRows:(NSArray *)rows library:(RDLPLibrary *)library playlist:(NSString *)playlist;
- (id)cachedObjectAtIndex:(NSUInteger)index;
- (NSUInteger)indexForIdentity:(NSString *)identity;
@end
