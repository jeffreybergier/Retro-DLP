#include "yt_formats.h"

#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "yt_challenges.h"
#include "yt_http.h"
#include "yt_util.h"

#define YT_USER_AGENT YT_INNERTUBE_DEFAULT_USER_AGENT

typedef struct {
  const char *url;
  const char *mime_type;
  char *owned_url;
  char *signature;
  char *signature_parameter;
  char *n_challenge;
  int itag;
  int width;
  int height;
  int fps;
  int bitrate;
  int audio_channels;
  int64_t content_length;
  int has_video;
  int has_audio;
  int is_drc;
} YTFormatCandidate;

typedef struct {
  int itags[2];
  int count;
} YTFormatAlternative;

#define YT_MAX_FORMAT_ALTERNATIVES 32
static int json_integer(cJSON *object, const char *name) {
  cJSON *value;
  value = cJSON_GetObjectItemCaseSensitive(object, name);
  return cJSON_IsNumber(value) ? value->valueint : 0;
}

static int64_t parse_decimal(const char *value) {
  int64_t result;
  if (value == NULL)
    return 0;
  result = 0;
  while (*value >= '0' && *value <= '9') {
    result = result * 10 + (*value - '0');
    ++value;
  }
  return result;
}

static int64_t url_query_integer(const char *url, const char *name) {
  size_t name_length;
  const char *cursor;

  name_length = strlen(name);
  cursor = strchr(url, '?');
  while (cursor != NULL) {
    ++cursor;
    if (strncmp(cursor, name, name_length) == 0 && cursor[name_length] == '=')
      return parse_decimal(cursor + name_length + 1);
    cursor = strchr(cursor, '&');
  }
  return 0;
}

static int url_has_query_parameter(const char *url, const char *name) {
  size_t name_length;
  const char *cursor;

  if (url == NULL || name == NULL)
    return 0;
  name_length = strlen(name);
  cursor = strchr(url, '?');
  while (cursor != NULL) {
    ++cursor;
    if (strncmp(cursor, name, name_length) == 0 && cursor[name_length] == '=')
      return 1;
    cursor = strchr(cursor, '&');
  }
  return 0;
}

static int hexadecimal_value(char value) {
  if (value >= '0' && value <= '9')
    return value - '0';
  if (value >= 'a' && value <= 'f')
    return value - 'a' + 10;
  if (value >= 'A' && value <= 'F')
    return value - 'A' + 10;
  return -1;
}

static char *percent_decode(const char *value, size_t length) {
  char *decoded;
  size_t source;
  size_t destination;
  decoded = (char *)malloc(length + 1);
  if (decoded == NULL)
    return NULL;
  destination = 0;
  for (source = 0; source < length; ++source) {
    if (value[source] == '%' && source + 2 < length) {
      int high = hexadecimal_value(value[source + 1]);
      int low = hexadecimal_value(value[source + 2]);
      if (high >= 0 && low >= 0) {
        decoded[destination++] = (char)((high << 4) | low);
        source += 2;
        continue;
      }
    }
    decoded[destination++] = value[source] == '+' ? ' ' : value[source];
  }
  decoded[destination] = '\0';
  return decoded;
}

static char *query_value(const char *query, const char *name) {
  size_t name_length;
  const char *cursor;
  const char *end;
  name_length = strlen(name);
  cursor = query;
  while (cursor != NULL && *cursor != '\0') {
    if (strncmp(cursor, name, name_length) == 0 && cursor[name_length] == '=') {
      cursor += name_length + 1;
      end = strchr(cursor, '&');
      if (end == NULL)
        end = cursor + strlen(cursor);
      return percent_decode(cursor, (size_t)(end - cursor));
    }
    cursor = strchr(cursor, '&');
    if (cursor != NULL)
      ++cursor;
  }
  return NULL;
}

static int query_safe_character(unsigned char value) {
  return isalnum(value) || value == '-' || value == '_' || value == '.' ||
         value == '~';
}

static char *percent_encode(const char *value) {
  static const char digits[] = "0123456789ABCDEF";
  size_t length;
  size_t index;
  size_t output_length;
  char *encoded;
  char *cursor;
  length = strlen(value);
  output_length = 0;
  for (index = 0; index < length; ++index)
    output_length += query_safe_character((unsigned char)value[index]) ? 1 : 3;
  encoded = (char *)malloc(output_length + 1);
  if (encoded == NULL)
    return NULL;
  cursor = encoded;
  for (index = 0; index < length; ++index) {
    unsigned char character = (unsigned char)value[index];
    if (query_safe_character(character)) {
      *cursor++ = (char)character;
    } else {
      *cursor++ = '%';
      *cursor++ = digits[character >> 4];
      *cursor++ = digits[character & 15];
    }
  }
  *cursor = '\0';
  return encoded;
}

