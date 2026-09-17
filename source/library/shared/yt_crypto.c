#include "yt_crypto.h"

#include <openssl/sha.h>

static void digest_to_hex(const unsigned char *digest, size_t length,
                          char *hex) {
  static const char digits[] = "0123456789abcdef";
  size_t index;
  for (index = 0; index < length; ++index) {
    hex[index * 2] = digits[digest[index] >> 4];
    hex[index * 2 + 1] = digits[digest[index] & 0x0f];
  }
  hex[length * 2] = '\0';
}

int yt_crypto_sha256_hex(const void *data, size_t length, char hex[65]) {
  unsigned char digest[SHA256_DIGEST_LENGTH];

  if ((data == NULL && length != 0) || hex == NULL ||
      SHA256((const unsigned char *)data, length, digest) == NULL)
    return 1;
  digest_to_hex(digest, sizeof(digest), hex);
  return 0;
}

int yt_crypto_sha1_hex(const void *data, size_t length, char hex[41]) {
  unsigned char digest[SHA_DIGEST_LENGTH];
  if ((data == NULL && length != 0) || hex == NULL ||
      SHA1((const unsigned char *)data, length, digest) == NULL)
    return 1;
  digest_to_hex(digest, sizeof(digest), hex);
  return 0;
}
