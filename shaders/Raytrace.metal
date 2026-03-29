//
// Raytrace.metal
//
// Schwarzschild black hole raytracer using the null geodesic orbit equation.
//
// Physics overview:
//   A photon in Schwarzschild spacetime obeys the orbit equation
//       d^2u/dphi^2 = 3*M*u^2 - u       (u = 1/r, phi = orbital angle)
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

// Halton low-discrepancy sequence (base 2 and base 3 for xy jitter)

static float halton(uint i, uint base) {
    float f = 1.0f, r = 0.0f;
    while (i > 0) { f /= float(base); r += f * float(i % base); i /= base; }
    return r;
}

// Constants

constant float RS            = 1.0;          // Schwarzschild radius
constant float M             = RS / 2.0;     // Mass  (RS = 2GM/c^2, G=c=1)
constant float R_ISCO        = 3.0 * RS;     // Innermost stable circular orbit
constant float R_DISK_OUTER  = 20.0 * RS;    // Outer edge of accretion disk

// Background sky + stars

static float star_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f);
}

// Stellar color from spectral type: blue giant -> yellow -> orange -> red dwarf
static float3 star_tint(float2 cell) {
    float t = star_hash(cell + float2(3.7f, 8.1f));  // independent rng
    if      (t < 0.08f) return float3(0.7f, 0.8f,  1.0f);  // blue-white giant
    else if (t < 0.25f) return float3(0.9f, 0.95f, 1.0f);  // white
    else if (t < 0.60f) return float3(1.0f, 0.97f, 0.85f); // yellow (sun-like)
    else if (t < 0.85f) return float3(1.0f, 0.75f, 0.45f); // orange
    else                return float3(1.0f, 0.45f, 0.25f);  // red dwarf
}

// Stars at one grid scale; threshold controls density
static float3 star_layer(float2 uv, float scale, float threshold, float size) {
    float2 cell  = floor(uv * scale);
    float2 local = fract(uv * scale) - 0.5f;
    float  rng   = star_hash(cell);
    if (rng <= threshold) return float3(0.0f);
    float brightness = star_hash(cell + 0.5f) * 1.4f + 0.6f;
    float spot = max(0.0f, 1.0f - length(local) * size);
    return star_tint(cell) * (spot * brightness);
}

// Milky Way band: faint nebula glow along a tilted great circle.
// We use a rotated coordinate so the "galaxy plane" is tilted ~60deg from equator.
static float milky_way(float3 dir) {
    // Rotate dir into galactic frame (tilt ~60deg around z-axis)
    const float ca = 0.5f, sa = 0.866f;  // cos/sin 60deg
    float3 g = float3(dir.x * ca - dir.y * sa,
                      dir.x * sa + dir.y * ca,
                      dir.z);
    // Latitude in galactic frame -glow peaks at b=0 (the galactic plane)
    float b    = asin(clamp(g.y, -1.0f, 1.0f));
    float band = exp(-b * b * 18.0f);  // gaussian falloff in latitude

    // Longitude-varying density using low-frequency noise
    float lon = atan2(g.x, g.z) / (2.0f * M_PI_F) + 0.5f;
    float2 np = float2(lon * 4.0f, 0.5f);
    float2 i  = floor(np);
    float2 f  = fract(np);
    float2 u  = f * f * (3.0f - 2.0f * f);
    float  n  = mix(mix(star_hash(i),               star_hash(i + float2(1,0)), u.x),
                    mix(star_hash(i+float2(0,1)),    star_hash(i + float2(1,1)), u.x), u.y);

    return band * (0.4f + 0.6f * n);
}

// Distant galaxies: sparse grid of faint elliptical/spiral blobs
static float3 galaxy_field(float2 uv) {
    const float scale = 32.0f;
    float2 cell  = floor(uv * scale);
    float2 local = fract(uv * scale) - 0.5f;

    float rng = star_hash(cell);
    if (rng < 0.93f) return float3(0.0f);

    // Random center offset within cell
    float2 center = float2(star_hash(cell + float2(0.1f, 0.0f)),
                           star_hash(cell + float2(0.2f, 0.0f))) - 0.5f;
    float2 d = local - center * 0.8f;

    // Random orientation and aspect ratio -> elliptical shape
    float angle  = star_hash(cell + float2(0.3f, 0.0f)) * M_PI_F;
    float aspect = 0.3f + star_hash(cell + float2(0.4f, 0.0f)) * 0.5f;
    float ca = cos(angle), sa = sin(angle);
    float2 rot = float2(d.x * ca - d.y * sa, d.x * sa + d.y * ca);
    rot.y /= aspect;
    float dist2 = dot(rot, rot);

    float peak   = 0.04f + star_hash(cell + float2(0.5f, 0.0f)) * 0.06f;
    float blob   = exp(-dist2 * 80.0f) * peak;

    // Color: spiral (blue-white) or elliptical (warm yellow-white)
    float3 color = (star_hash(cell + float2(0.6f, 0.0f)) < 0.4f)
                   ? float3(0.75f, 0.85f, 1.0f)    // spiral -blue-white
                   : float3(1.0f,  0.92f, 0.75f);  // elliptical -warm

    return color * blob;
}

