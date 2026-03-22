//
// Blit.metal
// Full-screen triangle pass: samples the compute texture and writes to the drawable.
//

#include <metal_stdlib>
using namespace metal;

struct BlitVertex {
    float4 position [[position]];
    float2 uv;
};

// Generates a full-screen triangle without a vertex buffer.
// Three vertices cover NDC [-1,1]² with a single over-sized triangle.
vertex BlitVertex blit_vertex(uint vid [[vertex_id]]) {
    const float2 pos[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    BlitVertex out;
    out.position = float4(pos[vid], 0.0, 1.0);
    out.uv       = pos[vid] * 0.5 + 0.5;
    out.uv.y     = 1.0 - out.uv.y;  // flip: Metal textures are top-left origin
    return out;
}

// ACES filmic tone mapping (Hill 2016 approximation)
// Maps HDR linear values to display-referred [0, 1].
static float3 aces(float3 x) {
    const float a = 2.51f, b = 0.03f, c = 2.43f, d = 0.59f, e = 0.14f;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

fragment float4 blit_fragment(BlitVertex         in    [[stage_in]],
                               texture2d<float>  tex   [[texture(0)]],
                               texture2d<float>  bloom [[texture(1)]]) {
    constexpr sampler s_near(filter::nearest, address::clamp_to_edge);
    constexpr sampler s_lin (filter::linear,  address::clamp_to_edge);

    // Chromatic aberration — R/G/B sampled at slightly different UVs,
    // offset proportional to distance from screen centre.
    float2 center = float2(0.5f, 0.5f);
    float2 dir    = in.uv - center;
    float2 ca     = dir * 0.006f;  // aberration strength (tune here)
    float3 hdr    = float3(
        tex.sample(s_near, in.uv + ca    ).r,
        tex.sample(s_near, in.uv         ).g,
        tex.sample(s_near, in.uv - ca    ).b);

    // Bloom composited in linear HDR space
    float3 glow  = bloom.sample(s_lin, in.uv).rgb;
    float3 color = aces(hdr + glow * 0.5f);

    // Vignette — soft quadratic falloff toward screen edges
    float r2 = dot(dir, dir);
    color   *= 1.0f - r2 * 1.2f;

    return float4(max(color, 0.0f), 1.0f);
}
