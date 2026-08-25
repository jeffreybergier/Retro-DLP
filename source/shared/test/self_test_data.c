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
