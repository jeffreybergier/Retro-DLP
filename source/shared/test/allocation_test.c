#include "allocation_test.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "retrodlp/retrodlp.h"
#include "yt_playlist_internal.h"

typedef enum {
  ALLOCATION_FAILURE_NONE = 0,
  ALLOCATION_FAILURE_MALLOC_SIZE,
  ALLOCATION_FAILURE_NTH,
  ALLOCATION_FAILURE_NEXT_CALLOC
} AllocationFailureMode;

static AllocationFailureMode allocation_failure_mode;
static size_t allocation_failure_size;
static size_t allocation_observed_size;
static size_t allocation_countdown;

void *__real_malloc(size_t size);
void *__real_calloc(size_t count, size_t size);
void *__real_realloc(void *pointer, size_t size);

static int fail_nth_allocation(void) {
  if (allocation_failure_mode == ALLOCATION_FAILURE_NTH &&
      --allocation_countdown == 0) {
    allocation_failure_mode = ALLOCATION_FAILURE_NONE;
    return 1;
  }
  return 0;
}

void *__wrap_realloc(void *pointer, size_t size) {
  return fail_nth_allocation() ? NULL : __real_realloc(pointer, size);
}

void *__wrap_malloc(size_t size) {
  if (fail_nth_allocation())
    return NULL;
  if (allocation_failure_mode == ALLOCATION_FAILURE_MALLOC_SIZE)
    allocation_observed_size = size;
  if (allocation_failure_mode == ALLOCATION_FAILURE_MALLOC_SIZE &&
      size == allocation_failure_size) {
    allocation_failure_mode = ALLOCATION_FAILURE_NONE;
    return NULL;
  }
  return __real_malloc(size);
}

void *__wrap_calloc(size_t count, size_t size) {
  if (fail_nth_allocation())
    return NULL;
  if (allocation_failure_mode == ALLOCATION_FAILURE_NEXT_CALLOC) {
    allocation_failure_mode = ALLOCATION_FAILURE_NONE;
    return NULL;
  }
  return __real_calloc(count, size);
}

static void fail_malloc_of_size(size_t size) {
  allocation_failure_size = size;
  allocation_observed_size = 0;
  allocation_failure_mode = ALLOCATION_FAILURE_MALLOC_SIZE;
}

static void fail_next_calloc(void) {
  allocation_failure_mode = ALLOCATION_FAILURE_NEXT_CALLOC;
}

static void reset_allocation_failure(void) {
  allocation_failure_mode = ALLOCATION_FAILURE_NONE;
  allocation_failure_size = 0;
}

static rdlp_error_code unused_transport_send(
    void *context, const rdlp_transport_request *request,
    rdlp_transport_response *response, rdlp_error *error) {
  (void)context;
  (void)request;
  (void)response;
  (void)error;
  return RDLP_ERROR_TRANSPORT_REQUEST_FAILED;
}

static int test_owned_result_allocations(void) {
  rdlp_transport transport;
  rdlp_config config;
  rdlp_context *context;
  rdlp_selection *selection;
  rdlp_playlist *playlist;
  rdlp_playlist_collection *collection;
  rdlp_error error;
  int failures = 0;

  memset(&transport, 0, sizeof(transport));
  memset(&config, 0, sizeof(config));
  memset(&error, 0, sizeof(error));
  transport.struct_size = sizeof(transport);
  transport.send = unused_transport_send;
  config.struct_size = sizeof(config);
  config.transport = &transport;
  error.struct_size = sizeof(error);
  context = NULL;
  if (rdlp_context_create(&config, &context, &error) != RDLP_OK) {
    fprintf(stderr, "FAIL: allocation fixture context setup\n");
    return 1;
  }

  selection = (rdlp_selection *)(size_t)1;
  fail_next_calloc();
  if (rdlp_resolve_video(context, "YE7VzlLtp-4", NULL, &selection, &error) !=
          RDLP_ERROR_OUT_OF_MEMORY ||
      selection != NULL || error.code != RDLP_ERROR_OUT_OF_MEMORY) {
    reset_allocation_failure();
    fprintf(stderr, "FAIL: selection result allocation failure contract\n");
    ++failures;
  }

  playlist = (rdlp_playlist *)(size_t)1;
  fail_next_calloc();
  if (rdlp_list_playlist(context, "PL_allocation_fixture", NULL, &playlist,
                         &error) != RDLP_ERROR_OUT_OF_MEMORY ||
      playlist != NULL || error.code != RDLP_ERROR_OUT_OF_MEMORY) {
    reset_allocation_failure();
    fprintf(stderr, "FAIL: playlist result allocation failure contract\n");
    ++failures;
  }

  collection = (rdlp_playlist_collection *)(size_t)1;
  fail_next_calloc();
  if (rdlp_list_playlist_collection(
          context, "https://www.youtube.com/feed/playlists", NULL,
          &collection, &error) != RDLP_ERROR_OUT_OF_MEMORY ||
      collection != NULL || error.code != RDLP_ERROR_OUT_OF_MEMORY) {
    reset_allocation_failure();
    fprintf(stderr,
            "FAIL: playlist collection result allocation failure contract\n");
    ++failures;
  }

  rdlp_context_destroy(context);
  if (failures == 0)
    printf("PASS: owned-result allocation failure contracts\n");
  return failures;
}

