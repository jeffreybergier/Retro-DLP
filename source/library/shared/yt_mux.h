#ifndef RETRO_DLP_YT_MUX_H
#define RETRO_DLP_YT_MUX_H

#include <stdint.h>

#include "yt_resolver.h"

typedef int (*YTMuxCancelCallback)(void *opaque);

YTStatus yt_mux_mp4_tracks(const char *video_path, const char *audio_path,
                           const char *destination, const char *audio_language,
                           int64_t *bytes_written,
                           YTMuxCancelCallback cancel_callback,
                           void *cancel_opaque);

#endif
