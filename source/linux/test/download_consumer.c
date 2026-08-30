#define _XOPEN_SOURCE 700

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <retrodlp/download.h>

typedef struct {
  const char *base_url;
  char player[4096];
} resolver_fixture;

typedef struct {
  int cancel_on_progress;
  int cancel_on_mux;
  int block_mux_destination;
  int cancelled;
  const char *destination;
} download_fixture;

static rdlp_error_code fixture_send(void *opaque,
                                const rdlp_transport_request *request,
                                rdlp_transport_response *response,
                                rdlp_error *error) {
  static const char bootstrap[] =
      "{\"INNERTUBE_CONTEXT_CLIENT_VERSION\":\"2.20260708.05.00\","
      "\"STS\":12345,\"jsUrl\":\"/s/player/fixture/base.js\"}";
  resolver_fixture *fixture = (resolver_fixture *)opaque;
  const char *data;
  (void)error;
  if (request->method == RDLP_HTTP_GET &&
      strstr(request->url, "m.youtube.com/watch") != NULL)
    data = bootstrap;
  else if (request->method == RDLP_HTTP_POST &&
           strstr(request->url, "/youtubei/v1/player") != NULL)
    data = fixture->player;
  else
    return RDLP_ERROR_TRANSPORT_REQUEST_FAILED;
  response->http_status = 200;
  response->data = data;
  response->data_length = strlen(data);
  return RDLP_OK;
}

static rdlp_selection *make_selection(resolver_fixture *fixture,
                                      const char *path, int adaptive) {
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
  if (adaptive) {
    snprintf(fixture->player, sizeof(fixture->player),
             "{\"playabilityStatus\":{\"status\":\"OK\"},"
             "\"videoDetails\":{\"videoId\":\"YE7VzlLtp-4\","
             "\"title\":\"download fixture\"},\"streamingData\":{"
             "\"adaptiveFormats\":[{\"itag\":137,\"url\":\"%s/video\","
             "\"mimeType\":\"video/mp4; codecs=\\\"avc1.640028\\\"\","
             "\"width\":1920,\"height\":1080,\"contentLength\":\"32\"},"
             "{\"itag\":140,\"url\":\"%s/audio\","
             "\"mimeType\":\"audio/mp4; codecs=\\\"mp4a.40.2\\\"\","
             "\"audioChannels\":2,\"contentLength\":\"32\"}]}}",
             fixture->base_url, fixture->base_url);
  } else {
    snprintf(fixture->player, sizeof(fixture->player),
             "{\"playabilityStatus\":{\"status\":\"OK\"},"
             "\"videoDetails\":{\"videoId\":\"YE7VzlLtp-4\","
             "\"title\":\"download fixture\"},\"streamingData\":{"
             "\"formats\":[{\"itag\":18,\"url\":\"%s/%s\","
             "\"mimeType\":\"video/mp4; codecs=\\\"avc1.42001E, mp4a.40.2\\\"\","
             "\"width\":640,\"height\":360,\"contentLength\":\"32\"}]}}",
             fixture->base_url, path);
  }
  transport.struct_size = sizeof(transport);
  transport.send = fixture_send;
  transport.context = fixture;
  config.struct_size = sizeof(config);
  config.transport = &transport;
  options.struct_size = sizeof(options);
  options.format_expression = adaptive ? "137+140" : "18";
  error.struct_size = sizeof(error);
  if (rdlp_context_create(&config, &context, &error) != RDLP_OK ||
      rdlp_resolve_video(context, "YE7VzlLtp-4", &options, &selection,
                         &error) != RDLP_OK) {
    fprintf(stderr, "FAIL: download selection fixture: %s\n", error.message);
    rdlp_selection_destroy(selection);
    selection = NULL;
  }
  rdlp_context_destroy(context);
  return selection;
}

static int cancel_download(void *opaque) {
  return ((download_fixture *)opaque)->cancelled;
}

