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
@property (nonatomic, copy, readonly, nullable) NSString *lastErrorMessage;

- (BOOL)startWithoutContent;
- (BOOL)loadContentAtURL:(NSURL *)url;
- (void)stop;
- (void)softReset;
- (void)hardReset;
- (void)setVirtualJoystickPort:(NSInteger)port;
- (void)setJoypadButton:(C64JoypadButton)button pressed:(BOOL)pressed;
- (void)setKey:(C64KeyCode)key pressed:(BOOL)pressed;
- (void)setRawKeyCode:(NSUInteger)keyCode pressed:(BOOL)pressed;

@end

NS_ASSUME_NONNULL_END
