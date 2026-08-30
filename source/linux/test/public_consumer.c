#define _GNU_SOURCE

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <retrodlp/assets.h>
#include <retrodlp/retrodlp.h>

typedef struct {
  pthread_mutex_t mutex;
  pthread_cond_t condition;
  int arrivals;
} fixture_gate;

typedef struct {
  int requests;
  int events;
  int cancelled;
  int reenter_cancel;
  int saw_clock;
  int64_t now;
  rdlp_context *reentry_context;
  rdlp_status reentry_status;
  fixture_gate *gate;
  int failure_mode;
} fixture_state;

enum {
  FIXTURE_SUCCESS = 0,
  FIXTURE_NETWORK_FAILURE,
  FIXTURE_HTTP_FAILURE,
  FIXTURE_MALFORMED_RESPONSE,
  FIXTURE_OVERSIZED_RESPONSE
};

typedef struct {
  fixture_state state;
  const char *cache_directory;
  int result;
} thread_case;

typedef struct {
  int requests;
  int cancelled;
} cancellation_fixture;

typedef struct {
  int saved_stdout;
  int saved_stderr;
  int stdout_read;
  int stderr_read;
} output_capture;

static int begin_output_capture(output_capture *capture) {
  int stdout_pipe[2];
  int stderr_pipe[2];
  fflush(NULL);
  if (pipe(stdout_pipe) != 0 || pipe(stderr_pipe) != 0)
    return 0;
  capture->saved_stdout = dup(STDOUT_FILENO);
  capture->saved_stderr = dup(STDERR_FILENO);
  capture->stdout_read = stdout_pipe[0];
  capture->stderr_read = stderr_pipe[0];
  if (capture->saved_stdout < 0 || capture->saved_stderr < 0 ||
      dup2(stdout_pipe[1], STDOUT_FILENO) < 0 ||
      dup2(stderr_pipe[1], STDERR_FILENO) < 0)
    return 0;
  close(stdout_pipe[1]);
  close(stderr_pipe[1]);
  return 1;
}

static int end_output_capture(output_capture *capture) {
  char byte;
  ssize_t stdout_count;
  ssize_t stderr_count;
  fflush(NULL);
  dup2(capture->saved_stdout, STDOUT_FILENO);
  dup2(capture->saved_stderr, STDERR_FILENO);
  close(capture->saved_stdout);
  close(capture->saved_stderr);
  stdout_count = read(capture->stdout_read, &byte, 1);
  stderr_count = read(capture->stderr_read, &byte, 1);
  close(capture->stdout_read);
  close(capture->stderr_read);
  return stdout_count == 0 && stderr_count == 0;
}

static void wait_for_peer(fixture_state *state) {
  fixture_gate *gate = state->gate;
  if (gate == NULL)
    return;
  pthread_mutex_lock(&gate->mutex);
  ++gate->arrivals;
  if (gate->arrivals == 2)
    pthread_cond_broadcast(&gate->condition);
  while (gate->arrivals < 2)
    pthread_cond_wait(&gate->condition, &gate->mutex);
  pthread_mutex_unlock(&gate->mutex);
}

