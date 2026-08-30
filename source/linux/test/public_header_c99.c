#include <retrodlp/assets.h>
#include <retrodlp/download.h>
#include <retrodlp/retrodlp.h>
#include <retrodlp/version.h>

int main(void) {
  rdlp_config config = {0};
  rdlp_ejs_asset_options asset_options = {0};
  rdlp_download_options download_options = {0};
  config.struct_size = sizeof(config);
  asset_options.struct_size = sizeof(asset_options);
  download_options.struct_size = sizeof(download_options);
  return RDLP_VERSION_STRING[0] == '\0' || RDLP_API_VERSION != 1 ||
         asset_options.struct_size == 0;
}
