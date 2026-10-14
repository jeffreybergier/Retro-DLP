#import <AICollectionTableAdapter.h>
#import <AICollectionController.h>
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
@public NSArray *sections_; AICollectionController *loader_; AICollectionTableAdapter *adapter_;
}
@end
@implementation RDLPCollectionTestSource
- (void)receive:(NSDictionary *)result;
{
  require([NSThread isMainThread], @"Snapshot receipt and table update stay on main");
  if ([loader_ prepareResult:result snapshotKey:@"collection"
      previousSnapshot:[adapter_ snapshot]]) return;
  [sections_ release]; sections_ = [[result objectForKey:@"sections"] retain];
  [adapter_ applySnapshot:[result objectForKey:@"collection"]];
}
- (void)dealloc;
{ [loader_ invalidate]; [loader_ release]; [sections_ release]; [super dealloc]; }
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
static void applyCollection(RDLPCollectionTestSource *source,
                            AICollectionTableAdapter *adapter, NSArray *sections)
{
  source->adapter_ = adapter;
  if (!source->loader_) source->loader_ = [[AICollectionController alloc]
      initWithTarget:source selector:@selector(receive:) builder:Nil];
  AICollectionSnapshot *snapshot = [[[AICollectionSnapshot alloc]
      initWithSections:sections] autorelease];
  [source receive:[NSDictionary dictionaryWithObjectsAndKeys:
      sections, @"sections", snapshot, @"collection", nil]];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while ([source->loader_ isLoading] && [deadline timeIntervalSinceNow] > 0) pump();
  require(![source->loader_ isLoading], @"Worker diff completes before deadline");
  pump();
}
static void collectionTest(UIWindow *window)
{
  UIViewController *previous=[[window rootViewController] retain];
  UIViewController *controller=[[UIViewController alloc] init];
  RDLPCollectionTestTable *table=[[RDLPCollectionTestTable alloc] initWithFrame:[window bounds] style:UITableViewStylePlain];
  RDLPCollectionTestSource *source=[[RDLPCollectionTestSource alloc] init];
  [table setDataSource:source]; [controller setView:table]; [window setRootViewController:controller];
  AICollectionTableAdapter *adapter=[[AICollectionTableAdapter alloc] initWithTableView:table];
  NSArray *rows=[NSArray arrayWithObjects:@"a",@"b",@"c",nil];
  applyCollection(source,adapter,[NSArray arrayWithObject:collectionSection(@"main",rows)]);
  require(table->partial_==0,@"Initial snapshot does not schedule a second row reload");
  [table selectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
  NSUInteger full=table->full_;
  rows=[NSArray arrayWithObjects:@"x",@"a",@"b",nil];
  applyCollection(source,adapter,[NSArray arrayWithObject:collectionSection(@"main",rows)]);
  require(table->full_==full && table->inserted_==1 && table->removed_==1,@"Collection uses native row insert/delete");
  require([[table indexPathForSelectedRow] row]==2,@"Collection preserves selected identity");
  [table setContentInset:UIEdgeInsetsMake(64,0,0,0)];
  [table setContentOffset:CGPointZero animated:NO];
  NSUInteger partial=table->partial_;
  [[NSNotificationCenter defaultCenter] postNotificationName:AIPagedRowsDidLoadNotification object:rows
    userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0] forKey:@"offset"]]; pump();
  require(table->full_==full && table->partial_>partial,@"Page arrival reloads rows without reloading table");
  require(CGPointEqualToPoint([table contentOffset],CGPointZero),@"Page refresh preserves deliberate offset in short inset table");
  applyCollection(source,adapter,source->sections_);
  require(CGPointEqualToPoint([table contentOffset],CGPointZero),@"Unchanged snapshot preserves deliberate offset in short inset table");
  applyCollection(source,adapter,[NSArray arrayWithObjects:collectionSection(@"new",[NSArray arrayWithObject:@"z"]),
    collectionSection(@"main",[NSArray arrayWithObjects:@"b",@"a",nil]),nil]);
  require(table->full_==full && [table numberOfSections]==2 && [[table indexPathForSelectedRow] section]==1 &&
    [[table indexPathForSelectedRow] row]==0,@"Section insertion and row reorder preserve identity");
  applyCollection(source,adapter,[NSArray array]);
  require(table->full_==full && [table numberOfSections]==0,@"Section deletion to empty is incremental");
  [adapter invalidate]; [adapter release]; [table setDataSource:nil]; [source release];
  [window setRootViewController:previous]; [previous release]; [controller release]; [table release];
}

#import <AICollectionTableViewController.h>
@interface RDLPCollectionForm : AICollectionTableViewController {
@public NSArray *ids_; UITextField *field_;
}
@end
@implementation RDLPCollectionForm
- (void)loadView;
{
  RDLPCollectionTestTable *table = [[[RDLPCollectionTestTable alloc]
      initWithFrame:CGRectMake(0,0,320,480) style:UITableViewStylePlain] autorelease];
  [self setTableView:table]; [table setDataSource:self]; [table setDelegate:self];
  field_ = [[UITextField alloc] initWithFrame:CGRectMake(15,0,200,44)];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{ (void)table; (void)section; return [ids_ count]; }
- (NSArray *)collectionIdentifiersForSection:(NSInteger)section;
{ (void)section; return ids_; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path;
{
  (void)table;
  UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
  if ([[ids_ objectAtIndex:[path row]] isEqual:@"field"]) [[cell contentView] addSubview:field_];
  else [[cell textLabel] setText:[ids_ objectAtIndex:[path row]]];
  return cell;
}
- (void)dealloc; { [field_ release]; [super dealloc]; }
@end
static void formCollectionTest(UIWindow *window)
{
  UIViewController *previous = [[window rootViewController] retain];
  RDLPCollectionForm *form = [[RDLPCollectionForm alloc] initWithStyle:UITableViewStylePlain];
  form->ids_ = [NSArray arrayWithObjects:@"field",@"status",nil];
  [window setRootViewController:form]; [form refreshCollection]; pump();
  RDLPCollectionTestTable *table = (id)[form tableView];
  NSUInteger full = table->full_, partial = table->partial_;
  [form beginAppearanceTransition:NO animated:NO]; [form endAppearanceTransition];
  [form beginAppearanceTransition:YES animated:NO]; [form endAppearanceTransition]; pump();
  require(table->full_==full && table->partial_==partial,@"Collection controller appearance does not reload content");
  [form->field_ setText:@"unsaved value"]; [form->field_ becomeFirstResponder]; pump();
  [[form collectionTableAdapter] refreshVisibleRows]; pump();
  require([form->field_ isFirstResponder] && [[form->field_ text] isEqual:@"unsaved value"],@"Content refresh preserves active field and text");
  [form->field_ resignFirstResponder];
  form->ids_ = [NSArray arrayWithObjects:@"field",@"inserted",@"status",nil];
  [form refreshCollection]; pump();
  require(table->full_ == full + 1 && [table numberOfRowsInSection:0] == 3,@"Immediate form mutation reloads safely without a main-thread diff");
  [window setRootViewController:previous]; [previous release]; [form release];
}
