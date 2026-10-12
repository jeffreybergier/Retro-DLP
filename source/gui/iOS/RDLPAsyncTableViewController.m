#import "RDLPAsyncTableViewController.h"
@implementation RDLPAsyncTableViewController
- (id)initWithStyle:(UITableViewStyle)style;
{
  self=[super initWithStyle:style];
  if(self) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pageLoaded:) name:AIPagedRowsDidLoadNotification object:nil];
  if(self) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryClosed:) name:RDLPLibraryWillClose object:nil];
  return self;
}
- (void)libraryClosed:(NSNotification *)note;
{
  if([note object]!=[[self listRequest] objectForKey:@"library"]) return;
  listClosed_=YES; listSuspended_=YES; [self discardList]; [sections_ release]; sections_=nil;
}
- (void)dealloc;
{
  [self discardList]; [sections_ release];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self]; [super dealloc];
}
- (NSDictionary *)listRequest;
{ [self doesNotRecognizeSelector:_cmd]; return nil; }
- (BOOL)canApplyList; { return !listSuspended_ && !listClosed_; }
- (void)refreshStatus:(id)sender; { (void)sender; }
- (void)refresh:(id)sender;
{
  (void)sender; if(![self isViewLoaded] || ![self canApplyList]) return;
  [self requestList]; [self refreshStatus:nil];
}
- (void)viewWillAppear:(BOOL)animated;
{ listSuspended_=NO; [super viewWillAppear:animated]; }
- (void)viewWillDisappear:(BOOL)animated;
{
  listSuspended_=YES; [self discardList]; [sections_ release]; sections_=nil;
  [super viewWillDisappear:animated];
}
- (NSDictionary *)rowAtIndex:(NSIndexPath *)index;
{
  if(!index || (NSUInteger)[index section]>=[sections_ count]) return nil;
  return [[[sections_ objectAtIndex:(NSUInteger)[index section]] objectForKey:@"rows"] RDLP_requestRow:(NSUInteger)[index row]];
}
- (NSIndexPath *)tableView:(UITableView *)table willSelectRowAtIndexPath:(NSIndexPath *)index;
{
  (void)table;
  return [[[self rowAtIndex:index] objectForKey:@"action"] isEqualToString:@"placeholder"]?nil:index;
}
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)index;
{
  (void)table; BOOL loading=[[[self rowAtIndex:index] objectForKey:@"action"] isEqualToString:@"placeholder"];
  [cell setUserInteractionEnabled:!loading];
  if(loading) { [cell setAccessoryType:UITableViewCellAccessoryNone]; [cell setAccessoryView:nil]; }
}
- (NSString *)identityAtIndex:(NSIndexPath *)index;
{
  if(!index || (NSUInteger)[index section]>=[sections_ count]) return nil;
  NSArray *rows=[[sections_ objectAtIndex:(NSUInteger)[index section]] objectForKey:@"rows"];
  if(![rows respondsToSelector:@selector(cachedObjectAtIndex:)]) return nil;
  NSDictionary *row=[(RDLPLibraryRows *)rows cachedObjectAtIndex:(NSUInteger)[index row]];
  NSDictionary *video=[row objectForKey:@"video"], *job=[row objectForKey:@"job"];
  BOOL playlist=[[[self listRequest] objectForKey:@"mode"] intValue]==RDLPScreenPlaylist;
  return playlist?[video objectForKey:@"position"]:([job objectForKey:@"id"]?:[[row objectForKey:@"playlist"] objectForKey:@"id"]);
}
- (void)requestList;
{
  if(!listLoader_) listLoader_=[[RDLPListLoader alloc] initWithTarget:self builder:[RDLPLibrarySections class]];
  NSMutableDictionary *input=[NSMutableDictionary dictionaryWithDictionary:[self listRequest]];
  NSIndexPath *top=[[[self tableView] indexPathsForVisibleRows] count]?[[[self tableView] indexPathsForVisibleRows] objectAtIndex:0]:nil;
  NSString *anchor=[self identityAtIndex:top];
  if(anchor) [input setObject:anchor forKey:@"anchor"];
  else if(top && (NSUInteger)[top section]<[sections_ count]) {
    [input setObject:[[sections_ objectAtIndex:(NSUInteger)[top section]] objectForKey:@"rows"] forKey:@"anchorRows"];
    [input setObject:[NSNumber numberWithInteger:[top row]] forKey:@"anchorRow"];
  }
  CGFloat delta=top?[[self tableView] contentOffset].y-[[self tableView] rectForRowAtIndexPath:top].origin.y:0;
  [input setObject:[NSNumber numberWithDouble:delta] forKey:@"delta"];
  NSString *selection=[self identityAtIndex:[[self tableView] indexPathForSelectedRow]];
  if(selection && ![input objectForKey:@"selection"]) [input setObject:selection forKey:@"selection"];
  [listLoader_ request:input];
}
- (void)discardList;
{
  [listLoader_ invalidate]; [listLoader_ release]; listLoader_=nil;
  NSEnumerator *e=[sections_ objectEnumerator]; NSDictionary *section;
  while((section=[e nextObject])) [[section objectForKey:@"rows"] RDLP_invalidateRows];
}
- (void)pageLoaded:(NSNotification *)note;
{
  NSEnumerator *e=[sections_ objectEnumerator]; NSDictionary *section;
  while((section=[e nextObject])) if([[section objectForKey:@"rows"] RDLP_containsRows:[note object]]) {
    id error=[[note userInfo] objectForKey:@"error"];
    if(error && error!=[NSNull null]) [[[self listRequest] objectForKey:@"library"] reportListError:[error localizedDescription]];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadPages:) object:nil];
    [self performSelector:@selector(reloadPages:) withObject:nil afterDelay:0]; break;
  }
}
- (void)reloadPages:(id)ignored;
{
  (void)ignored; if(![self canApplyList]) return;
  CGPoint offset=[[self tableView] contentOffset];
  NSIndexPath *selection=[[self tableView] indexPathForSelectedRow];
  [[self tableView] reloadData]; [[self tableView] setContentOffset:offset animated:NO];
  if(selection) [[self tableView] selectRowAtIndexPath:selection animated:NO scrollPosition:UITableViewScrollPositionNone];
}
- (void)didLoadList:(NSDictionary *)result;
{
  if(![self canApplyList]) return;
  if([result objectForKey:@"error"]) { [[[self listRequest] objectForKey:@"library"] reportListError:[result objectForKey:@"error"]]; return; }
  NSEnumerator *e=[sections_ objectEnumerator]; NSDictionary *section;
  while((section=[e nextObject])) [[section objectForKey:@"rows"] RDLP_invalidateRows];
  [sections_ release]; sections_=[[result objectForKey:@"sections"] retain];
  [[self tableView] reloadData];
  NSArray *anchor=[result objectForKey:@"anchorIndex"], *selection=[result objectForKey:@"selectionIndex"];
  if(anchor) {
    NSIndexPath *index=[NSIndexPath indexPathForRow:[[anchor objectAtIndex:1] integerValue] inSection:[[anchor objectAtIndex:0] integerValue]];
    CGPoint offset=[[self tableView] contentOffset]; offset.y=[[self tableView] rectForRowAtIndexPath:index].origin.y+[[result objectForKey:@"delta"] doubleValue];
    [[self tableView] setContentOffset:offset animated:NO];
  }
  if(selection) [[self tableView] selectRowAtIndexPath:[NSIndexPath indexPathForRow:[[selection objectAtIndex:1] integerValue] inSection:[[selection objectAtIndex:0] integerValue]] animated:NO scrollPosition:UITableViewScrollPositionNone];
  [self refreshStatus:nil];
}
@end
