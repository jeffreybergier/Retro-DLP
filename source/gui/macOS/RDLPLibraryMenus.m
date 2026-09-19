#import "RDLPLibraryMenus.h"
#import "RDLPLibrary.h"

@implementation RDLPLibraryMenus
+ (void)addItemToMenu:(NSMenu *)menu title:(NSString *)title action:(SEL)action target:(id)target;
{ [[menu addItemWithTitle:title action:action keyEquivalent:@""] setTarget:target]; }

+ (NSMenu *)menuForMenuBarTitle:(NSString *)title target:(id<RDLPLibraryMenuContext>)target;
{
  NSMenu *menu=[[[NSMenu alloc] initWithTitle:title] autorelease];
  if([title isEqualToString:@"File"]) {
    [self addItemToMenu:menu title:@"Add Video…" action:@selector(addVideo:) target:target];
    [self addItemToMenu:menu title:@"Add Playlist…" action:@selector(addPlaylist:) target:target];
    [self addItemToMenu:menu title:@"Load My Playlists…" action:@selector(discover:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:@"Sync Current Playlist" action:@selector(sync:) target:target];
    [self addItemToMenu:menu title:@"Sync All Playlists…" action:@selector(syncAll:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:@"Download Video" action:@selector(downloadFromMenu:) target:target];
    [self addItemToMenu:menu title:@"Cancel Download…" action:@selector(cancelTarget:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:@"Play Playlist" action:@selector(playSelection:) target:target];
    [self addItemToMenu:menu title:@"Play Entire Playlist" action:@selector(playTargetPlaylist:) target:target];
    [self addItemToMenu:menu title:@"Show in Finder" action:@selector(revealSelection:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
  } else if([title isEqualToString:@"Edit"]) {
    [menu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [menu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [menu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [menu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:@"Remove Playlist…" action:@selector(removePlaylist:) target:target];
    [self addItemToMenu:menu title:@"Delete Download…" action:@selector(removeTarget:) target:target];
  } else if([title isEqualToString:@"View"]) {
    [self addItemToMenu:menu title:@"Hide Playlists" action:@selector(togglePlaylists:) target:target];
    [self addItemToMenu:menu title:@"Show Download Queue" action:@selector(showQueue:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:@"Customize Toolbar…" action:@selector(customizeToolbar:) target:target];
  } else if([title isEqualToString:@"Download Quality"]) {
    NSArray *names=[NSArray arrayWithObjects:[RDLPLibrary qualityLabelForFormat:@"18"],[RDLPLibrary qualityLabelForFormat:@"136+140"],[RDLPLibrary qualityLabelForFormat:@"137+140"],@"Custom Format…",nil];
    unsigned int index;
    for(index=0;index<[names count];++index) {
      NSMenuItem *choice=[menu addItemWithTitle:[names objectAtIndex:index] action:@selector(chooseDownload:) keyEquivalent:@""];
      [choice setTarget:target]; [choice setTag:index+1];
    }
  } else if([title isEqualToString:@"Video Player"]) {
    NSArray *players=[NSArray arrayWithObjects:@"VLC",@"QuickTime",@"Default App",nil];
    NSUInteger index;
    for(index=0;index<[players count];++index) {
      NSString *player=[players objectAtIndex:index];
      NSMenuItem *choice=[menu addItemWithTitle:player action:@selector(chooseVideoPlayer:) keyEquivalent:@""];
      [choice setTarget:target]; [choice setRepresentedObject:player];
    }
  } else if([title isEqualToString:@"Cookies"]) {
    [self addItemToMenu:menu title:@"Import Cookies…" action:@selector(importCookies:) target:target];
    [self addItemToMenu:menu title:@"Replace Cookies…" action:@selector(replaceCookies:) target:target];
    [self addItemToMenu:menu title:@"Remove Cookies…" action:@selector(clearCookies:) target:target];
  } else if([title isEqualToString:@"Help"]) {
    [self addItemToMenu:menu title:@"Cookie Export Guide" action:@selector(openCookieExportGuide:) target:target];
  }
  return menu;
}

+ (NSMenu *)menuForToolbarIdentifier:(NSString *)identifier target:(id<RDLPLibraryMenuContext>)target;
{
  NSMenu *menu=[[[NSMenu alloc] initWithTitle:identifier] autorelease];
  if([identifier isEqualToString:@"download"] || [identifier isEqualToString:@"play"] || [identifier isEqualToString:@"remove"] || [identifier isEqualToString:@"library"]) {
    [menu setDelegate:(id)target]; [self updateMenu:menu target:target];
  } else if([identifier isEqualToString:@"view"]) {
    [self addItemToMenu:menu title:@"Hide Playlists" action:@selector(togglePlaylists:) target:target];
    [self addItemToMenu:menu title:@"Show Download Queue" action:@selector(showQueue:) target:target];
  } else if([identifier isEqualToString:@"cookies"]) {
    [menu setDelegate:(id)target];
    [self addItemToMenu:menu title:@"Import Cookies…" action:@selector(importCookies:) target:target];
    [self addItemToMenu:menu title:@"Replace Cookies…" action:@selector(replaceCookies:) target:target];
    [self addItemToMenu:menu title:@"Remove Cookies…" action:@selector(clearCookies:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:@"Export Guide" action:@selector(openCookieExportGuide:) target:target];
  } else {
    [self addItemToMenu:menu title:@"Show Download Queue" action:@selector(showQueue:) target:target];
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
  NSDictionary *job=[target targetJob];
  if(library) {
    [self addItemToMenu:menu title:@"Add Video…" action:@selector(addVideo:) target:target];
    [self addItemToMenu:menu title:@"Add Playlist…" action:@selector(addPlaylist:) target:target];
    [self addItemToMenu:menu title:@"Load My Playlists…" action:@selector(discover:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:menu title:@"Sync Current Playlist" action:@selector(sync:) target:target];
    [self addItemToMenu:menu title:@"Sync All Playlists…" action:@selector(syncAll:) target:target];
  } else if(download) {
    [self addItemToMenu:menu title:@"Download Video" action:@selector(chooseDownload:) target:target];
    if(video && ([target canRetry:job] || [target canDownloadAgain:job])) {
      [self addItemToMenu:menu title:[NSString stringWithFormat:@"Retry Download — %@",[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]]] action:[target canRetry:job]?@selector(retryTarget:):@selector(againTarget:) target:target];
    }
    [self addItemToMenu:menu title:@"Cancel Download…" action:@selector(cancelTarget:) target:target];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quality=[menu addItemWithTitle:@"Download Quality" action:NULL keyEquivalent:@""];
    [quality setSubmenu:[self menuForMenuBarTitle:@"Download Quality" target:target]];
  } else if(removal) {
    if(video) {
      [self addItemToMenu:menu title:@"Delete Download" action:@selector(removeTarget:) target:target];
    } else {
      NSDictionary *playlist=[target contextPlaylist];
      NSString *title=playlist?[NSString stringWithFormat:@"Remove Playlist — ‘%@’…",[playlist objectForKey:@"title"]]:@"Remove Playlist…";
      [self addItemToMenu:menu title:title action:@selector(removePlaylist:) target:target];
    }
  } else {
    NSString *object=video?@"Video":@"Playlist";
    [self addItemToMenu:menu title:[NSString stringWithFormat:@"Play %@",object] action:@selector(playSelection:) target:target];
    [self addItemToMenu:menu title:[NSString stringWithFormat:@"Reveal %@ in Finder",object] action:@selector(revealSelection:) target:target];
    if(video && [target contextPlaylist]) {
      [menu addItem:[NSMenuItem separatorItem]];
      [self addItemToMenu:menu title:@"Play Playlist" action:@selector(playTargetPlaylist:) target:target];
    }
  }
}
@end
