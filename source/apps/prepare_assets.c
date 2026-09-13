#include <retrodlp/assets.h>
#include <stdio.h>
#include <string.h>
int main(int argc,char **argv) {
  rdlp_ejs_asset_info info; rdlp_ejs_asset_options options; rdlp_error error;
  if(argc!=3) { fprintf(stderr,"usage: prepare-assets ABSOLUTE_DIRECTORY CA_BUNDLE\n"); return 2; }
  memset(&info,0,sizeof(info)); memset(&options,0,sizeof(options)); memset(&error,0,sizeof(error));
  info.struct_size=sizeof(info); options.struct_size=sizeof(options); error.struct_size=sizeof(error);
  options.ca_bundle_path=argv[2];
  if(rdlp_ejs_assets_inspect(argv[1],&info,&error)==RDLP_OK) return 0;
  if(rdlp_ejs_assets_install(argv[1],&options,&error)!=RDLP_OK) { fprintf(stderr,"%s\n",error.message); return 1; }
  return 0;
}
