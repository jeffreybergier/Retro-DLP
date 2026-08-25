#if !defined(__APPLE__)
#define _POSIX_C_SOURCE 200112L
#endif

#include "yt_cache.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "yt_crypto.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define CACHE_MAGIC "RETRODLP1\n"
#define CACHE_HEADER_MAX 96U

typedef struct {
  const char *directory;
  size_t maximum_entry_size;
  size_t maximum_total_size;
  size_t maximum_entries;
} YTCachePolicy;

static const YTCachePolicy cache_policies[] = {
    {"client-manifest", 256U * 1024U, 512U * 1024U, 2},
    {"player-javascript", 8U * 1024U * 1024U, 16U * 1024U * 1024U, 4},
    {"preprocessed-player", 8U * 1024U * 1024U, 16U * 1024U * 1024U, 4},
    {"successful-client", 64U * 1024U, 64U * 1024U, 1},
    {"failures", 64U * 1024U, 4U * 1024U * 1024U, 64}};

static unsigned long temporary_counter;

static int relative_path_is_safe(const char *path) {
  const char *component;
  const char *cursor;

  if (path == NULL || path[0] == '\0' || path[0] == '/')
    return 0;
  component = path;
  cursor = path;
  for (;;) {
    if (*cursor == '/' || *cursor == '\0') {
      size_t length = (size_t)(cursor - component);
      if (length == 0 || (length == 1 && component[0] == '.') ||
          (length == 2 && component[0] == '.' && component[1] == '.'))
        return 0;
      if (*cursor == '\0')
        break;
      component = cursor + 1;
    } else if ((unsigned char)*cursor < 0x20 || *cursor == '\\') {
      return 0;
    }
    ++cursor;
  }
  return 1;
}

static int key_is_safe(const char *key) {
  const unsigned char *cursor;

  if (key == NULL || key[0] == '\0' || strlen(key) > 128)
    return 0;
  cursor = (const unsigned char *)key;
  while (*cursor != '\0') {
    if (!( (*cursor >= 'a' && *cursor <= 'z') ||
           (*cursor >= 'A' && *cursor <= 'Z') ||
           (*cursor >= '0' && *cursor <= '9') || *cursor == '-' ||
           *cursor == '_' || *cursor == '.'))
      return 0;
    ++cursor;
  }
  return strcmp(key, ".") != 0 && strcmp(key, "..") != 0;
}

YTCacheStatus yt_cache_root(char *buffer, size_t buffer_size) {
  const char *home;
  size_t home_length;
  static const char suffix[] = "/.retro-dlp/cache";

  if (buffer == NULL || buffer_size == 0)
    return YT_CACHE_INVALID_ARGUMENT;
  buffer[0] = '\0';
  home = getenv("HOME");
  if (home == NULL || home[0] != '/')
    return YT_CACHE_HOME_UNAVAILABLE;
  home_length = strlen(home);
  while (home_length > 1 && home[home_length - 1] == '/')
    --home_length;
  if (home_length + sizeof(suffix) > buffer_size)
    return YT_CACHE_TOO_LARGE;
  memcpy(buffer, home, home_length);
  memcpy(buffer + home_length, suffix, sizeof(suffix));
  return YT_CACHE_OK;
}

static YTCacheStatus ensure_directory(const char *path) {
  struct stat information;

  if (lstat(path, &information) == 0)
    return S_ISDIR(information.st_mode) ? YT_CACHE_OK : YT_CACHE_IO_ERROR;
  if (errno != ENOENT)
    return YT_CACHE_IO_ERROR;
  if (mkdir(path, 0700) == 0)
    return YT_CACHE_OK;
  if (errno == EEXIST && lstat(path, &information) == 0 &&
      S_ISDIR(information.st_mode))
    return YT_CACHE_OK;
  return YT_CACHE_IO_ERROR;
}

