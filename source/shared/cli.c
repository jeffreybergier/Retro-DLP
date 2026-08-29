#include "cli.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cli_assets.h"
#include "cli_options.h"
#include "cli_render.h"
#include "platform.h"
#include "retrodlp/download.h"
#include "retrodlp/retrodlp.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

typedef struct {
  int download_event_seen[5];
} CLIEventState;

static int home_path(char *buffer, size_t buffer_size, const char *suffix) {
  const char *home = getenv("HOME");
  size_t home_length;
  if (buffer == NULL || buffer_size == 0 || home == NULL || home[0] != '/')
    return 0;
  home_length = strlen(home);
  while (home_length > 1 && home[home_length - 1] == '/')
    --home_length;
  if (home_length + strlen(suffix) + 1 > buffer_size)
    return 0;
  memcpy(buffer, home, home_length);
  strcpy(buffer + home_length, suffix);
  return 1;
}

static const char *event_message(rdlp_event_type type) {
  switch (type) {
  case RDLP_EVENT_LOADING_CONFIGURATION:
    return "loading client configuration";
  case RDLP_EVENT_FETCHING_BOOTSTRAP:
    return "downloading mobile web player configuration";
  case RDLP_EVENT_REQUESTING_METADATA:
    return "requesting YouTube player metadata";
  case RDLP_EVENT_LOADING_PLAYER_JAVASCRIPT:
    return "downloading player JavaScript";
  case RDLP_EVENT_SOLVING_CHALLENGES:
    return "solving player JavaScript challenges";
  case RDLP_EVENT_SELECTING_FORMATS:
    return "selecting media formats";
  case RDLP_EVENT_ENUMERATING_PLAYLIST:
    return "enumerating playlist pages";
  case RDLP_EVENT_OTHER:
    return "processing response";
  }
  return "processing response";
}

static void cli_event(const rdlp_event *event, void *opaque) {
  (void)opaque;
  if (event != NULL)
    fprintf(stderr, "retro-dlp: %s\n", event_message(event->type));
}

static void cli_download_event(const rdlp_download_event *event, void *opaque) {
  CLIEventState *state = (CLIEventState *)opaque;
  const char *message;
  if (event == NULL || event->type > RDLP_DOWNLOAD_EVENT_CLEANING_UP ||
      state->download_event_seen[event->type])
    return;
  state->download_event_seen[event->type] = 1;
  switch (event->type) {
  case RDLP_DOWNLOAD_EVENT_DOWNLOADING_AUDIO:
    message = "starting audio download to";
    break;
  case RDLP_DOWNLOAD_EVENT_DOWNLOADING_VIDEO:
    message = "starting video download to";
    break;
  case RDLP_DOWNLOAD_EVENT_DOWNLOADING_MEDIA:
    message = "starting download to";
    break;
  case RDLP_DOWNLOAD_EVENT_MUXING:
    message = "muxing tracks to";
    break;
  case RDLP_DOWNLOAD_EVENT_CLEANING_UP:
    message = "mux completed; removing source tracks for";
    break;
  default:
    return;
  }
  fprintf(stderr, "retro-dlp: %s %s\n", message,
          event->path == NULL ? "" : event->path);
}

static void print_error(const rdlp_error *error, rdlp_status status) {
  fprintf(stderr, "retro-dlp: %s\n",
          error != NULL && error->message[0] != '\0'
              ? error->message
              : rdlp_status_string(status));
}

static int create_cli_context(rdlp_context **context, rdlp_error *error,
                              char cache_directory[PATH_MAX],
                              char ejs_directory[PATH_MAX],
                              char ca_bundle[PATH_MAX]) {
  rdlp_config config;
  memset(&config, 0, sizeof(config));
  config.struct_size = sizeof(config);
  if (home_path(cache_directory, PATH_MAX, "/.retro-dlp/cache")) {
    config.cache_directory = cache_directory;
    if (snprintf(ejs_directory, PATH_MAX, "%s/assets/ejs/%s", cache_directory,
                 cli_ejs_asset_version()) < PATH_MAX)
      config.ejs_asset_directory = ejs_directory;
  }
  if (retro_dlp_default_ca_bundle_path(ca_bundle, PATH_MAX))
    config.ca_bundle_path = ca_bundle;
  config.event_callback = cli_event;
  return rdlp_context_create(&config, context, error) == RDLP_STATUS_OK;
}

