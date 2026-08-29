#include <stdio.h>

#include <retrodlp/retrodlp.h>

int main(int argc, char **argv) {
  rdlp_context *context = NULL;
  rdlp_selection *selection = NULL;
  rdlp_resolve_options options = {0};
  rdlp_error error = {0};
  rdlp_status status;

  if (argc != 3) {
    fprintf(stderr, "usage: %s VIDEO_URL_OR_ID COOKIES_TXT\n", argv[0]);
    return 2;
  }

  options.struct_size = sizeof(options);
  options.cookie_file = argv[2];
  error.struct_size = sizeof(error);
  status = rdlp_context_create(NULL, &context, &error);
  if (status == RDLP_STATUS_OK)
    status =
        rdlp_resolve_video(context, argv[1], &options, &selection, &error);
  if (status != RDLP_STATUS_OK) {
    fprintf(stderr, "%s: %s\n", rdlp_status_string(status), error.message);
    rdlp_context_destroy(context);
    return 1;
  }

  printf("%s\n%s\n", rdlp_selection_title(selection),
         rdlp_selection_media_url(selection, 0));
  rdlp_selection_destroy(selection);
  rdlp_context_destroy(context);
  return 0;
}
