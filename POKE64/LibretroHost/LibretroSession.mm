#import "LibretroSession.h"
#import "C64MetalView.h"
#import "LibretroMinimal.h"

#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <climits>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

static NSString * const C64LibretroErrorDomain = @"C64LibretroErrorDomain";

namespace {

class AudioRingBuffer {
public:
    explicit AudioRingBuffer(size_t stereoFrameCapacity = 96000)
        : samples_(stereoFrameCapacity * 2, 0), capacityFrames_(stereoFrameCapacity) {}

    void clear() {
        readFrame_.store(0, std::memory_order_release);
        writeFrame_.store(0, std::memory_order_release);
    }

    void push(const int16_t *interleaved, size_t frames) {
        if (!interleaved || frames == 0) return;

        uint64_t write = writeFrame_.load(std::memory_order_relaxed);
        uint64_t read = readFrame_.load(std::memory_order_acquire);
        if (frames > capacityFrames_) {
            interleaved += (frames - capacityFrames_) * 2;
            frames = capacityFrames_;
        }

        const uint64_t used = write - read;
        if (used + frames > capacityFrames_) {
            readFrame_.store(write + frames - capacityFrames_, std::memory_order_release);
        }

        for (size_t frame = 0; frame < frames; ++frame) {
            const size_t index = static_cast<size_t>((write + frame) % capacityFrames_) * 2;
            samples_[index] = interleaved[frame * 2];
            samples_[index + 1] = interleaved[frame * 2 + 1];
        }
        writeFrame_.store(write + frames, std::memory_order_release);
    }

    bool pop(float &left, float &right) {
        uint64_t read = readFrame_.load(std::memory_order_relaxed);
        const uint64_t write = writeFrame_.load(std::memory_order_acquire);
        if (read >= write) {
            left = 0.0f;
            right = 0.0f;
            return false;
        }

        const size_t index = static_cast<size_t>(read % capacityFrames_) * 2;
        left = static_cast<float>(samples_[index]) / 32768.0f;
        right = static_cast<float>(samples_[index + 1]) / 32768.0f;
        readFrame_.store(read + 1, std::memory_order_release);
        return true;
    }

private:
    std::vector<int16_t> samples_;
    size_t capacityFrames_;
    std::atomic<uint64_t> readFrame_{0};
    std::atomic<uint64_t> writeFrame_{0};
};

struct CoreAPI {
    unsigned (*retro_api_version)(void) = nullptr;
    void (*retro_set_environment)(retro_environment_t) = nullptr;
    void (*retro_set_video_refresh)(retro_video_refresh_t) = nullptr;
    void (*retro_set_audio_sample)(retro_audio_sample_t) = nullptr;
    void (*retro_set_audio_sample_batch)(retro_audio_sample_batch_t) = nullptr;
    void (*retro_set_input_poll)(retro_input_poll_t) = nullptr;
    void (*retro_set_input_state)(retro_input_state_t) = nullptr;
    void (*retro_set_controller_port_device)(unsigned, unsigned) = nullptr;
    void (*retro_init)(void) = nullptr;
    void (*retro_deinit)(void) = nullptr;
    void (*retro_get_system_info)(retro_system_info *) = nullptr;
    void (*retro_get_system_av_info)(retro_system_av_info *) = nullptr;
    bool (*retro_load_game)(const retro_game_info *) = nullptr;
    void (*retro_unload_game)(void) = nullptr;
    void (*retro_run)(void) = nullptr;
    void (*retro_reset)(void) = nullptr;
    void (*emu_reset)(int) = nullptr;
    int (*file_system_attach_disk)(unsigned int, unsigned int, const char *) = nullptr;
    void (*file_system_detach_disk)(unsigned int, unsigned int) = nullptr;
    void (*file_system_detach_disk_all)(void) = nullptr;
    int (*machine_bus_device_detach)(unsigned int) = nullptr;
    int (*tape_image_attach)(unsigned int, const char *) = nullptr;
    int (*tape_image_detach)(unsigned int) = nullptr;
    void (*tape_image_detach_all)(void) = nullptr;
    int (*cartridge_attach_image)(int, const char *) = nullptr;
    void (*cartridge_detach_image)(int) = nullptr;
    int (*autostart_disk)(int, int, const char *, const char *, unsigned int, unsigned int) = nullptr;
    int (*autostart_tape)(const char *, const char *, unsigned int, unsigned int, unsigned int) = nullptr;
    int (*autostart_prg)(const char *, unsigned int) = nullptr;
};

enum class MediaCommandType {
    AttachDisk,
    AutostartDisk,
    AttachTape,
    AutostartTape,
    RunProgram,
    AttachCartridge,
    EjectDisk,
    EjectTape,
    EjectCartridge,
    EjectAllAndReset
};

struct MediaCommand {
    MediaCommandType type;
    std::string path;
    int unit = 0;
    std::mutex mutex;
    std::condition_variable condition;
    bool completed = false;
    bool success = false;
    std::string error;
};

struct KeyEvent {
    bool down;
    unsigned key;
};

struct SessionImpl {
    void *coreHandle = nullptr;
    CoreAPI api;
    __weak C64MetalView *videoView = nil;
    std::atomic<bool> running{false};
    std::atomic<int> resetModeRequested{-1};
    std::atomic<bool> shutdownRequested{false};
    std::thread coreThread;
    std::array<std::atomic<uint32_t>, 2> joypadMasks{};
    std::atomic<unsigned> currentJoyport{1};
    std::atomic<unsigned> mousePort{0};
    std::atomic<int> mouseDeltaX{0};
    std::atomic<int> mouseDeltaY{0};
    std::atomic<uint32_t> mouseButtons{0};
    std::mutex keyMutex;
    std::vector<KeyEvent> keyEvents;
    std::mutex mediaCommandMutex;
    std::deque<std::shared_ptr<MediaCommand>> mediaCommands;
    retro_keyboard_event_t keyboardCallback = nullptr;
    retro_pixel_format pixelFormat = RETRO_PIXEL_FORMAT_0RGB1555;
    retro_disk_control_callback diskControl{};
    retro_disk_control_ext_callback diskControlExt{};
    bool hasDiskControl = false;
    bool hasDiskControlExt = false;
    std::map<std::string, std::string> variables;
    std::atomic<bool> variablesUpdated{false};
    std::string systemDirectory;
    std::string saveDirectory;
    std::string assetsDirectory;
    std::string contentPath;
    double fps = 50.0;
    double sampleRate = 48000.0;
    AudioRingBuffer audioRing;
    AVAudioEngine *audioEngine = nil;
    AVAudioSourceNode *audioSource = nil;
    std::mutex diagnosticMutex;
    std::string lastCoreMessage;
    std::string lastCoreError;
    std::mutex startupMutex;
    std::condition_variable startupCondition;
    bool firstRunCompleted = false;

