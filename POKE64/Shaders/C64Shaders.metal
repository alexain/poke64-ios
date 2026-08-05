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
