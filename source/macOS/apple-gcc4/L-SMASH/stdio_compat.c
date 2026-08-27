#include <stddef.h>
#include <stdio.h>

/*
 * L-SMASH requests a POSIX namespace that maps these stdio calls to the
 * Leopard UNIX2003 ABI. Export those spellings while forwarding to the
 * unsuffixed Tiger implementations selected by this compatibility source's
 * _NONSTD_SOURCE build profile.
 */
int retro_dlp_lsmash_fputs_unix2003(const char *string, FILE *stream)
    __asm__("_fputs$UNIX2003");
size_t retro_dlp_lsmash_fwrite_unix2003(const void *buffer, size_t size,
                                        size_t count, FILE *stream)
    __asm__("_fwrite$UNIX2003");

int retro_dlp_lsmash_fputs_unix2003(const char *string, FILE *stream) {
  return fputs(string, stream);
}

size_t retro_dlp_lsmash_fwrite_unix2003(const void *buffer, size_t size,
                                        size_t count, FILE *stream) {
  return fwrite(buffer, size, count, stream);
}
