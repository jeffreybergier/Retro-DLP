#if !defined(__APPLE__)
#define _POSIX_C_SOURCE 200112L
#endif

#include "yt_mux.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "lsmash.h"
#include "importer/importer.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define YT_MUX_MAX_INPUT_SIZE 0x7fffffffLL
#define YT_MUX_MAX_SAMPLES 50000000U

typedef struct {
  lsmash_root_t *root;
  importer_t *importer;
  lsmash_summary_t *summary;
  uint32_t input_track;
  uint32_t output_track;
  uint32_t sample_entry;
  uint32_t timescale;
  uint32_t timebase;
  uint32_t last_delta;
  uint64_t previous_dts;
  uint64_t start_offset;
  uint32_t sample_count;
  lsmash_sample_t *sample;
  int active;
} YTMuxTrack;

static int checked_input(const char *path) {
  struct stat information;
  return path != NULL && lstat(path, &information) == 0 &&
         S_ISREG(information.st_mode) && information.st_size > 0 &&
         information.st_size <= YT_MUX_MAX_INPUT_SIZE;
}

static void mux_track_cleanup(YTMuxTrack *track) {
  if (track == NULL)
    return;
  lsmash_delete_sample(track->sample);
  lsmash_cleanup_summary(track->summary);
  lsmash_importer_close(track->importer);
  lsmash_destroy_root(track->root);
  memset(track, 0, sizeof(*track));
}

static int open_input_track(const char *path, lsmash_summary_type summary_type,
                            YTMuxTrack *track) {
  memset(track, 0, sizeof(*track));
  track->root = lsmash_create_root();
  if (track->root == NULL)
    return 0;
  track->importer = lsmash_importer_open(track->root, path, "auto");
  if (track->importer == NULL ||
      lsmash_importer_get_track_count(track->importer) != 1)
    return 0;
  track->input_track = 1;
  if (lsmash_importer_construct_timeline(track->importer,
                                         track->input_track) < 0)
    return 0;
  track->summary =
      lsmash_duplicate_summary(track->importer, track->input_track);
  if (track->summary == NULL || track->summary->summary_type != summary_type)
    return 0;
  track->active = 1;
  track->start_offset = UINT64_MAX;
  return 1;
}

static int setup_output_track(lsmash_root_t *output, YTMuxTrack *track) {
  lsmash_track_parameters_t track_parameters;
  lsmash_media_parameters_t media_parameters;
  int sample_entry;

  lsmash_initialize_track_parameters(&track_parameters);
  lsmash_initialize_media_parameters(&media_parameters);
  track_parameters.mode = ISOM_TRACK_ENABLED | ISOM_TRACK_IN_MOVIE |
                          ISOM_TRACK_IN_PREVIEW;
  if (track->summary->summary_type == LSMASH_SUMMARY_TYPE_VIDEO) {
    lsmash_video_summary_t *video = (lsmash_video_summary_t *)track->summary;
    uint64_t display_width = (uint64_t)video->width << 16;
    uint64_t display_height = (uint64_t)video->height << 16;
    if (!lsmash_check_codec_type_identical(video->sample_type,
                                            ISOM_CODEC_TYPE_AVC1_VIDEO))
      return 0;
    if (video->par_h != 0 && video->par_v != 0) {
      if (video->par_h > video->par_v) {
        if (display_width > UINT64_MAX / video->par_h)
          return 0;
        display_width = display_width * video->par_h / video->par_v;
      } else {
        if (display_height > UINT64_MAX / video->par_v)
          return 0;
        display_height = display_height * video->par_v / video->par_h;
      }
    }
    track_parameters.display_width =
        display_width > UINT32_MAX ? UINT32_MAX : (uint32_t)display_width;
    track_parameters.display_height =
        display_height > UINT32_MAX ? UINT32_MAX : (uint32_t)display_height;
    track->output_track =
        lsmash_create_track(output, ISOM_MEDIA_HANDLER_TYPE_VIDEO_TRACK);
    track->timescale = video->timescale;
    track->timebase = video->timebase;
    media_parameters.media_handler_name = "L-SMASH Video Handler";
  } else {
    lsmash_audio_summary_t *audio = (lsmash_audio_summary_t *)track->summary;
    if (!lsmash_check_codec_type_identical(audio->sample_type,
                                            ISOM_CODEC_TYPE_MP4A_AUDIO) &&
        !lsmash_check_codec_type_identical(audio->sample_type,
                                            QT_CODEC_TYPE_MP4A_AUDIO))
      return 0;
    track->output_track =
        lsmash_create_track(output, ISOM_MEDIA_HANDLER_TYPE_AUDIO_TRACK);
    track->timescale = audio->frequency;
    track->timebase = 1;
    media_parameters.media_handler_name = "L-SMASH Audio Handler";
  }
  if (track->output_track == 0 || track->timescale == 0 ||
      track->timebase == 0)
    return 0;
  media_parameters.timescale = track->timescale;
  if (lsmash_set_track_parameters(output, track->output_track,
                                  &track_parameters) < 0 ||
      lsmash_set_media_parameters(output, track->output_track,
                                  &media_parameters) < 0)
    return 0;
  sample_entry =
      lsmash_add_sample_entry(output, track->output_track, track->summary);
  if (sample_entry <= 0)
    return 0;
  track->sample_entry = (uint32_t)sample_entry;
  return 1;
}

