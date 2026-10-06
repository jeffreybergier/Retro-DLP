#import "RDLPLibraryMenus.h"
#import "RDLPLibrary.h"

@implementation RDLPLibraryMenus
+ (void)addItemToMenu:(NSMenu *)menu title:(NSString *)title action:(SEL)action target:(id)target;
{ [[menu addItemWithTitle:title action:action keyEquivalent:@""] setTarget:target]; }

+ (NSMenu *)menuForMenuBarTitle:(NSString *)title target:(id<RDLPLibraryMenuContext>)target;
{
  NSMenu *menu=[[[NSMenu alloc] initWithTitle:NSLocalizedString(title, nil)] autorelease];
  if([title isEqualToString:@"File"]) {
    [self addItemToMenu:menu title:NSLocalizedString(@"Add Video…", nil) action:@selector(addVideo:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Add Playlist…", nil) action:@selector(addPlaylist:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Sync My Playlists…", nil) action:@selector(discover:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:NSLocalizedString(@"Sync Current Playlist", nil) action:@selector(sync:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Sync Added Playlists…", nil) action:@selector(syncAll:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:NSLocalizedString(@"Download Video", nil) action:@selector(downloadFromMenu:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Cancel Download…", nil) action:@selector(cancelTarget:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:NSLocalizedString(@"Play Playlist", nil) action:@selector(playSelection:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Play Entire Playlist", nil) action:@selector(playTargetPlaylist:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Show in Finder", nil) action:@selector(revealSelection:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:NSLocalizedString(@"Close Window", nil) action:@selector(performClose:) keyEquivalent:@"w"];
  } else if([title isEqualToString:@"Edit"]) {
    [menu addItemWithTitle:NSLocalizedString(@"Cut", nil) action:@selector(cut:) keyEquivalent:@"x"];
    [menu addItemWithTitle:NSLocalizedString(@"Copy", nil) action:@selector(copy:) keyEquivalent:@"c"];
    [menu addItemWithTitle:NSLocalizedString(@"Paste", nil) action:@selector(paste:) keyEquivalent:@"v"];
    [menu addItemWithTitle:NSLocalizedString(@"Select All", nil) action:@selector(selectAll:) keyEquivalent:@"a"];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:NSLocalizedString(@"Remove Playlist…", nil) action:@selector(removePlaylist:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Delete Download…", nil) action:@selector(removeTarget:) target:target];
  } else if([title isEqualToString:@"View"]) {
    [self addItemToMenu:menu title:NSLocalizedString(@"Hide Playlists", nil) action:@selector(togglePlaylists:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Show Download Queue", nil) action:@selector(showQueue:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:NSLocalizedString(@"Customize Toolbar…", nil) action:@selector(customizeToolbar:) target:target];
  } else if([title isEqualToString:@"Download Quality"]) {
    NSArray *names=[RDLPLibrary qualityTitles];
    unsigned int index;
    for(index=0;index<[names count];++index) {
      NSMenuItem *choice=[menu addItemWithTitle:[names objectAtIndex:index] action:@selector(chooseDownload:) keyEquivalent:@""];
      [choice setTarget:target]; [choice setTag:index+1];
      if(index<[[RDLPLibrary qualityFormats] count])
        [choice setToolTip:[RDLPLibrary qualityDetailForFormat:[[RDLPLibrary qualityFormats] objectAtIndex:index]]];
    }
  } else if([title isEqualToString:@"Video Player"]) {
    NSArray *players=[NSArray arrayWithObjects:@"VLC",@"QuickTime",@"Default App",nil];
    NSUInteger index;
    for(index=0;index<[players count];++index) {
      NSString *player=[players objectAtIndex:index];
      NSMenuItem *choice=[menu addItemWithTitle:NSLocalizedString(player, nil) action:@selector(chooseVideoPlayer:) keyEquivalent:@""];
      [choice setTarget:target]; [choice setRepresentedObject:player];
    }
  } else if([title isEqualToString:@"Cookies"]) {
    [self addItemToMenu:menu title:NSLocalizedString(@"Import Cookies…", nil) action:@selector(importCookies:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Replace Cookies…", nil) action:@selector(replaceCookies:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Remove Cookies…", nil) action:@selector(clearCookies:) target:target];
  } else if([title isEqualToString:@"Help"]) {
    [self addItemToMenu:menu title:NSLocalizedString(@"Cookie Export Guide", nil) action:@selector(openCookieExportGuide:) target:target];
  }
  return menu;
}

+ (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier target:(id<RDLPLibraryMenuContext>)target;
{
  NSMenu *menu=[[[NSMenu alloc] initWithTitle:identifier] autorelease];
  if([identifier isEqualToString:@"download"] || [identifier isEqualToString:@"play"] || [identifier isEqualToString:@"remove"] || [identifier isEqualToString:@"library"]) {
    [menu setDelegate:(id)target]; [self updateMenu:menu target:target];
  } else if([identifier isEqualToString:@"view"]) {
    [self addItemToMenu:menu title:NSLocalizedString(@"Hide Playlists", nil) action:@selector(togglePlaylists:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Show Download Queue", nil) action:@selector(showQueue:) target:target];
  } else if([identifier isEqualToString:@"cookies"]) {
    [menu setDelegate:(id)target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Import Cookies…", nil) action:@selector(importCookies:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Replace Cookies…", nil) action:@selector(replaceCookies:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Remove Cookies…", nil) action:@selector(clearCookies:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:NSLocalizedString(@"Export Guide", nil) action:@selector(openCookieExportGuide:) target:target];
  } else {
    [self addItemToMenu:menu title:NSLocalizedString(@"Show Download Queue", nil) action:@selector(showQueue:) target:target];
  }
  return menu;
}

+ (void)updateMenu:(NSMenu *)menu target:(id<RDLPLibraryMenuContext>)target;
{
  BOOL library=[[menu title] isEqualToString:@"library"];
  BOOL download=[[menu title] isEqualToString:@"download"];
  BOOL removal=[[menu title] isEqualToString:@"remove"];
  if(!library && !download && !removal && ![[menu title] isEqualToString:@"play"]) return;
  while([menu numberOfItems]) [menu removeItemAtIndex:0];
  BOOL video=[target hasTargetVideo];
  BOOL multiple=[target hasMultipleTargetVideos];
  NSDictionary *job=[target targetJob];
  if(library) {
    [self addItemToMenu:menu title:NSLocalizedString(@"Add Video…", nil) action:@selector(addVideo:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Add Playlist…", nil) action:@selector(addPlaylist:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Sync My Playlists…", nil) action:@selector(discover:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:NSLocalizedString(@"Sync Current Playlist", nil) action:@selector(sync:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Sync Added Playlists…", nil) action:@selector(syncAll:) target:target];
  } else if(download) {
    [self addItemToMenu:menu title:multiple?NSLocalizedString(@"Download Selected Videos", nil):NSLocalizedString(@"Download Video", nil) action:@selector(chooseDownload:) target:target];
    if(video && ([target canRetry:job] || [target canDownloadAgain:job])) {
      [self addItemToMenu:menu title:[NSString stringWithFormat:NSLocalizedString(@"Retry Download — %@", nil),[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]]] action:[target canRetry:job]?@selector(retryTarget:):@selector(againTarget:) target:target];
    }
    [self addItemToMenu:menu title:NSLocalizedString(@"Cancel Download…", nil) action:@selector(cancelTarget:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quality=[menu addItemWithTitle:NSLocalizedString(@"Download Quality", nil) action:NULL keyEquivalent:@""];
    [quality setSubmenu:[self menuForMenuBarTitle:@"Download Quality" target:target]];
  } else if(removal) {
    if(video) {
      [self addItemToMenu:menu title:multiple?NSLocalizedString(@"Delete Selected Downloads…", nil):NSLocalizedString(@"Delete Download", nil) action:@selector(removeTarget:) target:target];
    } else {
      [self addItemToMenu:menu title:NSLocalizedString(@"Remove Playlist…", nil) action:@selector(removePlaylist:) target:target];
    }
  } else {
    NSString *object=video?NSLocalizedString(@"Video", nil):NSLocalizedString(@"Playlist", nil);
    [self addItemToMenu:menu title:[NSString stringWithFormat:NSLocalizedString(@"Play %@", nil),object] action:@selector(playSelection:) target:target];
    [self addItemToMenu:menu title:NSLocalizedString(@"Show in Finder", nil) action:@selector(revealSelection:) target:target];
    if(video && [target contextPlaylist]) {
      [menu addItem:[NSMenuItem separatorItem]];
      [self addItemToMenu:menu title:NSLocalizedString(@"Play Playlist", nil) action:@selector(playTargetPlaylist:) target:target];
    }
  }
}
@end
