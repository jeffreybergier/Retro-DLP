#import <Foundation/Foundation.h>

@interface NSThread (RDLP_Foundation)
+ (BOOL)RLDP_isMainThread;
/* Starts a detached Cocoa worker with a native stack size, including on Tiger.
   Returns zero on success or a pthread error; retains target/object until exit. */
+ (int)RDLP_detachNewThreadSelector:(SEL)selector toTarget:(id)target
                       withObject:(id)object stackSize:(NSUInteger)stackSize;
@end

@interface NSFileManager (RDLP_Foundation)
- (BOOL)RDLP_createDirectoryAtPath:(NSString *)path error:(NSError **)error;
@end
