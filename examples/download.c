#include <stdio.h>

#include <retrodlp/download.h>

int main(int argc, char **argv) {
  rdlp_context *context = NULL;
  rdlp_selection *selection = NULL;
  rdlp_download_result result = {0};
  rdlp_error error = {0};
  rdlp_error_code status;

  if (argc != 3) {
    fprintf(stderr, "usage: %s VIDEO_URL_OR_ID DESTINATION.mp4\n", argv[0]);
    return 2;
  }

  error.struct_size = sizeof(error);
  result.struct_size = sizeof(result);
  status = rdlp_context_create(NULL, &context, &error);
  if (status == RDLP_OK)
    status = rdlp_resolve_video(context, argv[1], NULL, &selection, &error);
  if (status == RDLP_OK)
    status =
        rdlp_download_selection(selection, argv[2], NULL, &result, &error);
  if (status != RDLP_OK) {
    fprintf(stderr, "%s (%d)%s\n", rdlp_error_name(status), (int)status,
            result.source_tracks_retained ? " (source tracks retained)" : "");
    rdlp_selection_destroy(selection);
    rdlp_context_destroy(context);
    return 1;
  }

  printf("wrote %lld bytes to %s\n", (long long)result.bytes_written, argv[2]);
  rdlp_selection_destroy(selection);
  rdlp_context_destroy(context);
  return 0;
}
