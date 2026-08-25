#include "yt_ejs_bundle.h"

const char retro_dlp_ejs_core[] =
#include "yt_ejs_core.inc"
    ;

const size_t retro_dlp_ejs_core_length = sizeof(retro_dlp_ejs_core) - 1;

const char retro_dlp_ejs_lib[] =
#include "yt_ejs_lib.inc"
    ;

const size_t retro_dlp_ejs_lib_length = sizeof(retro_dlp_ejs_lib) - 1;
