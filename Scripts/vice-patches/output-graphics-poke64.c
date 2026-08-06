/*
 * POKE64 raster printer output for the VICE libretro core.
 *
 * This file replaces VICE's host graphics-export backend in the locally built
 * core. It remains part of the GPL-2.0-or-later VICE component, not the MIT
 * licensed iOS application layer.
 */
#include "vice.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "output-graphics.h"
#include "output-select.h"
#include "output.h"
#include "types.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define POKE64_PRINTER_COUNT 2

#if defined(__has_attribute)
#  if __has_attribute(retain)
#    define POKE64_RETAIN __attribute__((retain))
#  else
#    define POKE64_RETAIN
#  endif
#else
#  define POKE64_RETAIN
#endif

#if defined(__GNUC__)
#define POKE64_EXPORT \
    __attribute__((visibility("default"), used, noinline)) POKE64_RETAIN
#else
#define POKE64_EXPORT
#endif

typedef struct poke64_page_s {
    uint8_t *pixels;
    unsigned int width;
    unsigned int height;
    unsigned int dpi_x;
    unsigned int dpi_y;
    unsigned int x;
    unsigned int y;
    unsigned int sequence;
    int dirty;
} poke64_page_t;

typedef struct poke64_raw_capture_s {
    FILE *file;
    char path[PATH_MAX];
    int enabled;
} poke64_raw_capture_t;

static poke64_page_t pages[POKE64_PRINTER_COUNT];
static poke64_raw_capture_t raw_capture[POKE64_PRINTER_COUNT];
static char output_directory[PATH_MAX];

POKE64_EXPORT int poke64_printer_snapshot(unsigned int prnr);

static int valid_printer(unsigned int prnr)
{
    return prnr < POKE64_PRINTER_COUNT;
}

static void reset_page(poke64_page_t *page)
{
    if (page->pixels != NULL && page->width > 0 && page->height > 0) {
        memset(page->pixels, 255, (size_t)page->width * page->height);
    }
    page->x = 0;
    page->y = 0;
    page->dirty = 0;
}

static int allocate_page(poke64_page_t *page, const output_parameter_t *parameter)
{
    const size_t size = (size_t)parameter->maxcol * parameter->maxrow;
    uint8_t *pixels;

    if (size == 0 || parameter->maxcol > 4096 || parameter->maxrow > 8192) {
        return -1;
    }

    pixels = (uint8_t *)realloc(page->pixels, size);
    if (pixels == NULL) {
        return -1;
    }

    page->pixels = pixels;
    page->width = parameter->maxcol;
    page->height = parameter->maxrow;
    page->dpi_x = parameter->dpi_x;
    page->dpi_y = parameter->dpi_y;
    reset_page(page);
    return 0;
}

static int write_pgm(const char *path, const poke64_page_t *page)
{
    FILE *file;
    const size_t size = (size_t)page->width * page->height;

    file = fopen(path, "wb");
    if (file == NULL) {
        return -1;
    }

    if (fprintf(file, "P5\n# POKE64 MPS-803 %u %u DPI\n%u %u\n255\n",
                page->dpi_x, page->dpi_y, page->width, page->height) < 0
        || fwrite(page->pixels, 1, size, file) != size
        || fflush(file) != 0) {
        fclose(file);
        return -1;
    }
    return fclose(file) == 0 ? 0 : -1;
}

static int make_page_path(
    char *path,
    size_t path_size,
    unsigned int prnr,
    unsigned int sequence,
    int preview
)
{
    int length;

    if (output_directory[0] == '\0') {
        return -1;
    }

    if (preview) {
        length = snprintf(
            path,
            path_size,
            "%s/printer-%u-preview.pgm",
            output_directory,
            prnr + 4
        );
    } else {
        length = snprintf(
            path,
            path_size,
            "%s/printer-%u-page-%06u.pgm",
            output_directory,
            prnr + 4,
            sequence
        );
    }

    return length > 0 && (size_t)length < path_size ? 0 : -1;
}

static int write_final_page(unsigned int prnr)
{
    poke64_page_t *page;
    char path[PATH_MAX];
    FILE *existing;

    if (!valid_printer(prnr)) {
        return -1;
    }
    page = &pages[prnr];
    if (!page->dirty || page->pixels == NULL) {
        return 0;
    }

    do {
        page->sequence++;
        if (make_page_path(path, sizeof(path), prnr, page->sequence, 0) < 0) {
            return -1;
        }
        existing = fopen(path, "rb");
        if (existing != NULL) {
            fclose(existing);
        }
    } while (existing != NULL);

    if (write_pgm(path, page) < 0) {
        return -1;
    }
    if (make_page_path(path, sizeof(path), prnr, 0, 1) == 0) {
        (void)remove(path);
    }
    reset_page(page);
    return 0;
}

static int output_graphics_open(unsigned int prnr, output_parameter_t *parameter)
{
    if (!valid_printer(prnr)) {
        return -1;
    }
    return allocate_page(&pages[prnr], parameter);
}

