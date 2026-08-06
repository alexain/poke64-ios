#import <Foundation/Foundation.h>

@class C64MetalView;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, C64JoypadButton) {
    C64JoypadButtonFire = 0,
    C64JoypadButtonY = 1,
    C64JoypadButtonSelect = 2,
    C64JoypadButtonStart = 3,
    C64JoypadButtonUp = 4,
    C64JoypadButtonDown = 5,
    C64JoypadButtonLeft = 6,
    C64JoypadButtonRight = 7,
    C64JoypadButtonA = 8,
    C64JoypadButtonX = 9
};

typedef NS_ENUM(NSInteger, C64KeyCode) {
    C64KeyCodeReturnKey = 13,
    C64KeyCodeEscape = 27,
    C64KeyCodeSpace = 32,
    C64KeyCodeFunction1 = 282,
    C64KeyCodeFunction3 = 284,
    C64KeyCodeFunction5 = 286,
    C64KeyCodeFunction7 = 288
};

@interface LibretroSession : NSObject

@property (nonatomic, weak, nullable) C64MetalView *videoView;
@property (nonatomic, copy, nullable) void (^videoGeometryDidChange)(double aspectRatio);
@property (nonatomic, copy, nullable) void (^driveLEDStateDidChange)(BOOL active);
@property (nonatomic, copy, readonly, nullable) NSString *lastErrorMessage;

- (BOOL)startWithoutContent;
- (BOOL)loadContentAtURL:(NSURL *)url;
- (BOOL)attachDiskAtURL:(NSURL *)url
              driveUnit:(NSInteger)unit NS_SWIFT_NAME(attachDisk(at:driveUnit:));
- (BOOL)autostartDiskAtURL:(NSURL *)url
                  driveUnit:(NSInteger)unit NS_SWIFT_NAME(autostartDisk(at:driveUnit:));
- (BOOL)attachTapeAtURL:(NSURL *)url NS_SWIFT_NAME(attachTape(at:));
- (BOOL)autostartTapeAtURL:(NSURL *)url NS_SWIFT_NAME(autostartTape(at:));
- (BOOL)runProgramAtURL:(NSURL *)url NS_SWIFT_NAME(runProgram(at:));
- (BOOL)attachCartridgeAtURL:(NSURL *)url NS_SWIFT_NAME(attachCartridge(at:));
- (BOOL)ejectDiskFromDriveUnit:(NSInteger)unit NS_SWIFT_NAME(ejectDisk(fromDriveUnit:));
- (BOOL)ejectTape;
- (BOOL)ejectCartridge;
- (BOOL)ejectAllMediaAndReset;
- (void)stop;
- (void)softReset;
- (void)hardReset;
- (void)setMousePort:(NSInteger)port;
- (void)setJoypadMask:(uint32_t)mask forC64Port:(NSInteger)port;
- (void)addMouseDeltaX:(NSInteger)deltaX deltaY:(NSInteger)deltaY;
- (void)setMouseButton:(NSInteger)button pressed:(BOOL)pressed;
- (void)setKey:(C64KeyCode)key pressed:(BOOL)pressed;
- (void)setRawKeyCode:(NSUInteger)keyCode pressed:(BOOL)pressed;

@end

NS_ASSUME_NONNULL_END
