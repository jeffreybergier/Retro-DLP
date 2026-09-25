#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lsmash.h"
#include "yt_formats.h"
#include "yt_mux.h"

#define AUDIO(url, rate, extra) \
  "{\"itag\":140,\"url\":\"https://fixture/" url "\"," \
  "\"mimeType\":\"audio/mp4; codecs=\\\"mp4a.40.2\\\"\"," \
  "\"bitrate\":" #rate ",\"audioChannels\":2" extra "}"
#define ORIGINAL \
  ",\"audioTrack\":{\"id\":\"ja.4\",\"displayName\":\"Japanese ORIGINAL\"}"
#define DUB \
  ",\"audioTrack\":{\"id\":\"en.3\",\"displayName\":\"English\",\"audioIsDefault\":true}"
#define VIDEO \
  "{\"itag\":136,\"url\":\"https://fixture/video\",\"height\":720," \
  "\"mimeType\":\"video/mp4; codecs=\\\"avc1.64001f\\\"\"}"
#define PROGRESSIVE(url, extra) \
  "{\"itag\":18,\"url\":\"https://fixture/" url "\",\"height\":360," \
  "\"mimeType\":\"video/mp4; codecs=\\\"avc1.42001e, mp4a.40.2\\\"\"" extra "}"

static int test_selection(void) {
  static const struct {
    const char *name;
    const char *formats;
    int progressive;
    YTStatus expected;
    const char *url;
    const char *language;
  } cases[] = {
    {"original beats higher-bitrate default English dub",
     AUDIO("dub", 150000, DUB) "," AUDIO("original", 120000, ORIGINAL),
     0, YT_OK, "original", "ja"},
    {"original remains selected when formats are reversed",
     AUDIO("original", 120000, ORIGINAL) "," AUDIO("dub", 150000, DUB),
     0, YT_OK, "original", "ja"},
    {"non-DRC original beats DRC original and non-DRC dub",
     AUDIO("drc", 160000, ORIGINAL ",\"isDrc\":true") ","
     AUDIO("dub", 150000, DUB) "," AUDIO("original", 120000, ORIGINAL),
     0, YT_OK, "original", "ja"},
    {"DRC original beats non-DRC dub",
     AUDIO("dub", 150000, DUB) ","
     AUDIO("original", 120000, ORIGINAL ",\"isDrc\":true"),
     0, YT_OK, "original", "ja"},
    {"same-language dub has a different track identity",
     AUDIO("dub", 150000, ",\"audioTrack\":{\"id\":\"ja.3\",\"displayName\":\"Japanese\"}") ","
     AUDIO("original", 120000, ORIGINAL), 0, YT_OK, "original", "ja"},
    {"original without a language ID",
     AUDIO("original", 120000, ",\"audioTrack\":{\"displayName\":\"Original\"}") ","
     AUDIO("dub", 150000, DUB), 0, YT_OK, "original", NULL},
    {"explicitly dubbed sole track is not original",
     AUDIO("dub", 150000, ",\"audioTrack\":{\"id\":\"en.3\",\"displayName\":\"English dubbed\"}"),
     0, YT_ERR_FORMAT_UNAVAILABLE, NULL, NULL},
    {"missing track metadata",
     AUDIO("legacy", 120000, ""), 0, YT_OK, "legacy", NULL},
    {"empty track metadata",
     AUDIO("legacy", 120000, ",\"audioTrack\":{}"),
     0, YT_OK, "legacy", NULL},
    {"single track without original label and regional language",
     AUDIO("single", 120000,
           ",\"audioTrack\":{\"id\":\"pt-BR.4\",\"displayName\":\"Portuguese\"}"),
     0, YT_OK, "single", "pt-BR"},
    {"ambiguous multilingual response must not choose the default",
     AUDIO("dub", 150000, DUB) ","
     AUDIO("other", 120000, ",\"audioTrack\":{\"id\":\"ja.4\"}"),
     0, YT_ERR_FORMAT_UNAVAILABLE, NULL, NULL},
    {"named tracks without IDs must not be mistaken for untagged legacy audio",
     AUDIO("one", 150000, ",\"audioTrack\":{\"displayName\":\"English\"}") ","
     AUDIO("two", 120000, ",\"audioTrack\":{\"displayName\":\"Japanese\"}"),
     0, YT_ERR_FORMAT_UNAVAILABLE, NULL, NULL},
    {"unsupported original must not fall back to dub",
     AUDIO("dub", 150000, DUB) ","
     "{\"itag\":251,\"url\":\"https://fixture/original\","
     "\"mimeType\":\"audio/webm; codecs=\\\"opus\\\"\"" ORIGINAL "}",
     0, YT_ERR_FORMAT_UNAVAILABLE, NULL, NULL},
    {"original with missing URL must not fall back to dub",
     AUDIO("dub", 150000, DUB) ","
     "{\"itag\":140,\"mimeType\":\"audio/mp4\"" ORIGINAL "}",
     0, YT_ERR_FORMAT_UNAVAILABLE, NULL, NULL},
    {"original challenge must not fall back to direct dub",
     AUDIO("dub", 150000, DUB) "," AUDIO("original?n=challenge", 120000, ORIGINAL),
     0, YT_ERR_JS_CHALLENGE, NULL, NULL},
    {"descriptive original label is not the original soundtrack",
     AUDIO("description", 150000,
           ",\"audioTrack\":{\"id\":\"ja.5\",\"displayName\":\"Japanese original descriptive\"}") ","
     AUDIO("original", 120000, ORIGINAL), 0, YT_OK, "original", "ja"},
    {"unlabeled variant inherits original identity by track ID",
     AUDIO("original", 140000, ",\"audioTrack\":{\"id\":\"ja.4\"}") ","
     AUDIO("other-original", 120000, ORIGINAL) "," AUDIO("dub", 160000, DUB),
     0, YT_OK, "original", "ja"},
    {"progressive original",
     PROGRESSIVE("dub", DUB) "," PROGRESSIVE("original", ORIGINAL),
     1, YT_OK, "original", "ja"},
    {"progressive ambiguous languages",
     PROGRESSIVE("dub", DUB) ","
     PROGRESSIVE("other", ",\"audioTrack\":{\"id\":\"ja.4\"}"),
     1, YT_ERR_FORMAT_UNAVAILABLE, NULL, NULL}
  };
  size_t index;
  int automatic;
  int failures = 0;
  for (index = 0; index < sizeof(cases) / sizeof(cases[0]); ++index) {
    char json[8192];
    cJSON *document;
    snprintf(json, sizeof(json),
             "{\"playabilityStatus\":{\"status\":\"OK\"},\"streamingData\":{\"%s\":[%s%s%s]}}",
             cases[index].progressive ? "formats" : "adaptiveFormats",
             cases[index].progressive ? "" : VIDEO,
             cases[index].progressive ? "" : ",", cases[index].formats);
    document = cJSON_Parse(json);
    if (document == NULL)
      return 1;
    for (automatic = 0; automatic <= 1; ++automatic) {
      YTMediaSelection selection;
      YTMediaRequest *media;
      YTStatus status;
      memset(&selection, 0, sizeof(selection));
      status = automatic
          ? yt_formats_select(NULL, document, NULL, NULL, 720,
                              !cases[index].progressive, &selection)
          : yt_formats_select_exact(NULL, document, NULL, NULL,
                                    cases[index].progressive ? "18" : "136+140",
                                    &selection);
      /* The automatic selector retains its historical no-format status. */
      if (status == YT_ERR_NO_PROGRESSIVE_MP4)
        status = YT_ERR_FORMAT_UNAVAILABLE;
      media = cases[index].progressive ? &selection.video : &selection.audio;
      if (status != cases[index].expected ||
          (status == YT_OK &&
           (strcmp(media->url + strlen("https://fixture/"), cases[index].url) != 0 ||
            ((media->audio_language == NULL) != (cases[index].language == NULL)) ||
            (cases[index].language != NULL &&
             strcmp(media->audio_language, cases[index].language) != 0)))) {
        fprintf(stderr, "FAIL: %s (%s), status %d\n", cases[index].name,
                automatic ? "automatic" : "exact", status);
        ++failures;
      }
      yt_media_selection_free(&selection);
    }
    cJSON_Delete(document);
  }
  return failures;
}

