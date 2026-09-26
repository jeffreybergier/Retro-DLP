#include "rdlp_thread.h"

#include <pthread.h>

int rdlp_thread_start(void *(*entry)(void *), void *context, size_t stack_size) {
  pthread_attr_t attributes;
  pthread_t thread;
  int error=pthread_attr_init(&attributes);
  if(error) return error;
  error=pthread_attr_setdetachstate(&attributes,PTHREAD_CREATE_DETACHED);
  if(!error) error=pthread_attr_setstacksize(&attributes,stack_size);
  if(!error) error=pthread_create(&thread,&attributes,entry,context);
  pthread_attr_destroy(&attributes);
  return error;
}

int rdlp_thread_is_main(void) { return pthread_main_np()!=0; }
