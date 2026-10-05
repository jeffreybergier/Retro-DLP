#include "rdapp_strings.h"
#include <stdlib.h>
#include <string.h>

static const char *const keys[RDAPP_STRING_COUNT] = {
#define RDAPP_STRING(name, key) key,
#include "rdapp_strings.def"
#undef RDAPP_STRING
};
static char *values[RDAPP_STRING_COUNT];
static int initialized;

int rdapp_strings_initialize(rdapp_string_lookup lookup, void *context) {
  char *copies[RDAPP_STRING_COUNT];
  int i;
  if(initialized) return 1;
  memset(copies,0,sizeof(copies));
  for(i=0;i<RDAPP_STRING_COUNT;++i) {
    const char *text=lookup?lookup(keys[i],context):NULL;
    size_t size;
    if(!text || !*text) text=keys[i];
    size=strlen(text)+1;
    copies[i]=malloc(size);
    if(!copies[i]) {
      while(i>0) free(copies[--i]);
      return 0;
    }
    memcpy(copies[i],text,size);
  }
  memcpy(values,copies,sizeof(values));
  initialized=1;
  return 1;
}
const char *rdapp_string_key(rdapp_string_id identifier) {
  return (unsigned int)identifier<RDAPP_STRING_COUNT?keys[identifier]:"";
}
const char *rdapp_string(rdapp_string_id identifier) {
  if((unsigned int)identifier>=RDAPP_STRING_COUNT) return "";
  return initialized?values[identifier]:keys[identifier];
}
const char *rdapp_localize_key(const char *key) {
  int i;
  if(!key || !initialized) return key;
  for(i=0;i<RDAPP_STRING_COUNT;++i)
    if(!strcmp(key,keys[i])) return values[i];
  return key;
}
