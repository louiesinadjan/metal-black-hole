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

fragment float4 blit_fragment(BlitVertex         in    [[stage_in]],
                               texture2d<float>  tex   [[texture(0)]],
                               texture2d<float>  bloom [[texture(1)]]) {
    constexpr sampler s_near(filter::nearest, address::clamp_to_edge);
    constexpr sampler s_lin (filter::linear,  address::clamp_to_edge);
    float4 base = tex.sample(s_near, in.uv);
    float4 glow = bloom.sample(s_lin, in.uv);  // bilinear upsample from half-res
    return float4(base.rgb + glow.rgb * 2.0f, 1.0f);
}