static char *set_query_parameter(const char *url, const char *name,
                                 const char *value) {
  const char *query;
  const char *cursor;
  const char *parameter_start;
  const char *parameter_end;
  size_t name_length;
  char *encoded;
  char *result;
  size_t prefix_length;
  size_t suffix_length;
  size_t result_length;

  encoded = percent_encode(value);
  if (encoded == NULL)
    return NULL;
  query = strchr(url, '?');
  cursor = query == NULL ? NULL : query + 1;
  parameter_start = NULL;
  parameter_end = NULL;
  name_length = strlen(name);
  while (cursor != NULL && *cursor != '\0') {
    const char *end = strchr(cursor, '&');
    if (end == NULL)
      end = cursor + strlen(cursor);
    if ((size_t)(end - cursor) > name_length &&
        strncmp(cursor, name, name_length) == 0 && cursor[name_length] == '=') {
      parameter_start = cursor;
      parameter_end = end;
      break;
    }
    cursor = *end == '&' ? end + 1 : NULL;
  }
  if (parameter_start != NULL) {
    prefix_length = (size_t)(parameter_start - url) + name_length + 1;
    suffix_length = strlen(parameter_end);
    result_length = prefix_length + strlen(encoded) + suffix_length;
    result = (char *)malloc(result_length + 1);
    if (result != NULL) {
      memcpy(result, url, prefix_length);
      memcpy(result + prefix_length, encoded, strlen(encoded));
      memcpy(result + prefix_length + strlen(encoded), parameter_end,
             suffix_length + 1);
    }
  } else {
    prefix_length = strlen(url);
    result_length = prefix_length + 1 + name_length + 1 + strlen(encoded);
    result = (char *)malloc(result_length + 1);
    if (result != NULL)
      snprintf(result, result_length + 1, "%s%c%s=%s", url,
               query == NULL ? '?' : '&', name, encoded);
  }
  free(encoded);
  return result;
}

static void format_candidate_free(YTFormatCandidate *candidate) {
  free(candidate->owned_url);
  free(candidate->signature);
  free(candidate->signature_parameter);
  free(candidate->n_challenge);
  memset(candidate, 0, sizeof(*candidate));
}

static int mime_has_codec(const char *mime_type, const char *codec);

static int candidate_is_better(const YTFormatCandidate *current,
                               const YTFormatCandidate *candidate) {
  int current_is_direct;
  int candidate_is_direct;
  if (candidate->url == NULL || current->height > candidate->height)
    return 1;
  if (current->height != candidate->height)
    return 0;
  current_is_direct = current->signature == NULL &&
                      current->n_challenge == NULL;
  candidate_is_direct = candidate->signature == NULL &&
                        candidate->n_challenge == NULL;
  return current_is_direct && !candidate_is_direct;
}

static int read_format_candidate(cJSON *format, YTFormatCandidate *candidate) {
  const char *cipher;
  const char *url;
  const char *content_length;

  memset(candidate, 0, sizeof(*candidate));
  candidate->itag = json_integer(format, "itag");
  candidate->mime_type = yt_json_string(format, "mimeType");
  if (candidate->itag <= 0 || candidate->mime_type == NULL)
    return 0;
  url = yt_json_string(format, "url");
  cipher = yt_json_string(format, "signatureCipher");
  candidate->signature = query_value(cipher, "s");
  candidate->signature_parameter = query_value(cipher, "sp");
  candidate->owned_url = query_value(cipher, "url");
  if (cipher != NULL && candidate->signature == NULL) {
    format_candidate_free(candidate);
    return 0;
  }
  if (candidate->owned_url != NULL)
    url = candidate->owned_url;
  if (url == NULL) {
    format_candidate_free(candidate);
    return 0;
  }
  candidate->n_challenge = query_value(
      strchr(url, '?') == NULL ? "" : strchr(url, '?') + 1, "n");
  candidate->url = url;
  candidate->width = json_integer(format, "width");
  candidate->height = json_integer(format, "height");
  candidate->fps = json_integer(format, "fps");
  candidate->bitrate = json_integer(format, "bitrate");
  candidate->audio_channels = json_integer(format, "audioChannels");
  candidate->is_drc = cJSON_IsTrue(
      cJSON_GetObjectItemCaseSensitive(format, "isDrc"));
  content_length = yt_json_string(format, "contentLength");
  candidate->content_length = parse_decimal(content_length);
  return 1;
}

