#include "cli.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <unistd.h>

#include "cli_assets.h"
#include "cli_options.h"
#include "cli_render.h"
#include "platform.h"
#include "retrodlp/download.h"
#include "retrodlp/retrodlp.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define CLI_FALLBACK_COLUMNS 80U
#define CLI_LABEL_WIDTH 11U

typedef struct {
  int download_event_seen[5];
  int progress_started;
  int progress_line_open;
  rdlp_download_event_type progress_type;
  unsigned int last_percent;
  uint64_t last_completed_bytes;
  uint64_t last_expected_bytes;
  struct timeval progress_started_at;
  int progress_clock_valid;
} CLIEventState;

static void print_operation_prefix(const char *label) {
  size_t length = strlen(label);
  size_t padding = length < CLI_LABEL_WIDTH ? CLI_LABEL_WIDTH - length : 1U;
  fprintf(stderr, "[%s]", label);
  while (padding-- != 0)
    fputc(' ', stderr);
}

static void print_operation(const char *label, const char *detail) {
  print_operation_prefix(label);
  fprintf(stderr, "%s\n", detail == NULL ? "" : detail);
}

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

static size_t terminal_columns(void) {
  struct winsize size;
  const char *configured;
  char *end;
  unsigned long columns;
  if (ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_col >= 40)
    return size.ws_col;
  configured = getenv("COLUMNS");
  if (configured != NULL && configured[0] != '\0') {
    columns = strtoul(configured, &end, 10);
    if (*end == '\0' && columns >= 40 && columns <= 1000)
      return (size_t)columns;
  }
  return CLI_FALLBACK_COLUMNS;
}

static size_t utf8_decode(const unsigned char *text, unsigned long *codepoint) {
  size_t size;
  unsigned long value;
  if (text[0] < 0x80) {
    *codepoint = text[0];
    return 1;
  }
  if (text[0] >= 0xc2 && text[0] <= 0xdf) {
    size = 2;
    value = text[0] & 0x1fU;
  } else if (text[0] >= 0xe0 && text[0] <= 0xef) {
    size = 3;
    value = text[0] & 0x0fU;
  } else if (text[0] >= 0xf0 && text[0] <= 0xf4) {
    size = 4;
    value = text[0] & 0x07U;
  } else {
    *codepoint = '?';
    return 0;
  }
  {
    size_t index;
    for (index = 1; index < size; ++index) {
      if (text[index] == '\0' || (text[index] & 0xc0U) != 0x80U) {
        *codepoint = '?';
        return 0;
      }
      value = (value << 6) | (text[index] & 0x3fU);
    }
  }
  if ((size == 3 && value >= 0xd800 && value <= 0xdfff) ||
      (size == 4 && value > 0x10ffff)) {
    *codepoint = '?';
    return 0;
  }
  *codepoint = value;
  return size;
}

static int unicode_columns(unsigned long value) {
  if ((value >= 0x0300 && value <= 0x036f) ||
      (value >= 0x1ab0 && value <= 0x1aff) ||
      (value >= 0x1dc0 && value <= 0x1dff) ||
      (value >= 0x20d0 && value <= 0x20ff) ||
      (value >= 0xfe00 && value <= 0xfe0f) ||
      (value >= 0xfe20 && value <= 0xfe2f))
    return 0;
  if ((value >= 0x1100 && value <= 0x115f) || value == 0x2329 ||
      value == 0x232a || (value >= 0x2e80 && value <= 0xa4cf) ||
      (value >= 0xac00 && value <= 0xd7a3) ||
      (value >= 0xf900 && value <= 0xfaff) ||
      (value >= 0xfe10 && value <= 0xfe19) ||
      (value >= 0xfe30 && value <= 0xfe6f) ||
      (value >= 0xff00 && value <= 0xff60) ||
      (value >= 0xffe0 && value <= 0xffe6) ||
      (value >= 0x1f300 && value <= 0x1faff) ||
      (value >= 0x20000 && value <= 0x3fffd))
    return 2;
  return 1;
}

static size_t escape_display_path(const char *path, char *escaped,
                                  size_t escaped_size) {
  const unsigned char *source = (const unsigned char *)path;
  size_t read_index = 0;
  size_t written = 0;
  while (source[read_index] != '\0' && written + 1 < escaped_size) {
    unsigned long codepoint;
    size_t character_size = utf8_decode(source + read_index, &codepoint);
    if (source[read_index] == '"' || source[read_index] == '\\') {
      if (written + 2 >= escaped_size)
        break;
      escaped[written++] = '\\';
      escaped[written++] = (char)source[read_index++];
    } else if (source[read_index] == '\n' || source[read_index] == '\r' ||
               source[read_index] == '\t') {
      if (written + 2 >= escaped_size)
        break;
      escaped[written++] = '\\';
      escaped[written++] = source[read_index] == '\n'
                               ? 'n'
                               : (source[read_index] == '\r' ? 'r' : 't');
      ++read_index;
    } else if (character_size == 0 || source[read_index] < 0x20 ||
               source[read_index] == 0x7f) {
      escaped[written++] = '?';
      ++read_index;
    } else {
      if (written + character_size >= escaped_size)
        break;
      memcpy(escaped + written, source + read_index, character_size);
      written += character_size;
      read_index += character_size;
    }
  }
  escaped[written] = '\0';
  return written;
}

