#ifndef RETRO_DLP_CLI_OPTIONS_H
#define RETRO_DLP_CLI_OPTIONS_H

#include <stddef.h>

typedef enum {
  CLI_ACTION_RUN = 0,
  CLI_ACTION_HELP,
  CLI_ACTION_VERSION,
  CLI_ACTION_ASSETS
} CLIAction;

typedef struct {
  CLIAction action;
  const char *input;
  const char *format_expression;
  const char *output;
  const char *cookie_file;
  const char *asset_command;
  int cookies_default;
  int list_formats;
  int dump_json;
  int simulate;
  int flat_playlist;
} CLIOptions;

int cli_options_parse(int argc, char **argv, CLIOptions *options,
                      char *error, size_t error_size);

#endif
