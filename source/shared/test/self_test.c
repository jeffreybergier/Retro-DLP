#include "self_test.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "cJSON.h"
#include "curl/curl.h"
#include "quickjs.h"
#include "self_test_data.h"
#include "yt_resolver.h"

#define SELF_TEST_VIDEO_ID "YE7VzlLtp-4"

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

  if (yt_extract_video_id(SELF_TEST_VIDEO_ID, video_id) != YT_OK ||
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
  printf("PASS: video ID parsing (%s)\n", SELF_TEST_VIDEO_ID);
  return 0;
}

static int test_offline_player_fixtures(void) {
  YTMediaRequest media;
  YTStatus status;

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

static int test_live_resolver(void) {
  const curl_version_info_data *curl_version;
  YTMediaRequest media;
  YTStatus status;
  long http_status;
  int failed;

  curl_version = curl_version_info(CURLVERSION_NOW);
  if (curl_version == NULL || curl_version->version == NULL) {
    fprintf(stderr, "FAIL: libcurl version unavailable\n");
    return 1;
  }
  printf("PASS: libcurl %s\n", curl_version->version);

  status = yt_resolve_video(SELF_TEST_VIDEO_ID, &media);
  if (status != YT_OK) {
    fprintf(stderr, "FAIL: player API resolution: %s\n",
            yt_status_string(status));
    return 1;
  }
  printf("PASS: player API response (%s)\n", SELF_TEST_VIDEO_ID);

  failed = 0;
  if (media.itag != 18 || media.width != 640 || media.height != 360 ||
      media.mime_type == NULL ||
      strncmp(media.mime_type, "video/mp4", 9) != 0) {
    fprintf(stderr, "FAIL: live fixture metadata\n");
    failed = 1;
  } else {
    printf("PASS: live fixture metadata (itag 18, 640x360 MP4)\n");
  }

  if (!has_googlevideo_host(media.url) ||
      strstr(media.url, "itag=18") == NULL ||
      strstr(media.url, "expire=") == NULL || media.expires_unix <= 0) {
    fprintf(stderr, "FAIL: resolved media URL fields\n");
    failed = 1;
  } else {
    printf("PASS: Google Video host and required query fields\n");
  }

  if (strstr(media.url, "sig=") == NULL || strstr(media.url, "&n=") != NULL) {
    fprintf(stderr, "FAIL: direct URL challenge classification\n");
    failed = 1;
  } else {
    printf("PASS: direct URL requires no s/n challenge solving\n");
  }

  http_status = 0;
  status = yt_probe_media_head(&media, &http_status);
  if ((status != YT_OK && status != YT_ERR_PO_TOKEN_REQUIRED) ||
      !((http_status >= 200 && http_status < 400) || http_status == 403)) {
    fprintf(stderr, "FAIL: media HEAD request: %s (HTTP %ld)\n",
            yt_status_string(status), http_status);
    failed = 1;
  } else if (status == YT_ERR_PO_TOKEN_REQUIRED) {
    printf("PASS: media HEAD reached GVS (HTTP 403: PO token required)\n");
  } else {
    printf("PASS: media HEAD (HTTP %ld)\n", http_status);
  }

  yt_media_request_free(&media);
  return failed;
}

int retro_dlp_run_self_tests(void) {
  int failures;

  failures = test_cjson();
  failures += test_quickjs();
  failures += test_video_id();
  failures += test_offline_player_fixtures();
  failures += test_live_resolver();
  if (failures != 0)
    return 1;

  printf("PASS: retro-dlp self-test\n");
  return 0;
}
