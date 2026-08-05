#ifndef LIBRETRO_MINIMAL_H
#define LIBRETRO_MINIMAL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RETRO_API_VERSION 1

#define RETRO_DEVICE_NONE 0
#define RETRO_DEVICE_JOYPAD 1
#define RETRO_DEVICE_MOUSE 2
#define RETRO_DEVICE_KEYBOARD 3
#define RETRO_DEVICE_LIGHTGUN 4
#define RETRO_DEVICE_ANALOG 5
#define RETRO_DEVICE_POINTER 6
#define RETRO_DEVICE_MASK 0xff

#define RETRO_DEVICE_ID_JOYPAD_B 0
#define RETRO_DEVICE_ID_JOYPAD_Y 1
#define RETRO_DEVICE_ID_JOYPAD_SELECT 2
#define RETRO_DEVICE_ID_JOYPAD_START 3
#define RETRO_DEVICE_ID_JOYPAD_UP 4
#define RETRO_DEVICE_ID_JOYPAD_DOWN 5
#define RETRO_DEVICE_ID_JOYPAD_LEFT 6
#define RETRO_DEVICE_ID_JOYPAD_RIGHT 7
#define RETRO_DEVICE_ID_JOYPAD_A 8
#define RETRO_DEVICE_ID_JOYPAD_X 9
#define RETRO_DEVICE_ID_JOYPAD_L 10
#define RETRO_DEVICE_ID_JOYPAD_R 11
#define RETRO_DEVICE_ID_JOYPAD_L2 12
#define RETRO_DEVICE_ID_JOYPAD_R2 13
#define RETRO_DEVICE_ID_JOYPAD_L3 14
#define RETRO_DEVICE_ID_JOYPAD_R3 15
#define RETRO_DEVICE_ID_JOYPAD_MASK 256

#define RETRO_DEVICE_ID_MOUSE_X 0
#define RETRO_DEVICE_ID_MOUSE_Y 1
#define RETRO_DEVICE_ID_MOUSE_LEFT 2
#define RETRO_DEVICE_ID_MOUSE_RIGHT 3
#define RETRO_DEVICE_ID_MOUSE_MIDDLE 4

#define RETRO_ENVIRONMENT_SET_ROTATION 1
#define RETRO_ENVIRONMENT_GET_OVERSCAN 2
#define RETRO_ENVIRONMENT_GET_CAN_DUPE 3
#define RETRO_ENVIRONMENT_SET_MESSAGE 6
#define RETRO_ENVIRONMENT_SHUTDOWN 7
#define RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL 8
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY 9
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT 10
#define RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS 11
#define RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK 12
#define RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE 13
#define RETRO_ENVIRONMENT_GET_VARIABLE 15
#define RETRO_ENVIRONMENT_SET_VARIABLES 16
#define RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE 17
#define RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME 18
#define RETRO_ENVIRONMENT_GET_LOG_INTERFACE 27
#define RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY 30
#define RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY 31
#define RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO 32
#define RETRO_ENVIRONMENT_SET_GEOMETRY 37
#define RETRO_ENVIRONMENT_GET_USERNAME 38
#define RETRO_ENVIRONMENT_GET_LANGUAGE 39
#define RETRO_ENVIRONMENT_GET_LED_INTERFACE 46
#define RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE 47
#define RETRO_ENVIRONMENT_GET_FASTFORWARDING 49
#define RETRO_ENVIRONMENT_GET_TARGET_REFRESH_RATE 50
#define RETRO_ENVIRONMENT_GET_INPUT_BITMASKS 51
#define RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION 52
#define RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION 57
#define RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE 58
#define RETRO_ENVIRONMENT_GET_MESSAGE_INTERFACE_VERSION 59
#define RETRO_ENVIRONMENT_SET_MINIMUM_AUDIO_LATENCY 63
#define RETRO_ENVIRONMENT_SET_VARIABLE 70

#define RETRO_LANGUAGE_ENGLISH 0

struct retro_game_info {
    const char *path;
    const void *data;
    size_t size;
    const char *meta;
};

struct retro_system_info {
    const char *library_name;
    const char *library_version;
    const char *valid_extensions;
    bool need_fullpath;
    bool block_extract;
};

struct retro_game_geometry {
    unsigned base_width;
    unsigned base_height;
    unsigned max_width;
    unsigned max_height;
    float aspect_ratio;
};

struct retro_system_timing {
    double fps;
    double sample_rate;
};

struct retro_system_av_info {
    struct retro_game_geometry geometry;
    struct retro_system_timing timing;
};

struct retro_variable {
    const char *key;
    const char *value;
};

struct retro_message {
    const char *msg;
    unsigned frames;
};

