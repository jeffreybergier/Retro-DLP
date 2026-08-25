#include "yt_crypto.h"

#include <openssl/sha.h>

int yt_crypto_sha256_hex(const void *data, size_t length, char hex[65]) {
  static const char digits[] = "0123456789abcdef";
  unsigned char digest[SHA256_DIGEST_LENGTH];
  size_t index;

  if ((data == NULL && length != 0) || hex == NULL ||
      SHA256((const unsigned char *)data, length, digest) == NULL)
    return 1;
  for (index = 0; index < sizeof(digest); ++index) {
    hex[index * 2] = digits[digest[index] >> 4];
    hex[index * 2 + 1] = digits[digest[index] & 0x0f];
  }
  hex[64] = '\0';
  return 0;
}
