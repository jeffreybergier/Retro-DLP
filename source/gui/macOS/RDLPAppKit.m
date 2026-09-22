#import "RDLPAppKit.h"
#import <math.h>
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
@implementation RDLPAppKit
/* CGFloat returns need NSInvocation across the legacy and modern ABIs.
   Mirrors ENIL's XP_backingScaleFactor; Tiger has no backing scale API. */
+ (CGFloat)backingScaleForWindow:(NSWindow *)window {
  SEL selector=@selector(backingScaleFactor);
  if(![window respondsToSelector:selector]) return 1.0;
  NSInvocation *inv=[NSInvocation invocationWithMethodSignature:[window methodSignatureForSelector:selector]];
  CGFloat scale=1.0;
  [inv setTarget:window]; [inv setSelector:selector]; [inv invoke]; [inv getReturnValue:&scale];
  return scale>=1.0?scale:1.0;
}
/* Big Sur's expanded style preserves the separate, full-height toolbar.
   Earlier systems already use the classic toolbar layout. */
+ (void)useExpandedToolbar:(NSWindow *)window {
  SEL selector=@selector(setToolbarStyle:);
  if(![window respondsToSelector:selector]) return;
  NSInvocation *inv=[NSInvocation invocationWithMethodSignature:[window methodSignatureForSelector:selector]];
  NSInteger style=1; /* NSWindowToolbarStyleExpanded */
  [inv setTarget:window]; [inv setSelector:selector]; [inv setArgument:&style atIndex:2]; [inv invoke];
}
+ (void)beginSheet:(NSWindow *)sheet forWindow:(NSWindow *)window delegate:(id)delegate didEnd:(SEL)didEnd {
  [NSApp beginSheet:sheet modalForWindow:window modalDelegate:delegate didEndSelector:didEnd contextInfo:NULL];
}
+ (void)styleButton:(NSButton *)button { [button setBezelStyle:NSRoundedBezelStyle]; }
+ (void)setApplication:(NSApplication *)application delegate:(id)delegate { [application setDelegate:delegate]; }
+ (void)showAlert:(NSString *)message {
  NSAlert *alert=[[[NSAlert alloc] init] autorelease]; [alert setMessageText:message]; [alert addButtonWithTitle:@"OK"]; [alert runModal];
}
+ (void)beginAlertSheet:(NSAlert *)alert forWindow:(NSWindow *)window delegate:(id)delegate didEnd:(SEL)didEnd {
  [alert beginSheetModalForWindow:window modalDelegate:delegate didEndSelector:didEnd contextInfo:NULL];
}
+ (NSImage *)youTubeMaskForScale:(CGFloat)scale {
  NSImage *image=[AIFontAwesome imageForCodePoint:0xf167 style:AIFontAwesomeStyleBrands iconSize:24 canvasSize:32 scale:scale];
  /* Tiger's ATSUI Unicode mapping misses this Brands glyph. Rendering its
     named outline avoids the missing-glyph box after the font is registered. */
  if(NSAppKitVersionNumber<825.0) {
    NSFont *font=[NSFont fontWithName:@"FontAwesome7Brands-Regular" size:24];
    NSGlyph glyph=[font glyphWithName:@"youtube"];
    if(font && glyph) {
      image=[[[NSImage alloc] initWithSize:NSMakeSize(32,32)] autorelease];
      [image lockFocus];
      NSBezierPath *path=[NSBezierPath bezierPath]; [path moveToPoint:NSZeroPoint];
      [path appendBezierPathWithGlyph:glyph inFont:font];
      NSRect bounds=[path bounds]; NSAffineTransform *transform=[NSAffineTransform transform];
      [transform translateXBy:(32-bounds.size.width)/2-bounds.origin.x yBy:(32-bounds.size.height)/2-bounds.origin.y];
      [path transformUsingAffineTransform:transform]; [[NSColor blackColor] set]; [path fill]; [image unlockFocus];
    }
  }
  return image;
}
+ (NSColor *)controlIconColor {
  return [NSColor blackColor];
}
+ (NSImage *)controlIcon:(AIFontAwesomeIcon)icon style:(AIFontAwesomeStyle)style iconSize:(CGFloat)iconSize canvasSize:(CGFloat)canvasSize scale:(CGFloat)scale {
  if(!isfinite(iconSize) || !isfinite(canvasSize) || !isfinite(scale) ||
     iconSize<=0 || canvasSize<iconSize || scale<1 || canvasSize*scale>4096) return nil;
  static NSMutableDictionary *cache=nil;
  if(!cache) cache=[[NSMutableDictionary alloc] init];
  NSArray *key=[NSArray arrayWithObjects:[NSNumber numberWithUnsignedInt:(unsigned int)icon],
    [NSNumber numberWithInt:(int)style],[NSNumber numberWithDouble:iconSize],
    [NSNumber numberWithDouble:canvasSize],[NSNumber numberWithDouble:scale],nil];
  NSImage *image=[cache objectForKey:key]; if(image) return image;
  NSImage *mask=(icon==(AIFontAwesomeIcon)0xf167 && style==AIFontAwesomeStyleBrands && iconSize==24 && canvasSize==32)
    ?[RDLPAppKit youTubeMaskForScale:scale]:[AIFontAwesome imageForIcon:icon style:style iconSize:iconSize canvasSize:canvasSize scale:scale];
  if(!mask) return nil;
  NSInteger pixels=(NSInteger)ceil(canvasSize*scale);
  NSBitmapImageRep *bitmap=[[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
    pixelsWide:pixels pixelsHigh:pixels bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
    isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
  if(!bitmap) return nil;
  NSGraphicsContext *context=[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
  if(!context) return nil;
  [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:context];
  NSAffineTransform *transform=[NSAffineTransform transform]; [transform scaleBy:(CGFloat)pixels/canvasSize]; [transform concat];
  NSRect bounds=NSMakeRect(0,0,canvasSize,canvasSize);
  [mask drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];
  [[RDLPAppKit controlIconColor] set]; NSRectFillUsingOperation(bounds,NSCompositeSourceIn);
  [NSGraphicsContext restoreGraphicsState];
  [bitmap setSize:NSMakeSize(canvasSize,canvasSize)];
  image=[[[NSImage alloc] initWithSize:NSMakeSize(canvasSize,canvasSize)] autorelease];
  [image addRepresentation:bitmap];
  /* AppKit must preserve this explicit color, including on modern systems. */
  if([image respondsToSelector:@selector(setTemplate:)]) [image setTemplate:NO];
  [cache setObject:image forKey:key]; return image;
}
+ (NSImage *)youTubeIconForScale:(CGFloat)scale {
  return [RDLPAppKit controlIcon:(AIFontAwesomeIcon)0xf167 style:AIFontAwesomeStyleBrands iconSize:24 canvasSize:32 scale:scale];
}
+ (NSString *)chooseCookieFile {
  NSOpenPanel *panel=[NSOpenPanel openPanel]; [panel setCanChooseDirectories:NO]; [panel setAllowsMultipleSelection:NO];
  if([panel runModalForDirectory:nil file:nil types:nil]==NSOKButton) return [panel filename];
  return nil;
}
+ (void)revealInFinder:(NSString *)path {
  if(!path || ![[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""])
    [RDLPAppKit showAlert:@"Could not reveal this file in Finder. Check that the download exists."];
}
+ (NSString *)defaultApplication:(NSString *)path {
  if(![path length] || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
  NSWorkspace *workspace=[NSWorkspace sharedWorkspace];
  SEL selector=@selector(URLForApplicationToOpenURL:);
  if([workspace respondsToSelector:selector]) {
    NSURL *application=[workspace performSelector:selector withObject:[NSURL fileURLWithPath:path]];
    return [application path];
  }
  /* Tiger/Leopard expose the default handler through the older path API. */
  NSString *application=nil;
  if(![workspace getInfoForFile:path application:&application type:NULL] || ![application length]) return nil;
  return [application isAbsolutePath]?application:[workspace fullPathForApplication:application];
}
+ (NSString *)VLCApplication {
  return [[NSWorkspace sharedWorkspace] fullPathForApplication:@"VLC"];
}
+ (NSString *)VLCVersion {
  NSString *application=[self VLCApplication];
  id version=application?[[[NSBundle bundleWithPath:application] infoDictionary] objectForKey:@"CFBundleShortVersionString"]:nil;
  return [version isKindOfClass:[NSString class]]?version:nil;
}
+ (NSString *)VLCPlaybackPath:(NSString *)path {
  NSString *name=[path lastPathComponent];
  if(![name isEqualToString:@"Playlist.xspf"] && ![name isEqualToString:@"Playlist.m3u8"]) return path;
  NSString *version=[self VLCVersion];
  BOOL known=[version length]>0;
  NSArray *parts=[version componentsSeparatedByString:@"."];
  unsigned int i;
  for(i=0;i<[parts count];++i) {
    NSString *part=[parts objectAtIndex:i];
    if(![part length] || [part rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location!=NSNotFound) known=NO;
  }
  BOOL modern=known && [version compare:@"1.1.12" options:NSNumericSearch]!=NSOrderedAscending;
  return [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:modern?@"Playlist.xspf":@"Playlist.m3u8"];
}
+ (NSString *)QuickTimeApplication {
  return [[NSWorkspace sharedWorkspace] fullPathForApplication:@"QuickTime Player"];
}
+ (BOOL)videoPlayerAvailable:(NSString *)player {
  if([player isEqualToString:@"VLC"]) return [self VLCApplication]!=nil;
  if([player isEqualToString:@"QuickTime"]) return [self QuickTimeApplication]!=nil;
  return [player isEqualToString:@"Default App"];
}
+ (NSString *)videoPlayer {
  NSString *saved=[[NSUserDefaults standardUserDefaults] stringForKey:@"RetroDLPVideoPlayer"];
  if([saved isEqualToString:@"VLC"] || [saved isEqualToString:@"QuickTime"] || [saved isEqualToString:@"Default App"])
    return [self videoPlayerAvailable:saved]?saved:@"Default App";
  return [self VLCApplication]?@"VLC":@"Default App";
}
+ (void)saveVideoPlayer:(NSString *)player {
  if([self videoPlayerAvailable:player]) {
    [[NSUserDefaults standardUserDefaults] setObject:player forKey:@"RetroDLPVideoPlayer"];
    [[NSUserDefaults standardUserDefaults] synchronize];
  }
}
+ (NSString *)preferredPlaybackApplication:(NSString *)path {
  NSString *player=[self videoPlayer];
  if([player isEqualToString:@"VLC"]) path=[self VLCPlaybackPath:path];
  if(![path length] || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
  if([player isEqualToString:@"VLC"]) return [self VLCApplication];
  if([player isEqualToString:@"QuickTime"]) return [self QuickTimeApplication];
  return [self defaultApplication:path];
}
+ (void)openPreferredPlayback:(NSString *)path {
  NSString *player=[self videoPlayer];
  if([player isEqualToString:@"VLC"]) path=[self VLCPlaybackPath:path];
  if(![path length] || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
  if([player isEqualToString:@"VLC"]) [self openInVLC:path];
  else if([player isEqualToString:@"QuickTime"]) [self openInQuickTime:path];
  else [self openDefaultApplication:path];
}
+ (void)openInVLC:(NSString *)path {
  NSString *application=[self VLCApplication];
  path=[self VLCPlaybackPath:path];
  if(path && application && (![[NSFileManager defaultManager] fileExistsAtPath:path] || ![[NSWorkspace sharedWorkspace] openFile:path withApplication:application])) [RDLPAppKit showAlert:@"Could not open this file in VLC."];
}
+ (void)openInQuickTime:(NSString *)path {
  NSString *application=[self QuickTimeApplication];
  if(path && application && ![[NSWorkspace sharedWorkspace] openFile:path withApplication:application]) [self showAlert:@"Could not open this file in QuickTime Player."];
}
+ (void)openDefaultApplication:(NSString *)path {
  if(!path || ![[NSWorkspace sharedWorkspace] openFile:path])
    [RDLPAppKit showAlert:@"Could not open this file in its default app. Check that the download exists and choose an app in Finder’s Open With settings."];
}
@end
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
