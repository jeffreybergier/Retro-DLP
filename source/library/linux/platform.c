#include "platform.h"

const char *retro_dlp_platform(void) {
  return "Linux";
}

int retro_dlp_configure_curl(CURL *curl) {
  (void)curl;
  return 0;
}

int retro_dlp_default_ca_bundle_path(char *path, size_t path_size) {
  if (path != NULL && path_size != 0)
    path[0] = '\0';
  return 0;
}