    SessionImpl() {
        clearInputState();
    }

    unsigned retroPortForC64Port(unsigned c64Port) const {
        const unsigned current = currentJoyport.load(std::memory_order_acquire);
        return c64Port == current ? 0u : 1u;
    }

    void clearInputState() {
        for (auto &mask : joypadMasks) {
            mask.store(0, std::memory_order_release);
        }
        mouseDeltaX.store(0, std::memory_order_release);
        mouseDeltaY.store(0, std::memory_order_release);
        mouseButtons.store(0, std::memory_order_release);
    }

    void clearCoreDiagnostics() {
        std::lock_guard<std::mutex> lock(diagnosticMutex);
        lastCoreMessage.clear();
        lastCoreError.clear();
    }

    static bool isGenericStartupError(const std::string &value) {
        return value == "Core startup failed with error:" ||
               value == "Core startup without parameters failed with error:";
    }

    void recordCoreMessage(const char *message, bool isError) {
        if (!message || !*message) return;
        std::string value(message);
        while (!value.empty() && (value.back() == '\n' || value.back() == '\r')) {
            value.pop_back();
        }
        if (value.empty()) return;

        std::lock_guard<std::mutex> lock(diagnosticMutex);
        lastCoreMessage = value;
        if (isError && (!isGenericStartupError(value) || lastCoreError.empty())) {
            lastCoreError = value;
        }
    }

    std::string startupFailureMessage(const char *fallback) {
        std::lock_guard<std::mutex> lock(diagnosticMutex);
        if (!lastCoreError.empty()) return lastCoreError;
        if (!lastCoreMessage.empty()) return lastCoreMessage;
        return fallback ? fallback : "VICE requested shutdown during startup";
    }

    ~SessionImpl() {
        stop();
        unloadCore();
    }

    static std::string pathForDirectory(NSSearchPathDirectory directory, NSString *child) {
        NSFileManager *manager = NSFileManager.defaultManager;
        NSURL *base = [manager URLForDirectory:directory
                                      inDomain:NSUserDomainMask
                             appropriateForURL:nil
                                        create:YES
                                         error:nil];
        NSURL *url = [base URLByAppendingPathComponent:child isDirectory:YES];
        [manager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
        return std::string(url.fileSystemRepresentation);
    }

    void configureDirectories() {
        systemDirectory = pathForDirectory(NSApplicationSupportDirectory, @"System");
        saveDirectory = pathForDirectory(NSDocumentDirectory, @"Saves");
        assetsDirectory = pathForDirectory(NSApplicationSupportDirectory, @"Assets");

        NSString *system = [NSString stringWithUTF8String:systemDirectory.c_str()];
        NSURL *vice = [[NSURL fileURLWithPath:system] URLByAppendingPathComponent:@"vice" isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:vice
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:nil];
    }

    NSURL *coreURL() const {
        NSBundle *bundle = NSBundle.mainBundle;
        NSURL *frameworks = bundle.privateFrameworksURL;
        NSURL *candidate = [frameworks URLByAppendingPathComponent:@"vice_x64sc_libretro_ios.dylib"];
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate.path]) {
            return candidate;
        }
        return [bundle URLForResource:@"vice_x64sc_libretro_ios" withExtension:@"dylib"];
    }

    template <typename T>
    bool loadSymbol(T &target, const char *name, std::string &error) {
        target = reinterpret_cast<T>(dlsym(coreHandle, name));
        if (!target) {
            error = std::string("Missing libretro symbol: ") + name;
            return false;
        }
        return true;
    }

