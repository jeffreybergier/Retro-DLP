#ifndef RETRO_DLP_PLATFORM_H
#define RETRO_DLP_PLATFORM_H

#include <stddef.h>
#include <curl/curl.h>

const char *retro_dlp_platform(void);
int retro_dlp_configure_curl(CURL *curl);
int retro_dlp_default_ca_bundle_path(char *path, size_t path_size);

#endif
