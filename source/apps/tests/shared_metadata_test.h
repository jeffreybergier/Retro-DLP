/* Formatting must preserve optional-value semantics on both legacy runtimes. */
static void metadataRequire(BOOL condition,NSString *message) {
  if(!condition) [NSException raise:@"MetadataRegression" format:@"%@",message];
}
static void testSharedMetadata(void) {
  NSMutableDictionary *entry=[NSMutableDictionary dictionaryWithObject:@"A video" forKey:@"title"];
  metadataRequire([[RDLPLibrary durationLabelForEntry:entry] isEqualToString:@""],@"Absent duration must stay empty");
  metadataRequire([[RDLPLibrary metadataTooltipForEntry:entry] isEqualToString:@"A video"],@"Absent metadata must not invent labels");
  [entry setObject:@"0" forKey:@"duration"]; [entry setObject:@"0" forKey:@"view_count"];
  metadataRequire([[RDLPLibrary durationLabelForEntry:entry] isEqualToString:@"0:00"],@"Zero duration must be visible");
  metadataRequire([[RDLPLibrary spokenDurationForEntry:entry] isEqualToString:@"0 seconds"],@"Zero duration must be spoken");
  metadataRequire([[RDLPLibrary metadataTooltipForEntry:entry] rangeOfString:@"0 views"].location!=NSNotFound,@"Zero views must be visible");
  [entry setObject:@"3723" forKey:@"duration"]; [entry setObject:@"Café Channel" forKey:@"channel"];
  metadataRequire([[RDLPLibrary metadataSummaryForEntry:entry] isEqualToString:@"1:02:03 · Café Channel"],@"Hour duration and Unicode channel");
  metadataRequire([[RDLPLibrary spokenDurationForEntry:entry] isEqualToString:@"1 hour, 2 minutes, 3 seconds"],@"Duration accessibility");
  [entry setObject:@"9007199254740991" forKey:@"view_count"];
  metadataRequire([[RDLPLibrary metadataTooltipForEntry:entry] rangeOfString:@"9007199254740991 views"].location!=NSNotFound,@"Exact counts must retain 64-bit precision");
  [entry setObject:@"1.2M views" forKey:@"view_count_text"]; [entry setObject:@"2 days ago" forKey:@"published_text"];
  [entry setObject:@"Available snippet…" forKey:@"description_snippet"];
  NSString *tip=[RDLPLibrary metadataTooltipForEntry:entry];
  metadataRequire([tip rangeOfString:@"At last sync: 1.2M views · Published 2 days ago"].location!=NSNotFound,@"Preserve and identify source snapshot labels");
  metadataRequire([tip rangeOfString:@"9007199254740991"].location==NSNotFound && [tip hasSuffix:@"Available snippet…"],@"Prefer original view text and include snippet");
  [entry setObject:@"123 watching" forKey:@"view_count_text"];
  metadataRequire([[RDLPLibrary metadataTooltipForEntry:entry] rangeOfString:@"123 watching"].location!=NSNotFound,@"Live-viewer label must not become cumulative views");
  [entry setObject:@"" forKey:@"duration"]; [entry removeObjectForKey:@"channel"];
  metadataRequire(![[RDLPLibrary metadataSummaryForEntry:entry] length],@"SQL NULL mapped to empty string must stay absent");
}