static int load_next_sample(YTMuxTrack *track) {
  int result;
  if (!track->active || track->sample != NULL)
    return 1;
  result = lsmash_importer_get_access_unit(track->importer,
                                           track->input_track,
                                           &track->sample);
  if (result == 2) {
    track->active = 0;
    track->last_delta = lsmash_importer_get_last_delta(
        track->importer, track->input_track);
    if (track->last_delta == 0 ||
        track->last_delta > UINT32_MAX / track->timebase)
      return 0;
    track->last_delta *= track->timebase;
    return 1;
  }
  if (result != 0 || track->sample == NULL ||
      track->sample->dts > UINT64_MAX / track->timebase ||
      track->sample->cts == LSMASH_TIMESTAMP_UNDEFINED ||
      track->sample->cts > UINT64_MAX / track->timebase)
    return 0;
  track->sample->dts *= track->timebase;
  track->sample->cts *= track->timebase;
  track->sample->index = track->sample_entry;
  return 1;
}

static int append_sample(lsmash_root_t *output, YTMuxTrack *track) {
  uint64_t dts;
  uint64_t cts;
  if (track->sample_count >= YT_MUX_MAX_SAMPLES)
    return 0;
  dts = track->sample->dts;
  cts = track->sample->cts;
  if (track->sample_count != 0 && dts <= track->previous_dts)
    return 0;
  if (lsmash_append_sample(output, track->output_track, track->sample) < 0)
    return 0;
  track->sample = NULL;
  if (cts < track->start_offset)
    track->start_offset = cts;
  if (track->sample_count != 0) {
    uint64_t delta = dts - track->previous_dts;
    if (delta == 0 || delta > UINT32_MAX)
      return 0;
    track->last_delta = (uint32_t)delta;
  }
  track->previous_dts = dts;
  ++track->sample_count;
  return 1;
}

static int finish_track(lsmash_root_t *output, YTMuxTrack *track) {
  lsmash_edit_t edit;
  uint64_t media_duration;
  uint32_t movie_timescale;
  if (track->sample_count == 0 || track->last_delta == 0 ||
      track->start_offset == UINT64_MAX ||
      lsmash_flush_pooled_samples(output, track->output_track,
                                  track->last_delta) < 0)
    return 0;
  movie_timescale = lsmash_get_movie_timescale(output);
  if (movie_timescale == 0 ||
      track->previous_dts > UINT64_MAX - track->last_delta ||
      track->start_offset > INT64_MAX)
    return 0;
  media_duration = track->previous_dts + track->last_delta;
  edit.duration = (uint64_t)(media_duration *
                             ((double)movie_timescale / track->timescale));
  edit.start_time = (int64_t)track->start_offset;
  edit.rate = ISOM_EDIT_MODE_NORMAL;
  return lsmash_create_explicit_timeline_map(output, track->output_track,
                                             edit) == 0;
}