static rdlp_status fixture_send(void *opaque,
                                const rdlp_transport_request *request,
                                rdlp_transport_response *response,
                                rdlp_error *error) {
  static const char bootstrap[] =
      "{\"INNERTUBE_CONTEXT_CLIENT_VERSION\":\"2.20260708.05.00\","
      "\"STS\":12345,\"jsUrl\":\"/s/player/fixture/base.js\"}";
  static const char player[] =
      "{\"playabilityStatus\":{\"status\":\"OK\"},"
      "\"videoDetails\":{\"videoId\":\"YE7VzlLtp-4\","
      "\"title\":\"Public API fixture\"},\"streamingData\":{"
      "\"formats\":[{\"itag\":18,"
      "\"url\":\"https://fixture.googlevideo.com/media?expire=1900000000\","
      "\"mimeType\":\"video/mp4; codecs=\\\"avc1.42001E, mp4a.40.2\\\"\","
      "\"width\":640,\"height\":360,\"contentLength\":\"1234\"}]}}";
  fixture_state *state = (fixture_state *)opaque;
  const char *data;
  size_t index;
  (void)error;
  if (state->failure_mode == FIXTURE_NETWORK_FAILURE) {
    if (error != NULL) {
      error->status = RDLP_STATUS_NETWORK;
      error->transport_code = 77;
      snprintf(error->message, sizeof(error->message), "fixture network failure");
    }
    return RDLP_STATUS_NETWORK;
  }
  if (request->cancel_callback != NULL &&
      request->cancel_callback(request->cancel_context))
    return RDLP_STATUS_CANCELLED;
  if (request->method == RDLP_HTTP_GET &&
      strstr(request->url, "m.youtube.com/watch") != NULL)
    data = bootstrap;
  else if (request->method == RDLP_HTTP_POST &&
           strstr(request->url, "/youtubei/v1/player") != NULL)
    data = player;
  else
    return RDLP_STATUS_NETWORK;
  if (state->requests == 0)
    wait_for_peer(state);
  for (index = 0; index < request->header_count; ++index) {
    if (strcmp(request->headers[index].name, "Authorization") == 0 &&
        strstr(request->headers[index].value, "1700000000_") != NULL)
      state->saw_clock = 1;
  }
  ++state->requests;
  response->http_status = state->failure_mode == FIXTURE_HTTP_FAILURE ? 503 : 200;
  response->data = state->failure_mode == FIXTURE_MALFORMED_RESPONSE ? "{" : data;
  response->data_length = state->failure_mode == FIXTURE_OVERSIZED_RESPONSE
                              ? request->maximum_response_bytes + 1
                              : strlen((const char *)response->data);
  return RDLP_STATUS_OK;
}

static void fixture_event(const rdlp_event *event, void *opaque) {
  fixture_state *state = (fixture_state *)opaque;
  if (event != NULL && event->struct_size >= sizeof(*event))
    ++state->events;
}

static int fixture_cancel(void *opaque) {
  fixture_state *state = (fixture_state *)opaque;
  if (state->reenter_cancel) {
    rdlp_selection *selection = NULL;
    rdlp_error error;
    memset(&error, 0, sizeof(error));
    error.struct_size = sizeof(error);
    state->reenter_cancel = 0;
    state->reentry_status =
        rdlp_resolve_video(state->reentry_context, "YE7VzlLtp-4", NULL,
                           &selection, &error);
    rdlp_selection_destroy(selection);
  }
  return state->cancelled;
}

static int64_t fixture_clock(void *opaque) {
  return ((fixture_state *)opaque)->now;
}

static int asset_api_test(void) {
  char directory[] = "/tmp/retrodlp-assets-api-XXXXXX";
  rdlp_ejs_asset_info info;
  rdlp_error error;
  int passed;
  if (mkdtemp(directory) == NULL)
    return 0;
  memset(&info, 0, sizeof(info));
  memset(&error, 0, sizeof(error));
  info.struct_size = sizeof(info);
  error.struct_size = sizeof(error);
  passed = strcmp(rdlp_ejs_asset_version(), RDLP_EJS_ASSET_VERSION) == 0 &&
           rdlp_ejs_assets_inspect(directory, &info, &error) ==
               RDLP_STATUS_EJS_ASSETS_MISSING &&
           !info.installed && !info.core_valid && !info.lib_valid &&
           error.status == RDLP_STATUS_EJS_ASSETS_MISSING &&
           rdlp_ejs_assets_remove(directory, &error) == RDLP_STATUS_OK &&
           error.status == RDLP_STATUS_OK;
  rmdir(directory);
  return passed;
}

static void remove_fixture_cache(const char *root) {
  rmdir(root);
}

