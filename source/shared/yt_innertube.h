#ifndef RETRO_DLP_YT_INNERTUBE_H
#define RETRO_DLP_YT_INNERTUBE_H

#include "cJSON.h"
#include "yt_resolver.h"
#include "yt_session.h"

typedef struct {
  char name[32];
  char id[16];
  char version[32];
  char user_agent[256];
} YTInnertubeClient;

#define YT_INNERTUBE_DEFAULT_USER_AGENT                                     \
  "Mozilla/5.0 (iPad; CPU OS 16_7_10 like Mac OS X) AppleWebKit/605.1.15 " \
  "(KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1,gzip(gfe)"

YTStatus yt_innertube_load_client(YTHttpSession *session,
                                  YTInnertubeClient *client);
void yt_innertube_prefer_recent_client(YTHttpSession *session,
                                       YTInnertubeClient *client,
                                       int authenticated);
void yt_innertube_remember_successful_client(
    YTHttpSession *session, const YTInnertubeClient *client,
    int authenticated);
YTStatus yt_innertube_call_player(YTHttpSession *session,
                                  const YTAccountContext *account,
                                  const char *video_id,
                                  const char *visitor_data,
                                  const YTInnertubeClient *client,
                                  int signature_timestamp,
                                  cJSON **document_out);
YTStatus yt_innertube_call_browse(
    YTHttpSession *session, const YTAccountContext *account,
    const char *api_key, const char *client_version, const char *visitor_data,
    const char *continuation, const char *playlist_id, cJSON **document_out);

#endif