static YTCacheStatus ensure_root(void) {
  char root[PATH_MAX];
  char parent[PATH_MAX];
  char *separator;
  YTCacheStatus status;

  status = yt_cache_root(root, sizeof(root));
  if (status != YT_CACHE_OK)
    return status;
  if (strlen(root) >= sizeof(parent))
    return YT_CACHE_TOO_LARGE;
  memcpy(parent, root, strlen(root) + 1);
  separator = strrchr(parent, '/');
  if (separator == NULL)
    return YT_CACHE_IO_ERROR;
  *separator = '\0';
  status = ensure_directory(parent);
  if (status != YT_CACHE_OK)
    return status;
  return ensure_directory(root);
}

static YTCacheStatus build_path(const char *relative_path, char *path,
                                size_t path_size) {
  char root[PATH_MAX];
  size_t root_length;
  size_t relative_length;
  YTCacheStatus status;

  if (!relative_path_is_safe(relative_path))
    return YT_CACHE_INVALID_ARGUMENT;
  status = yt_cache_root(root, sizeof(root));
  if (status != YT_CACHE_OK)
    return status;
  root_length = strlen(root);
  relative_length = strlen(relative_path);
  if (root_length + 1 + relative_length + 1 > path_size)
    return YT_CACHE_TOO_LARGE;
  memcpy(path, root, root_length);
  path[root_length] = '/';
  memcpy(path + root_length + 1, relative_path, relative_length + 1);
  return YT_CACHE_OK;
}

static YTCacheStatus ensure_parent_directories(const char *relative_path) {
  char root[PATH_MAX];
  char path[PATH_MAX];
  const char *cursor;
  size_t used;
  YTCacheStatus status;

  status = ensure_root();
  if (status != YT_CACHE_OK)
    return status;
  status = yt_cache_root(root, sizeof(root));
  if (status != YT_CACHE_OK)
    return status;
  used = strlen(root);
  memcpy(path, root, used + 1);
  cursor = relative_path;
  while ((cursor = strchr(cursor, '/')) != NULL) {
    size_t component_length = (size_t)(cursor - relative_path);
    if (used + 1 + component_length + 1 > sizeof(path))
      return YT_CACHE_TOO_LARGE;
    path[used] = '/';
    memcpy(path + used + 1, relative_path, component_length);
    path[used + 1 + component_length] = '\0';
    status = ensure_directory(path);
    if (status != YT_CACHE_OK)
      return status;
    cursor++;
  }
  return YT_CACHE_OK;
}

YTCacheStatus yt_cache_read_file(const char *relative_path, size_t maximum_size,
                                 char **data, size_t *length) {
  char path[PATH_MAX];
  struct stat information;
  int descriptor;
  int open_flags;
  char *buffer;
  size_t offset;
  YTCacheStatus status;

  if (data == NULL || length == NULL || maximum_size == 0)
    return YT_CACHE_INVALID_ARGUMENT;
  *data = NULL;
  *length = 0;
  status = build_path(relative_path, path, sizeof(path));
  if (status != YT_CACHE_OK)
    return status;
  open_flags = O_RDONLY;
#ifdef O_NOFOLLOW
  open_flags |= O_NOFOLLOW;
#endif
  descriptor = open(path, open_flags);
  if (descriptor < 0)
    return errno == ENOENT ? YT_CACHE_MISSING : YT_CACHE_IO_ERROR;
  if (fstat(descriptor, &information) != 0 ||
      !S_ISREG(information.st_mode) || information.st_size < 0) {
    close(descriptor);
    return YT_CACHE_CORRUPT;
  }
  if ((uint64_t)information.st_size > (uint64_t)maximum_size) {
    close(descriptor);
    return YT_CACHE_TOO_LARGE;
  }
  buffer = (char *)malloc((size_t)information.st_size + 1);
  if (buffer == NULL) {
    close(descriptor);
    return YT_CACHE_OUT_OF_MEMORY;
  }
  offset = 0;
  while (offset < (size_t)information.st_size) {
    ssize_t count = read(descriptor, buffer + offset,
                         (size_t)information.st_size - offset);
    if (count <= 0) {
      free(buffer);
      close(descriptor);
      return YT_CACHE_IO_ERROR;
    }
    offset += (size_t)count;
  }
  if (close(descriptor) != 0) {
    free(buffer);
    return YT_CACHE_IO_ERROR;
  }
  buffer[offset] = '\0';
  *data = buffer;
  *length = offset;
  return YT_CACHE_OK;
}

