#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "cJSON.h"
#include "cli_render.h"
#include "retrodlp/retrodlp.h"
#include "playlist_metadata_fixtures.h"
#include "yt_playlist_internal.h"

/* Transport rejects every request outside the pre-existing listing sequence. */
typedef struct {
  unsigned requests;
  int fallback;
  int absent;
  int invalid_request;
} MetadataFixture;

static rdlp_error_code metadata_send(void *opaque,
    const rdlp_transport_request *request, rdlp_transport_response *response,
    rdlp_error *error) {
  MetadataFixture *fixture = (MetadataFixture *)opaque;
  const char *data = NULL;
  cJSON *body;
  cJSON *field;
  int valid;
  (void)error;
  ++fixture->requests;
  if (fixture->requests == 1) {
    valid = request->method == RDLP_HTTP_GET &&
        strcmp(request->url,
               "https://www.youtube.com/playlist?list=PL_metadata&hl=en") == 0;
    if (valid)
      data = fixture->absent ? playlist_metadata_absent_bootstrap
                             : playlist_metadata_browse_bootstrap;
  } else if (fixture->requests <= 3 &&
             request->method == RDLP_HTTP_POST &&
             strstr(request->url, "https://www.youtube.com/youtubei/v1/browse?")
                 == request->url) {
    body = cJSON_ParseWithLength(request->body, request->body_length);
    field = cJSON_GetObjectItemCaseSensitive(body,
        fixture->requests == 2 ? "browseId" : "continuation");
    valid = cJSON_IsString(field) &&
        strcmp(field->valuestring, fixture->requests == 2
                   ? "VLPL_metadata" : "metadata-page-two") == 0;
    if (valid && fixture->requests == 2)
      valid = !cJSON_HasObjectItem(body, "continuation");
    if (valid && fixture->requests == 3)
      valid = !cJSON_HasObjectItem(body, "browseId");
    cJSON_Delete(body);
    if (valid && fixture->requests == 2) {
      response->http_status = fixture->fallback ? 503 : 200;
      data = fixture->absent ? playlist_metadata_absent : playlist_metadata_browse;
    } else if (valid) {
      data = fixture->absent ? playlist_metadata_absent_continuation
                             : playlist_metadata_continuation;
    }
  }
  if (data == NULL) {
    fixture->invalid_request = 1;
    return RDLP_ERROR_TRANSPORT_REQUEST_FAILED;
  }
  if (response->http_status == 0)
    response->http_status = 200;
  response->data = data;
  response->data_length = strlen(data);
  return RDLP_OK;
}

static int equal(const char *actual, const char *expected) {
  return actual != NULL && strcmp(actual, expected) == 0;
}

