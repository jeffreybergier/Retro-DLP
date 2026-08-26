#include "ejs_test.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ejs_test_data.h"
#include "yt_ejs.h"
#include "yt_ejs_assets.h"
#include "yt_ejs_internal.h"
#include "yt_resolver.h"

static const char *const signature_challenges[] = {
    RETRO_DLP_EJS_SIG_INPUT_1, RETRO_DLP_EJS_SIG_INPUT_2};
static const char *const n_challenges[] = {RETRO_DLP_EJS_N_INPUT_1,
                                           RETRO_DLP_EJS_N_INPUT_2};
static const YTEJSRequest requests[] = {
    {YT_EJS_CHALLENGE_SIGNATURE, signature_challenges, 2},
    {YT_EJS_CHALLENGE_N, n_challenges, 2}};

static int result_matches_fixture(const YTEJSResult *result) {
  return result->response_count == 2 && result->responses != NULL &&
         result->responses[0].error == NULL &&
         result->responses[0].solution_count == 2 &&
         result->responses[0].solutions != NULL &&
         strcmp(result->responses[0].solutions[0],
                RETRO_DLP_EJS_SIG_OUTPUT_1) == 0 &&
         strcmp(result->responses[0].solutions[1],
                RETRO_DLP_EJS_SIG_OUTPUT_2) == 0 &&
         result->responses[1].error == NULL &&
         result->responses[1].solution_count == 2 &&
         result->responses[1].solutions != NULL &&
         strcmp(result->responses[1].solutions[0], RETRO_DLP_EJS_N_OUTPUT_1) ==
             0 &&
         strcmp(result->responses[1].solutions[1], RETRO_DLP_EJS_N_OUTPUT_2) ==
             0;
}

static int test_player_and_preprocessed_solver(void) {
  YTEJSResult result;
  YTEJSResult warm_result;
  YTEJSStatus status;
  char *preprocessed;

  status = yt_ejs_solve(YT_EJS_SOURCE_PLAYER, retro_dlp_ejs_player_fixture,
                        requests, 2, NULL, &result);
  if (status != YT_EJS_OK || !result_matches_fixture(&result) ||
      result.preprocessed_player == NULL ||
      result.preprocessed_player[0] == '\0') {
    fprintf(stderr, "FAIL: EJS player fixture: %s%s%s\n",
            yt_ejs_status_string(status),
            result.error_message == NULL ? "" : ": ",
            result.error_message == NULL ? "" : result.error_message);
    yt_ejs_result_free(&result);
    return 1;
  }

  preprocessed = result.preprocessed_player;
  result.preprocessed_player = NULL;
  yt_ejs_result_free(&result);
  status = yt_ejs_solve(YT_EJS_SOURCE_PREPROCESSED, preprocessed, requests, 2,
                        NULL, &warm_result);
  if (status != YT_EJS_OK || !result_matches_fixture(&warm_result) ||
      warm_result.preprocessed_player != NULL) {
    fprintf(stderr, "FAIL: EJS preprocessed fixture: %s%s%s\n",
            yt_ejs_status_string(status),
            warm_result.error_message == NULL ? "" : ": ",
            warm_result.error_message == NULL ? "" :
                                                 warm_result.error_message);
    yt_ejs_result_free(&warm_result);
    free(preprocessed);
    return 1;
  }
  yt_ejs_result_free(&warm_result);
  free(preprocessed);
  printf("PASS: EJS 0.8.0 sig/n batch and preprocessed fixtures\n");
  return 0;
}

static int test_resolver_cipher_wiring(void) {
  YTMediaRequest media;
  YTStatus status;
  status = yt_parse_player_response_with_javascript(
      retro_dlp_ejs_cipher_response_fixture,
      (size_t)retro_dlp_ejs_cipher_response_fixture_length,
      retro_dlp_ejs_player_fixture, &media);
  if (status != YT_OK || media.url == NULL ||
      strstr(media.url, "n=xyz-n") == NULL ||
      strstr(media.url, "sig=cba") == NULL || media.itag != 18 ||
      media.expires_unix != 1900000000LL) {
    fprintf(stderr, "FAIL: resolver EJS s/n wiring: %s\n",
            yt_status_string(status));
    if (status == YT_OK)
      yt_media_request_free(&media);
    return 1;
  }
  yt_media_request_free(&media);
  printf("PASS: resolver batched signatureCipher and n transformation\n");
  return 0;
}

