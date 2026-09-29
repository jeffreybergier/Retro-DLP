#import "RDLPDownloadsViewController.h"
#import "RDLP_Foundation.h"
#import "RDLPUIKit.h"

@implementation RDLPDownloadsViewController
- (id)initWithLibrary:(RDLPLibrary *)library;
{
  self=[super initWithLibrary:library title:@"All Downloads"];
  if(self) {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RDLPDateBoundariesDidChange object:nil];
    [NSCalendar RDLP_monitorDateBoundaries];
  }
  return self;
}
- (void)viewDidLoad;
{ [super viewDidLoad]; [self configureAddVideoButton]; }
- (NSArray *)listSections;
{ return [model_ sectionsForScreen:RDLPScreenDownloads playlist:nil video:nil collapsed:nil]; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section;
{ (void)table; return [[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"title"]; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index;
{
  UITableViewCell *cell=[super tableView:table cellForRowAtIndexPath:index];
  [[cell detailTextLabel] setNumberOfLines:1];
  [RDLPUIKit truncateMiddleInLabel:[cell detailTextLabel]];
  return cell;
}
@end
