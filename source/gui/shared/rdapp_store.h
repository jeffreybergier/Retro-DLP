#ifndef RDAPP_STORE_H
#define RDAPP_STORE_H
#include <stddef.h>
#include <stdint.h>

typedef struct rdapp_store rdapp_store;
#define RDAPP_ADHOC_PLAYLIST_ID "adhoc"
typedef struct {
  const char *video_id; const char *title; int position;
  /* Borrowed, ordered URLs only; snapshot copies them without fetching images. */
  const char *const *thumbnail_urls; size_t thumbnail_count;
  /* Optional metadata belongs to this occurrence, not the global video ID. */
  const char *channel, *channel_id, *view_count_text, *published_text, *description_snippet;
  uint64_t duration, view_count;
  int has_duration, has_view_count;
} rdapp_entry;
typedef int (*rdapp_row_callback)(void *, int, const char *const *, const char *const *);
typedef enum { RDAPP_PLAYLISTS, RDAPP_ENTRIES, RDAPP_JOBS, RDAPP_DOWNLOADS,
  RDAPP_ADDED_PLAYLISTS, RDAPP_ACCOUNT_PLAYLISTS, RDAPP_QUEUE, RDAPP_PENDING,
  RDAPP_BLOCKING_JOBS, RDAPP_VIDEO_JOBS, RDAPP_JOB, RDAPP_PLAYLIST,
  RDAPP_MISSING, RDAPP_DOWNLOAD_CANDIDATES, RDAPP_PLAYLIST_INPUT,
  RDAPP_ADDED_IDS, RDAPP_ACCOUNT_IDS, RDAPP_VIDEO_ENTRIES } rdapp_query;
/* Serialized by the owner. All strings passed to callbacks are borrowed. */
int rdapp_store_open(const char *path, rdapp_store **out);
/* UI reader: no migration or recovery; WAL snapshots do not block the worker. */
int rdapp_store_open_reader(const char *path, rdapp_store **out);
void rdapp_store_close(rdapp_store *store);
const char *rdapp_store_error(rdapp_store *store);
int rdapp_store_list(rdapp_store *, rdapp_query, int64_t playlist, rdapp_row_callback, void *);
/* Count and page use identical predicates. limit=-1 is reserved for bulk work.
   video/format narrow VIDEO_JOBS; key identifies a playlist, or a JOB/PLAYLIST. */
int rdapp_store_count(rdapp_store *, rdapp_query, int64_t key, const char *video,
                      const char *format, int64_t *count);
int rdapp_store_page(rdapp_store *, rdapp_query, int64_t key, const char *video,
                     const char *format, int64_t offset, int64_t limit, rdapp_row_callback, void *);
/* Indexed seek for sequential scrolling; playlists continue to use offsets. */
int rdapp_store_after(rdapp_store *, rdapp_query, int64_t key, const char *video,
                      const char *format, int64_t identity, rdapp_row_callback, void *);
/* Position in ENTRIES (by position), DOWNLOADS or QUEUE (by job ID), -1 if absent. */
int rdapp_store_index(rdapp_store *, rdapp_query, int64_t playlist, int64_t identity, int64_t *index);
int rdapp_store_playlist(rdapp_store *, const char *id, const char *title, int64_t *key);
int rdapp_store_discovered_playlist(rdapp_store *, const char *id, const char *title);
int rdapp_store_snapshot(rdapp_store *, const char *id, const char *title,
                         const rdapp_entry *, size_t count, int64_t *key);
/* Adds or refreshes one locally-added video without replacing other Ad-Hoc rows. */
int rdapp_store_add_adhoc(rdapp_store *, const char *video_id, const char *title,
                          int64_t *key);
/* Atomically adds the entry and queues its quality, retrying stopped/removed
   jobs while preserving queued, running and completed downloads. A NULL title
   preserves known titles or uses the video ID until download resolution. */
int rdapp_store_add_adhoc_download(rdapp_store *, const char *video_id,
                                  const char *title, const char *format, int64_t *key);
/* Seconds are shared by video ID across playlists and downloaded qualities. */
int rdapp_store_playback_seconds(rdapp_store *, const char *video_id, double *seconds);
int rdapp_store_save_playback_seconds(rdapp_store *, const char *video_id, double seconds);
int rdapp_store_enqueue(rdapp_store *, int64_t playlist, const char *video_id,
                        const char *format); /* NULL video means whole playlist */
int rdapp_store_claim(rdapp_store *, rdapp_row_callback, void *);
/* Finalizes an Ad-Hoc title/path before transfer; other playlists keep theirs.
   The job must be running. Copies the persisted relative path into path. */
int rdapp_store_resolve_job(rdapp_store *, int64_t job, const char *title,
                            char *path, size_t capacity);
int rdapp_store_finish(rdapp_store *, int64_t job, const char *state,
                       const char *actual_format, const char *message);
int rdapp_store_retry(rdapp_store *, int64_t job);
int rdapp_store_reconcile_job(rdapp_store *, int64_t job, const char *root);
int rdapp_store_cancel(rdapp_store *, int64_t job);
int rdapp_store_forget_file(rdapp_store *, int64_t job);
int rdapp_store_remove_playlist(rdapp_store *, int64_t playlist, const char *root);
/* Atomic M3U8 export, rooted in an app-owned directory. Missing files omitted. */
int rdapp_store_reconcile(rdapp_store *, const char *root);
int rdapp_store_remove_file(rdapp_store *, int64_t job, const char *root);
int rdapp_store_export(rdapp_store *, int64_t playlist, const char *root);
int rdapp_make_directory(const char *path);
void rdapp_filename(const char *text, char *out, size_t capacity);
#endif
