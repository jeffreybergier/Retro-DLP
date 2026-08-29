#include <stdio.h>
#include <string.h>

#include <retrodlp/retrodlp.h>

typedef struct {
  unsigned int request_count;
} example_transport;

static rdlp_status send_fixture(void *opaque,
                                const rdlp_transport_request *request,
                                rdlp_transport_response *response,
                                rdlp_error *error) {
  static const char bootstrap[] =
      "{\"INNERTUBE_CONTEXT_CLIENT_VERSION\":\"2.20260708.05.00\","
      "\"STS\":12345,\"jsUrl\":\"/s/player/example/base.js\"}";
  static const char player[] =
      "{\"playabilityStatus\":{\"status\":\"OK\"},"
      "\"videoDetails\":{\"videoId\":\"YE7VzlLtp-4\","
      "\"title\":\"Custom transport example\"},\"streamingData\":{"
      "\"formats\":[{\"itag\":18,"
      "\"url\":\"https://media.example/video.mp4\","
      "\"mimeType\":\"video/mp4; codecs=\\\"avc1.42001E, mp4a.40.2\\\"\","
      "\"width\":640,\"height\":360,\"contentLength\":\"1234\"}]}}";
  example_transport *transport = (example_transport *)opaque;
  const char *body = NULL;
  size_t body_length;
  (void)error;

  if (request->cancel_callback != NULL &&
      request->cancel_callback(request->cancel_context))
    return RDLP_STATUS_CANCELLED;
  if (strncmp(request->url, "https://", 8) != 0)
    return RDLP_STATUS_NETWORK;
  if (request->method == RDLP_HTTP_GET && strstr(request->url, "/watch") != NULL)
    body = bootstrap;
  else if (request->method == RDLP_HTTP_POST &&
           strstr(request->url, "/youtubei/v1/player") != NULL)
    body = player;
  else
    return RDLP_STATUS_NETWORK;

  body_length = strlen(body);
  if (request->maximum_response_bytes != 0 &&
      body_length > request->maximum_response_bytes)
    return RDLP_STATUS_INVALID_RESPONSE;
  ++transport->request_count;
  response->http_status = 200;
  response->transport_code = 0;
  response->data = body;
  response->data_length = body_length;
  return RDLP_STATUS_OK;
}

int main(void) {
  example_transport state = {0};
  rdlp_transport transport = {0};
  rdlp_config config = {0};
  rdlp_context *context = NULL;
  rdlp_selection *selection = NULL;
  rdlp_error error = {0};
  rdlp_status status;

  transport.struct_size = sizeof(transport);
  transport.send = send_fixture;
  transport.context = &state;
  config.struct_size = sizeof(config);
  config.transport = &transport;
  error.struct_size = sizeof(error);

  status = rdlp_context_create(&config, &context, &error);
  if (status == RDLP_STATUS_OK)
    status = rdlp_resolve_video(context, "YE7VzlLtp-4", NULL, &selection,
                                &error);
  if (status != RDLP_STATUS_OK) {
    fprintf(stderr, "%s: %s\n", rdlp_status_string(status), error.message);
    rdlp_context_destroy(context);
    return 1;
  }

  printf("%s: %s (%u requests)\n", rdlp_selection_title(selection),
         rdlp_selection_media_url(selection, 0), state.request_count);
  rdlp_selection_destroy(selection);
  rdlp_context_destroy(context);
  return 0;
}
