#import "../RDLP_Foundation.h"
#import "../RDLPVideoRows.h"
#import "../RDLPDownloadSections.h"
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

static void testBatchedVideoRows(NSString *base) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSString *support=[base stringByAppendingPathComponent:@"Support"];
  RDLPLibrary *library=[[RDLPLibrary alloc] initWithSupportDirectory:support
      downloadDirectory:[base stringByAppendingPathComponent:@"Downloads"]];
  metadataRequire(library!=nil,@"Open batched row fixture");
  rdapp_store *store=NULL; int64_t key=0; NSUInteger i;
  metadataRequire(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open batch writer");
  rdapp_entry entries[34]; char ids[34][12]; memset(entries,0,sizeof(entries));
  for(i=0;i<34;++i) {
    snprintf(ids[i],sizeof(ids[i]),"B%010lu",(unsigned long)(i==1?0:i));
    entries[i].video_id=ids[i]; entries[i].title=i==1?"Duplicate occurrence":"Batch row";
    entries[i].position=(int)i;
  }
  metadataRequire(rdapp_store_snapshot(store,"PLbatch","Batch",entries,34,&key),@"Seed batch boundary and duplicate");
  metadataRequire(rdapp_store_enqueue(store,key,ids[0],"18") &&
      rdapp_store_enqueue(store,key,ids[0],"22") &&
      rdapp_store_enqueue(store,key,ids[33],"18"),@"Seed multiple qualities and off-page job");
  NSString *pid=[NSString stringWithFormat:@"%lld",(long long)key];
  metadataRequire(rdapp_store_claim(store,NULL,NULL) && rdapp_store_claim(store,NULL,NULL) &&
      rdapp_store_claim(store,NULL,NULL),@"Assign paths for representative-job fixtures");
  NSDictionary *oldest=[[library jobsForPlaylist:pid video:[NSString stringWithUTF8String:ids[0]]] lastObject];
  NSString *file=[library fileForJob:oldest];
  metadataRequire(rdapp_make_directory([[file stringByDeletingLastPathComponent] fileSystemRepresentation]) &&
      [[NSData dataWithBytes:"fixture" length:7] writeToFile:file atomically:YES],@"Publish older playable quality");
  metadataRequire(rdapp_store_finish(store,strtoll([[oldest objectForKey:@"id"] UTF8String],NULL,10),"complete","18",""),@"Complete older quality before snapshot");
  RDLPLibraryRows *source=(RDLPLibraryRows *)[library entriesForPlaylist:pid];
  NSArray *videos=[NSArray arrayWithObjects:[NSString stringWithUTF8String:ids[0]],
      [NSString stringWithUTF8String:ids[0]],[NSString stringWithUTF8String:ids[2]],nil];
  NSDictionary *batch=[source jobsByVideoForPlaylist:pid videos:videos];
  metadataRequire([batch count]==1 && [[batch objectForKey:[videos objectAtIndex:0]] count]==2,@"Batch groups qualities and deduplicates IDs, omitting empty/off-page results");
  metadataRequire(rdapp_store_enqueue(store,key,ids[0],"137+140"),@"Write after read snapshot");
  metadataRequire([[source jobsByVideoForPlaylist:pid videos:videos] isEqual:batch],@"Batch remains in original read snapshot during writes");
  RDLPTestVideoRows *display=[[[RDLPTestVideoRows alloc] initWithRows:source library:library playlist:pid] autorelease];
  RDLPDownloadPolicy *policy=[[[RDLPDownloadPolicy alloc] initWithLibrary:library] autorelease];
  for(i=0;i<32;++i) {
    NSDictionary *entry=[source objectAtIndex:i];
    NSArray *jobs=[source jobsForPlaylist:pid video:[entry objectForKey:@"video_id"]];
    NSDictionary *expected=[policy representativeJobForEntry:entry playlist:pid jobs:jobs];
    NSDictionary *actual=[[display objectAtIndex:i] objectForKey:@"job"];
    metadataRequire(actual==expected || [actual isEqual:expected],@"Batched representative matches legacy per-video policy");
  }
  metadataRequire([[[display objectAtIndex:1] objectForKey:@"title"] isEqualToString:@"Duplicate occurrence"] &&
      [display cachedObjectAtIndex:32]==nil && [source cachedObjectAtIndex:32]==nil,@"Duplicate text and page boundaries remain intact");
  for(i=0;i<130;++i) {
    char format[16]; snprintf(format,sizeof(format),"%lu",(unsigned long)i+1000);
    metadataRequire(rdapp_store_enqueue(store,key,ids[0],format),@"Seed overflow qualities");
  }
  RDLPLibraryRows *fresh=(RDLPLibraryRows *)[library entriesForPlaylist:pid];
  metadataRequire([fresh jobsByVideoForPlaylist:pid videos:videos]==nil && ![fresh readError],@"Oversized batch requests fallback without a read error");
  RDLPVideoRows *overflow=[[[RDLPVideoRows alloc] initWithRows:fresh library:library playlist:pid] autorelease];
  NSDictionary *entry=[fresh objectAtIndex:0];
  NSDictionary *expected=[policy representativeJobForEntry:entry playlist:pid
      jobs:[fresh jobsForPlaylist:pid video:[entry objectForKey:@"video_id"]]];
  metadataRequire([[[overflow objectAtIndex:0] objectForKey:@"job"] isEqual:expected] &&
      [[expected objectForKey:@"id"] isEqual:[oldest objectForKey:@"id"]],@"Overflow fallback preserves older playable quality beyond the batch limit");
  metadataRequire(rdapp_store_add_adhoc_download(store,"C0000000000","Sectioned video","18",&key),@"Seed sectioned Added Videos");
  NSString *adhoc=[NSString stringWithFormat:@"%lld",(long long)key];
  RDLPLibraryRows *added=[library addedVideos];
  RDLPDownloadSections *groups=[[[RDLPDownloadSections alloc] initWithRows:added
      date:[NSDate date] calendar:[NSCalendar currentCalendar]] autorelease];
  NSArray *table=[groups tableRows:added];
  NSArray *slice=[[[groups sectionsWithRows:added] objectAtIndex:0] objectForKey:@"rows"];
  RDLPVideoRows *sectioned=[[[RDLPVideoRows alloc] initWithRows:table library:library playlist:adhoc] autorelease];
  RDLPVideoRows *sliced=[[[RDLPVideoRows alloc] initWithRows:slice library:library playlist:adhoc] autorelease];
  metadataRequire([[[sectioned objectAtIndex:0] objectForKey:@"action"] isEqual:@"section"] &&
      [[[sectioned objectAtIndex:1] objectForKey:@"job"] isEqual:[[sliced objectAtIndex:0] objectForKey:@"job"]],@"Header and slice wrappers forward batches within their snapshot");
  rdapp_store_close(store); [library shutdown]; [library release]; [pool drain];
}