static void print_quoted_target(const char *path) {
  char escaped[PATH_MAX * 2 + 1];
  size_t offsets[PATH_MAX * 2 + 1];
  unsigned char widths[PATH_MAX * 2];
  size_t escaped_length;
  size_t character_count = 0;
  size_t full_width = 0;
  size_t maximum_width;
  size_t index = 0;
  escaped_length = escape_display_path(path, escaped, sizeof(escaped));
  while (index < escaped_length) {
    unsigned long codepoint;
    size_t character_size = utf8_decode(
        (const unsigned char *)escaped + index, &codepoint);
    if (character_size == 0)
      character_size = 1;
    offsets[character_count] = index;
    widths[character_count] = (unsigned char)unicode_columns(codepoint);
    full_width += widths[character_count++];
    index += character_size;
  }
  offsets[character_count] = escaped_length;
  maximum_width = terminal_columns();
  maximum_width = maximum_width > CLI_LABEL_WIDTH + 4
                      ? maximum_width - CLI_LABEL_WIDTH - 4
                      : 16;
  print_operation_prefix("target");
  fputc('"', stderr);
  if (full_width <= maximum_width || maximum_width < 8) {
    fputs(escaped, stderr);
  } else {
    size_t available = maximum_width - 3;
    size_t head_width = (available + 1) / 2;
    size_t tail_width = available / 2;
    size_t head_count = 0;
    size_t tail_start = character_count;
    size_t used = 0;
    while (head_count < character_count &&
           used + widths[head_count] <= head_width)
      used += widths[head_count++];
    used = 0;
    while (tail_start > head_count &&
           used + widths[tail_start - 1] <= tail_width)
      used += widths[--tail_start];
    fwrite(escaped, 1, offsets[head_count], stderr);
    fputs("...", stderr);
    fputs(escaped + offsets[tail_start], stderr);
  }
  fputs("\"\n", stderr);
}

static const char *video_codec_label(const char *mime_type) {
  if (mime_type == NULL)
    return "unknown";
  if (strstr(mime_type, "avc1") != NULL || strstr(mime_type, "avc3") != NULL)
    return "H.264";
  if (strstr(mime_type, "hev1") != NULL || strstr(mime_type, "hvc1") != NULL)
    return "HEVC";
  if (strstr(mime_type, "av01") != NULL)
    return "AV1";
  if (strstr(mime_type, "vp9") != NULL || strstr(mime_type, "vp09") != NULL)
    return "VP9";
  return "video";
}

static const char *audio_codec_label(const char *mime_type) {
  if (mime_type == NULL)
    return "unknown";
  if (strstr(mime_type, "mp4a") != NULL)
    return "AAC";
  if (strstr(mime_type, "opus") != NULL)
    return "Opus";
  if (strstr(mime_type, "vorbis") != NULL)
    return "Vorbis";
  return "audio";
}

static void print_format_summary(const rdlp_selection *selection) {
  char detail[256];
  const char *video_mime = rdlp_selection_media_mime_type(selection, 0);
  const char *audio_mime = rdlp_selection_media_mime_type(
      selection, rdlp_selection_is_adaptive(selection) ? 1U : 0U);
  snprintf(detail, sizeof(detail), "%s | %dx%d | %s + %s",
           rdlp_selection_format_id(selection),
           rdlp_selection_media_width(selection, 0),
           rdlp_selection_media_height(selection, 0),
           video_codec_label(video_mime), audio_codec_label(audio_mime));
  print_operation("format", detail);
}

static void format_file_size(int64_t bytes, char output[32]) {
  double amount = bytes > 0 ? (double)bytes : 0.0;
  const char *unit = "bytes";
  if (amount >= 1024.0 * 1024.0 * 1024.0) {
    amount /= 1024.0 * 1024.0 * 1024.0;
    unit = "GiB";
  } else if (amount >= 1024.0 * 1024.0) {
    amount /= 1024.0 * 1024.0;
    unit = "MiB";
  } else if (amount >= 1024.0) {
    amount /= 1024.0;
    unit = "KiB";
  }
  if (strcmp(unit, "bytes") == 0)
    snprintf(output, 32, "%.0f %s", amount, unit);
  else
    snprintf(output, 32, "%.1f %s", amount, unit);
}

