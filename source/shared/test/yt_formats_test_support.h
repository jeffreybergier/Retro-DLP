#ifndef RETRO_DLP_YT_FORMATS_TEST_SUPPORT_H
#define RETRO_DLP_YT_FORMATS_TEST_SUPPORT_H

#include "yt_resolver.h"

/* Low-level JSON parsing is intentionally exposed only to fixture tests. */
YTStatus yt_test_parse_player_response(const char *json, size_t length,
                                       YTMediaRequest *result);
YTStatus yt_test_parse_player_response_with_max_height(
    const char *json, size_t length, int max_height, YTMediaRequest *result);
YTStatus yt_test_parse_player_response_with_adaptive_size(
    const char *json, size_t length, int max_height,
    YTMediaSelection *result);
YTStatus yt_test_parse_player_response_with_format(
    const char *json, size_t length, const char *format_expression,
    YTMediaSelection *result);
YTStatus yt_test_parse_player_response_with_javascript(
    const char *json, size_t length, const char *player_source,
    YTMediaRequest *result);

#endif
