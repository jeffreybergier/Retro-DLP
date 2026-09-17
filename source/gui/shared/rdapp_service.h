#ifndef RDAPP_SERVICE_H
#define RDAPP_SERVICE_H
#include "rdapp_store.h"
#include <retrodlp/retrodlp.h>
#include <retrodlp/download.h>

typedef enum { RDAPP_SYNC, RDAPP_DISCOVER, RDAPP_DOWNLOAD, RDAPP_ADD_VIDEO } rdapp_operation;
typedef struct {
  int64_t id, playlist_id;
  const char *video_id, *format, *relative_path;
} rdapp_job;
typedef struct {
  uint64_t downloaded_bytes;
  int warning;
} rdapp_service_result;
typedef struct {
  const char *download_root, *cookie_file;
  rdlp_config resolver;
  rdlp_download_options download;
  /* Optional serialization hooks; never held during network or media work. */
  void (*lock)(void *);
  void (*unlock)(void *);
  void *lock_context;
  /* Optional app presentation hooks. Called on the worker, outside store locks. */
  void (*status_callback)(const char *message, void *context);
  /* Resolved metadata is ready for a UI reload. Uses status_context. */
  void (*change_callback)(void *context);
  void *status_context;
  rdapp_service_result *result;
} rdapp_service_config;
/* Synchronous, portable workflow. Call on a worker. All configuration is borrowed
   for the duration of this call. Download jobs must already have been claimed
   in SQLite. ADD_VIDEO is local-only and uses job->format to queue immediately;
   it requires neither a resolver context nor certificates. */
rdlp_error_code rdapp_service_run(rdapp_store *, const rdapp_service_config *,
                                 rdapp_operation, const char *input,
                                 const rdapp_job *, char *message, size_t capacity);
#endif