static void output_graphics_close(unsigned int prnr)
{
    (void)prnr;
    /* IEC CLOSE does not eject physical paper. Form feed does. */
}

static int output_graphics_putc(unsigned int prnr, uint8_t value)
{
    poke64_page_t *page;

    if (!valid_printer(prnr)) {
        return -1;
    }
    page = &pages[prnr];
    if (page->pixels == NULL) {
        return -1;
    }

    if (value == OUTPUT_NEWLINE) {
        page->x = 0;
        if (page->y + 1 >= page->height) {
            return write_final_page(prnr);
        }
        page->y++;
        return 0;
    }

    if (page->x < page->width && page->y < page->height) {
        page->pixels[(size_t)page->y * page->width + page->x] =
            value == OUTPUT_PIXEL_WHITE ? 255 : 0;
        if (value != OUTPUT_PIXEL_WHITE) {
            page->dirty = 1;
        }
    }
    if (page->x + 1 < page->width) {
        page->x++;
    }
    return 0;
}

static int output_graphics_getc(unsigned int prnr, uint8_t *value)
{
    (void)prnr;
    (void)value;
    return 0;
}

static int output_graphics_flush(unsigned int prnr)
{
    return poke64_printer_snapshot(prnr);
}

static int output_graphics_formfeed(unsigned int prnr)
{
    return write_final_page(prnr);
}

void output_graphics_init(void)
{
    unsigned int i;
    for (i = 0; i < POKE64_PRINTER_COUNT; ++i) {
        pages[i].sequence = 0;
        reset_page(&pages[i]);
    }
}

void output_graphics_shutdown(void)
{
    unsigned int i;
    for (i = 0; i < POKE64_PRINTER_COUNT; ++i) {
        free(pages[i].pixels);
        pages[i].pixels = NULL;
        if (raw_capture[i].file != NULL) {
            fclose(raw_capture[i].file);
            raw_capture[i].file = NULL;
        }
    }
}

int output_graphics_init_resources(void)
{
    output_select_t output_select;
    output_select.output_name = "graphics";
    output_select.output_open = output_graphics_open;
    output_select.output_close = output_graphics_close;
    output_select.output_putc = output_graphics_putc;
    output_select.output_getc = output_graphics_getc;
    output_select.output_flush = output_graphics_flush;
    output_select.output_formfeed = output_graphics_formfeed;
    output_select_register(&output_select);
    return 0;
}

POKE64_EXPORT void poke64_printer_set_output_directory(const char *path)
{
    unsigned int prnr;
    char preview_path[PATH_MAX];

    if (path == NULL) {
        output_directory[0] = '\0';
        return;
    }
    snprintf(output_directory, sizeof(output_directory), "%s", path);

    /* A preview represents volatile, in-progress paper. A restarted core cannot
     * restore the MPS-803 interpreter state, so never expose a stale preview. */
    for (prnr = 0; prnr < POKE64_PRINTER_COUNT; ++prnr) {
        if (make_page_path(preview_path, sizeof(preview_path), prnr, 0, 1) == 0) {
            (void)remove(preview_path);
        }
    }
}

POKE64_EXPORT int poke64_printer_snapshot(unsigned int prnr)
{
    char path[PATH_MAX];
    poke64_page_t *page;

    if (!valid_printer(prnr)) {
        return -1;
    }
    page = &pages[prnr];
    if (page->pixels == NULL || !page->dirty) {
        return 0;
    }
    if (make_page_path(path, sizeof(path), prnr, 0, 1) < 0) {
        return -1;
    }
    return write_pgm(path, page);
}

POKE64_EXPORT void poke64_printer_configure_raw_capture(
    unsigned int prnr,
    int enabled,
    const char *path
)
{
    poke64_raw_capture_t *capture;

    if (!valid_printer(prnr)) {
        return;
    }
    capture = &raw_capture[prnr];
    if (capture->file != NULL) {
        fflush(capture->file);
        fclose(capture->file);
        capture->file = NULL;
    }
    capture->enabled = enabled ? 1 : 0;
    capture->path[0] = '\0';
    if (path != NULL) {
        snprintf(capture->path, sizeof(capture->path), "%s", path);
    }
}

POKE64_EXPORT void poke64_printer_capture_byte(unsigned int prnr, uint8_t value)
{
    poke64_raw_capture_t *capture;

    if (!valid_printer(prnr)) {
        return;
    }
    capture = &raw_capture[prnr];
    if (!capture->enabled || capture->path[0] == '\0') {
        return;
    }
    if (capture->file == NULL) {
        capture->file = fopen(capture->path, "ab");
        if (capture->file == NULL) {
            return;
        }
    }
    fputc(value, capture->file);
}

POKE64_EXPORT void poke64_printer_capture_formfeed(unsigned int prnr)
{
    if (!valid_printer(prnr)) {
        return;
    }
    if (raw_capture[prnr].file != NULL) {
        fflush(raw_capture[prnr].file);
    }
}
