#ifndef RETRO_DLP_LEGACY_STDATOMIC_H
#define RETRO_DLP_LEGACY_STDATOMIC_H

#include <stdbool.h>
#include <stdint.h>

#define _Atomic(type) volatile type

uint64_t retro_dlp_atomic_fetch_add_8(volatile uint64_t *object,
                                      uint64_t operand);
uint64_t retro_dlp_atomic_fetch_and_8(volatile uint64_t *object,
                                      uint64_t operand);
uint64_t retro_dlp_atomic_fetch_or_8(volatile uint64_t *object,
                                     uint64_t operand);
uint64_t retro_dlp_atomic_fetch_sub_8(volatile uint64_t *object,
                                      uint64_t operand);
uint64_t retro_dlp_atomic_fetch_xor_8(volatile uint64_t *object,
                                      uint64_t operand);
uint64_t retro_dlp_atomic_exchange_8(volatile uint64_t *object,
                                     uint64_t desired);
uint64_t retro_dlp_atomic_load_8(volatile uint64_t *object);
void retro_dlp_atomic_store_8(volatile uint64_t *object, uint64_t desired);
bool retro_dlp_atomic_compare_exchange_8(volatile uint64_t *object,
                                         uint64_t *expected,
                                         uint64_t desired);

#define atomic_fetch_add(object, operand) \
  __builtin_choose_expr(sizeof(*(object)) == 8, \
      retro_dlp_atomic_fetch_add_8((volatile uint64_t *)(object), (operand)), \
      __sync_fetch_and_add((object), (operand)))
#define atomic_fetch_and(object, operand) \
  __builtin_choose_expr(sizeof(*(object)) == 8, \
      retro_dlp_atomic_fetch_and_8((volatile uint64_t *)(object), (operand)), \
      __sync_fetch_and_and((object), (operand)))
#define atomic_fetch_or(object, operand) \
  __builtin_choose_expr(sizeof(*(object)) == 8, \
      retro_dlp_atomic_fetch_or_8((volatile uint64_t *)(object), (operand)), \
      __sync_fetch_and_or((object), (operand)))
#define atomic_fetch_sub(object, operand) \
  __builtin_choose_expr(sizeof(*(object)) == 8, \
      retro_dlp_atomic_fetch_sub_8((volatile uint64_t *)(object), (operand)), \
      __sync_fetch_and_sub((object), (operand)))
#define atomic_fetch_xor(object, operand) \
  __builtin_choose_expr(sizeof(*(object)) == 8, \
      retro_dlp_atomic_fetch_xor_8((volatile uint64_t *)(object), (operand)), \
      __sync_fetch_and_xor((object), (operand)))
#define atomic_exchange(object, desired) \
  __builtin_choose_expr(sizeof(*(object)) == 8, \
      retro_dlp_atomic_exchange_8((volatile uint64_t *)(object), (desired)), \
      __sync_lock_test_and_set((object), (desired)))
#define atomic_load(object) \
  __builtin_choose_expr(sizeof(*(object)) == 8, \
      retro_dlp_atomic_load_8((volatile uint64_t *)(object)), \
      __sync_fetch_and_add((object), 0))
#define atomic_store(object, desired) \
  ((void)__builtin_choose_expr(sizeof(*(object)) == 8, \
      (retro_dlp_atomic_store_8((volatile uint64_t *)(object), (desired)), 0), \
      __sync_lock_test_and_set((object), (desired))))

#define atomic_compare_exchange_strong(object, expected, desired) \
  __builtin_choose_expr(sizeof(*(object)) == 8, \
      retro_dlp_atomic_compare_exchange_8((volatile uint64_t *)(object), \
                                          (uint64_t *)(expected), (desired)), \
      __extension__ ({ \
        __typeof__(*(object)) retroDlpExpected = *(expected); \
        __typeof__(*(object)) retroDlpPrevious = \
            __sync_val_compare_and_swap((object), retroDlpExpected, (desired)); \
        bool retroDlpExchanged = retroDlpPrevious == retroDlpExpected; \
        if (!retroDlpExchanged) \
          *(expected) = retroDlpPrevious; \
        retroDlpExchanged; \
      }))

#endif
