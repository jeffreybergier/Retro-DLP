#ifndef RETRO_DLP_YT_CRYPTO_H
#define RETRO_DLP_YT_CRYPTO_H

#include <stddef.h>

int yt_crypto_sha256_hex(const void *data, size_t length, char hex[65]);
int yt_crypto_sha1_hex(const void *data, size_t length, char hex[41]);

#endif
