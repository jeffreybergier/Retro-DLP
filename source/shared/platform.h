#ifndef RETRO_DLP_PLATFORM_H
#define RETRO_DLP_PLATFORM_H

#include <curl/curl.h>

const char *retro_dlp_platform(void);
int retro_dlp_configure_curl(CURL *curl);

#endif
