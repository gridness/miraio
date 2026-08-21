#include "ASSBridge.h"

#include <ass/ass.h>
#include <stdlib.h>
#include <string.h>

#define MIRAIO_MAX_SCRIPT_BYTES (1024 * 1024)
#define MIRAIO_MAX_EVENTS 10000
#define MIRAIO_MAX_WIDTH 3840
#define MIRAIO_MAX_HEIGHT 2160
#define MIRAIO_GLYPH_CACHE_LIMIT 10000
#define MIRAIO_BITMAP_CACHE_MB 128

struct MiraioASSContext {
    ASS_Library *library;
    ASS_Renderer *renderer;
    ASS_Track *track;
    uint8_t *pixels;
    size_t pixel_capacity;
    bool advanced_effects;
    bool readability_boost;
};

static bool contains_advanced_effect(const char *script) {
    static const char *markers[] = {
        "\\k", "\\K", "\\kf", "\\ko", "\\t(",
        "\\move(", "\\clip(", "\\iclip(", "\\p1", "\\p2"
    };
    for (size_t i = 0; i < sizeof(markers) / sizeof(markers[0]); i++) {
        if (strstr(script, markers[i]) != NULL)
            return true;
    }
    return false;
}

static uint8_t blend_channel(uint8_t destination, uint8_t source, uint8_t alpha) {
    return (uint8_t) (source + ((uint16_t) destination * (255 - alpha) + 127) / 255);
}

MiraioASSContext *miraio_ass_create(
    const char *script,
    size_t script_length,
    int *error_code
) {
    if (error_code)
        *error_code = MIRAIO_ASS_OK;
    if (!script || script_length == 0 || script_length > MIRAIO_MAX_SCRIPT_BYTES) {
        if (error_code)
            *error_code = MIRAIO_ASS_ERROR_INPUT_TOO_LARGE;
        return NULL;
    }

    MiraioASSContext *context = calloc(1, sizeof(*context));
    if (!context) {
        if (error_code)
            *error_code = MIRAIO_ASS_ERROR_ALLOCATION;
        return NULL;
    }

    context->library = ass_library_init();
    if (!context->library)
        goto initialization_error;

    // External ASS is untrusted presentation data. Embedded font extraction is
    // outside this prototype boundary; CoreText supplies installed fallbacks.
    ass_set_extract_fonts(context->library, 0);

    context->renderer = ass_renderer_init(context->library);
    if (!context->renderer)
        goto initialization_error;

    ass_set_fonts(
        context->renderer,
        NULL,
        "Helvetica Neue",
        ASS_FONTPROVIDER_CORETEXT,
        NULL,
        0
    );
    ass_set_cache_limits(
        context->renderer,
        MIRAIO_GLYPH_CACHE_LIMIT,
        MIRAIO_BITMAP_CACHE_MB
    );
    ass_set_storage_size(context->renderer, 960, 540);

    char *owned_script = malloc(script_length + 1);
    if (!owned_script) {
        if (error_code)
            *error_code = MIRAIO_ASS_ERROR_ALLOCATION;
        miraio_ass_destroy(context);
        return NULL;
    }
    memcpy(owned_script, script, script_length);
    owned_script[script_length] = '\0';
    context->advanced_effects = contains_advanced_effect(owned_script);
    context->track = ass_read_memory(context->library, owned_script, script_length, NULL);
    free(owned_script);

    if (!context->track) {
        if (error_code)
            *error_code = MIRAIO_ASS_ERROR_PARSE;
        miraio_ass_destroy(context);
        return NULL;
    }
    if (context->track->n_events > MIRAIO_MAX_EVENTS) {
        if (error_code)
            *error_code = MIRAIO_ASS_ERROR_TOO_MANY_EVENTS;
        miraio_ass_destroy(context);
        return NULL;
    }
    return context;

initialization_error:
    if (error_code)
        *error_code = MIRAIO_ASS_ERROR_INITIALIZATION;
    miraio_ass_destroy(context);
    return NULL;
}

void miraio_ass_destroy(MiraioASSContext *context) {
    if (!context)
        return;
    if (context->track)
        ass_free_track(context->track);
    if (context->renderer)
        ass_renderer_done(context->renderer);
    if (context->library)
        ass_library_done(context->library);
    free(context->pixels);
    free(context);
}

