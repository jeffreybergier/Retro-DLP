#import "XPAppKit.h"
#import <AIFontAwesome.h>
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
/* CGFloat returns need NSInvocation across the legacy and modern ABIs.
   Mirrors ENIL's XP_backingScaleFactor; Tiger has no backing scale API. */
CGFloat RDWindowBackingScale(NSWindow *window) {
  SEL selector=@selector(backingScaleFactor);
  if(![window respondsToSelector:selector]) return 1.0;
  NSInvocation *inv=[NSInvocation invocationWithMethodSignature:[window methodSignatureForSelector:selector]];
  CGFloat scale=1.0;
  [inv setTarget:window]; [inv setSelector:selector]; [inv invoke]; [inv getReturnValue:&scale];
  return scale>=1.0?scale:1.0;
}
/* Big Sur's expanded style preserves the separate, full-height toolbar.
   Earlier systems already use the classic toolbar layout. */
void RDUseExpandedToolbar(NSWindow *window) {
  SEL selector=@selector(setToolbarStyle:);
  if(![window respondsToSelector:selector]) return;
  NSInvocation *inv=[NSInvocation invocationWithMethodSignature:[window methodSignatureForSelector:selector]];
  NSInteger style=1; /* NSWindowToolbarStyleExpanded */
  [inv setTarget:window]; [inv setSelector:selector]; [inv setArgument:&style atIndex:2]; [inv invoke];
}
void RDBeginSheet(NSWindow *sheet,NSWindow *window,id delegate,SEL didEnd) {
  [NSApp beginSheet:sheet modalForWindow:window modalDelegate:delegate didEndSelector:didEnd contextInfo:NULL];
}
void RDStyleButton(NSButton *button) { [button setBezelStyle:NSRoundedBezelStyle]; }
void RDSetAppDelegate(NSApplication *application,id delegate) { [application setDelegate:delegate]; }
void RDAlert(NSString *message) {
  NSAlert *alert=[[[NSAlert alloc] init] autorelease]; [alert setMessageText:message]; [alert addButtonWithTitle:@"OK"]; [alert runModal];
}
void RDBeginAlertSheet(NSAlert *alert,NSWindow *window,id delegate,SEL didEnd) {
  [alert beginSheetModalForWindow:window modalDelegate:delegate didEndSelector:didEnd contextInfo:NULL];
}
NSImage *RDYouTubeIcon(CGFloat scale) {
  static NSMutableDictionary *cache=nil;
  if(!cache) cache=[[NSMutableDictionary alloc] init];
  NSNumber *key=[NSNumber numberWithDouble:scale]; NSImage *image=[cache objectForKey:key];
  if(image) return image;
  image=[AIFontAwesome imageForCodePoint:0xf167 style:AIFontAwesomeStyleBrands iconSize:24 canvasSize:32 scale:scale];
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
  if(image) [cache setObject:image forKey:key];
  return image;
}
NSString *RDChooseCookieFile(void) {
  NSOpenPanel *panel=[NSOpenPanel openPanel]; [panel setCanChooseDirectories:NO]; [panel setAllowsMultipleSelection:NO];
  if([panel runModalForDirectory:nil file:nil types:nil]==NSOKButton) return [panel filename];
  return nil;
}
void RDRevealInFinder(NSString *path) {
  if(!path || ![[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""])
    RDAlert(@"Could not reveal this file in Finder. Check that the download exists.");
}
NSString *RDDefaultApplication(NSString *path) {
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
void RDOpenInVLC(NSString *path) {
  NSString *application=[[NSWorkspace sharedWorkspace] fullPathForApplication:@"VLC"];
  if(path && application && ![[NSWorkspace sharedWorkspace] openFile:path withApplication:application]) RDAlert(@"Could not open this file in VLC.");
}
void RDOpenDefaultApplication(NSString *path) {
  if(!path || ![[NSWorkspace sharedWorkspace] openFile:path])
    RDAlert(@"Could not open this file in its default app. Check that the download exists and choose an app in Finder’s Open With settings.");
}
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
