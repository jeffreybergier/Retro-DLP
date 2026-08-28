#ifndef RETRO_DLP_YT_CACHE_H
#define RETRO_DLP_YT_CACHE_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
  YT_CACHE_OK = 0,
  YT_CACHE_MISSING,
  YT_CACHE_EXPIRED,
  YT_CACHE_INVALID_ARGUMENT,
  YT_CACHE_HOME_UNAVAILABLE,
  YT_CACHE_IO_ERROR,
  YT_CACHE_CORRUPT,
  YT_CACHE_TOO_LARGE,
  YT_CACHE_OUT_OF_MEMORY
} YTCacheStatus;

typedef enum {
  YT_CACHE_CLIENT_MANIFEST = 0,
  YT_CACHE_PLAYER_JAVASCRIPT,
  YT_CACHE_PREPROCESSED_PLAYER,
  YT_CACHE_SUCCESSFUL_CLIENT,
  YT_CACHE_FAILURE
} YTCacheKind;

YTCacheStatus yt_cache_root(char *buffer, size_t buffer_size);
YTCacheStatus yt_cache_read_file(const char *relative_path, size_t maximum_size,
                                 char **data, size_t *length);
YTCacheStatus yt_cache_write_file_atomic(const char *relative_path,
                                         const void *data, size_t length);
YTCacheStatus yt_cache_remove_file(const char *relative_path);

/* Explicit-root variants are used by the public context. A NULL root disables
 * caching and returns YT_CACHE_MISSING for reads/removals and YT_CACHE_OK for
 * writes. The legacy variants above retain CLI asset-tooling behavior. */
YTCacheStatus yt_cache_read_file_at(const char *root,
                                    const char *relative_path,
                                    size_t maximum_size, char **data,
                                    size_t *length);
YTCacheStatus yt_cache_write_file_atomic_at(const char *root,
                                            const char *relative_path,
                                            const void *data, size_t length);
YTCacheStatus yt_cache_remove_file_at(const char *root,
                                      const char *relative_path);

void yt_cache_key_for_string(const char *value, char key[65]);
YTCacheStatus yt_cache_put(YTCacheKind kind, const char *key,
                           const void *data, size_t length,
                           int64_t expires_unix);
YTCacheStatus yt_cache_get(YTCacheKind kind, const char *key,
                           int64_t now_unix, char **data, size_t *length);
YTCacheStatus yt_cache_remove(YTCacheKind kind, const char *key);
YTCacheStatus yt_cache_clear(YTCacheKind kind);
YTCacheStatus yt_cache_put_at(const char *root, YTCacheKind kind,
                              const char *key, const void *data,
                              size_t length, int64_t expires_unix);
YTCacheStatus yt_cache_get_at(const char *root, YTCacheKind kind,
                              const char *key, int64_t now_unix, char **data,
                              size_t *length);
YTCacheStatus yt_cache_remove_at(const char *root, YTCacheKind kind,
                                 const char *key);

const char *yt_cache_status_string(YTCacheStatus status);

#endif
