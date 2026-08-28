#ifndef RETRO_DLP_YT_PLAYLIST_H
#define RETRO_DLP_YT_PLAYLIST_H

#include <stddef.h>

#include "yt_resolver.h"

typedef struct {
  char *video_id;
  char *title;
  size_t index;
} YTPlaylistEntry;

typedef struct {
  char *playlist_id;
  char *title;
  YTPlaylistEntry *entries;
  size_t entry_count;
} YTPlaylist;

YTStatus yt_extract_playlist_id(const char *input, char *playlist_id,
                                size_t playlist_id_size);
YTStatus yt_list_playlist(YTHttpSession *session, const char *input,
                          const char *cookie_file, YTPlaylist *playlist,
                          YTProgressCallback progress, void *progress_opaque);
void yt_playlist_free(YTPlaylist *playlist);

#endif
