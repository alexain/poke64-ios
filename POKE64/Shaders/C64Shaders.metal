#include <metal_stdlib>
using namespace metal;

struct C64Vertex {
    float2 position;
    float2 texCoord;
};

struct C64VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct C64CRTParameters {
    float4 appearance;
    float4 geometry;
    float4 effects;
};

vertex C64VertexOut c64Vertex(
    const device C64Vertex *vertices [[buffer(0)]],
    uint vertexID [[vertex_id]]) {
    C64VertexOut output;
    output.position = float4(vertices[vertexID].position, 0.0, 1.0);
    output.texCoord = vertices[vertexID].texCoord;
    return output;
}

fragment float4 c64Fragment(
    C64VertexOut input [[stage_in]],
    texture2d<float> frameTexture [[texture(0)]]) {
    constexpr sampler frameSampler(
        mag_filter::nearest,
        min_filter::nearest,
        address::clamp_to_edge);
    return frameTexture.sample(frameSampler, input.texCoord);
}

// CRT-Lottes-inspired single-pass CRT filter for POKE64.
// Based on Timothy Lottes' public-domain CRT shader used by libretro.
// POKE64 exposes a curated subset of Lottes-style controls, including
// selectable phosphor masks and a lightweight single-pass bloom.

static float crtToLinear1(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

static float3 crtToLinear(float3 c) {
    return float3(crtToLinear1(c.r), crtToLinear1(c.g), crtToLinear1(c.b));
}

static float crtToSRGB1(float c) {
    c = max(c, 0.0);
    return c < 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

static float3 crtToSRGB(float3 c) {
    return float3(crtToSRGB1(c.r), crtToSRGB1(c.g), crtToSRGB1(c.b));
}

static float2 crtWarp(float2 pos, float curvature) {
    float warpX = 0.0225 * clamp(curvature, 0.0, 1.0);
    float warpY = 0.0270 * clamp(curvature, 0.0, 1.0);
    pos = pos * 2.0 - 1.0;
    pos *= float2(1.0 + pos.y * pos.y * warpX,
                  1.0 + pos.x * pos.x * warpY);
    return pos * 0.5 + 0.5;
}

static float crtGaussian(float position, float scale) {
    constexpr float shape = 2.0;
    return exp2(scale * pow(abs(position), shape));
}

static float2 crtDistance(float2 pos, float2 sourceSize) {
    float2 sourcePos = pos * sourceSize;
    return -((sourcePos - floor(sourcePos)) - float2(0.5));
}

static float3 crtFetch(
    texture2d<float> frameTexture,
    float2 sourceSize,
    float2 pos,
    float2 offset,
    float brightness) {
    float2 samplePosition = (floor(pos * sourceSize + offset) + float2(0.5)) / sourceSize;
    if (any(samplePosition < float2(0.0)) || any(samplePosition > float2(1.0))) {
        return float3(0.0);
    }

    constexpr sampler frameSampler(
        mag_filter::nearest,
        min_filter::nearest,
        address::clamp_to_edge);
    return crtToLinear(frameTexture.sample(frameSampler, samplePosition).rgb * brightness);
}

static float3 crtHorz3(
    texture2d<float> frameTexture,
    float2 sourceSize,
    float2 pos,
    float offset,
    float hardPixel,
    float brightness) {
    float3 left = crtFetch(frameTexture, sourceSize, pos, float2(-1.0, offset), brightness);
    float3 center = crtFetch(frameTexture, sourceSize, pos, float2(0.0, offset), brightness);
    float3 right = crtFetch(frameTexture, sourceSize, pos, float2(1.0, offset), brightness);
    float distance = crtDistance(pos, sourceSize).x;
    float leftWeight = crtGaussian(distance - 1.0, hardPixel);
    float centerWeight = crtGaussian(distance, hardPixel);
    float rightWeight = crtGaussian(distance + 1.0, hardPixel);
    return (left * leftWeight + center * centerWeight + right * rightWeight)
         / (leftWeight + centerWeight + rightWeight);
}

static float3 crtHorz5(
    texture2d<float> frameTexture,
    float2 sourceSize,
    float2 pos,
    float offset,
    float hardPixel,
    float brightness) {
    float3 a = crtFetch(frameTexture, sourceSize, pos, float2(-2.0, offset), brightness);
    float3 b = crtFetch(frameTexture, sourceSize, pos, float2(-1.0, offset), brightness);
    float3 c = crtFetch(frameTexture, sourceSize, pos, float2(0.0, offset), brightness);
    float3 d = crtFetch(frameTexture, sourceSize, pos, float2(1.0, offset), brightness);
    float3 e = crtFetch(frameTexture, sourceSize, pos, float2(2.0, offset), brightness);
    float distance = crtDistance(pos, sourceSize).x;
    float wa = crtGaussian(distance - 2.0, hardPixel);
    float wb = crtGaussian(distance - 1.0, hardPixel);
    float wc = crtGaussian(distance, hardPixel);
    float wd = crtGaussian(distance + 1.0, hardPixel);
    float we = crtGaussian(distance + 2.0, hardPixel);
    return (a * wa + b * wb + c * wc + d * wd + e * we)
         / (wa + wb + wc + wd + we);
}

static float crtScanWeight(
    float2 pos,
    float2 sourceSize,
    float offset,
    float hardScan) {
    float distance = crtDistance(pos, sourceSize).y;
    return crtGaussian(distance + offset, hardScan);
}

static float3 crtTri(
    texture2d<float> frameTexture,
    float2 sourceSize,
    float2 pos,
    float scanlineIntensity,
    float beamSoftness,
    float sharpness,
    float brightness) {
    float hardPixel = mix(-1.6, -6.0, clamp(sharpness, 0.0, 1.0));
    float hardScan = mix(-12.0, -4.0, clamp(beamSoftness, 0.0, 1.0));
    float3 previous = crtHorz3(frameTexture, sourceSize, pos, -1.0, hardPixel, brightness);
    float3 current = crtHorz5(frameTexture, sourceSize, pos, 0.0, hardPixel, brightness);
    float3 next = crtHorz3(frameTexture, sourceSize, pos, 1.0, hardPixel, brightness);
    float previousWeight = crtScanWeight(pos, sourceSize, -1.0, hardScan);
    float currentWeight = crtScanWeight(pos, sourceSize, 0.0, hardScan);
    float nextWeight = crtScanWeight(pos, sourceSize, 1.0, hardScan);
    float3 scanlined = previous * previousWeight
                    + current * currentWeight
                    + next * nextWeight;
    return mix(current, scanlined, clamp(scanlineIntensity, 0.0, 1.0));
}

static float3 crtBloom(
    texture2d<float> frameTexture,
    float2 sourceSize,
    float2 pos,
    float softness,
    float brightness) {
    float soft = clamp(softness, 0.0, 1.0);
    float hardBloomPixel = mix(-2.4, -0.55, soft);
    float hardBloomScan = mix(-5.0, -1.15, soft);
    float3 previous = crtHorz5(frameTexture, sourceSize, pos, -1.0, hardBloomPixel, brightness);
    float3 current = crtHorz5(frameTexture, sourceSize, pos, 0.0, hardBloomPixel, brightness);
    float3 next = crtHorz5(frameTexture, sourceSize, pos, 1.0, hardBloomPixel, brightness);
    float previousWeight = crtScanWeight(pos, sourceSize, -1.0, hardBloomScan);
    float currentWeight = crtScanWeight(pos, sourceSize, 0.0, hardBloomScan);
    float nextWeight = crtScanWeight(pos, sourceSize, 1.0, hardBloomScan);
    float weightSum = max(previousWeight + currentWeight + nextWeight, 0.0001);
    return (previous * previousWeight
          + current * currentWeight
          + next * nextWeight) / weightSum;
}

static float3 crtMask(float2 outputPixel, int maskType) {
    if (maskType <= 0) {
        return float3(1.0);
    }

    constexpr float maskDark = 0.82;
    constexpr float maskLight = 1.12;
    float3 mask = float3(maskDark);
    int x = int(floor(outputPixel.x));
    int y = int(floor(outputPixel.y));
    int channel = 0;

    if (maskType == 1) {
        // Dot/shadow mask: stagger RGB triads on alternating scan rows.
        channel = (x + (y & 1)) % 3;
        if ((y & 1) != 0) {
            mask *= 0.96;
        }
    } else if (maskType == 2) {
        // Aperture grille: continuous vertical RGB phosphor stripes.
        channel = x % 3;
    } else {
        // VGA-style mask: wider, staggered phosphor groups.
        channel = ((x / 2) + (y & 1)) % 3;
        if (((x + y) & 1) != 0) {
            mask *= 0.94;
        }
    }

    if (channel == 0) {
        mask.r = maskLight;
    } else if (channel == 1) {
        mask.g = maskLight;
    } else {
        mask.b = maskLight;
    }
    return mask;
}

fragment float4 c64CRTFragment(
    C64VertexOut input [[stage_in]],
    texture2d<float> frameTexture [[texture(0)]],
    constant C64CRTParameters &parameters [[buffer(0)]]) {
    float2 sourceSize = float2(
        (float)frameTexture.get_width(),
        (float)frameTexture.get_height());
    if (sourceSize.x <= 0.0 || sourceSize.y <= 0.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float scanlineIntensity = clamp(parameters.appearance.x, 0.0, 1.0);
    float beamSoftness = clamp(parameters.appearance.y, 0.0, 1.0);
    float sharpness = clamp(parameters.appearance.z, 0.0, 1.0);
    float maskIntensity = clamp(parameters.appearance.w, 0.0, 1.0);
    float curvature = clamp(parameters.geometry.x, 0.0, 1.0);
    float brightness = clamp(parameters.geometry.y, 0.80, 1.30);
    float bloomAmount = clamp(parameters.geometry.z, 0.0, 1.0);
    float bloomSoftness = clamp(parameters.geometry.w, 0.0, 1.0);
    int maskType = clamp(int(parameters.effects.x + 0.5), 0, 3);

    float2 pos = crtWarp(input.texCoord, curvature);
    if (any(pos < float2(0.0)) || any(pos > float2(1.0))) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float3 color = crtTri(
        frameTexture,
        sourceSize,
        pos,
        scanlineIntensity,
        beamSoftness,
        sharpness,
        brightness
    );
    if (bloomAmount > 0.001) {
        float3 glow = crtBloom(
            frameTexture,
            sourceSize,
            pos,
            bloomSoftness,
            brightness
        );
        color += glow * (0.35 * bloomAmount);
    }

    color *= mix(float3(1.0), crtMask(input.position.xy, maskType), maskIntensity);
    return float4(crtToSRGB(color), 1.0);
}
