#ifndef RETRODLP_RETRODLP_H
#define RETRODLP_RETRODLP_H

#include <stddef.h>
#include <stdint.h>

#include "version.h"

#if defined(_WIN32) && defined(RDLP_SHARED)
#if defined(RDLP_BUILDING_LIBRARY)
#define RDLP_API __declspec(dllexport)
#else
#define RDLP_API __declspec(dllimport)
#endif
#elif defined(__GNUC__) && defined(RDLP_SHARED)
#define RDLP_API __attribute__((visibility("default")))
#else
#define RDLP_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rdlp_context rdlp_context;
typedef struct rdlp_selection rdlp_selection;
typedef struct rdlp_playlist rdlp_playlist;

typedef enum {
  RDLP_STATUS_OK = 0,
  RDLP_STATUS_INVALID_ARGUMENT,
  RDLP_STATUS_OUT_OF_MEMORY,
  RDLP_STATUS_NETWORK,
  RDLP_STATUS_CERTIFICATE_BUNDLE,
  RDLP_STATUS_HTTP,
  RDLP_STATUS_INVALID_RESPONSE,
  RDLP_STATUS_UNAVAILABLE,
  RDLP_STATUS_FORMAT_UNAVAILABLE,
  RDLP_STATUS_EJS_ASSETS_MISSING,
  RDLP_STATUS_JS_CHALLENGE,
  RDLP_STATUS_AUTHENTICATION_REQUIRED,
  RDLP_STATUS_COOKIE,
  RDLP_STATUS_CANCELLED,
  RDLP_STATUS_BUSY,
  RDLP_STATUS_STORAGE,
  RDLP_STATUS_INTERNAL
} rdlp_status;

typedef struct rdlp_error {
  size_t struct_size;
  rdlp_status status;
  long http_status;
  int transport_code;
  int retryable;
  char message[256];
} rdlp_error;

typedef enum {
  RDLP_EVENT_LOADING_CONFIGURATION = 0,
  RDLP_EVENT_FETCHING_BOOTSTRAP,
  RDLP_EVENT_REQUESTING_METADATA,
  RDLP_EVENT_LOADING_PLAYER_JAVASCRIPT,
  RDLP_EVENT_SOLVING_CHALLENGES,
  RDLP_EVENT_SELECTING_FORMATS,
  RDLP_EVENT_ENUMERATING_PLAYLIST,
  RDLP_EVENT_OTHER
} rdlp_event_type;

typedef struct {
  size_t struct_size;
  rdlp_event_type type;
  uint64_t completed_bytes;
  uint64_t expected_bytes;
} rdlp_event;

typedef void (*rdlp_event_callback)(const rdlp_event *event, void *context);
typedef int (*rdlp_cancel_callback)(void *context);

typedef struct {
  const char *name;
  const char *value;
} rdlp_http_header;

typedef enum {
  RDLP_HTTP_GET = 0,
  RDLP_HTTP_POST,
  RDLP_HTTP_HEAD
} rdlp_http_method;

typedef struct {
  size_t struct_size;
  rdlp_http_method method;
  const char *url;
  const rdlp_http_header *headers;
  size_t header_count;
  const void *body;
  size_t body_length;
  size_t maximum_response_bytes;
  unsigned long timeout_milliseconds;
  rdlp_cancel_callback cancel_callback;
  void *cancel_context;
} rdlp_transport_request;

typedef struct {
  size_t struct_size;
  long http_status;
  int transport_code;
  const void *data;
  size_t data_length;
} rdlp_transport_response;

typedef rdlp_status (*rdlp_transport_send_callback)(
    void *context, const rdlp_transport_request *request,
    rdlp_transport_response *response, rdlp_error *error);

typedef struct rdlp_transport {
  size_t struct_size;
  rdlp_transport_send_callback send;
  void *context;
} rdlp_transport;

typedef struct {
  size_t struct_size;
  const char *cache_directory;
  const char *ca_bundle_path;
  const char *ejs_asset_directory;
  unsigned long network_timeout_milliseconds;
  size_t ejs_memory_limit_bytes;
  size_t ejs_stack_limit_bytes;
  rdlp_event_callback event_callback;
  rdlp_cancel_callback cancel_callback;
  void *callback_context;
  const rdlp_transport *transport;
} rdlp_config;

typedef struct {
  size_t struct_size;
  const char *format_expression;
  const char *cookie_file;
  const void *cookie_data;
  size_t cookie_data_length;
  int include_format_inventory;
  int maximum_height;
  int prefer_adaptive;
} rdlp_resolve_options;

