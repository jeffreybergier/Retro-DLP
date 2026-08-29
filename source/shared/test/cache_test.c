#if !defined(__APPLE__)
#define _XOPEN_SOURCE 600
#endif

#include "cache_test.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "yt_cache.h"
#include "yt_challenges.h"
#include "yt_crypto.h"
#include "yt_failure_cache.h"
#include "yt_http.h"
#include "yt_resolver_internal.h"

static int test_sha256(void) {
  char digest[65];

  printf("RUN: OpenSSL SHA-256 wrapper\n");
  fflush(stdout);
  if (yt_crypto_sha256_hex("abc", 3, digest) != 0 ||
      strcmp(digest,
             "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") !=
          0) {
    fprintf(stderr, "FAIL: OpenSSL SHA-256 wrapper\n");
    return 1;
  }
  printf("PASS: OpenSSL SHA-256\n");
  return 0;
}

static int exercise_cache(const char *temporary_home) {
  static const char payload[] = "cached-value";
  char root[4096];
  char expected_root[4096];
  char key[65];
  char *loaded;
  size_t loaded_length;
  YTCacheStatus status;
  int failures;
  int retained;
  char *player_source;
  YTHttpSessionConfig session_config;
  YTHttpSession *session;

  printf("RUN: cache filesystem behavior\n");
  fflush(stdout);
  failures = 0;
  if (snprintf(expected_root, sizeof(expected_root), "%s/.retro-dlp/cache",
               temporary_home) >= (int)sizeof(expected_root)) {
    fprintf(stderr, "FAIL: cache root\n");
    return 1;
  }
  memcpy(root, expected_root, strlen(expected_root) + 1);
  memset(&session_config, 0, sizeof(session_config));
  session_config.cache_directory = root;
  session = NULL;
  if (yt_http_session_create_with_config(&session_config, &session) != YT_OK) {
    fprintf(stderr, "FAIL: cache session setup\n");
    return 1;
  }
  if (yt_cache_write_file_atomic_at(root, "../escape", payload,
                                    sizeof(payload) - 1) !=
      YT_CACHE_INVALID_ARGUMENT) {
    fprintf(stderr, "FAIL: unsafe cache path was accepted\n");
    ++failures;
  }

  yt_cache_key_for_string("fixture-player", key);
  status = yt_cache_put_at(root, YT_CACHE_PLAYER_JAVASCRIPT, key, payload,
                           sizeof(payload) - 1, 2000);
  loaded = NULL;
  loaded_length = 0;
  if (status != YT_CACHE_OK ||
      yt_cache_get_at(root, YT_CACHE_PLAYER_JAVASCRIPT, key, 1000, &loaded,
                      &loaded_length) != YT_CACHE_OK ||
      loaded_length != sizeof(payload) - 1 ||
      memcmp(loaded, payload, sizeof(payload) - 1) != 0) {
    fprintf(stderr, "FAIL: versioned cache round trip\n");
    ++failures;
  }
  free(loaded);
  yt_cache_key_for_string("https://www.youtube.com/s/player/fixture/base.js",
                          key);
  if (yt_cache_put_at(root, YT_CACHE_PLAYER_JAVASCRIPT, key,
                      "fixture-player-js", 17, 0) != YT_CACHE_OK) {
    fprintf(stderr, "FAIL: raw player cache setup\n");
    ++failures;
  } else {
    player_source = NULL;
    if (yt_challenges_load_player(
            session, "https://www.youtube.com/s/player/fixture/base.js",
            &player_source) != YT_OK || player_source == NULL ||
        strcmp(player_source, "fixture-player-js") != 0) {
      fprintf(stderr, "FAIL: production raw player cache lookup\n");
      ++failures;
    }
    free(player_source);
  }
  if (yt_failure_cache_ttl(YT_ERR_UNAVAILABLE) <=
          yt_failure_cache_ttl(YT_ERR_INVALID_RESPONSE) ||
      yt_failure_cache_ttl(YT_ERR_NETWORK) != 0 ||
      yt_failure_cache_ttl(YT_ERR_NO_PROGRESSIVE_MP4) <= 0) {
    fprintf(stderr, "FAIL: error-specific failure cache lifetimes\n");
    ++failures;
  }
  {
    YTStatus cached_failure = YT_OK;
    yt_failure_cache_remember(session, "failure-fixture", YT_ERR_UNAVAILABLE);
    if (!yt_failure_cache_load(session, "failure-fixture", &cached_failure) ||
        cached_failure != YT_ERR_UNAVAILABLE) {
      fprintf(stderr, "FAIL: production failure cache round trip\n");
      ++failures;
    }
  }
  if (yt_cache_put_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "one", payload,
                   sizeof(payload) - 1, 0) != YT_CACHE_OK ||
      yt_cache_put_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "two", payload,
                   sizeof(payload) - 1, 0) != YT_CACHE_OK ||
      yt_cache_put_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "three", payload,
                   sizeof(payload) - 1, 0) != YT_CACHE_OK ||
      yt_cache_put_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "four", payload,
                   sizeof(payload) - 1, 0) != YT_CACHE_OK ||
      yt_cache_put_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "five", payload,
                   sizeof(payload) - 1, 0) != YT_CACHE_OK) {
    fprintf(stderr, "FAIL: bounded cache writes\n");
    ++failures;
  }
  retained = 0;
  loaded = NULL;
  if (yt_cache_get_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "one", 0, &loaded,
                   &loaded_length) == YT_CACHE_OK)
    ++retained;
  free(loaded);
  loaded = NULL;
  if (yt_cache_get_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "two", 0, &loaded,
                   &loaded_length) == YT_CACHE_OK)
    ++retained;
  free(loaded);
  loaded = NULL;
  if (yt_cache_get_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "three", 0, &loaded,
                   &loaded_length) == YT_CACHE_OK)
    ++retained;
  free(loaded);
  loaded = NULL;
  if (yt_cache_get_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "four", 0, &loaded,
                   &loaded_length) == YT_CACHE_OK)
    ++retained;
  free(loaded);
  loaded = NULL;
  if (yt_cache_get_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "five", 0, &loaded,
                   &loaded_length) == YT_CACHE_OK)
    ++retained;
  free(loaded);
  if (retained == 0 || retained > 4) {
    fprintf(stderr, "FAIL: bounded cache pruning\n");
    ++failures;
  }
  loaded = NULL;
  if (yt_cache_put_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "expiring", payload,
                   sizeof(payload) - 1, 2000) != YT_CACHE_OK ||
      yt_cache_get_at(root, YT_CACHE_PLAYER_JAVASCRIPT, "expiring", 2000, &loaded,
                   &loaded_length) != YT_CACHE_EXPIRED) {
    fprintf(stderr, "FAIL: cache expiry\n");
    ++failures;
  }

  status = yt_cache_put_at(root, YT_CACHE_FAILURE, "broken", payload,
                        sizeof(payload) - 1, 0);
  if (status != YT_CACHE_OK ||
      yt_cache_write_file_atomic_at(root, "v1/failures/broken.entry", "invalid", 7) !=
          YT_CACHE_OK ||
      yt_cache_get_at(root, YT_CACHE_FAILURE, "broken", 0, &loaded, &loaded_length) !=
          YT_CACHE_CORRUPT) {
    fprintf(stderr, "FAIL: corrupt cache classification\n");
    ++failures;
  }
  free(loaded);
  yt_http_session_destroy(session);
  if (failures == 0)
    printf("PASS: ~/.retro-dlp/cache atomic, versioned, bounded entries\n");
  return failures;
}