static const char *event_label(rdlp_event_type type) {
  switch (type) {
  case RDLP_EVENT_AUTHENTICATING:
    return "auth";
  case RDLP_EVENT_LOADING_CONFIGURATION:
    return "client";
  case RDLP_EVENT_FETCHING_BOOTSTRAP:
    return "bootstrap";
  case RDLP_EVENT_REQUESTING_METADATA:
  case RDLP_EVENT_REFRESHING_METADATA:
    return "metadata";
  case RDLP_EVENT_LOADING_PLAYER_JAVASCRIPT:
    return "player-js";
  case RDLP_EVENT_SOLVING_CHALLENGES:
    return "challenges";
  case RDLP_EVENT_SELECTING_FORMATS:
    return "formats";
  case RDLP_EVENT_ENUMERATING_PLAYLIST:
    return "playlist";
  case RDLP_EVENT_OTHER:
    return "process";
  }
  return "process";
}

static const char *event_detail(rdlp_event_type type) {
  switch (type) {
  case RDLP_EVENT_AUTHENTICATING:
    return "cookies";
  case RDLP_EVENT_LOADING_CONFIGURATION:
    return "configure";
  case RDLP_EVENT_FETCHING_BOOTSTRAP:
    return "mobile-web";
  case RDLP_EVENT_REQUESTING_METADATA:
    return "request";
  case RDLP_EVENT_REFRESHING_METADATA:
    return "refresh (visitor data)";
  case RDLP_EVENT_LOADING_PLAYER_JAVASCRIPT:
    return "download";
  case RDLP_EVENT_SOLVING_CHALLENGES:
    return "solve";
  case RDLP_EVENT_SELECTING_FORMATS:
    return "select";
  case RDLP_EVENT_ENUMERATING_PLAYLIST:
    return "enumerate";
  case RDLP_EVENT_OTHER:
    return "response";
  }
  return "response";
}

static void cli_event(const rdlp_event *event, void *opaque) {
  (void)opaque;
  if (event != NULL)
    print_operation(event_label(event->type), event_detail(event->type));
}

static void cli_download_progress_finish(CLIEventState *state) {
  if (state != NULL && state->progress_line_open) {
    fputc('\n', stderr);
    fflush(stderr);
    state->progress_line_open = 0;
  }
}

static const char *download_label(rdlp_download_event_type type) {
  switch (type) {
  case RDLP_DOWNLOAD_EVENT_DOWNLOADING_AUDIO:
    return "audio";
  case RDLP_DOWNLOAD_EVENT_DOWNLOADING_VIDEO:
    return "video";
  case RDLP_DOWNLOAD_EVENT_DOWNLOADING_MEDIA:
    return "download";
  case RDLP_DOWNLOAD_EVENT_MUXING:
    return "mux";
  case RDLP_DOWNLOAD_EVENT_CLEANING_UP:
    return "cleanup";
  }
  return "download";
}

static void cli_download_progress(const rdlp_download_event *event,
                                  CLIEventState *state) {
  char bar[33];
  char speed[7];
  const char *speed_unit;
  unsigned int percent = 0;
  size_t bar_width;
  size_t completed_width;
  size_t index;
  struct timeval now;
  double elapsed;
  double bits_per_second = 0.0;
  double displayed_speed;
  int should_render;

  if (!state->progress_started || state->progress_type != event->type) {
    cli_download_progress_finish(state);
    state->progress_started = 1;
    state->progress_type = event->type;
    state->last_percent = 101U;
    state->last_completed_bytes = 0;
    state->last_expected_bytes = 0;
    state->progress_clock_valid =
        gettimeofday(&state->progress_started_at, NULL) == 0;
  }
  if (event->expected_bytes != 0) {
    uint64_t bounded = event->completed_bytes;
    if (bounded > event->expected_bytes)
      bounded = event->expected_bytes;
    percent = (unsigned int)(((double)bounded * 100.0) /
                             (double)event->expected_bytes);
    should_render = percent != state->last_percent ||
                    event->expected_bytes != state->last_expected_bytes;
  } else {
    should_render = state->last_percent == 101U ||
                    event->completed_bytes < state->last_completed_bytes ||
                    event->completed_bytes - state->last_completed_bytes >=
                        256U * 1024U;
  }
  if (!should_render)
    return;

  elapsed = 0.0;
  if (state->progress_clock_valid && gettimeofday(&now, NULL) == 0) {
    elapsed = (double)(now.tv_sec - state->progress_started_at.tv_sec) +
              (double)(now.tv_usec - state->progress_started_at.tv_usec) /
                  1000000.0;
  }
  if (elapsed > 0.0)
    bits_per_second = ((double)event->completed_bytes * 8.0) / elapsed;
  if (bits_per_second >= 1000000.0) {
    displayed_speed = bits_per_second / 1000000.0;
    speed_unit = "Mbps";
  } else {
    displayed_speed = bits_per_second / 1000.0;
    speed_unit = "Kbps";
  }
  if (displayed_speed > 9999.9)
    snprintf(speed, sizeof(speed), "%6s", ">9999");
  else
    snprintf(speed, sizeof(speed), "%6.1f", displayed_speed);
  bar_width = terminal_columns();
  bar_width = bar_width > 35 ? bar_width - 27 : 8;
  if (bar_width > 32)
    bar_width = 32;
  completed_width = event->expected_bytes == 0
                        ? 0
                        : (size_t)(((double)percent * (double)bar_width) /
                                   100.0);
  if (completed_width > bar_width)
    completed_width = bar_width;
  for (index = 0; index < bar_width; ++index) {
    if (index < completed_width)
      bar[index] = '=';
    else if (index == completed_width && completed_width < bar_width)
      bar[index] = '>';
    else
      bar[index] = '-';
  }
  bar[bar_width] = '\0';
  fputc('\r', stderr);
  print_operation_prefix(download_label(event->type));
  fprintf(stderr, "%s (%s %s)", bar, speed, speed_unit);
  fflush(stderr);
  state->progress_line_open = 1;
  state->last_percent = percent;
  state->last_completed_bytes = event->completed_bytes;
  state->last_expected_bytes = event->expected_bytes;
  if (event->expected_bytes != 0 &&
      event->completed_bytes >= event->expected_bytes)
    cli_download_progress_finish(state);
}

