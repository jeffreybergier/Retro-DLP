#import "../RDLPVideoRows.h"
#import "../rdapp_store.h"

@interface RDLPCountingFilePolicy : RDLPDownloadPolicy { @public NSUInteger probes; }
@end
@implementation RDLPCountingFilePolicy
- (NSDictionary *)localFileForJob:(NSDictionary *)job;
{ ++probes; return [super localFileForJob:job]; }
@end

@interface RDLPTestVideoRows : RDLPVideoRows
- (void)setTestPolicy:(RDLPDownloadPolicy *)policy;
@end
@implementation RDLPTestVideoRows
- (void)setTestPolicy:(RDLPDownloadPolicy *)policy;
{ [policy retain]; [policy_ release]; policy_=policy; }
@end

static void testSharedVideoRows(NSString *base) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSString *support=[base stringByAppendingPathComponent:@"Support"], *downloads=[base stringByAppendingPathComponent:@"Downloads"];
  RDLPLibrary *library=[[RDLPLibrary alloc] initWithSupportDirectory:support downloadDirectory:downloads];
  metadataRequire(library!=nil,@"Open shared row fixture");
  rdapp_store *store=NULL; int64_t key=0;
  metadataRequire(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open shared row store");
  rdapp_entry entries[2]; memset(entries,0,sizeof(entries));
  entries[0].video_id=entries[1].video_id="AAAAAAAAAAA";
  entries[0].title=entries[1].title="Shared video";
  entries[0].channel="First channel"; entries[0].duration=754; entries[0].has_duration=1;
  entries[1].position=1; entries[1].channel="Duplicate channel";
  metadataRequire(rdapp_store_snapshot(store,"PLrows","Rows",entries,2,&key),@"Save duplicate metadata");
  metadataRequire(rdapp_store_enqueue(store,key,"AAAAAAAAAAA","18"),@"Queue low quality");
  metadataRequire(rdapp_store_enqueue(store,key,"AAAAAAAAAAA","137+140"),@"Queue high quality");
  metadataRequire(rdapp_store_claim(store,NULL,NULL) && rdapp_store_claim(store,NULL,NULL),@"Assign download paths before publishing files");
  NSString *pid=[NSString stringWithFormat:@"%lld",(long long)key];
  NSArray *jobs=[library jobsForPlaylist:pid completedOnly:NO];
  NSEnumerator *e=[jobs objectEnumerator]; NSDictionary *job;
  while((job=[e nextObject])) {
    NSString *path=[library fileForJob:job];
    metadataRequire(rdapp_make_directory([[path stringByDeletingLastPathComponent] fileSystemRepresentation]),@"Create local file folder");
    NSUInteger bytes=[[job objectForKey:@"format"] isEqualToString:@"18"]?1500:1500000;
    metadataRequire([[NSMutableData dataWithLength:bytes] writeToFile:path atomically:YES],@"Write measured fixture file");
    metadataRequire(rdapp_store_finish(store,strtoll([[job objectForKey:@"id"] UTF8String],NULL,10),"complete",[[job objectForKey:@"format"] UTF8String],""),@"Complete measured file");
  }
  rdapp_store_close(store);
  RDLPLibraryRows *source=(RDLPLibraryRows *)[library entriesForPlaylist:pid];
  RDLPTestVideoRows *playlist=[[[RDLPTestVideoRows alloc] initWithRows:source library:library playlist:pid] autorelease];
  metadataRequire([playlist count]==2 && [source cachedObjectAtIndex:0]==nil,@"Counting display rows preserves on-demand loading");
  RDLPCountingFilePolicy *policy=[[[RDLPCountingFilePolicy alloc] initWithLibrary:library] autorelease];
  [playlist setTestPolicy:policy];
  NSDictionary *first=[playlist objectAtIndex:0];
  metadataRequire([[first objectForKey:@"detail"] isEqualToString:@"12:34 · 1.5 MB · High (137+140) · First channel"],@"Playlist combines metadata with representative file quality and bytes");
  metadataRequire([first objectForKey:@"accessibility_label"]!=nil && [[first objectForKey:@"tooltip"] rangeOfString:@"Local file: High (137+140) · 1.5 MB"].location!=NSNotFound,@"Shared accessibility and tooltip include local size");
  metadataRequire([playlist objectAtIndex:0]==first && policy->probes==1,@"Repeated row rendering reuses one filesystem probe");
  metadataRequire([source cachedObjectAtIndex:1]==nil,@"Displaying one row does not load the next occurrence");
  metadataRequire([[[playlist objectAtIndex:1] objectForKey:@"metadata_detail"] isEqualToString:@"Duplicate channel"],@"Duplicate occurrence metadata stays independent");
  NSArray *complete=[library jobsForPlaylist:pid completedOnly:YES];
  RDLPVideoRows *all=[[[RDLPVideoRows alloc] initWithRows:complete library:library playlist:nil] autorelease];
  metadataRequire([all count]==2 && [[[all objectAtIndex:0] objectForKey:@"detail"] isEqual:[first objectForKey:@"detail"]],@"All Downloads matches shared presentation and preserves both qualities");
  metadataRequire([[[all objectAtIndex:1] objectForKey:@"size"] isEqualToString:@"2 KB"],@"Each exact job reports its own file size");
  NSString *highPath=[[first objectForKey:@"local_file"] objectForKey:@"path"];
  metadataRequire([[NSFileManager defaultManager] removeItemAtPath:highPath error:NULL],@"Remove file after row snapshot");
  metadataRequire(![policy playable:[first objectForKey:@"job"]],@"Actions recheck a deleted file despite cached display");
  RDLPVideoRows *refreshed=[[[RDLPVideoRows alloc] initWithRows:complete library:library playlist:nil] autorelease];
  NSDictionary *missing=[refreshed objectAtIndex:0];
  metadataRequire(![[missing objectForKey:@"quality"] length] && ![[missing objectForKey:@"size"] length] && [[missing objectForKey:@"status"] isEqualToString:@"File missing"],@"Refresh removes quality and size for missing files");
  metadataRequire(rdapp_make_directory([highPath fileSystemRepresentation]),@"Replace file with directory");
  metadataRequire(![policy playable:[first objectForKey:@"job"]],@"A directory is not a playable local file");
  [[NSFileManager defaultManager] removeItemAtPath:highPath error:NULL];
  metadataRequire([[RDLPLibrary fileSizeLabelForBytes:0] isEqualToString:@"0 KB"] && [[RDLPLibrary fileSizeLabelForBytes:1] isEqualToString:@"1 KB"] && [[RDLPLibrary fileSizeLabelForBytes:999999] isEqualToString:@"1000 KB"] && [[RDLPLibrary fileSizeLabelForBytes:1000000] isEqualToString:@"1.0 MB"] && [[RDLPLibrary fileSizeLabelForBytes:5000000000ULL] isEqualToString:@"5000.0 MB"],@"Size labels preserve zero, unit boundaries, and 64-bit values");
  [library shutdown]; [library release]; [pool drain];
}
