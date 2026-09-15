#import "RDLPDownloadPolicy.h"
#include <sys/stat.h>

@implementation RDLPDownloadPolicy
- (id)initWithLibrary:(RDLPLibrary *)library;
{
  self=[super init];
  if(self) library_=[library retain];
  return self;
}
- (void)dealloc;
{ [library_ release]; [super dealloc]; }
+ (BOOL)job:(NSDictionary *)job hasState:(NSString *)state;
{ return [[job objectForKey:@"state"] isEqualToString:state]; }
- (NSString *)statusForJob:(NSDictionary *)job;
{ return [self statusForJob:job localFile:[self localFileForJob:job]]; }
- (NSString *)statusForJob:(NSDictionary *)job localFile:(NSDictionary *)file;
{
  if(file) return @"Downloaded";
  if([RDLPDownloadPolicy job:job hasState:@"running"]) return @"Downloading";
  if([RDLPDownloadPolicy job:job hasState:@"queued"]) return @"Queued";
  if([RDLPDownloadPolicy job:job hasState:@"failed"]) return @"Failed";
  if([RDLPDownloadPolicy job:job hasState:@"interrupted"]) return @"Interrupted";
  if([RDLPDownloadPolicy job:job hasState:@"cancelled"]) return @"Cancelled";
  if([RDLPDownloadPolicy job:job hasState:@"complete"] || ([RDLPDownloadPolicy job:job hasState:@"removed"] && [[job objectForKey:@"error"] length])) return @"File missing";
  return @"Not downloaded";
}

- (BOOL)playable:(NSDictionary *)job;
{ return [self localFileForJob:job]!=nil; }
- (NSDictionary *)localFileForJob:(NSDictionary *)job;
{
  if(![RDLPDownloadPolicy job:job hasState:@"complete"]) return nil;
  NSString *path=[library_ fileForJob:job];
  struct stat info;
  if(!path || stat([path fileSystemRepresentation],&info) || !S_ISREG(info.st_mode) || info.st_size<0) return nil;
  return [NSDictionary dictionaryWithObjectsAndKeys:path,@"path",[NSNumber numberWithUnsignedLongLong:(unsigned long long)info.st_size],@"bytes",nil];
}

- (BOOL)canRetry:(NSDictionary *)job;
{ return [RDLPDownloadPolicy job:job hasState:@"failed"] || [RDLPDownloadPolicy job:job hasState:@"cancelled"] || [RDLPDownloadPolicy job:job hasState:@"interrupted"]; }

- (BOOL)canDownloadAgain:(NSDictionary *)job;
{ return [RDLPDownloadPolicy job:job hasState:@"removed"] || ([RDLPDownloadPolicy job:job hasState:@"complete"] && ![self playable:job]); }

- (BOOL)canRemove:(NSDictionary *)job;
{ return job && ![library_ isBusy] && ![RDLPDownloadPolicy job:job hasState:@"running"] && ![RDLPDownloadPolicy job:job hasState:@"removed"]; }

- (BOOL)canCancel:(NSDictionary *)job;
{ return [RDLPDownloadPolicy job:job hasState:@"queued"] || [RDLPDownloadPolicy job:job hasState:@"running"]; }

/* Preserve newest-first ordering when two jobs have the same priority. */
- (NSInteger)priorityForJob:(NSDictionary *)job localFile:(NSDictionary *)file;
{
  if(file) return 6;
  NSString *state=[job objectForKey:@"state"];
  if([state isEqualToString:@"running"]) return 5;
  if([state isEqualToString:@"queued"]) return 4;
  if([state isEqualToString:@"failed"] || [state isEqualToString:@"interrupted"] ||
     [state isEqualToString:@"complete"] ||
     ([state isEqualToString:@"removed"] && [[job objectForKey:@"error"] length])) return 3;
  if([state isEqualToString:@"cancelled"]) return 2;
  return 1;
}

- (NSDictionary *)representativeJobForEntry:(NSDictionary *)entry playlist:(NSString *)playlist jobs:(NSArray *)jobs;
{ return [self representativeJobForEntry:entry playlist:playlist jobs:jobs localFile:NULL]; }
- (NSDictionary *)representativeJobForEntry:(NSDictionary *)entry playlist:(NSString *)playlist jobs:(NSArray *)jobs localFile:(NSDictionary **)file;
{
  NSDictionary *best=nil, *bestFile=nil; NSInteger bestRank=-1;
  NSEnumerator *e=[jobs objectEnumerator]; NSDictionary *job;
  /* jobs is newest-first. A playable copy wins regardless of preference. */
  while(entry && (job=[e nextObject])) {
    if(![[job objectForKey:@"playlist_id"] isEqualToString:playlist] ||
       ![[job objectForKey:@"video_id"] isEqualToString:[entry objectForKey:@"video_id"]]) continue;
    NSDictionary *candidateFile=[self localFileForJob:job];
    NSInteger rank=[self priorityForJob:job localFile:candidateFile];
    if(rank>bestRank) { best=job; bestRank=rank; bestFile=candidateFile; }
    if(bestRank==6) break;
  }
  if(file) *file=bestFile;
  return best;
}
@end
