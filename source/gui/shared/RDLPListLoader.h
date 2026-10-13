#import <Foundation/Foundation.h>
#import <AIPagedRows.h>
#import <AICollectionController.h>
/* Main-thread owner, borrowed delivery target. One worker and one latest
 * request per view. Invalidate before disposal; no UI objects in build input. */
@interface RDLPListLoader : AICollectionController
- (id)initWithTarget:(id)target builder:(Class)builder;
@end
@interface NSObject (RDLPListLoading)
+ (NSDictionary *)buildList:(NSDictionary *)input;
- (void)didLoadList:(NSDictionary *)result;
@end
@interface NSArray (RDLPAsyncRows)
- (NSArray *)RDLP_collectionIdentifiers;
/* Resolve a complete row synchronously through the bounded page cache. */
- (id)RDLP_requestRow:(NSUInteger)index;
- (void)RDLP_invalidateRows;
- (BOOL)RDLP_containsRows:(id)rows;
@end
