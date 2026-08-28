#ifndef RETRO_DLP_YT_FORMATS_H
#define RETRO_DLP_YT_FORMATS_H

#include "cJSON.h"
#include "yt_innertube.h"
#include "yt_resolver.h"

YTStatus yt_formats_attach_metadata(cJSON *document, const char *video_id,
                                    YTMediaSelection *result);
YTStatus yt_formats_select(YTHttpSession *session, cJSON *document,
                           const char *player_source,
                           const YTInnertubeClient *client, int max_height,
                           int try_adaptive, YTMediaSelection *result);
YTStatus yt_formats_select_exact(YTHttpSession *session, cJSON *document,
                                 const char *player_source,
                                 const YTInnertubeClient *client,
                                 const char *format_expression,
                                 YTMediaSelection *result);

#endif