static int candidate_supported(const YTFormatCandidate *candidate) {
  if (candidate->has_video && candidate->has_audio)
    return strncmp(candidate->mime_type, "video/mp4", 9) == 0 &&
           mime_has_codec(candidate->mime_type, "avc1.") &&
           mime_has_codec(candidate->mime_type, "mp4a.40.2");
  if (candidate->has_video)
    return strncmp(candidate->mime_type, "video/mp4", 9) == 0 &&
           mime_has_codec(candidate->mime_type, "avc1.");
  if (candidate->has_audio)
    return strncmp(candidate->mime_type, "audio/mp4", 9) == 0 &&
           (mime_has_codec(candidate->mime_type, "mp4a.40.2") ||
            mime_has_codec(candidate->mime_type, "mp4a.40.5")) &&
           candidate->audio_channels <= 2;
  return 0;
}

static int parse_format_expression(const char *expression,
                                   YTFormatAlternative *alternatives,
                                   size_t *alternative_count) {
  const char *cursor;
  char *end;
  long value;
  size_t count;
  int item_count;
  if (expression == NULL || expression[0] == '\0')
    return 0;
  cursor = expression;
  count = 0;
  while (*cursor != '\0') {
    if (count == YT_MAX_FORMAT_ALTERNATIVES)
      return 0;
    item_count = 0;
    while (1) {
      if (!isdigit((unsigned char)*cursor))
        return 0;
      value = strtol(cursor, &end, 10);
      if (end == cursor || value <= 0 || value > INT_MAX)
        return 0;
      alternatives[count].itags[item_count++] = (int)value;
      cursor = end;
      if (*cursor != '+')
        break;
      if (item_count == 2)
        return 0;
      ++cursor;
    }
    alternatives[count].count = item_count;
    ++count;
    if (*cursor == '\0')
      break;
    if (*cursor != '/')
      return 0;
    ++cursor;
    if (*cursor == '\0')
      return 0;
  }
  *alternative_count = count;
  return 1;
}

int yt_format_expression_valid(const char *expression) {
  YTFormatAlternative alternatives[YT_MAX_FORMAT_ALTERNATIVES];
  size_t count;
  return parse_format_expression(expression, alternatives, &count);
}

static int add_format_info(YTMediaSelection *result,
                           const YTFormatCandidate *candidate) {
  YTFormatInfo *resized;
  YTFormatInfo *info;
  size_t new_count;
  size_t index;
  for (index = 0; index < result->format_count; ++index) {
    info = &result->formats[index];
    if (info->itag == candidate->itag &&
        info->has_video == candidate->has_video &&
        info->has_audio == candidate->has_audio &&
        strcmp(info->mime_type, candidate->mime_type) == 0) {
      if (info->is_drc && !candidate->is_drc)
        info->is_drc = 0;
      return 1;
    }
  }
  if (result->format_count == (size_t)-1)
    return 0;
  new_count = result->format_count + 1;
  resized = (YTFormatInfo *)realloc(result->formats,
                                    new_count * sizeof(*result->formats));
  if (resized == NULL)
    return 0;
  result->formats = resized;
  info = &result->formats[result->format_count];
  memset(info, 0, sizeof(*info));
  info->mime_type = yt_copy_string(candidate->mime_type);
  if (info->mime_type == NULL)
    return 0;
  info->itag = candidate->itag;
  info->width = candidate->width;
  info->height = candidate->height;
  info->fps = candidate->fps;
  info->bitrate = candidate->bitrate;
  info->audio_channels = candidate->audio_channels;
  info->content_length = candidate->content_length;
  info->has_video = candidate->has_video;
  info->has_audio = candidate->has_audio;
  info->supported = candidate_supported(candidate);
  info->is_drc = candidate->is_drc;
  result->format_count = new_count;
  return 1;
}

static int format_type_rank(const YTFormatInfo *format) {
  if (format->has_video && format->has_audio)
    return 0;
  if (format->has_video)
    return 1;
  return 2;
}

static int format_container_rank(const YTFormatInfo *format) {
  if (strncmp(format->mime_type, "video/mp4", 9) == 0 ||
      strncmp(format->mime_type, "audio/mp4", 9) == 0)
    return 0;
  if (strncmp(format->mime_type, "video/webm", 10) == 0 ||
      strncmp(format->mime_type, "audio/webm", 10) == 0)
    return 1;
  return 2;
}

