#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface C64MetalView : MTKView

@property(nonatomic, assign) BOOL crtFilterEnabled;
@property(nonatomic, assign) float crtScanlineIntensity;
@property(nonatomic, assign) float crtBeamSoftness;
@property(nonatomic, assign) float crtSharpness;
@property(nonatomic, assign) float crtMaskIntensity;
@property(nonatomic, assign) NSInteger crtMaskType;
@property(nonatomic, assign) float crtCurvature;
@property(nonatomic, assign) float crtBrightness;
@property(nonatomic, assign) float crtBloomAmount;
@property(nonatomic, assign) float crtBloomSoftness;
// Non-owning: this file is compiled with manual reference counting.
// SwiftUI clears the temporary target when the Advanced preview is dismantled.
@property(nonatomic, assign, nullable) C64MetalView *crtPreviewMirrorView;

- (void)submitFrame:(const void *)data
              width:(NSUInteger)width
             height:(NSUInteger)height
              pitch:(NSUInteger)pitch
        pixelFormat:(NSInteger)pixelFormat;

- (nullable NSData *)captureCurrentFramePNGData;

@end

NS_ASSUME_NONNULL_END