static int test_malformed_result(void) {
  static const char malformed_result[] =
      "{\"type\":\"result\",\"responses\":["
      "{\"type\":\"result\",\"data\":{}}]}";
  YTEJSResult result;
  YTEJSStatus status;

  status = yt_ejs_parse_result_json(malformed_result, requests, 2, &result);
  if (status != YT_EJS_ERR_INVALID_RESULT) {
    fprintf(stderr, "FAIL: malformed EJS result was accepted\n");
    if (status == YT_EJS_OK)
      yt_ejs_result_free(&result);
    return 1;
  }
  printf("PASS: malformed EJS result classification\n");
  return 0;
}

static int test_exception_and_recovery(void) {
  YTEJSResult result;
  YTEJSStatus status;

  status = yt_ejs_solve(YT_EJS_SOURCE_PLAYER, "not valid JavaScript {",
                        requests, 2, NULL, &result);
  if (status != YT_EJS_ERR_JAVASCRIPT || result.error_message == NULL) {
    fprintf(stderr, "FAIL: EJS exception classification: %s\n",
            yt_ejs_status_string(status));
    yt_ejs_result_free(&result);
    return 1;
  }
  yt_ejs_result_free(&result);

  status = yt_ejs_solve(YT_EJS_SOURCE_PLAYER, retro_dlp_ejs_player_fixture,
                        requests, 2, NULL, &result);
  if (status != YT_EJS_OK || !result_matches_fixture(&result)) {
    fprintf(stderr, "FAIL: EJS runtime recovery after exception\n");
    yt_ejs_result_free(&result);
    return 1;
  }
  yt_ejs_result_free(&result);
  printf("PASS: EJS exception classification and runtime recovery\n");
  return 0;
}

static int test_timeout_and_memory_limit(void) {
  YTEJSConfig config;
  YTEJSResult result;
  YTEJSStatus status;

  config = yt_ejs_default_config();
  config.timeout_milliseconds = 0;
  status = yt_ejs_solve(YT_EJS_SOURCE_PLAYER, retro_dlp_ejs_player_fixture,
                        requests, 2, &config, &result);
  if (status != YT_EJS_ERR_TIMEOUT) {
    fprintf(stderr, "FAIL: EJS timeout classification: %s\n",
            yt_ejs_status_string(status));
    yt_ejs_result_free(&result);
    return 1;
  }
  yt_ejs_result_free(&result);

  config = yt_ejs_default_config();
  config.memory_limit_bytes = 64U * 1024U;
  status = yt_ejs_solve(YT_EJS_SOURCE_PLAYER, retro_dlp_ejs_player_fixture,
                        requests, 2, &config, &result);
  if (status != YT_EJS_ERR_OUT_OF_MEMORY) {
    fprintf(stderr, "FAIL: EJS memory-limit classification: %s\n",
            yt_ejs_status_string(status));
    yt_ejs_result_free(&result);
    return 1;
  }
  yt_ejs_result_free(&result);

  status = yt_ejs_solve(YT_EJS_SOURCE_PLAYER, retro_dlp_ejs_player_fixture,
                        requests, 2, NULL, &result);
  if (status != YT_EJS_OK || !result_matches_fixture(&result)) {
    fprintf(stderr, "FAIL: EJS runtime recovery after resource failure\n");
    yt_ejs_result_free(&result);
    return 1;
  }
  yt_ejs_result_free(&result);
  printf("PASS: EJS execution limits and resource-failure recovery\n");
  return 0;
}

int retro_dlp_run_ejs_tests(void) {
  int failures;
  YTEJSAssetsInfo info;
  YTEJSAssetsStatus assets_status;

  assets_status = yt_ejs_assets_inspect(&info);
  if (assets_status == YT_EJS_ASSETS_MISSING) {
    printf("SKIP: EJS assets missing (run: retro-dlp assets install)\n");
    return 0;
  }
  if (assets_status != YT_EJS_ASSETS_OK) {
    fprintf(stderr, "FAIL: EJS assets: %s\n",
            yt_ejs_assets_status_string(assets_status));
    return 1;
  }

  failures = test_player_and_preprocessed_solver();
  failures += test_resolver_cipher_wiring();
  failures += test_malformed_result();
  failures += test_exception_and_recovery();
  failures += test_timeout_and_memory_limit();
  return failures;
}
