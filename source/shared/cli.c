#include "cli.h"

#include <stdio.h>
#include <string.h>

#include "platform.h"
#include "test/self_test.h"

#ifndef RETRO_DLP_VERSION
#define RETRO_DLP_VERSION "development"
#endif

static void print_usage(FILE *stream) {
  fprintf(stream,
          "Usage: retro-dlp [OPTION]\n"
          "\n"
          "Retro-DLP command line tool.\n"
          "\n"
          "Options:\n"
          "  -h, --help       Show this help.\n"
          "  -V, --version    Show version and build platform.\n"
          "      --test       Run embedded dependency tests.\n");
}

int retro_dlp_run(int argc, char **argv) {
  if (argc == 1) {
    print_usage(stdout);
    return 0;
  }

  if (argc == 2 &&
      (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0)) {
    print_usage(stdout);
    return 0;
  }

  if (argc == 2 &&
      (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-V") == 0)) {
    printf("retro-dlp %s (%s)\n", RETRO_DLP_VERSION, retro_dlp_platform());
    return 0;
  }

  if (argc == 2 && strcmp(argv[1], "--test") == 0)
    return retro_dlp_run_self_tests();

  fprintf(stderr, "retro-dlp: unsupported arguments\n");
  print_usage(stderr);
  return 2;
}
