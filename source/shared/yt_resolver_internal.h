#ifndef RETRO_DLP_YT_RESOLVER_INTERNAL_H
#define RETRO_DLP_YT_RESOLVER_INTERNAL_H

#include "yt_resolver.h"

int yt_failure_cache_ttl(YTStatus status);
int yt_load_cached_failure(const char *key, YTStatus *status);
void yt_remember_failure(const char *key, YTStatus status);
YTStatus yt_load_player_javascript(const char *player_url, char **source);

#endif