    bool loadCore(std::string &error) {
        if (coreHandle) return true;
        configureDirectories();

        NSURL *url = coreURL();
        if (!url) {
            error = "Core not found. Run Scripts/build_vice_core.sh on macOS, then rebuild the app.";
            return false;
        }

        coreHandle = dlopen(url.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (!coreHandle) {
            error = std::string("dlopen failed: ") + (dlerror() ?: "unknown error");
            return false;
        }

#define LOAD_CORE_SYMBOL(symbol) if (!loadSymbol(api.symbol, #symbol, error)) return false
        LOAD_CORE_SYMBOL(retro_api_version);
        LOAD_CORE_SYMBOL(retro_set_environment);
        LOAD_CORE_SYMBOL(retro_set_video_refresh);
        LOAD_CORE_SYMBOL(retro_set_audio_sample);
        LOAD_CORE_SYMBOL(retro_set_audio_sample_batch);
        LOAD_CORE_SYMBOL(retro_set_input_poll);
        LOAD_CORE_SYMBOL(retro_set_input_state);
        LOAD_CORE_SYMBOL(retro_set_controller_port_device);
        LOAD_CORE_SYMBOL(retro_init);
        LOAD_CORE_SYMBOL(retro_deinit);
        LOAD_CORE_SYMBOL(retro_get_system_info);
        LOAD_CORE_SYMBOL(retro_get_system_av_info);
        LOAD_CORE_SYMBOL(retro_load_game);
        LOAD_CORE_SYMBOL(retro_unload_game);
        LOAD_CORE_SYMBOL(retro_run);
        LOAD_CORE_SYMBOL(retro_reset);
#undef LOAD_CORE_SYMBOL

        // VICE-libretro exposes emu_reset() from libretro-core.c. It allows
        // POKE64 to request a real soft or hard machine reset without using
        // retro_reset(), whose default action autostarts the current content.
        api.emu_reset = reinterpret_cast<void (*)(int)>(dlsym(coreHandle, "emu_reset"));

        // Native VICE entry points used for media changes while the core is
        // already running. These are optional at startup so an older core can
        // still boot; individual media commands report a precise error when a
        // required entry point is unavailable.
        api.file_system_attach_disk = reinterpret_cast<int (*)(unsigned int, unsigned int, const char *)>(
            dlsym(coreHandle, "file_system_attach_disk")
        );
        api.file_system_detach_disk = reinterpret_cast<void (*)(unsigned int, unsigned int)>(
            dlsym(coreHandle, "file_system_detach_disk")
        );
        api.file_system_detach_disk_all = reinterpret_cast<void (*)(void)>(
            dlsym(coreHandle, "file_system_detach_disk_all")
        );
        api.machine_bus_device_detach = reinterpret_cast<int (*)(unsigned int)>(
            dlsym(coreHandle, "machine_bus_device_detach")
        );
        api.tape_image_attach = reinterpret_cast<int (*)(unsigned int, const char *)>(
            dlsym(coreHandle, "tape_image_attach")
        );
        api.tape_image_detach = reinterpret_cast<int (*)(unsigned int)>(
            dlsym(coreHandle, "tape_image_detach")
        );
        api.tape_image_detach_all = reinterpret_cast<void (*)(void)>(
            dlsym(coreHandle, "tape_image_detach_all")
        );
        api.cartridge_attach_image = reinterpret_cast<int (*)(int, const char *)>(
            dlsym(coreHandle, "cartridge_attach_image")
        );
        api.cartridge_detach_image = reinterpret_cast<void (*)(int)>(
            dlsym(coreHandle, "cartridge_detach_image")
        );
        api.autostart_disk = reinterpret_cast<int (*)(int, int, const char *, const char *, unsigned int, unsigned int)>(
            dlsym(coreHandle, "autostart_disk")
        );
        api.autostart_tape = reinterpret_cast<int (*)(const char *, const char *, unsigned int, unsigned int, unsigned int)>(
            dlsym(coreHandle, "autostart_tape")
        );
        api.autostart_prg = reinterpret_cast<int (*)(const char *, unsigned int)>(
            dlsym(coreHandle, "autostart_prg")
        );

        if (api.retro_api_version() != RETRO_API_VERSION) {
            error = "Incompatible libretro API version";
            return false;
        }
        return true;
    }

    void unloadCore() {
        if (coreHandle) {
            dlclose(coreHandle);
            coreHandle = nullptr;
        }
        api = {};
    }

    bool start(const char *path, std::string &error);

    void completeMediaCommand(
        const std::shared_ptr<MediaCommand> &command,
        bool success,
        const std::string &error = {}
    ) {
        {
            std::lock_guard<std::mutex> lock(command->mutex);
            command->success = success;
            command->error = error;
            command->completed = true;
        }
        command->condition.notify_all();
    }

    void failPendingMediaCommands(const char *message) {
        std::deque<std::shared_ptr<MediaCommand>> pending;
        {
            std::lock_guard<std::mutex> lock(mediaCommandMutex);
            pending.swap(mediaCommands);
        }
        const char *resolvedMessage = message ? message : "The core is not running";
        for (const auto &command : pending) {
            completeMediaCommand(command, false, resolvedMessage);
        }
    }

    bool executeMediaCommand(const std::shared_ptr<MediaCommand> &command, std::string &error) {
        constexpr unsigned int kTapePort = 1;
        constexpr unsigned int kAutostartModeRun = 0;
        constexpr int kCartridgeCRT = 0;

        switch (command->type) {
            case MediaCommandType::AttachDisk:
                if (!api.file_system_attach_disk) {
                    error = "The VICE core does not expose runtime disk attachment";
                    return false;
                }
                if (api.file_system_attach_disk(
                        static_cast<unsigned int>(command->unit),
                        0,
                        command->path.c_str()
                    ) != 0) {
                    error = "VICE could not insert the selected disk";
                    return false;
                }
                return true;

            case MediaCommandType::AutostartDisk:
                if (!api.autostart_disk) {
                    error = "The VICE core does not expose disk autostart";
                    return false;
                }
                if (api.autostart_disk(
                        command->unit,
                        0,
                        command->path.c_str(),
                        nullptr,
                        0,
                        kAutostartModeRun
                    ) != 0) {
                    error = "VICE could not autostart the selected disk";
                    return false;
                }
                return true;

            case MediaCommandType::AttachTape:
                if (!api.tape_image_attach) {
                    error = "The VICE core does not expose runtime tape attachment";
                    return false;
                }
                if (api.tape_image_attach(kTapePort, command->path.c_str()) != 0) {
                    error = "VICE could not insert the selected tape";
                    return false;
                }
                return true;

            case MediaCommandType::AutostartTape:
                if (!api.autostart_tape) {
                    error = "The VICE core does not expose tape autostart";
                    return false;
                }
                if (api.autostart_tape(
                        command->path.c_str(),
                        nullptr,
                        0,
                        kAutostartModeRun,
                        kTapePort
                    ) != 0) {
                    error = "VICE could not autostart the selected tape";
                    return false;
                }
                return true;

            case MediaCommandType::RunProgram:
                if (!api.autostart_prg) {
                    error = "The VICE core does not expose PRG autostart";
                    return false;
                }
                if (api.autostart_prg(command->path.c_str(), kAutostartModeRun) != 0) {
                    error = "VICE could not run the selected program";
                    return false;
                }
                return true;

            case MediaCommandType::AttachCartridge:
                if (!api.cartridge_attach_image) {
                    error = "The VICE core does not expose runtime cartridge attachment";
                    return false;
                }
                if (api.cartridge_attach_image(kCartridgeCRT, command->path.c_str()) != 0) {
                    error = "VICE could not insert the selected cartridge";
                    return false;
                }
                if (api.emu_reset) {
                    api.emu_reset(2);
                } else {
                    api.retro_reset();
                }
                return true;

            case MediaCommandType::EjectDisk:
                if (!api.file_system_detach_disk) {
                    error = "The VICE core does not expose runtime disk ejection";
                    return false;
                }
                api.file_system_detach_disk(static_cast<unsigned int>(command->unit), 0);
                // VICE restores its host-filesystem backend after detaching an
                // image. Remove those serial hooks so an empty drive reports
                // DEVICE NOT PRESENT instead of listing the app sandbox.
                if (api.machine_bus_device_detach) {
                    api.machine_bus_device_detach(
                        static_cast<unsigned int>(command->unit)
                    );
                }
                return true;

            case MediaCommandType::EjectTape:
                if (!api.tape_image_detach) {
                    error = "The VICE core does not expose runtime tape ejection";
                    return false;
                }
                if (api.tape_image_detach(kTapePort) != 0) {
                    error = "VICE could not eject the current tape";
                    return false;
                }
                return true;

            case MediaCommandType::EjectCartridge:
                if (!api.cartridge_detach_image) {
                    error = "The VICE core does not expose runtime cartridge ejection";
                    return false;
                }
                api.cartridge_detach_image(-1);
                return true;

            case MediaCommandType::EjectAllAndReset:
                if (!api.file_system_detach_disk_all ||
                    !api.tape_image_detach_all ||
                    !api.cartridge_detach_image) {
                    error = "The VICE core does not expose complete media ejection";
                    return false;
                }
                api.file_system_detach_disk_all();
                if (api.machine_bus_device_detach) {
                    for (unsigned int unit = 8; unit <= 11; ++unit) {
                        api.machine_bus_device_detach(unit);
                    }
                }
                api.tape_image_detach_all();
                api.cartridge_detach_image(-1);
                if (api.emu_reset) {
                    api.emu_reset(2);
                } else {
                    api.retro_reset();
                }
                return true;
        }
        error = "Unknown media command";
        return false;
    }

    void drainMediaCommands() {
        std::deque<std::shared_ptr<MediaCommand>> pending;
        {
            std::lock_guard<std::mutex> lock(mediaCommandMutex);
            pending.swap(mediaCommands);
        }

        for (const auto &command : pending) {
            std::string error;
            const bool success = executeMediaCommand(command, error);
            completeMediaCommand(command, success, error);
        }
    }

    bool performMediaCommand(
        MediaCommandType type,
        const char *path,
        int unit,
        std::string &error
    ) {
        if (!running.load(std::memory_order_acquire)) {
            error = "The C64 core is not running";
            return false;
        }

        auto command = std::make_shared<MediaCommand>();
        command->type = type;
        command->unit = unit;
        if (path) command->path = path;

        {
            std::lock_guard<std::mutex> lock(mediaCommandMutex);
            mediaCommands.push_back(command);
        }

        std::unique_lock<std::mutex> lock(command->mutex);
        bool completed = command->condition.wait_for(
            lock,
            std::chrono::seconds(3),
            [&command] { return command->completed; }
        );
        if (!completed) {
            lock.unlock();

            bool removedBeforeExecution = false;
            {
                std::lock_guard<std::mutex> queueLock(mediaCommandMutex);
                const auto iterator = std::find(mediaCommands.begin(), mediaCommands.end(), command);
                if (iterator != mediaCommands.end()) {
                    mediaCommands.erase(iterator);
                    removedBeforeExecution = true;
                }
            }

            if (removedBeforeExecution) {
                error = "VICE did not begin the media operation in time";
                return false;
            }

            lock.lock();
            completed = command->condition.wait_for(
                lock,
                std::chrono::seconds(7),
                [&command] { return command->completed; }
            );
            if (!completed) {
                error = "VICE did not complete the media operation in time";
                return false;
            }
        }
        error = command->error;
        return command->success;
    }

    void stop() {
        running.store(false, std::memory_order_release);
        failPendingMediaCommands("The core stopped before completing the media operation");
        if (coreThread.joinable() && coreThread.get_id() != std::this_thread::get_id()) {
            coreThread.join();
        }
        stopAudio();
    }

    void startAudio() {
        stopAudio();
        audioRing.clear();

        AVAudioSession *session = AVAudioSession.sharedInstance;
        [session setCategory:AVAudioSessionCategoryPlayback
                        mode:AVAudioSessionModeDefault
                     options:AVAudioSessionCategoryOptionMixWithOthers
                       error:nil];
        [session setPreferredIOBufferDuration:0.01 error:nil];
        [session setActive:YES error:nil];

        const double rate = sampleRate > 1000.0 ? sampleRate : 48000.0;
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate channels:2];
        AudioRingBuffer *ring = &audioRing;

        audioSource = [[AVAudioSourceNode alloc]
            initWithFormat:format
            renderBlock:^OSStatus(BOOL *isSilence,
                                  const AudioTimeStamp *timestamp,
                                  AVAudioFrameCount frameCount,
                                  AudioBufferList *outputData) {
                (void)timestamp;
                bool any = false;
                for (AVAudioFrameCount frame = 0; frame < frameCount; ++frame) {
                    float left = 0.0f;
                    float right = 0.0f;
                    any |= ring->pop(left, right);

                    if (outputData->mNumberBuffers >= 2) {
                        static_cast<float *>(outputData->mBuffers[0].mData)[frame] = left;
                        static_cast<float *>(outputData->mBuffers[1].mData)[frame] = right;
                    } else if (outputData->mNumberBuffers == 1) {
                        float *interleaved = static_cast<float *>(outputData->mBuffers[0].mData);
                        interleaved[frame * 2] = left;
                        interleaved[frame * 2 + 1] = right;
                    }
                }
                if (isSilence) *isSilence = !any;
                return noErr;
            }];

        audioEngine = [[AVAudioEngine alloc] init];
        [audioEngine attachNode:audioSource];
        [audioEngine connect:audioSource to:audioEngine.mainMixerNode format:format];
        [audioEngine prepare];
        NSError *error = nil;
        if (![audioEngine startAndReturnError:&error]) {
            NSLog(@"AVAudioEngine: %@", error);
        }
    }

