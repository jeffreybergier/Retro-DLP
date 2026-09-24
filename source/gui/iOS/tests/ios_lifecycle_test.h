/* Real scheduler and delegate, with only the worker and OS task grant faked.
   No network requests or production-library access. */
#include <sys/xattr.h>
#include <pthread.h>
@interface RDLPAppDelegate (LifecycleTesting)
- (void)activityChanged:(id)sender;
- (void)backgroundTimeExpired;
- (UIBackgroundTaskIdentifier)beginBackgroundTask;
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)task;
- (void)downloadCompleted:(NSNotification *)notification;
- (void)presentDownloadNotification:(UILocalNotification *)notification;
@end
@interface RDLPBackgroundTestDelegate : RDLPAppDelegate {
@public
  NSUInteger starts_, ends_;
  BOOL deny_;
  NSMutableArray *notifications_;
}
@end
@implementation RDLPBackgroundTestDelegate
- (id)init;
{ self=[super init]; if(self) notifications_=[[NSMutableArray alloc] init]; return self; }
- (void)dealloc;
{ [notifications_ release]; [super dealloc]; }
- (void)presentDownloadNotification:(UILocalNotification *)notification;
{
  statusRequire([NSThread isMainThread],@"Deliver local notifications on the main thread");
  statusRequire(starts_>ends_,@"Deliver before releasing background execution");
  [notifications_ addObject:notification];
}
- (UIBackgroundTaskIdentifier)beginBackgroundTask;
{ ++starts_; return deny_?UIBackgroundTaskInvalid:starts_; }
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)task;
{ statusRequire(task!=UIBackgroundTaskInvalid,@"Never end an invalid task"); ++ends_; }
@end
@interface RDLPActivityTestLibrary : RDLPLibrary {
@public
  NSUInteger workers_;
}
@end
@implementation RDLPActivityTestLibrary
- (void)workerStarted:(NSNumber *)stackSize;
{
  statusRequire([stackSize unsignedLongLongValue]>=2U*1024U*1024U,
    @"Native worker stack accommodates QuickJS's 1 MiB limit and native calls");
  ++workers_;
}
- (void)work:(NSDictionary *)command;
{
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  (void)command;
  NSNumber *stackSize=[NSNumber numberWithUnsignedLongLong:pthread_get_stacksize_np(pthread_self())];
  [self performSelectorOnMainThread:@selector(workerStarted:) withObject:stackSize waitUntilDone:NO];
  [pool drain];
  /* The test explicitly delivers completion, exercising the real scheduler. */
}
@end
static void waitForWorker(RDLPActivityTestLibrary *library,NSUInteger count) {
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
  while(library->workers_<count && [deadline timeIntervalSinceNow]>0) statusWait(0.01);
  statusRequire(library->workers_==count,@"Expected worker starts without networking");
}
static NSDictionary *activityResult(rdlp_error_code code) {
  return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:code],@"code",@"Synthetic result",@"message",nil];
}
static void testIOSLifecycle(NSString *base) {
  [[NSFileManager defaultManager] removeItemAtPath:base error:NULL];
  NSString *downloads=[base stringByAppendingPathComponent:@"Downloads"];
  NSString *support=[base stringByAppendingPathComponent:@"Support"];
  [[NSFileManager defaultManager] createDirectoryAtPath:downloads withIntermediateDirectories:YES attributes:nil error:NULL];
  NSString *existing=[downloads stringByAppendingPathComponent:@"existing.mp4"];
  statusRequire([@"existing media" writeToFile:existing atomically:YES encoding:NSUTF8StringEncoding error:NULL],@"Create pre-upgrade media");
  RDLPActivityTestLibrary *library=[[RDLPActivityTestLibrary alloc] initWithSupportDirectory:support downloadDirectory:downloads];
  statusRequire(library!=nil,@"Open lifecycle fixture");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
  if(kCFCoreFoundationVersionNumber>=kCFCoreFoundationVersionNumber_iOS_5_1) {
    NSNumber *excluded=nil,*supportExcluded=nil;
    statusRequire([[NSURL fileURLWithPath:downloads] getResourceValue:&excluded forKey:NSURLIsExcludedFromBackupKey error:NULL] && [excluded boolValue],@"Media parent is excluded from backup");
    [[NSURL fileURLWithPath:support] getResourceValue:&supportExcluded forKey:NSURLIsExcludedFromBackupKey error:NULL];
    statusRequire(![supportExcluded boolValue],@"Library metadata remains eligible for backup");
  } else {
    unsigned char value=0;
    statusRequire(getxattr([downloads fileSystemRepresentation],"com.apple.MobileBackup",&value,sizeof(value),0,0)==1 && value==1,@"Legacy backup attribute is present");
  }
#pragma clang diagnostic pop
  statusRequire([[NSString stringWithContentsOfFile:existing encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"existing media"],@"Backup migration preserves existing media");
  RDLPBackgroundTestDelegate *delegate=[[RDLPBackgroundTestDelegate alloc] init];
  [delegate setValue:library forKey:@"library_"];
  [[NSNotificationCenter defaultCenter] addObserver:delegate selector:@selector(activityChanged:) name:RDLPLibraryActivityDidChange object:library];
  /* Launch reconciliation, playlist sync and discovery share the same lease. */
  NSMutableArray *commands=[library valueForKey:@"commands_"];
  [commands addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"sync",@"type",@"PLfixture",@"input",nil]];
  [commands addObject:[NSDictionary dictionaryWithObject:@"discover" forKey:@"type"]];
  [library startDownloads]; waitForWorker(library,1);
  statusRequire([library operationCount]==1 && delegate->starts_==1,@"First operation requests background time before completion");
  [delegate applicationDidEnterBackground:[UIApplication sharedApplication]];
  statusRequire(![library cancelled] && ![library isPaused],@"Backgrounding does not cancel active work");
  [library finished:activityResult(RDLP_OK)]; waitForWorker(library,2);
  statusRequire([library operationCount]==1 && delegate->starts_==1 && delegate->ends_==0,@"Reconciliation hands off without releasing background time");
  [library finished:activityResult(RDLP_ERROR_STORAGE_IO)]; waitForWorker(library,3);
  statusRequire([library operationCount]==1 && delegate->ends_==0,@"Failure balances its reference while discovery proceeds");
  [library finished:activityResult(RDLP_OK)];
  statusRequire([library operationCount]==0 && delegate->ends_==1,@"Last completion releases background time exactly once");
  /* Overlapping references must not release the grant early. */
  [library beginOperation]; [library beginOperation]; [library endOperation];
  statusRequire([library operationCount]==1 && delegate->starts_==2 && delegate->ends_==1,@"An outstanding reference retains the background task");
  [library endOperation];
  statusRequire(delegate->ends_==2,@"Balanced nested operations release the task");
  [commands addObject:[NSDictionary dictionaryWithObject:@"sync" forKey:@"type"]];
  [commands addObject:[NSDictionary dictionaryWithObject:@"discover" forKey:@"type"]];
  [library startDownloads]; waitForWorker(library,4);
  [delegate backgroundTimeExpired]; [delegate backgroundTimeExpired];
  statusRequire([library cancelled] && delegate->ends_==3,@"Expiration cancels non-download work and ends its task once");
  [library finished:activityResult(RDLP_ERROR_CANCELLED)]; statusWait(0.05);
  statusRequire([library operationCount]==0 && library->workers_==4 && [commands count]==1,@"Expired background time blocks all queued worker types");
  [delegate applicationWillEnterForeground:[UIApplication sharedApplication]]; waitForWorker(library,5);
  statusRequire(![library cancelled] && delegate->starts_==4,@"Foreground resumes queued requests with a fresh task");
  [library finished:activityResult(RDLP_OK)];
  /* A denied background task cancels the operation and never ends an invalid ID. */
  delegate->deny_=YES; [delegate applicationDidEnterBackground:[UIApplication sharedApplication]];
  [commands addObject:[NSDictionary dictionaryWithObject:@"sync" forKey:@"type"]];
  [library startDownloads]; waitForWorker(library,6);
  statusRequire([library cancelled],@"Denied background execution cancels work");
  [library finished:activityResult(RDLP_ERROR_CANCELLED)];
  statusRequire([library operationCount]==0 && delegate->ends_==4,@"Denied grants do not leak references or end invalid tasks");
  delegate->deny_=NO;
  [delegate applicationWillEnterForeground:[UIApplication sharedApplication]];
  [commands addObject:[NSDictionary dictionaryWithObject:@"sync" forKey:@"type"]];
  [library startDownloads]; waitForWorker(library,7);
  [delegate applicationWillTerminate:[UIApplication sharedApplication]];
  [library finished:activityResult(RDLP_ERROR_CANCELLED)];
  statusRequire([library operationCount]==0 && delegate->ends_==5,@"Shutdown and late completion do not double-end a task");
  [[NSNotificationCenter defaultCenter] removeObserver:delegate];
  [delegate release]; [library release];
}

