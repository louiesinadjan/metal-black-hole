# Metal Black Hole

A real-time Schwarzschild black hole renderer written in C++ and Metal. Each frame, a compute kernel traces one photon per pixel through curved spacetime using the null geodesic orbit equation, then blits the result to the screen via a full-screen triangle.

## Physics

The simulation models a Schwarzschild black hole in natural units (G = c = 1, Schwarzschild radius RS = 1).

Each pixel casts a ray. The ray and the black hole define an orbital plane. Within that plane, photon paths obey the Schwarzschild orbit equation:

$$\frac{d^2u}{d\varphi^2} = 3Mu^2 - u \qquad \left(u = \frac{1}{r},\ \varphi = \text{orbital angle}\right)$$

This is integrated with RK4 (step $d\varphi = 0.005$, up to 3000 iterations). At each step:

- $r < R_S$ → event horizon reached, pixel is black
- $r > 300$ → photon escaped, pixel takes a sky color based on exit direction
- Sign change of the photon's $y$-coordinate within $[R_\text{ISCO},\ R_\text{disk}]$ → accretion disk intersection

The accretion disk lies in the $y = 0$ equatorial plane. Its intrinsic color is a temperature gradient: white-yellow near the ISCO ($3R_S$), fading to orange-red at the outer edge ($12R_S$).

### Observational effects

Two relativistic effects break the left–right symmetry of the disk.

**Gravitational redshift** — a photon emitted at radius $r$ loses energy climbing out of the gravitational well and arrives at infinity shifted by:

$$g_\text{grav} = \sqrt{1 - \frac{R_S}{r}}$$

**Relativistic Doppler** — disk material orbits at Keplerian speed $\beta = \sqrt{M/r}$ (in units $c = 1$; at the ISCO, $\beta \approx 0.41$). For a source moving at angle $\alpha$ to the line of sight:

$$D = \frac{1}{\gamma\!\left(1 - \beta\cos\alpha\right)}, \qquad \gamma = \frac{1}{\sqrt{1 - \beta^2}}$$

The **combined redshift factor** and its effect on observed flux:

$$g = D \cdot g_\text{grav}, \qquad F_\text{obs} \propto g^4$$

The $g^4$ scaling follows from relativistic beaming ($g^3$ compresses the solid angle of emission) plus the photon energy shift ($g^1$). The approaching side of the disk ($D > 1$) appears significantly brighter; the receding side is dimmer and redder.

## Rendering Architecture

Three GPU passes per frame, encoded into one command buffer:

1. **Compute pass** — `raytrace` kernel writes pixels into an RGBA16Float texture (GPU-private)
2. **Accumulate pass** — `accumulate` kernel blends the new frame into an RGBA32Float accumulation texture
3. **Render pass** — `blit_vertex` / `blit_fragment` draw a full-screen triangle, sampling the accumulation texture into the MTKView drawable

### Temporal anti-aliasing

The renderer is fully deterministic, so naively accumulating identical frames does nothing. Instead, each frame applies a subpixel **Halton jitter** before casting rays:

$$\text{uv} = \frac{\text{pixel} + 0.5 + \bigl(h_2(n) - 0.5,\ h_3(n) - 0.5\bigr)}{resolution}$$

where $h_b(n)$ is the $n$-th term of the base-$b$ Halton low-discrepancy sequence. Bases 2 and 3 are coprime, so successive jitters cover the unit pixel cell without repetition or clustering.

The accumulation kernel maintains a running average:

$$A_n = A_{n-1} + \frac{1}{\min(n, 512)}\,(F_n - A_{n-1})$$

This is a true running mean for the first 512 frames, then transitions to an exponential moving average. The result is that edges on the photon ring, disk boundary, and star field sharpen progressively while the camera is still. Dragging the camera resets $n$ to zero, discarding the stale history and eliminating ghosting.

## Build & Run

Requires macOS with Xcode command line tools.

```bash
make        # compile shaders → build/Shaders.metallib, compile C++ → build/BlackHole
make run    # build + launch
make clean  # remove build/
```

Always run from the project root — the binary loads `build/Shaders.metallib` via a relative path.

## Project Structure

```
src/
  main.cpp          NS::Application setup, AppDelegate, MTKViewDelegate
  renderer.hpp/cpp  owns all Metal state; called once per frame
  shader_types.h    structs shared between C++ and Metal
shaders/
  raytrace.metal    compute kernel: geodesic integrator, one thread per pixel
  accumulate.metal  compute kernel: TAA running-average blend
  blit.metal        vertex + fragment shaders: full-screen triangle
metal-cpp/          Apple's header-only C++ bindings for Metal
```

## Dependencies

- [metal-cpp](https://developer.apple.com/metal/cpp/) — Apple's header-only C++ wrapper for Metal, included in the repo
