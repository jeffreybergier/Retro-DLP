#include "platform.h"

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <mach-o/dyld.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

const char *retro_dlp_platform(void) {
  return "macOS";
}

static const char *certificate_bundle_path(void) {
  static char path[PATH_MAX];
  static int initialized;
  char executable_path[PATH_MAX];
  char resolved_path[PATH_MAX];
  char *separator;
  uint32_t size;
  size_t directory_length;
  static const char filename[] = "cacert.pem";

  if (initialized)
    return path[0] == '\0' ? NULL : path;
  initialized = 1;

  size = (uint32_t)sizeof(executable_path);
  if (_NSGetExecutablePath(executable_path, &size) != 0)
    return NULL;

  if (realpath(executable_path, resolved_path) != NULL)
    memcpy(path, resolved_path, strlen(resolved_path) + 1);
  else
    memcpy(path, executable_path, strlen(executable_path) + 1);

  separator = strrchr(path, '/');
  if (separator == NULL) {
    path[0] = '\0';
    return NULL;
  }
  directory_length = (size_t)(separator - path) + 1;
  if (directory_length + sizeof(filename) > sizeof(path)) {
    path[0] = '\0';
    return NULL;
  }
  memcpy(path + directory_length, filename, sizeof(filename));
  if (access(path, R_OK) != 0) {
    path[0] = '\0';
    return NULL;
  }
  return path;
}

int retro_dlp_configure_curl(CURL *curl) {
  const char *path;

  path = certificate_bundle_path();
  if (path == NULL)
    return 1;
  return curl_easy_setopt(curl, CURLOPT_CAINFO, path) == CURLE_OK ? 0 : 1;
}
