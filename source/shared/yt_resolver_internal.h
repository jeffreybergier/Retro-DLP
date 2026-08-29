#ifndef RETRO_DLP_YT_RESOLVER_INTERNAL_H
#define RETRO_DLP_YT_RESOLVER_INTERNAL_H

#include "yt_resolver.h"

int yt_failure_cache_ttl(YTStatus status);
void yt_failure_cache_key_for_session(const char *video_id,
                                      const char *client_name,
                                      const char *client_version,
                                      int authenticated, char key[65]);

#endif
