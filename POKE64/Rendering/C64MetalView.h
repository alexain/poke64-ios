#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface C64MetalView : MTKView

- (void)submitFrame:(const void *)data
              width:(NSUInteger)width
             height:(NSUInteger)height
              pitch:(NSUInteger)pitch
        pixelFormat:(NSInteger)pixelFormat;

@end

NS_ASSUME_NONNULL_END