    void stopAudio() {
        if (audioEngine) {
            [audioEngine stop];
            if (audioSource) [audioEngine detachNode:audioSource];
        }
        audioSource = nil;
        audioEngine = nil;
        audioRing.clear();
    }

    void drainKeyEvents() {
        std::vector<KeyEvent> pending;
        {
            std::lock_guard<std::mutex> lock(keyMutex);
            pending.swap(keyEvents);
        }
        if (!keyboardCallback) return;
        for (const KeyEvent &event : pending) {
            keyboardCallback(event.down, event.key, 0, 0);
        }
    }
};

static SessionImpl *gSession = nullptr;

static void frontendLog(enum retro_log_level level, const char *format, ...) {
    const char *prefix = "INFO";
    if (level == RETRO_LOG_DEBUG) prefix = "DEBUG";
    else if (level == RETRO_LOG_WARN) prefix = "WARN";
    else if (level == RETRO_LOG_ERROR) prefix = "ERROR";

    char buffer[4096] = {};
    va_list arguments;
    va_start(arguments, format);
    std::vsnprintf(buffer, sizeof(buffer), format, arguments);
    va_end(arguments);

    std::fprintf(stderr, "[VICE/%s] %s", prefix, buffer);
    if (gSession) {
        gSession->recordCoreMessage(buffer, level == RETRO_LOG_WARN || level == RETRO_LOG_ERROR);
    }
}

