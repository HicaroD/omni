#ifndef OMNI_PLATFORM_H
#define OMNI_PLATFORM_H
#include <stdint.h>
#include <stdbool.h>
uint64_t omni_argc(void);
const char *omni_arg(uint64_t i);
int32_t omni_root(const char *path);
int32_t omni_load(const char *path, void **data, uint64_t *length);
int32_t omni_preview(const char *path, void **data, uint64_t *length);
int32_t omni_save(const char *path, void *data, uint64_t length);
int32_t omni_width(uint32_t codepoint);
void omni_locale(void);
uint8_t omni_byte(const char *text, uint64_t i);
const char *omni_cview(void *data);
uint32_t omni_widen(uint8_t value);
int32_t omni_path(const char *path, void **resolved);
uint64_t omni_stamp(const char *path);
int32_t omni_spawn(int32_t kind, const char *query, bool hidden, bool ignored, bool regex, void **process);
int32_t omni_poll(void *process, void *buffer, uint64_t capacity, uint64_t *count);
void omni_cancel(void *process);
int32_t omni_copy(void *data, uint64_t length);
int32_t omni_paste(void **data, uint64_t *length);
#endif
