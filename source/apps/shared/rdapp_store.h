#ifndef RDAPP_STORE_H
#define RDAPP_STORE_H
#include <stddef.h>
#include <stdint.h>

typedef struct rdapp_store rdapp_store;
typedef struct { const char *video_id; const char *title; int position; } rdapp_entry;
typedef int (*rdapp_row_callback)(void *, int, const char *const *, const char *const *);
typedef enum { RDAPP_PLAYLISTS, RDAPP_ENTRIES, RDAPP_JOBS, RDAPP_DOWNLOADS } rdapp_query;
/* Serialized by the owner. All strings passed to callbacks are borrowed. */
int rdapp_store_open(const char *path, rdapp_store **out);
void rdapp_store_close(rdapp_store *store);
const char *rdapp_store_error(rdapp_store *store);
int rdapp_store_list(rdapp_store *, rdapp_query, int64_t playlist, rdapp_row_callback, void *);
int rdapp_store_playlist(rdapp_store *, const char *id, const char *title, int64_t *key);
int rdapp_store_snapshot(rdapp_store *, const char *id, const char *title,
                         const rdapp_entry *, size_t count, int64_t *key);
int rdapp_store_enqueue(rdapp_store *, int64_t playlist, const char *video_id,
                        const char *format); /* NULL video means whole playlist */
int rdapp_store_claim(rdapp_store *, rdapp_row_callback, void *);
int rdapp_store_finish(rdapp_store *, int64_t job, const char *state,
                       const char *actual_format, const char *message);
int rdapp_store_retry(rdapp_store *, int64_t job);
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
