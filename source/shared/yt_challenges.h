#ifndef RETRO_DLP_YT_CHALLENGES_H
#define RETRO_DLP_YT_CHALLENGES_H

#include <stddef.h>

#include "yt_ejs.h"
#include "yt_resolver.h"

YTStatus yt_challenges_load_player(YTHttpSession *session,
                                   const char *player_url, char **source);
YTStatus yt_challenges_solve(YTHttpSession *session,
                             const char *player_source,
                             const YTEJSRequest *requests,
                             size_t request_count, YTEJSResult *result);
void yt_challenges_result_free(YTEJSResult *result);

#endif
