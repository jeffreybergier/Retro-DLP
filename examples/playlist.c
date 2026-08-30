#include <stdio.h>

#include <retrodlp/retrodlp.h>

int main(int argc, char **argv) {
  rdlp_context *context = NULL;
  rdlp_playlist *playlist = NULL;
  rdlp_error error = {0};
  rdlp_error_code status;
  size_t index;

  if (argc != 2) {
    fprintf(stderr, "usage: %s PLAYLIST_URL_OR_ID\n", argv[0]);
    return 2;
  }

  error.struct_size = sizeof(error);
  status = rdlp_context_create(NULL, &context, &error);
  if (status == RDLP_OK)
    status = rdlp_list_playlist(context, argv[1], NULL, &playlist, &error);
  if (status != RDLP_OK) {
    fprintf(stderr, "%s (%d)\n", rdlp_error_name(status), (int)status);
    rdlp_context_destroy(context);
    return 1;
  }

  printf("%s (%s)\n", rdlp_playlist_title(playlist),
         rdlp_playlist_id(playlist));
  for (index = 0; index < rdlp_playlist_entry_count(playlist); ++index)
    printf("%lu\t%s\t%s\n",
           (unsigned long)rdlp_playlist_entry_index(playlist, index),
           rdlp_playlist_entry_video_id(playlist, index),
           rdlp_playlist_entry_title(playlist, index));

  rdlp_playlist_destroy(playlist);
  rdlp_context_destroy(context);
  return 0;
}
