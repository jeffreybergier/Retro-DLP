#include "self_test.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "cJSON.h"
#include "cache_test.h"
#include "cookie_test.h"
#include "curl/curl.h"
#include "ejs_test.h"
#include "quickjs.h"
#include "self_test_data.h"
#include "yt_http.h"
#include "yt_resolver.h"

#define SELF_TEST_VIDEO_ID "YE7VzlLtp-4"
#define SECOND_SELF_TEST_VIDEO_ID "-_x6t4CaPzo"
#define SELF_TEST_MEDIA_RANGE_LENGTH 10241U

static void announce_test(const char *description) {
  printf("RUN: %s\n", description);
  fflush(stdout);
}

static int test_cjson(void) {
  cJSON *document;
  cJSON *value;

  document = cJSON_ParseWithLength(retro_dlp_self_test_json,
                                   retro_dlp_self_test_json_length);
  if (document == NULL) {
    fprintf(stderr, "FAIL: cJSON could not parse JSON\n");
    return 1;
  }

  value = cJSON_GetObjectItemCaseSensitive(document, "enabled");
  if (!cJSON_IsTrue(value)) {
    fprintf(stderr, "FAIL: cJSON returned an unexpected value\n");
    cJSON_Delete(document);
    return 1;
  }

  cJSON_Delete(document);
  printf("PASS: cJSON\n");
  return 0;
}

static int test_quickjs(void) {
  JSRuntime *runtime;
  JSContext *context;
  JSValue result;
  int32_t number;
  int failed;

  runtime = JS_NewRuntime();
  if (runtime == NULL) {
    fprintf(stderr, "FAIL: QuickJS could not create a runtime\n");
    return 1;
  }

  context = JS_NewContext(runtime);
  if (context == NULL) {
    fprintf(stderr, "FAIL: QuickJS could not create a context\n");
    JS_FreeRuntime(runtime);
    return 1;
  }

  result = JS_Eval(context, retro_dlp_self_test_javascript,
                   retro_dlp_self_test_javascript_length, "<self-test>",
                   JS_EVAL_TYPE_GLOBAL);
  failed = JS_IsException(result) ||
           JS_ToInt32(context, &number, result) != 0 || number != 42;
  JS_FreeValue(context, result);
  JS_FreeContext(context);
  JS_FreeRuntime(runtime);

  if (failed) {
    fprintf(stderr, "FAIL: QuickJS evaluation returned an unexpected value\n");
    return 1;
  }

  printf("PASS: QuickJS\n");
  return 0;
}

static int test_video_id(void) {
  char video_id[12];

  if (yt_extract_video_id("-_x6t4CaPzo", video_id) != YT_OK ||
      strcmp(video_id, "-_x6t4CaPzo") != 0 ||
      yt_extract_video_id(
          "https://www.youtube.com/watch?v=-_x6t4CaPzo", video_id) != YT_OK ||
      strcmp(video_id, "-_x6t4CaPzo") != 0 ||
      yt_extract_video_id(SELF_TEST_VIDEO_ID, video_id) != YT_OK ||
      strcmp(video_id, SELF_TEST_VIDEO_ID) != 0 ||
      yt_extract_video_id("https://youtu.be/" SELF_TEST_VIDEO_ID "?feature=x",
                          video_id) != YT_OK ||
      strcmp(video_id, SELF_TEST_VIDEO_ID) != 0 ||
      yt_extract_video_id("https://www.youtube.com/shorts/" SELF_TEST_VIDEO_ID,
                          video_id) != YT_OK ||
      strcmp(video_id, SELF_TEST_VIDEO_ID) != 0 ||
      yt_extract_video_id("https://www.youtube.com/embed/" SELF_TEST_VIDEO_ID,
                          video_id) != YT_OK ||
      strcmp(video_id, SELF_TEST_VIDEO_ID) != 0 ||
      yt_extract_video_id("https://www.youtube-nocookie.com/embed/"
                          SELF_TEST_VIDEO_ID,
                          video_id) != YT_OK ||
      strcmp(video_id, SELF_TEST_VIDEO_ID) != 0) {
    fprintf(stderr, "FAIL: YouTube video ID forms\n");
    return 1;
  }

  if (yt_extract_video_id(
          "https://www.youtube.com/watch?feature=test&v=" SELF_TEST_VIDEO_ID,
          video_id) != YT_OK || strcmp(video_id, SELF_TEST_VIDEO_ID) != 0) {
    fprintf(stderr, "FAIL: YouTube video ID parsing\n");
    return 1;
  }
  if (yt_extract_video_id("not-video", video_id) !=
          YT_ERR_INVALID_VIDEO_ID ||
      yt_extract_video_id(SELF_TEST_VIDEO_ID "x", video_id) !=
          YT_ERR_INVALID_VIDEO_ID ||
      yt_extract_video_id("YE7VzlLtp!4", video_id) !=
          YT_ERR_INVALID_VIDEO_ID ||
      yt_extract_video_id("https://example.com/watch?v=" SELF_TEST_VIDEO_ID,
                          video_id) != YT_ERR_INVALID_VIDEO_ID ||
      yt_extract_video_id("https://example.com/youtu.be/" SELF_TEST_VIDEO_ID,
                          video_id) != YT_ERR_INVALID_VIDEO_ID ||
      yt_extract_video_id("https://youtube.com.example/watch?v="
                          SELF_TEST_VIDEO_ID,
                          video_id) !=
          YT_ERR_INVALID_VIDEO_ID) {
    fprintf(stderr, "FAIL: invalid YouTube video ID was accepted\n");
    return 1;
  }
  printf("PASS: video ID parsing (%s, -_x6t4CaPzo)\n",
         SELF_TEST_VIDEO_ID);
  return 0;
}

