# TODO

## Rendering improvements
- [x] Turbulent disk noise — procedural hotspots on the disk that rotate with orbital velocity
- [x] Chromatic aberration — split R/G/B through slightly different lens distortions
- [x] Pinch/vignette post-process

## Physics features

### Hotspots / orbiting clumps
- [ ] Place bright clumps on circular Keplerian orbits in the disk, animating angular position each frame
- [ ] No full ODE integration needed: $\phi(t) = \sqrt{M/r^3} \cdot t$

### Timelike geodesic particles
- [ ] Simulate N massive particles on the GPU as a compute pass, render as bright dots/streaks
- [ ] Particles follow the timelike Schwarzschild orbit equation:

$$\frac{d^2u}{d\phi^2} = 3Mu^2 - u + \frac{M}{L^2}$$

  where $L$ is specific angular momentum
- [ ] Particles inside $r = 6M$ (ISCO) inevitably fall in; outside can orbit stably or escape

### Multiple black holes
- [ ] Extend the raytracer to sum potentials from two Schwarzschild masses (approximate)
- [ ] Creates chaotic photon lensing between the two masses