static int test_fallback(void) {
  static const char json[] =
      "{\"playabilityStatus\":{\"status\":\"OK\"},\"streamingData\":{"
      "\"formats\":[" PROGRESSIVE("untagged", "") "],"
      "\"adaptiveFormats\":[" VIDEO "," AUDIO("dub", 150000, DUB) ","
      "{\"itag\":139,\"url\":\"https://fixture/original\",\"audioChannels\":6,"
      "\"mimeType\":\"audio/mp4; codecs=\\\"mp4a.40.2\\\"\"" ORIGINAL "}]}}";
  cJSON *document = cJSON_Parse(json);
  cJSON *original;
  YTMediaSelection selection;
  YTStatus status;
  int automatic;
  int failures = 0;
  if (document == NULL)
    return 1;
  for (automatic = 0; automatic <= 1; ++automatic) {
    memset(&selection, 0, sizeof(selection));
    status = automatic
        ? yt_formats_select(NULL, document, NULL, NULL, 720, 1, &selection)
        : yt_formats_select_exact(NULL, document, NULL, NULL,
                                  "136+140/18", &selection);
    if (status != YT_ERR_FORMAT_UNAVAILABLE && status != YT_ERR_NO_PROGRESSIVE_MP4) {
      fprintf(stderr, "FAIL: unavailable original fell back to untagged progressive\n");
      ++failures;
    }
    yt_media_selection_free(&selection);
  }
  original = cJSON_GetArrayItem(cJSON_GetObjectItemCaseSensitive(
      cJSON_GetObjectItemCaseSensitive(document, "streamingData"), "adaptiveFormats"), 2);
  cJSON_SetNumberValue(cJSON_GetObjectItemCaseSensitive(original, "audioChannels"), 2);
  memset(&selection, 0, sizeof(selection));
  status = yt_formats_select_exact(NULL, document, NULL, NULL,
                                   "136+140/136+139", &selection);
  if (status != YT_OK || selection.audio.itag != 139 ||
      selection.audio.audio_language == NULL ||
      strcmp(selection.audio.audio_language, "ja") != 0) {
    fprintf(stderr, "FAIL: explicit alternative did not select compatible original\n");
    ++failures;
  }
  yt_media_selection_free(&selection);
  cJSON_Delete(document);
  return failures;
}