static void testIOSDownloadNotifications(NSString *base) {
  [[NSFileManager defaultManager] removeItemAtPath:base error:NULL];
  NSString *support=[base stringByAppendingPathComponent:@"Support"];
  RDLPActivityTestLibrary *library=[[RDLPActivityTestLibrary alloc] initWithSupportDirectory:support downloadDirectory:[base stringByAppendingPathComponent:@"Downloads"]];
  statusRequire(library!=nil,@"Open notification fixture");
  RDLPBackgroundTestDelegate *delegate=[[RDLPBackgroundTestDelegate alloc] init];
  [delegate setValue:library forKey:@"library_"];
  [[NSNotificationCenter defaultCenter] addObserver:delegate selector:@selector(activityChanged:) name:RDLPLibraryActivityDidChange object:library];
  [[NSNotificationCenter defaultCenter] addObserver:delegate selector:@selector(downloadCompleted:) name:RDLPLibraryDownloadDidComplete object:library];
  [delegate applicationDidEnterBackground:[UIApplication sharedApplication]];
  [library startDownloads]; waitForWorker(library,1);
  [library finished:activityResult(RDLP_OK)];
  statusRequire(![delegate->notifications_ count],@"Reconciliation never sends a download alert");

  /* The real scheduler claims each job. Only network work is replaced; use
     persisted titles/states so Ad-Hoc metadata changes are covered too. */
  rdapp_store *store=NULL;
  statusRequire(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open notification fixture writer");
  const char *videos[]={"ABCDEFGHIJK","BCDEFGHIJKL","CDEFGHIJKLM","DEFGHIJKLMN","EFGHIJKLMNO","FGHIJKLMNOP"};
  const char *states[]={"complete","complete","failed","cancelled","running","complete"};
  rdlp_error_code codes[]={RDLP_OK,RDLP_OK,RDLP_ERROR_STORAGE_IO,RDLP_ERROR_CANCELLED,RDLP_OK,RDLP_OK};
  for(NSUInteger i=0;i<6;++i) {
    if(i==1) [delegate applicationWillEnterForeground:[UIApplication sharedApplication]];
    if(i==2) [delegate applicationDidEnterBackground:[UIApplication sharedApplication]];
    statusRequire(rdapp_store_add_adhoc_download(store,videos[i],NULL,"18",NULL),@"Queue notification fixture");
    [library startDownloads]; waitForWorker(library,i+2);
    NSDictionary *command=[library valueForKey:@"activeCommand_"];
    long long job=[[[command objectForKey:@"job"] objectForKey:@"id"] longLongValue];
    char path[1024];
    statusRequire(rdapp_store_resolve_job(store,job,"Alice's Video 日本語",path,sizeof(path)),@"Persist resolved title after the worker starts");
    statusRequire(rdapp_store_finish(store,job,states[i],"18",""),@"Persist download outcome");
    [library finished:activityResult(codes[i])];
    statusRequire([delegate->notifications_ count]==(i==5?2:1),@"Only successful, persisted background downloads send alerts");
    statusRequire([library operationCount]==0,@"Notification completion balances execution time");
  }
  UILocalNotification *alert=[delegate->notifications_ objectAtIndex:0];
  statusRequire([alert.alertBody isEqualToString:@"Download Complete 'Alice's Video 日本語'"],@"Alert uses exact wording and the resolved Unicode title");
  statusRequire([alert.soundName isEqualToString:UILocalNotificationDefaultSoundName],@"Completion uses the default notification sound");
  [delegate applicationWillEnterForeground:[UIApplication sharedApplication]];
  statusRequire([delegate->notifications_ count]==2,@"Foreground return does not repeat completion alerts");
  rdapp_store_close(store);
  [[NSNotificationCenter defaultCenter] removeObserver:delegate];
  [delegate release]; [library release];
}
