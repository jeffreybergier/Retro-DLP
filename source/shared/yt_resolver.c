#include "yt_resolver.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "cJSON.h"
#include "yt_challenges.h"
#include "yt_failure_cache.h"
#include "yt_formats.h"
#include "yt_http.h"
#include "yt_innertube.h"
#include "yt_session.h"
#include "yt_util.h"
#include "yt_webpage.h"

#define YT_USER_AGENT YT_INNERTUBE_DEFAULT_USER_AGENT
const char *yt_resolver_user_agent(void) { return YT_USER_AGENT; }

static int is_video_id_character(char value) {
  return isalnum((unsigned char)value) || value == '-' || value == '_';
}

static int copy_candidate(const char *candidate, char video_id[12]) {
  size_t index;

  if (candidate == NULL)
    return 0;
  for (index = 0; index < 11; ++index) {
    if (candidate[index] == '\0' || !is_video_id_character(candidate[index]))
      return 0;
    video_id[index] = candidate[index];
  }
  if (is_video_id_character(candidate[11]))
    return 0;
  video_id[11] = '\0';
  return 1;
}

static int host_equals(const char *host, size_t host_length,
                       const char *expected) {
  size_t expected_length;

  expected_length = strlen(expected);
  return host_length == expected_length &&
         strncasecmp(host, expected, host_length) == 0;
}

static int is_youtube_host(const char *host, size_t host_length) {
  static const char suffix[] = ".youtube.com";
  size_t suffix_length;

  if (host_equals(host, host_length, "youtube.com") ||
      host_equals(host, host_length, "youtube-nocookie.com") ||
      host_equals(host, host_length, "www.youtube-nocookie.com"))
    return 1;
  suffix_length = sizeof(suffix) - 1;
  return host_length > suffix_length &&
         strncasecmp(host + host_length - suffix_length, suffix,
                     suffix_length) == 0;
}

static int copy_query_video_id(const char *query, char video_id[12]) {
  const char *candidate;

  while (query != NULL && *query != '\0' && *query != '#') {
    if ((query[0] == '?' || query[0] == '&') && query[1] == 'v' &&
        query[2] == '=' && copy_candidate(query + 3, video_id))
      return 1;
    candidate = strchr(query + 1, '&');
    query = candidate;
  }
  return 0;
}

YTStatus yt_extract_video_id(const char *input, char video_id[12]) {
  const char *authority;
  const char *host_end;
  const char *path;
  const char *port;
  size_t host_length;

  if (input == NULL || video_id == NULL)
    return YT_ERR_INVALID_VIDEO_ID;
  if (copy_candidate(input, video_id))
    return YT_OK;

  if (strncmp(input, "https://", 8) == 0)
    authority = input + 8;
  else if (strncmp(input, "http://", 7) == 0)
    authority = input + 7;
  else
    return YT_ERR_INVALID_VIDEO_ID;

  path = strpbrk(authority, "/?#");
  if (path == NULL || path == authority || memchr(authority, '@',
                                                   (size_t)(path - authority)))
    return YT_ERR_INVALID_VIDEO_ID;
  host_end = path;
  port = (const char *)memchr(authority, ':', (size_t)(path - authority));
  if (port != NULL)
    host_end = port;
  host_length = (size_t)(host_end - authority);

  if (host_equals(authority, host_length, "youtu.be") && path[0] == '/' &&
      copy_candidate(path + 1, video_id))
    return YT_OK;
  if (!is_youtube_host(authority, host_length))
    return YT_ERR_INVALID_VIDEO_ID;
  if (strncmp(path, "/shorts/", 8) == 0 &&
      copy_candidate(path + 8, video_id))
    return YT_OK;
  if (strncmp(path, "/embed/", 7) == 0 && copy_candidate(path + 7, video_id))
    return YT_OK;
  if (strncmp(path, "/v/", 3) == 0 && copy_candidate(path + 3, video_id))
    return YT_OK;
  if (copy_query_video_id(strchr(path, '?'), video_id))
    return YT_OK;
  return YT_ERR_INVALID_VIDEO_ID;
}

static void report_progress(YTProgressCallback progress, void *opaque,
                            const char *message) {
  if (progress != NULL)
    progress(message, opaque);
}

static YTStatus resolve_player_selection_document(
    YTHttpSession *session, cJSON *document, const char *video_id,
    const char *bootstrap_player_url, const YTInnertubeClient *client,
    int max_height, int try_adaptive, YTMediaSelection *result,
    YTProgressCallback progress, void *progress_opaque) {
  YTStatus status;
  char *player_url;
  char *player_source;

  status = yt_formats_select(session, document, NULL, client, max_height,
                             try_adaptive, result);
  if (status != YT_ERR_JS_CHALLENGE)
    return status;
  player_url = yt_webpage_player_url_from_document(document);
  if (player_url == NULL)
    player_url = yt_copy_string(bootstrap_player_url);
  if (player_url == NULL) {
    report_progress(progress, progress_opaque,
                    "fetching fallback player information");
    status = yt_webpage_load_player_url(session, video_id, &player_url);
    if (status != YT_OK)
      return status;
  }
  player_source = NULL;
  report_progress(progress, progress_opaque,
                  "loading player JavaScript for URL challenges");
  status = yt_challenges_load_player(session, player_url, &player_source);
  free(player_url);
  if (status != YT_OK)
    return status;
  report_progress(progress, progress_opaque, "solving media URL challenges");
  status = yt_formats_select(session, document, player_source, client,
                             max_height, try_adaptive, result);
  free(player_source);
  return status;
}

