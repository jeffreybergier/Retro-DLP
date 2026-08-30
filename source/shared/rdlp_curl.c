#include "rdlp_curl.h"

#include <stddef.h>

#include <curl/curl.h>
#include <pthread.h>

static pthread_mutex_t lifecycle_mutex = PTHREAD_MUTEX_INITIALIZER;
static size_t lifecycle_count;

int rdlp_curl_acquire(void) {
  int initialized = 1;
  pthread_mutex_lock(&lifecycle_mutex);
  if (lifecycle_count == 0 &&
      curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK)
    initialized = 0;
  if (initialized)
    ++lifecycle_count;
  pthread_mutex_unlock(&lifecycle_mutex);
  return initialized;
}

void rdlp_curl_release(void) {
  pthread_mutex_lock(&lifecycle_mutex);
  if (lifecycle_count != 0 && --lifecycle_count == 0)
    curl_global_cleanup();
  pthread_mutex_unlock(&lifecycle_mutex);
}
