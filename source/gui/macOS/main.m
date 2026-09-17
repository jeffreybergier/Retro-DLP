#import "RDLPAppDelegate.h"
#import "RDLPAppKit.h"
#import "RDLPToolbarButton.h"

int main(int argc,char **argv) {
  (void)argc; (void)argv; NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSApplication *app=[RDLPApplication sharedApplication]; RDLPAppDelegate *delegate=[[RDLPAppDelegate alloc] init];
  [RDLPAppKit setApplication:app delegate:delegate]; [app run]; [delegate release]; [pool drain]; return 0;
}
