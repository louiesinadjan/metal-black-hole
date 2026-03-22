#pragma once

//
// Shared type definitions between C++ host code and Metal shaders.
// Use float4 throughout to guarantee 16-byte alignment on both sides.
//

#ifdef __METAL_VERSION__
#   include <metal_stdlib>
    using namespace metal;
    typedef float4 vec4;
#else
#   include <simd/simd.h>
    typedef simd_float4 vec4;
#endif

struct CameraData {
    vec4 position;  // .xyz = world-space position,    .w = unused
    vec4 forward;   // .xyz = forward direction,        .w = vertical FoV (radians)
    vec4 right;     // .xyz = right direction,          .w = aspect ratio (width/height)
    vec4 up;        // .xyz = up direction,             .w = frame count (TAA jitter)
};