YTCacheStatus yt_cache_write_file_atomic(const char *relative_path,
                                         const void *data, size_t length) {
  char path[PATH_MAX];
  char temporary[PATH_MAX];
  int descriptor;
  size_t offset;
  int failed;
  YTCacheStatus status;

  if ((data == NULL && length != 0) || !relative_path_is_safe(relative_path))
    return YT_CACHE_INVALID_ARGUMENT;
  status = ensure_parent_directories(relative_path);
  if (status != YT_CACHE_OK)
    return status;
  status = build_path(relative_path, path, sizeof(path));
  if (status != YT_CACHE_OK)
    return status;
  if (snprintf(temporary, sizeof(temporary), "%s.tmp.%ld.%lu", path,
               (long)getpid(), ++temporary_counter) >=
      (int)sizeof(temporary))
    return YT_CACHE_TOO_LARGE;
  descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (descriptor < 0)
    return YT_CACHE_IO_ERROR;
  offset = 0;
  failed = 0;
  while (offset < length) {
    ssize_t count = write(descriptor, (const char *)data + offset,
                          length - offset);
    if (count <= 0) {
      failed = 1;
      break;
    }
    offset += (size_t)count;
  }
  if (!failed && fsync(descriptor) != 0)
    failed = 1;
  if (close(descriptor) != 0)
    failed = 1;
  if (!failed && rename(temporary, path) != 0)
    failed = 1;
  if (failed) {
    unlink(temporary);
    return YT_CACHE_IO_ERROR;
  }
  return YT_CACHE_OK;
}

YTCacheStatus yt_cache_remove_file(const char *relative_path) {
  char path[PATH_MAX];
  YTCacheStatus status;

  status = build_path(relative_path, path, sizeof(path));
  if (status != YT_CACHE_OK)
    return status;
  if (unlink(path) == 0)
    return YT_CACHE_OK;
  return errno == ENOENT ? YT_CACHE_MISSING : YT_CACHE_IO_ERROR;
}

void yt_cache_key_for_string(const char *value, char key[65]) {
  if (value == NULL) {
    key[0] = '\0';
    return;
  }
  if (yt_crypto_sha256_hex(value, strlen(value), key) != 0)
    key[0] = '\0';
}

static const YTCachePolicy *policy_for_kind(YTCacheKind kind) {
  if ((int)kind < 0 || (size_t)kind >=
                           sizeof(cache_policies) / sizeof(cache_policies[0]))
    return NULL;
  return &cache_policies[(size_t)kind];
}

static YTCacheStatus entry_path(YTCacheKind kind, const char *key, char *path,
                                size_t path_size) {
  const YTCachePolicy *policy;

  policy = policy_for_kind(kind);
  if (policy == NULL || !key_is_safe(key))
    return YT_CACHE_INVALID_ARGUMENT;
  if (snprintf(path, path_size, "v1/%s/%s.entry", policy->directory, key) >=
      (int)path_size)
    return YT_CACHE_TOO_LARGE;
  return YT_CACHE_OK;
}

