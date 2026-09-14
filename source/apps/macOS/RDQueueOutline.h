#import <AppKit/AppKit.h>
#import "RetroDLPLibrary.h"

enum { RDQueueGroup, RDQueuePlaylist, RDQueueVideo, RDQueueQuality };
enum { RDQueueNoAction, RDQueueStop, RDQueueRetry };

/* Stable identities let NSOutlineView retain disclosure state across updates. */
@interface RDQueueNode : NSObject {
@public
  NSString *key, *title, *parentKey, *playlistID, *videoID;
  NSMutableArray *children;
  NSDictionary *job;
  NSInteger kind, action;
}
@end

@interface RDQueueTree : NSObject {
  NSMutableDictionary *nodes_;
  NSArray *roots_;
}
- (NSArray *)roots;
- (RDQueueNode *)nodeForKey:(NSString *)key;
- (void)rebuildJobs:(NSArray *)jobs library:(RetroDLPLibrary *)library;
@end

@interface RDQueueOutlineView : NSOutlineView {
  NSString *actionJobID_;
}
- (NSString *)actionJobID;
- (BOOL)isTrackingAction;
@end

/* A cell-based action column works on Tiger without embedding NSButton views. */
@interface RDQueueActionColumn : NSTableColumn {
  NSButtonCell *button_;
  NSTextFieldCell *blank_;
  id actionTarget_;
}
- (id)initWithTarget:(id)target;
@end
