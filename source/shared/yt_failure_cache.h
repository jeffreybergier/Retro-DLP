#ifndef RETRO_DLP_YT_FAILURE_CACHE_H
#define RETRO_DLP_YT_FAILURE_CACHE_H

#include "yt_innertube.h"
#include "yt_resolver.h"

void yt_failure_cache_key(const char *video_id,
                          const YTInnertubeClient *client,
                          int authenticated, int max_height,
                          int try_adaptive, char key[65]);
void yt_failure_cache_exact_key(const char *video_id,
                                const YTInnertubeClient *client,
                                int authenticated,
                                const char *format_expression, char key[65]);
int yt_failure_cache_load(YTHttpSession *session, const char *key,
                          YTStatus *status);
void yt_failure_cache_remember(YTHttpSession *session, const char *key,
                               YTStatus status);
void yt_failure_cache_clear(YTHttpSession *session, const char *key);

#endif
