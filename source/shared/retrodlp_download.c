#if !defined(__APPLE__)
#define _POSIX_C_SOURCE 200809L
#endif

#include "retrodlp/download.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <curl/curl.h>

#include "rdlp_curl.h"
#include "yt_mux.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define DOWNLOAD_DEFAULT_TIMEOUT_MILLISECONDS 0UL
#define HAS_FIELD(value, type, field)                                           \
  ((value)->struct_size >= offsetof(type, field) + sizeof((value)->field))

typedef struct {
  FILE *file;
  int failed;
  int64_t bytes_written;
  unsigned char prefix[16];
  size_t prefix_length;
  const rdlp_download_options *options;
  rdlp_download_event_type event_type;
  const char *path;
} download_writer;

static void set_error(rdlp_error *error, rdlp_status status, long http_status,
                      int transport_code, const char *message) {
  rdlp_error value;
  size_t size;
  if (error == NULL)
    return;
  size = error->struct_size;
  if (size == 0 || size > sizeof(value))
    size = sizeof(value);
  memset(&value, 0, sizeof(value));
  value.struct_size = sizeof(value);
  value.status = status;
  value.http_status = http_status;
  value.transport_code = transport_code;
  value.retryable = status == RDLP_STATUS_NETWORK || status == RDLP_STATUS_HTTP;
  if (message != NULL)
    snprintf(value.message, sizeof(value.message), "%s", message);
  memcpy(error, &value, size);
}

static void emit_event(const rdlp_download_options *options,
                       rdlp_download_event_type type, const char *path,
                       uint64_t completed, uint64_t expected) {
  rdlp_download_event event;
  if (options == NULL ||
      !HAS_FIELD(options, rdlp_download_options, event_callback) ||
      options->event_callback == NULL)
    return;
  memset(&event, 0, sizeof(event));
  event.struct_size = sizeof(event);
  event.type = type;
  event.path = path;
  event.completed_bytes = completed;
  event.expected_bytes = expected;
  options->event_callback(
      &event, HAS_FIELD(options, rdlp_download_options, callback_context)
                  ? options->callback_context
                  : NULL);
}

static int cancelled(const rdlp_download_options *options) {
  return options != NULL &&
         HAS_FIELD(options, rdlp_download_options, cancel_callback) &&
         options->cancel_callback != NULL &&
         options->cancel_callback(
             HAS_FIELD(options, rdlp_download_options, callback_context)
                 ? options->callback_context
                 : NULL);
}

static size_t write_download(void *contents, size_t size, size_t count,
                             void *opaque) {
  download_writer *writer = (download_writer *)opaque;
  size_t incoming;
  size_t copied;
  size_t written;
  if (count != 0 && size > ((size_t)-1) / count) {
    writer->failed = 1;
    return 0;
  }
  incoming = size * count;
  copied = sizeof(writer->prefix) - writer->prefix_length;
  if (copied > incoming)
    copied = incoming;
  if (copied != 0) {
    memcpy(writer->prefix + writer->prefix_length, contents, copied);
    writer->prefix_length += copied;
  }
  written = fwrite(contents, 1, incoming, writer->file);
  if (written != incoming ||
      incoming > (size_t)(INT64_MAX - writer->bytes_written)) {
    writer->failed = 1;
    return written;
  }
  writer->bytes_written += (int64_t)incoming;
  return incoming;
}

#if LIBCURL_VERSION_NUM >= 0x072000
static int transfer_progress(void *opaque, curl_off_t total, curl_off_t now,
                             curl_off_t upload_total, curl_off_t upload_now) {
  download_writer *writer = (download_writer *)opaque;
  (void)upload_total;
  (void)upload_now;
  emit_event(writer->options, writer->event_type, writer->path,
             now > 0 ? (uint64_t)now : 0U,
             total > 0 ? (uint64_t)total : 0U);
  return cancelled(writer->options);
}
#else
static int transfer_progress(void *opaque, double total, double now,
                             double upload_total, double upload_now) {
  download_writer *writer = (download_writer *)opaque;
  (void)upload_total;
  (void)upload_now;
  emit_event(writer->options, writer->event_type, writer->path,
             now > 0 ? (uint64_t)now : 0U,
             total > 0 ? (uint64_t)total : 0U);
  return cancelled(writer->options);
}
#endif

