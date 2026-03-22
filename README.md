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

The accretion disk lies in the $y = 0$ equatorial plane. Its color is a temperature gradient: white-yellow near the ISCO ($3R_S$), fading to orange-red at the outer edge ($12R_S$).

## Rendering Architecture

Two GPU passes per frame, encoded into one command buffer:

1. **Compute pass** — `raytrace` kernel writes pixels into an RGBA16Float texture (GPU-private)
2. **Render pass** — `blit_vertex` / `blit_fragment` draw a full-screen triangle, sampling the compute texture into the MTKView drawable

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
  Renderer.hpp/cpp  owns all Metal state; called once per frame
  ShaderTypes.h     structs shared between C++ and Metal
shaders/
  Raytrace.metal    compute kernel: geodesic integrator, one thread per pixel
  Blit.metal        vertex + fragment shaders: full-screen triangle
metal-cpp/          Apple's header-only C++ bindings for Metal
```

## Dependencies

- [metal-cpp](https://developer.apple.com/metal/cpp/) — Apple's header-only C++ wrapper for Metal, included in the repo
