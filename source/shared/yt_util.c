#include "yt_util.h"

#include <stdlib.h>
#include <string.h>

char *yt_copy_string(const char *value) {
  size_t length;
  char *copy;
  if (value == NULL)
    return NULL;
  length = strlen(value);
  copy = (char *)malloc(length + 1);
  if (copy != NULL)
    memcpy(copy, value, length + 1);
  return copy;
}

int yt_copy_field(char *destination, size_t capacity, const char *value) {
  size_t length;
  if (destination == NULL || capacity == 0 || value == NULL)
    return 0;
  length = strlen(value);
  if (length >= capacity)
    return 0;
  memcpy(destination, value, length + 1);
  return 1;
}

const char *yt_json_string(cJSON *object, const char *name) {
  cJSON *value = cJSON_GetObjectItemCaseSensitive(object, name);
  return cJSON_IsString(value) ? value->valuestring : NULL;
}