static int valid_header(const rdlp_http_header *header) {
  return header != NULL && header->name != NULL && header->value != NULL &&
         header->name[0] != '\0' && strchr(header->name, ':') == NULL &&
         strchr(header->name, '\r') == NULL && strchr(header->name, '\n') == NULL &&
         strchr(header->value, '\r') == NULL && strchr(header->value, '\n') == NULL;
}

static struct curl_slist *media_headers(const rdlp_selection *selection,
                                        size_t media_index, int *valid) {
  struct curl_slist *list = NULL;
  size_t count = rdlp_selection_media_header_count(selection, media_index);
  size_t index;
  *valid = 1;
  for (index = 0; index < count; ++index) {
    const rdlp_http_header *header =
        rdlp_selection_media_header(selection, media_index, index);
    char *line;
    size_t length;
    struct curl_slist *grown;
    if (!valid_header(header)) {
      *valid = 0;
      break;
    }
    length = strlen(header->name) + strlen(header->value) + 3;
    line = (char *)malloc(length);
    if (line == NULL) {
      *valid = 0;
      break;
    }
    snprintf(line, length, "%s: %s", header->name, header->value);
    grown = curl_slist_append(list, line);
    free(line);
    if (grown == NULL) {
      *valid = 0;
      break;
    }
    list = grown;
  }
  if (!*valid) {
    curl_slist_free_all(list);
    list = NULL;
  }
  return list;
}

static rdlp_status download_media(const rdlp_selection *selection,
                                  size_t media_index, const char *destination,
                                  const rdlp_download_options *options,
                                  rdlp_download_event_type event_type,
                                  int64_t *bytes_written, rdlp_error *error) {
  char temporary[PATH_MAX];
  struct stat information;
  int descriptor;
  int headers_valid;
  int close_failed;
  CURL *curl;
  CURLcode code;
  struct curl_slist *headers;
  download_writer writer;
  long http_status = 0;
  const char *url = rdlp_selection_media_url(selection, media_index);
  if (url == NULL || destination == NULL || destination[0] == '\0' ||
      snprintf(temporary, sizeof(temporary), "%s.part", destination) >=
          (int)sizeof(temporary)) {
    set_error(error, RDLP_STATUS_INVALID_ARGUMENT, 0, 0,
              "invalid media download arguments");
    return RDLP_STATUS_INVALID_ARGUMENT;
  }
  *bytes_written = 0;
  if (lstat(destination, &information) == 0 ||
      lstat(temporary, &information) == 0) {
    set_error(error, RDLP_STATUS_STORAGE, 0, 0,
              "destination or partial download already exists");
    return RDLP_STATUS_STORAGE;
  }
  if (errno != ENOENT) {
    set_error(error, RDLP_STATUS_STORAGE, 0, 0, "download storage error");
    return RDLP_STATUS_STORAGE;
  }
  descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (descriptor < 0) {
    set_error(error, RDLP_STATUS_STORAGE, 0, 0,
              errno == EEXIST
                  ? "destination or partial download already exists"
                  : "download storage error");
    return RDLP_STATUS_STORAGE;
  }
  memset(&writer, 0, sizeof(writer));
  writer.file = fdopen(descriptor, "wb");
  writer.options = options;
  writer.event_type = event_type;
  writer.path = destination;
  if (writer.file == NULL) {
    close(descriptor);
    unlink(temporary);
    set_error(error, RDLP_STATUS_STORAGE, 0, 0, "download storage error");
    return RDLP_STATUS_STORAGE;
  }
  headers = media_headers(selection, media_index, &headers_valid);
  curl = headers_valid ? curl_easy_init() : NULL;
  if (!headers_valid || curl == NULL) {
    curl_slist_free_all(headers);
    fclose(writer.file);
    unlink(temporary);
    set_error(error, headers_valid ? RDLP_STATUS_NETWORK
                                   : RDLP_STATUS_INVALID_ARGUMENT,
              0, 0, headers_valid ? "could not initialize HTTP transfer"
                                   : "invalid media request headers");
    return headers_valid ? RDLP_STATUS_NETWORK : RDLP_STATUS_INVALID_ARGUMENT;
  }
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 5L);
#if LIBCURL_VERSION_NUM >= 0x075500
  curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "https");
  curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS_STR, "https");
#else
  curl_easy_setopt(curl, CURLOPT_PROTOCOLS, (long)CURLPROTO_HTTPS);
  curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS, (long)CURLPROTO_HTTPS);
