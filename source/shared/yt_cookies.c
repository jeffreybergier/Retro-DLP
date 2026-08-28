#if !defined(__APPLE__)
#define _POSIX_C_SOURCE 200112L
#endif

#include "yt_cookies.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "yt_crypto.h"

#define YT_COOKIE_FILE_MAXIMUM (2U * 1024U * 1024U)

static char *copy_value(const char *value) {
  size_t length;
  char *copy;
  if (value == NULL)
    return NULL;
  length = strlen(value);
  copy = (char *)malloc(length + 1);
  if (copy != NULL)
    memcpy(copy, value, length + 1);
  return copy;
}

static int youtube_cookie_domain(const char *domain) {
  static const char suffix[] = ".youtube.com";
  size_t length;
  size_t suffix_length;
  if (domain == NULL)
    return 0;
  if (strncmp(domain, "#HttpOnly_", 10) == 0)
    domain += 10;
  if (strcmp(domain, "youtube.com") == 0)
    return 1;
  length = strlen(domain);
  suffix_length = sizeof(suffix) - 1;
  return length >= suffix_length &&
         strcmp(domain + length - suffix_length, suffix) == 0;
}

static int cookie_is_current(const char *expiry, int64_t now_unix) {
  char *end;
  long long value;
  if (expiry == NULL || expiry[0] == '\0')
    return 0;
  errno = 0;
  value = strtoll(expiry, &end, 10);
  if (errno != 0 || *end != '\0' || value < 0)
    return 0;
  return value == 0 || now_unix <= 0 || value > now_unix;
}

static int replace_secret(char **destination, const char *value) {
  char *copy = copy_value(value);
  if (copy == NULL)
    return 0;
  free(*destination);
  *destination = copy;
  return 1;
}

static int parse_cookie_line(char *line, int64_t now_unix,
                             YTAuthCookies *cookies) {
  char *fields[7];
  char *cursor;
  size_t index;

  fields[0] = line;
  cursor = line;
  for (index = 1; index < 7; ++index) {
    cursor = strchr(cursor, '\t');
    if (cursor == NULL)
      return 1;
    *cursor++ = '\0';
    fields[index] = cursor;
  }
  if (strchr(fields[6], '\t') != NULL)
    return 1;
  if (!youtube_cookie_domain(fields[0]) || strcmp(fields[2], "/") != 0 ||
      strcmp(fields[3], "TRUE") != 0 ||
      !cookie_is_current(fields[4], now_unix))
    return 1;
  if (strcmp(fields[5], "LOGIN_INFO") == 0) {
    cookies->has_login_info = 1;
    return 1;
  }
  if (strcmp(fields[5], "SAPISID") == 0)
    return replace_secret(&cookies->sapisid, fields[6]);
  if (strcmp(fields[5], "__Secure-1PAPISID") == 0)
    return replace_secret(&cookies->sapisid_1p, fields[6]);
  if (strcmp(fields[5], "__Secure-3PAPISID") == 0)
    return replace_secret(&cookies->sapisid_3p, fields[6]);
  return 1;
}

YTStatus yt_auth_cookies_parse(const void *data, size_t length,
                               int64_t now_unix, YTAuthCookies *cookies) {
  char *copy;
  char *line;
  char *next;
  int first_line;
  int valid_header;
  if (data == NULL || length == 0 || length > YT_COOKIE_FILE_MAXIMUM ||
      cookies == NULL)
    return YT_ERR_COOKIE_FILE;
  memset(cookies, 0, sizeof(*cookies));
  copy = (char *)malloc(length + 1);
  if (copy == NULL)
    return YT_ERR_OUT_OF_MEMORY;
  memcpy(copy, data, length);
  copy[length] = '\0';
  first_line = 1;
  valid_header = 0;
  line = copy;
  while (line <= copy + length) {
    size_t line_length;
    next = strchr(line, '\n');
    if (next != NULL)
      *next++ = '\0';
    line_length = strlen(line);
    if (line_length != 0 && line[line_length - 1] == '\r')
      line[--line_length] = '\0';
    if (first_line) {
      valid_header = strcmp(line, "# Netscape HTTP Cookie File") == 0 ||
                     strcmp(line, "# HTTP Cookie File") == 0;
      first_line = 0;
    } else if (line_length != 0 &&
               (line[0] != '#' || strncmp(line, "#HttpOnly_", 10) == 0) &&
               !parse_cookie_line(line, now_unix, cookies)) {
      free(copy);
      yt_auth_cookies_free(cookies);
      return YT_ERR_OUT_OF_MEMORY;
    }
    if (next == NULL)
      break;
    line = next;
  }
  memset(copy, 0, length);
  free(copy);
  if (!valid_header) {
    yt_auth_cookies_free(cookies);
    return YT_ERR_COOKIE_FILE;
  }
  if (!yt_auth_cookies_is_authenticated(cookies)) {
    yt_auth_cookies_free(cookies);
    return YT_ERR_AUTH_COOKIES_INVALID;
  }
  return YT_OK;
}

