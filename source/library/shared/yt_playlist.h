#ifndef RETRO_DLP_YT_PLAYLIST_H
#define RETRO_DLP_YT_PLAYLIST_H

#include <stddef.h>
#include <stdint.h>

#include "yt_resolver.h"

typedef struct {
  char *video_id;
  char *title;
  size_t index;
  int has_duration;
  uint64_t duration;
  char *channel;
  char *channel_id;
  char **thumbnail_urls;
  size_t thumbnail_count;
  int has_view_count;
  uint64_t view_count;
  char *view_count_text;
  char *published_text;
  char *description_snippet;
} YTPlaylistEntry;

typedef struct {
  char *playlist_id;
  char *title;
  YTPlaylistEntry *entries;
  size_t entry_count;
} YTPlaylist;

typedef struct {
  char *playlist_id;
  char *title;
  size_t index;
} YTPlaylistReference;

typedef struct {
  YTPlaylistReference *playlists;
  size_t playlist_count;
} YTPlaylistCollection;

YTStatus yt_extract_playlist_id(const char *input, char *playlist_id,
                                size_t playlist_id_size);
YTStatus yt_list_playlist(YTHttpSession *session, const char *input,
                          const char *cookie_file, YTPlaylist *playlist,
                          YTProgressCallback progress, void *progress_opaque);
void yt_playlist_free(YTPlaylist *playlist);
int yt_is_playlist_collection_url(const char *input);
YTStatus yt_parse_playlist_collection_json(const char *json, size_t length,
                                           YTPlaylistCollection *collection);
YTStatus yt_list_account_playlists(
    YTHttpSession *session, const char *input, const char *cookie_file,
    YTPlaylistCollection *collection, YTProgressCallback progress,
    void *progress_opaque);
void yt_playlist_collection_free(YTPlaylistCollection *collection);

#endif