static void *run_thread_case(void *opaque) {
  static const char cookies[] =
      "# Netscape HTTP Cookie File\n"
      ".youtube.com\tTRUE\t/\tTRUE\t1900000000\tLOGIN_INFO\tfixture\n"
      ".youtube.com\tTRUE\t/\tTRUE\t1900000000\tSAPISID\tsecret\n";
  thread_case *test = (thread_case *)opaque;
  rdlp_transport transport;
  rdlp_config config;
  rdlp_resolve_options options;
  rdlp_context *context = NULL;
  rdlp_selection *selection = NULL;
  rdlp_error error;
  memset(&transport, 0, sizeof(transport));
  memset(&config, 0, sizeof(config));
  memset(&options, 0, sizeof(options));
  memset(&error, 0, sizeof(error));
  transport.struct_size = sizeof(transport);
  transport.send = fixture_send;
  transport.context = &test->state;
  config.struct_size = sizeof(config);
  config.cache_directory = test->cache_directory;
  config.transport = &transport;
  config.clock_callback = fixture_clock;
  config.clock_context = &test->state;
  options.struct_size = sizeof(options);
  options.cookie_data = cookies;
  options.cookie_data_length = sizeof(cookies) - 1;
  error.struct_size = sizeof(error);
  test->result = rdlp_context_create(&config, &context, &error) ==
                         RDLP_STATUS_OK &&
                 rdlp_resolve_video(context, "YE7VzlLtp-4", &options,
                                    &selection, &error) == RDLP_STATUS_OK &&
                 selection != NULL && test->state.requests == 2 &&
                 test->state.saw_clock;
  rdlp_selection_destroy(selection);
  rdlp_context_destroy(context);
  return NULL;
}

static int independent_context_test(void) {
  char first_cache[] = "/tmp/retrodlp-context-a-XXXXXX";
  char second_cache[] = "/tmp/retrodlp-context-b-XXXXXX";
  fixture_gate gate;
  thread_case cases[2];
  pthread_t threads[2];
  int passed;
  if (mkdtemp(first_cache) == NULL || mkdtemp(second_cache) == NULL)
    return 0;
  memset(&gate, 0, sizeof(gate));
  memset(cases, 0, sizeof(cases));
  pthread_mutex_init(&gate.mutex, NULL);
  pthread_cond_init(&gate.condition, NULL);
  cases[0].cache_directory = first_cache;
  cases[1].cache_directory = second_cache;
  cases[0].state.gate = &gate;
  cases[1].state.gate = &gate;
  cases[0].state.now = 1700000000LL;
  cases[1].state.now = 1700000000LL;
  if (pthread_create(&threads[0], NULL, run_thread_case, &cases[0]) != 0) {
    passed = 0;
    goto finished;
  }
  if (pthread_create(&threads[1], NULL, run_thread_case, &cases[1]) != 0) {
    pthread_mutex_lock(&gate.mutex);
    gate.arrivals = 2;
    pthread_cond_broadcast(&gate.condition);
    pthread_mutex_unlock(&gate.mutex);
    pthread_join(threads[0], NULL);
    passed = 0;
    goto finished;
  }
  pthread_join(threads[0], NULL);
  pthread_join(threads[1], NULL);
  passed = cases[0].result && cases[1].result;
finished:
  pthread_cond_destroy(&gate.condition);
  pthread_mutex_destroy(&gate.mutex);
  remove_fixture_cache(first_cache);
  remove_fixture_cache(second_cache);
  return passed;
}

static int additive_transport_struct_test(void) {
  rdlp_transport transport;
  rdlp_config config;
  rdlp_context *context = NULL;
  rdlp_error error;
  rdlp_status status;
  memset(&transport, 0, sizeof(transport));
  memset(&config, 0, sizeof(config));
  memset(&error, 0, sizeof(error));
  transport.struct_size =
      offsetof(rdlp_transport, send) + sizeof(transport.send);
  transport.send = fixture_send;
  config.struct_size = sizeof(config);
  config.transport = &transport;
  error.struct_size = sizeof(error);
  status = rdlp_context_create(&config, &context, &error);
  rdlp_context_destroy(context);
  return status == RDLP_STATUS_OK;
}