typedef struct {
  size_t struct_size;
  const char *cookie_file;
  const void *cookie_data;
  size_t cookie_data_length;
} rdlp_playlist_options;

RDLP_API const char *rdlp_version_string(void);
RDLP_API const char *rdlp_status_string(rdlp_status status);
RDLP_API rdlp_status rdlp_context_create(const rdlp_config *config,
                                         rdlp_context **context,
                                         rdlp_error *error);
RDLP_API void rdlp_context_destroy(rdlp_context *context);

RDLP_API rdlp_status rdlp_parse_video_id(const char *input, char video_id[12],
                                         rdlp_error *error);
RDLP_API rdlp_status rdlp_parse_playlist_id(const char *input,
                                            char *playlist_id,
                                            size_t playlist_id_size,
                                            rdlp_error *error);
RDLP_API rdlp_status rdlp_resolve_video(rdlp_context *context,
                                        const char *input,
                                        const rdlp_resolve_options *options,
                                        rdlp_selection **selection,
                                        rdlp_error *error);
RDLP_API rdlp_status rdlp_list_playlist(rdlp_context *context,
                                        const char *input,
                                        const rdlp_playlist_options *options,
                                        rdlp_playlist **playlist,
                                        rdlp_error *error);

RDLP_API void rdlp_selection_destroy(rdlp_selection *selection);
RDLP_API const char *rdlp_selection_video_id(const rdlp_selection *selection);
RDLP_API const char *rdlp_selection_title(const rdlp_selection *selection);
RDLP_API const char *rdlp_selection_format_id(const rdlp_selection *selection);
RDLP_API int rdlp_selection_is_adaptive(const rdlp_selection *selection);
RDLP_API size_t rdlp_selection_media_count(const rdlp_selection *selection);
RDLP_API const char *rdlp_selection_media_url(const rdlp_selection *selection,
                                              size_t media_index);
RDLP_API const char *rdlp_selection_media_mime_type(
    const rdlp_selection *selection, size_t media_index);
RDLP_API int rdlp_selection_media_itag(const rdlp_selection *selection,
                                       size_t media_index);
RDLP_API int rdlp_selection_media_width(const rdlp_selection *selection,
                                        size_t media_index);
RDLP_API int rdlp_selection_media_height(const rdlp_selection *selection,
                                         size_t media_index);
RDLP_API int64_t rdlp_selection_media_content_length(
    const rdlp_selection *selection, size_t media_index);
RDLP_API size_t rdlp_selection_media_header_count(
    const rdlp_selection *selection, size_t media_index);
RDLP_API const rdlp_http_header *rdlp_selection_media_header(
    const rdlp_selection *selection, size_t media_index, size_t header_index);
RDLP_API size_t rdlp_selection_format_count(const rdlp_selection *selection);
RDLP_API int rdlp_selection_format_itag(const rdlp_selection *selection,
                                        size_t format_index);
RDLP_API const char *rdlp_selection_format_mime_type(
    const rdlp_selection *selection, size_t format_index);
RDLP_API int rdlp_selection_format_width(const rdlp_selection *selection,
                                         size_t format_index);
RDLP_API int rdlp_selection_format_height(const rdlp_selection *selection,
                                          size_t format_index);
RDLP_API int rdlp_selection_format_has_video(const rdlp_selection *selection,
                                             size_t format_index);
RDLP_API int rdlp_selection_format_has_audio(const rdlp_selection *selection,
                                             size_t format_index);
RDLP_API int rdlp_selection_format_is_supported(
    const rdlp_selection *selection, size_t format_index);

RDLP_API void rdlp_playlist_destroy(rdlp_playlist *playlist);
RDLP_API const char *rdlp_playlist_id(const rdlp_playlist *playlist);
RDLP_API const char *rdlp_playlist_title(const rdlp_playlist *playlist);
RDLP_API size_t rdlp_playlist_entry_count(const rdlp_playlist *playlist);
RDLP_API const char *rdlp_playlist_entry_video_id(
    const rdlp_playlist *playlist, size_t entry_index);
RDLP_API const char *rdlp_playlist_entry_title(const rdlp_playlist *playlist,
                                               size_t entry_index);
RDLP_API size_t rdlp_playlist_entry_index(const rdlp_playlist *playlist,
                                          size_t entry_index);

#ifdef __cplusplus
}
#endif

#endif
