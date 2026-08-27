#include <stdio.h>

#include <curl/curl.h>

#include "test/self_test.h"

int main(void) {
  int result;
  if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
    fprintf(stderr, "FAIL: could not initialize libcurl\n");
    return 1;
  }
  result = retro_dlp_run_self_tests();
  curl_global_cleanup();
  return result;
}
