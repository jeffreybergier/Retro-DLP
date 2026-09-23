#import <Foundation/Foundation.h>

@interface NSThread (RDLP_Foundation)
+ (BOOL)RLDP_isMainThread;
@end

@interface NSFileManager (RDLP_Foundation)
- (BOOL)RDLP_createDirectoryAtPath:(NSString *)path error:(NSError **)error;
@end
