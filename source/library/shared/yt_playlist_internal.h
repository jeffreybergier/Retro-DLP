#ifndef RETRO_DLP_YT_PLAYLIST_INTERNAL_H
#define RETRO_DLP_YT_PLAYLIST_INTERNAL_H

#include "cJSON.h"
#include "yt_playlist.h"

typedef struct {
  char *api_key;
  char *client_version;
  char *visitor_data;
  cJSON *document;
} YTPlaylistBootstrap;

YTStatus yt_playlist_parse_bootstrap_page(const char *page,
                                          YTPlaylistBootstrap *bootstrap);
void yt_playlist_bootstrap_free(YTPlaylistBootstrap *bootstrap);

YTStatus yt_playlist_collect_entries(cJSON *document, YTPlaylist *playlist,
                                     char **continuation);

#endif