static int resolve_argument(const CLIOptions *cli, const char *cookie_file,
                            const char *ca_bundle, rdlp_context *context) {
  rdlp_resolve_options options;
  rdlp_selection *selection = NULL;
  rdlp_error error;
  rdlp_status status;
  char destination[PATH_MAX];
  int failed;
  memset(&options, 0, sizeof(options));
  memset(&error, 0, sizeof(error));
  options.struct_size = sizeof(options);
  options.format_expression = cli->format_expression == NULL
                                  ? "22/18"
                                  : cli->format_expression;
  options.cookie_file = cookie_file;
  options.include_format_inventory = cli->list_formats;
  error.struct_size = sizeof(error);
  fprintf(stderr, "retro-dlp: resolving video information\n");
  status = rdlp_resolve_video(context, cli->input, &options, &selection, &error);
  if (status != RDLP_STATUS_OK) {
    print_error(&error, status);
    return 1;
  }
  if (cli->list_formats) {
    cli_render_formats(stdout, selection);
    rdlp_selection_destroy(selection);
    return 0;
  }
  if (cli->dump_json) {
    failed = cli_render_selection_json(selection, cli->input);
    rdlp_selection_destroy(selection);
    if (failed)
      fprintf(stderr, "retro-dlp: could not create result JSON\n");
    return failed;
  }
  if (cli->simulate) {
    fprintf(stderr, "retro-dlp: selected format %s\n",
            rdlp_selection_format_id(selection));
    rdlp_selection_destroy(selection);
    return 0;
  }
  if (cli->output != NULL) {
    if (snprintf(destination, sizeof(destination), "%s", cli->output) >=
        (int)sizeof(destination)) {
      rdlp_selection_destroy(selection);
      return 1;
    }
  } else if (!retro_dlp_default_output_path(
                 rdlp_selection_title(selection),
                 rdlp_selection_video_id(selection), destination,
                 sizeof(destination))) {
    rdlp_selection_destroy(selection);
    return 1;
  }
  fprintf(stderr, "retro-dlp: selected itag %d (%dx%d, %s)\n",
          rdlp_selection_media_itag(selection, 0),
          rdlp_selection_media_width(selection, 0),
          rdlp_selection_media_height(selection, 0),
          rdlp_selection_media_mime_type(selection, 0));
  if (rdlp_selection_is_adaptive(selection))
    fprintf(stderr, "retro-dlp: selected audio itag %d (%s)\n",
            rdlp_selection_media_itag(selection, 1),
            rdlp_selection_media_mime_type(selection, 1));
  {
    rdlp_download_options download_options;
    rdlp_download_result result;
    CLIEventState event_state;
    memset(&download_options, 0, sizeof(download_options));
    memset(&result, 0, sizeof(result));
    memset(&event_state, 0, sizeof(event_state));
    download_options.struct_size = sizeof(download_options);
    download_options.ca_bundle_path = ca_bundle[0] == '\0' ? NULL : ca_bundle;
    download_options.event_callback = cli_download_event;
    download_options.callback_context = &event_state;
    result.struct_size = sizeof(result);
    error.struct_size = sizeof(error);
    status = rdlp_download_selection(selection, destination, &download_options,
                                     &result, &error);
    rdlp_selection_destroy(selection);
    if (status != RDLP_STATUS_OK) {
      if (result.source_tracks_retained)
        fprintf(stderr,
                "retro-dlp: %s; downloaded tracks were retained\n",
                error.message[0] == '\0' ? rdlp_status_string(status)
                                         : error.message);
      else
        print_error(&error, status);
      return 1;
    }
    failed = cli_render_download_result(destination, result.bytes_written);
    if (failed)
      fprintf(stderr,
              "retro-dlp: download completed but result JSON failed\n");
    return failed;
  }
}