static int compare_format_info(const void *left_value,
                               const void *right_value) {
  const YTFormatInfo *left = (const YTFormatInfo *)left_value;
  const YTFormatInfo *right = (const YTFormatInfo *)right_value;
  int left_type;
  int right_type;
  int left_container;
  int right_container;
  if (left->supported != right->supported)
    return left->supported ? -1 : 1;
  left_type = format_type_rank(left);
  right_type = format_type_rank(right);
  if (left_type != right_type)
    return left_type < right_type ? -1 : 1;
  left_container = format_container_rank(left);
  right_container = format_container_rank(right);
  if (left_container != right_container)
    return left_container < right_container ? -1 : 1;
  if (left->width != right->width)
    return left->width < right->width ? -1 : 1;
  if (left->itag != right->itag)
    return left->itag < right->itag ? -1 : 1;
  return 0;
}

static YTStatus collect_format_inventory(cJSON *document,
                                         YTMediaSelection *result) {
  cJSON *streaming_data;
  cJSON *array;
  cJSON *format;
  YTFormatCandidate candidate;
  int adaptive;
  streaming_data = cJSON_GetObjectItemCaseSensitive(document, "streamingData");
  for (adaptive = 0; adaptive <= 1; ++adaptive) {
    array = cJSON_GetObjectItemCaseSensitive(
        streaming_data, adaptive ? "adaptiveFormats" : "formats");
    if (!cJSON_IsArray(array))
      continue;
    cJSON_ArrayForEach(format, array) {
      if (!read_format_candidate(format, &candidate))
        continue;
      if (adaptive) {
        candidate.has_video = strncmp(candidate.mime_type, "video/", 6) == 0;
        candidate.has_audio = strncmp(candidate.mime_type, "audio/", 6) == 0;
      } else {
        candidate.has_video = 1;
        candidate.has_audio = 1;
      }
      if (!add_format_info(result, &candidate)) {
        format_candidate_free(&candidate);
        return YT_ERR_OUT_OF_MEMORY;
      }
      format_candidate_free(&candidate);
    }
  }
  if (result->format_count == 0)
    return YT_ERR_NO_PROGRESSIVE_MP4;
  qsort(result->formats, result->format_count, sizeof(*result->formats),
        compare_format_info);
  return YT_OK;
}

static YTStatus inspect_progressive_mp4(cJSON *document, int max_height,
                                        YTFormatCandidate *candidate) {
  cJSON *streaming_data;
  cJSON *formats;
  cJSON *format;
  YTFormatCandidate current;

  if (max_height <= 0)
    return YT_ERR_INVALID_RESPONSE;
  memset(candidate, 0, sizeof(*candidate));
  streaming_data = cJSON_GetObjectItemCaseSensitive(document, "streamingData");
  formats = cJSON_GetObjectItemCaseSensitive(streaming_data, "formats");
  if (!cJSON_IsArray(formats))
    return YT_ERR_NO_PROGRESSIVE_MP4;

  cJSON_ArrayForEach(format, formats) {
    if (!read_format_candidate(format, &current) ||
        strncmp(current.mime_type, "video/mp4", 9) != 0) {
      format_candidate_free(&current);
      continue;
    }
    if (current.height <= 0 || current.height > max_height) {
      format_candidate_free(&current);
      continue;
    }
    if (candidate_is_better(&current, candidate)) {
      format_candidate_free(candidate);
      *candidate = current;
    } else {
      format_candidate_free(&current);
    }
  }
  return candidate->url == NULL ? YT_ERR_NO_PROGRESSIVE_MP4 : YT_OK;
}

static int mime_has_codec(const char *mime_type, const char *codec) {
  const char *codecs;
  if (mime_type == NULL || codec == NULL)
    return 0;
  codecs = strstr(mime_type, "codecs=\"");
  return codecs != NULL && strstr(codecs + 8, codec) != NULL;
}

static int adaptive_video_is_better(const YTFormatCandidate *candidate,
                                    const YTFormatCandidate *selected) {
  if (selected->url == NULL || candidate->height != selected->height)
    return selected->url == NULL || candidate->height > selected->height;
  if (candidate->width != selected->width)
    return candidate->width > selected->width;
  return candidate->bitrate > selected->bitrate;
}

static int adaptive_audio_is_better(const YTFormatCandidate *candidate,
                                    const YTFormatCandidate *selected) {
  return selected->url == NULL || candidate->bitrate > selected->bitrate;
}