static int mux_samples(lsmash_root_t *output, YTMuxTrack tracks[2],
                       YTMuxCancelCallback cancel_callback,
                       void *cancel_opaque, int *was_cancelled) {
  while (tracks[0].active || tracks[1].active || tracks[0].sample != NULL ||
         tracks[1].sample != NULL) {
    YTMuxTrack *selected;
    if (cancel_callback != NULL && cancel_callback(cancel_opaque)) {
      *was_cancelled = 1;
      return 0;
    }
    if (!load_next_sample(&tracks[0]) || !load_next_sample(&tracks[1]))
      return 0;
    if (tracks[0].sample == NULL && tracks[1].sample == NULL)
      break;
    if (tracks[1].sample == NULL)
      selected = &tracks[0];
    else if (tracks[0].sample == NULL)
      selected = &tracks[1];
    else
      selected = ((double)tracks[0].sample->dts / tracks[0].timescale <=
                  (double)tracks[1].sample->dts / tracks[1].timescale)
                     ? &tracks[0]
                     : &tracks[1];
    if (!append_sample(output, selected))
      return 0;
  }
  return finish_track(output, &tracks[0]) &&
         finish_track(output, &tracks[1]);
}

static uint32_t read_be32(const unsigned char value[4]) {
  return ((uint32_t)value[0] << 24) | ((uint32_t)value[1] << 16) |
         ((uint32_t)value[2] << 8) | value[3];
}

static int scan_boxes(FILE *file, uint64_t start, uint64_t end,
                      int reject_mvex, int *has_moov, int *has_mdat) {
  uint64_t position = start;
  while (position < end) {
    unsigned char header[16];
    uint64_t size;
    uint64_t header_size = 8;
    uint32_t type;
    if (end - position < 8 || position > (uint64_t)LONG_MAX ||
        fseek(file, (long)position, SEEK_SET) != 0 ||
        fread(header, 1, 8, file) != 8)
      return 0;
    size = read_be32(header);
    type = read_be32(header + 4);
    if (size == 1) {
      if (end - position < 16 || fread(header + 8, 1, 8, file) != 8)
        return 0;
      size = ((uint64_t)read_be32(header + 8) << 32) |
             read_be32(header + 12);
      header_size = 16;
    } else if (size == 0) {
      size = end - position;
    }
    if (size < header_size || size > end - position)
      return 0;
    if (type == LSMASH_4CC('m', 'o', 'o', 'f') ||
        type == LSMASH_4CC('s', 'i', 'd', 'x') ||
        (reject_mvex && type == LSMASH_4CC('m', 'v', 'e', 'x')))
      return 0;
    if (type == LSMASH_4CC('m', 'o', 'o', 'v')) {
      *has_moov = 1;
      if (!scan_boxes(file, position + header_size, position + size, 1,
                      has_moov, has_mdat))
        return 0;
    } else if (type == LSMASH_4CC('m', 'd', 'a', 't')) {
      *has_mdat = 1;
    }
    position += size;
  }
  return position == end;
}

static int validate_flat_mp4(const char *path, int64_t *size_out) {
  struct stat information;
  FILE *file;
  unsigned char prefix[8];
  int has_moov = 0;
  int has_mdat = 0;
  int valid;
  if (lstat(path, &information) != 0 || !S_ISREG(information.st_mode) ||
      information.st_size < 16 || information.st_size > INT64_MAX)
    return 0;
  file = fopen(path, "rb");
  if (file == NULL)
    return 0;
  valid = fread(prefix, 1, sizeof(prefix), file) == sizeof(prefix) &&
          memcmp(prefix + 4, "ftyp", 4) == 0 &&
          scan_boxes(file, 0, (uint64_t)information.st_size, 0, &has_moov,
                     &has_mdat) &&
          has_moov && has_mdat;
  fclose(file);
  if (valid)
    *size_out = information.st_size;
  return valid;
}

