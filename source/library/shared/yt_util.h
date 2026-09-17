#ifndef RETRO_DLP_YT_UTIL_H
#define RETRO_DLP_YT_UTIL_H

#include "cJSON.h"

char *yt_copy_string(const char *value);
int yt_copy_field(char *destination, size_t capacity, const char *value);
const char *yt_json_string(cJSON *object, const char *name);

#endif
