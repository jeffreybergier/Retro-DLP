#import "RDLP_Foundation.h"
#include <pthread.h>

@implementation NSThread (RDLP_Foundation)
+ (BOOL)RLDP_isMainThread {
  if([self respondsToSelector:@selector(isMainThread)]) return [self isMainThread];
  /* Tiger predates NSThread's main-thread queries. */
  return pthread_main_np()!=0;
}
@end