static int list_playlist_argument(const CLIOptions *cli,
                                  const char *cookie_file,
                                  rdlp_context *context) {
  rdlp_playlist_options options;
  rdlp_playlist *playlist = NULL;
  rdlp_playlist_collection *collection = NULL;
  rdlp_error error;
  rdlp_status status;
  int failed;
  memset(&options, 0, sizeof(options));
  memset(&error, 0, sizeof(error));
  options.struct_size = sizeof(options);
  options.cookie_file = cookie_file;
  error.struct_size = sizeof(error);
  if (rdlp_is_playlist_collection_input(cli->input))
    status = rdlp_list_playlist_collection(context, cli->input, &options,
                                           &collection, &error);
  else
    status = rdlp_list_playlist(context, cli->input, &options, &playlist,
                                &error);
  if (status != RDLP_STATUS_OK) {
    print_error(&error, status);
    return 1;
  }
  if (collection != NULL) {
    if (cli->dump_json)
      failed = cli_render_playlist_collection_json(collection);
    else {
      cli_render_playlist_collection_table(collection);
      failed = 0;
    }
  } else if (cli->dump_json) {
    failed = cli_render_playlist_json(playlist);
  } else {
    cli_render_playlist_table(playlist);
    failed = 0;
  }
  if (failed)
    fprintf(stderr, "retro-dlp: could not create playlist output\n");
  rdlp_playlist_destroy(playlist);
  rdlp_playlist_collection_destroy(collection);
  return failed;
}

int retro_dlp_run(int argc, char **argv) {
  CLIOptions cli;
  char parse_error[512];
  char cookie_path[PATH_MAX];
  char cache_directory[PATH_MAX];
  char ejs_directory[PATH_MAX];
  char ca_bundle[PATH_MAX];
  const char *cookie_file;
  rdlp_context *context = NULL;
  rdlp_error error;
  int result;
  if (!cli_options_parse(argc, argv, &cli, parse_error,
                         sizeof(parse_error))) {
    fprintf(stderr, "retro-dlp: %s\n", parse_error);
    if (strcmp(parse_error, "unsupported arguments") == 0)
      cli_render_usage(stderr);
    return 2;
  }
  if (cli.action == CLI_ACTION_HELP) {
    cli_render_usage(stdout);
    return 0;
  }
  if (cli.action == CLI_ACTION_VERSION) {
    printf("retro-dlp %s (%s)\n", rdlp_version_string(),
           retro_dlp_platform());
    return 0;
  }
  if (cli.action == CLI_ACTION_ASSETS)
    return cli_run_asset_command(cli.asset_command);
  cookie_file = cli.cookie_file;
  if (cli.cookies_default) {
    if (!home_path(cookie_path, sizeof(cookie_path),
                   "/.retro-dlp/cookies.txt")) {
      fprintf(stderr,
              "retro-dlp: could not determine the default cookie path\n");
      return 1;
    }
    cookie_file = cookie_path;
  }
  memset(&error, 0, sizeof(error));
  cache_directory[0] = '\0';
  ejs_directory[0] = '\0';
  ca_bundle[0] = '\0';
  error.struct_size = sizeof(error);
  if (!create_cli_context(&context, &error, cache_directory, ejs_directory,
                          ca_bundle)) {
    print_error(&error, error.status);
    return 1;
  }
  if (cli.flat_playlist)
    result = list_playlist_argument(&cli, cookie_file, context);
  else
    result = resolve_argument(&cli, cookie_file, ca_bundle, context);
  rdlp_context_destroy(context);
  return result;
}
