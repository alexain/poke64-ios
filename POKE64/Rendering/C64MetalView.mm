#import "C64MetalView.h"

#import <UIKit/UIKit.h>

#include <algorithm>
#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>
#include <simd/simd.h>

struct C64MetalVertex {
    simd_float2 position;
    simd_float2 texCoord;
};

struct C64MetalState {
    id<MTLCommandQueue> commandQueue = nil;
    id<MTLRenderPipelineState> pipeline = nil;
    id<MTLTexture> texture = nil;
    std::mutex mutex;
    std::vector<uint8_t> pixels;
    NSUInteger width = 0;
    NSUInteger height = 0;
    bool dirty = false;
};

@interface C64MetalView () <MTKViewDelegate> {
    std::unique_ptr<C64MetalState> _state;
}
@end

@implementation C64MetalView

- (void)configureMetalView {
    id<MTLDevice> device = self.device ?: MTLCreateSystemDefaultDevice();
    self.device = device;

    _state = std::make_unique<C64MetalState>();
    self.delegate = self;
    self.paused = YES;
    self.enableSetNeedsDisplay = YES;
    self.framebufferOnly = YES;
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.clearColor = MTLClearColorMake(0.02, 0.02, 0.025, 1.0);
    self.autoResizeDrawable = YES;

    _state->commandQueue = [device newCommandQueue];

    id<MTLLibrary> library = [device newDefaultLibrary];
    id<MTLFunction> vertex = [library newFunctionWithName:@"c64Vertex"];
    id<MTLFunction> fragment = [library newFunctionWithName:@"c64Fragment"];

    MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertex;
    descriptor.fragmentFunction = fragment;
    descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;

    NSError *error = nil;
    _state->pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!_state->pipeline) {
        NSLog(@"Metal pipeline error: %@", error);
    }
}

- (instancetype)initWithFrame:(CGRect)frameRect {
    self = [super initWithFrame:frameRect device:MTLCreateSystemDefaultDevice()];
    if (self) {
        [self configureMetalView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self configureMetalView];
    }
    return self;
}

- (void)submitFrame:(const void *)data
              width:(NSUInteger)width
             height:(NSUInteger)height
              pitch:(NSUInteger)pitch
        pixelFormat:(NSInteger)pixelFormat {
    if (!data || width == 0 || height == 0) {
        return;
    }

    std::vector<uint8_t> converted(width * height * 4);
    const uint8_t *source = static_cast<const uint8_t *>(data);

    for (NSUInteger y = 0; y < height; ++y) {
        const uint8_t *row = source + y * pitch;
        uint8_t *destination = converted.data() + y * width * 4;

        for (NSUInteger x = 0; x < width; ++x) {
            uint8_t red = 0;
            uint8_t green = 0;
            uint8_t blue = 0;

            if (pixelFormat == 1) { // XRGB8888
                uint32_t value = reinterpret_cast<const uint32_t *>(row)[x];
                red = static_cast<uint8_t>((value >> 16) & 0xff);
                green = static_cast<uint8_t>((value >> 8) & 0xff);
                blue = static_cast<uint8_t>(value & 0xff);
            } else if (pixelFormat == 2) { // RGB565
                uint16_t value = reinterpret_cast<const uint16_t *>(row)[x];
                red = static_cast<uint8_t>(((value >> 11) & 0x1f) * 255 / 31);
                green = static_cast<uint8_t>(((value >> 5) & 0x3f) * 255 / 63);
                blue = static_cast<uint8_t>((value & 0x1f) * 255 / 31);
            } else { // 0RGB1555
                uint16_t value = reinterpret_cast<const uint16_t *>(row)[x];
                red = static_cast<uint8_t>(((value >> 10) & 0x1f) * 255 / 31);
                green = static_cast<uint8_t>(((value >> 5) & 0x1f) * 255 / 31);
                blue = static_cast<uint8_t>((value & 0x1f) * 255 / 31);
            }

            destination[x * 4 + 0] = blue;
            destination[x * 4 + 1] = green;
            destination[x * 4 + 2] = red;
            destination[x * 4 + 3] = 255;
        }
    }

    {
        std::lock_guard<std::mutex> lock(_state->mutex);
        _state->pixels.swap(converted);
        _state->width = width;
        _state->height = height;
        _state->dirty = true;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsDisplay];
    });
}

- (nullable NSData *)captureCurrentFramePNGData {
    std::vector<uint8_t> pixels;
    NSUInteger width = 0;
    NSUInteger height = 0;

    {
        std::lock_guard<std::mutex> lock(_state->mutex);
        pixels = _state->pixels;
        width = _state->width;
        height = _state->height;
    }

    if (pixels.empty() || width == 0 || height == 0) {
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) {
        return nil;
    }

    CGBitmapInfo bitmapInfo = (CGBitmapInfo)(kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGContextRef context = CGBitmapContextCreate(
        pixels.data(),
        width,
        height,
        8,
        width * 4,
        colorSpace,
        bitmapInfo
    );
    CGColorSpaceRelease(colorSpace);

    if (!context) {
        return nil;
    }

    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!imageRef) {
        return nil;
    }

    UIImage *image = [UIImage imageWithCGImage:imageRef scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(imageRef);
    return UIImagePNGRepresentation(image);
}

- (void)drawInMTKView:(MTKView *)view {
    if (!_state->pipeline || !view.currentDrawable || !view.currentRenderPassDescriptor) {
        return;
    }

    std::vector<uint8_t> pixels;
    NSUInteger width = 0;
    NSUInteger height = 0;

    {
        std::lock_guard<std::mutex> lock(_state->mutex);
        if (_state->dirty) {
            pixels = _state->pixels;
            width = _state->width;
            height = _state->height;
            _state->dirty = false;
        }
    }

    if (!pixels.empty()) {
        if (!_state->texture || _state->texture.width != width || _state->texture.height != height) {
            MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor
                texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                width:width
                height:height
                mipmapped:NO];
            textureDescriptor.usage = MTLTextureUsageShaderRead;
            _state->texture = [self.device newTextureWithDescriptor:textureDescriptor];
        }

        MTLRegion region = MTLRegionMake2D(0, 0, width, height);
        [_state->texture replaceRegion:region
                           mipmapLevel:0
                             withBytes:pixels.data()
                           bytesPerRow:width * 4];
    }

    id<MTLCommandBuffer> commandBuffer = [_state->commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];
    [encoder setRenderPipelineState:_state->pipeline];

    float sourceAspect = _state->height > 0 ? (float)_state->width / (float)_state->height : 4.0f / 3.0f;
    float targetAspect = view.drawableSize.height > 0 ? (float)view.drawableSize.width / (float)view.drawableSize.height : sourceAspect;
    float xScale = 1.0f;
    float yScale = 1.0f;
    if (targetAspect > sourceAspect) {
        xScale = sourceAspect / targetAspect;
    } else {
        yScale = targetAspect / sourceAspect;
    }

    const C64MetalVertex vertices[] = {
        {{-xScale, -yScale}, {0.0f, 1.0f}},
        {{ xScale, -yScale}, {1.0f, 1.0f}},
        {{-xScale,  yScale}, {0.0f, 0.0f}},
        {{ xScale,  yScale}, {1.0f, 0.0f}}
    };

    [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
    if (_state->texture) {
        [encoder setFragmentTexture:_state->texture atIndex:0];
    }
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [encoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
}

@end