static int test_offline_player_fixtures(void) {
  static const unsigned char mp4_prefix[] = {0, 0, 0, 24, 'f', 't', 'y', 'p',
                                              'i', 's', 'o', 'm'};
  static const char direct_after_challenge[] =
      "{\"playabilityStatus\":{\"status\":\"OK\"},\"streamingData\":{"
      "\"formats\":[{\"itag\":18,\"url\":\"https://fixture.googlevideo.com/"
      "videoplayback?itag=18&n=challenge\",\"mimeType\":\"video/mp4\"},"
      "{\"itag\":18,\"url\":\"https://fixture.googlevideo.com/"
      "videoplayback?expire=1900000000&itag=18&sig=direct\","
      "\"mimeType\":\"video/mp4\",\"width\":640,\"height\":360}]}}";
  YTMediaRequest media;
  YTStatus status;

  if (!yt_http_has_mp4_ftyp(mp4_prefix, sizeof(mp4_prefix)) ||
      yt_http_has_mp4_ftyp((const unsigned char *)"<html>error", 11)) {
    fprintf(stderr, "FAIL: MP4 download prefix validation\n");
    return 1;
  }

  status = yt_parse_player_response(retro_dlp_player_itag18_fixture,
                                    retro_dlp_player_itag18_fixture_length,
                                    &media);
  if (status != YT_OK || media.itag != 18 || media.width != 640 ||
      media.height != 360 || media.expires_unix != 1900000000LL ||
      media.content_length != 12345678LL || media.url == NULL ||
      strstr(media.url, "itag=18") == NULL || media.mime_type == NULL ||
      strncmp(media.mime_type, "video/mp4", 9) != 0) {
    fprintf(stderr, "FAIL: deterministic itag 18 player fixture\n");
    if (status == YT_OK)
      yt_media_request_free(&media);
    return 1;
  }
  yt_media_request_free(&media);

  status = yt_parse_player_response(direct_after_challenge,
                                    sizeof(direct_after_challenge) - 1, &media);
  if (status != YT_OK || media.url == NULL ||
      strstr(media.url, "sig=direct") == NULL ||
      strstr(media.url, "n=challenge") != NULL) {
    fprintf(stderr, "FAIL: direct format was not preferred over EJS fallback\n");
    if (status == YT_OK)
      yt_media_request_free(&media);
    return 1;
  }
  yt_media_request_free(&media);

  status = yt_parse_player_response(
      retro_dlp_player_n_challenge_fixture,
      retro_dlp_player_n_challenge_fixture_length, &media);
  if (status != YT_ERR_NO_PROGRESSIVE_MP4) {
    fprintf(stderr, "FAIL: unresolved s/n challenge fixture was accepted\n");
    if (status == YT_OK)
      yt_media_request_free(&media);
    return 1;
  }

  status = yt_parse_player_response(retro_dlp_player_unavailable_fixture,
                                    retro_dlp_player_unavailable_fixture_length,
                                    &media);
  if (status != YT_ERR_UNAVAILABLE) {
    fprintf(stderr, "FAIL: unavailable player fixture classification\n");
    return 1;
  }

  if (yt_classify_media_http_status(204) != YT_OK ||
      yt_classify_media_http_status(302) != YT_OK ||
      yt_classify_media_http_status(403) != YT_ERR_PO_TOKEN_REQUIRED ||
      yt_classify_media_http_status(404) != YT_ERR_HTTP) {
    fprintf(stderr, "FAIL: media HTTP status classification fixture\n");
    return 1;
  }

  printf("PASS: deterministic player and HTTP classification fixtures\n");
  return 0;
}

static int has_googlevideo_host(const char *url) {
  const char *host;
  const char *host_end;
  const char *suffix;
  size_t host_length;
  size_t suffix_length;

  host = strstr(url, "://");
  if (host == NULL)
    return 0;
  host += 3;
  host_end = strchr(host, '/');
  if (host_end == NULL)
    return 0;
  host_length = (size_t)(host_end - host);
  suffix = ".googlevideo.com";
  suffix_length = strlen(suffix);
  return host_length > suffix_length &&
         memcmp(host + host_length - suffix_length, suffix, suffix_length) ==
             0;
}

