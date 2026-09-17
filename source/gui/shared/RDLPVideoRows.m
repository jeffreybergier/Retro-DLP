#import "RDLPVideoRows.h"

@implementation RDLPVideoRows
- (id)initWithRows:(NSArray *)rows library:(RDLPLibrary *)library playlist:(NSString *)playlist;
{
  self=[super init];
  if(self) {
    source_=[rows retain]; library_=[library retain]; playlist_=[playlist copy];
    policy_=[[RDLPDownloadPolicy alloc] initWithLibrary:library]; cache_=[[NSMutableDictionary alloc] init];
  }
  return self;
}
- (void)dealloc;
{ [source_ release]; [library_ release]; [playlist_ release]; [policy_ release]; [cache_ release]; [super dealloc]; }
- (NSUInteger)count; { return [source_ count]; }
- (id)copyWithZone:(NSZone *)zone; { (void)zone; return [self retain]; }
- (id)cachedObjectAtIndex:(NSUInteger)index;
{ return [cache_ objectForKey:[NSNumber numberWithUnsignedLong:index]]; }
- (NSUInteger)indexForIdentity:(NSString *)identity;
{ return [(RDLPLibraryRows *)source_ indexForIdentity:identity]; }
- (NSDictionary *)displayRow:(NSDictionary *)entry;
{
  NSDictionary *file=nil, *job=entry;
  if(playlist_) {
    NSArray *jobs=[library_ jobsForPlaylist:playlist_ video:[entry objectForKey:@"video_id"]];
    job=[policy_ representativeJobForEntry:entry playlist:playlist_ jobs:jobs localFile:&file];
  } else file=[policy_ localFileForJob:job];
  NSString *pid=playlist_?playlist_:[entry objectForKey:@"playlist_id"];
  NSString *title=[entry objectForKey:@"title"], *status=[policy_ statusForJob:job localFile:file];
  if(![title length]) title=@"Untitled";
  NSString *quality=@"", *size=@"", *local=@"";
  if(file) {
    NSString *format=[[job objectForKey:@"actual_format"] length]?[job objectForKey:@"actual_format"]:[job objectForKey:@"format"];
    quality=[RDLPLibrary qualityLabelForFormat:format];
    size=[RDLPLibrary fileSizeLabelForBytes:[[file objectForKey:@"bytes"] unsignedLongLongValue]];
    local=[quality length]?[quality stringByAppendingFormat:@" · %@",size]:size;
  }
  NSString *summary=[RDLPLibrary metadataSummaryForEntry:entry];
  NSMutableArray *details=[NSMutableArray array];
  NSString *durationLabel=[RDLPLibrary durationLabelForEntry:entry];
  if([durationLabel length]) [details addObject:durationLabel];
  if([size length]) [details addObject:size];
  if([quality length]) [details addObject:quality];
  if([[entry objectForKey:@"channel"] length]) [details addObject:[entry objectForKey:@"channel"]];
  NSString *detail=[details componentsJoinedByString:@" · "];
  NSMutableArray *spoken=[NSMutableArray array];
  NSString *duration=[RDLPLibrary spokenDurationForEntry:entry], *channel=[entry objectForKey:@"channel"];
  if(!channel) channel=@"";
  if([duration length]) [spoken addObject:duration];
  if([size length]) [spoken addObject:[NSString stringWithFormat:@"%@ %@",[size substringToIndex:[size length]-3],[size hasSuffix:@" KB"]?@"kilobytes":@"megabytes"]];
  if([quality length]) [spoken addObject:quality];
  if([channel length]) [spoken addObject:channel];
  NSString *spokenDetail=[spoken componentsJoinedByString:@", "];
  NSString *accessibility=[NSString stringWithFormat:@"%@%@, %@",title,[spokenDetail length]?[@", " stringByAppendingString:spokenDetail]:@"",status];
  NSString *tooltip=[RDLPLibrary metadataTooltipForEntry:entry];
  if([local length]) tooltip=[tooltip stringByAppendingFormat:@"\nLocal file: %@",local];
  NSString *error=[job objectForKey:@"error"];
  NSMutableDictionary *row=[NSMutableDictionary dictionaryWithObjectsAndKeys:
    title,@"title",entry,@"video",pid?pid:@"",@"playlist_id",status,@"status",detail,@"detail",
    summary,@"metadata_detail",local,@"local_detail",spokenDetail,@"spoken_detail",accessibility,@"accessibility_label",
    tooltip,@"tooltip",quality,@"quality",size,@"size",[RDLPLibrary durationLabelForEntry:entry],@"duration",channel,@"channel",
    [error length]?[status stringByAppendingFormat:@": %@",error]:status,@"status_tooltip",@"video",@"action",nil];
  NSString *description=[entry objectForKey:@"description_snippet"];
  [row setObject:description?description:@"" forKey:@"description_snippet"];
  if(job) [row setObject:job forKey:@"job"];
  if(file) [row setObject:file forKey:@"local_file"];
  return row;
}
- (id)objectAtIndex:(NSUInteger)index;
{
  NSNumber *key=[NSNumber numberWithUnsignedLong:index];
  NSDictionary *row=[cache_ objectForKey:key];
  if(!row) {
    row=[self displayRow:[source_ objectAtIndex:index]];
    if([cache_ count]>=128) [cache_ removeAllObjects];
    [cache_ setObject:row forKey:key];
  }
  return [[row retain] autorelease];
}
@end
