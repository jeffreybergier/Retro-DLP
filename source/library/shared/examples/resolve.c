#include <stdio.h>

#include <retrodlp/retrodlp.h>

int main(int argc, char **argv) {
  rdlp_context *context = NULL;
  rdlp_selection *selection = NULL;
  rdlp_error error = {0};
  rdlp_error_code status;
  size_t index;

  if (argc != 2) {
    fprintf(stderr, "usage: %s VIDEO_URL_OR_ID\n", argv[0]);
    return 2;
  }

  error.struct_size = sizeof(error);
  status = rdlp_context_create(NULL, &context, &error);
  if (status == RDLP_OK)
    status = rdlp_resolve_video(context, argv[1], NULL, &selection, &error);
  if (status != RDLP_OK) {
    fprintf(stderr, "%s (%d)\n", rdlp_error_name(status), (int)status);
    rdlp_context_destroy(context);
    return 1;
  }

  printf("%s (%s)\n", rdlp_selection_title(selection),
         rdlp_selection_video_id(selection));
  for (index = 0; index < rdlp_selection_media_count(selection); ++index) {
    size_t header_index;
    printf("media[%lu]: %s\n", (unsigned long)index,
           rdlp_selection_media_url(selection, index));
    for (header_index = 0;
         header_index < rdlp_selection_media_header_count(selection, index);
         ++header_index) {
      const rdlp_http_header *header =
          rdlp_selection_media_header(selection, index, header_index);
      printf("  %s: %s\n", header->name, header->value);
    }
  }

  rdlp_selection_destroy(selection);
  rdlp_context_destroy(context);
  return 0;
}