YTStatus yt_mux_mp4_tracks(const char *video_path, const char *audio_path,
                           const char *destination, int64_t *bytes_written,
                           YTMuxCancelCallback cancel_callback,
                           void *cancel_opaque) {
  YTMuxTrack tracks[2];
  lsmash_root_t *output;
  lsmash_file_parameters_t output_file;
  lsmash_movie_parameters_t movie;
  lsmash_brand_type brands[3];
  lsmash_adhoc_remux_t optimize;
  char temporary[PATH_MAX];
  struct stat information;
  int descriptor;
  int output_open;
  int success;
  int was_cancelled;
  YTStatus status;

  if (video_path == NULL || audio_path == NULL || destination == NULL ||
      destination[0] == '\0' || bytes_written == NULL)
    return YT_ERR_INVALID_RESPONSE;
  *bytes_written = 0;
  was_cancelled = 0;
  if (cancel_callback != NULL && cancel_callback(cancel_opaque))
    return YT_ERR_CANCELLED;
  if (!checked_input(video_path) || !checked_input(audio_path))
    return YT_ERR_INVALID_MEDIA;
  if (lstat(destination, &information) == 0)
    return YT_ERR_FILE_EXISTS;
  if (errno != ENOENT ||
      snprintf(temporary, sizeof(temporary), "%s.part", destination) >=
          (int)sizeof(temporary))
    return YT_ERR_STORAGE;
  descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (descriptor < 0)
    return errno == EEXIST ? YT_ERR_FILE_EXISTS : YT_ERR_STORAGE;
  close(descriptor);

  memset(tracks, 0, sizeof(tracks));
  memset(&output_file, 0, sizeof(output_file));
  output = NULL;
  output_open = 0;
  status = YT_ERR_MUX;
  if (!open_input_track(video_path, LSMASH_SUMMARY_TYPE_VIDEO, &tracks[0]) ||
      !open_input_track(audio_path, LSMASH_SUMMARY_TYPE_AUDIO, &tracks[1]))
    goto finished;
  output = lsmash_create_root();
  if (output == NULL)
    goto finished;
  if (lsmash_open_file(temporary, 0, &output_file) < 0)
    goto finished;
  output_open = 1;
  brands[0] = ISOM_BRAND_TYPE_ISOM;
  brands[1] = ISOM_BRAND_TYPE_MP41;
  brands[2] = ISOM_BRAND_TYPE_AVC1;
  output_file.major_brand = ISOM_BRAND_TYPE_ISOM;
  output_file.brands = brands;
  output_file.brand_count = 3;
  output_file.minor_version = 0;
  if (lsmash_set_file(output, &output_file) == NULL)
    goto finished;
  lsmash_initialize_movie_parameters(&movie);
  if (lsmash_set_movie_parameters(output, &movie) < 0 ||
      !setup_output_track(output, &tracks[0]) ||
      !setup_output_track(output, &tracks[1]) ||
      !mux_samples(output, tracks, cancel_callback, cancel_opaque,
                   &was_cancelled))
    goto finished;
  if (cancel_callback != NULL && cancel_callback(cancel_opaque)) {
    was_cancelled = 1;
    goto finished;
  }
  optimize.buffer_size = 4U * 1024U * 1024U;
  optimize.func = NULL;
  optimize.param = NULL;
  if (lsmash_finish_movie(output, &optimize) < 0)
    goto finished;
  success = lsmash_close_file(&output_file) == 0;
  output_open = 0;
  if (!success || !validate_flat_mp4(temporary, bytes_written))
    goto finished;
  descriptor = open(temporary, O_RDONLY);
  if (descriptor < 0 || fsync(descriptor) != 0) {
    if (descriptor >= 0)
      close(descriptor);
    status = YT_ERR_STORAGE;
    goto finished;
  }
  close(descriptor);
  if (link(temporary, destination) != 0) {
    status = errno == EEXIST ? YT_ERR_FILE_EXISTS : YT_ERR_STORAGE;
    goto finished;
  }
  if (unlink(temporary) != 0) {
    status = YT_ERR_STORAGE;
    goto finished;
  }
  status = YT_OK;

finished:
  if (output_open)
    lsmash_close_file(&output_file);
  lsmash_destroy_root(output);
  mux_track_cleanup(&tracks[0]);
  mux_track_cleanup(&tracks[1]);
  if (status != YT_OK)
    unlink(temporary);
  return was_cancelled ? YT_ERR_CANCELLED : status;
}
