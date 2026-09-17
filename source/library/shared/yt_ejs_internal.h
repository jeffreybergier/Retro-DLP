#ifndef RETRO_DLP_YT_EJS_INTERNAL_H
#define RETRO_DLP_YT_EJS_INTERNAL_H

#include "yt_ejs.h"

/* Exposed only so deterministic tests can exercise protocol validation. */
YTEJSStatus yt_ejs_parse_result_json(const char *json,
                                     const YTEJSRequest *requests,
                                     size_t request_count,
                                     YTEJSResult *result);

#endif
