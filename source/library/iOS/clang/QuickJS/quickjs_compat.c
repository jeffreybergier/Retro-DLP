#include "quickjs_compat.h"

#include <sys/time.h>

int retro_dlp_ios_clock_gettime(int clock_id, struct timespec *time_value) {
  struct timeval value;

  (void)clock_id;
  if (time_value == NULL || gettimeofday(&value, NULL) != 0)
    return -1;
  time_value->tv_sec = value.tv_sec;
  time_value->tv_nsec = value.tv_usec * 1000;
  return 0;
}
