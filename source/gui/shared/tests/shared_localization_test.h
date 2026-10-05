/* Run only in the synthetic translated bundles from prepare_localization_probe.py.
   Exercise real bundle lookup and C startup ownership on legacy Apple runtimes. */
#include "../rdapp_strings.h"
#include <string.h>
static void testSharedLocalization(NSString *base) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  [RDLPLibrary qualityTitles]; /* Force the actual +initialize bridge. */
  const char *translated=rdapp_store_error(NULL);
  statusRequire(!strcmp(translated,"翻訳済みデータベース"),@"C startup reads the bundled translation");
  [pool drain];
  statusRequire(!strcmp(translated,"翻訳済みデータベース"),@"C UTF-8 survives the initialization autorelease pool");
  statusRequire(!strcmp(rdapp_string_key(RDAPP_STRING_CANNOT_OPEN_LIBRARY_DATABASE),"Cannot open library database"),@"English storage key remains stable");
  statusRequire([NSLocalizedString(@"Resolving video…",nil) isEqualToString:@"準備中…"],@"Cocoa reads the shared translated table");
  RDLPStatusTestLibrary *library=[[RDLPStatusTestLibrary alloc]
    initWithSupportDirectory:[base stringByAppendingPathComponent:@"Support"]
    downloadDirectory:[base stringByAppendingPathComponent:@"Downloads"]];
  statusRequire(library!=nil,@"Open translated library");
  [library addVideoInput:@"abcdefghijk"];
  NSDictionary *playlist=[library adhocPlaylist];
  statusRequire([[playlist objectForKey:@"title"] isEqualToString:@"追加した動画"],@"C rows translate the built-in playlist title");
  statusRequire([[playlist objectForKey:@"service_id"] isEqualToString:@"adhoc"] &&
    [[playlist objectForKey:@"directory"] hasPrefix:@"Playlists/Added Videos"],@"Translated display keeps identifiers and paths stable");
  [library setValue:[NSDictionary dictionaryWithObject:@"download" forKey:@"type"] forKey:@"activeCommand_"];
  [library resolverEvent:RDLP_EVENT_LOADING_CONFIGURATION]; statusWait(0.05);
  statusRequire([[library status] isEqualToString:@"設定中…"],@"Resolver events use the translated shared table");
  [library shutdown]; [library release];
}
