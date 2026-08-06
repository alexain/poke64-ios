#import "LibretroSession.h"
#import "C64MetalView.h"
#import "LibretroMinimal.h"

#import <AVFoundation/AVFoundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
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
    void (*datasette_control)(int, int) = nullptr;
    void (*printer_formfeed)(unsigned int) = nullptr;
    int *tape_enabled = nullptr;
    int *tape_control = nullptr;
    int *tape_counter = nullptr;
    int *tape_motor = nullptr;
    int (*cartridge_attach_image)(int, const char *) = nullptr;
    void (*cartridge_detach_image)(int) = nullptr;
    int (*autostart_disk)(int, int, const char *, const char *, unsigned int, unsigned int) = nullptr;
    int (*autostart_tape)(const char *, const char *, unsigned int, unsigned int, unsigned int) = nullptr;
    int (*autostart_prg)(const char *, unsigned int) = nullptr;
    int (*resources_set_int)(const char *, int) = nullptr;
    int (*resources_get_int)(const char *, int *) = nullptr;
    int (*resources_set_string)(const char *, const char *) = nullptr;
    int (*iecrom_load_1541)(void) = nullptr;
    int (*iecrom_load_1541ii)(void) = nullptr;
    int (*iecrom_load_1571)(void) = nullptr;
    int (*iecrom_load_1581)(void) = nullptr;
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
    DatasetteControl,
    PrinterFormFeed,
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

static bool storedDriveEnabled(unsigned int unit);
static bool storedTrueDriveEmulationEnabled();
static unsigned int storedPrinterDevice();
static int storedDriveTypeResourceValue(unsigned int unit);
static int storedDriveSoundVolumeResourceValue();
static const char *storedDriveROMResourceName(unsigned int unit);
static std::string storedDriveROMPath(unsigned int unit);

struct SessionImpl {
    void *coreHandle = nullptr;
    CoreAPI api;
    __weak LibretroSession *owner = nil;
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
    std::atomic<bool> driveActivityLED{false};
    std::atomic<bool> datasetteActivityLED{false};
    bool datasetteStateInitialized = false;
    bool lastDatasetteTelemetryAvailable = false;
    int lastDatasetteEnabled = 0;
    int lastDatasetteControl = 0;
    int lastDatasetteCounter = 0;
    int lastDatasetteMotor = 0;

    SessionImpl() {
        clearInputState();
    }

    unsigned retroPortForC64Port(unsigned c64Port) const {
        const unsigned current = currentJoyport.load(std::memory_order_acquire);
        return c64Port == current ? 0u : 1u;
    }

    void applyControllerPortDevices() {
        if (!coreHandle || !api.retro_set_controller_port_device) return;

        // VICE-libretro maps frontend port 0 to the C64 joyport selected by
        // vice_joyport. When a 1351 is enabled, that selected frontend port
        // must be declared as a libretro mouse rather than a RetroPad.
        const bool mouseEnabled = mousePort.load(std::memory_order_acquire) != 0;
        api.retro_set_controller_port_device(
            0,
            mouseEnabled ? RETRO_DEVICE_MOUSE : RETRO_DEVICE_JOYPAD
        );
        api.retro_set_controller_port_device(1, RETRO_DEVICE_JOYPAD);

        std::fprintf(
            stderr,
            "[POKE64/INFO] Input devices: port0=%s port1=joypad C64MousePort=%u\n",
            mouseEnabled ? "mouse" : "joypad",
            mousePort.load(std::memory_order_acquire)
        );
    }

