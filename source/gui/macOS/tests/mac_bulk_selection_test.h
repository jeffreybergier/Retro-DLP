/* Offline AppKit regression: real store and controls, isolated file moves. */
@interface RDLPBulkTestLibrary : RDLPLibrary
@end
@implementation RDLPBulkTestLibrary
- (NSString *)removeDownloadFileAtPath:(NSString *)path;
{
  NSString *trash=[[self downloadsDirectory] stringByAppendingPathComponent:@"TestTrash"];
  if(!rdapp_make_directory([trash fileSystemRepresentation])) return @"Cannot create test Trash";
  return [[NSFileManager defaultManager] movePath:path
    toPath:[trash stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] handler:nil]?nil:@"Test Trash move failed";
}
@end

static void testBulkSelection(void) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSString *base=@"/tmp/retrodlp-toolbar-fixture/Bulk";
  NSString *support=[base stringByAppendingPathComponent:@"Support"];
  NSString *downloads=[base stringByAppendingPathComponent:@"Downloads"];
  NSString *savedFormat=[[RDLPLibrary preferredFormat] copy];
  [RDLPLibrary savePreferredFormat:@"18"];
  RDLPLibrary *library=[[RDLPBulkTestLibrary alloc] initWithSupportDirectory:support downloadDirectory:downloads];
  requireCondition(library!=nil,@"Open bulk fixture"); [library setPaused:YES];
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
  while([library isBusy] && [deadline timeIntervalSinceNow]>0) pump();
  requireCondition(![library isBusy],@"Bulk fixture startup finished");
  rdapp_store *store=NULL; int64_t playlistID=0;
  requireCondition(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open bulk store");
  rdapp_entry entries[4]; memset(entries,0,sizeof(entries));
  const char *videos[]={"AAAAAAAAAAA","BBBBBBBBBBB","AAAAAAAAAAA","CCCCCCCCCCC"};
  NSUInteger i;
  for(i=0;i<4;++i) { entries[i].video_id=videos[i]; entries[i].title=videos[i]; entries[i].position=(int)i; }
  requireCondition(rdapp_store_snapshot(store,"PLbulk","Bulk",entries,4,&playlistID),@"Create duplicate playlist occurrences");
  requireCondition(rdapp_store_enqueue(store,playlistID,videos[0],"18") &&
    rdapp_store_enqueue(store,playlistID,videos[0],"137+140") &&
    rdapp_store_enqueue(store,playlistID,videos[1],"18"),@"Create completed and failed download fixtures");
  for(i=0;i<3;++i) requireCondition(rdapp_store_claim(store,NULL,NULL),@"Assign fixture paths");
  NSString *pid=[NSString stringWithFormat:@"%lld",(long long)playlistID];
  NSEnumerator *jobs=[[library jobsForPlaylist:pid completedOnly:NO] objectEnumerator]; NSDictionary *job;
  while((job=[jobs nextObject])) {
    BOOL complete=[[job objectForKey:@"video_id"] isEqualToString:@"AAAAAAAAAAA"];
    if(complete) {
      NSString *path=[library fileForJob:job];
      requireCondition(rdapp_make_directory([[path stringByDeletingLastPathComponent] fileSystemRepresentation]),@"Create fixture media directory");
      requireCondition([[@"media" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES],@"Write fixture media");
    }
    requireCondition(rdapp_store_finish(store,strtoll([[job objectForKey:@"id"] UTF8String],NULL,10),complete?"complete":"failed",[[job objectForKey:@"format"] UTF8String],""),@"Set fixture job state");
  }
  RDLPLibraryWindowController *owner=[[RDLPLibraryWindowController alloc] initWithLibrary:library];
  [owner showWindow:nil]; [owner hideQueue:nil];
  selectRow(owner,@"sidebar_",1);
  NSTableView *table=[owner valueForKey:@"table_"];
  requireCondition([table allowsMultipleSelection],@"Video table supports multiple selection");
  NSIndexSet *all=[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,4)];
  [table selectRowIndexes:all byExtendingSelection:NO]; [owner tableWasUsed:table];
  [owner refresh:nil];
  requireCondition([[table selectedRowIndexes] isEqual:all],@"Refresh preserves every playlist occurrence");
  requireCondition([toolbarButton(owner,@"download") isDefaultEnabled] && [toolbarButton(owner,@"remove") isDefaultEnabled] && ![toolbarButton(owner,@"play") isDefaultEnabled],@"Mixed selection enables bulk download/delete, without first-row playback");
  NSMenu *menu=[owner menuForToolbarIdentifier:@"download"];
  invoke(owner,choice(menu,@"Download Videos"));
  requireCondition([[library jobsForPlaylist:pid completedOnly:NO] count]==4,@"Bulk download deduplicates occurrences and skips completed qualities");
  NSDictionary *failed=[library jobForPlaylist:pid video:@"BBBBBBBBBBB" format:@"18"];
  NSDictionary *newJob=[library jobForPlaylist:pid video:@"CCCCCCCCCCC" format:@"18"];
  NSString *failedID=[[failed objectForKey:@"id"] copy], *newID=[[newJob objectForKey:@"id"] copy];
  requireCondition([[failed objectForKey:@"state"] isEqual:@"queued"] && [[newJob objectForKey:@"state"] isEqual:@"queued"],@"Bulk download retries failed work and queues missing videos");
  requireCondition([[table selectedRowIndexes] isEqual:all] && ![[[owner valueForKey:@"queueWindow_"] window] isVisible],@"Bulk download retains selection and keeps Queue closed");
  requireCondition(![toolbarButton(owner,@"download") isDefaultEnabled],@"Completed/queued selection cannot download twice or implicitly cancel work");
  /* Native context-clicking within a group keeps it; outside replaces it. */
  NSIndexSet *group=[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,3)];
  [table selectRowIndexes:group byExtendingSelection:NO];
  for(i=0;i<2;++i) {
    NSUInteger row=i?3:1;
    NSPoint point=[table convertPoint:NSMakePoint(10,NSMidY([table rectOfRow:(NSInteger)row])) toView:nil];
    NSEvent *event=[NSEvent mouseEventWithType:NSRightMouseDown location:point modifierFlags:0 timestamp:0
      windowNumber:[[owner window] windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1];
    requireCondition([table menuForEvent:event]!=nil,@"Video context menu exists");
    requireCondition([[table selectedRowIndexes] isEqual:i?[NSIndexSet indexSetWithIndex:3]:group],@"Context menu respects selected group and unselected row");
  }
  [table selectRowIndexes:all byExtendingSelection:NO]; [owner tableWasUsed:table];
  [toolbarButton(owner,@"remove") performClick:nil]; pump();
  NSDictionary *request=[owner valueForKey:@"confirmationRequest_"];
  requireCondition([[request objectForKey:@"jobs"] count]==3,@"Bulk deletion snapshots unique representative downloads only");
  confirm(owner,NO);
  requireCondition([[[library jobForID:newID] objectForKey:@"state"] isEqual:@"queued"],@"Cancelling bulk deletion makes no changes");
  [toolbarButton(owner,@"remove") performClick:nil]; pump();
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:NO];
  requireCondition(rdapp_store_finish(store,strtoll([failedID UTF8String],NULL,10),"running","18",""),@"Make one confirmed job ineligible before accepting");
  confirm(owner,YES);
  requireCondition([[[library jobForID:failedID] objectForKey:@"state"] isEqual:@"running"],@"Bulk deletion rechecks current state and skips newly running jobs");
  requireCondition([[[library jobForID:newID] objectForKey:@"state"] isEqual:@"removed"],@"Bulk deletion removes snapshotted eligible jobs");
  NSDictionary *low=[library jobForPlaylist:pid video:@"AAAAAAAAAAA" format:@"18"];
  NSDictionary *high=[library jobForPlaylist:pid video:@"AAAAAAAAAAA" format:@"137+140"];
  requireCondition([[low objectForKey:@"state"] isEqual:@"complete"] && [[high objectForKey:@"state"] isEqual:@"removed"],@"Changed selection cannot retarget confirmation; other qualities remain");
  requireCondition([[library entriesForPlaylist:pid] count]==4,@"Bulk deletion preserves playlist membership and duplicates");
  requireCondition([[NSFileManager defaultManager] fileExistsAtPath:[library fileForJob:low]],@"Unselected quality remains on disk");
  requireCondition(rdapp_store_finish(store,strtoll([failedID UTF8String],NULL,10),"failed","18",""),@"Reset synthetic running state");
  /* Select All in All Downloads targets exact quality rows. */
  requireCondition(rdapp_store_retry(store,strtoll([[high objectForKey:@"id"] UTF8String],NULL,10)) && rdapp_store_claim(store,NULL,NULL),@"Prepare second completed quality");
  NSString *highPath=[library fileForJob:high];
  requireCondition([[@"high" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:highPath atomically:YES] &&
    rdapp_store_finish(store,strtoll([[high objectForKey:@"id"] UTF8String],NULL,10),"complete","137+140",""),@"Restore second quality for exact-job deletion");
  selectRow(owner,@"sidebar_",0); [table selectAll:nil]; [owner tableWasUsed:table];
  requireCondition([table numberOfSelectedRows]==2,@"Select All selects both completed quality rows");
  [toolbarButton(owner,@"remove") performClick:nil]; pump();
  requireCondition([[[owner valueForKey:@"confirmationRequest_"] objectForKey:@"jobs"] count]==2,@"All Downloads deletion captures both exact jobs");
  confirm(owner,YES);
  requireCondition([table numberOfRows]==0 && [table numberOfSelectedRows]==0,@"Deleting selected All Downloads rows clears vanished identities");
  requireCondition([[library entriesForPlaylist:pid] count]==4 && ![toolbarButton(owner,@"remove") isDefaultEnabled],@"Empty All Downloads preserves playlist entries and disables deletion");
  rdapp_store_close(store); [failedID release]; [newID release];
  [owner close]; [owner release]; [library shutdown]; [library release];
  [RDLPLibrary savePreferredFormat:savedFormat]; [savedFormat release]; [pool drain];
}