static void cli_download_event(const rdlp_download_event *event, void *opaque) {
  CLIEventState *state = (CLIEventState *)opaque;
  int downloading;
  if (event == NULL || state == NULL ||
      event->type > RDLP_DOWNLOAD_EVENT_CLEANING_UP)
    return;
  downloading = event->type == RDLP_DOWNLOAD_EVENT_DOWNLOADING_AUDIO ||
                event->type == RDLP_DOWNLOAD_EVENT_DOWNLOADING_VIDEO ||
                event->type == RDLP_DOWNLOAD_EVENT_DOWNLOADING_MEDIA;
  if (!downloading)
    cli_download_progress_finish(state);
  if (state->download_event_seen[event->type]) {
    if (downloading)
      cli_download_progress(event, state);
    return;
  }
  state->download_event_seen[event->type] = 1;
  switch (event->type) {
  case RDLP_DOWNLOAD_EVENT_DOWNLOADING_AUDIO:
  case RDLP_DOWNLOAD_EVENT_DOWNLOADING_VIDEO:
  case RDLP_DOWNLOAD_EVENT_DOWNLOADING_MEDIA:
    cli_download_progress(event, state);
    break;
  case RDLP_DOWNLOAD_EVENT_MUXING:
    print_operation("mux", "audio + video");
    break;
  case RDLP_DOWNLOAD_EVENT_CLEANING_UP:
    break;
  default:
    return;
  }
}

static void print_error(const rdlp_error *error, rdlp_error_code code) {
  (void)error;
  fprintf(stderr, "retro-dlp: %s (%d)\n", rdlp_error_name(code), (int)code);
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
  return rdlp_context_create(&config, context, error) == RDLP_OK;
}

static int resolve_argument(const CLIOptions *cli, const char *cookie_file,
                            const char *ca_bundle, rdlp_context *context) {
  rdlp_resolve_options options;
  rdlp_selection *selection = NULL;
  rdlp_error error;
  rdlp_error_code status;
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
  print_operation("resolve", cli->input);
  status = rdlp_resolve_video(context, cli->input, &options, &selection, &error);
  if (status != RDLP_OK) {
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
    print_format_summary(selection);
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
  print_format_summary(selection);
  print_quoted_target(destination);
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
    cli_download_progress_finish(&event_state);
    rdlp_selection_destroy(selection);
    if (status != RDLP_OK) {
      if (result.source_tracks_retained)
        fprintf(stderr, "retro-dlp: %s (%d); downloaded tracks were retained\n",
                rdlp_error_name(status), (int)status);
      else
        print_error(&error, status);
      return 1;
    }
    {
      char size[32];
      format_file_size(result.bytes_written, size);
      print_operation("done", size);
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
  rdlp_error_code status;
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
  if (status != RDLP_OK) {
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
    print_error(&error, error.code);
    return 1;
  }
  if (cli.flat_playlist)
    result = list_playlist_argument(&cli, cookie_file, context);
  else
    result = resolve_argument(&cli, cookie_file, ca_bundle, context);
  rdlp_context_destroy(context);
  return result;
}
