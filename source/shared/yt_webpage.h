#ifndef RETRO_DLP_YT_WEBPAGE_H
#define RETRO_DLP_YT_WEBPAGE_H

#include "cJSON.h"
#include "yt_innertube.h"
#include "yt_session.h"

char *yt_webpage_string_after_marker(const char *text, const char *marker);
int yt_webpage_integer_after_marker(const char *text, const char *marker,
                                    int allow_zero, int *found);
int yt_webpage_true_after_marker(const char *text, const char *marker);
cJSON *yt_webpage_embedded_json(const char *page, const char *marker);
char *yt_webpage_absolute_player_url(const char *value);
char *yt_webpage_player_url_from_document(cJSON *document);
YTStatus yt_webpage_load_mweb_bootstrap(
    YTHttpSession *session, YTAccountContext *account, const char *video_id,
    YTInnertubeClient *client, int *signature_timestamp, char **player_url);
YTStatus yt_webpage_load_player_url(YTHttpSession *session,
                                    const char *video_id, char **player_url);

#endif
