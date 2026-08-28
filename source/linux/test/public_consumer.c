#include <stdio.h>
#include <string.h>

#include <retrodlp/retrodlp.h>

typedef struct {
  int requests;
  int events;
  int cancelled;
} fixture_state;

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
  (void)error;
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
  ++state->requests;
  response->http_status = 200;
  response->data = data;
  response->data_length = strlen(data);
  return RDLP_STATUS_OK;
}

static void fixture_event(const rdlp_event *event, void *opaque) {
  fixture_state *state = (fixture_state *)opaque;
  if (event != NULL && event->struct_size >= sizeof(*event))
    ++state->events;
}

static int fixture_cancel(void *opaque) {
  return ((fixture_state *)opaque)->cancelled;
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
  memset(&state, 0, sizeof(state));
  memset(&transport, 0, sizeof(transport));
  memset(&config, 0, sizeof(config));
  memset(&error, 0, sizeof(error));
  memset(&options, 0, sizeof(options));
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
  if (rdlp_context_create(&config, &context, &error) != RDLP_STATUS_OK ||
      rdlp_parse_video_id("https://youtu.be/YE7VzlLtp-4", video_id, &error) !=
          RDLP_STATUS_OK ||
      strcmp(video_id, "YE7VzlLtp-4") != 0 ||
      rdlp_resolve_video(context, video_id, &options, &selection, &error) !=
          RDLP_STATUS_OK ||
      selection == NULL || state.requests != 2 || state.events == 0 ||
      strcmp(rdlp_selection_video_id(selection), video_id) != 0 ||
      strcmp(rdlp_selection_title(selection), "Public API fixture") != 0 ||
      rdlp_selection_media_count(selection) != 1 ||
      rdlp_selection_media_itag(selection, 0) != 18 ||
      rdlp_selection_media_height(selection, 0) != 360 ||
      rdlp_selection_media_header_count(selection, 0) != 1 ||
      rdlp_selection_format_count(selection) != 1 ||
      rdlp_selection_format_itag(selection, 0) != 18 ||
      !rdlp_selection_format_is_supported(selection, 0)) {
    fprintf(stderr, "FAIL: public facade consumer: %s\n", error.message);
    rdlp_selection_destroy(selection);
    rdlp_context_destroy(context);
    return 1;
  }
  state.cancelled = 1;
  if (rdlp_resolve_video(context, video_id, NULL, &cancelled_selection,
                         &error) != RDLP_STATUS_CANCELLED ||
      cancelled_selection != NULL || error.status != RDLP_STATUS_CANCELLED) {
    fprintf(stderr, "FAIL: public cancellation contract\n");
    rdlp_selection_destroy(selection);
    rdlp_context_destroy(context);
    return 1;
  }
  rdlp_selection_destroy(selection);
  rdlp_context_destroy(context);
  puts("PASS: external public API fixture consumer");
  return 0;
}