static YTStatus resolve_exact_selection_document(
    YTHttpSession *session, cJSON *document, const char *video_id,
    const char *bootstrap_player_url, const YTInnertubeClient *client,
    const char *format_expression, YTMediaSelection *result,
    YTProgressCallback progress, void *progress_opaque) {
  YTStatus status;
  char *player_url;
  char *player_source;
  status = yt_formats_select_exact(session, document, NULL, client,
                                   format_expression, result);
  if (status != YT_ERR_JS_CHALLENGE)
    return status;
  player_url = yt_webpage_player_url_from_document(document);
  if (player_url == NULL)
    player_url = yt_copy_string(bootstrap_player_url);
  if (player_url == NULL) {
    report_progress(progress, progress_opaque,
                    "fetching fallback player information");
    status = yt_webpage_load_player_url(session, video_id, &player_url);
    if (status != YT_OK)
      return status;
  }
  player_source = NULL;
  report_progress(progress, progress_opaque,
                  "loading player JavaScript for URL challenges");
  status = yt_challenges_load_player(session, player_url, &player_source);
  free(player_url);
  if (status != YT_OK)
    return status;
  report_progress(progress, progress_opaque, "solving media URL challenges");
  status = yt_formats_select_exact(session, document, player_source, client,
                                   format_expression, result);
  free(player_source);
  return status;
}

YTStatus yt_resolver_resolve(YTHttpSession *session, const char *input,
                             const char *cookie_file, int max_height,
                             int try_adaptive, YTMediaSelection *result,
                             const char *format_expression, int list_only,
                             YTProgressCallback progress,
                             void *progress_opaque) {
  char video_id[12];
  char failure_key[65];
  YTInnertubeClient client;
  cJSON *document;
  cJSON *response_context;
  const char *visitor_data;
  char *visitor_copy;
  char *bootstrap_player_url;
  int signature_timestamp;
  YTStatus status;
  YTAccountContext account;

  if (!list_only && format_expression != NULL &&
      !yt_format_expression_valid(format_expression))
    return YT_ERR_INVALID_FORMAT;
  if (session == NULL || result == NULL || max_height <= 0 ||
      (cookie_file != NULL && cookie_file[0] == '\0') ||
      (try_adaptive && max_height != 720 && max_height != 1080))
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  memset(&account, 0, sizeof(account));
  document = NULL;
  bootstrap_player_url = NULL;
  status = yt_extract_video_id(input, video_id);
  if (status != YT_OK)
    return status;
  if (cookie_file != NULL || yt_http_session_has_cookies(session)) {
    status = yt_account_context_load_cookies(session, cookie_file, &account);
    if (status != YT_OK)
      return status;
    report_progress(progress, progress_opaque,
                    "using authenticated YouTube cookies");
  }
  report_progress(progress, progress_opaque, "loading client configuration");
  status = yt_innertube_load_client(&client);
  if (status != YT_OK)
    goto finished;
  signature_timestamp = 0;
  report_progress(progress, progress_opaque,
                  "fetching web player configuration");
  status = yt_webpage_load_mweb_bootstrap(session, &account, video_id, &client,
                                          &signature_timestamp,
                                          &bootstrap_player_url);
  if (status != YT_OK)
    goto finished;
  failure_key[0] = '\0';
  if (!list_only) {
    if (format_expression == NULL)
      yt_failure_cache_key(video_id, &client, account.authenticated, max_height,
                           try_adaptive, failure_key);
    else
      yt_failure_cache_exact_key(video_id, &client, account.authenticated,
                                 format_expression, failure_key);
    if (yt_failure_cache_load(session, failure_key, &status))
      goto finished;
  }

  report_progress(progress, progress_opaque, "requesting video metadata");
  status = yt_innertube_call_player(session, &account, video_id, NULL, &client,
                                    signature_timestamp, &document);
  if (status != YT_OK) {
    if (failure_key[0] != '\0')
      yt_failure_cache_remember(session, failure_key, status);
    goto finished;
  }

  response_context = cJSON_GetObjectItemCaseSensitive(document,
                                                       "responseContext");
  visitor_data = yt_json_string(response_context, "visitorData");
  visitor_copy = yt_copy_string(visitor_data);
  if (visitor_data != NULL && visitor_copy == NULL) {
    status = YT_ERR_OUT_OF_MEMORY;
    goto finished;
  }

  if (visitor_copy != NULL) {
    cJSON_Delete(document);
    document = NULL;
    report_progress(progress, progress_opaque,
                    "refreshing video metadata with visitor data");
    status = yt_innertube_call_player(session, &account, video_id,
                                      visitor_copy, &client,
                                      signature_timestamp, &document);
    free(visitor_copy);
    if (status != YT_OK) {
      if (failure_key[0] != '\0')
        yt_failure_cache_remember(session, failure_key, status);
      goto finished;
    }
  }

  status = yt_formats_attach_metadata(document, video_id, result);
  if (status != YT_OK)
    goto finished;
  if (list_only) {
    status = YT_OK;
  } else if (format_expression != NULL) {
    report_progress(progress, progress_opaque, "selecting requested formats");
    status = resolve_exact_selection_document(
        session, document, video_id, bootstrap_player_url, &client,
        format_expression, result, progress, progress_opaque);
  } else {
    report_progress(progress, progress_opaque,
                    try_adaptive ? "selecting adaptive H.264 and AAC streams"
                                 : "selecting a progressive MP4 stream");
    status = resolve_player_selection_document(
        session, document, video_id, bootstrap_player_url, &client, max_height,
        try_adaptive, result, progress, progress_opaque);
    if (status == YT_OK) {
      char buffer[64];
      if (result->adaptive)
        snprintf(buffer, sizeof(buffer), "%d+%d", result->video.itag,
                 result->audio.itag);
      else
        snprintf(buffer, sizeof(buffer), "%d", result->video.itag);
      result->format_id = yt_copy_string(buffer);
      if (result->format_id == NULL)
        status = YT_ERR_OUT_OF_MEMORY;
    }
  }
  if (status == YT_OK) {
    if (failure_key[0] != '\0')
      yt_failure_cache_clear(session, failure_key);
  } else if (failure_key[0] != '\0' &&
             status != YT_ERR_FORMAT_UNAVAILABLE &&
             status != YT_ERR_INVALID_FORMAT) {
    yt_failure_cache_remember(session, failure_key, status);
  }

finished:
  cJSON_Delete(document);
  free(bootstrap_player_url);
  yt_account_context_free(&account);
  return status;
}