    void updateVideoGeometry(const retro_game_geometry &geometry) {
        double aspectRatio = geometry.aspect_ratio;
        if (!(aspectRatio > 0.0) && geometry.base_height > 0) {
            aspectRatio = static_cast<double>(geometry.base_width)
                / static_cast<double>(geometry.base_height);
        }
        if (!std::isfinite(aspectRatio) || aspectRatio < 0.5 || aspectRatio > 3.0) {
            return;
        }

        LibretroSession *session = owner;
        void (^callback)(double) = session.videoGeometryDidChange;
        if (!callback) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            callback(aspectRatio);
        });
    }

    void updateDriveLED(int state) {
        const bool active = state != 0;
        const bool previous = driveActivityLED.exchange(
            active,
            std::memory_order_acq_rel
        );
        if (previous == active) return;

        LibretroSession *session = owner;
        void (^callback)(BOOL) = session.driveLEDStateDidChange;
        if (!callback) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            callback(active);
        });
    }

    void clearDriveLED() {
        updateDriveLED(0);
    }

    void updateDatasetteLED(int state) {
        const bool active = state != 0;
        const bool previous = datasetteActivityLED.exchange(
            active,
            std::memory_order_acq_rel
        );
        if (previous == active) return;

        LibretroSession *session = owner;
        void (^callback)(BOOL) = session.datasetteLEDStateDidChange;
        if (!callback) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            callback(active);
        });
    }

    void updateDatasetteState(bool force = false) {
        const bool telemetryAvailable = api.tape_enabled
            && api.tape_control
            && api.tape_counter
            && api.tape_motor;
        const int enabled = telemetryAvailable ? *api.tape_enabled : 0;
        const int control = telemetryAvailable ? *api.tape_control : 0;
        const int counter = telemetryAvailable
            ? std::clamp(*api.tape_counter, 0, 999)
            : 0;
        const int motor = telemetryAvailable ? *api.tape_motor : 0;

        if (!force
            && datasetteStateInitialized
            && telemetryAvailable == lastDatasetteTelemetryAvailable
            && enabled == lastDatasetteEnabled
            && control == lastDatasetteControl
            && counter == lastDatasetteCounter
            && motor == lastDatasetteMotor) {
            return;
        }

        datasetteStateInitialized = true;
        lastDatasetteTelemetryAvailable = telemetryAvailable;
        lastDatasetteEnabled = enabled;
        lastDatasetteControl = control;
        lastDatasetteCounter = counter;
        lastDatasetteMotor = motor;

        LibretroSession *session = owner;
        void (^callback)(BOOL, BOOL, NSInteger, NSInteger, BOOL) =
            session.datasetteStateDidChange;
        if (!callback) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            callback(
                telemetryAvailable,
                enabled != 0,
                static_cast<NSInteger>(control),
                static_cast<NSInteger>(counter),
                motor != 0
            );
        });
    }

    void clearDatasetteState() {
        updateDatasetteLED(0);
        datasetteStateInitialized = false;
        lastDatasetteTelemetryAvailable = false;
        lastDatasetteEnabled = 0;
        lastDatasetteControl = 0;
        lastDatasetteCounter = 0;
        lastDatasetteMotor = 0;

        LibretroSession *session = owner;
        void (^callback)(BOOL, BOOL, NSInteger, NSInteger, BOOL) =
            session.datasetteStateDidChange;
        if (!callback) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            callback(NO, NO, 0, 0, NO);
        });
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
        api.datasette_control = reinterpret_cast<void (*)(int, int)>(
            dlsym(coreHandle, "datasette_control")
        );
        api.printer_formfeed = reinterpret_cast<void (*)(unsigned int)>(
            dlsym(coreHandle, "printer_formfeed")
        );
        api.tape_enabled = reinterpret_cast<int *>(dlsym(coreHandle, "tape_enabled"));
        api.tape_control = reinterpret_cast<int *>(dlsym(coreHandle, "tape_control"));
        api.tape_counter = reinterpret_cast<int *>(dlsym(coreHandle, "tape_counter"));
        api.tape_motor = reinterpret_cast<int *>(dlsym(coreHandle, "tape_motor"));
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
        api.resources_set_int = reinterpret_cast<int (*)(const char *, int)>(
            dlsym(coreHandle, "resources_set_int")
        );
        api.resources_get_int = reinterpret_cast<int (*)(const char *, int *)>(
            dlsym(coreHandle, "resources_get_int")
        );
        api.resources_set_string = reinterpret_cast<int (*)(const char *, const char *)>(
            dlsym(coreHandle, "resources_set_string")
        );
        api.iecrom_load_1541 = reinterpret_cast<int (*)(void)>(
            dlsym(coreHandle, "iecrom_load_1541")
        );
        api.iecrom_load_1541ii = reinterpret_cast<int (*)(void)>(
            dlsym(coreHandle, "iecrom_load_1541ii")
        );
        api.iecrom_load_1571 = reinterpret_cast<int (*)(void)>(
            dlsym(coreHandle, "iecrom_load_1571")
        );
        api.iecrom_load_1581 = reinterpret_cast<int (*)(void)>(
            dlsym(coreHandle, "iecrom_load_1581")
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

    bool setRuntimeIntegerResource(
        const char *name,
        int value,
        std::string &error
    ) {
        if (!api.resources_set_int) {
            error = "The VICE core does not expose runtime resource updates";
            return false;
        }

        int currentValue = 0;
        if (api.resources_get_int &&
            api.resources_get_int(name, &currentValue) == 0 &&
            currentValue == value) {
            return true;
        }

        if (api.resources_set_int(name, value) < 0) {
            error = std::string("VICE could not set the runtime resource ") + name;
            return false;
        }
        return true;
    }

    bool loadSelectedDriveROM(unsigned int unit, std::string &error) {
        if (!api.resources_set_string) {
            error = "The VICE core does not expose runtime drive-ROM configuration";
            return false;
        }

        const char *resourceName = storedDriveROMResourceName(unit);
        const std::string romPath = storedDriveROMPath(unit);
        if (!resourceName || romPath.empty()) {
            error = "The selected drive ROM is not available";
            return false;
        }

        if (api.resources_set_string(resourceName, romPath.c_str()) < 0) {
            error = std::string("VICE could not select the drive ROM at ") + romPath;
            return false;
        }

        int result = -1;
        switch (storedDriveTypeResourceValue(unit)) {
            case 1541:
                if (api.iecrom_load_1541) result = api.iecrom_load_1541();
                break;
            case 1542:
                if (api.iecrom_load_1541ii) result = api.iecrom_load_1541ii();
                break;
            case 1571:
                if (api.iecrom_load_1571) result = api.iecrom_load_1571();
                break;
            case 1581:
                if (api.iecrom_load_1581) result = api.iecrom_load_1581();
                break;
            default:
                break;
        }

        if (result < 0) {
            error = std::string("VICE could not load the selected drive ROM at ") + romPath;
            return false;
        }
        return true;
    }

    bool applyRuntimePrinterConfiguration(std::string &error) {
        const unsigned int selectedDevice = storedPrinterDevice();
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        const bool enabled = [defaults objectForKey:@"poke64.printer.enabled"] != nil
            && [defaults boolForKey:@"poke64.printer.enabled"];

        for (unsigned int device = 4; device <= 5; ++device) {
            const bool selected = enabled && device == selectedDevice;
            const std::string printerResource = "Printer" + std::to_string(device);
            const std::string trapResource = "TrapDevice" + std::to_string(device);
            if (!setRuntimeIntegerResource(
                    printerResource.c_str(),
                    selected ? 1 : 0,
                    error
                ) || !setRuntimeIntegerResource(
                    trapResource.c_str(),
                    selected ? 1 : 0,
                    error
                )) {
                return false;
            }
        }
        return true;
    }

    bool applyRuntimeDriveConfiguration(unsigned int unit, std::string &error) {
        if (unit < 8 || unit > 9) {
            return true;
        }
        if (!storedDriveEnabled(unit)) {
            error = std::string("Drive ") + std::to_string(unit) + " is disabled";
            return false;
        }
        if (!storedTrueDriveEmulationEnabled()) {
            return true;
        }

        if (!api.resources_get_int) {
            error = "The VICE core does not expose runtime drive-state inspection";
            return false;
        }

        const int expectedDriveType = storedDriveTypeResourceValue(unit);
        const std::string prefix = std::string("Drive") + std::to_string(unit);
        const std::string typeResource = prefix + "Type";
        int currentDriveType = 0;
        if (api.resources_get_int(typeResource.c_str(), &currentDriveType) < 0) {
            error = std::string("VICE could not read the Drive ")
                + std::to_string(unit) + " model";
            return false;
        }

        if (currentDriveType != expectedDriveType) {
            if (!loadSelectedDriveROM(unit, error)) {
                return false;
            }
            if (!setRuntimeIntegerResource(
                    typeResource.c_str(),
                    expectedDriveType,
                    error
                )) {
                return false;
            }
        }

        const std::string trueDriveResource = prefix + "TrueEmulation";
        const std::string trapResource = std::string("TrapDevice") + std::to_string(unit);
        const std::string filesystemResource = std::string("FileSystemDevice") + std::to_string(unit);
        const std::pair<std::string, int> resources[] = {
            {trueDriveResource, 1},
            {trapResource, 0},
            {filesystemResource, 0}
        };

        for (const auto &resource : resources) {
            if (!setRuntimeIntegerResource(
                    resource.first.c_str(),
                    resource.second,
                    error
                )) {
                return false;
            }
        }
        return true;
    }

    bool applyRuntimeDriveSoundConfiguration(std::string &error) {
        const int volume = storedDriveSoundVolumeResourceValue();
        const bool enabled = storedTrueDriveEmulationEnabled()
            && ((storedDriveEnabled(8) && storedDriveTypeResourceValue(8) != 1581)
                || (storedDriveEnabled(9) && storedDriveTypeResourceValue(9) != 1581))
            && volume > 0;

        if (!setRuntimeIntegerResource(
                "DriveSoundEmulation",
                enabled ? 1 : 0,
                error
            )) {
            return false;
        }
        if (!setRuntimeIntegerResource(
                "DriveSoundEmulationVolume",
                enabled ? volume : 0,
                error
            )) {
            return false;
        }

        int actualEnabled = 0;
        int actualVolume = 0;
        if (api.resources_get_int) {
            api.resources_get_int("DriveSoundEmulation", &actualEnabled);
            api.resources_get_int("DriveSoundEmulationVolume", &actualVolume);
        }
        std::fprintf(
            stderr,
            "[POKE64/INFO] Drive sound: requested=%d%% enabled=%d volume=%d\n",
            volume / 20,
            actualEnabled,
            actualVolume
        );
        return true;
    }

    bool finalizeDiskAttachment(unsigned int unit, std::string &error) {
        if (!storedTrueDriveEmulationEnabled()) {
            return true;
        }

        const std::string typeResource = std::string("Drive")
            + std::to_string(unit) + "Type";
        int driveType = 0;
        if (!api.resources_get_int ||
            api.resources_get_int(typeResource.c_str(), &driveType) < 0) {
            error = std::string("VICE could not verify the Drive ")
                + std::to_string(unit) + " model after insertion";
            return false;
        }

        if (driveType != storedDriveTypeResourceValue(unit)) {
            error = std::string("VICE inserted the disk but the selected Drive ")
                + std::to_string(unit) + " hardware is not active";
            return false;
        }

        std::string soundError;
        if (!applyRuntimeDriveSoundConfiguration(soundError)) {
            std::fprintf(
                stderr,
                "[POKE64/WARN] %s\n",
                soundError.c_str()
            );
        }
        return true;
    }

    bool executeMediaCommand(const std::shared_ptr<MediaCommand> &command, std::string &error) {
        // VICE uses a 1-based tape image unit for attach/detach, but a
        // 0-based tape-port index for autostart and datasette transport.
        constexpr unsigned int kTapeUnit = 1;
        constexpr unsigned int kTapePort = 0;
        constexpr unsigned int kAutostartModeRun = 0;
        constexpr int kCartridgeCRT = 0;

        switch (command->type) {
            case MediaCommandType::AttachDisk:
                if (!api.file_system_attach_disk) {
                    error = "The VICE core does not expose runtime disk attachment";
                    return false;
                }
                if (!applyRuntimeDriveConfiguration(
                        static_cast<unsigned int>(command->unit),
                        error
                    )) {
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
                return finalizeDiskAttachment(
                    static_cast<unsigned int>(command->unit),
                    error
                );

            case MediaCommandType::AutostartDisk:
                if (!api.autostart_disk) {
                    error = "The VICE core does not expose disk autostart";
                    return false;
                }
                if (!applyRuntimeDriveConfiguration(
                        static_cast<unsigned int>(command->unit),
                        error
                    )) {
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
                return finalizeDiskAttachment(
                    static_cast<unsigned int>(command->unit),
                    error
                );

            case MediaCommandType::AttachTape:
                if (!api.tape_image_attach) {
                    error = "The VICE core does not expose runtime tape attachment";
                    return false;
                }
                if (api.tape_image_attach(kTapeUnit, command->path.c_str()) != 0) {
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
                // In fast virtual-drive mode VICE restores its host-filesystem
                // backend after detaching an image. Remove those serial hooks so
                // an empty unit reports DEVICE NOT PRESENT. With True Drive
                // Emulation the hardware drive remains present without a disk.
                if (!storedTrueDriveEmulationEnabled() && api.machine_bus_device_detach) {
                    api.machine_bus_device_detach(
                        static_cast<unsigned int>(command->unit)
                    );
                }
                clearDriveLED();
                return true;

            case MediaCommandType::EjectTape:
                if (!api.tape_image_detach) {
                    error = "The VICE core does not expose runtime tape ejection";
                    return false;
                }
                if (api.tape_image_detach(kTapeUnit) != 0) {
                    error = "VICE could not eject the current tape";
                    return false;
                }
                updateDatasetteState(true);
                return true;

            case MediaCommandType::DatasetteControl:
                if (!api.datasette_control) {
                    error = "The VICE core does not expose datasette transport control";
                    return false;
                }
                if (command->unit < C64DatasetteCommandStop
                    || command->unit > C64DatasetteCommandResetCounter
                    || command->unit == 4) {
                    error = "Unsupported datasette command";
                    return false;
                }
                api.datasette_control(static_cast<int>(kTapePort), command->unit);
                updateDatasetteState(true);
                return true;

            case MediaCommandType::PrinterFormFeed: {
                if (command->unit < 4 || command->unit > 5) {
                    error = "Printer device must be 4 or 5";
                    return false;
                }
                if (api.printer_formfeed) {
                    api.printer_formfeed(
                        static_cast<unsigned int>(command->unit - 4)
                    );
                    return true;
                }

                // Compatibility fallback for older core builds: cycling the
                // selected printer resource closes and reopens the RAW backend,
                // which flushes its stdio buffer without resetting the C64.
                const std::string resource =
                    "Printer" + std::to_string(command->unit);
                if (!setRuntimeIntegerResource(resource.c_str(), 0, error)) {
                    return false;
                }
                return setRuntimeIntegerResource(resource.c_str(), 1, error);
            }

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
                if (!storedTrueDriveEmulationEnabled() && api.machine_bus_device_detach) {
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
        clearDriveLED();
        clearDatasetteState();
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

static NSString *validatedDefaultString(
    NSString *key,
    NSArray<NSString *> *allowedValues,
    NSString *fallback
) {
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:key];
    return [allowedValues containsObject:stored] ? stored : fallback;
}

static NSInteger validatedDefaultInteger(
    NSString *key,
    NSInteger fallback,
    NSInteger minimum,
    NSInteger maximum
) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults objectForKey:key]) return fallback;
    return std::clamp([defaults integerForKey:key], minimum, maximum);
}

static void assignCoreOption(
    SessionImpl *session,
    const char *coreKey,
    NSString *value
) {
    auto found = session->variables.find(coreKey);
    if (found == session->variables.end() || !value) return;
    found->second = value.UTF8String;
}

static void applyStoredVideoOptions(SessionImpl *session) {
    assignCoreOption(
        session,
        "vice_aspect_ratio",
        validatedDefaultString(
            @"poke64.video.aspectRatio",
            @[@"auto", @"pal", @"ntsc", @"raw"],
            @"auto"
        )
    );
    assignCoreOption(
        session,
        "vice_crop",
        validatedDefaultString(
            @"poke64.video.crop",
            @[@"disabled", @"small", @"medium", @"maximum", @"auto"],
            @"disabled"
        )
    );
    assignCoreOption(
        session,
        "vice_crop_delay",
        [NSUserDefaults.standardUserDefaults objectForKey:@"poke64.video.cropDelay"] == nil
            || [NSUserDefaults.standardUserDefaults boolForKey:@"poke64.video.cropDelay"]
            ? @"enabled"
            : @"disabled"
    );
    assignCoreOption(
        session,
        "vice_external_palette",
        validatedDefaultString(
            @"poke64.video.palette",
            @[
                @"default", @"vice", @"colodore", @"community-colors",
                @"pepto-pal", @"pepto-ntsc", @"the64", @"rgb"
            ],
            @"default"
        )
    );
    assignCoreOption(
        session,
        "vice_vicii_filter",
        validatedDefaultString(
            @"poke64.video.filter",
            @[
                @"disabled", @"enabled_noblur", @"enabled_lowblur",
                @"enabled_medblur", @"enabled"
            ],
            @"disabled"
        )
    );

    const struct {
        NSString *defaultsKey;
        const char *coreKey;
        NSInteger fallback;
        NSInteger minimum;
        NSInteger maximum;
    } integerOptions[] = {
        {@"poke64.video.brightness", "vice_vicii_color_brightness", 1000, 20, 2000},
        {@"poke64.video.contrast", "vice_vicii_color_contrast", 1000, 20, 2000},
        {@"poke64.video.saturation", "vice_vicii_color_saturation", 1000, 20, 2000},
        {@"poke64.video.gamma", "vice_vicii_color_gamma", 2800, 1000, 4000},
        {@"poke64.video.tint", "vice_vicii_color_tint", 1000, 20, 2000}
    };

    for (const auto &option : integerOptions) {
        const NSInteger value = validatedDefaultInteger(
            option.defaultsKey,
            option.fallback,
            option.minimum,
            option.maximum
        );
        assignCoreOption(
            session,
            option.coreKey,
            [NSString stringWithFormat:@"%ld", static_cast<long>(value)]
        );
    }
}

static bool storedDriveEnabled(unsigned int unit) {
    if (unit == 8) return true;
    if (unit != 9) return false;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [defaults objectForKey:@"poke64.drive9.enabled"] != nil
        ? [defaults boolForKey:@"poke64.drive9.enabled"]
        : false;
}

static bool storedTrueDriveEmulationEnabled() {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [defaults objectForKey:@"poke64.drive.trueEmulation"] != nil
        ? [defaults boolForKey:@"poke64.drive.trueEmulation"]
        : false;
}

static unsigned int storedPrinterDevice() {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    const NSInteger stored = [defaults objectForKey:@"poke64.printer.device"] != nil
        ? [defaults integerForKey:@"poke64.printer.device"]
        : 4;
    return stored == 5 ? 5u : 4u;
}

static NSString *storedDriveModel(unsigned int unit) {
    NSString *key = unit == 9 ? @"poke64.drive9.model" : @"poke64.drive.model";
    return validatedDefaultString(
        key,
        @[@"1541", @"1541-II", @"1571", @"1581"],
        @"1541-II"
    );
}

static int storedDriveTypeResourceValue(unsigned int unit) {
    NSString *model = storedDriveModel(unit);
    if ([model isEqualToString:@"1541"]) return 1541;
    if ([model isEqualToString:@"1571"]) return 1571;
    if ([model isEqualToString:@"1581"]) return 1581;
    return 1542;
}

static const char *storedDriveROMResourceName(unsigned int unit) {
    switch (storedDriveTypeResourceValue(unit)) {
        case 1541: return "DosName1541";
        case 1571: return "DosName1571";
        case 1581: return "DosName1581";
        default: return "DosName1541ii";
    }
}

static int storedDriveSoundVolumeResourceValue() {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSInteger level = [defaults objectForKey:@"poke64.drive.soundLevel"] == nil
        ? 20
        : [defaults integerForKey:@"poke64.drive.soundLevel"];
    level = std::clamp(
        static_cast<NSInteger>((level + 2) / 5 * 5),
        static_cast<NSInteger>(0),
        static_cast<NSInteger>(100)
    );
    return static_cast<int>(level * 20);
}

static NSString *storedDriveROMFilename(unsigned int unit) {
    switch (storedDriveTypeResourceValue(unit)) {
        case 1541: return @"poke64-dos1541.bin";
        case 1571: return @"poke64-dos1571.bin";
        case 1581: return @"poke64-dos1581.bin";
        default: return @"poke64-dos1541ii.bin";
    }
}

static std::string storedDriveROMPath(unsigned int unit) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *base = [manager URLForDirectory:NSApplicationSupportDirectory
                                  inDomain:NSUserDomainMask
                         appropriateForURL:nil
                                    create:YES
                                     error:nil];
    NSURL *url = [[[[base URLByAppendingPathComponent:@"System" isDirectory:YES]
        URLByAppendingPathComponent:@"vice" isDirectory:YES]
        URLByAppendingPathComponent:@"POKE64" isDirectory:YES]
        URLByAppendingPathComponent:@"Firmware" isDirectory:YES];
    url = [url URLByAppendingPathComponent:storedDriveROMFilename(unit) isDirectory:NO];

    NSDictionary<NSURLResourceKey, id> *values = [url resourceValuesForKeys:@[
        NSURLIsRegularFileKey,
        NSURLFileSizeKey
    ] error:nil];
    if (![values[NSURLIsRegularFileKey] boolValue]) {
        return {};
    }

    const long long expectedSize =
        storedDriveTypeResourceValue(unit) == 1571 || storedDriveTypeResourceValue(unit) == 1581
            ? 32768
            : 16384;
    if ([values[NSURLFileSizeKey] longLongValue] != expectedSize) {
        return {};
    }
    return std::string(url.fileSystemRepresentation);
}

static void applyStoredREUOptions(SessionImpl *session) {
    assignCoreOption(
        session,
        "vice_ram_expansion_unit",
        validatedDefaultString(
            @"poke64.system.reuSize",
            @[
                @"none", @"128kB", @"256kB", @"512kB", @"1024kB",
                @"2048kB", @"4096kB", @"8192kB", @"16384kB"
            ],
            @"none"
        )
    );
}

static void applyStoredPrinterOptions(SessionImpl *session) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    const bool enabled = [defaults objectForKey:@"poke64.printer.enabled"] != nil
        && [defaults boolForKey:@"poke64.printer.enabled"];

    // The libretro core keeps its printer backend disabled by default and
    // treats Virtual Device Traps as the device-4 printer trap. Both options
    // must therefore follow POKE64's printer switch; the generated vicerc then
    // selects the RAW driver, output file and active IEC device.
    assignCoreOption(
        session,
        "vice_printer",
        enabled ? @"enabled" : @"disabled"
    );
    assignCoreOption(
        session,
        "vice_virtual_device_traps",
        enabled ? @"enabled" : @"disabled"
    );
}

static void applyStoredDriveOptions(SessionImpl *session) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    const bool trueDrive = storedTrueDriveEmulationEnabled();

    assignCoreOption(
        session,
        "vice_drive_true_emulation",
        trueDrive ? @"enabled" : @"disabled"
    );
    assignCoreOption(
        session,
        "vice_floppy_write_protection",
        [defaults objectForKey:@"poke64.drive.writeProtection"] != nil
            && [defaults boolForKey:@"poke64.drive.writeProtection"]
            ? @"enabled"
            : @"disabled"
    );

    NSInteger soundLevel = validatedDefaultInteger(
        @"poke64.drive.soundLevel",
        20,
        0,
        100
    );
    soundLevel = std::clamp(
        static_cast<NSInteger>((soundLevel + 2) / 5 * 5),
        static_cast<NSInteger>(0),
        static_cast<NSInteger>(100)
    );
    const bool supportsSound =
        (storedDriveEnabled(8) && storedDriveTypeResourceValue(8) != 1581)
        || (storedDriveEnabled(9) && storedDriveTypeResourceValue(9) != 1581);
    assignCoreOption(
        session,
        "vice_drive_sound_emulation",
        !trueDrive || !supportsSound || soundLevel == 0
            ? @"disabled"
            : [NSString stringWithFormat:@"%ld%%", static_cast<long>(soundLevel)]
    );
}

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

