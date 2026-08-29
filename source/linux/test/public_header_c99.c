#include <retrodlp/download.h>
#include <retrodlp/retrodlp.h>
#include <retrodlp/version.h>

int main(void) {
  rdlp_config config = {0};
  rdlp_download_options download_options = {0};
  config.struct_size = sizeof(config);
  download_options.struct_size = sizeof(download_options);
  return RDLP_VERSION_STRING[0] == '\0';
}