static int test_pagination_token_allocation(void) {
  static const char continuation_json[] =
      "{\"contents\":[{\"playlistVideoRenderer\":{"
      "\"videoId\":\"AAAAAAAAAAA\",\"title\":{"
      "\"simpleText\":\"Video\"}}},{\"continuationItemRenderer\":{"
      "\"continuationEndpoint\":{\"continuationCommand\":{"
      "\"token\":\"page-two\"}}}}]}";
  cJSON *document;
  YTPlaylist playlist;
  char *continuation;
  YTStatus status;

  document = cJSON_Parse(continuation_json);
  if (document == NULL) {
    fprintf(stderr, "FAIL: pagination allocation fixture setup\n");
    return 1;
  }
  memset(&playlist, 0, sizeof(playlist));
  continuation = (char *)(size_t)1;
  fail_malloc_of_size(sizeof("page-two"));
  status = yt_playlist_collect_entries(document, &playlist, &continuation);
  reset_allocation_failure();
  cJSON_Delete(document);
  yt_playlist_free(&playlist);
  if (status != YT_ERR_OUT_OF_MEMORY || continuation != NULL) {
    free(continuation);
    fprintf(stderr,
            "FAIL: pagination token allocation failure contract "
            "(status=%d allocation=%lu)\n",
            (int)status, (unsigned long)allocation_observed_size);
    return 1;
  }
  printf("PASS: pagination token allocation failure contract\n");
  return 0;
}

static int test_metadata_allocations(void) {
  static const char json[] =
      "{\"contents\":[{\"playlistVideoRenderer\":{"
      "\"videoId\":\"AAAAAAAAAAA\",\"title\":{\"runs\":[{\"text\":\"Rich \"},"
      "{\"text\":\"title\"}]},\"lengthText\":{\"simpleText\":\"1:02\"},"
      "\"shortBylineText\":{\"runs\":[{\"text\":\"Channel\",\"navigationEndpoint\":{"
      "\"browseEndpoint\":{\"browseId\":\"UC_fixture\"}}}]},"
      "\"thumbnail\":{\"thumbnails\":[{\"url\":\"https://img.example/1\"},"
      "{\"url\":\"https://img.example/2\"}]},"
      "\"descriptionSnippet\":{\"simpleText\":\"Description\"},"
      "\"publishedTimeText\":{\"simpleText\":\"Yesterday\"},"
      "\"viewCountText\":{\"simpleText\":\"123 views\"}}}]}";
  cJSON *document = cJSON_Parse(json);
  size_t nth;
  int complete = 0;
  if (document == NULL)
    return 1;
  for (nth = 1; nth < 100; ++nth) {
    YTPlaylist playlist;
    char *continuation = NULL;
    YTStatus status;
    int injected;
    memset(&playlist, 0, sizeof(playlist));
    allocation_countdown = nth;
    allocation_failure_mode = ALLOCATION_FAILURE_NTH;
    status = yt_playlist_collect_entries(document, &playlist, &continuation);
    injected = allocation_failure_mode == ALLOCATION_FAILURE_NONE;
    reset_allocation_failure();
    free(continuation);
    yt_playlist_free(&playlist);
    if (status != (injected ? YT_ERR_OUT_OF_MEMORY : YT_OK)) {
      fprintf(stderr, "FAIL: playlist metadata allocation %lu (status=%d)\n",
              (unsigned long)nth, (int)status);
      cJSON_Delete(document);
      return 1;
    }
    if (!injected) {
      complete = 1;
      break;
    }
  }
  cJSON_Delete(document);
  if (!complete)
    return 1;
  printf("PASS: playlist metadata cleanup at every allocation failure (%lu sites)\n",
         (unsigned long)(nth - 1));
  return 0;
}

int retro_dlp_run_allocation_tests(void) {
  int failures;
  printf("RUN: injectable allocation failures\n");
  fflush(stdout);
  failures = test_owned_result_allocations();
  failures += test_pagination_token_allocation();
  failures += test_metadata_allocations();
  reset_allocation_failure();
  return failures;
}
