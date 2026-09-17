#include "self_test_data.h"

const char retro_dlp_self_test_json[] =
    "{\n"
    "  \"name\": \"retro-dlp\",\n"
    "  \"enabled\": true,\n"
    "  \"values\": [21, 21]\n"
    "}\n";

const size_t retro_dlp_self_test_json_length =
    sizeof(retro_dlp_self_test_json) - 1;

const char retro_dlp_self_test_javascript[] =
    "var values = [21, 21];\n"
    "values[0] + values[1];\n";

const size_t retro_dlp_self_test_javascript_length =
    sizeof(retro_dlp_self_test_javascript) - 1;

/* Sanitized from an ANDROID_VR player response. Volatile request values and
 * unrelated metadata are intentionally omitted. */
const char retro_dlp_player_itag18_fixture[] =
    "{"
    "\"playabilityStatus\":{\"status\":\"OK\"},"
    "\"streamingData\":{"
    "\"formats\":["
    "{\"itag\":22,\"url\":\"https://fixture.googlevideo.com/"
    "videoplayback?expire=1900000000&itag=22\","
    "\"mimeType\":\"video/mp4; codecs=\\\"avc1.64001F, mp4a.40.2\\\"\","
    "\"width\":1280,\"height\":720},"
    "{\"itag\":18,\"url\":\"https://fixture.googlevideo.com/"
    "videoplayback?expire=1900000000&itag=18&sig=fixture-signature\","
    "\"mimeType\":\"video/mp4; codecs=\\\"avc1.42001E, mp4a.40.2\\\"\","
    "\"width\":640,\"height\":360,\"contentLength\":\"12345678\"}"
    "],"
    "\"adaptiveFormats\":[{\"itag\":137,\"width\":1920,"
    "\"height\":1080}]"
    "}}";

const size_t retro_dlp_player_itag18_fixture_length =
    sizeof(retro_dlp_player_itag18_fixture) - 1;

const char retro_dlp_player_n_challenge_fixture[] =
    "{"
    "\"playabilityStatus\":{\"status\":\"OK\"},"
    "\"streamingData\":{\"formats\":["
    "{\"itag\":18,\"url\":\"https://fixture.googlevideo.com/"
    "videoplayback?expire=1900000000&itag=18&n=unsolved\","
    "\"mimeType\":\"video/mp4\",\"width\":640,\"height\":360},"
    "{\"itag\":18,\"signatureCipher\":\"url=fixture&s=unsolved\","
    "\"mimeType\":\"video/mp4\",\"width\":640,\"height\":360}"
    "]}}";

const size_t retro_dlp_player_n_challenge_fixture_length =
    sizeof(retro_dlp_player_n_challenge_fixture) - 1;

const char retro_dlp_player_unavailable_fixture[] =
    "{\"playabilityStatus\":{\"status\":\"LOGIN_REQUIRED\","
    "\"reason\":\"Sign in to confirm your age\"}}";

const size_t retro_dlp_player_unavailable_fixture_length =
    sizeof(retro_dlp_player_unavailable_fixture) - 1;