static void download_event(const rdlp_download_event *event, void *opaque) {
  download_fixture *fixture = (download_fixture *)opaque;
  FILE *file;
  if ((fixture->cancel_on_progress && event->completed_bytes != 0) ||
      (fixture->cancel_on_mux && event->type == RDLP_DOWNLOAD_EVENT_MUXING))
    fixture->cancelled = 1;
  if (fixture->block_mux_destination &&
      event->type == RDLP_DOWNLOAD_EVENT_MUXING) {
    file = fopen(fixture->destination, "wb");
    if (file != NULL) {
      fwrite("blocked", 1, 7, file);
      fclose(file);
    }
  }
}

static int exists(const char *path) {
  struct stat information;
  return lstat(path, &information) == 0;
}

static int write_text(const char *path, const char *value) {
  FILE *file = fopen(path, "wb");
  size_t length = strlen(value);
  int ok = file != NULL && fwrite(value, 1, length, file) == length;
  if (file != NULL && fclose(file) != 0)
    ok = 0;
  return ok;
}

static int file_equals(const char *path, const char *value) {
  char buffer[32];
  size_t expected = strlen(value);
  FILE *file = fopen(path, "rb");
  size_t count = file == NULL ? 0 : fread(buffer, 1, sizeof(buffer), file);
  if (file != NULL)
    fclose(file);
  return count == expected && memcmp(buffer, value, expected) == 0;
}

static rdlp_error_code run_download(const rdlp_selection *selection,
                                const char *destination, const char *ca_path,
                                unsigned long timeout,
                                download_fixture *fixture,
                                rdlp_download_result *result,
                                rdlp_error *error) {
  rdlp_download_options options;
  memset(&options, 0, sizeof(options));
  memset(result, 0, sizeof(*result));
  memset(error, 0, sizeof(*error));
  options.struct_size = sizeof(options);
  options.ca_bundle_path = ca_path;
  options.network_timeout_milliseconds = timeout;
  options.event_callback = download_event;
  options.cancel_callback = cancel_download;
  options.callback_context = fixture;
  result->struct_size = sizeof(*result);
  error->struct_size = sizeof(*error);
  return rdlp_download_selection(selection, destination, &options, result,
                                 error);
}