static void cleanup_cache_test(const char *temporary_home) {
  static const char *const suffixes[] = {
      "/.retro-dlp/cache/v1/player-javascript",
      "/.retro-dlp/cache/v1/failures",
      "/.retro-dlp/cache/v1",
      "/.retro-dlp/cache",
      "/.retro-dlp",
      ""};
  char path[4096];
  size_t index;

  for (index = 0; index < sizeof(suffixes) / sizeof(suffixes[0]); ++index) {
    if (snprintf(path, sizeof(path), "%s%s", temporary_home, suffixes[index]) <
        (int)sizeof(path))
      rmdir(path);
  }
}

int retro_dlp_run_cache_tests(void) {
  char template_path[] = "/tmp/retro-dlp-cache-test.XXXXXX";
  char *temporary_home;
  int temporary_descriptor;
  int failures;

  failures = test_sha256();
  temporary_descriptor = mkstemp(template_path);
  if (temporary_descriptor < 0 || close(temporary_descriptor) != 0 ||
      unlink(template_path) != 0 || mkdir(template_path, 0700) != 0) {
    fprintf(stderr, "FAIL: cache test temporary directory\n");
    return failures + 1;
  }
  temporary_home = template_path;
  failures += exercise_cache(temporary_home);
  cleanup_cache_test(temporary_home);
  return failures;
}
