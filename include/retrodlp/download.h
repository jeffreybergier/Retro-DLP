#ifndef RETRODLP_DOWNLOAD_H
#define RETRODLP_DOWNLOAD_H

#include <stddef.h>
#include <stdint.h>

#include "retrodlp.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  RDLP_DOWNLOAD_EVENT_DOWNLOADING_AUDIO = 0,
  RDLP_DOWNLOAD_EVENT_DOWNLOADING_VIDEO = 1,
  RDLP_DOWNLOAD_EVENT_DOWNLOADING_MEDIA = 2,
  RDLP_DOWNLOAD_EVENT_MUXING = 3,
  RDLP_DOWNLOAD_EVENT_CLEANING_UP = 4
} rdlp_download_event_type;

typedef struct {
  size_t struct_size;
  rdlp_download_event_type type;
  const char *path;
  uint64_t completed_bytes;
  uint64_t expected_bytes;
} rdlp_download_event;

typedef void (*rdlp_download_event_callback)(
    const rdlp_download_event *event, void *context);

typedef struct {
  size_t struct_size;
  const char *ca_bundle_path;
  unsigned long network_timeout_milliseconds;
  rdlp_download_event_callback event_callback;
  rdlp_cancel_callback cancel_callback;
  void *callback_context;
} rdlp_download_options;

typedef struct {
  size_t struct_size;
  int64_t bytes_written;
  int source_tracks_retained;
} rdlp_download_result;

RDLP_API rdlp_status rdlp_download_selection(
    const rdlp_selection *selection, const char *destination,
    const rdlp_download_options *options, rdlp_download_result *result,
    rdlp_error *error);

#ifdef __cplusplus
}
#endif

#endif
