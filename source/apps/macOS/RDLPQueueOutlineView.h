#import <AppKit/AppKit.h>
#import "RDLPLibrary.h"

enum { RDLPQueueGroup, RDLPQueuePlaylist, RDLPQueueVideo, RDLPQueueQuality };
enum { RDLPQueueNoAction, RDLPQueueStop, RDLPQueueRetry };

/* Stable identities let NSOutlineView retain disclosure state across updates. */
@interface RDLPQueueNode : NSObject {
@public
  NSString *key, *title, *parentKey, *playlistID, *videoID;
  NSMutableArray *children;
  NSDictionary *job;
  NSInteger kind, action;
}
@end

@interface RDLPQueueTree : NSObject {
  NSMutableDictionary *nodes_;
  NSArray *roots_;
}
- (NSArray *)roots;
- (RDLPQueueNode *)nodeForKey:(NSString *)key;
- (void)rebuildJobs:(NSArray *)jobs library:(RDLPLibrary *)library;
@end

@interface RDLPQueueOutlineView : NSOutlineView {
  NSString *actionJobID_;
}
- (NSString *)actionJobID;
- (BOOL)isTrackingAction;
@end

/* A cell-based action column works on Tiger without embedding NSButton views. */
@interface RDLPQueueActionColumn : NSTableColumn {
  NSButtonCell *button_;
  NSTextFieldCell *blank_;
  id actionTarget_;
}
- (id)initWithTarget:(id)target;
@end