static int read_mux_language(const char *path, uint16_t expected) {
  lsmash_root_t *root = lsmash_create_root();
  lsmash_file_parameters_t file;
  lsmash_file_t *input;
  lsmash_media_parameters_t media;
  int passed = 0;
  if (root == NULL)
    return 0;
  if (lsmash_open_file(path, 1, &file) < 0) {
    lsmash_destroy_root(root);
    return 0;
  }
  input = lsmash_set_file(root, &file);
  if (input != NULL && lsmash_read_file(input, &file) >= 0) {
    lsmash_initialize_media_parameters(&media);
    if (lsmash_get_media_parameters(root, lsmash_get_track_ID(root, 2), &media) == 0)
      passed = media.handler_type == ISOM_MEDIA_HANDLER_TYPE_AUDIO_TRACK &&
               media.ISO_language == expected;
  }
  lsmash_close_file(&file);
  lsmash_destroy_root(root);
  return passed;
}

static int test_mux_languages(void) {
  static const struct { const char *tag; const char *iso; } cases[] = {
    {"en", "eng"}, {"ja", "jpn"}, {"ko", "kor"}, {"pt-BR", "por"},
    {"zh-Hans", "zho"}, {"EN-us", "eng"}, {"deu", "deu"},
    {"ger", "deu"}, {"haw", "haw"}, {"iw", "heb"},
    {NULL, "und"}, {"", "und"}, {"xx", "und"}, {"xyz", "und"},
    {"english", "und"}, {"12", "und"}
  };
  char directory[] = "/tmp/retro-dlp-mux-language.XXXXXX";
  char destination[256];
  size_t index;
  int failures = 0;
  if (mkdtemp(directory) == NULL)
    return 1;
  snprintf(destination, sizeof(destination), "%s/output.mp4", directory);
  for (index = 0; index < sizeof(cases) / sizeof(cases[0]); ++index) {
    int64_t bytes = 0;
    const char *iso = cases[index].iso;
    uint16_t expected = (uint16_t)LSMASH_PACK_ISO_LANGUAGE(iso[0], iso[1], iso[2]);
    YTStatus status = yt_mux_mp4_tracks(
        "source/library/shared/tests/fixtures/language-video.mp4",
        "source/library/shared/tests/fixtures/language-audio.m4a",
        destination, cases[index].tag, &bytes, NULL, NULL);
    if (status != YT_OK || bytes <= 0 || !read_mux_language(destination, expected)) {
      fprintf(stderr, "FAIL: mux language %s -> %s (status %d)\n",
              cases[index].tag == NULL ? "NULL" : cases[index].tag, iso, status);
      ++failures;
    }
    unlink(destination);
  }
  rmdir(directory);
  return failures;
}

int retro_dlp_run_audio_track_tests(void) {
  int failures = test_selection() + test_fallback() + test_mux_languages();
  if (failures == 0)
    puts("PASS: original audio selection and muxed language metadata");
  return failures;
}