// Emission nebulae: 3 soft colored clouds at fixed sky positions
static float3 nebula_clouds(float3 dir, float2 uv) {
    float3 result = float3(0.0f);

    // Anchor directions, colors, angular-size parameter k, peak brightness
    const float3 anchors[3] = {
        normalize(float3( 0.6f,  0.5f, -0.6f)),
        normalize(float3(-0.7f, -0.3f,  0.5f)),
        normalize(float3( 0.1f, -0.6f, -0.8f)),
    };
    const float3 colors[3] = {
        float3(0.05f, 0.18f, 0.25f),  // blue-green (oxygen emission)
        float3(0.22f, 0.05f, 0.10f),  // red-pink   (hydrogen-alpha)
        float3(0.12f, 0.06f, 0.20f),  // purple     (mixed)
    };
    const float k[3]    = { 38.0f, 50.0f, 32.0f };
    const float peak[3] = { 0.55f, 0.50f, 0.45f };

    for (int i = 0; i < 3; ++i) {
        float fade = exp((dot(dir, anchors[i]) - 1.0f) * k[i]);
        if (fade < 0.001f) continue;

        // 2-octave fbm warp for organic edge -reuse uv noise
        float2 np = uv * 3.0f + float2(float(i) * 1.7f, 0.0f);
        float2 ni = floor(np);
        float2 nf = fract(np);
        float2 nu = nf * nf * (3.0f - 2.0f * nf);
        float  n1 = mix(mix(star_hash(ni),               star_hash(ni+float2(1,0)), nu.x),
                        mix(star_hash(ni+float2(0,1)),    star_hash(ni+float2(1,1)), nu.x), nu.y);
        np *= 2.1f;
        ni = floor(np); nf = fract(np); nu = nf*nf*(3.0f-2.0f*nf);
        float  n2 = mix(mix(star_hash(ni),               star_hash(ni+float2(1,0)), nu.x),
                        mix(star_hash(ni+float2(0,1)),    star_hash(ni+float2(1,1)), nu.x), nu.y);
        float  warp = 0.55f * n1 + 0.45f * n2;

        result += colors[i] * fade * warp * peak[i];
    }
    return result;
}

static float4 skyColor(float3 dir) {
    // Spherical UV from escape direction
    float phi   = atan2(dir.x, dir.z);
    float theta = asin(clamp(dir.y, -1.0f, 1.0f));
    float2 uv   = float2(phi / (2.0f * M_PI_F) + 0.5f,
                         theta / M_PI_F + 0.5f);

    // Two star layers: bright foreground + faint dense background
    float3 stars  = star_layer(uv, 256.0f, 0.994f, 8.0f);
           stars += star_layer(uv, 512.0f, 0.988f, 12.0f) * 0.35f;

    // Milky Way band
    float  mw       = milky_way(dir);
    float3 mw_color = float3(0.12f, 0.10f, 0.22f) * mw * 0.6f;

    // Nebulae and galaxies
    float3 nebulae  = nebula_clouds(dir, uv);
    float3 galaxies = galaxy_field(uv);

    // Deep space background
    float3 sky = float3(0.003f, 0.004f, 0.012f);

    return float4(sky + mw_color + nebulae + galaxies + stars, 1.0f);
}

// Turbulence noise -bilinear value noise + 4-octave fbm
// Used to modulate disk brightness with MHD-like density fluctuations.

static float noise2(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0f - 2.0f * f);  // smoothstep
    return mix(mix(star_hash(i),                star_hash(i + float2(1, 0)), u.x),
               mix(star_hash(i + float2(0, 1)), star_hash(i + float2(1, 1)), u.x), u.y);
}

static float disk_fbm(float2 p) {
    float v = 0.0f, a = 0.5f;
    for (int i = 0; i < 4; ++i) {
        v += a * noise2(p);
        p  = p * 2.1f + float2(1.7f, 9.2f);  // offset avoids lattice alignment
        a *= 0.5f;
    }
    return v;  // ~ [0, 1]
}