void yt_media_request_free(YTMediaRequest *media) {
  if (media == NULL)
    return;
  free(media->url);
  free(media->mime_type);
  free(media->user_agent);
  memset(media, 0, sizeof(*media));
}

void yt_format_info_free(YTFormatInfo *format) {
  if (format == NULL)
    return;
  free(format->mime_type);
  memset(format, 0, sizeof(*format));
}

void yt_media_selection_free(YTMediaSelection *selection) {
  size_t index;
  if (selection == NULL)
    return;
  yt_media_request_free(&selection->video);
  yt_media_request_free(&selection->audio);
  free(selection->video_id);
  free(selection->title);
  free(selection->format_id);
  for (index = 0; index < selection->format_count; ++index)
    yt_format_info_free(&selection->formats[index]);
  free(selection->formats);
  memset(selection, 0, sizeof(*selection));
}

const char *yt_status_string(YTStatus status) {
  switch (status) {
  case YT_OK:
    return "success";
  case YT_ERR_INVALID_VIDEO_ID:
    return "invalid YouTube video ID";
  case YT_ERR_OUT_OF_MEMORY:
    return "out of memory";
  case YT_ERR_NETWORK:
    return "network request failed";
  case YT_ERR_CERTIFICATE_BUNDLE:
    return "CA certificate bundle is missing beside the executable";
  case YT_ERR_HTTP:
    return "HTTP request failed";
  case YT_ERR_INVALID_RESPONSE:
    return "invalid YouTube response";
  case YT_ERR_UNAVAILABLE:
    return "video unavailable";
  case YT_ERR_NO_PROGRESSIVE_MP4:
    return "no direct progressive MP4 available";
  case YT_ERR_EJS_ASSETS_MISSING:
    return "EJS assets missing; run: retro-dlp assets install";
  case YT_ERR_JS_CHALLENGE:
    return "JavaScript challenge resolution failed";
  case YT_ERR_FILE_EXISTS:
    return "destination or partial download already exists";
  case YT_ERR_STORAGE:
    return "download storage error";
  case YT_ERR_INVALID_MEDIA:
    return "download response is not an MP4 file";
  case YT_ERR_PO_TOKEN_REQUIRED:
    return "PO token required";
  case YT_ERR_COOKIE_FILE:
    return "invalid or unreadable Netscape cookie file";
  case YT_ERR_AUTH_COOKIES_INVALID:
    return "YouTube authentication cookies are missing, expired, or invalid";
  case YT_ERR_MUX:
    return "MP4 muxing failed";
  case YT_ERR_INVALID_FORMAT:
    return "invalid format expression";
  case YT_ERR_FORMAT_UNAVAILABLE:
    return "requested format is not available";
  case YT_ERR_INVALID_PLAYLIST:
    return "invalid or unsupported YouTube playlist URL";
  case YT_ERR_CANCELLED:
    return "operation cancelled";
  }
  return "unknown error";
}