static bool environmentCallback(unsigned command, void *data) {
    SessionImpl *session = gSession;
    if (!session) return false;

    switch (command) {
        case RETRO_ENVIRONMENT_GET_CAN_DUPE:
            *static_cast<bool *>(data) = true;
            return true;

        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
            *static_cast<const char **>(data) = session->systemDirectory.c_str();
            return true;

        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
            *static_cast<const char **>(data) = session->saveDirectory.c_str();
            return true;

        case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY:
            *static_cast<const char **>(data) = session->assetsDirectory.c_str();
            return true;

        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            const auto requested = *static_cast<const retro_pixel_format *>(data);
            if (requested != RETRO_PIXEL_FORMAT_0RGB1555 &&
                requested != RETRO_PIXEL_FORMAT_XRGB8888 &&
                requested != RETRO_PIXEL_FORMAT_RGB565) {
                return false;
            }
            session->pixelFormat = requested;
            return true;
        }

        case RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK:
            session->keyboardCallback = static_cast<retro_keyboard_callback *>(data)->callback;
            return true;

        case RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE:
            session->diskControl = *static_cast<retro_disk_control_callback *>(data);
            session->hasDiskControl = true;
            return true;

        case RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION:
            *static_cast<unsigned *>(data) = 1;
            return true;

        case RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE:
            session->diskControlExt = *static_cast<retro_disk_control_ext_callback *>(data);
            session->hasDiskControlExt = true;
            return true;

        case RETRO_ENVIRONMENT_SET_VARIABLES: {
            const retro_variable *variables = static_cast<const retro_variable *>(data);
            for (size_t index = 0; variables && variables[index].key; ++index) {
                const char *definition = variables[index].value;
                if (!definition) continue;
                const char *separator = std::strstr(definition, "; ");
                const char *values = separator ? separator + 2 : definition;
                const char *pipe = std::strchr(values, '|');
                session->variables[variables[index].key] =
                    pipe ? std::string(values, static_cast<size_t>(pipe - values)) : std::string(values);
            }

            // POKE64 uses a generated system/vice/vicerc for user-imported
            // firmware. Keep drive behavior aligned with the temporary
            // compatibility mode used by FirmwareStore: virtual-device traps
            // enabled, True Drive Emulation disabled. This prevents the core's
            // defaults from overriding vicerc and leaving device 8 unavailable.
            session->variables["vice_read_vicerc"] = "enabled";
            session->variables["vice_drive_true_emulation"] = "disabled";
            session->variables["vice_virtual_device_traps"] = "enabled";
            session->variables["vice_drive_sound_emulation"] = "disabled";
            return true;
        }

        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            retro_variable *variable = static_cast<retro_variable *>(data);
            const char *key = variable->key ?: "";

            // VICE maps frontend port 0 to the selected C64 joyport and
            // frontend port 1 to the opposite joyport. POKE64 keeps that
            // mapping explicit so two controllers can be used simultaneously.
            if (std::strcmp(key, "vice_joyport") == 0) {
                variable->value = session->currentJoyport.load(std::memory_order_acquire) == 2
                    ? "2"
                    : "1";
                return true;
            }

            // Type 3 is the Commodore 1351 mouse. VICE applies it to the
            // selected joyport while leaving the opposite port as a joystick.
            if (std::strcmp(key, "vice_joyport_type") == 0) {
                variable->value = session->mousePort.load(std::memory_order_acquire) == 0
                    ? "1"
                    : "3";
                return true;
            }

            auto found = session->variables.find(key);
            variable->value = found == session->variables.end() ? nullptr : found->second.c_str();
            return true;
        }

        case RETRO_ENVIRONMENT_SET_VARIABLE: {
            const retro_variable *variable = static_cast<const retro_variable *>(data);
            if (!variable || !variable->key || !variable->value) return false;
            session->variables[variable->key] = variable->value;
            session->variablesUpdated.store(true, std::memory_order_release);
            return true;
        }

        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
            *static_cast<bool *>(data) = session->variablesUpdated.exchange(false, std::memory_order_acq_rel);
            return true;

        case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
            *static_cast<unsigned *>(data) = 0;
            return true;

        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
            static_cast<retro_log_callback *>(data)->log = frontendLog;
            return true;

        case RETRO_ENVIRONMENT_SET_MESSAGE: {
            const retro_message *message = static_cast<const retro_message *>(data);
            if (message && message->msg) {
                NSLog(@"VICE: %s", message->msg);
                session->recordCoreMessage(message->msg, true);
            }
            return true;
        }

        case RETRO_ENVIRONMENT_SHUTDOWN:
            session->recordCoreMessage(
                "VICE requested shutdown. Check the imported firmware files and generated vicerc.",
                false
            );
            session->shutdownRequested.store(true, std::memory_order_release);
            return true;

        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
            const retro_system_av_info *info = static_cast<const retro_system_av_info *>(data);
            if (info) {
                session->fps = info->timing.fps;
                session->sampleRate = info->timing.sample_rate;
            }
            return true;
        }

        case RETRO_ENVIRONMENT_SET_GEOMETRY:
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
        case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
        case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
        case RETRO_ENVIRONMENT_SET_MINIMUM_AUDIO_LATENCY:
            return true;

        case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
            return true;

        case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:
            *static_cast<int *>(data) = 3;
            return true;

        case RETRO_ENVIRONMENT_GET_FASTFORWARDING:
            *static_cast<bool *>(data) = false;
            return true;

        case RETRO_ENVIRONMENT_GET_TARGET_REFRESH_RATE:
            *static_cast<float *>(data) = 60.0f;
            return true;

        case RETRO_ENVIRONMENT_GET_MESSAGE_INTERFACE_VERSION:
            *static_cast<unsigned *>(data) = 0;
            return true;

        case RETRO_ENVIRONMENT_GET_LANGUAGE:
            *static_cast<unsigned *>(data) = RETRO_LANGUAGE_ENGLISH;
            return true;

        case RETRO_ENVIRONMENT_GET_USERNAME:
            *static_cast<const char **>(data) = nullptr;
            return true;

        case RETRO_ENVIRONMENT_GET_LED_INTERFACE:
        default:
            return false;
    }
}

