#ifndef RETRO_DLP_CLI_RENDER_H
#define RETRO_DLP_CLI_RENDER_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "retrodlp/retrodlp.h"

void cli_render_usage(FILE *stream);
int cli_render_selection_json(const rdlp_selection *selection,
                              const char *input);
void cli_render_formats(FILE *stream, const rdlp_selection *selection);
int cli_render_download_result(const char *path, int64_t bytes_written);
int cli_render_playlist_json(const rdlp_playlist *playlist);
void cli_render_playlist_table(const rdlp_playlist *playlist);
int cli_render_playlist_collection_json(
    const rdlp_playlist_collection *collection);
void cli_render_playlist_collection_table(
    const rdlp_playlist_collection *collection);
int retro_dlp_default_output_path(const char *title, const char *video_id,
                                  char *buffer, size_t buffer_size);

#endif