static int transport_failure_test(void) {
  static const rdlp_status expected[] = {
      RDLP_STATUS_NETWORK, RDLP_STATUS_HTTP, RDLP_STATUS_INVALID_RESPONSE,
      RDLP_STATUS_INVALID_RESPONSE};
  fixture_state state;
  rdlp_transport transport;
  rdlp_config config;
  rdlp_context *context = NULL;
  rdlp_selection *selection;
  rdlp_error error;
  size_t index;
  memset(&state, 0, sizeof(state));
  memset(&transport, 0, sizeof(transport));
  memset(&config, 0, sizeof(config));
  transport.struct_size = sizeof(transport);
  transport.send = fixture_send;
  transport.context = &state;
  config.struct_size = sizeof(config);
  config.transport = &transport;
  memset(&error, 0, sizeof(error));
  error.struct_size = sizeof(error);
  if (rdlp_context_create(&config, &context, &error) != RDLP_STATUS_OK)
    return 0;
  for (index = 0; index < sizeof(expected) / sizeof(expected[0]); ++index) {
    state.failure_mode = (int)index + FIXTURE_NETWORK_FAILURE;
    selection = (rdlp_selection *)(size_t)1;
    if (rdlp_resolve_video(context, "YE7VzlLtp-4", NULL, &selection, &error) !=
            expected[index] ||
        selection != NULL || error.status != expected[index]) {
      rdlp_context_destroy(context);
      return 0;
    }
    if (state.failure_mode == FIXTURE_NETWORK_FAILURE &&
        error.transport_code != 77) {
      rdlp_context_destroy(context);
      return 0;
    }
  }
  rdlp_context_destroy(context);
  return 1;
}

static int cancellation_fixture_cancel(void *opaque) {
  return ((cancellation_fixture *)opaque)->cancelled;
}

static rdlp_status active_network_cancel_send(
    void *opaque, const rdlp_transport_request *request,
    rdlp_transport_response *response, rdlp_error *error) {
  cancellation_fixture *fixture = (cancellation_fixture *)opaque;
  (void)response;
  (void)error;
  ++fixture->requests;
  fixture->cancelled = 1;
  return request->cancel_callback != NULL &&
                 request->cancel_callback(request->cancel_context)
             ? RDLP_STATUS_CANCELLED
             : RDLP_STATUS_NETWORK;
}

static rdlp_status playlist_cancel_send(
    void *opaque, const rdlp_transport_request *request,
    rdlp_transport_response *response, rdlp_error *error) {
  static const char bootstrap[] =
      "<html><script>ytcfg.set({\"INNERTUBE_API_KEY\":\"fixture-key\","
      "\"INNERTUBE_CONTEXT_CLIENT_VERSION\":\"1.20260828.00.00\","
      "\"VISITOR_DATA\":\"fixture-visitor\"});var ytInitialData="
      "{\"metadata\":{\"playlistMetadataRenderer\":{"
      "\"title\":\"Cancellation fixture\"}},\"contents\":[{"
      "\"playlistVideoRenderer\":{\"videoId\":\"AAAAAAAAAAA\","
      "\"title\":{\"simpleText\":\"First video\"}}},{"
      "\"continuationItemRenderer\":{\"continuationEndpoint\":{"
      "\"continuationCommand\":{\"token\":\"page-two\"}}}}]};"
      "</script></html>";
  static const char browse[] =
      "{\"metadata\":{\"playlistMetadataRenderer\":{"
      "\"title\":\"Cancellation fixture\"}},\"contents\":[{"
      "\"playlistVideoRenderer\":{\"videoId\":\"AAAAAAAAAAA\","
      "\"title\":{\"simpleText\":\"First video\"}}},{"
      "\"continuationItemRenderer\":{\"continuationEndpoint\":{"
      "\"continuationCommand\":{\"token\":\"page-two\"}}}}]}";
  cancellation_fixture *fixture = (cancellation_fixture *)opaque;
  const char *data;
  (void)error;
  if (request->method == RDLP_HTTP_GET &&
      strstr(request->url, "/playlist?list=") != NULL)
    data = bootstrap;
  else if (request->method == RDLP_HTTP_POST &&
           strstr(request->url, "/youtubei/v1/browse") != NULL)
    data = browse;
  else
    return RDLP_STATUS_NETWORK;
  ++fixture->requests;
  response->http_status = 200;
  response->data = data;
  response->data_length = strlen(data);
  if (request->method == RDLP_HTTP_POST)
    fixture->cancelled = 1;
  return RDLP_STATUS_OK;
}