static void videoCallback(const void *data, unsigned width, unsigned height, size_t pitch) {
    SessionImpl *session = gSession;
    if (!session || !data) return;
    C64MetalView *view = session->videoView;
    [view submitFrame:data
                width:width
               height:height
                pitch:pitch
          pixelFormat:session->pixelFormat];
}

static void audioSampleCallback(int16_t left, int16_t right) {
    const int16_t samples[] = {left, right};
    if (gSession) gSession->audioRing.push(samples, 1);
}

static size_t audioBatchCallback(const int16_t *data, size_t frames) {
    if (gSession) gSession->audioRing.push(data, frames);
    return frames;
}

static void inputPollCallback(void) {}

static int16_t clampedMouseDelta(std::atomic<int> &delta) {
    const int value = delta.exchange(0, std::memory_order_acq_rel);
    if (value > INT16_MAX) return INT16_MAX;
    if (value < INT16_MIN) return INT16_MIN;
    return static_cast<int16_t>(value);
}

static int16_t inputStateCallback(unsigned port, unsigned device, unsigned index, unsigned id) {
    (void)index;
    SessionImpl *session = gSession;
    if (!session || port > 1) return 0;

    switch (device & RETRO_DEVICE_MASK) {
        case RETRO_DEVICE_JOYPAD: {
            const uint32_t mask = session->joypadMasks[port].load(std::memory_order_acquire);
            if (id == RETRO_DEVICE_ID_JOYPAD_MASK) {
                return static_cast<int16_t>(mask & 0xffff);
            }
            if (id > 31) return 0;
            return (mask & (1u << id)) ? 1 : 0;
        }

        case RETRO_DEVICE_MOUSE: {
            const unsigned c64MousePort = session->mousePort.load(std::memory_order_acquire);
            if (c64MousePort == 0 || port != session->retroPortForC64Port(c64MousePort)) {
                return 0;
            }

            switch (id) {
                case RETRO_DEVICE_ID_MOUSE_X:
                    return clampedMouseDelta(session->mouseDeltaX);
                case RETRO_DEVICE_ID_MOUSE_Y:
                    return clampedMouseDelta(session->mouseDeltaY);
                case RETRO_DEVICE_ID_MOUSE_LEFT:
                    return (session->mouseButtons.load(std::memory_order_acquire) & 0x1u) ? 1 : 0;
                case RETRO_DEVICE_ID_MOUSE_RIGHT:
                    return (session->mouseButtons.load(std::memory_order_acquire) & 0x2u) ? 1 : 0;
                case RETRO_DEVICE_ID_MOUSE_MIDDLE:
                    return (session->mouseButtons.load(std::memory_order_acquire) & 0x4u) ? 1 : 0;
                default:
                    return 0;
            }
        }

        default:
            return 0;
    }
}

