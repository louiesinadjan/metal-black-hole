//
// bloom.metal
//
// Three-kernel bloom pipeline:
//   1. bloom_threshold  — 2x downsample + soft-knee extract of bright regions
//   2. bloom_blur_h     — horizontal 9-tap separable gaussian
//   3. bloom_blur_v     — vertical   9-tap separable gaussian
//
// Two H+V iterations are run per frame (ping-pong between bloom_a and bloom_b)
// so the effective screen-space blur radius is ~16 pixels despite operating at
// half resolution.
//

#include <metal_stdlib>
using namespace metal;

// Normalised 9-tap gaussian weights (centre + 4 symmetric taps).
// sigma ≈ 1.5; offsets 0..4.
constant float k_gauss[5] = { 0.22703f, 0.19459f, 0.12162f, 0.05405f, 0.01622f };

// ---------------------------------------------------------------------------
// Pass 1 — downsample 2x + soft-knee threshold
//   src  : accum_texture  (full resolution, RGBA32Float)
//   dst  : bloom_a        (half resolution, RGBA16Float)
// ---------------------------------------------------------------------------
kernel void bloom_threshold(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    // 2×2 box downsample
    uint2 p = gid * 2;
    float4 c = (src.read(p)               + src.read(p + uint2(1, 0)) +
                src.read(p + uint2(0, 1)) + src.read(p + uint2(1, 1))) * 0.25f;

    // Soft-knee threshold — keeps energy near the cutoff smooth
    float lum       = dot(c.rgb, float3(0.2126f, 0.7152f, 0.0722f));
    const float T   = 0.1f;   // threshold
    const float K   = 0.1f;   // knee width
    float rq        = clamp(lum - T + K, 0.0f, 2.0f * K);
    rq              = (rq * rq) / (4.0f * K + 1e-5f);
    float w         = max(rq, lum - T) / max(lum, 1e-5f);
    c.rgb          *= w;

    dst.write(float4(max(c.rgb, 0.0f), 1.0f), gid);
}

// ---------------------------------------------------------------------------
// Pass 2 — horizontal gaussian blur
//   src  : bloom_a or bloom_b  (read)
//   dst  : bloom_b or bloom_a  (write)
// ---------------------------------------------------------------------------
kernel void bloom_blur_h(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    int W     = int(src.get_width());
    float4 col = src.read(gid) * k_gauss[0];
    for (int i = 1; i <= 4; ++i) {
        int xa = clamp(int(gid.x) + i, 0, W - 1);
        int xb = clamp(int(gid.x) - i, 0, W - 1);
        col += (src.read(uint2(xa, gid.y)) + src.read(uint2(xb, gid.y))) * k_gauss[i];
    }
    dst.write(col, gid);
}

// ---------------------------------------------------------------------------
// Pass 3 — vertical gaussian blur
//   src  : bloom_b or bloom_a  (read)
//   dst  : bloom_a or bloom_b  (write)
// ---------------------------------------------------------------------------
kernel void bloom_blur_v(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    int H      = int(src.get_height());
    float4 col = src.read(gid) * k_gauss[0];
    for (int i = 1; i <= 4; ++i) {
        int ya = clamp(int(gid.y) + i, 0, H - 1);
        int yb = clamp(int(gid.y) - i, 0, H - 1);
        col += (src.read(uint2(gid.x, ya)) + src.read(uint2(gid.x, yb))) * k_gauss[i];
    }
    dst.write(col, gid);
}
