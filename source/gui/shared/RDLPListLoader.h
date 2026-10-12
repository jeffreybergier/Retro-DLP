#import <Foundation/Foundation.h>
#import <AIPagedRows.h>
/* Main-thread owner, borrowed delivery target. One worker and one latest
 * request per view. Invalidate before disposal; no UI objects in build input. */
@interface RDLPListLoader : NSObject {
  id target_;
  Class builder_;
  NSLock *lock_;
  NSDictionary *pending_;
  unsigned long generation_;
  BOOL working_, invalid_;
}
- (id)initWithTarget:(id)target builder:(Class)builder;
- (void)request:(NSDictionary *)input;
- (void)invalidate;
- (BOOL)isCancelled;
/* Includes a result waiting for main-thread delivery. */
- (BOOL)isLoading;
@end
@interface NSObject (RDLPListLoading)
+ (NSDictionary *)buildList:(NSDictionary *)input;
- (void)didLoadList:(NSDictionary *)result;
@end
@interface NSArray (RDLPAsyncRows)
- (id)RDLP_requestRow:(NSUInteger)index;
- (void)RDLP_invalidateRows;
- (BOOL)RDLP_containsRows:(id)rows;
@end