static YTStatus inspect_adaptive_mp4(cJSON *document, int max_height,
                                     YTFormatCandidate *video,
                                     YTFormatCandidate *audio) {
  cJSON *streaming_data;
  cJSON *formats;
  cJSON *format;
  YTFormatCandidate current;

  if (max_height != 720 && max_height != 1080)
    return YT_ERR_INVALID_RESPONSE;
  memset(video, 0, sizeof(*video));
  memset(audio, 0, sizeof(*audio));
  streaming_data = cJSON_GetObjectItemCaseSensitive(document, "streamingData");
  formats = cJSON_GetObjectItemCaseSensitive(streaming_data, "adaptiveFormats");
  if (!cJSON_IsArray(formats))
    return YT_ERR_NO_PROGRESSIVE_MP4;

  cJSON_ArrayForEach(format, formats) {
    if (!read_format_candidate(format, &current))
      continue;
    if (strncmp(current.mime_type, "video/mp4", 9) == 0 &&
        mime_has_codec(current.mime_type, "avc1.") && current.height > 0 &&
        current.height <= max_height && current.fps <= 30) {
      if (adaptive_video_is_better(&current, video)) {
        format_candidate_free(video);
        *video = current;
      } else {
        format_candidate_free(&current);
      }
    } else if (strncmp(current.mime_type, "audio/mp4", 9) == 0 &&
               mime_has_codec(current.mime_type, "mp4a.40.2") &&
               current.audio_channels <= 2) {
      if (adaptive_audio_is_better(&current, audio)) {
        format_candidate_free(audio);
        *audio = current;
      } else {
        format_candidate_free(&current);
      }
    } else {
      format_candidate_free(&current);
    }
  }
  if (video->url != NULL && audio->url != NULL)
    return YT_OK;
  format_candidate_free(video);
  format_candidate_free(audio);
  return YT_ERR_NO_PROGRESSIVE_MP4;
}

static YTStatus finish_candidate(const YTFormatCandidate *candidate,
                                 const char *url, const YTInnertubeClient *client,
                                 YTMediaRequest *result) {
  result->url = yt_copy_string(url);
  result->mime_type = yt_copy_string(candidate->mime_type);
  result->user_agent = yt_copy_string(client == NULL ? YT_USER_AGENT :
                                                    client->user_agent);
  if (result->url == NULL || result->mime_type == NULL ||
      result->user_agent == NULL) {
    yt_media_request_free(result);
    return YT_ERR_OUT_OF_MEMORY;
  }
  result->itag = candidate->itag;
  result->width = candidate->width;
  result->height = candidate->height;
  result->fps = candidate->fps;
  result->bitrate = candidate->bitrate;
  result->audio_channels = candidate->audio_channels;
  result->expires_unix = url_query_integer(url, "expire");
  result->content_length = candidate->content_length;
  return YT_OK;
}

static YTStatus solve_candidates(YTHttpSession *session,
                                 YTFormatCandidate *candidates,
                                 size_t candidate_count,
                                 const char *player_source,
                                 const YTInnertubeClient *client,
                                 YTMediaRequest *results) {
  const char *signature_challenges[2];
  const char *n_challenges[2];
  size_t signature_solutions[2];
  size_t n_solutions[2];
  YTEJSRequest requests[2];
  size_t request_count;
  size_t signature_index;
  size_t n_index;
  size_t signature_count;
  size_t n_count;
  size_t index;
  YTEJSResult solved;
  YTStatus status;

  if (candidate_count == 0 || candidate_count > 2)
    return YT_ERR_INVALID_RESPONSE;
  signature_count = 0;
  n_count = 0;
  for (index = 0; index < candidate_count; ++index) {
    memset(&results[index], 0, sizeof(results[index]));
    signature_solutions[index] = (size_t)-1;
    n_solutions[index] = (size_t)-1;
    if (candidates[index].signature != NULL) {
      signature_solutions[index] = signature_count;
      signature_challenges[signature_count++] = candidates[index].signature;
    }
    if (candidates[index].n_challenge != NULL) {
      n_solutions[index] = n_count;
      n_challenges[n_count++] = candidates[index].n_challenge;
    }
  }
  if (signature_count == 0 && n_count == 0) {
    for (index = 0; index < candidate_count; ++index) {
      status = finish_candidate(&candidates[index], candidates[index].url,
                                client, &results[index]);
      if (status != YT_OK)
        goto failed_results;
    }
    return YT_OK;
  }
  if (player_source == NULL)
    return YT_ERR_JS_CHALLENGE;
  request_count = 0;
  signature_index = (size_t)-1;
  n_index = (size_t)-1;
  if (signature_count != 0) {
    signature_index = request_count;
    requests[request_count].type = YT_EJS_CHALLENGE_SIGNATURE;
    requests[request_count].challenges = signature_challenges;
    requests[request_count].challenge_count = signature_count;
    ++request_count;
  }
  if (n_count != 0) {
    n_index = request_count;
    requests[request_count].type = YT_EJS_CHALLENGE_N;
    requests[request_count].challenges = n_challenges;
    requests[request_count].challenge_count = n_count;
    ++request_count;
  }
  status = yt_challenges_solve(session, player_source, requests,
                               request_count, &solved);
  if (status != YT_OK)
    return status;
  status = YT_OK;
  if (solved.responses == NULL || solved.response_count != request_count ||
      (signature_index != (size_t)-1 &&
       (solved.responses[signature_index].error != NULL ||
        solved.responses[signature_index].solution_count != signature_count)) ||
      (n_index != (size_t)-1 &&
       (solved.responses[n_index].error != NULL ||
        solved.responses[n_index].solution_count != n_count)))
    status = YT_ERR_JS_CHALLENGE;
  for (index = 0; status == YT_OK && index < candidate_count; ++index) {
    YTFormatCandidate *candidate = &candidates[index];
    char *url = yt_copy_string(candidate->url);
    char *updated;
    char *remaining_n;
    if (url == NULL) {
      status = YT_ERR_OUT_OF_MEMORY;
      break;
    }
    if (signature_solutions[index] != (size_t)-1) {
      updated = set_query_parameter(
          url,
          candidate->signature_parameter == NULL ||
                  candidate->signature_parameter[0] == '\0'
              ? "signature"
              : candidate->signature_parameter,
          solved.responses[signature_index]
              .solutions[signature_solutions[index]]);
      free(url);
      url = updated;
    }
    if (url != NULL && n_solutions[index] != (size_t)-1) {
      updated = set_query_parameter(
          url, "n", solved.responses[n_index].solutions[n_solutions[index]]);
      free(url);
      url = updated;
    }
    if (url == NULL) {
      status = YT_ERR_OUT_OF_MEMORY;
      break;
    }
    remaining_n = query_value(
        strchr(url, '?') == NULL ? "" : strchr(url, '?') + 1, "n");
    if (url_has_query_parameter(url, "s") ||
        (candidate->n_challenge != NULL && remaining_n != NULL &&
         strcmp(remaining_n, candidate->n_challenge) == 0))
      status = YT_ERR_JS_CHALLENGE;
    free(remaining_n);
    if (status == YT_OK)
      status = finish_candidate(candidate, url, client, &results[index]);
    free(url);
  }
  yt_challenges_result_free(&solved);
  if (status != YT_OK)
    goto failed_results;
  return status;

failed_results:
  for (index = 0; index < candidate_count; ++index)
    yt_media_request_free(&results[index]);
  return status;
}

