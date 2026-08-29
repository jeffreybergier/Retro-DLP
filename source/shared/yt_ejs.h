#ifndef RETRO_DLP_YT_EJS_H
#define RETRO_DLP_YT_EJS_H

#include <stddef.h>

typedef enum {
  YT_EJS_OK = 0,
  YT_EJS_ERR_INVALID_ARGUMENT,
  YT_EJS_ERR_OUT_OF_MEMORY,
  YT_EJS_ERR_JAVASCRIPT,
  YT_EJS_ERR_TIMEOUT,
  YT_EJS_ERR_CANCELLED,
  YT_EJS_ERR_INVALID_RESULT,
  YT_EJS_ERR_ASSETS_MISSING,
  YT_EJS_ERR_ASSETS_INVALID
} YTEJSStatus;

typedef enum {
  YT_EJS_CHALLENGE_SIGNATURE = 0,
  YT_EJS_CHALLENGE_N
} YTEJSChallengeType;

typedef enum {
  YT_EJS_SOURCE_PLAYER = 0,
  YT_EJS_SOURCE_PREPROCESSED
} YTEJSSourceType;

typedef struct {
  YTEJSChallengeType type;
  const char *const *challenges;
  size_t challenge_count;
} YTEJSRequest;

typedef struct {
  char **solutions;
  size_t solution_count;
  char *error;
} YTEJSResponse;

typedef struct {
  YTEJSResponse *responses;
  size_t response_count;
  char *preprocessed_player;
  char *error_message;
} YTEJSResult;

typedef struct {
  size_t memory_limit_bytes;
  size_t stack_limit_bytes;
  unsigned long timeout_milliseconds;
} YTEJSConfig;

#ifndef YT_HTTP_SESSION_TYPE_DEFINED
#define YT_HTTP_SESSION_TYPE_DEFINED
typedef struct YTHttpSession YTHttpSession;
#endif

YTEJSConfig yt_ejs_default_config(void);

YTEJSStatus yt_ejs_solve_with_session(YTHttpSession *session,
                                      YTEJSSourceType source_type,
                                      const char *player_source,
                                      const YTEJSRequest *requests,
                                      size_t request_count,
                                      const YTEJSConfig *config,
                                      YTEJSResult *result);

void yt_ejs_result_free(YTEJSResult *result);
const char *yt_ejs_status_string(YTEJSStatus status);

#endif