bool SessionImpl::start(const char *path, std::string &error) {
    stop();
    if (coreHandle) {
        api.retro_unload_game();
        api.retro_deinit();
        unloadCore();
    }

    if (!loadCore(error)) return false;
    gSession = this;
    clearCoreDiagnostics();
    shutdownRequested.store(false, std::memory_order_release);
    {
        std::lock_guard<std::mutex> lock(startupMutex);
        firstRunCompleted = false;
    }

    api.retro_set_environment(environmentCallback);
    api.retro_set_video_refresh(videoCallback);
    api.retro_set_audio_sample(audioSampleCallback);
    api.retro_set_audio_sample_batch(audioBatchCallback);
    api.retro_set_input_poll(inputPollCallback);
    api.retro_set_input_state(inputStateCallback);

    retro_system_info systemInfo{};
    api.retro_get_system_info(&systemInfo);
    frontendLog(RETRO_LOG_INFO, "Loading %s %s\n",
                systemInfo.library_name ?: "unknown",
                systemInfo.library_version ?: "");

    api.retro_init();
    if (shutdownRequested.load(std::memory_order_acquire)) {
        error = startupFailureMessage("VICE failed during core initialization");
        api.retro_deinit();
        unloadCore();
        gSession = nullptr;
        return false;
    }
    api.retro_set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
    api.retro_set_controller_port_device(1, RETRO_DEVICE_JOYPAD);

    retro_game_info game{};
    const retro_game_info *gamePointer = nullptr;
    if (path && *path) {
        contentPath = path;
        game.path = contentPath.c_str();
        gamePointer = &game;
    } else {
        contentPath.clear();
    }

    const bool gameLoaded = api.retro_load_game(gamePointer);
    if (!gameLoaded || shutdownRequested.load(std::memory_order_acquire)) {
        if (gameLoaded) api.retro_unload_game();
        error = shutdownRequested.load(std::memory_order_acquire)
            ? startupFailureMessage("VICE requested shutdown while loading firmware")
            : startupFailureMessage(path
                ? "The core rejected the selected content"
                : "The core does not support starting without content");
        api.retro_deinit();
        unloadCore();
        gSession = nullptr;
        return false;
    }

    retro_system_av_info avInfo{};
    api.retro_get_system_av_info(&avInfo);
    fps = avInfo.timing.fps > 1.0 ? avInfo.timing.fps : 50.0;
    sampleRate = avInfo.timing.sample_rate > 1000.0 ? avInfo.timing.sample_rate : 48000.0;
    startAudio();

    running.store(true, std::memory_order_release);
    coreThread = std::thread([this] {
        using clock = std::chrono::steady_clock;
        const std::chrono::duration<double> frameDuration(1.0 / fps);
        auto nextFrame = clock::now();

        bool firstIteration = true;
        while (running.load(std::memory_order_acquire) &&
               !shutdownRequested.load(std::memory_order_acquire)) {
            drainMediaCommands();
            const int resetMode = resetModeRequested.exchange(-1, std::memory_order_acq_rel);
            if (resetMode >= 0) {
                if (api.emu_reset) {
                    api.emu_reset(resetMode);
                } else {
                    // Compatibility fallback for a core build that does not
                    // export the VICE reset helper.
                    api.retro_reset();
                }
            }
            drainKeyEvents();
            api.retro_run();

            if (firstIteration) {
                {
                    std::lock_guard<std::mutex> lock(startupMutex);
                    firstRunCompleted = true;
                }
                startupCondition.notify_all();
                firstIteration = false;
            }

            nextFrame += std::chrono::duration_cast<clock::duration>(frameDuration);
            std::this_thread::sleep_until(nextFrame);

            const auto now = clock::now();
            if (now - nextFrame > std::chrono::milliseconds(250)) {
                nextFrame = now;
            }
        }

        if (firstIteration) {
            {
                std::lock_guard<std::mutex> lock(startupMutex);
                firstRunCompleted = true;
            }
            startupCondition.notify_all();
        }
        running.store(false, std::memory_order_release);
        failPendingMediaCommands("The core stopped before completing the media operation");
    });

    {
        std::unique_lock<std::mutex> lock(startupMutex);
        startupCondition.wait_for(lock, std::chrono::seconds(2), [this] {
            return firstRunCompleted;
        });
    }

    if (shutdownRequested.load(std::memory_order_acquire)) {
        stop();
        error = startupFailureMessage("VICE requested shutdown during the first emulated frame");
        api.retro_unload_game();
        api.retro_deinit();
        unloadCore();
        gSession = nullptr;
        return false;
    }

    return true;
}

} // namespace

@interface LibretroSession () {
    std::unique_ptr<SessionImpl> _impl;
}
@property (nonatomic, copy, readwrite, nullable) NSString *lastErrorMessage;
@end

@implementation LibretroSession