static YTStatus solve_candidate(YTHttpSession *session,
                                YTFormatCandidate *candidate,
                                const char *player_source,
                                const YTInnertubeClient *client,
                                YTMediaRequest *result) {
  return solve_candidates(session, candidate, 1, player_source, client,
                          result);
}

static int exact_candidate_is_better(const YTFormatCandidate *candidate,
                                     const YTFormatCandidate *selected) {
  int candidate_direct;
  int selected_direct;
  if (selected->url == NULL)
    return 1;
  if (candidate->is_drc != selected->is_drc)
    return !candidate->is_drc;
  candidate_direct = candidate->signature == NULL &&
                     candidate->n_challenge == NULL;
  selected_direct = selected->signature == NULL &&
                    selected->n_challenge == NULL;
  if (candidate_direct != selected_direct)
    return candidate_direct;
  return candidate->bitrate > selected->bitrate;
}

static YTStatus find_exact_candidate(cJSON *document, int itag,
                                     int want_video, int want_audio,
                                     YTFormatCandidate *selected) {
  cJSON *streaming_data;
  cJSON *array;
  cJSON *format;
  YTFormatCandidate candidate;
  int adaptive;
  memset(selected, 0, sizeof(*selected));
  streaming_data = cJSON_GetObjectItemCaseSensitive(document, "streamingData");
  for (adaptive = 0; adaptive <= 1; ++adaptive) {
    array = cJSON_GetObjectItemCaseSensitive(
        streaming_data, adaptive ? "adaptiveFormats" : "formats");
    if (!cJSON_IsArray(array))
      continue;
    cJSON_ArrayForEach(format, array) {
      if (json_integer(format, "itag") != itag ||
          !read_format_candidate(format, &candidate))
        continue;
      if (adaptive) {
        candidate.has_video = strncmp(candidate.mime_type, "video/", 6) == 0;
        candidate.has_audio = strncmp(candidate.mime_type, "audio/", 6) == 0;
      } else {
        candidate.has_video = 1;
        candidate.has_audio = 1;
      }
      if (candidate.has_video != want_video ||
          candidate.has_audio != want_audio ||
          !candidate_supported(&candidate)) {
        format_candidate_free(&candidate);
        continue;
      }
      if (exact_candidate_is_better(&candidate, selected)) {
        format_candidate_free(selected);
        *selected = candidate;
      } else {
        format_candidate_free(&candidate);
      }
    }
  }
  return selected->url == NULL ? YT_ERR_FORMAT_UNAVAILABLE : YT_OK;
}

