#import "RDLP_Foundation.h"
#import <TargetConditionals.h>
#include <pthread.h>

@implementation NSThread (RDLP_Foundation)
+ (BOOL)RLDP_isMainThread {
  if([self respondsToSelector:@selector(isMainThread)]) return [self isMainThread];
  /* Tiger predates NSThread's main-thread queries. */
  return pthread_main_np()!=0;
}
@end

@implementation NSFileManager (RDLP_Foundation)
- (BOOL)RDLP_createDirectoryAtPath:(NSString *)path error:(NSError **)error {
  NSDictionary *attributes=[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:0700]
    forKey:NSFilePosixPermissions];
  if(error) *error=nil;
  if([self respondsToSelector:@selector(createDirectoryAtPath:withIntermediateDirectories:attributes:error:)])
    return [self createDirectoryAtPath:path withIntermediateDirectories:YES attributes:attributes error:error];
#if !TARGET_OS_IPHONE
  /* Tiger has only the older API. Stop at the nearest existing directory. */
  BOOL directory=NO;
  if([self fileExistsAtPath:path isDirectory:&directory] && directory) return YES;
  NSString *parent=[path stringByDeletingLastPathComponent];
  if([path isAbsolutePath] && ![parent isEqualToString:path] &&
     [self RDLP_createDirectoryAtPath:parent error:error] &&
     [self createDirectoryAtPath:path attributes:attributes]) return YES;
  if(error && !*error) *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
    userInfo:[NSDictionary dictionaryWithObject:path forKey:NSFilePathErrorKey]];
#endif
  return NO;
}
@end