static int test_media_byte_range(YTHttpSession *session,
                                 const YTMediaRequest *media,
                                 const char *video_id) {
  YTHttpResponse response;
  YTStatus status;

  printf("RUN: request first 10,241 bytes of media (%s)\n", video_id);
  fflush(stdout);
  memset(&response, 0, sizeof(response));
  status = yt_http_session_get_range(session, media->url,
                                     SELF_TEST_MEDIA_RANGE_LENGTH, &response);
  if (status == YT_OK)
    status = yt_classify_media_http_status(response.status);
  if (status != YT_OK || response.status < 200 || response.status >= 300 ||
      response.length == 0 ||
      !yt_http_has_mp4_ftyp((const unsigned char *)response.data,
                            response.length)) {
    fprintf(stderr,
            "FAIL: media byte-range request (%s): %s "
            "(HTTP %ld, %lu bytes)\n",
            video_id, yt_status_string(status), response.status,
            (unsigned long)response.length);
    yt_http_response_free(&response);
    return 1;
  }

  printf("PASS: media byte range (%s, %lu bytes, HTTP %ld)\n", video_id,
         (unsigned long)response.length, response.status);
  yt_http_response_free(&response);
  return 0;
}

static int test_live_video(const char *video_id, int check_fixture_metadata,
                           const char *cookie_file) {
  YTMediaRequest media;
  YTStatus status;
  int failed;
  YTHttpSession *session;

  printf("RUN: resolve live video (%s)\n", video_id);
  fflush(stdout);
  session = NULL;
  status = yt_http_session_create(cookie_file, &session);
  if (status == YT_OK)
    status = yt_resolve_video_with_http_session_and_progress(
        session, video_id, cookie_file, &media, NULL, NULL);
  if (status != YT_OK) {
    fprintf(stderr, "FAIL: player API resolution (%s): %s\n", video_id,
            yt_status_string(status));
    yt_http_session_destroy(session);
    return 1;
  }
  printf("PASS: player API response (%s)\n", video_id);

  failed = 0;
  if (media.itag != 18 || media.mime_type == NULL ||
      strncmp(media.mime_type, "video/mp4", 9) != 0) {
    fprintf(stderr, "FAIL: live video metadata (%s)\n", video_id);
    failed = 1;
  } else if (check_fixture_metadata &&
             (media.width != 640 || media.height != 360)) {
    fprintf(stderr, "FAIL: live fixture metadata (%s)\n", video_id);
    failed = 1;
  } else if (check_fixture_metadata) {
    printf("PASS: live fixture metadata (itag 18, 640x360 MP4)\n");
  } else {
    printf("PASS: live video metadata (%s, itag 18 MP4)\n", video_id);
  }

  if (!has_googlevideo_host(media.url) ||
      strstr(media.url, "itag=18") == NULL ||
      strstr(media.url, "expire=") == NULL || media.expires_unix <= 0) {
    fprintf(stderr, "FAIL: resolved media URL fields (%s)\n", video_id);
    failed = 1;
  } else {
    printf("PASS: Google Video host and required query fields (%s)\n",
           video_id);
  }

  if (strstr(media.url, "sig=") == NULL) {
    fprintf(stderr, "FAIL: resolved URL signature classification (%s)\n",
            video_id);
    failed = 1;
  } else {
    printf("PASS: resolved URL signature and n challenge processing (%s)\n",
           video_id);
  }

  failed += test_media_byte_range(session, &media, video_id);

  yt_media_request_free(&media);
  yt_http_session_destroy(session);
  return failed;
}

static int test_libcurl(void) {
  const curl_version_info_data *curl_version;

  curl_version = curl_version_info(CURLVERSION_NOW);
  if (curl_version == NULL || curl_version->version == NULL) {
    fprintf(stderr, "FAIL: libcurl version unavailable\n");
    return 1;
  }
  printf("PASS: libcurl %s\n", curl_version->version);
  return 0;
}

static int test_live_resolver(const char *cookie_file) {
  int failures;

  failures = test_live_video(SELF_TEST_VIDEO_ID, 1, cookie_file);
  failures += test_live_video(SECOND_SELF_TEST_VIDEO_ID, 0, cookie_file);
  return failures;
}

int retro_dlp_run_self_tests_with_cookies(const char *cookie_file) {
  int failures;

  setvbuf(stdout, NULL, _IONBF, 0);
  fflush(stderr);
  dup2(STDOUT_FILENO, STDERR_FILENO);

  announce_test("libcurl availability");
  failures = test_libcurl();
  announce_test("YouTube video ID parsing");
  failures += test_video_id();
  announce_test("cJSON parsing");
  failures += test_cjson();
  announce_test("deterministic player and HTTP fixtures");
  failures += test_offline_player_fixtures();
  announce_test("QuickJS evaluation");
  failures += test_quickjs();
  announce_test("cache and SHA-256 fixtures");
  failures += retro_dlp_run_cache_tests();
  announce_test("cookie authentication fixtures");
  failures += retro_dlp_run_cookie_tests();
  announce_test("EJS fixtures and runtime limits");
  failures += retro_dlp_run_ejs_tests();
  announce_test("live network fixtures");
  failures += test_live_resolver(cookie_file);
  if (failures != 0)
    return 1;

  printf("PASS: retro-dlp self-test\n");
  return 0;
}

int retro_dlp_run_self_tests(void) {
  return retro_dlp_run_self_tests_with_cookies(NULL);
}