static YTCacheStatus prune_kind(YTCacheKind kind) {
  const YTCachePolicy *policy;
  char relative[PATH_MAX];
  char directory_path[PATH_MAX];
  DIR *directory;
  struct dirent *entry;
  size_t total_size;
  size_t total_entries;
  YTCacheStatus status;

  policy = policy_for_kind(kind);
  if (policy == NULL)
    return YT_CACHE_INVALID_ARGUMENT;
  if (snprintf(relative, sizeof(relative), "v1/%s", policy->directory) >=
      (int)sizeof(relative))
    return YT_CACHE_TOO_LARGE;
  status = build_path(relative, directory_path, sizeof(directory_path));
  if (status != YT_CACHE_OK)
    return status;

  for (;;) {
    char oldest_path[PATH_MAX];
    time_t oldest_time;
    int have_oldest;

    directory = opendir(directory_path);
    if (directory == NULL)
      return errno == ENOENT ? YT_CACHE_OK : YT_CACHE_IO_ERROR;
    total_size = 0;
    total_entries = 0;
    have_oldest = 0;
    oldest_time = 0;
    oldest_path[0] = '\0';
    while ((entry = readdir(directory)) != NULL) {
      char candidate[PATH_MAX];
      struct stat information;
      size_t name_length;

      if (entry->d_name[0] == '.')
        continue;
      name_length = strlen(entry->d_name);
      if (name_length < 6 ||
          strcmp(entry->d_name + name_length - 6, ".entry") != 0)
        continue;
      if (snprintf(candidate, sizeof(candidate), "%s/%s", directory_path,
                   entry->d_name) >= (int)sizeof(candidate))
        continue;
      if (lstat(candidate, &information) != 0 ||
          !S_ISREG(information.st_mode))
        continue;
      ++total_entries;
      if (information.st_size > 0)
        total_size += (size_t)information.st_size;
      if (!have_oldest || information.st_mtime < oldest_time) {
        memcpy(oldest_path, candidate, strlen(candidate) + 1);
        oldest_time = information.st_mtime;
        have_oldest = 1;
      }
    }
    closedir(directory);
    if (total_entries <= policy->maximum_entries &&
        total_size <= policy->maximum_total_size)
      return YT_CACHE_OK;
    if (!have_oldest || unlink(oldest_path) != 0)
      return YT_CACHE_IO_ERROR;
  }
}

YTCacheStatus yt_cache_put(YTCacheKind kind, const char *key,
                           const void *data, size_t length,
                           int64_t expires_unix) {
  const YTCachePolicy *policy;
  char relative[PATH_MAX];
  char header[CACHE_HEADER_MAX];
  int header_length;
  char *entry;
  YTCacheStatus status;

  policy = policy_for_kind(kind);
  if (policy == NULL || (data == NULL && length != 0) ||
      length > policy->maximum_entry_size)
    return length > (policy == NULL ? 0 : policy->maximum_entry_size)
               ? YT_CACHE_TOO_LARGE
               : YT_CACHE_INVALID_ARGUMENT;
  status = entry_path(kind, key, relative, sizeof(relative));
  if (status != YT_CACHE_OK)
    return status;
  header_length = snprintf(header, sizeof(header), CACHE_MAGIC "%lld\n%lu\n",
                           (long long)expires_unix, (unsigned long)length);
  if (header_length < 0 || (size_t)header_length >= sizeof(header))
    return YT_CACHE_TOO_LARGE;
  if ((size_t)header_length > (size_t)-1 - length)
    return YT_CACHE_TOO_LARGE;
  entry = (char *)malloc((size_t)header_length + length);
  if (entry == NULL)
    return YT_CACHE_OUT_OF_MEMORY;
  memcpy(entry, header, (size_t)header_length);
  if (length != 0)
    memcpy(entry + header_length, data, length);
  status = yt_cache_write_file_atomic(relative, entry,
                                      (size_t)header_length + length);
  free(entry);
  if (status != YT_CACHE_OK)
    return status;
  return prune_kind(kind);
}