static int check_api(const rdlp_playlist *playlist, int absent) {
  uint64_t value = 999;
  size_t count = rdlp_playlist_entry_count(playlist);
  size_t index;
  if (count != (absent ? 2U : 10U) ||
      rdlp_playlist_entry_channel(NULL, 0) != NULL ||
      rdlp_playlist_entry_thumbnail_count(NULL, 0) != 0 ||
      rdlp_playlist_entry_thumbnail_url(playlist, count, 0) != NULL ||
      rdlp_playlist_entry_duration(playlist, count, &value) || value != 999 ||
      rdlp_playlist_entry_view_count(NULL, 0, &value) || value != 999 ||
      rdlp_playlist_entry_duration(playlist, 0, NULL))
    return 0;
  for (index = 0; index < count; ++index) {
    if (rdlp_playlist_entry_index(playlist, index) != index + 1)
      return 0;
  }
  if (!equal(rdlp_playlist_entry_video_id(playlist, 0), "AAAAAAAAAAA") ||
      !equal(rdlp_playlist_entry_video_id(playlist, 1), "AAAAAAAAAAA"))
    return 0;
  if (rdlp_playlist_entry_channel(playlist, 1) != NULL ||
      rdlp_playlist_entry_channel_id(playlist, 1) != NULL ||
      rdlp_playlist_entry_description_snippet(playlist, 1) != NULL ||
      rdlp_playlist_entry_published_text(playlist, 1) != NULL ||
      rdlp_playlist_entry_view_count_text(playlist, 1) != NULL ||
      rdlp_playlist_entry_thumbnail_count(playlist, 1) != 0 ||
      rdlp_playlist_entry_duration(playlist, 1, &value) || value != 999 ||
      rdlp_playlist_entry_view_count(playlist, 1, &value) || value != 999)
    return 0;
  if (absent)
    return 1;
  if (!equal(rdlp_playlist_entry_title(playlist, 0), "A rich title") ||
      !equal(rdlp_playlist_entry_channel(playlist, 0), "The channel") ||
      !equal(rdlp_playlist_entry_channel_id(playlist, 0), "UC_fixture") ||
      !equal(rdlp_playlist_entry_description_snippet(playlist, 0), "Hello world…") ||
      !equal(rdlp_playlist_entry_published_text(playlist, 0), "2 days ago") ||
      !equal(rdlp_playlist_entry_view_count_text(playlist, 0), "1,234 views") ||
      !rdlp_playlist_entry_view_count(playlist, 0, &value) || value != 1234 ||
      !rdlp_playlist_entry_duration(playlist, 0, &value) || value != 62 ||
      rdlp_playlist_entry_thumbnail_count(playlist, 0) != 2 ||
      !equal(rdlp_playlist_entry_thumbnail_url(playlist, 0, 1),
             "https://img.example/large.jpg") ||
      rdlp_playlist_entry_thumbnail_url(playlist, 0, 2) != NULL ||
      !rdlp_playlist_entry_duration(playlist, 2, &value) || value != 0 ||
      !rdlp_playlist_entry_view_count(playlist, 2, &value) || value != 0 ||
      rdlp_playlist_entry_duration(playlist, 3, &value) ||
      rdlp_playlist_entry_view_count(playlist, 3, &value) ||
      rdlp_playlist_entry_published_text(playlist, 3) != NULL ||
      rdlp_playlist_entry_description_snippet(playlist, 3) != NULL ||
      rdlp_playlist_entry_thumbnail_count(playlist, 3) != 0 ||
      !rdlp_playlist_entry_duration(playlist, 4, &value) || value != 3723 ||
      !equal(rdlp_playlist_entry_channel(playlist, 4), "Owner only") ||
      !equal(rdlp_playlist_entry_description_snippet(playlist, 4), "Detailed snippet") ||
      !equal(rdlp_playlist_entry_view_count_text(playlist, 4), "1.2M views") ||
      !equal(rdlp_playlist_entry_published_text(playlist, 4), "10 years ago") ||
      rdlp_playlist_entry_view_count(playlist, 4, &value))
    return 0;
  for (index = 5; index <= 7; ++index) {
    if (rdlp_playlist_entry_duration(playlist, index, &value) ||
        rdlp_playlist_entry_view_count(playlist, index, &value))
      return 0;
  }
  return equal(rdlp_playlist_entry_channel(playlist, 8), "Lockup Channel") &&
      equal(rdlp_playlist_entry_channel_id(playlist, 8), "UC_lockup") &&
      equal(rdlp_playlist_entry_title(playlist, 8), "Lockup title") &&
      equal(rdlp_playlist_entry_published_text(playlist, 8), "3 weeks ago") &&
      rdlp_playlist_entry_duration(playlist, 8, &value) && value == 123 &&
      rdlp_playlist_entry_view_count(playlist, 8, &value) && value == 12345 &&
      rdlp_playlist_entry_thumbnail_count(playlist, 8) == 1 &&
      !rdlp_playlist_entry_duration(playlist, 9, &value) &&
      !rdlp_playlist_entry_view_count(playlist, 9, &value);
}

static int json_number(cJSON *document, const char *name, double expected) {
  cJSON *number = cJSON_GetObjectItemCaseSensitive(document, name);
  return cJSON_IsNumber(number) && number->valuedouble == expected;
}

/* Exercise the actual --flat-playlist -j renderer; parse every JSON line. */
static int check_cli(const rdlp_playlist *playlist, int absent) {
  FILE *capture = tmpfile();
  int saved_stdout;
  int result;
  int ok = 1;
  size_t index = 0;
  char line[8192];
  if (capture == NULL)
    return 0;
  fflush(stdout);
  saved_stdout = dup(STDOUT_FILENO);
  if (saved_stdout < 0 || dup2(fileno(capture), STDOUT_FILENO) < 0) {
    if (saved_stdout >= 0)
      close(saved_stdout);
    fclose(capture);
    return 0;
  }
  result = cli_render_playlist_json(playlist);
  fflush(stdout);
  if (dup2(saved_stdout, STDOUT_FILENO) < 0)
    ok = 0;
  close(saved_stdout);
  rewind(capture);
  while (fgets(line, sizeof(line), capture) != NULL) {
    cJSON *document = cJSON_Parse(line);
    cJSON *thumbnails;
    if (document == NULL || !json_number(document, "playlist_index", index + 1))
      ok = 0;
    if (absent || index == 1) {
      static const char *fields[] = {"duration", "channel", "channel_id",
          "thumbnails", "view_count", "view_count_text", "published_text",
          "description_snippet"};
      size_t field;
      for (field = 0; field < sizeof(fields) / sizeof(fields[0]); ++field) {
        if (cJSON_HasObjectItem(document, fields[field]))
          ok = 0;
      }
    } else if (index == 0) {
      thumbnails = cJSON_GetObjectItemCaseSensitive(document, "thumbnails");
      if (!json_number(document, "duration", 62) ||
          !json_number(document, "view_count", 1234) ||
          !equal(cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(document,
                     "description_snippet")), "Hello world…") ||
          !equal(cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(document,
                     "published_text")), "2 days ago") ||
          cJSON_GetArraySize(thumbnails) != 2 ||
          !equal(cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(
                     cJSON_GetArrayItem(thumbnails, 1), "url")),
                 "https://img.example/large.jpg"))
        ok = 0;
    } else if (index == 2) {
      if (!json_number(document, "duration", 0) ||
          !json_number(document, "view_count", 0))
        ok = 0;
    } else if (index != 8 && cJSON_HasObjectItem(document, "view_count")) {
      ok = 0;
    }
    cJSON_Delete(document);
    ++index;
  }
  fclose(capture);
  return ok && result == 0 && index == rdlp_playlist_entry_count(playlist);
}