// Volumetric cloud disk
//
// Replaces the thin equatorial plane with a 3D gas cloud. Density is sampled
// at every geodesic step inside the disk region and accumulated via alpha
// compositing, giving real vertical thickness, depth, and Keplerian swirls.

// Henyey-Greenstein phase function.
//
// Describes how likely a photon is to scatter in a given direction when
// passing through a particle. cos_theta is the angle between the light
// direction and the view direction.
//   g > 0 ->forward scattering (bright when looking toward the light)
//   g < 0 ->backward scattering (bright when looking away from light)
//   g = 0 ->isotropic (uniform in all directions)
static float hg(float cos_theta, float g) {
    float g2 = g * g;
    return (1.0f - g2) / (4.0f * M_PI_F * pow(1.0f + g2 - 2.0f * g * cos_theta, 1.5f));
}

// Double-lobed HG: blends a forward lobe (in-falling gas) and back lobe
// (scattered light returning toward camera) for a richer appearance.
static float double_hg(float cos_theta, float g_fwd, float g_bck, float weight) {
    return weight * hg(cos_theta, g_fwd) + (1.0f - weight) * hg(cos_theta, g_bck);
}

// Base cloud colour: neutral blue-white tint -lighting drives the brightness
static float3 cloud_color(float r) {
    float  t     = saturate((r - R_ISCO) / (R_DISK_OUTER - R_ISCO));
    float3 inner = float3(0.85f, 0.92f, 1.0f);   // blue-white
    float3 outer = float3(0.25f, 0.35f, 0.55f);  // steel blue
    return mix(inner, outer, pow(t, 0.25f));
}

// 3D cloud density: radial envelope x vertical falloff x Keplerian swirl noise
static float cloud_density(float3 pos, float r, float anim_time) {
    // Radial: quick ramp up from ISCO, gradual fade toward outer edge
    float t_r        = saturate((r - R_ISCO) / (R_DISK_OUTER - R_ISCO));
    float inner_ramp = saturate(t_r * 4.0f);          // reaches full density by ~25% of disk width
    float outer_fade = pow(1.0f - t_r, 4.0f);          // falloff -still concentrates near ISCO but extends further
    float radial     = inner_ramp * outer_fade;

    // Vertical: flared scale height grows with r
    float H        = 0.2f + 0.06f * r;
    float vertical = exp(-pos.y * pos.y / (H * H));

    // Quick out: skip noise evaluation if clearly outside vertical extent
    if (vertical < 0.01f) return 0.0f;

    // Keplerian rotation: inner gas orbits faster than outer
    float omega = sqrt(M / (r * r * r));
    float phase = omega * anim_time * 0.18f;
    float cp = cos(phase), sp = sin(phase);
    float rx = pos.x * cp - pos.z * sp;
    float rz = pos.x * sp + pos.z * cp;

    // Curl noise warping: displace sampling position along a rotational field.
    //
    // For any scalar potential n(x,z), the 2D curl is:
    //   F = ( dn/dz, -dn/dx )
    // This vector is always perpendicular to the gradient of n, so it flows
    // *around* iso-contours of n in closed loops - producing circular swirls
    // rather than the random blobs you get from displacing in Cartesian x/z.
    //
    // We approximate the partial derivatives numerically with a small epsilon:
    //   dn/dz ~ (n(p + eps*z) - n(p - eps*z)) / 2*eps
    //
    // The resulting warp field has no divergence (it only rotates, never
    // compresses or expands), which is what keeps the swirls visibly circular.
    float2 p   = float2(rx * 0.15f, rz * 0.15f + pos.y * 0.4f);
    float  eps = 0.15f;
    float  dn_dz = noise2(p + float2(0, eps)) - noise2(p - float2(0, eps));
    float  dn_dx = noise2(p + float2(eps, 0)) - noise2(p - float2(eps, 0));
    float2 curl  = float2(dn_dz, -dn_dx);   // perpendicular to gradient ->circular flow
    float2 p_warped = p + curl * 1.5f;

    float noise = disk_fbm(p_warped);

    return radial * vertical * pow(noise, 1.8f);
}

// Geodesic integrator 

