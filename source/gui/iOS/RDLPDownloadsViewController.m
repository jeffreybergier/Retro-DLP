#import "RDLPDownloadsViewController.h"

@implementation RDLPDownloadsViewController
- (id)initWithLibrary:(RDLPLibrary *)library;
{ return [super initWithLibrary:library title:@"All Downloads"]; }
- (NSArray *)listSections;
{ return [model_ sectionsForScreen:RDLPScreenDownloads playlist:nil video:nil collapsed:nil]; }
@end
