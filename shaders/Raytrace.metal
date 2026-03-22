//
// Raytrace.metal
//
// Schwarzschild black hole raytracer using the null geodesic orbit equation.
//
// Physics overview:
//   A photon in Schwarzschild spacetime obeys the orbit equation
//       d²u/dφ² = 3·M·u² − u       (u = 1/r, φ = orbital angle)
//   integrated with RK4. The photon path is confined to the orbital plane
//   defined by the camera ray and the black hole. We track the 3D position
//   within that plane to detect intersections with the accretion disk
//   (y = 0 equatorial plane) and the event horizon (r < RS).
//
// Units: Schwarzschild radius RS = 1 throughout.
//

#include <metal_stdlib>
#include "src/shader_types.h"

using namespace metal;

// Constants 

constant float RS            = 1.0;          // Schwarzschild radius
constant float M             = RS / 2.0;     // Mass  (RS = 2GM/c², G=c=1)
constant float R_ISCO        = 3.0 * RS;     // Innermost stable circular orbit
constant float R_DISK_OUTER  = 12.0 * RS;    // Outer edge of accretion disk

// Background sky + stars

static float star_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f);
}

static float4 skyColor(float3 dir) {
    // Spherical UV from escape direction
    float phi   = atan2(dir.x, dir.z);             // azimuth  [-π, π]
    float theta = asin(clamp(dir.y, -1.0f, 1.0f)); // elevation [-π/2, π/2]
    float2 uv   = float2(phi / (2.0f * M_PI_F) + 0.5f,
                         theta / M_PI_F + 0.5f);

    // Procedural star field: grid of cells, one potential star per cell
    float2 cell  = floor(uv * 256.0f);
    float2 local = fract(uv * 256.0f) - 0.5f;
    float  rng   = star_hash(cell);
    float  star  = (rng > 0.994f) ? max(0.0f, 1.0f - length(local) * 8.0f) : 0.0f;
    star *= star_hash(cell + 0.5f) * 1.5f + 0.5f;  // vary brightness

    float up = max(0.0f, dir.y) * 0.1f;
    return float4(0.005f + star,
                  0.005f + star,
                  0.02f  + star + up,
                  1.0f);
}

// Accretion disk color

static float4 diskColor(float r) {
    // Temperature gradient: white-yellow near ISCO, orange-red at outer edge
    float t           = saturate((r - R_ISCO) / (R_DISK_OUTER - R_ISCO));
    float3 innerColor = float3(1.0f, 0.95f, 0.7f);
    float3 outerColor = float3(0.8f, 0.15f, 0.02f);
    float3 col        = mix(innerColor, outerColor, sqrt(t));
    float  brightness = 2.0f / (t * 5.0f + 0.3f);   // brighter toward ISCO
    return float4(col * brightness, 1.0f);
}

// Geodesic integrator 

static float4 traceRay(float3 rayOrigin, float3 rayDir) {
    float r0 = length(rayOrigin);

    // Orbital plane basis vectors
    float3 e1   = normalize(rayOrigin);           // BH → camera (radial)
    float3 Lvec = cross(rayOrigin, rayDir);        // angular momentum axis
    float  b    = length(Lvec);                    // impact parameter

    // Degenerate: ray aimed directly at or away from the black hole
    if (b < 1e-5f) {
        bool towardBH = dot(rayDir, -e1) > 0.0f;
        return towardBH ? float4(0, 0, 0, 1) : skyColor(rayDir);
    }

    float3 eN = Lvec / b;            // orbital plane normal
    float3 e2 = cross(eN, e1);       // tangential direction (φ increases here)

    // Initial orbit-equation state  [u = 1/r, du = du/dφ]
    float u  = 1.0f / r0;
    float du = -dot(rayDir, e1) / b; // sign: inward ray → u increasing

    const float dphi    = 0.005f;
    const int   maxIter = 3000;

    float prevY = rayOrigin.y;   // for equatorial-plane crossing detection

    for (int i = 0; i < maxIter; i++) {
        float u1  = u,                du1  = du;
        float f1u = du1,              f1d  = 3.0f*M*u1*u1 - u1;

        float u2  = u  + 0.5f*dphi*f1u,  du2 = du + 0.5f*dphi*f1d;
        float f2u = du2,              f2d  = 3.0f*M*u2*u2 - u2;

        float u3  = u  + 0.5f*dphi*f2u,  du3 = du + 0.5f*dphi*f2d;
        float f3u = du3,              f3d  = 3.0f*M*u3*u3 - u3;

        float u4  = u  + dphi*f3u,       du4 = du + dphi*f3d;
        float f4u = du4,              f4d  = 3.0f*M*u4*u4 - u4;

        u  += dphi / 6.0f * (f1u + 2.0f*f2u + 2.0f*f3u + f4u);
        du += dphi / 6.0f * (f1d + 2.0f*f2d + 2.0f*f3d + f4d);

        float phi = dphi * float(i + 1);
        float r   = 1.0f / max(u, 1e-7f);

        // Hit event horizon 
        if (r < RS) return float4(0, 0, 0, 1);

        // Escaped to far background 
        if (u <= 0.0f || r > 300.0f) {
            // Reconstruct 3D escape direction from orbital-plane vectors
            float3 rHat     = cos(phi)*e1 + sin(phi)*e2;
            float3 phiHat   = -sin(phi)*e1 + cos(phi)*e2;
            float3 escapeDir = normalize(-du * rHat + phiHat);
            return skyColor(escapeDir);
        }

        // Accretion disk: equatorial-plane (y = 0) crossing
        float3 pos3D = r * (cos(phi)*e1 + sin(phi)*e2);
        float  curY  = pos3D.y;

        if (prevY * curY < 0.0f && r > R_ISCO && r < R_DISK_OUTER)
            return diskColor(r);

        prevY = curY;
    }

    // Photon captured (too many iterations)
    return float4(0, 0, 0, 1);
}

// Compute kernel 

kernel void raytrace(texture2d<float, access::write> outTexture [[texture(0)]],
                     constant CameraData&            camera     [[buffer(0)]],
                     uint2                           gid        [[thread_position_in_grid]])
{
    uint w = outTexture.get_width();
    uint h = outTexture.get_height();
    if (gid.x >= w || gid.y >= h) return;

    // NDC in [-1, 1], y pointing up
    float2 uv = (float2(gid) + 0.5f) / float2(w, h);
    uv        = uv * 2.0f - 1.0f;
    uv.y      = -uv.y;   // flip: gid.y=0 is top of texture

    // Perspective ray from camera
    float  halfTanFov = tan(camera.forward.w * 0.5f);
    float3 rayOrigin  = camera.position.xyz;
    float3 rayDir     = normalize(
        camera.forward.xyz
        + uv.x * camera.right.w * halfTanFov * camera.right.xyz
        + uv.y *                  halfTanFov * camera.up.xyz);

    outTexture.write(traceRay(rayOrigin, rayDir), gid);
}