static float4 traceRay(float3 rayOrigin, float3 rayDir, float anim_time) {
    float r0 = length(rayOrigin);

    // Orbital plane basis vectors
    float3 e1   = normalize(rayOrigin);           // BH ->camera (radial)
    float3 Lvec = cross(rayOrigin, rayDir);        // angular momentum axis
    float  b    = length(Lvec);                    // impact parameter

    // Degenerate: ray aimed directly at or away from the black hole
    if (b < 1e-5f) {
        bool towardBH = dot(rayDir, -e1) > 0.0f;
        return towardBH ? float4(0, 0, 0, 1) : skyColor(rayDir);
    }

    float3 eN = Lvec / b;            // orbital plane normal
    float3 e2 = cross(eN, e1);       // tangential direction (phi increases here)

    // Initial orbit-equation state  [u = 1/r, du = du/dphi]
    float u  = 1.0f / r0;
    float du = -dot(rayDir, e1) / b; // sign: inward ray ->u increasing

    const float dphi    = 0.005f;
    const int   maxIter = 3000;

    float3 cloud_acc   = float3(0.0f);
    float  cloud_alpha = 0.0f;

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

        // Hit event horizon -return any cloud accumulated in front
        if (r < RS) return float4(cloud_acc, 1.0f);

        // Escaped to far background -blend cloud over sky
        if (u <= 0.0f || r > 300.0f) {
            float3 rHat      = cos(phi)*e1 + sin(phi)*e2;
            float3 phiHat    = -sin(phi)*e1 + cos(phi)*e2;
            float3 escapeDir = normalize(-du * rHat + phiHat);
            float4 bg        = skyColor(escapeDir);
            return float4(cloud_acc + (1.0f - cloud_alpha) * bg.rgb, 1.0f);
        }

        // Volumetric cloud accumulation inside disk region
        if (r > R_ISCO && r < R_DISK_OUTER) {
            float3 pos3D = r * (cos(phi)*e1 + sin(phi)*e2);
            float  d     = cloud_density(pos3D, r, anim_time);
            if (d > 0.002f) {
                float3 orb_dir = normalize(float3(-pos3D.z, 0.0f, pos3D.x));
                float3 to_obs  = normalize(rayOrigin - pos3D);
                float beta     = min(sqrt(M / r), 0.95f);
                float gam      = 1.0f / sqrt(1.0f - beta * beta);
                float doppler  = 1.0f / (gam * (1.0f - beta * dot(orb_dir, to_obs)));
                float grav     = sqrt(max(0.0f, 1.0f - RS / r));
                float g        = doppler * grav;

                // HG phase: BH is the light source, camera is the viewer
                float3 Ld       = normalize(-pos3D);          // toward BH at origin
                float3 Vd       = -rayDir;                    // toward camera
                float  cos_t    = dot(Ld, Vd);
                float  phase    = double_hg(cos_t, 0.6f, -0.3f, 0.75f);

                // Inverse square falloff from BH
                float  dist2    = max(dot(pos3D, pos3D), 0.1f);
                float  atten    = 1.0f / (dist2 * 0.08f);

                // g^2 rather than g^4: volumetric clouds integrate many samples so the
                // relativistic asymmetry is less extreme than a thin emitting disk
                float phase_floor = max(phase, 0.04f);  // prevent completely black backlit regions
                float ms          = 0.06f * (1.0f - cloud_alpha);  // fake multiple scattering

                float step_opacity = saturate(d * dphi * r * 7.0f);
                float transmit     = 1.0f - cloud_alpha;
                cloud_acc   += transmit * cloud_color(r) * d * phase_floor * atten * pow(g, 2.0f);
                cloud_acc   += transmit * cloud_color(r) * d * ms;
                cloud_alpha += transmit * step_opacity;

                if (cloud_alpha > 0.98f) return float4(cloud_acc, 1.0f);
            }
        }
    }

    // Photon captured (too many iterations)
    return float4(cloud_acc, 1.0f);
}

// Compute kernel 

kernel void raytrace(texture2d<float, access::write> outTexture [[texture(0)]],
                     constant CameraData&            camera     [[buffer(0)]],
                     uint2                           gid        [[thread_position_in_grid]])
{
    uint w = outTexture.get_width();
    uint h = outTexture.get_height();
    if (gid.x >= w || gid.y >= h) return;

    // NDC in [-1, 1], y pointing up; subpixel jitter for TAA
    uint   frame  = uint(camera.up.w);
    float2 jitter = float2(halton(frame, 2), halton(frame, 3)) - 0.5f;
    float2 uv     = (float2(gid) + 0.5f + jitter) / float2(w, h);
    uv            = uv * 2.0f - 1.0f;
    uv.y      = -uv.y;   // flip: gid.y=0 is top of texture

    // Perspective ray from camera
    float  halfTanFov = tan(camera.forward.w * 0.5f);
    float3 rayOrigin  = camera.position.xyz;
    float3 rayDir     = normalize(
        camera.forward.xyz
        + uv.x * camera.right.w * halfTanFov * camera.right.xyz
        + uv.y *                  halfTanFov * camera.up.xyz);

    float anim_time = camera.position.w;  // continuous frame counter, never resets
    outTexture.write(traceRay(rayOrigin, rayDir, anim_time), gid);
}