static void testSharedVideoRows(NSString *base) {
  testBatchedVideoRows([base stringByAppendingPathComponent:@"Batch"]);
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSArray *formats=[RDLPLibrary qualityFormats];
  NSArray *labels=[NSArray arrayWithObjects:@"Low",@"Med",@"High",nil];
  NSUInteger i;
  for(i=0;i<[formats count];++i) {
    NSString *format=[formats objectAtIndex:i];
    metadataRequire([[RDLPLibrary qualityLabelForFormat:format] isEqualToString:[labels objectAtIndex:i]],@"Compact presets omit fallback expressions");
    metadataRequire([[RDLPLibrary qualityDetailForFormat:format] rangeOfString:format].location!=NSNotFound,@"Preset inspection preserves the complete fallback expression");
  }
  metadataRequire([[RDLPLibrary qualityLabelForFormat:@"136+140"] isEqualToString:RDLP_isIOSApp()?@"Med":@"High"] && [[RDLPLibrary qualityLabelForFormat:@"137+140"] isEqualToString:@"High"],@"Resolved formats use platform-specific preset names");
  metadataRequire([[RDLPLibrary qualityLabelForFormat:@"135+140"] isEqualToString:RDLP_isIOSApp()?@"Custom":@"Med"],@"Resolved 480p is Medium on Mac and custom on iOS");
  metadataRequire([[RDLPLibrary qualityLabelForFormat:@"135+599"] isEqualToString:@"Custom"] && [[RDLPLibrary qualityDetailForFormat:@"135+599"] isEqualToString:@"Custom (135+599)"],@"Custom labels stay compact while inspection identifies the exact format");
  metadataRequire(![[RDLPLibrary qualityLabelForFormat:nil] length] && ![[RDLPLibrary qualityDetailForFormat:@""] length],@"Absent formats have no fabricated quality label");
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
  metadataRequire([[first objectForKey:@"detail"] isEqualToString:@"12:34·1.5 MB·High·First channel"],@"Playlist combines metadata with representative file quality and bytes");
  metadataRequire([first objectForKey:@"accessibility_label"]!=nil && [[first objectForKey:@"tooltip"] rangeOfString:@"Local file: High (137+140)·1.5 MB"].location!=NSNotFound,@"Shared accessibility and tooltip include local size");
  metadataRequire([playlist objectAtIndex:0]==first && policy->probes==2,@"Repeated row rendering reuses bounded background-page filesystem probes");
  metadataRequire([playlist cachedObjectAtIndex:1]!=nil,@"Presentation prefetch is bounded to the requested page");
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
  metadataRequire(![[missing objectForKey:@"quality"] length] && ![[missing objectForKey:@"size"] length] && [[missing objectForKey:@"status"] isEqualToString:@"File Missing"],@"Refresh removes quality and size for missing files");
  metadataRequire(rdapp_make_directory([highPath fileSystemRepresentation]),@"Replace file with directory");
  metadataRequire(![policy playable:[first objectForKey:@"job"]],@"A directory is not a playable local file");
  [[NSFileManager defaultManager] removeItemAtPath:highPath error:NULL];
  metadataRequire([[RDLPLibrary fileSizeLabelForBytes:0] isEqualToString:@"0 KB"] && [[RDLPLibrary fileSizeLabelForBytes:1] isEqualToString:@"1 KB"] && [[RDLPLibrary fileSizeLabelForBytes:999999] isEqualToString:@"1000 KB"] && [[RDLPLibrary fileSizeLabelForBytes:1000000] isEqualToString:@"1.0 MB"] && [[RDLPLibrary fileSizeLabelForBytes:5000000000ULL] isEqualToString:@"5000.0 MB"],@"Size labels preserve zero, unit boundaries, and 64-bit values");
  NSDictionary *parent=[library playlistForID:pid];
  metadataRequire([library canRemovePlaylist:parent],@"Completed downloads permit playlist removal");
  [library setValue:[NSDictionary dictionaryWithObject:@"download" forKey:@"type"] forKey:@"activeCommand_"];
  [library setValue:[NSNumber numberWithBool:YES] forKey:@"busy_"];
  metadataRequire([library canRemovePlaylist:parent],@"Active transfers permit playlist removal");
  NSDictionary *removable=[complete objectAtIndex:1];
  metadataRequire([policy canRemove:removable],@"Completed downloads remain removable during another transfer");
  [library setValue:[NSNumber numberWithLongLong:strtoll([[removable objectForKey:@"id"] UTF8String],NULL,10)] forKey:@"activeJob_"];
  metadataRequire(![policy canRemove:removable],@"The active job identity cannot be deleted even from a stale row");
  [library setValue:[NSNumber numberWithLongLong:0] forKey:@"activeJob_"];
  [library setValue:[NSDictionary dictionaryWithObject:@"sync" forKey:@"type"] forKey:@"activeCommand_"];
  metadataRequire(![library canRemovePlaylist:parent],@"Active sync serializes playlist removal");
  metadataRequire(![policy canRemove:removable],@"Active sync still blocks download deletion");
  [library setValue:[NSDictionary dictionaryWithObject:@"download" forKey:@"type"] forKey:@"activeCommand_"];
  [library removePlaylist:parent];
  [library setValue:nil forKey:@"activeCommand_"];
  [library setValue:[NSNumber numberWithBool:NO] forKey:@"busy_"];
  metadataRequire([library playlistForID:pid]==nil && [[library entriesForPlaylist:pid] count]==0,@"Removal hides playlist and clears membership");
  metadataRequire([[library jobsForPlaylist:nil completedOnly:YES] count]==2,@"Removal retains every completed quality in All Downloads");
  metadataRequire([policy playable:[complete objectAtIndex:1]],@"Retained completed download remains playable");
  [library setValue:[NSDictionary dictionaryWithObject:@"download" forKey:@"type"] forKey:@"activeCommand_"];
  [library setValue:[NSNumber numberWithBool:YES] forKey:@"busy_"];
  [library removeDownload:removable];
  metadataRequire(![[NSFileManager defaultManager] fileExistsAtPath:[library fileForJob:removable]] &&
    [[[library jobForID:[removable objectForKey:@"id"]] objectForKey:@"state"] isEqualToString:@"removed"],@"Deletion during an unrelated transfer removes the file and updates its exact job");
  [library setValue:nil forKey:@"activeCommand_"];
  [library setValue:[NSNumber numberWithBool:NO] forKey:@"busy_"];
  metadataRequire(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open empty destination fixture");
  metadataRequire(rdapp_store_snapshot(store,"PLempty","Empty",NULL,0,&key),@"Save empty destination playlist");
  rdapp_store_close(store);
  parent=[library playlistForID:[NSString stringWithFormat:@"%lld",(long long)key]];
  NSString *emptyDirectory=[downloads stringByAppendingPathComponent:[parent objectForKey:@"directory"]];
  metadataRequire(rdapp_make_directory([emptyDirectory fileSystemRepresentation]),@"Prepare download destination");
  [library removePlaylist:parent];
  metadataRequire([[NSFileManager defaultManager] fileExistsAtPath:emptyDirectory],@"Removal preserves empty destination needed for file publication");
  metadataRequire(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open sync scope fixture");
  metadataRequire(rdapp_store_snapshot(store,"PLmanual","Manual",NULL,0,NULL),@"Add manual sync fixture");
  metadataRequire(rdapp_store_discovered_playlist(store,"PLaccount","Account"),@"Add account sync fixture");
  rdapp_store_close(store);
  [library setValue:[NSNumber numberWithBool:YES] forKey:@"operationsSuspended_"];
  NSMutableArray *commands=[library valueForKey:@"commands_"]; [commands removeAllObjects];
  metadataRequire([library hasPlaylistsToSync],@"Added playlists enable scoped sync");
  [library syncAll];
  metadataRequire([commands count]==1 && [[[[commands objectAtIndex:0] objectForKey:@"input"] description] isEqualToString:@"PLmanual"],@"Sync Added Playlists queues only manual inputs");
  metadataRequire(![library hasPlaylistsToSync],@"Pending added sync disables duplicate bulk work");
  [commands removeAllObjects];
  [library discoverPlaylists]; [library discoverPlaylists];
  metadataRequire([commands count]==1 && [[[commands objectAtIndex:0] objectForKey:@"type"] isEqualToString:@"discover"],@"Sync My Playlists queues one account refresh before individual syncing");
  [library shutdown]; [library release]; [pool drain];
}
