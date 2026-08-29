extern "C" {
#include <retrodlp/download.h>
#include <retrodlp/retrodlp.h>
#include <retrodlp/version.h>
}

int main() {
  rdlp_context *context = 0;
  return context != 0 || RDLP_API_VERSION != 1;
}
