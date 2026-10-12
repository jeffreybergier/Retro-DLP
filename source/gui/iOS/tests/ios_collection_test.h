#import <AICollectionTableAdapter.h>
@interface RDLPCollectionTestTable : UITableView {
@public NSUInteger full_, partial_, inserted_, removed_;
}
@end
@implementation RDLPCollectionTestTable
- (void)reloadData; { ++full_; [super reloadData]; }
- (void)reloadRowsAtIndexPaths:(NSArray *)paths withRowAnimation:(UITableViewRowAnimation)animation;
{ partial_+=[paths count]; [super reloadRowsAtIndexPaths:paths withRowAnimation:animation]; }
- (void)insertRowsAtIndexPaths:(NSArray *)paths withRowAnimation:(UITableViewRowAnimation)animation;
{ inserted_+=[paths count]; [super insertRowsAtIndexPaths:paths withRowAnimation:animation]; }
- (void)deleteRowsAtIndexPaths:(NSArray *)paths withRowAnimation:(UITableViewRowAnimation)animation;
{ removed_+=[paths count]; [super deleteRowsAtIndexPaths:paths withRowAnimation:animation]; }
@end
@interface RDLPCollectionTestSource : NSObject <UITableViewDataSource> {
@public NSArray *sections_;
}
@end
@implementation RDLPCollectionTestSource
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table;
{ (void)table; return [sections_ count]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{ (void)table; return [[[sections_ objectAtIndex:section] objectForKey:@"rows"] count]; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path;
{
  (void)table;
  UITableViewCell *cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
  [[cell textLabel] setText:[[[sections_ objectAtIndex:[path section]] objectForKey:@"rows"] objectAtIndex:[path row]]];
  return cell;
}
@end
static NSDictionary *collectionSection(NSString *key, NSArray *rows)
{ return [NSDictionary dictionaryWithObjectsAndKeys:key,@"id",rows,@"rows",rows,@"identifiers",nil]; }
static void collectionTest(UIWindow *window)
{
  UIViewController *previous=[[window rootViewController] retain];
  UIViewController *controller=[[UIViewController alloc] init];
  RDLPCollectionTestTable *table=[[RDLPCollectionTestTable alloc] initWithFrame:[window bounds] style:UITableViewStylePlain];
  RDLPCollectionTestSource *source=[[RDLPCollectionTestSource alloc] init];
  [table setDataSource:source]; [controller setView:table]; [window setRootViewController:controller];
  AICollectionTableAdapter *adapter=[[AICollectionTableAdapter alloc] initWithTableView:table];
  NSArray *rows=[NSArray arrayWithObjects:@"a",@"b",@"c",nil];
  source->sections_=[NSArray arrayWithObject:collectionSection(@"main",rows)];
  [adapter applySnapshot:[[[AICollectionSnapshot alloc] initWithSections:source->sections_] autorelease]]; pump();
  [table selectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
  NSUInteger full=table->full_;
  rows=[NSArray arrayWithObjects:@"x",@"a",@"b",nil];
  source->sections_=[NSArray arrayWithObject:collectionSection(@"main",rows)];
  [adapter applySnapshot:[[[AICollectionSnapshot alloc] initWithSections:source->sections_] autorelease]]; pump();
  require(table->full_==full && table->inserted_==1 && table->removed_==1,@"Collection uses native row insert/delete");
  require([[table indexPathForSelectedRow] row]==2,@"Collection preserves selected identity");
  [table setContentInset:UIEdgeInsetsMake(64,0,0,0)];
  [table setContentOffset:CGPointZero animated:NO];
  NSUInteger partial=table->partial_;
  [[NSNotificationCenter defaultCenter] postNotificationName:AIPagedRowsDidLoadNotification object:rows
    userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0] forKey:@"offset"]]; pump();
  require(table->full_==full && table->partial_>partial,@"Page arrival reloads rows without reloading table");
  require(CGPointEqualToPoint([table contentOffset],CGPointZero),@"Page refresh preserves deliberate offset in short inset table");
  source->sections_=[NSArray arrayWithObjects:collectionSection(@"new",[NSArray arrayWithObject:@"z"]),
    collectionSection(@"main",[NSArray arrayWithObjects:@"b",@"a",nil]),nil];
  [adapter applySnapshot:[[[AICollectionSnapshot alloc] initWithSections:source->sections_] autorelease]]; pump();
  require(table->full_==full && [table numberOfSections]==2 && [[table indexPathForSelectedRow] section]==1 &&
    [[table indexPathForSelectedRow] row]==0,@"Section insertion and row reorder preserve identity");
  source->sections_=[NSArray array];
  [adapter applySnapshot:[[[AICollectionSnapshot alloc] initWithSections:source->sections_] autorelease]]; pump();
  require(table->full_==full && [table numberOfSections]==0,@"Section deletion to empty is incremental");
  [adapter invalidate]; [adapter release]; [table setDataSource:nil]; [source release];
  [window setRootViewController:previous]; [previous release]; [controller release]; [table release];
}
