#include "self_test.h"

#include "../../library/shared/tests/allocation_test.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "cJSON.h"
#include "cli.h"
#include "../../library/shared/tests/cache_test.h"
#include "../../library/shared/tests/cookie_test.h"
#include "curl/curl.h"
#include "../../library/shared/tests/ejs_test.h"
#include "quickjs.h"
#include "self_test_data.h"
#include "yt_http.h"
#include "yt_playlist.h"
#include "yt_playlist_internal.h"
#include "yt_resolver.h"
#include "../../library/shared/tests/yt_formats_test_support.h"

int retro_dlp_run_playlist_metadata_tests(void);

#define SELF_TEST_VIDEO_ID "YE7VzlLtp-4"

static void announce_test(const char *description) {
  printf("RUN: %s\n", description);
  fflush(stdout);
}

static int has_mp4_ftyp(const unsigned char *prefix, size_t length) {
  return prefix != NULL && length >= 8 && memcmp(prefix + 4, "ftyp", 4) == 0;
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
      yt_extract_video_id("http://www.youtube.com/v/wjhAtz3_X3M",
                          video_id) != YT_OK ||
      strcmp(video_id, "wjhAtz3_X3M") != 0 ||
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

static int test_playlist_id(void) {
  char playlist_id[128];
  if (yt_extract_playlist_id(
          "https://www.youtube.com/watch?v=BlHv3BbBv6A&list="
          "PLFWnTRz9kjd__AsPFMkdw9G7P-NBhAlaf",
          playlist_id, sizeof(playlist_id)) != YT_OK ||
      strcmp(playlist_id, "PLFWnTRz9kjd__AsPFMkdw9G7P-NBhAlaf") != 0 ||
      yt_extract_playlist_id(
          "https://www.youtube.com/playlist?list=PL_test-123",
          playlist_id, sizeof(playlist_id)) != YT_OK ||
      strcmp(playlist_id, "PL_test-123") != 0 ||
      yt_extract_playlist_id("PL0SbJRdq3h-WCYdFjWM03h9IxgDs3fHot",
                             playlist_id, sizeof(playlist_id)) != YT_OK ||
      strcmp(playlist_id, "PL0SbJRdq3h-WCYdFjWM03h9IxgDs3fHot") != 0 ||
      yt_extract_playlist_id("UU0SbJRdq3h-WCYdFjWM03h9IxgDs3fHot",
                             playlist_id, sizeof(playlist_id)) != YT_OK ||
      strcmp(playlist_id, "UU0SbJRdq3h-WCYdFjWM03h9IxgDs3fHot") != 0 ||
      yt_extract_playlist_id(
          "https://WWW.YOUTUBE.COM/playlist?list=OLAK5uy_fixture",
          playlist_id, sizeof(playlist_id)) != YT_OK ||
      strcmp(playlist_id, "OLAK5uy_fixture") != 0 ||
      yt_extract_playlist_id("LL", playlist_id, sizeof(playlist_id)) !=
          YT_ERR_INVALID_PLAYLIST ||
      yt_extract_playlist_id("WL", playlist_id, sizeof(playlist_id)) !=
          YT_ERR_INVALID_PLAYLIST ||
      yt_extract_playlist_id(SELF_TEST_VIDEO_ID, playlist_id,
                             sizeof(playlist_id)) != YT_ERR_INVALID_PLAYLIST ||
      yt_extract_playlist_id("https://www.youtube.com/watch?v=YE7VzlLtp-4",
                             playlist_id, sizeof(playlist_id)) !=
          YT_ERR_INVALID_PLAYLIST ||
      yt_extract_playlist_id(
          "https://www.youtube.com/playlist?list=bad%20id", playlist_id,
          sizeof(playlist_id)) != YT_ERR_INVALID_PLAYLIST ||
      yt_extract_playlist_id(
          "https://example.com/playlist?list=PL_test-123", playlist_id,
          sizeof(playlist_id)) != YT_ERR_INVALID_PLAYLIST ||
      yt_extract_playlist_id(
          "https://youtube.com.example/playlist?list=PL_test-123",
          playlist_id, sizeof(playlist_id)) != YT_ERR_INVALID_PLAYLIST) {
    fprintf(stderr, "FAIL: YouTube playlist ID forms\n");
    return 1;
  }
  if (!yt_is_playlist_collection_url(
          "https://www.youtube.com/feed/playlists") ||
      !yt_is_playlist_collection_url(
          "https://youtube.com/feed/you/?feature=test") ||
      !yt_is_playlist_collection_url(
          "https://m.youtube.com/feed/library#playlists") ||
      yt_is_playlist_collection_url(
          "https://example.com/feed/playlists") ||
      yt_is_playlist_collection_url(
          "https://youtube.com.example/feed/playlists") ||
      yt_is_playlist_collection_url(
          "https://www.youtube.com/feed/playlists/more")) {
    fprintf(stderr, "FAIL: YouTube playlist collection URL forms\n");
    return 1;
  }
  printf("PASS: playlist ID parsing\n");
  return 0;
}

static int test_playlist_page_fixtures(void) {
  static const char bootstrap_page[] =
      "<html><script>ytcfg.set({\"INNERTUBE_API_KEY\":\"fixture-key\","
      "\"INNERTUBE_CONTEXT_CLIENT_VERSION\":\"1.20260828.00.00\","
      "\"VISITOR_DATA\":\"fixture-visitor\"});"
      "var ytInitialData={\"contents\":["
      "{\"playlistVideoRenderer\":{\"videoId\":\"AAAAAAAAAAA\","
      "\"title\":{\"simpleText\":\"First video\"}}},"
      "{\"playlistVideoRenderer\":{\"videoId\":\"AAAAAAAAAAA\","
      "\"title\":{\"runs\":[{\"text\":\"Repeated video\"}]}}},"
      "{\"continuationItemRenderer\":{\"continuationEndpoint\":{"
      "\"continuationCommand\":{\"token\":\"page-two\"}}}}]};"
      "</script></html>";
  static const char continuation_json[] =
      "{\"onResponseReceivedActions\":[{\"appendContinuationItemsAction\":{"
      "\"continuationItems\":[{\"lockupViewModel\":{"
      "\"contentId\":\"BBBBBBBBBBB\","
      "\"contentType\":\"LOCKUP_CONTENT_TYPE_VIDEO\","
      "\"metadata\":{\"lockupMetadataViewModel\":{\"title\":{"
      "\"content\":\"Second page video\"}}}}}]}}]}";
  static const char malformed_continuation_json[] =
      "{\"contents\":[{\"playlistVideoRenderer\":{"
      "\"videoId\":\"CCCCCCCCCCC\",\"title\":{"
      "\"simpleText\":\"Malformed continuation fixture\"}}},"
      "{\"continuationItemRenderer\":{\"continuationEndpoint\":{"
      "\"continuationCommand\":{\"token\":42}}}}]}";
  YTPlaylistBootstrap bootstrap;
  YTPlaylist playlist;
  YTPlaylist malformed_playlist;
  cJSON *continuation_document;
  cJSON *malformed_document;
  char *continuation;
  YTStatus status;

  memset(&bootstrap, 0, sizeof(bootstrap));
  memset(&playlist, 0, sizeof(playlist));
  memset(&malformed_playlist, 0, sizeof(malformed_playlist));
  continuation = NULL;
  status = yt_playlist_parse_bootstrap_page(bootstrap_page, &bootstrap);
  if (status != YT_OK || strcmp(bootstrap.api_key, "fixture-key") != 0 ||
      strcmp(bootstrap.client_version, "1.20260828.00.00") != 0 ||
      strcmp(bootstrap.visitor_data, "fixture-visitor") != 0 ||
      yt_playlist_collect_entries(bootstrap.document, &playlist,
                                  &continuation) != YT_OK ||
      continuation == NULL || strcmp(continuation, "page-two") != 0 ||
      playlist.entry_count != 2 ||
      strcmp(playlist.entries[0].video_id, "AAAAAAAAAAA") != 0 ||
      strcmp(playlist.entries[0].title, "First video") != 0 ||
      strcmp(playlist.entries[1].video_id, "AAAAAAAAAAA") != 0 ||
      strcmp(playlist.entries[1].title, "Repeated video") != 0) {
    fprintf(stderr, "FAIL: playlist webpage bootstrap and first page fixtures\n");
    free(continuation);
    yt_playlist_free(&playlist);
    yt_playlist_bootstrap_free(&bootstrap);
    return 1;
  }
  free(continuation);
  continuation = NULL;
  continuation_document = cJSON_Parse(continuation_json);
  if (continuation_document == NULL ||
      yt_playlist_collect_entries(continuation_document, &playlist,
                                  &continuation) != YT_OK ||
      continuation != NULL || playlist.entry_count != 3 ||
      strcmp(playlist.entries[2].video_id, "BBBBBBBBBBB") != 0 ||
      strcmp(playlist.entries[2].title, "Second page video") != 0 ||
      playlist.entries[2].index != 3) {
    fprintf(stderr, "FAIL: playlist continuation page fixture\n");
    free(continuation);
    cJSON_Delete(continuation_document);
    yt_playlist_free(&playlist);
    yt_playlist_bootstrap_free(&bootstrap);
    return 1;
  }
  cJSON_Delete(continuation_document);
  yt_playlist_bootstrap_free(&bootstrap);
  malformed_document = cJSON_Parse(malformed_continuation_json);
  status = malformed_document == NULL
               ? YT_ERR_INVALID_RESPONSE
               : yt_playlist_collect_entries(malformed_document,
                                             &malformed_playlist,
                                             &continuation);
  cJSON_Delete(malformed_document);
  free(continuation);
  if (status != YT_ERR_INVALID_RESPONSE ||
      yt_playlist_parse_bootstrap_page("ytInitialData={broken", &bootstrap) !=
          YT_ERR_INVALID_RESPONSE) {
    fprintf(stderr, "FAIL: malformed playlist fixture classification\n");
    yt_playlist_free(&malformed_playlist);
    yt_playlist_free(&playlist);
    yt_playlist_bootstrap_free(&bootstrap);
    return 1;
  }
  yt_playlist_free(&malformed_playlist);
  yt_playlist_free(&playlist);
  yt_playlist_bootstrap_free(&bootstrap);
  printf("PASS: playlist bootstrap, pagination, duplicate, and error fixtures\n");
  return 0;
}

static int test_playlist_collection_json(void) {
  static const char json[] =
      "{\"contents\":["
      "{\"lockupViewModel\":{\"contentId\":\"PL_current-1\","
      "\"contentType\":\"LOCKUP_CONTENT_TYPE_PLAYLIST\","
      "\"metadata\":{\"lockupMetadataViewModel\":{\"title\":{"
      "\"content\":\"Current playlist\"}}}}},"
      "{\"gridPlaylistRenderer\":{\"playlistId\":\"PL_old-2\","
      "\"title\":{\"runs\":[{\"text\":\"Old playlist\"}]}}},"
      "{\"playlistRenderer\":{\"playlistId\":\"PL_current-1\","
      "\"title\":{\"simpleText\":\"Duplicate\"}}}]}";
  YTPlaylistCollection collection;
  YTStatus status;
  memset(&collection, 0, sizeof(collection));
  status = yt_parse_playlist_collection_json(json, strlen(json),
                                             &collection);
  if (status != YT_OK || collection.playlist_count != 2 ||
      strcmp(collection.playlists[0].playlist_id, "PL_current-1") != 0 ||
      strcmp(collection.playlists[0].title, "Current playlist") != 0 ||
      collection.playlists[0].index != 1 ||
      strcmp(collection.playlists[1].playlist_id, "PL_old-2") != 0 ||
      strcmp(collection.playlists[1].title, "Old playlist") != 0 ||
      collection.playlists[1].index != 2) {
    fprintf(stderr, "FAIL: playlist collection JSON parsing\n");
    yt_playlist_collection_free(&collection);
    return 1;
  }
  yt_playlist_collection_free(&collection);
  printf("PASS: playlist collection JSON parsing\n");
  return 0;
}

static int test_default_output_path(void) {
  char path[256];
  char short_path[12];
  char utf8_path[9];
  char invalid_utf8_path[32];

  if (!retro_dlp_default_output_path("Fixture Title", SELF_TEST_VIDEO_ID,
                                     path, sizeof(path)) ||
      strcmp(path, "Fixture Title.mp4") != 0 ||
      !retro_dlp_default_output_path("../A/B:\n", SELF_TEST_VIDEO_ID,
                                     path, sizeof(path)) ||
      strcmp(path, "___A_B__.mp4") != 0 ||
      !retro_dlp_default_output_path("", SELF_TEST_VIDEO_ID,
                                     path, sizeof(path)) ||
      strcmp(path, SELF_TEST_VIDEO_ID ".mp4") != 0 ||
      !retro_dlp_default_output_path("abcdefghijk", SELF_TEST_VIDEO_ID,
                                     short_path, sizeof(short_path)) ||
      strcmp(short_path, "abcdefg.mp4") != 0 ||
      !retro_dlp_default_output_path("\xc3\xa9\xc3\xa9\xc3\xa9",
                                     SELF_TEST_VIDEO_ID, utf8_path,
                                     sizeof(utf8_path)) ||
      strcmp(utf8_path, "\xc3\xa9\xc3\xa9.mp4") != 0 ||
      !retro_dlp_default_output_path("\xed\xa0\x80" "bad",
                                     SELF_TEST_VIDEO_ID, invalid_utf8_path,
                                     sizeof(invalid_utf8_path)) ||
      strcmp(invalid_utf8_path, "___bad.mp4") != 0) {
    fprintf(stderr, "FAIL: title-based default output path\n");
    return 1;
  }
  printf("PASS: title-based default output path\n");
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
  static const char progressive_sizes[] =
      "{\"playabilityStatus\":{\"status\":\"OK\"},\"streamingData\":{"
      "\"formats\":["
      "{\"itag\":18,\"url\":\"https://fixture.googlevideo.com/360\","
      "\"mimeType\":\"video/mp4\",\"width\":640,\"height\":360},"
      "{\"itag\":22,\"url\":\"https://fixture.googlevideo.com/720\","
      "\"mimeType\":\"video/mp4\",\"width\":1280,\"height\":720},"
      "{\"itag\":37,\"url\":\"https://fixture.googlevideo.com/1080\","
      "\"mimeType\":\"video/mp4\",\"width\":1920,\"height\":1080}],"
      "\"adaptiveFormats\":["
      "{\"itag\":999,\"url\":\"https://fixture.googlevideo.com/ignored\","
      "\"mimeType\":\"video/mp4\",\"width\":3840,\"height\":2160}]}}";
  static const char adaptive_sizes[] =
      "{\"playabilityStatus\":{\"status\":\"OK\"},"
      "\"videoDetails\":{\"videoId\":\"fixture1234\","
      "\"title\":\"Fixture Title\"},\"streamingData\":{"
      "\"formats\":[{\"itag\":18,\"url\":\"https://fixture.googlevideo.com/"
      "progressive\",\"mimeType\":\"video/mp4; codecs=\\\"avc1.42001E, "
      "mp4a.40.2\\\"\",\"width\":640,\"height\":360}],"
      "\"adaptiveFormats\":["
      "{\"itag\":137,\"url\":\"https://fixture.googlevideo.com/v1080\","
      "\"mimeType\":\"video/mp4; codecs=\\\"avc1.640028\\\"\","
      "\"width\":1920,\"height\":1080,\"fps\":30,\"bitrate\":4000000},"
      "{\"itag\":299,\"url\":\"https://fixture.googlevideo.com/v1080-60\","
      "\"mimeType\":\"video/mp4; codecs=\\\"avc1.64002a\\\"\","
      "\"width\":1920,\"height\":1080,\"fps\":60,\"bitrate\":6000000},"
      "{\"itag\":136,\"url\":\"https://fixture.googlevideo.com/v720\","
      "\"mimeType\":\"video/mp4; codecs=\\\"avc1.4d401f\\\"\","
      "\"width\":1280,\"height\":720,\"fps\":30,\"bitrate\":2000000},"
      "{\"itag\":247,\"url\":\"https://fixture.googlevideo.com/vp9\","
      "\"mimeType\":\"video/webm; codecs=\\\"vp9\\\"\","
      "\"width\":1280,\"height\":720,\"bitrate\":3000000},"
      "{\"itag\":398,\"url\":\"https://fixture.googlevideo.com/av1\","
      "\"mimeType\":\"video/mp4; codecs=\\\"av01.0.05M.08\\\"\","
      "\"width\":1280,\"height\":720,\"bitrate\":2500000},"
      "{\"itag\":139,\"url\":\"https://fixture.googlevideo.com/aac-low\","
      "\"mimeType\":\"audio/mp4; codecs=\\\"mp4a.40.2\\\"\","
      "\"bitrate\":48000},"
      "{\"itag\":140,\"url\":\"https://fixture.googlevideo.com/aac\","
      "\"mimeType\":\"audio/mp4; codecs=\\\"mp4a.40.2\\\"\","
      "\"audioChannels\":2,\"bitrate\":129000},"
      "{\"itag\":599,\"url\":\"https://fixture.googlevideo.com/he-aac\","
      "\"mimeType\":\"audio/mp4; codecs=\\\"mp4a.40.5\\\"\","
      "\"audioChannels\":2,\"bitrate\":32000},"
      "{\"itag\":258,\"url\":\"https://fixture.googlevideo.com/aac-6ch\","
      "\"mimeType\":\"audio/mp4; codecs=\\\"mp4a.40.2\\\"\","
      "\"audioChannels\":6,\"bitrate\":384000},"
      "{\"itag\":251,\"url\":\"https://fixture.googlevideo.com/opus\","
      "\"mimeType\":\"audio/webm; codecs=\\\"opus\\\"\","
      "\"bitrate\":160000}]}}";
  YTMediaRequest media;
  YTMediaSelection selection;
  YTStatus status;

  if (!has_mp4_ftyp(mp4_prefix, sizeof(mp4_prefix)) ||
      has_mp4_ftyp((const unsigned char *)"<html>error", 11)) {
    fprintf(stderr, "FAIL: MP4 download prefix validation\n");
    return 1;
  }

  status = yt_test_parse_player_response(retro_dlp_player_itag18_fixture,
                                    retro_dlp_player_itag18_fixture_length,
                                    &media);
  if (status != YT_OK || media.itag != 22 || media.width != 1280 ||
      media.height != 720 || media.expires_unix != 1900000000LL ||
      media.url == NULL || strstr(media.url, "itag=22") == NULL ||
      media.mime_type == NULL ||
      strncmp(media.mime_type, "video/mp4", 9) != 0) {
    fprintf(stderr, "FAIL: deterministic default player fixture\n");
    if (status == YT_OK)
      yt_media_request_free(&media);
    return 1;
  }
  yt_media_request_free(&media);

  status = yt_test_parse_player_response_with_adaptive_size(
      adaptive_sizes, sizeof(adaptive_sizes) - 1, 720, &selection);
  if (status != YT_OK || !selection.adaptive ||
      selection.video.itag != 136 || selection.video.height != 720 ||
      selection.audio.itag != 140 || selection.audio.url == NULL ||
      strstr(selection.audio.url, "aac") == NULL) {
    fprintf(stderr, "FAIL: adaptive 720p H.264/AAC format selection\n");
    if (status == YT_OK)
      yt_media_selection_free(&selection);
    return 1;
  }
  yt_media_selection_free(&selection);

  if (!yt_format_expression_valid("18") ||
      !yt_format_expression_valid("137+140/136+140/18") ||
      yt_format_expression_valid("best") ||
      yt_format_expression_valid("136,140") ||
      yt_format_expression_valid("136+") ||
      yt_format_expression_valid("136+140+141")) {
    fprintf(stderr, "FAIL: exact format expression grammar\n");
    return 1;
  }

  status = yt_test_parse_player_response_with_format(
      adaptive_sizes, sizeof(adaptive_sizes) - 1, "136+140", &selection);
  if (status != YT_OK || !selection.adaptive ||
      selection.video.itag != 136 || selection.audio.itag != 140 ||
      selection.format_id == NULL ||
      strcmp(selection.format_id, "136+140") != 0 ||
      selection.video_id == NULL ||
      strcmp(selection.video_id, "fixture1234") != 0 ||
      selection.title == NULL || strcmp(selection.title, "Fixture Title") != 0 ||
      selection.format_count < 10 || selection.formats[0].itag != 18 ||
      selection.formats[1].itag != 136 || selection.formats[2].itag != 137 ||
      selection.formats[3].itag != 299 || selection.formats[4].itag != 139 ||
      selection.formats[5].itag != 140 || selection.formats[6].itag != 599 ||
      selection.formats[7].itag != 398 || selection.formats[8].itag != 247 ||
      !selection.formats[3].supported || !selection.formats[6].supported ||
      selection.formats[7].supported || selection.formats[8].supported) {
    fprintf(stderr, "FAIL: exact adaptive format selection\n");
    if (status == YT_OK)
      yt_media_selection_free(&selection);
    return 1;
  }
  yt_media_selection_free(&selection);

  status = yt_test_parse_player_response_with_format(
      adaptive_sizes, sizeof(adaptive_sizes) - 1, "136+599", &selection);
  if (status != YT_OK || !selection.adaptive ||
      selection.video.itag != 136 || selection.audio.itag != 599) {
    fprintf(stderr, "FAIL: exact HE-AAC format selection\n");
    if (status == YT_OK)
      yt_media_selection_free(&selection);
    return 1;
  }
  yt_media_selection_free(&selection);

  status = yt_test_parse_player_response_with_format(
      adaptive_sizes, sizeof(adaptive_sizes) - 1, "999+140/18", &selection);
  if (status != YT_OK || selection.adaptive || selection.video.itag != 18 ||
      selection.format_id == NULL || strcmp(selection.format_id, "18") != 0) {
    fprintf(stderr, "FAIL: explicit exact-format fallback\n");
    if (status == YT_OK)
      yt_media_selection_free(&selection);
    return 1;
  }
  yt_media_selection_free(&selection);

  status = yt_test_parse_player_response_with_format(
      adaptive_sizes, sizeof(adaptive_sizes) - 1, "137+1399", &selection);
  if (status != YT_ERR_FORMAT_UNAVAILABLE || selection.format_count == 0) {
    fprintf(stderr, "FAIL: unavailable format inventory\n");
    if (status == YT_OK)
      yt_media_selection_free(&selection);
    return 1;
  }
  yt_media_selection_free(&selection);

  status = yt_test_parse_player_response_with_adaptive_size(
      progressive_sizes, sizeof(progressive_sizes) - 1, 720, &selection);
  if (status != YT_OK || selection.adaptive || selection.video.itag != 22 ||
      selection.video.height != 720 || selection.audio.url != NULL) {
    fprintf(stderr, "FAIL: adaptive selection did not fall back to progressive\n");
    if (status == YT_OK)
      yt_media_selection_free(&selection);
    return 1;
  }
  yt_media_selection_free(&selection);

  status = yt_test_parse_player_response_with_adaptive_size(
      adaptive_sizes, sizeof(adaptive_sizes) - 1, 1080, &selection);
  if (status != YT_OK || !selection.adaptive ||
      selection.video.itag != 137 || selection.video.height != 1080 ||
      selection.audio.itag != 140) {
    fprintf(stderr, "FAIL: adaptive 1080p H.264/AAC format selection\n");
    if (status == YT_OK)
      yt_media_selection_free(&selection);
    return 1;
  }
  yt_media_selection_free(&selection);

  status = yt_test_parse_player_response_with_adaptive_size(
      adaptive_sizes, sizeof(adaptive_sizes) - 1, 480, &selection);
  if (status != YT_ERR_INVALID_RESPONSE) {
    fprintf(stderr, "FAIL: adaptive selection accepted 480p\n");
    if (status == YT_OK)
      yt_media_selection_free(&selection);
    return 1;
  }

  status = yt_test_parse_player_response_with_max_height(
      adaptive_sizes, sizeof(adaptive_sizes) - 1, 480, &media);
  if (status != YT_OK || media.itag != 18 || media.height != 360) {
    fprintf(stderr, "FAIL: 480p path did not remain progressive-only\n");
    if (status == YT_OK)
      yt_media_request_free(&media);
    return 1;
  }
  yt_media_request_free(&media);

  status = yt_test_parse_player_response_with_max_height(
      retro_dlp_player_itag18_fixture,
      retro_dlp_player_itag18_fixture_length, 480, &media);
  if (status != YT_OK || media.itag != 18 || media.width != 640 ||
      media.height != 360 || media.expires_unix != 1900000000LL ||
      media.content_length != 12345678LL || media.url == NULL ||
      strstr(media.url, "itag=18") == NULL) {
    fprintf(stderr, "FAIL: deterministic 480p fallback fixture\n");
    if (status == YT_OK)
      yt_media_request_free(&media);
    return 1;
  }
  yt_media_request_free(&media);

  status = yt_test_parse_player_response(progressive_sizes,
                                    sizeof(progressive_sizes) - 1, &media);
  if (status != YT_OK || media.itag != 22 || media.height != 720) {
    fprintf(stderr, "FAIL: default 720p progressive format selection\n");
    if (status == YT_OK)
      yt_media_request_free(&media);
    return 1;
  }
  yt_media_request_free(&media);

  status = yt_test_parse_player_response_with_max_height(
      progressive_sizes, sizeof(progressive_sizes) - 1, 480, &media);
  if (status != YT_OK || media.itag != 18 || media.height != 360) {
    fprintf(stderr, "FAIL: 480p progressive format fallback\n");
    if (status == YT_OK)
      yt_media_request_free(&media);
    return 1;
  }
  yt_media_request_free(&media);

  status = yt_test_parse_player_response_with_max_height(
      progressive_sizes, sizeof(progressive_sizes) - 1, 1080, &media);
  if (status != YT_OK || media.itag != 37 || media.height != 1080) {
    fprintf(stderr, "FAIL: 1080p progressive format selection\n");
    if (status == YT_OK)
      yt_media_request_free(&media);
    return 1;
  }
  yt_media_request_free(&media);

  status = yt_test_parse_player_response(direct_after_challenge,
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

  status = yt_test_parse_player_response(
      retro_dlp_player_n_challenge_fixture,
      retro_dlp_player_n_challenge_fixture_length, &media);
  if (status != YT_ERR_NO_PROGRESSIVE_MP4) {
    fprintf(stderr, "FAIL: unresolved s/n challenge fixture was accepted\n");
    if (status == YT_OK)
      yt_media_request_free(&media);
    return 1;
  }

  status = yt_test_parse_player_response(retro_dlp_player_unavailable_fixture,
                                    retro_dlp_player_unavailable_fixture_length,
                                    &media);
  if (status != YT_ERR_UNAVAILABLE) {
    fprintf(stderr, "FAIL: unavailable player fixture classification\n");
    return 1;
  }

  printf("PASS: deterministic player fixtures\n");
  return 0;
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

int retro_dlp_run_self_tests(void) {
  int failures;

  setvbuf(stdout, NULL, _IONBF, 0);
  fflush(stderr);
  dup2(STDOUT_FILENO, STDERR_FILENO);

  announce_test("libcurl availability");
  failures = test_libcurl();
  announce_test("YouTube video ID parsing");
  failures += test_video_id();
  failures += test_playlist_id();
  failures += test_playlist_collection_json();
  failures += test_playlist_page_fixtures();
  failures += retro_dlp_run_playlist_metadata_tests();
  announce_test("title-based default output path");
  failures += test_default_output_path();
  announce_test("cJSON parsing");
  failures += test_cjson();
  announce_test("deterministic player fixtures");
  failures += test_offline_player_fixtures();
  announce_test("QuickJS evaluation");
  failures += test_quickjs();
  announce_test("cache and SHA-256 fixtures");
  failures += retro_dlp_run_cache_tests();
  announce_test("allocation failure contracts");
  failures += retro_dlp_run_allocation_tests();
  announce_test("cookie authentication fixtures");
  failures += retro_dlp_run_cookie_tests();
  announce_test("EJS fixtures and runtime limits");
  failures += retro_dlp_run_ejs_tests(getenv("RETRO_DLP_TEST_EJS_DIR"));
  if (failures != 0)
    return 1;

  printf("PASS: retro-dlp self-test\n");
  return 0;
}