static int check_numeric_boundaries(void) {
  static const struct {
    const char *seconds_json;
    const char *duration_text;
    const char *views;
    int has_duration;
    uint64_t duration;
    int has_views;
    uint64_t count;
  } cases[] = {
      {"\"0\"", "", "0 views", 1, 0, 1, 0},
      {"null", "00:00", "1 view", 1, 0, 1, 1},
      {"null", "12:34", "12,345,678 views", 1, 754, 1, 12345678},
      {"9007199254740991", "", "9007199254740991 views", 1,
       UINT64_C(9007199254740991), 1, UINT64_C(9007199254740991)},
      {"9007199254740992", "", "9007199254740992 views", 0, 0, 0, 0},
      {"1e309", "999999999999999999999999:00", "999999999999999999999 views", 0, 0, 0, 0},
      {"-0.1", "1:2", "12,34 views", 0, 0, 0, 0},
      {"true", "1:60", "1.2M views", 0, 0, 0, 0},
      {"{}", "LIVE", "123 watching", 0, 0, 0, 0},
      {"[]", "UPCOMING", "1.234 Aufrufe", 0, 0, 0, 0},
      {"\"-1\"", "", "1234,567 views", 0, 0, 0, 0},
      {"\"1.5\"", "", ",123 views", 0, 0, 0, 0},
      {"null", "", "12, views", 0, 0, 0, 0}};
  size_t index;
  for (index = 0; index < sizeof(cases) / sizeof(cases[0]); ++index) {
    char json[1024];
    char *continuation = NULL;
    cJSON *document;
    YTPlaylist playlist;
    YTPlaylistEntry *entry;
    YTStatus status;
    int ok;
    memset(&playlist, 0, sizeof(playlist));
    snprintf(json, sizeof(json), "{\"contents\":[{\"playlistVideoRenderer\":{"
        "\"videoId\":\"AAAAAAAAAAA\",\"lengthSeconds\":%s,"
        "\"lengthText\":{\"simpleText\":\"%s\"},"
        "\"viewCountText\":{\"simpleText\":\"%s\"}}}]}",
        cases[index].seconds_json, cases[index].duration_text, cases[index].views);
    document = cJSON_Parse(json);
    status = yt_playlist_collect_entries(document, &playlist, &continuation);
    ok = document != NULL && status == YT_OK && playlist.entry_count == 1;
    if (ok) {
      entry = &playlist.entries[0];
      ok = entry->has_duration == cases[index].has_duration &&
          (!entry->has_duration || entry->duration == cases[index].duration) &&
          entry->has_view_count == cases[index].has_views &&
          (!entry->has_view_count || entry->view_count == cases[index].count);
    }
    free(continuation);
    yt_playlist_free(&playlist);
    cJSON_Delete(document);
    if (!ok) {
      fprintf(stderr, "FAIL: playlist metadata numeric boundary %lu\n",
              (unsigned long)index);
      return 0;
    }
  }
  return 1;
}

int retro_dlp_run_playlist_metadata_tests(void) {
  int scenario;
  if (!check_numeric_boundaries())
    return 1;
  for (scenario = 0; scenario < 4; ++scenario) {
    MetadataFixture fixture;
    rdlp_transport transport;
    rdlp_config config;
    rdlp_context *context = NULL;
    rdlp_playlist *playlist = NULL;
    rdlp_error error;
    rdlp_error_code status;
    int ok;
    memset(&fixture, 0, sizeof(fixture));
    memset(&transport, 0, sizeof(transport));
    memset(&config, 0, sizeof(config));
    memset(&error, 0, sizeof(error));
    fixture.absent = scenario / 2;
    fixture.fallback = scenario % 2;
    transport.struct_size = sizeof(transport);
    transport.send = metadata_send;
    transport.context = &fixture;
    config.struct_size = sizeof(config);
    config.transport = &transport;
    error.struct_size = sizeof(error);
    status = rdlp_context_create(&config, &context, &error);
    if (status == RDLP_OK)
      status = rdlp_list_playlist(context, "PL_metadata", NULL, &playlist, &error);
    ok = status == RDLP_OK && fixture.requests == 3 &&
        !fixture.invalid_request && check_api(playlist, fixture.absent) &&
        check_cli(playlist, fixture.absent);
    rdlp_playlist_destroy(playlist);
    rdlp_context_destroy(context);
    if (!ok) {
      fprintf(stderr, "FAIL: playlist metadata API/JSON scenario %d "
              "(status=%d requests=%u invalid=%d)\n", scenario,
              (int)status, fixture.requests, fixture.invalid_request);
      return 1;
    }
  }
  printf("PASS: optional playlist metadata API/CLI and unchanged request sequence "
         "(browse, fallback, absent, continuation, duplicates, live, zero)\n");
  return 0;
}
