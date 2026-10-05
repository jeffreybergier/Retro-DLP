#ifndef RDAPP_STRINGS_H
#define RDAPP_STRINGS_H

/* Application presentation only; no dependency on Foundation/CoreFoundation. */
typedef enum {
#define RDAPP_STRING(name, key) RDAPP_STRING_##name,
#include "rdapp_strings.def"
#undef RDAPP_STRING
  RDAPP_STRING_COUNT
} rdapp_string_id;

typedef const char *(*rdapp_string_lookup)(const char *key, void *context);
/* Call once, before starting workers or exposing stores to other threads.
   Copies callback results immediately. NULL/empty results use the English key.
   Success freezes the table for the process lifetime; later calls are no-ops.
   Failure leaves every English default intact and permits a startup retry.
   Callers that never initialize (CLI/tests) use English without allocation. */
int rdapp_strings_initialize(rdapp_string_lookup lookup, void *context);
/* Returned bytes are borrowed, immutable, and valid for the process lifetime.
   key() is for persisted English records/diagnostics, string() for UI text. */
const char *rdapp_string_key(rdapp_string_id identifier);
const char *rdapp_string(rdapp_string_id identifier);
/* Exact known keys only, for historical plain-text errors read from SQLite.
   Unknown text is returned unchanged and retains the caller's lifetime. */
const char *rdapp_localize_key(const char *key);
#endif
