/* Test-only instrumentation of the real store's executed SQLite statements. */
#include "../shared/rdapp_store.c"
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