enum retro_pixel_format {
    RETRO_PIXEL_FORMAT_0RGB1555 = 0,
    RETRO_PIXEL_FORMAT_XRGB8888 = 1,
    RETRO_PIXEL_FORMAT_RGB565 = 2,
    RETRO_PIXEL_FORMAT_UNKNOWN = INT32_MAX
};

enum retro_log_level {
    RETRO_LOG_DEBUG = 0,
    RETRO_LOG_INFO,
    RETRO_LOG_WARN,
    RETRO_LOG_ERROR,
    RETRO_LOG_DUMMY = INT32_MAX
};

enum retro_key {
    RETROK_UNKNOWN = 0,
    RETROK_BACKSPACE = 8,
    RETROK_TAB = 9,
    RETROK_CLEAR = 12,
    RETROK_RETURN = 13,
    RETROK_PAUSE = 19,
    RETROK_ESCAPE = 27,
    RETROK_SPACE = 32,
    RETROK_0 = 48,
    RETROK_1 = 49,
    RETROK_2 = 50,
    RETROK_3 = 51,
    RETROK_4 = 52,
    RETROK_5 = 53,
    RETROK_6 = 54,
    RETROK_7 = 55,
    RETROK_8 = 56,
    RETROK_9 = 57,
    RETROK_a = 97,
    RETROK_b = 98,
    RETROK_c = 99,
    RETROK_d = 100,
    RETROK_e = 101,
    RETROK_f = 102,
    RETROK_g = 103,
    RETROK_h = 104,
    RETROK_i = 105,
    RETROK_j = 106,
    RETROK_k = 107,
    RETROK_l = 108,
    RETROK_m = 109,
    RETROK_n = 110,
    RETROK_o = 111,
    RETROK_p = 112,
    RETROK_q = 113,
    RETROK_r = 114,
    RETROK_s = 115,
    RETROK_t = 116,
    RETROK_u = 117,
    RETROK_v = 118,
    RETROK_w = 119,
    RETROK_x = 120,
    RETROK_y = 121,
    RETROK_z = 122,
    RETROK_DELETE = 127,
    RETROK_UP = 273,
    RETROK_DOWN = 274,
    RETROK_RIGHT = 275,
    RETROK_LEFT = 276,
    RETROK_INSERT = 277,
    RETROK_HOME = 278,
    RETROK_END = 279,
    RETROK_PAGEUP = 280,
    RETROK_PAGEDOWN = 281,
    RETROK_F1 = 282,
    RETROK_F2 = 283,
    RETROK_F3 = 284,
    RETROK_F4 = 285,
    RETROK_F5 = 286,
    RETROK_F6 = 287,
    RETROK_F7 = 288,
    RETROK_F8 = 289,
    RETROK_F9 = 290,
    RETROK_F10 = 291,
    RETROK_F11 = 292,
    RETROK_F12 = 293,
    RETROK_RSHIFT = 303,
    RETROK_LSHIFT = 304,
    RETROK_RCTRL = 305,
    RETROK_LCTRL = 306,
    RETROK_RALT = 307,
    RETROK_LALT = 308
};

typedef bool (*retro_environment_t)(unsigned cmd, void *data);
typedef void (*retro_video_refresh_t)(const void *data, unsigned width, unsigned height, size_t pitch);
typedef void (*retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t (*retro_audio_sample_batch_t)(const int16_t *data, size_t frames);
typedef void (*retro_input_poll_t)(void);
typedef int16_t (*retro_input_state_t)(unsigned port, unsigned device, unsigned index, unsigned id);
typedef void (*retro_keyboard_event_t)(bool down, unsigned keycode, uint32_t character, uint16_t key_modifiers);
typedef void (*retro_log_printf_t)(enum retro_log_level level, const char *fmt, ...);

struct retro_keyboard_callback {
    retro_keyboard_event_t callback;
};

struct retro_log_callback {
    retro_log_printf_t log;
};

struct retro_disk_control_callback {
    bool (*set_eject_state)(bool ejected);
    bool (*get_eject_state)(void);
    unsigned (*get_image_index)(void);
    bool (*set_image_index)(unsigned index);
    unsigned (*get_num_images)(void);
    bool (*replace_image_index)(unsigned index, const struct retro_game_info *info);
    bool (*add_image_index)(void);
};

struct retro_disk_control_ext_callback {
    bool (*set_eject_state)(bool ejected);
    bool (*get_eject_state)(void);
    unsigned (*get_image_index)(void);
    bool (*set_image_index)(unsigned index);
    unsigned (*get_num_images)(void);
    bool (*replace_image_index)(unsigned index, const struct retro_game_info *info);
    bool (*add_image_index)(void);
    bool (*set_initial_image)(unsigned index, const char *path);
    bool (*get_image_path)(unsigned index, char *path, size_t len);
    bool (*get_image_label)(unsigned index, char *label, size_t len);
};

#ifdef __cplusplus
}
#endif

#endif
