#ifndef RETRO_DLP_IOS_QUICKJS_COMPAT_H
#define RETRO_DLP_IOS_QUICKJS_COMPAT_H

#include <time.h>

#ifndef CLOCK_REALTIME
#define CLOCK_REALTIME 0
#endif

#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC 1
#endif

int retro_dlp_ios_clock_gettime(int clock_id, struct timespec *time_value);

#define clock_gettime retro_dlp_ios_clock_gettime

#endif