YTStatus yt_auth_cookies_load(const char *path, int64_t now_unix,
                              YTAuthCookies *cookies) {
  struct stat information;
  FILE *file;
  int descriptor;
  int open_flags;
  char line[16384];
  int first_line;
  int valid_header;

  if (path == NULL || path[0] == '\0' || cookies == NULL)
    return YT_ERR_COOKIE_FILE;
  memset(cookies, 0, sizeof(*cookies));
  open_flags = O_RDONLY;
#ifdef O_NOFOLLOW
  open_flags |= O_NOFOLLOW;
#endif
  descriptor = open(path, open_flags);
  if (descriptor < 0 || fstat(descriptor, &information) != 0 ||
      !S_ISREG(information.st_mode) || information.st_size <= 0 ||
      (uint64_t)information.st_size > YT_COOKIE_FILE_MAXIMUM) {
    if (descriptor >= 0)
      close(descriptor);
    return YT_ERR_COOKIE_FILE;
  }
  file = fdopen(descriptor, "rb");
  if (file == NULL) {
    close(descriptor);
    return YT_ERR_COOKIE_FILE;
  }
  first_line = 1;
  valid_header = 0;
  while (fgets(line, sizeof(line), file) != NULL) {
    size_t length = strlen(line);
    if (length != 0 && line[length - 1] == '\n')
      line[--length] = '\0';
    if (length != 0 && line[length - 1] == '\r')
      line[--length] = '\0';
    if (first_line) {
      valid_header = strcmp(line, "# Netscape HTTP Cookie File") == 0 ||
                     strcmp(line, "# HTTP Cookie File") == 0;
      first_line = 0;
      continue;
    }
    if (length == sizeof(line) - 1 || line[0] == '\0' ||
        (line[0] == '#' && strncmp(line, "#HttpOnly_", 10) != 0))
      continue;
    if (!parse_cookie_line(line, now_unix, cookies)) {
      fclose(file);
      yt_auth_cookies_free(cookies);
      return YT_ERR_OUT_OF_MEMORY;
    }
  }
  if (ferror(file) || fclose(file) != 0 || !valid_header) {
    yt_auth_cookies_free(cookies);
    return YT_ERR_COOKIE_FILE;
  }
  if (!yt_auth_cookies_is_authenticated(cookies)) {
    yt_auth_cookies_free(cookies);
    return YT_ERR_AUTH_COOKIES_INVALID;
  }
  return YT_OK;
}

int yt_auth_cookies_is_authenticated(const YTAuthCookies *cookies) {
  return cookies != NULL && cookies->has_login_info &&
         (cookies->sapisid != NULL || cookies->sapisid_1p != NULL ||
          cookies->sapisid_3p != NULL);
}

static YTStatus append_authorization(char *buffer, size_t buffer_size,
                                     size_t *used, const char *scheme,
                                     const char *sid, const char *origin,
                                     const char *user_session_id,
                                     int64_t now_unix) {
  char timestamp[32];
  char material[4096];
  char digest[41];
  int length;
  if (sid == NULL)
    return YT_OK;
  length = snprintf(timestamp, sizeof(timestamp), "%lld",
                    (long long)now_unix);
  if (length <= 0 || length >= (int)sizeof(timestamp))
    return YT_ERR_INVALID_RESPONSE;
  if (user_session_id != NULL && user_session_id[0] != '\0')
    length = snprintf(material, sizeof(material), "%s %s %s %s",
                      user_session_id, timestamp, sid, origin);
  else
    length = snprintf(material, sizeof(material), "%s %s %s", timestamp,
                      sid, origin);
  if (length <= 0 || length >= (int)sizeof(material) ||
      yt_crypto_sha1_hex(material, (size_t)length, digest) != 0)
    return YT_ERR_INVALID_RESPONSE;
  length = snprintf(buffer + *used, buffer_size - *used, "%s%s %s_%s%s",
                    *used == 0 ? "" : " ", scheme, timestamp, digest,
                    user_session_id != NULL && user_session_id[0] != '\0'
                        ? "_u"
                        : "");
  memset(material, 0, sizeof(material));
  if (length <= 0 || (size_t)length >= buffer_size - *used)
    return YT_ERR_INVALID_RESPONSE;
  *used += (size_t)length;
  return YT_OK;
}

YTStatus yt_auth_cookies_make_authorization(
    const YTAuthCookies *cookies, const char *origin,
    const char *user_session_id, int64_t now_unix, char *buffer,
    size_t buffer_size) {
  YTStatus status;
  size_t used;
  if (!yt_auth_cookies_is_authenticated(cookies) || origin == NULL ||
      origin[0] == '\0' || now_unix <= 0 || buffer == NULL ||
      buffer_size == 0)
    return YT_ERR_AUTH_COOKIES_INVALID;
  buffer[0] = '\0';
  used = 0;
  status = append_authorization(buffer, buffer_size, &used, "SAPISIDHASH",
                                cookies->sapisid, origin, user_session_id,
                                now_unix);
  if (status == YT_OK)
    status = append_authorization(buffer, buffer_size, &used,
                                  "SAPISID1PHASH", cookies->sapisid_1p,
                                  origin, user_session_id, now_unix);
  if (status == YT_OK)
    status = append_authorization(buffer, buffer_size, &used,
                                  "SAPISID3PHASH", cookies->sapisid_3p,
                                  origin, user_session_id, now_unix);
  return status;
}

void yt_auth_cookies_free(YTAuthCookies *cookies) {
  if (cookies == NULL)
    return;
  if (cookies->sapisid != NULL)
    memset(cookies->sapisid, 0, strlen(cookies->sapisid));
  if (cookies->sapisid_1p != NULL)
    memset(cookies->sapisid_1p, 0, strlen(cookies->sapisid_1p));
  if (cookies->sapisid_3p != NULL)
    memset(cookies->sapisid_3p, 0, strlen(cookies->sapisid_3p));
  free(cookies->sapisid);
  free(cookies->sapisid_1p);
  free(cookies->sapisid_3p);
  memset(cookies, 0, sizeof(*cookies));
}
