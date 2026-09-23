/* Test-only instrumentation of the real store's executed SQLite statements. */
#define _POSIX_C_SOURCE 200809L
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
static char writable_root[PATH_MAX];
void rdapp_test_writable_root(const char *path) {
  snprintf(writable_root,sizeof(writable_root),"%s",path?path:"");
}
static int sandbox_mkdir(const char *path,mode_t mode) {
  size_t length=strlen(writable_root);
  if(length && (strncmp(path,writable_root,length) ||
     (path[length] && path[length]!='/'))) { errno=EPERM; return -1; }
  return mkdir(path,mode);
}
#define mkdir sandbox_mkdir
#include "../rdapp_store.c"
#undef mkdir
static int64_t statement_steps;
static int trace_statement(unsigned event,void *context,void *statement,void *elapsed) {
  (void)event; (void)context; (void)elapsed;
  statement_steps+=sqlite3_stmt_status(statement,SQLITE_STMTSTATUS_VM_STEP,0);
  return 0;
}
void rdapp_test_measure(rdapp_store *store) {
  statement_steps=0;
  sqlite3_trace_v2(store->db,SQLITE_TRACE_PROFILE,trace_statement,NULL);
}
int64_t rdapp_test_steps(void) { return statement_steps; }