static void applyStoredAudioOptions(SessionImpl *session) {
    assignCoreOption(
        session,
        "vice_sid_engine",
        validatedDefaultString(
            @"poke64.audio.sidEngine",
            @[@"FastSID", @"ReSID", @"ReSID-FP"],
            @"ReSID"
        )
    );
    assignCoreOption(
        session,
        "vice_sid_model",
        validatedDefaultString(
            @"poke64.audio.sidModel",
            @[@"default", @"6581", @"8580", @"8580RD"],
            @"default"
        )
    );
    assignCoreOption(
        session,
        "vice_resid_sampling",
        validatedDefaultString(
            @"poke64.audio.residSampling",
            @[@"fast", @"interpolation", @"fast resampling", @"resampling"],
            @"resampling"
        )
    );
    assignCoreOption(
        session,
        "vice_sound_sample_rate",
        validatedDefaultString(
            @"poke64.audio.sampleRate",
            @[@"44100", @"48000", @"96000"],
            @"48000"
        )
    );

    const NSInteger leakLevel = validatedDefaultInteger(
        @"poke64.audio.leakLevel",
        0,
        0,
        10
    );
    assignCoreOption(
        session,
        "vice_audio_leak_emulation",
        leakLevel == 0
            ? @"disabled"
            : [NSString stringWithFormat:@"%ld", static_cast<long>(leakLevel)]
    );

    NSInteger datasetteSoundLevel = validatedDefaultInteger(
        @"poke64.audio.datasetteSoundLevel",
        0,
        0,
        100
    );
    datasetteSoundLevel = std::clamp(
        static_cast<NSInteger>((datasetteSoundLevel + 2) / 5 * 5),
        static_cast<NSInteger>(0),
        static_cast<NSInteger>(100)
    );
    assignCoreOption(
        session,
        "vice_datasette_sound",
        datasetteSoundLevel == 0
            ? @"disabled"
            : [NSString stringWithFormat:@"%ld%%", static_cast<long>(datasetteSoundLevel)]
    );
}