static char *selection_format_id(const YTFormatAlternative *alternative) {
  char buffer[64];
  if (alternative->count == 1)
    snprintf(buffer, sizeof(buffer), "%d", alternative->itags[0]);
  else
    snprintf(buffer, sizeof(buffer), "%d+%d", alternative->itags[0],
             alternative->itags[1]);
  return yt_copy_string(buffer);
}

YTStatus yt_formats_select_exact(
    YTHttpSession *session, cJSON *document, const char *player_source,
    const YTInnertubeClient *client,
    const char *format_expression, YTMediaSelection *result) {
  YTFormatAlternative alternatives[YT_MAX_FORMAT_ALTERNATIVES];
  size_t alternative_count;
  size_t index;
  YTFormatCandidate candidates[2];
  YTMediaRequest solved[2];
  YTStatus status;
  if (!parse_format_expression(format_expression, alternatives,
                               &alternative_count))
    return YT_ERR_INVALID_FORMAT;
  for (index = 0; index < alternative_count; ++index) {
    memset(candidates, 0, sizeof(candidates));
    if (alternatives[index].count == 1) {
      status = find_exact_candidate(document, alternatives[index].itags[0],
                                    1, 1, &candidates[0]);
      if (status != YT_OK)
        continue;
      status = solve_candidate(session, &candidates[0], player_source, client,
                               &result->video);
      format_candidate_free(&candidates[0]);
      if (status != YT_OK)
        return status;
      result->format_id = selection_format_id(&alternatives[index]);
      if (result->format_id == NULL) {
        yt_media_request_free(&result->video);
        return YT_ERR_OUT_OF_MEMORY;
      }
      return YT_OK;
    }
    status = find_exact_candidate(document, alternatives[index].itags[0],
                                  1, 0, &candidates[0]);
    if (status == YT_OK)
      status = find_exact_candidate(document, alternatives[index].itags[1],
                                    0, 1, &candidates[1]);
    if (status != YT_OK) {
      format_candidate_free(&candidates[0]);
      format_candidate_free(&candidates[1]);
      status = find_exact_candidate(document, alternatives[index].itags[1],
                                    1, 0, &candidates[0]);
      if (status == YT_OK)
        status = find_exact_candidate(document, alternatives[index].itags[0],
                                      0, 1, &candidates[1]);
    }
    if (status != YT_OK) {
      format_candidate_free(&candidates[0]);
      format_candidate_free(&candidates[1]);
      continue;
    }
    memset(solved, 0, sizeof(solved));
    status = solve_candidates(session, candidates, 2, player_source, client,
                              solved);
    format_candidate_free(&candidates[0]);
    format_candidate_free(&candidates[1]);
    if (status != YT_OK)
      return status;
    result->video = solved[0];
    result->audio = solved[1];
    result->adaptive = 1;
    result->format_id = selection_format_id(&alternatives[index]);
    if (result->format_id == NULL) {
      yt_media_request_free(&result->video);
      yt_media_request_free(&result->audio);
      return YT_ERR_OUT_OF_MEMORY;
    }
    return YT_OK;
  }
  return YT_ERR_FORMAT_UNAVAILABLE;
}

