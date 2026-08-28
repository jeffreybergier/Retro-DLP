#ifndef RETRO_DLP_YT_RESOLVER_H
#define RETRO_DLP_YT_RESOLVER_H

#include <stddef.h>
#include <stdint.h>

typedef struct YTHttpSession YTHttpSession;

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
  YT_ERR_EJS_ASSETS_MISSING,
  YT_ERR_JS_CHALLENGE,
  YT_ERR_FILE_EXISTS,
  YT_ERR_STORAGE,
  YT_ERR_INVALID_MEDIA,
  YT_ERR_PO_TOKEN_REQUIRED,
  YT_ERR_COOKIE_FILE,
  YT_ERR_AUTH_COOKIES_INVALID,
  YT_ERR_MUX,
  YT_ERR_INVALID_FORMAT,
  YT_ERR_FORMAT_UNAVAILABLE,
  YT_ERR_INVALID_PLAYLIST,
  YT_ERR_CANCELLED
} YTStatus;

typedef struct {
  char *url;
  char *mime_type;
  char *user_agent;
  int itag;
  int width;
  int height;
  int fps;
  int bitrate;
  int audio_channels;
  int64_t expires_unix;
  int64_t content_length;
} YTMediaRequest;

typedef struct {
  char *mime_type;
  int itag;
  int width;
  int height;
  int fps;
  int bitrate;
  int audio_channels;
  int64_t content_length;
  int has_video;
  int has_audio;
  int supported;
  int is_drc;
} YTFormatInfo;

typedef struct {
  YTMediaRequest video;
  YTMediaRequest audio;
  int adaptive;
  char *video_id;
  char *title;
  char *format_id;
  YTFormatInfo *formats;
  size_t format_count;
} YTMediaSelection;

typedef void (*YTProgressCallback)(const char *message, void *opaque);

#define YT_DEFAULT_MAX_HEIGHT 720

YTStatus yt_extract_video_id(const char *input, char video_id[12]);
YTStatus yt_parse_player_response(const char *json, size_t length,
                                  YTMediaRequest *result);
YTStatus yt_parse_player_response_with_max_height(const char *json,
                                                  size_t length,
                                                  int max_height,
                                                  YTMediaRequest *result);
YTStatus yt_parse_player_response_with_adaptive_size(
    const char *json, size_t length, int max_height,
    YTMediaSelection *result);
YTStatus yt_parse_player_response_with_format(const char *json, size_t length,
                                              const char *format_expression,
                                              YTMediaSelection *result);
YTStatus yt_parse_player_response_with_javascript(const char *json,
                                                  size_t length,
                                                  const char *player_source,
                                                  YTMediaRequest *result);
YTStatus yt_resolve_video(const char *input, YTMediaRequest *result);
YTStatus yt_resolve_video_with_progress(const char *input,
                                        YTMediaRequest *result,
                                        YTProgressCallback progress,
                                        void *progress_opaque);
YTStatus yt_resolve_video_with_cookies_and_progress(
    const char *input, const char *cookie_file, YTMediaRequest *result,
    YTProgressCallback progress, void *progress_opaque);
YTStatus yt_resolve_video_with_http_session_and_progress(
    YTHttpSession *session, const char *input, const char *cookie_file,
    YTMediaRequest *result, YTProgressCallback progress,
    void *progress_opaque);
YTStatus yt_resolve_video_with_http_session_and_max_height_and_progress(
    YTHttpSession *session, const char *input, const char *cookie_file,
    int max_height, YTMediaRequest *result, YTProgressCallback progress,
    void *progress_opaque);
YTStatus yt_resolve_video_with_http_session_and_size_and_progress(
    YTHttpSession *session, const char *input, const char *cookie_file,
    int max_height, int try_adaptive, YTMediaSelection *result,
    YTProgressCallback progress, void *progress_opaque);
YTStatus yt_resolve_video_with_http_session_and_format_and_progress(
    YTHttpSession *session, const char *input, const char *cookie_file,
    const char *format_expression, int list_only, YTMediaSelection *result,
    YTProgressCallback progress, void *progress_opaque);
int yt_format_expression_valid(const char *expression);
YTStatus yt_probe_media_head(const YTMediaRequest *media, long *http_status);
YTStatus yt_classify_media_http_status(long http_status);
const char *yt_resolver_user_agent(void);
void yt_media_request_free(YTMediaRequest *media);
void yt_format_info_free(YTFormatInfo *format);
void yt_media_selection_free(YTMediaSelection *selection);
const char *yt_status_string(YTStatus status);

#endif
