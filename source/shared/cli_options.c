#include "cli_options.h"

#include <stdio.h>
#include <string.h>

#include "retrodlp/retrodlp.h"

#define PRESET_LOW_FORMAT "18"
#define PRESET_MED_FORMAT "135+140/134+140"
#define PRESET_HIGH_FORMAT "137+599/137+140/136+599/136+140"

static const char *preset_format_expression(const char *preset) {
  if (strcmp(preset, "low") == 0)
    return PRESET_LOW_FORMAT;
  if (strcmp(preset, "med") == 0)
    return PRESET_MED_FORMAT;
  if (strcmp(preset, "high") == 0)
    return PRESET_HIGH_FORMAT;
  return NULL;
}

static int fail(char *error, size_t error_size, const char *message,
                const char *value) {
  if (error != NULL && error_size != 0) {
    if (value == NULL)
      snprintf(error, error_size, "%s", message);
    else
      snprintf(error, error_size, message, value);
  }
  return 0;
}

int cli_options_parse(int argc, char **argv, CLIOptions *options,
                      char *error, size_t error_size) {
  const char *preset_alias = NULL;
  int cookies_requested = 0;
  int index;
  if (options == NULL || argc < 1 || argv == NULL)
    return fail(error, error_size, "unsupported arguments", NULL);
  memset(options, 0, sizeof(*options));
  if (error != NULL && error_size != 0)
    error[0] = '\0';
  if (argc == 1) {
    options->action = CLI_ACTION_HELP;
    return 1;
  }
  if (argc == 2 &&
      (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0)) {
    options->action = CLI_ACTION_HELP;
    return 1;
  }
  if (argc == 2 &&
      (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-V") == 0)) {
    options->action = CLI_ACTION_VERSION;
    return 1;
  }
  if (argc == 3 && strcmp(argv[1], "assets") == 0) {
    options->action = CLI_ACTION_ASSETS;
    options->asset_command = argv[2];
    return 1;
  }
  options->action = CLI_ACTION_RUN;
  for (index = 1; index < argc; ++index) {
    if (strcmp(argv[index], "--cookies") == 0) {
      if (cookies_requested || options->cookies_default || index + 1 >= argc ||
          argv[index + 1][0] == '\0')
        break;
      cookies_requested = 1;
      options->cookie_file = argv[++index];
    } else if (strcmp(argv[index], "--cookies-default") == 0) {
      if (cookies_requested || options->cookies_default)
        break;
      options->cookies_default = 1;
    } else if (strcmp(argv[index], "--format") == 0 ||
               strcmp(argv[index], "-f") == 0) {
      if (preset_alias != NULL)
        return fail(error, error_size,
                    "--format and --preset-alias cannot be combined", NULL);
      if (options->format_expression != NULL || index + 1 >= argc)
        break;
      if (!rdlp_format_expression_valid(argv[index + 1]))
        return fail(error, error_size,
                    "unsupported format expression \"%s\"\n"
                    "retro-dlp: supported forms are ITAG, "
                    "VIDEO_ITAG+AUDIO_ITAG, and alternatives separated by /",
                    argv[index + 1]);
      options->format_expression = argv[++index];
    } else if (strcmp(argv[index], "--preset-alias") == 0 ||
               strcmp(argv[index], "-t") == 0) {
      const char *expanded;
      if (preset_alias != NULL || index + 1 >= argc)
        break;
      if (options->format_expression != NULL)
        return fail(error, error_size,
                    "--format and --preset-alias cannot be combined", NULL);
      preset_alias = argv[++index];
      expanded = preset_format_expression(preset_alias);
      if (expanded == NULL)
        return fail(error, error_size,
                    "unknown preset alias \"%s\"\n"
                    "retro-dlp: available presets are high, med, low",
                    preset_alias);
      options->format_expression = expanded;
    } else if (strcmp(argv[index], "--list-formats") == 0 ||
               strcmp(argv[index], "-F") == 0) {
      if (options->list_formats)
        break;
      options->list_formats = 1;
    } else if (strcmp(argv[index], "--flat-playlist") == 0) {
      if (options->flat_playlist)
        break;
      options->flat_playlist = 1;
    } else if (strcmp(argv[index], "--output") == 0 ||
               strcmp(argv[index], "-o") == 0) {
      if (options->output != NULL || index + 1 >= argc ||
          argv[index + 1][0] == '\0')
        break;
      options->output = argv[++index];
    } else if (strcmp(argv[index], "--simulate") == 0 ||
               strcmp(argv[index], "-s") == 0) {
      if (options->simulate)
        break;
      options->simulate = 1;
    } else if (strcmp(argv[index], "--dump-json") == 0 ||
               strcmp(argv[index], "-j") == 0) {
      if (options->dump_json)
        break;
      options->dump_json = 1;
      options->simulate = 1;
    } else if (options->input == NULL) {
      char video_id[12];
      rdlp_error parse_error;
      memset(&parse_error, 0, sizeof(parse_error));
      parse_error.struct_size = sizeof(parse_error);
      if (argv[index][0] == '-' &&
          rdlp_parse_video_id(argv[index], video_id, &parse_error) !=
              RDLP_STATUS_OK)
        break;
      options->input = argv[index];
    } else {
      break;
    }
  }
  if (index == argc && options->input != NULL &&
      (!options->flat_playlist ||
       (!options->list_formats && options->format_expression == NULL &&
        options->output == NULL)) &&
      (options->flat_playlist ||
       (!(options->list_formats && options->format_expression != NULL) &&
        !(options->list_formats && options->dump_json))))
    return 1;
  return fail(error, error_size, "unsupported arguments", NULL);
}