#endif
  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_download);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &writer);
  curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
  curl_easy_setopt(
      curl, CURLOPT_TIMEOUT_MS,
      options == NULL ||
              !HAS_FIELD(options, rdlp_download_options,
                         network_timeout_milliseconds)
          ? DOWNLOAD_DEFAULT_TIMEOUT_MILLISECONDS
          : options->network_timeout_milliseconds);
  if (options != NULL &&
      HAS_FIELD(options, rdlp_download_options, ca_bundle_path) &&
      options->ca_bundle_path != NULL)
    curl_easy_setopt(curl, CURLOPT_CAINFO, options->ca_bundle_path);
  curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
#if LIBCURL_VERSION_NUM >= 0x072000
  curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, transfer_progress);
  curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &writer);
#else
  curl_easy_setopt(curl, CURLOPT_PROGRESSFUNCTION, transfer_progress);
  curl_easy_setopt(curl, CURLOPT_PROGRESSDATA, &writer);
#endif
  emit_event(options, event_type, destination, 0U,
             rdlp_selection_media_content_length(selection, media_index) > 0
                 ? (uint64_t)rdlp_selection_media_content_length(selection,
                                                                 media_index)
                 : 0U);
  code = curl_easy_perform(curl);
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_status);
  curl_easy_cleanup(curl);
  curl_slist_free_all(headers);
  *bytes_written = writer.bytes_written;
  close_failed = fflush(writer.file) != 0 || fsync(descriptor) != 0;
  if (fclose(writer.file) != 0)
    close_failed = 1;
  if (code != CURLE_OK || writer.failed || close_failed) {
    unlink(temporary);
    if (code == CURLE_ABORTED_BY_CALLBACK && cancelled(options)) {
      set_error(error, RDLP_STATUS_CANCELLED, http_status, (int)code,
                "operation cancelled");
      return RDLP_STATUS_CANCELLED;
    }
    set_error(error, writer.failed || close_failed ? RDLP_STATUS_STORAGE
                                                   : RDLP_STATUS_NETWORK,
              http_status, (int)code,
              writer.failed || close_failed ? "download storage error"
                                             : curl_easy_strerror(code));
    return writer.failed || close_failed ? RDLP_STATUS_STORAGE
                                         : RDLP_STATUS_NETWORK;
  }
  if (http_status < 200 || http_status >= 300) {
    unlink(temporary);
    set_error(error, RDLP_STATUS_HTTP, http_status, (int)code,
              "media download returned an HTTP error");
    return RDLP_STATUS_HTTP;
  }
  if (writer.prefix_length < 8 || memcmp(writer.prefix + 4, "ftyp", 4) != 0) {
    unlink(temporary);
    set_error(error, RDLP_STATUS_INVALID_RESPONSE, http_status, (int)code,
              "download response is not an MP4 file");
    return RDLP_STATUS_INVALID_RESPONSE;
  }
  if (link(temporary, destination) != 0 || unlink(temporary) != 0) {
    unlink(temporary);
    set_error(error, RDLP_STATUS_STORAGE, http_status, (int)code,
              "download storage error");
    return RDLP_STATUS_STORAGE;
  }
  return RDLP_STATUS_OK;
}

static rdlp_status mux_status(YTStatus status) {
  if (status == YT_ERR_CANCELLED)
    return RDLP_STATUS_CANCELLED;
  if (status == YT_ERR_FILE_EXISTS || status == YT_ERR_STORAGE)
    return RDLP_STATUS_STORAGE;
  if (status == YT_ERR_INVALID_MEDIA)
    return RDLP_STATUS_INVALID_RESPONSE;
  return RDLP_STATUS_INTERNAL;
}

static int mux_cancelled(void *opaque) {
  return cancelled((const rdlp_download_options *)opaque);
}