int main(void) {
  const char *base_url = getenv("RETRO_DLP_TEST_DOWNLOAD_URL");
  const char *ca_path = getenv("RETRO_DLP_TEST_DOWNLOAD_CA");
  char temporary[] = "/tmp/retro-dlp-download-test.XXXXXX";
  char destination[1024];
  char partial[1024];
  char audio[1024];
  char video[1024];
  resolver_fixture resolver;
  download_fixture fixture;
  rdlp_selection *selection;
  rdlp_download_result result;
  rdlp_error error;
  rdlp_error_code status;
  int failures = 0;

  memset(&result, 0, sizeof(result));
  memset(&error, 0, sizeof(error));
  result.struct_size = sizeof(result);
  error.struct_size = sizeof(error);
  if (rdlp_download_selection(NULL, "unused.mp4", NULL, &result, &error) !=
          RDLP_ERROR_INVALID_ARGUMENT ||
      error.code != RDLP_ERROR_INVALID_ARGUMENT) {
    fprintf(stderr, "FAIL: optional download public API contract\n");
    return 1;
  }
  if (base_url == NULL || ca_path == NULL || mkdtemp(temporary) == NULL) {
    fprintf(stderr, "FAIL: download fixture environment\n");
    return 1;
  }
  memset(&resolver, 0, sizeof(resolver));
  resolver.base_url = base_url;
  snprintf(destination, sizeof(destination), "%s/result.mp4", temporary);
  snprintf(partial, sizeof(partial), "%s/result.mp4.part", temporary);
  snprintf(audio, sizeof(audio), "%s/result.mp4.audio.m4a", temporary);
  snprintf(video, sizeof(video), "%s/result.mp4.video.mp4", temporary);

  selection = make_selection(&resolver, "valid", 0);
  memset(&fixture, 0, sizeof(fixture));
  if (selection == NULL || !write_text(destination, "original") ||
      run_download(selection, destination, ca_path, 5000, &fixture, &result,
                   &error) != RDLP_ERROR_DESTINATION_EXISTS ||
      !file_equals(destination, "original")) {
    fprintf(stderr, "FAIL: existing destination preservation\n");
    ++failures;
  }
  unlink(destination);
  if (!write_text(partial, "original") ||
      run_download(selection, destination, ca_path, 5000, &fixture, &result,
                   &error) != RDLP_ERROR_DESTINATION_EXISTS ||
      !file_equals(partial, "original")) {
    fprintf(stderr, "FAIL: existing partial-file preservation\n");
    ++failures;
  }
  unlink(partial);
  status = run_download(selection, destination, ca_path, 5000, &fixture,
                        &result, &error);
  if (status != RDLP_OK || !exists(destination) || exists(partial)) {
    fprintf(stderr, "FAIL: progressive download success and cleanup\n");
    ++failures;
  }
  unlink(destination);
  rdlp_selection_destroy(selection);

  selection = make_selection(&resolver, "invalid", 0);
  status = run_download(selection, destination, ca_path, 5000, &fixture,
                        &result, &error);
  if (status != RDLP_ERROR_MEDIA_NOT_MP4 || exists(destination) ||
      exists(partial)) {
    fprintf(stderr, "FAIL: malformed download cleanup\n");
    ++failures;
  }
  rdlp_selection_destroy(selection);

  selection = make_selection(&resolver, "status", 0);
  status = run_download(selection, destination, ca_path, 5000, &fixture,
                        &result, &error);
  if (status != RDLP_ERROR_HTTP_STATUS || error.http_status != 503 ||
      exists(partial)) {
    fprintf(stderr, "FAIL: media HTTP error classification\n");
    ++failures;
  }
  rdlp_selection_destroy(selection);

  selection = make_selection(&resolver, "slow", 0);
  memset(&fixture, 0, sizeof(fixture));
  fixture.cancel_on_progress = 1;
  status = run_download(selection, destination, ca_path, 5000, &fixture,
                        &result, &error);
  if (status != RDLP_ERROR_CANCELLED || exists(destination) ||
      exists(partial)) {
    fprintf(stderr, "FAIL: active download cancellation and cleanup\n");
    ++failures;
  }
  memset(&fixture, 0, sizeof(fixture));
  status = run_download(selection, destination, ca_path, 10, &fixture, &result,
                        &error);
  if (status != RDLP_ERROR_TRANSPORT_TIMEOUT || exists(partial)) {
    fprintf(stderr, "FAIL: media timeout classification and cleanup\n");
    ++failures;
  }
  rdlp_selection_destroy(selection);

  selection = make_selection(&resolver, NULL, 1);
  memset(&fixture, 0, sizeof(fixture));
  fixture.block_mux_destination = 1;
  fixture.destination = destination;
  status = run_download(selection, destination, ca_path, 5000, &fixture,
                        &result, &error);
  if (status != RDLP_ERROR_DESTINATION_EXISTS ||
      !result.source_tracks_retained ||
      !exists(audio) || !exists(video) ||
      !file_equals(destination, "blocked")) {
    fprintf(stderr, "FAIL: mux failure source-track retention\n");
    ++failures;
  }
  unlink(audio);
  unlink(video);
  unlink(destination);
  memset(&fixture, 0, sizeof(fixture));
  fixture.cancel_on_mux = 1;
  status = run_download(selection, destination, ca_path, 5000, &fixture,
                        &result, &error);
  if (status != RDLP_ERROR_CANCELLED || !result.source_tracks_retained ||
      !exists(audio) || !exists(video) || exists(destination)) {
    fprintf(stderr, "FAIL: mux-boundary cancellation and source retention\n");
    ++failures;
  }
  unlink(audio);
  unlink(video);
  rdlp_selection_destroy(selection);
  rmdir(temporary);

  if (failures != 0)
    return 1;
  puts("PASS: download failures, cleanup, cancellation, and mux retention");
  return 0;
}
