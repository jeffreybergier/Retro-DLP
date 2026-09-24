#import "RDLP_Foundation.h"
#import <TargetConditionals.h>
#include <pthread.h>

static void *RDLPThreadMain(void *context) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSInvocation *invocation=(NSInvocation *)context;
  [invocation invoke];
  [invocation release];
  [pool drain];
  [NSThread exit];
  return NULL;
}

@implementation NSThread (RDLP_Foundation)
+ (BOOL)RLDP_isMainThread {
  if([self respondsToSelector:@selector(isMainThread)]) return [self isMainThread];
  /* Tiger predates NSThread's main-thread queries. */
  return pthread_main_np()!=0;
}
+ (void)RDLP_prepareMultithreading:(id)object { (void)object; }
+ (int)RDLP_detachNewThreadSelector:(SEL)selector toTarget:(id)target
                       withObject:(id)object stackSize:(NSUInteger)stackSize {
  /* Tiger needs an NSThread launch to enable Cocoa's internal locks before
     using Cocoa on POSIX threads. The bootstrap does no application work. */
  if(![self isMultiThreaded])
    [self detachNewThreadSelector:@selector(RDLP_prepareMultithreading:)
      toTarget:self withObject:nil];
  pthread_attr_t attributes;
  int error=pthread_attr_init(&attributes);
  if(error) return error;
  error=pthread_attr_setdetachstate(&attributes,PTHREAD_CREATE_DETACHED);
  if(!error) error=pthread_attr_setstacksize(&attributes,stackSize);
  if(!error) {
    NSInvocation *invocation=[[NSInvocation invocationWithMethodSignature:
      [target methodSignatureForSelector:selector]] retain];
    [invocation setTarget:target];
    [invocation setSelector:selector];
    [invocation setArgument:&object atIndex:2];
    [invocation retainArguments];
    pthread_t thread;
    error=pthread_create(&thread,&attributes,RDLPThreadMain,invocation);
    if(error) [invocation release];
  }
  pthread_attr_destroy(&attributes);
  return error;
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