- (instancetype)init {
    self = [super init];
    if (self) {
        _impl = std::make_unique<SessionImpl>();
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (C64MetalView *)videoView {
    return _impl->videoView;
}

- (void)setVideoView:(C64MetalView *)videoView {
    _impl->videoView = videoView;
}

- (BOOL)startWithoutContent {
    self.lastErrorMessage = nil;
    std::string message;
    const bool success = _impl->start(nullptr, message);
    if (!success) {
        self.lastErrorMessage = [NSString stringWithUTF8String:message.c_str()];
    }
    return success;
}

- (BOOL)loadContentAtURL:(NSURL *)url {
    self.lastErrorMessage = nil;
    if (!url.isFileURL) {
        self.lastErrorMessage = @"A local file is required";
        return NO;
    }

    std::string message;
    const bool success = _impl->start(url.fileSystemRepresentation, message);
    if (!success) {
        self.lastErrorMessage = [NSString stringWithUTF8String:message.c_str()];
    }
    return success;
}

- (BOOL)performMediaCommand:(MediaCommandType)type
                        URL:(NSURL * _Nullable)url
                  driveUnit:(NSInteger)unit {
    self.lastErrorMessage = nil;
    if (url && !url.isFileURL) {
        self.lastErrorMessage = @"A local file is required";
        return NO;
    }
    if (unit != 0 && (unit < 8 || unit > 11)) {
        self.lastErrorMessage = @"Drive unit must be between 8 and 11";
        return NO;
    }

    std::string message;
    const bool success = _impl->performMediaCommand(
        type,
        url ? url.fileSystemRepresentation : nullptr,
        static_cast<int>(unit),
        message
    );
    if (!success) {
        self.lastErrorMessage = [NSString stringWithUTF8String:message.c_str()];
    }
    return success;
}

- (BOOL)attachDiskAtURL:(NSURL *)url driveUnit:(NSInteger)unit {
    return [self performMediaCommand:MediaCommandType::AttachDisk URL:url driveUnit:unit];
}

- (BOOL)autostartDiskAtURL:(NSURL *)url driveUnit:(NSInteger)unit {
    return [self performMediaCommand:MediaCommandType::AutostartDisk URL:url driveUnit:unit];
}

- (BOOL)attachTapeAtURL:(NSURL *)url {
    return [self performMediaCommand:MediaCommandType::AttachTape URL:url driveUnit:0];
}

- (BOOL)autostartTapeAtURL:(NSURL *)url {
    return [self performMediaCommand:MediaCommandType::AutostartTape URL:url driveUnit:0];
}

- (BOOL)runProgramAtURL:(NSURL *)url {
    return [self performMediaCommand:MediaCommandType::RunProgram URL:url driveUnit:0];
}

- (BOOL)attachCartridgeAtURL:(NSURL *)url {
    return [self performMediaCommand:MediaCommandType::AttachCartridge URL:url driveUnit:0];
}

- (BOOL)ejectDiskFromDriveUnit:(NSInteger)unit {
    return [self performMediaCommand:MediaCommandType::EjectDisk URL:nil driveUnit:unit];
}

- (BOOL)ejectTape {
    return [self performMediaCommand:MediaCommandType::EjectTape URL:nil driveUnit:0];
}

- (BOOL)ejectCartridge {
    return [self performMediaCommand:MediaCommandType::EjectCartridge URL:nil driveUnit:0];
}

- (BOOL)ejectAllMediaAndReset {
    return [self performMediaCommand:MediaCommandType::EjectAllAndReset URL:nil driveUnit:0];
}

- (void)stop {
    _impl->stop();
    if (_impl->coreHandle) {
        _impl->api.retro_unload_game();
        _impl->api.retro_deinit();
        _impl->unloadCore();
    }
    if (gSession == _impl.get()) gSession = nullptr;
}

- (void)softReset {
    _impl->resetModeRequested.store(1, std::memory_order_release);
}

- (void)hardReset {
    _impl->resetModeRequested.store(2, std::memory_order_release);
}

- (void)setMousePort:(NSInteger)port {
    if (port < 0 || port > 2) return;

    const unsigned selectedPort = static_cast<unsigned>(port);
    _impl->mousePort.store(selectedPort, std::memory_order_release);
    _impl->currentJoyport.store(selectedPort == 0 ? 1u : selectedPort, std::memory_order_release);
    _impl->clearInputState();
    _impl->variablesUpdated.store(true, std::memory_order_release);
}

- (void)setJoypadMask:(uint32_t)mask forC64Port:(NSInteger)port {
    if (port < 1 || port > 2) return;
    const unsigned retroPort = _impl->retroPortForC64Port(static_cast<unsigned>(port));
    _impl->joypadMasks[retroPort].store(mask, std::memory_order_release);
}

- (void)addMouseDeltaX:(NSInteger)deltaX deltaY:(NSInteger)deltaY {
    if (_impl->mousePort.load(std::memory_order_acquire) == 0) return;

    const NSInteger clampedX = std::clamp(
        deltaX,
        static_cast<NSInteger>(INT_MIN),
        static_cast<NSInteger>(INT_MAX)
    );
    const NSInteger clampedY = std::clamp(
        deltaY,
        static_cast<NSInteger>(INT_MIN),
        static_cast<NSInteger>(INT_MAX)
    );
    _impl->mouseDeltaX.fetch_add(static_cast<int>(clampedX), std::memory_order_acq_rel);
    _impl->mouseDeltaY.fetch_add(static_cast<int>(clampedY), std::memory_order_acq_rel);
}

- (void)setMouseButton:(NSInteger)button pressed:(BOOL)pressed {
    if (button < 0 || button > 2) return;
    const uint32_t bit = 1u << static_cast<unsigned>(button);
    if (pressed) {
        _impl->mouseButtons.fetch_or(bit, std::memory_order_acq_rel);
    } else {
        _impl->mouseButtons.fetch_and(~bit, std::memory_order_acq_rel);
    }
}

- (void)setKey:(C64KeyCode)key pressed:(BOOL)pressed {
    [self setRawKeyCode:static_cast<NSUInteger>(key) pressed:pressed];
}

- (void)setRawKeyCode:(NSUInteger)keyCode pressed:(BOOL)pressed {
    if (keyCode > UINT_MAX) return;
    std::lock_guard<std::mutex> lock(_impl->keyMutex);
    _impl->keyEvents.push_back({static_cast<bool>(pressed), static_cast<unsigned>(keyCode)});
}

@end
