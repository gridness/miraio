#ifndef MIRAIO_ASS_BRIDGE_H
#define MIRAIO_ASS_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MiraioASSContext MiraioASSContext;

typedef struct {
    const uint8_t *pixels;
    int width;
    int height;
    int bytes_per_row;
    int change_kind;
} MiraioASSFrame;

enum {
    MIRAIO_ASS_OK = 0,
    MIRAIO_ASS_ERROR_INPUT_TOO_LARGE = 1,
    MIRAIO_ASS_ERROR_INITIALIZATION = 2,
    MIRAIO_ASS_ERROR_PARSE = 3,
    MIRAIO_ASS_ERROR_TOO_MANY_EVENTS = 4,
    MIRAIO_ASS_ERROR_INVALID_DIMENSIONS = 5,
    MIRAIO_ASS_ERROR_ALLOCATION = 6
};

MiraioASSContext *miraio_ass_create(
    const char *script,
    size_t script_length,
    int *error_code
);

void miraio_ass_destroy(MiraioASSContext *context);

bool miraio_ass_render(
    MiraioASSContext *context,
    int width,
    int height,
    int64_t time_milliseconds,
    bool readability_boost,
    MiraioASSFrame *frame,
    int *error_code
);

size_t miraio_ass_semantic_text(
    MiraioASSContext *context,
    int64_t time_milliseconds,
    char *output,
    size_t output_capacity
);

int miraio_ass_event_count(const MiraioASSContext *context);
bool miraio_ass_has_advanced_effects(const MiraioASSContext *context);
int miraio_ass_library_version(void);

#ifdef __cplusplus
}
#endif

#endif