static void ledStateCallback(int led, int state) {
    // VICE-libretro LED mapping: 0 = machine power, 1 = floppy,
    // 2 = datasette. VICE exposes a single aggregate floppy activity LED.
    if (!gSession) return;
    if (led == 1) {
        gSession->updateDriveLED(state);
    } else if (led == 2) {
        gSession->updateDatasetteLED(state);
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
            // firmware and applies the matching libretro options here so the
            // core cannot replace the selected drive backend with defaults.
            session->variables["vice_read_vicerc"] = "enabled";

            NSString *storedModel = [NSUserDefaults.standardUserDefaults
                stringForKey:@"poke64.machineModel"];
            static NSSet<NSString *> *supportedModels = [NSSet setWithArray:@[
                @"C64 PAL",
                @"C64 NTSC",
                @"C64C PAL",
                @"C64C NTSC"
            ]];
            NSString *selectedModel = [supportedModels containsObject:storedModel]
                ? storedModel
                : @"C64 PAL";
            session->variables["vice_c64_model"] = selectedModel.UTF8String;
            applyStoredREUOptions(session);
            applyStoredVideoOptions(session);
            applyStoredAudioOptions(session);
            applyStoredDriveOptions(session);
            applyStoredPrinterOptions(session);
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
                session->updateVideoGeometry(info->geometry);
            }
            return true;
        }

        case RETRO_ENVIRONMENT_SET_GEOMETRY: {
            const retro_game_geometry *geometry = static_cast<const retro_game_geometry *>(data);
            if (geometry) {
                session->updateVideoGeometry(*geometry);
            }
            return true;
        }

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

        case RETRO_ENVIRONMENT_GET_LED_INTERFACE: {
            if (!data) return true;
            retro_led_interface *interface = static_cast<retro_led_interface *>(data);
            interface->set_led_state = ledStateCallback;
            std::fprintf(stderr, "[POKE64/INFO] Libretro LED interface registered\n");
            return true;
        }

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
    applyControllerPortDevices();

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
    updateVideoGeometry(avInfo.geometry);
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
            updateDatasetteState(firstIteration);

            if (firstIteration) {
                {
                    std::string printerError;
                    if (!applyRuntimePrinterConfiguration(printerError)) {
                        recordCoreMessage(printerError.c_str(), true);
                    }
                }
                if (storedTrueDriveEmulationEnabled()) {
                    std::string driveError;
                    if (!applyRuntimeDriveConfiguration(8, driveError)) {
                        recordCoreMessage(driveError.c_str(), true);
                    } else if (storedDriveEnabled(9)
                               && !applyRuntimeDriveConfiguration(9, driveError)) {
                        recordCoreMessage(driveError.c_str(), true);
                    } else {
                        std::string soundError;
                        if (!applyRuntimeDriveSoundConfiguration(soundError)) {
                            std::fprintf(
                                stderr,
                                "[POKE64/WARN] %s\n",
                                soundError.c_str()
                            );
                        }
                    }
                }
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
        _impl->owner = self;
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

- (BOOL)controlDatasette:(C64DatasetteCommand)command {
    self.lastErrorMessage = nil;
    if (command < C64DatasetteCommandStop
        || command > C64DatasetteCommandResetCounter
        || command == 4) {
        self.lastErrorMessage = @"Unsupported datasette command";
        return NO;
    }

    std::string message;
    const bool success = _impl->performMediaCommand(
        MediaCommandType::DatasetteControl,
        nullptr,
        static_cast<int>(command),
        message
    );
    if (!success) {
        self.lastErrorMessage = [NSString stringWithUTF8String:message.c_str()];
    }
    return success;
}

- (BOOL)flushPrinterAtDevice:(NSInteger)device {
    self.lastErrorMessage = nil;
    if (device < 4 || device > 5) {
        self.lastErrorMessage = @"Printer device must be 4 or 5";
        return NO;
    }

    std::string message;
    const bool success = _impl->performMediaCommand(
        MediaCommandType::PrinterFormFeed,
        nullptr,
        static_cast<int>(device),
        message
    );
    if (!success) {
        self.lastErrorMessage = [NSString stringWithUTF8String:message.c_str()];
    }
    return success;
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
    _impl->applyControllerPortDevices();
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
