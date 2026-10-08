#import <UIKit/UIKit.h>
@class RDLPStatusBarView, RDLPLibrary;
@protocol RDLPPlaybackRemoteTarget <NSObject>
- (BOOL)handlePlaybackRemoteControl:(UIEventSubtype)subtype;
@end
typedef enum {
  RDLPPlayerIconHeadphones,
  RDLPPlayerIconPrevious,
  RDLPPlayerIconNext,
  RDLPPlayerIconPlay,
  RDLPPlayerIconPause,
  RDLPPlayerIconBack,
  RDLPPlayerIconForward,
  RDLPPlayerIconVideoSlash
} RDLPPlayerIcon;
@interface RDLPUIKit : NSObject
+ (UIImage *)playerIcon:(RDLPPlayerIcon)icon;
+ (UIImage *)playerIcon:(RDLPPlayerIcon)icon size:(CGFloat)size canvas:(CGFloat)canvas;
+ (void)configureContentEdges:(UIViewController *)controller;
+ (void)configurePlayerFullScreenLayout:(UIViewController *)controller;
+ (void)setBorderedStyleForBarButtonItem:(UIBarButtonItem *)item;
+ (void)centerTextInLabel:(UILabel *)label;
+ (void)truncateMiddleInLabel:(UILabel *)label;
+ (BOOL)legacyStatusBarHidden;
+ (void)setLegacyStatusBarHidden:(BOOL)hidden;
+ (void)registerDownloadNotificationsForApplication:(UIApplication *)application;
+ (id)downloadCompletionNotificationForTitle:(NSString *)title;
+ (void)presentDownloadNotification:(id)notification;
+ (void)activatePlaybackAudioSessionForDelegate:(id)delegate;
+ (void)deactivatePlaybackAudioSessionForDelegate:(id)delegate;
+ (BOOL)shouldResumePlaybackAfterInterruptionFlags:(NSUInteger)flags;
/* Main-thread session registration. Returns nil before iOS 7.1. Retain the
 * registration and stop it before releasing its nonretained target. */
+ (id)playbackRemoteCommandsForTarget:(id<RDLPPlaybackRemoteTarget>)target;
+ (void)updatePlaybackRemoteCommands:(id)registration longContent:(BOOL)longContent
                         available:(BOOL)available canSeek:(BOOL)canSeek
                       canPrevious:(BOOL)canPrevious canNext:(BOOL)canNext;
+ (void)stopPlaybackRemoteCommands:(id)registration;
+ (UIImage *)statusIcon:(NSString *)status;
+ (UIImage *)queueActionIcon:(BOOL)stop;
+ (UIImage *)settingsIcon;
+ (UIImage *)plusIcon;
+ (UIImage *)syncIcon;
+ (UIImage *)queueToolbarIcon;
+ (NSArray *)statusToolbarItems:(RDLPStatusBarView *)status target:(id)target queueAction:(SEL)action;
+ (void)refreshStatusToolbarPlayback:(UIViewController *)controller;
+ (BOOL)hasHiddenPlayback;
+ (void)reopenPlayer:(UIViewController *)owner;
+ (void)showMessage:(NSString *)message;
+ (void)presentPlayer:(UIViewController *)owner library:(RDLPLibrary *)library job:(NSDictionary *)job;
+ (void)presentPlayer:(UIViewController *)owner library:(RDLPLibrary *)library playlist:(NSString *)playlist entry:(NSDictionary *)entry job:(NSDictionary *)job;
+ (UIBarButtonItem *)item:(NSString *)title target:(id)target action:(SEL)action;
@end
