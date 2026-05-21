#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexMain(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    const float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 fragmentMain(VertexOut in [[stage_in]],
                              texture2d<float> frameTex [[texture(0)]],
                              texture2d<float> paletteTex [[texture(1)]]) {
    constexpr sampler nearestSampler(filter::nearest, coord::normalized);
    float index = frameTex.sample(nearestSampler, in.texCoord).r;
    // palette is 256x1, sample at (index, 0.5)
    float2 paletteCoord = float2(index, 0.5);
    return paletteTex.sample(nearestSampler, paletteCoord);
}
