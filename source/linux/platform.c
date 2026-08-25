#include "platform.h"

const char *retro_dlp_platform(void) {
  return "Linux";
}

int retro_dlp_configure_curl(CURL *curl) {
  (void)curl;
  return 0;
}