static int cancellation_boundary_test(void) {
  cancellation_fixture fixture;
  rdlp_transport transport;
  rdlp_config config;
  rdlp_context *context;
  rdlp_selection *selection;
  rdlp_playlist *playlist;
  rdlp_error error;

  memset(&fixture, 0, sizeof(fixture));
  memset(&transport, 0, sizeof(transport));
  memset(&config, 0, sizeof(config));
  memset(&error, 0, sizeof(error));
  transport.struct_size = sizeof(transport);
  transport.send = active_network_cancel_send;
  transport.context = &fixture;
  config.struct_size = sizeof(config);
  config.transport = &transport;
  config.cancel_callback = cancellation_fixture_cancel;
  config.callback_context = &fixture;
  error.struct_size = sizeof(error);
  context = NULL;
  selection = (rdlp_selection *)(size_t)1;
  if (rdlp_context_create(&config, &context, &error) != RDLP_STATUS_OK ||
      rdlp_resolve_video(context, "YE7VzlLtp-4", NULL, &selection, &error) !=
          RDLP_STATUS_CANCELLED ||
      selection != NULL || fixture.requests != 1) {
    fprintf(stderr,
            "FAIL: active network cancellation (status=%d requests=%d)\n",
            (int)error.status, fixture.requests);
    rdlp_selection_destroy(selection);
    rdlp_context_destroy(context);
    return 0;
  }
  rdlp_context_destroy(context);

  memset(&fixture, 0, sizeof(fixture));
  transport.send = playlist_cancel_send;
  context = NULL;
  playlist = (rdlp_playlist *)(size_t)1;
  if (rdlp_context_create(&config, &context, &error) != RDLP_STATUS_OK ||
      rdlp_list_playlist(context, "PL_cancel_fixture", NULL, &playlist,
                         &error) != RDLP_STATUS_CANCELLED ||
      playlist != NULL || fixture.requests != 2) {
    fprintf(stderr,
            "FAIL: playlist pagination cancellation (status=%d requests=%d)\n",
            (int)error.status, fixture.requests);
    rdlp_playlist_destroy(playlist);
    rdlp_context_destroy(context);
    return 0;
  }
  rdlp_context_destroy(context);
  return 1;
}