YTCacheStatus yt_cache_get(YTCacheKind kind, const char *key,
                           int64_t now_unix, char **data, size_t *length) {
  const YTCachePolicy *policy;
  char relative[PATH_MAX];
  char *entry;
  size_t entry_length;
  char *first_newline;
  char *second_newline;
  char *third_newline;
  int64_t expires;
  unsigned long payload_length;
  char *end;
  char *payload;
  YTCacheStatus status;

  if (data == NULL || length == NULL)
    return YT_CACHE_INVALID_ARGUMENT;
  *data = NULL;
  *length = 0;
  policy = policy_for_kind(kind);
  if (policy == NULL)
    return YT_CACHE_INVALID_ARGUMENT;
  status = entry_path(kind, key, relative, sizeof(relative));
  if (status != YT_CACHE_OK)
    return status;
  status = yt_cache_read_file(relative,
                              policy->maximum_entry_size + CACHE_HEADER_MAX,
                              &entry, &entry_length);
  if (status != YT_CACHE_OK)
    return status;
  first_newline = strchr(entry, '\n');
  second_newline = first_newline == NULL ? NULL : strchr(first_newline + 1, '\n');
  third_newline = second_newline == NULL ? NULL : strchr(second_newline + 1, '\n');
  if (first_newline == NULL || second_newline == NULL || third_newline == NULL ||
      (size_t)(first_newline - entry + 1) != strlen(CACHE_MAGIC) ||
      memcmp(entry, CACHE_MAGIC, strlen(CACHE_MAGIC)) != 0) {
    free(entry);
    yt_cache_remove_file(relative);
    return YT_CACHE_CORRUPT;
  }
  *second_newline = '\0';
  expires = (int64_t)strtoll(first_newline + 1, &end, 10);
  if (end != second_newline) {
    free(entry);
    yt_cache_remove_file(relative);
    return YT_CACHE_CORRUPT;
  }
  *third_newline = '\0';
  payload_length = strtoul(second_newline + 1, &end, 10);
  if (end != third_newline || payload_length > policy->maximum_entry_size ||
      (size_t)(third_newline + 1 - entry) + (size_t)payload_length !=
          entry_length) {
    free(entry);
    yt_cache_remove_file(relative);
    return YT_CACHE_CORRUPT;
  }
  if (expires != 0 && now_unix >= expires) {
    free(entry);
    yt_cache_remove_file(relative);
    return YT_CACHE_EXPIRED;
  }
  payload = (char *)malloc((size_t)payload_length + 1);
  if (payload == NULL) {
    free(entry);
    return YT_CACHE_OUT_OF_MEMORY;
  }
  memcpy(payload, third_newline + 1, (size_t)payload_length);
  payload[payload_length] = '\0';
  free(entry);
  *data = payload;
  *length = (size_t)payload_length;
  return YT_CACHE_OK;
}

YTCacheStatus yt_cache_remove(YTCacheKind kind, const char *key) {
  char relative[PATH_MAX];
  YTCacheStatus status;

  status = entry_path(kind, key, relative, sizeof(relative));
  if (status != YT_CACHE_OK)
    return status;
  return yt_cache_remove_file(relative);
}

YTCacheStatus yt_cache_clear(YTCacheKind kind) {
  const YTCachePolicy *policy;
  char relative[PATH_MAX];
  char directory_path[PATH_MAX];
  DIR *directory;
  struct dirent *entry;
  YTCacheStatus status;

  policy = policy_for_kind(kind);
  if (policy == NULL)
    return YT_CACHE_INVALID_ARGUMENT;
  if (snprintf(relative, sizeof(relative), "v1/%s", policy->directory) >=
      (int)sizeof(relative))
    return YT_CACHE_TOO_LARGE;
  status = build_path(relative, directory_path, sizeof(directory_path));
  if (status != YT_CACHE_OK)
    return status;
  directory = opendir(directory_path);
  if (directory == NULL)
    return errno == ENOENT ? YT_CACHE_OK : YT_CACHE_IO_ERROR;
  while ((entry = readdir(directory)) != NULL) {
    char candidate[PATH_MAX];
    size_t name_length = strlen(entry->d_name);

    if (entry->d_name[0] == '.' || name_length < 6 ||
        strcmp(entry->d_name + name_length - 6, ".entry") != 0)
      continue;
    if (snprintf(candidate, sizeof(candidate), "%s/%s", directory_path,
                 entry->d_name) >= (int)sizeof(candidate) ||
        unlink(candidate) != 0) {
      closedir(directory);
      return YT_CACHE_IO_ERROR;
    }
  }
  closedir(directory);
  return YT_CACHE_OK;
}

const char *yt_cache_status_string(YTCacheStatus status) {
  switch (status) {
    case YT_CACHE_OK:
      return "ok";
    case YT_CACHE_MISSING:
      return "missing";
    case YT_CACHE_EXPIRED:
      return "expired";
    case YT_CACHE_INVALID_ARGUMENT:
      return "invalid_argument";
    case YT_CACHE_HOME_UNAVAILABLE:
      return "home_unavailable";
    case YT_CACHE_IO_ERROR:
      return "io_error";
    case YT_CACHE_CORRUPT:
      return "corrupt";
    case YT_CACHE_TOO_LARGE:
      return "too_large";
    case YT_CACHE_OUT_OF_MEMORY:
      return "out_of_memory";
  }
  return "unknown";
}
