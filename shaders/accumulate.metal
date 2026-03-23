//
// Accumulate.metal
//
// Temporal accumulation kernel: blends the latest raytraced frame into a
// running-average texture. When the camera is still the jittered frames
// average together, progressively sharpening the image. The blend weight
// 1/N gives a true running average up to N frames, then transitions to an
// exponential moving average so the buffer stays responsive.
//

#include <metal_stdlib>
using namespace metal;

kernel void accumulate(
    texture2d<float, access::read>       new_frame   [[texture(0)]],
    texture2d<float, access::read_write> accum       [[texture(1)]],
    constant uint&                       frame_count [[buffer(0)]],
    uint2                                gid         [[thread_position_in_grid]])
{
    if (gid.x >= new_frame.get_width() || gid.y >= new_frame.get_height()) return;

    float4 incoming = new_frame.read(gid);
    // Cap at 8 frames — enough to reduce noise without smearing the animated
    // accretion streams (animated plasma following Keplerian orbits).
    float  alpha    = 1.0f / float(min(frame_count, 8u));
    float4 blended  = mix(accum.read(gid), incoming, alpha);
    accum.write(blended, gid);
}