int main(void) {
  fixture_state state;
  rdlp_transport transport;
  rdlp_config config;
  rdlp_resolve_options options;
  rdlp_context *context;
  rdlp_selection *selection;
  rdlp_selection *cancelled_selection;
  rdlp_error error;
  char video_id[12];
  output_capture capture;
  int initial_ok;
  int quiet;
  char disabled_home[] = "/tmp/retrodlp-disabled-cache-XXXXXX";
  char disabled_cache_path[1024];
  const char *old_home_value;
  char *old_home;
  struct stat disabled_cache_info;
  memset(&state, 0, sizeof(state));
  memset(&transport, 0, sizeof(transport));
  memset(&config, 0, sizeof(config));
  memset(&error, 0, sizeof(error));
  memset(&options, 0, sizeof(options));
  old_home_value = getenv("HOME");
  old_home = old_home_value == NULL ? NULL : strdup(old_home_value);
  if (mkdtemp(disabled_home) == NULL ||
      setenv("HOME", disabled_home, 1) != 0) {
    free(old_home);
    fprintf(stderr, "FAIL: disabled-cache setup\n");
    return 1;
  }
  transport.struct_size = sizeof(transport);
  transport.send = fixture_send;
  transport.context = &state;
  config.struct_size = sizeof(config);
  config.transport = &transport;
  config.event_callback = fixture_event;
  config.cancel_callback = fixture_cancel;
  config.callback_context = &state;
  error.struct_size = sizeof(error);
  options.struct_size = sizeof(options);
  options.include_format_inventory = 1;
  context = NULL;
  selection = NULL;
  cancelled_selection = (rdlp_selection *)(size_t)1;
  if (!begin_output_capture(&capture)) {
    fprintf(stderr, "FAIL: output-capture setup\n");
    return 1;
  }
  initial_ok =
      rdlp_context_create(&config, &context, &error) == RDLP_STATUS_OK &&
      rdlp_parse_video_id("https://youtu.be/YE7VzlLtp-4", video_id, &error) ==
          RDLP_STATUS_OK &&
      strcmp(video_id, "YE7VzlLtp-4") == 0 &&
      rdlp_resolve_video(context, video_id, &options, &selection, &error) ==
          RDLP_STATUS_OK &&
      selection != NULL && state.requests == 2 && state.events != 0 &&
      strcmp(rdlp_selection_video_id(selection), video_id) == 0 &&
      strcmp(rdlp_selection_title(selection), "Public API fixture") == 0 &&
      rdlp_selection_media_count(selection) == 1 &&
      rdlp_selection_media_itag(selection, 0) == 18 &&
      rdlp_selection_media_height(selection, 0) == 360 &&
      rdlp_selection_media_header_count(selection, 0) == 1 &&
      rdlp_selection_format_count(selection) == 1 &&
      rdlp_selection_format_itag(selection, 0) == 18 &&
      rdlp_selection_format_is_supported(selection, 0) &&
      rdlp_format_expression_valid("136+140/22/18") &&
      !rdlp_format_expression_valid("best") &&
      rdlp_is_playlist_collection_input(
          "https://www.youtube.com/feed/playlists");
  quiet = end_output_capture(&capture);
  snprintf(disabled_cache_path, sizeof(disabled_cache_path),
           "%s/.retro-dlp", disabled_home);
  initial_ok = initial_ok &&
               stat(disabled_cache_path, &disabled_cache_info) != 0;
  if (old_home != NULL)
    setenv("HOME", old_home, 1);
  else
    unsetenv("HOME");
  free(old_home);
  rmdir(disabled_home);
  if (!initial_ok || !quiet) {
    fprintf(stderr, "FAIL: public facade consumer: %s\n", error.message);
    rdlp_selection_destroy(selection);
    rdlp_context_destroy(context);
    return 1;
  }
  state.cancelled = 1;
  state.reenter_cancel = 1;
  state.reentry_context = context;
  if (rdlp_resolve_video(context, video_id, NULL, &cancelled_selection,
                         &error) != RDLP_STATUS_CANCELLED ||
      cancelled_selection != NULL || error.status != RDLP_STATUS_CANCELLED ||
      state.reentry_status != RDLP_STATUS_BUSY) {
    fprintf(stderr, "FAIL: public cancellation contract\n");
    rdlp_selection_destroy(selection);
    rdlp_context_destroy(context);
    return 1;
  }
  rdlp_selection_destroy(selection);
  rdlp_context_destroy(context);
  if (!independent_context_test()) {
    fprintf(stderr,
            "FAIL: independent contexts, injected clock, or explicit cache\n");
    return 1;
  }
  if (!additive_transport_struct_test()) {
    fprintf(stderr, "FAIL: additive transport structure contract\n");
    return 1;
  }
  if (!transport_failure_test()) {
    fprintf(stderr,
            "FAIL: network, HTTP, malformed, or oversized response contract\n");
    return 1;
  }
  if (!cancellation_boundary_test()) {
    fprintf(stderr, "FAIL: active network or playlist cancellation boundary\n");
    return 1;
  }
  if (!asset_api_test()) {
    fprintf(stderr, "FAIL: public EJS asset API contract\n");
    return 1;
  }
  puts("PASS: external public API fixture consumer");
  return 0;
}
