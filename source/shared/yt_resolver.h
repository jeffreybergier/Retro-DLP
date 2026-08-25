#ifndef RETRO_DLP_YT_RESOLVER_H
#define RETRO_DLP_YT_RESOLVER_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
  YT_OK = 0,
  YT_ERR_INVALID_VIDEO_ID,
  YT_ERR_OUT_OF_MEMORY,
  YT_ERR_NETWORK,
  YT_ERR_CERTIFICATE_BUNDLE,
  YT_ERR_HTTP,
  YT_ERR_INVALID_RESPONSE,
  YT_ERR_UNAVAILABLE,
  YT_ERR_NO_PROGRESSIVE_MP4,
  YT_ERR_PO_TOKEN_REQUIRED
} YTStatus;

typedef struct {
  char *url;
  char *mime_type;
  char *user_agent;
  int itag;
  int width;
  int height;
  int64_t expires_unix;
  int64_t content_length;
} YTMediaRequest;

YTStatus yt_extract_video_id(const char *input, char video_id[12]);
YTStatus yt_parse_player_response(const char *json, size_t length,
                                  YTMediaRequest *result);
YTStatus yt_resolve_video(const char *input, YTMediaRequest *result);
YTStatus yt_probe_media_head(const YTMediaRequest *media, long *http_status);
YTStatus yt_classify_media_http_status(long http_status);
void yt_media_request_free(YTMediaRequest *media);
const char *yt_status_string(YTStatus status);

#endif