rdlp_status rdlp_download_selection(
    const rdlp_selection *selection, const char *destination,
    const rdlp_download_options *options, rdlp_download_result *result,
    rdlp_error *error) {
  char video_path[PATH_MAX];
  char audio_path[PATH_MAX];
  int adaptive;
  int audio_downloaded = 0;
  int cleanup_failed;
  int64_t ignored_bytes;
  int64_t final_bytes = 0;
  rdlp_status status;
  YTStatus internal_status;
  rdlp_download_result value;
  size_t result_size = 0;
  memset(&value, 0, sizeof(value));
  value.struct_size = sizeof(value);
  if (result != NULL) {
    result_size = result->struct_size;
    if (result_size == 0 || result_size > sizeof(value))
      result_size = sizeof(value);
    memcpy(result, &value, result_size);
  }
  if (selection == NULL || destination == NULL || destination[0] == '\0' ||
      (options != NULL && options->struct_size < sizeof(options->struct_size))) {
    set_error(error, RDLP_STATUS_INVALID_ARGUMENT, 0, 0,
              "selection, destination, or options are invalid");
    return RDLP_STATUS_INVALID_ARGUMENT;
  }
  if (cancelled(options)) {
    set_error(error, RDLP_STATUS_CANCELLED, 0, 0, "operation cancelled");
    return RDLP_STATUS_CANCELLED;
  }
  if (!rdlp_curl_acquire()) {
    set_error(error, RDLP_STATUS_NETWORK, 0, 0,
              "could not initialize HTTP transfers");
    return RDLP_STATUS_NETWORK;
  }
  adaptive = rdlp_selection_is_adaptive(selection);
  if (!adaptive) {
    status = download_media(selection, 0, destination, options,
                            RDLP_DOWNLOAD_EVENT_DOWNLOADING_MEDIA,
                            &final_bytes, error);
    rdlp_curl_release();
    if (status == RDLP_STATUS_OK)
      set_error(error, RDLP_STATUS_OK, 0, 0, "success");
    value.bytes_written = final_bytes;
    if (result != NULL)
      memcpy(result, &value, result_size);
    return status;
  }
  if (snprintf(video_path, sizeof(video_path), "%s.video.mp4", destination) >=
          (int)sizeof(video_path) ||
      snprintf(audio_path, sizeof(audio_path), "%s.audio.m4a", destination) >=
          (int)sizeof(audio_path)) {
    rdlp_curl_release();
    set_error(error, RDLP_STATUS_STORAGE, 0, 0, "download path is too long");
    return RDLP_STATUS_STORAGE;
  }
  status = download_media(selection, 1, audio_path, options,
                          RDLP_DOWNLOAD_EVENT_DOWNLOADING_AUDIO,
                          &ignored_bytes, error);
  if (status == RDLP_STATUS_OK) {
    audio_downloaded = 1;
    status = download_media(selection, 0, video_path, options,
                            RDLP_DOWNLOAD_EVENT_DOWNLOADING_VIDEO,
                            &ignored_bytes, error);
  }
  if (status != RDLP_STATUS_OK) {
    if (audio_downloaded)
      unlink(audio_path);
    rdlp_curl_release();
    return status;
  }
  rdlp_curl_release();
  if (cancelled(options)) {
    value.source_tracks_retained = 1;
    if (result != NULL)
      memcpy(result, &value, result_size);
    set_error(error, RDLP_STATUS_CANCELLED, 0, 0, "operation cancelled");
    return RDLP_STATUS_CANCELLED;
  }
  emit_event(options, RDLP_DOWNLOAD_EVENT_MUXING, destination, 0U, 0U);
  internal_status = yt_mux_mp4_tracks(video_path, audio_path, destination,
                                      &final_bytes, mux_cancelled,
                                      (void *)options);
  if (internal_status != YT_OK) {
    value.source_tracks_retained = 1;
    if (result != NULL)
      memcpy(result, &value, result_size);
    status = mux_status(internal_status);
    set_error(error, status, 0, 0,
              status == RDLP_STATUS_CANCELLED ? "operation cancelled"
                                              : "MP4 muxing failed");
    return status;
  }
  emit_event(options, RDLP_DOWNLOAD_EVENT_CLEANING_UP, destination, 0U, 0U);
  cleanup_failed = unlink(video_path) != 0;
  if (unlink(audio_path) != 0)
    cleanup_failed = 1;
  value.bytes_written = final_bytes;
  value.source_tracks_retained = cleanup_failed;
  if (result != NULL)
    memcpy(result, &value, result_size);
  if (cleanup_failed) {
    set_error(error, RDLP_STATUS_STORAGE, 0, 0,
              "mux succeeded but source-track cleanup failed");
    return RDLP_STATUS_STORAGE;
  }
  set_error(error, RDLP_STATUS_OK, 0, 0, "success");
  return RDLP_STATUS_OK;
}
