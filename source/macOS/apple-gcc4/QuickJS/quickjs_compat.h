#ifndef RETRO_DLP_LEGACY_QUICKJS_COMPAT_H
#define RETRO_DLP_LEGACY_QUICKJS_COMPAT_H

struct timespec;

#ifndef CLOCK_REALTIME
#define CLOCK_REALTIME 0
#endif

#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC 1
#endif

int retro_dlp_clock_gettime(int clockId, struct timespec *timeValue);
#define clock_gettime retro_dlp_clock_gettime

#endif
