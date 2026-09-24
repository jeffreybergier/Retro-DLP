/* Exercise the real scheduler and QuickJS without networking or user data. */
#include <pthread.h>
#include <string.h>
#include <quickjs.h>
#include "../../../library/shared/yt_ejs.h"

@interface RDLPStackTestLibrary : RDLPLibrary {
@public
  BOOL completed_, overflowCaught_;
  unsigned long long stackSize_;
}
@end
@implementation RDLPStackTestLibrary
- (void)work:(NSDictionary *)command;
{
  (void)command;
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  size_t stackSize=pthread_get_stacksize_np(pthread_self());
  BOOL caught=NO;
  JSRuntime *runtime=JS_NewRuntime();
  if(runtime) {
    JS_SetMaxStackSize(runtime,yt_ejs_default_config().stack_limit_bytes);
    JSContext *context=JS_NewContext(runtime);
    if(context) {
      /* Reproduce the recursive array conversion seen in both crash reports.
         A default 512 KiB thread dies before QuickJS's 1 MiB guard fires. */
      const char *script="var a=[]; a.push(a); a.toString();";
      JSValue value=JS_Eval(context,script,strlen(script),"<worker-stack-test>",JS_EVAL_TYPE_GLOBAL);
      if(JS_IsException(value)) {
        JSValue exception=JS_GetException(context);
        const char *message=JS_ToCString(context,exception);
        caught=message && strstr(message,"stack overflow")!=NULL;
        JS_FreeCString(context,message);
        JS_FreeValue(context,exception);
      }
      JS_FreeValue(context,value);
      JS_FreeContext(context);
    }
    JS_FreeRuntime(runtime);
  }
  NSDictionary *result=[NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt:RDLP_OK],@"code",@"",@"message",
    [NSNumber numberWithUnsignedLongLong:stackSize],@"stackSize",
    [NSNumber numberWithBool:caught],@"overflowCaught",nil];
  [self performSelectorOnMainThread:@selector(finished:) withObject:result waitUntilDone:NO];
  [pool drain];
}
- (void)finished:(NSDictionary *)result;
{
  stackSize_=[[result objectForKey:@"stackSize"] unsignedLongLongValue];
  overflowCaught_=[[result objectForKey:@"overflowCaught"] boolValue];
  [super finished:result];
  completed_=YES;
}
@end

static void testSharedWorker(NSString *base) {
  RDLPStackTestLibrary *library=[[[RDLPStackTestLibrary alloc]
    initWithSupportDirectory:[base stringByAppendingPathComponent:@"Support"]
    downloadDirectory:[base stringByAppendingPathComponent:@"Downloads"]] autorelease];
  statusRequire(library!=nil,@"Open isolated worker fixture");
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:15];
  while(!library->completed_ && [deadline timeIntervalSinceNow]>0) statusWait(0.01);
  statusRequire(library->completed_,@"Real scheduler delivers worker completion");
  statusRequire(library->stackSize_>=2U*1024U*1024U,@"Worker has native stack headroom above the QuickJS limit");
  statusRequire(library->overflowCaught_,@"QuickJS recursion returns a catchable exception without crashing");
  statusRequire(![library isBusy] && [library operationCount]==0,@"Worker completion balances scheduler state");
}