YTStatus yt_formats_attach_metadata(cJSON *document, const char *video_id,
                                      YTMediaSelection *result) {
  cJSON *details;
  const char *title;
  result->video_id = yt_copy_string(video_id);
  details = cJSON_GetObjectItemCaseSensitive(document, "videoDetails");
  title = yt_json_string(details, "title");
  result->title = yt_copy_string(title == NULL ? "" : title);
  if (result->video_id == NULL || result->title == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  return collect_format_inventory(document, result);
}

static YTStatus parse_player_document(YTHttpSession *session, cJSON *document,
                                      const char *player_source,
                                      const YTInnertubeClient *client, int max_height,
                                      YTMediaRequest *result) {
  cJSON *playability;
  const char *playability_status;

  if (document == NULL || result == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  playability = cJSON_GetObjectItemCaseSensitive(document,
                                                 "playabilityStatus");
  playability_status = yt_json_string(playability, "status");
  if (playability_status == NULL || strcmp(playability_status, "OK") != 0)
    return YT_ERR_UNAVAILABLE;
  {
    YTFormatCandidate candidate;
    YTStatus status = inspect_progressive_mp4(document, max_height, &candidate);
    if (status != YT_OK)
      return status;
    status = solve_candidate(session, &candidate, player_source, client,
                             result);
    format_candidate_free(&candidate);
    return status;
  }
}

YTStatus yt_formats_select(
    YTHttpSession *session, cJSON *document, const char *player_source,
    const YTInnertubeClient *client,
    int max_height, int try_adaptive, YTMediaSelection *result) {
  cJSON *playability;
  const char *playability_status;
  YTStatus status;

  if (document == NULL || result == NULL ||
      (try_adaptive && max_height != 720 && max_height != 1080))
    return YT_ERR_INVALID_RESPONSE;
  /* Metadata and format inventory may already have been attached by the
     resolver facade. Only reset the stream portion before (re)selection. */
  yt_media_request_free(&result->video);
  yt_media_request_free(&result->audio);
  result->adaptive = 0;
  playability = cJSON_GetObjectItemCaseSensitive(document,
                                                 "playabilityStatus");
  playability_status = yt_json_string(playability, "status");
  if (playability_status == NULL || strcmp(playability_status, "OK") != 0)
    return YT_ERR_UNAVAILABLE;

  if (try_adaptive) {
    YTFormatCandidate candidates[2];
    YTMediaRequest solved[2];
    status = inspect_adaptive_mp4(document, max_height, &candidates[0],
                                  &candidates[1]);
    if (status == YT_OK) {
      memset(solved, 0, sizeof(solved));
      status = solve_candidates(session, candidates, 2, player_source, client,
                                solved);
      format_candidate_free(&candidates[0]);
      format_candidate_free(&candidates[1]);
      if (status == YT_OK) {
        result->video = solved[0];
        result->audio = solved[1];
        result->adaptive = 1;
        return YT_OK;
      }
      if (status == YT_ERR_JS_CHALLENGE && player_source == NULL)
        return status;
      if (status == YT_ERR_OUT_OF_MEMORY)
        return status;
    }
  }

  status = parse_player_document(session, document, player_source, client,
                                 max_height, &result->video);
  return status;
}

YTStatus yt_parse_player_response(const char *json, size_t length,
                                  YTMediaRequest *result) {
  return yt_parse_player_response_with_max_height(
      json, length, YT_DEFAULT_MAX_HEIGHT, result);
}

YTStatus yt_parse_player_response_with_max_height(const char *json,
                                                  size_t length,
                                                  int max_height,
                                                  YTMediaRequest *result) {
  cJSON *document;
  YTStatus status;

  if (json == NULL || result == NULL || max_height <= 0)
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  status = parse_player_document(NULL, document, NULL, NULL, max_height,
                                 result);
  if (status == YT_ERR_JS_CHALLENGE)
    status = YT_ERR_NO_PROGRESSIVE_MP4;
  cJSON_Delete(document);
  return status;
}

YTStatus yt_parse_player_response_with_adaptive_size(
    const char *json, size_t length, int max_height,
    YTMediaSelection *result) {
  cJSON *document;
  YTStatus status;
  if (json == NULL || result == NULL ||
      (max_height != 720 && max_height != 1080))
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  status = yt_formats_select(NULL, document, NULL, NULL,
                                           max_height, 1, result);
  if (status == YT_ERR_JS_CHALLENGE)
    status = YT_ERR_NO_PROGRESSIVE_MP4;
  cJSON_Delete(document);
  return status;
}

YTStatus yt_parse_player_response_with_format(const char *json, size_t length,
                                              const char *format_expression,
                                              YTMediaSelection *result) {
  cJSON *document;
  cJSON *details;
  const char *video_id;
  YTStatus status;
  if (json == NULL || result == NULL ||
      !yt_format_expression_valid(format_expression))
    return YT_ERR_INVALID_FORMAT;
  memset(result, 0, sizeof(*result));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  details = cJSON_GetObjectItemCaseSensitive(document, "videoDetails");
  video_id = yt_json_string(details, "videoId");
  status = yt_formats_attach_metadata(document, video_id == NULL ? "" : video_id,
                                 result);
  if (status == YT_OK)
    status = yt_formats_select_exact(NULL, document, NULL, NULL,
                                            format_expression, result);
  cJSON_Delete(document);
  return status;
}

YTStatus yt_parse_player_response_with_javascript(const char *json,
                                                  size_t length,
                                                  const char *player_source,
                                                  YTMediaRequest *result) {
  cJSON *document;
  YTStatus status;
  if (json == NULL || player_source == NULL || result == NULL)
    return YT_ERR_INVALID_RESPONSE;
  memset(result, 0, sizeof(*result));
  document = cJSON_ParseWithLength(json, length);
  if (document == NULL)
    return YT_ERR_INVALID_RESPONSE;
  status = parse_player_document(NULL, document, player_source, NULL,
                                 YT_DEFAULT_MAX_HEIGHT, result);
  cJSON_Delete(document);
  return status;
}
