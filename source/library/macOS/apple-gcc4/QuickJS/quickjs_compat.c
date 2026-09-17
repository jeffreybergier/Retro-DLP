#include "quickjs_compat.h"

#include <mach/mach_time.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/time.h>
#include <time.h>

static pthread_mutex_t retroDlpAtomic64Mutex = PTHREAD_MUTEX_INITIALIZER;

#define RETRO_DLP_ATOMIC_FETCH_OPERATION(name, operation) \
  uint64_t name(volatile uint64_t *object, uint64_t operand) { \
    uint64_t previous; \
    pthread_mutex_lock(&retroDlpAtomic64Mutex); \
    previous = *object; \
    *object operation operand; \
    pthread_mutex_unlock(&retroDlpAtomic64Mutex); \
    return previous; \
  }

RETRO_DLP_ATOMIC_FETCH_OPERATION(retro_dlp_atomic_fetch_add_8, +=)
RETRO_DLP_ATOMIC_FETCH_OPERATION(retro_dlp_atomic_fetch_and_8, &=)
RETRO_DLP_ATOMIC_FETCH_OPERATION(retro_dlp_atomic_fetch_or_8, |=)
RETRO_DLP_ATOMIC_FETCH_OPERATION(retro_dlp_atomic_fetch_sub_8, -=)
RETRO_DLP_ATOMIC_FETCH_OPERATION(retro_dlp_atomic_fetch_xor_8, ^=)

uint64_t retro_dlp_atomic_exchange_8(volatile uint64_t *object,
                                     uint64_t desired) {
  uint64_t previous;
  pthread_mutex_lock(&retroDlpAtomic64Mutex);
  previous = *object;
  *object = desired;
  pthread_mutex_unlock(&retroDlpAtomic64Mutex);
  return previous;
}

uint64_t retro_dlp_atomic_load_8(volatile uint64_t *object) {
  uint64_t value;
  pthread_mutex_lock(&retroDlpAtomic64Mutex);
  value = *object;
  pthread_mutex_unlock(&retroDlpAtomic64Mutex);
  return value;
}

void retro_dlp_atomic_store_8(volatile uint64_t *object, uint64_t desired) {
  pthread_mutex_lock(&retroDlpAtomic64Mutex);
  *object = desired;
  pthread_mutex_unlock(&retroDlpAtomic64Mutex);
}

bool retro_dlp_atomic_compare_exchange_8(volatile uint64_t *object,
                                         uint64_t *expected,
                                         uint64_t desired) {
  bool exchanged;
  pthread_mutex_lock(&retroDlpAtomic64Mutex);
  exchanged = *object == *expected;
  if (exchanged)
    *object = desired;
  else
    *expected = *object;
  pthread_mutex_unlock(&retroDlpAtomic64Mutex);
  return exchanged;
}

int retro_dlp_clock_gettime(int clockId, struct timespec *timeValue) {
  if (timeValue == NULL)
    return -1;

  if (clockId == CLOCK_MONOTONIC) {
    mach_timebase_info_data_t timebase;
    uint64_t ticks;
    uint64_t nanoseconds;

    if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.denom == 0)
      return -1;

    ticks = mach_absolute_time();
    nanoseconds = (ticks / timebase.denom) * timebase.numer;
    nanoseconds += ((ticks % timebase.denom) * timebase.numer) /
                   timebase.denom;
    timeValue->tv_sec = (time_t)(nanoseconds / 1000000000ULL);
    timeValue->tv_nsec = (long)(nanoseconds % 1000000000ULL);
    return 0;
  }

  if (clockId == CLOCK_REALTIME) {
    struct timeval now;
    if (gettimeofday(&now, NULL) != 0)
      return -1;
    timeValue->tv_sec = now.tv_sec;
    timeValue->tv_nsec = now.tv_usec * 1000L;
    return 0;
  }

  return -1;
}
