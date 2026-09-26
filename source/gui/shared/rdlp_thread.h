#ifndef RDLP_THREAD_H
#define RDLP_THREAD_H

#include <stddef.h>

/* Start a detached native thread with the requested stack size. The caller
   owns context if this returns an error; the thread owns it on success. */
int rdlp_thread_start(void *(*entry)(void *), void *context, size_t stack_size);
int rdlp_thread_is_main(void);

#endif
