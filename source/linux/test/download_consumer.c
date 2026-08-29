#include <stdio.h>
#include <string.h>

#include <retrodlp/download.h>

int main(void) {
  rdlp_download_result result;
  rdlp_error error;
  memset(&result, 0, sizeof(result));
  memset(&error, 0, sizeof(error));
  result.struct_size = sizeof(result);
  error.struct_size = sizeof(error);
  if (rdlp_download_selection(NULL, "unused.mp4", NULL, &result, &error) !=
          RDLP_STATUS_INVALID_ARGUMENT ||
      error.status != RDLP_STATUS_INVALID_ARGUMENT) {
    fprintf(stderr, "FAIL: optional download public API contract\n");
    return 1;
  }
  puts("PASS: optional download public API consumer");
  return 0;
}
