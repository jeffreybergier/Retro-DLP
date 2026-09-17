#ifndef RETRO_DLP_EJS_TEST_DATA_H
#define RETRO_DLP_EJS_TEST_DATA_H

#include <stddef.h>

extern const char retro_dlp_ejs_player_fixture[];
extern const char retro_dlp_ejs_cipher_response_fixture[];
extern const size_t retro_dlp_ejs_cipher_response_fixture_length;

#define RETRO_DLP_EJS_SIG_INPUT_1 "abc"
#define RETRO_DLP_EJS_SIG_OUTPUT_1 "cba"
#define RETRO_DLP_EJS_SIG_INPUT_2 "retro"
#define RETRO_DLP_EJS_SIG_OUTPUT_2 "orter"
#define RETRO_DLP_EJS_N_INPUT_1 "xyz"
#define RETRO_DLP_EJS_N_OUTPUT_1 "xyz-n"
#define RETRO_DLP_EJS_N_INPUT_2 "batch"
#define RETRO_DLP_EJS_N_OUTPUT_2 "batch-n"

#endif
