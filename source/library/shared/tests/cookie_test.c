#if !defined(__APPLE__)
#define _XOPEN_SOURCE 600
#endif

#include "cookie_test.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "yt_cookies.h"
#include "yt_resolver_internal.h"

static int write_all(int descriptor, const char *data, size_t length) {
  size_t offset = 0;
  while (offset < length) {
    ssize_t count = write(descriptor, data + offset, length - offset);
    if (count <= 0)
      return 0;
    offset += (size_t)count;
  }
  return 1;
}

static int load_fixture(const char *fixture, YTAuthCookies *cookies,
                        YTStatus *status) {
  char path[] = "/tmp/retro-dlp-cookie-test.XXXXXX";
  int descriptor = mkstemp(path);
  int written;
  if (descriptor < 0)
    return 0;
  written = write_all(descriptor, fixture, strlen(fixture));
  if (close(descriptor) != 0)
    written = 0;
  if (written)
    *status = yt_auth_cookies_load(path, 1700000000LL, cookies);
  unlink(path);
  return written;
}

int retro_dlp_run_cookie_tests(void) {
  static const char valid_fixture[] =
      "# Netscape HTTP Cookie File\n"
      ".youtube.com\tTRUE\t/\tTRUE\t4102444800\tLOGIN_INFO\tlogin\n"
      ".youtube.com\tTRUE\t/\tTRUE\t1600000000\tSAPISID\texpired\n"
      ".example.com\tTRUE\t/\tTRUE\t4102444800\tSAPISID\twrong-domain\n"
      ".youtube.com\tTRUE\t/not-root\tTRUE\t4102444800\tSAPISID\twrong-path\n"
      ".youtube.com\tTRUE\t/\tTRUE\t4102444800\tSAPISID\talpha\n"
      "#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t4102444800\t__Secure-1PAPISID\tbeta\n"
      ".youtube.com\tTRUE\t/\tTRUE\t4102444800\t__Secure-3PAPISID\tgamma\n";
  static const char missing_auth_fixture[] =
      "# Netscape HTTP Cookie File\n"
      ".youtube.com\tTRUE\t/\tTRUE\t4102444800\tPREF\thl=en\n";
  static const char invalid_header_fixture[] =
      "not a Netscape cookie file\n"
      ".youtube.com\tTRUE\t/\tTRUE\t4102444800\tLOGIN_INFO\tlogin\n";
  static const char expected_authorization[] =
      "SAPISIDHASH 1700000000_8c97eeb5e7370957e4db83d3ff73f0f94a4b4d6f_u "
      "SAPISID1PHASH 1700000000_1e079087fb41c1bbb3eee0c6dbd4855c7f097f47_u "
      "SAPISID3PHASH 1700000000_15706705bac3bbe35119eb11c5524400b4217ea4_u";
  YTAuthCookies cookies;
  YTStatus status;
  char authorization[1024];
  char anonymous_key[65];
  char authenticated_key[65];
  int failures = 0;

  printf("RUN: Netscape YouTube cookie authentication fixtures\n");
  fflush(stdout);
  memset(&cookies, 0, sizeof(cookies));
  if (!load_fixture(valid_fixture, &cookies, &status) || status != YT_OK ||
      !yt_auth_cookies_is_authenticated(&cookies) ||
      strcmp(cookies.sapisid, "alpha") != 0 ||
      strcmp(cookies.sapisid_1p, "beta") != 0 ||
      strcmp(cookies.sapisid_3p, "gamma") != 0) {
    fprintf(stderr, "FAIL: valid authenticated Netscape cookie fixture\n");
    ++failures;
  } else if (yt_auth_cookies_make_authorization(
                 &cookies, "https://www.youtube.com", "user-session",
                 1700000000LL, authorization, sizeof(authorization)) != YT_OK ||
             strcmp(authorization, expected_authorization) != 0 ||
             strstr(authorization, "alpha") != NULL ||
             strstr(authorization, "beta") != NULL ||
             strstr(authorization, "gamma") != NULL) {
    fprintf(stderr, "FAIL: SAPISID authorization fixture\n");
    ++failures;
  }
  yt_auth_cookies_free(&cookies);

  memset(&cookies, 0, sizeof(cookies));
  if (!load_fixture(missing_auth_fixture, &cookies, &status) ||
      status != YT_ERR_AUTH_COOKIES_INVALID) {
    fprintf(stderr, "FAIL: missing authentication cookie classification\n");
    ++failures;
  }
  yt_auth_cookies_free(&cookies);
  memset(&cookies, 0, sizeof(cookies));
  if (!load_fixture(invalid_header_fixture, &cookies, &status) ||
      status != YT_ERR_COOKIE_FILE) {
    fprintf(stderr, "FAIL: invalid cookie file classification\n");
    ++failures;
  }
  yt_auth_cookies_free(&cookies);

  yt_failure_cache_key_for_session("YE7VzlLtp-4", "MWEB", "fixture", 0,
                                   anonymous_key);
  yt_failure_cache_key_for_session("YE7VzlLtp-4", "MWEB", "fixture", 1,
                                   authenticated_key);
  if (anonymous_key[0] == '\0' || authenticated_key[0] == '\0' ||
      strcmp(anonymous_key, authenticated_key) == 0) {
    fprintf(stderr, "FAIL: authenticated and anonymous cache isolation\n");
    ++failures;
  }

  if (failures == 0)
    printf("PASS: cookies, SAPISID authorization, redaction, and cache isolation\n");
  return failures;
}
