#import "RDLPLibrary.h"

/* Five ranges over one immutable database snapshot, never arrays of jobs. */
@interface RDLPDownloadSections : NSObject {
  NSArray *sections_;
}
- (id)initWithRows:(RDLPLibraryRows *)rows date:(NSDate *)date calendar:(NSCalendar *)calendar;
- (NSArray *)sections;
/* UIKit gets lazy slices; AppKit gets a lazy list with nonselectable headers. */
- (NSArray *)sectionsWithRows:(NSArray *)rows;
- (NSArray *)tableRows:(NSArray *)rows;
@end

/* Optional metadata query for the lazy AppKit adapter. */
@interface NSArray (RDLPDownloadHeaders)
- (NSIndexSet *)downloadHeaderIndexes;
- (BOOL)isSectionAtIndex:(NSUInteger)index;
@end
