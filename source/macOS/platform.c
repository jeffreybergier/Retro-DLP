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

static int certificate_bundle_path(char path[PATH_MAX]) {
  char executable_path[PATH_MAX];
  char resolved_path[PATH_MAX];
  char *separator;
  uint32_t size;
  size_t directory_length;
  static const char filename[] = "cacert.pem";

  size = (uint32_t)sizeof(executable_path);
  if (_NSGetExecutablePath(executable_path, &size) != 0)
    return 0;

  if (realpath(executable_path, resolved_path) != NULL)
    memcpy(path, resolved_path, strlen(resolved_path) + 1);
  else
    memcpy(path, executable_path, strlen(executable_path) + 1);

  separator = strrchr(path, '/');
  if (separator == NULL) {
    path[0] = '\0';
    return 0;
  }
  directory_length = (size_t)(separator - path) + 1;
  if (directory_length + sizeof(filename) > PATH_MAX) {
    path[0] = '\0';
    return 0;
  }
  memcpy(path + directory_length, filename, sizeof(filename));
  if (access(path, R_OK) != 0) {
    path[0] = '\0';
    return 0;
  }
  return 1;
}

int retro_dlp_configure_curl(CURL *curl) {
  char path[PATH_MAX];

  if (!certificate_bundle_path(path))
    return 1;
  return curl_easy_setopt(curl, CURLOPT_CAINFO, path) == CURLE_OK ? 0 : 1;
}

int retro_dlp_default_ca_bundle_path(char *path, size_t path_size) {
  char resolved[PATH_MAX];
  size_t length;
  if (path == NULL || path_size == 0 || !certificate_bundle_path(resolved))
    return 0;
  length = strlen(resolved);
  if (length + 1 > path_size)
    return 0;
  memcpy(path, resolved, length + 1);
  return 1;
}
