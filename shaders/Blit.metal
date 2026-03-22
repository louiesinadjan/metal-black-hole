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

fragment float4 blit_fragment(BlitVertex          in  [[stage_in]],
                               texture2d<float>   tex [[texture(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    return tex.sample(s, in.uv);
}
