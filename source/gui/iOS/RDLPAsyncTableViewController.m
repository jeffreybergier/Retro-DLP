#import "RDLPAsyncTableViewController.h"
@implementation RDLPAsyncTableViewController
- (id)initWithStyle:(UITableViewStyle)style;
{
  self=[super initWithStyle:style];
  if(self) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(collectionReadFailed:) name:AICollectionReadFailedNotification object:nil];
  if(self) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryClosed:) name:RDLPLibraryWillClose object:nil];
  return self;
}
- (void)libraryClosed:(NSNotification *)note;
{
  if([note object]!=[[self listRequest] objectForKey:@"library"]) return;
  listClosed_=YES; [self discardList]; [sections_ release]; sections_=nil;
}
- (void)dealloc;
{
  [self discardList]; [sections_ release];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self]; [super dealloc];
}
- (NSDictionary *)listRequest;
{ [self doesNotRecognizeSelector:_cmd]; return nil; }
- (BOOL)canApplyList; { return !listClosed_; }
- (void)refreshStatus:(id)sender; { (void)sender; }
- (void)refresh:(id)sender;
{
  (void)sender; if(![self isViewLoaded] || ![self canApplyList]) return;
  [self requestList]; [self refreshStatus:nil];
}
- (void)viewDidUnload;
{
  /* iOS 5 can dispose the table under memory pressure. Its borrowed adapter
   * must go with it; the next viewDidLoad prepares a fresh initial snapshot. */
  [self discardList]; [sections_ release]; sections_=nil;
  [super viewDidUnload];
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
  if (![input objectForKey:@"explicitSelection"] && [[input objectForKey:@"selection"] length])
    [input setObject:[NSNumber numberWithBool:YES] forKey:@"explicitSelection"];
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
  if(!sections_) [self didLoadList:[listLoader_ buildResultForRequest:input]];
  else [listLoader_ request:input];
}
- (void)discardList;
{
  [collectionAdapter_ invalidate]; [collectionAdapter_ release]; collectionAdapter_=nil;
  [listLoader_ invalidate]; [listLoader_ release]; listLoader_=nil;
  NSEnumerator *e=[sections_ objectEnumerator]; NSDictionary *section;
  while((section=[e nextObject])) [[section objectForKey:@"rows"] RDLP_invalidateRows];
}
- (void)collectionReadFailed:(NSNotification *)note;
{
  if([note object]!=collectionAdapter_) return;
  [[[self listRequest] objectForKey:@"library"] reportListError:
    [[[note userInfo] objectForKey:@"error"] localizedDescription]];
}
- (void)didLoadList:(NSDictionary *)result;
{
  if(![self canApplyList]) return;
  id error = [result objectForKey:@"error"];
  if (error) {
    NSString *message = [error isKindOfClass:[NSError class]] ?
        [error localizedDescription] : error;
    [[[self listRequest] objectForKey:@"library"] reportListError:message];
    return;
  }
  if ([listLoader_ prepareResult:result snapshotKey:@"collection"
      previousSnapshot:[collectionAdapter_ snapshot]]) return;
  NSEnumerator *e=[sections_ objectEnumerator]; NSDictionary *section;
  while((section=[e nextObject])) [[section objectForKey:@"rows"] RDLP_invalidateRows];
  [sections_ release]; sections_=[[result objectForKey:@"sections"] retain];
  BOOL restoreFallback=![[collectionAdapter_ snapshot] hasCompleteIdentities] ||
    ![[result objectForKey:@"collection"] hasCompleteIdentities];
  if(!collectionAdapter_) collectionAdapter_=[[AICollectionTableAdapter alloc] initWithTableView:[self tableView]];
  [collectionAdapter_ applySnapshot:[result objectForKey:@"collection"]];
  NSArray *anchor=[result objectForKey:@"anchorIndex"], *selection=[result objectForKey:@"selectionIndex"];
  if(restoreFallback && anchor) {
    NSIndexPath *index=[NSIndexPath indexPathForRow:[[anchor objectAtIndex:1] integerValue] inSection:[[anchor objectAtIndex:0] integerValue]];
    CGPoint offset=[[self tableView] contentOffset]; offset.y=[[self tableView] rectForRowAtIndexPath:index].origin.y+[[result objectForKey:@"delta"] doubleValue];
    [[self tableView] setContentOffset:offset animated:NO];
  }
  if((restoreFallback || [[result objectForKey:@"explicitSelection"] boolValue]) && selection) [[self tableView] selectRowAtIndexPath:[NSIndexPath indexPathForRow:[[selection objectAtIndex:1] integerValue] inSection:[[selection objectAtIndex:0] integerValue]] animated:NO scrollPosition:UITableViewScrollPositionNone];
  [self refreshStatus:nil];
}
@end