bool miraio_ass_render(
    MiraioASSContext *context,
    int width,
    int height,
    int64_t time_milliseconds,
    bool readability_boost,
    MiraioASSFrame *frame,
    int *error_code
) {
    if (error_code)
        *error_code = MIRAIO_ASS_OK;
    if (!context || !frame || width <= 0 || height <= 0 ||
        width > MIRAIO_MAX_WIDTH || height > MIRAIO_MAX_HEIGHT) {
        if (error_code)
            *error_code = MIRAIO_ASS_ERROR_INVALID_DIMENSIONS;
        return false;
    }

    size_t pixel_count = (size_t) width * (size_t) height;
    size_t required_capacity = pixel_count * 4;
    if (required_capacity > context->pixel_capacity) {
        uint8_t *new_pixels = realloc(context->pixels, required_capacity);
        if (!new_pixels) {
            if (error_code)
                *error_code = MIRAIO_ASS_ERROR_ALLOCATION;
            return false;
        }
        context->pixels = new_pixels;
        context->pixel_capacity = required_capacity;
    }
    memset(context->pixels, 0, required_capacity);

    ass_set_frame_size(context->renderer, width, height);
    ass_set_margins(context->renderer, 0, 64, 0, 0);
    ass_set_use_margins(context->renderer, 0);
    if (context->readability_boost != readability_boost) {
        context->readability_boost = readability_boost;
        ass_set_font_scale(context->renderer, readability_boost ? 1.25 : 1.0);
        ass_set_selective_style_override_enabled(
            context->renderer,
            readability_boost ? ASS_OVERRIDE_BIT_SELECTIVE_FONT_SCALE : ASS_OVERRIDE_DEFAULT
        );
    }

    int change_kind = 0;
    ASS_Image *image = ass_render_frame(
        context->renderer,
        context->track,
        time_milliseconds,
        &change_kind
    );
    for (; image; image = image->next) {
        uint8_t red = (uint8_t) (image->color >> 24);
        uint8_t green = (uint8_t) (image->color >> 16);
        uint8_t blue = (uint8_t) (image->color >> 8);
        uint8_t color_alpha = (uint8_t) (255 - (image->color & 0xFF));

        for (int y = 0; y < image->h; y++) {
            int destination_y = image->dst_y + y;
            if (destination_y < 0 || destination_y >= height)
                continue;
            for (int x = 0; x < image->w; x++) {
                int destination_x = image->dst_x + x;
                if (destination_x < 0 || destination_x >= width)
                    continue;

                uint8_t mask = image->bitmap[y * image->stride + x];
                uint8_t alpha = (uint8_t) (((uint16_t) mask * color_alpha + 127) / 255);
                if (alpha == 0)
                    continue;

                size_t offset = ((size_t) destination_y * width + destination_x) * 4;
                uint8_t source_red = (uint8_t) (((uint16_t) red * alpha + 127) / 255);
                uint8_t source_green = (uint8_t) (((uint16_t) green * alpha + 127) / 255);
                uint8_t source_blue = (uint8_t) (((uint16_t) blue * alpha + 127) / 255);

                context->pixels[offset] = blend_channel(context->pixels[offset], source_red, alpha);
                context->pixels[offset + 1] = blend_channel(context->pixels[offset + 1], source_green, alpha);
                context->pixels[offset + 2] = blend_channel(context->pixels[offset + 2], source_blue, alpha);
                context->pixels[offset + 3] = (uint8_t) (
                    alpha + ((uint16_t) context->pixels[offset + 3] * (255 - alpha) + 127) / 255
                );
            }
        }
    }

    frame->pixels = context->pixels;
    frame->width = width;
    frame->height = height;
    frame->bytes_per_row = width * 4;
    frame->change_kind = change_kind;
    return true;
}

static size_t append_character(char *output, size_t capacity, size_t length, char character) {
    if (capacity > 0 && length + 1 < capacity)
        output[length] = character;
    return length + 1;
}

static size_t append_plain_event_text(
    const char *input,
    char *output,
    size_t capacity,
    size_t length
) {
    bool inside_override = false;
    for (size_t i = 0; input[i] != '\0'; i++) {
        char character = input[i];
        if (character == '{') {
            inside_override = true;
            continue;
        }
        if (character == '}' && inside_override) {
            inside_override = false;
            continue;
        }
        if (inside_override)
            continue;
        if (character == '\\' && input[i + 1] != '\0') {
            char escaped = input[i + 1];
            if (escaped == 'N' || escaped == 'n') {
                length = append_character(output, capacity, length, '\n');
                i++;
                continue;
            }
            if (escaped == 'h') {
                length = append_character(output, capacity, length, ' ');
                i++;
                continue;
            }
        }
        length = append_character(output, capacity, length, character);
    }
    return length;
}

size_t miraio_ass_semantic_text(
    MiraioASSContext *context,
    int64_t time_milliseconds,
    char *output,
    size_t output_capacity
) {
    if (!context || !context->track)
        return 0;

    size_t length = 0;
    bool first = true;
    for (int i = 0; i < context->track->n_events; i++) {
        ASS_Event *event = &context->track->events[i];
        if (time_milliseconds < event->Start ||
            time_milliseconds >= event->Start + event->Duration ||
            !event->Text || strstr(event->Text, "\\p") != NULL)
            continue;

        if (!first) {
            length = append_character(output, output_capacity, length, '\n');
        }
        first = false;
        length = append_plain_event_text(event->Text, output, output_capacity, length);
    }

    if (output_capacity > 0)
        output[length < output_capacity ? length : output_capacity - 1] = '\0';
    return length;
}

int miraio_ass_event_count(const MiraioASSContext *context) {
    return context && context->track ? context->track->n_events : 0;
}

bool miraio_ass_has_advanced_effects(const MiraioASSContext *context) {
    return context ? context->advanced_effects : false;
}

int miraio_ass_library_version(void) {
    return ass_library_version();
}
