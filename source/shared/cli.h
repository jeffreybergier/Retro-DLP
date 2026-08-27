#ifndef RETRO_DLP_CLI_H
#define RETRO_DLP_CLI_H

#include <stddef.h>

int retro_dlp_run(int argc, char **argv);
int retro_dlp_default_output_path(const char *title, const char *video_id,
                                  char *buffer, size_t buffer_size);

#endif
