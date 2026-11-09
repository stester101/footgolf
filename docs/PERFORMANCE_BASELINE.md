# Performance baseline (General Improvements GI03/GI04/GI13, phase 0)

## What this is and is not
Measured in the **sandbox**: xvfb virtual display, **software rendering** (Mesa llvmpipe, OpenGL 4.5 core), forced `--rendering-method gl_compatibility --rendering-driver opengl3` at 540x1170. It is **NOT the phone's Mobile renderer and NOT a phone GPU/CPU**. Absolute frame times (100 to 235 ms) are dominated by CPU rasterisation in llvmpipe and say nothing about phone fps. They are only useful for relative comparisons on the same machine. Script-side timings (`_process`, hole build jobs) are real GDScript CPU time but on a sandbox CPU, not a phone. Numbers vary run to run: the Starter Links run below overlapped other runs on the same machine (its frame times are about 2x noisier than a clean run, which gave tee view avg 116 ms, flight 125 ms, putt 122 ms, preload 3306 ms).

## Method
`--smoke-perf` (new, in `scripts/core/smoke_driver.gd`; used together with `--smoke-test`, one course per process):

```
xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 540x1170 -- \
  --smoke-test --smoke-perf --smoke-course="Pinewood Ridge" [--smoke-gfx=low] [--perf-frames=30] [--perf-out=<file>]
```
It drives the real UI: Start round, Tee off, one full-flight shot with the footballer whose caps are closest to the pin distance, `dev_place_ball` 3 m short of the pin, putts (Goals/roll) until the hole is out, then the hole summary (next hole preloads behind the loading bar) and Next hole. It records per-frame wall time (avg, p95, max), Godot render monitors (nodes, objects, draw calls, primitives, video memory), the script time of `RoundController._process` (split into session advance, `place_grass`, trail drawing), and per-job build time of `CourseView`. `--perf-frames=N` shortens the idle windows (used for Pinewood and Jizzy, where 30 idle frames were used instead of 100-150 because llvmpipe frames are slow). Measurement hooks are cheap counters (`CourseView.job_usec`, `RoundController.perf`).

## Baseline numbers (before any change; graphics High, Tier 1+2)
```
== Starter Links, graphics High, renderer gl_compatibility, driver X11
hole 1 load, synchronous part (Start round press, includes round scene + HUD + hole build): 254 ms
hole 1 ready (first drawn frame): 1295 ms
hole 1 build jobs: terrain_sample 139 ms; terrain_mesh 8 ms; ground_water 0 ms; trees_xform 0 ms; tree_multimeshes_sky 9 ms; details_pin_grass 5 ms; 
tee view (idle, aiming): frames 150, avg 216.2 ms, p95 319.7 ms, max 376.8 ms
  script tee view: _process avg 0.34 ms, max 7.39 ms; per frame: advance 0.01, place_grass 0.00, trail 0.01 ms (150 frames)
tee view counters: nodes 195, objects/frame 881, draw calls/frame 315, primitives/frame 171603, video mem 33.5 MB
full-flight shot (ball moving): frames 39, avg 273.7 ms, p95 390.1 ms, max 390.2 ms
  script flight: _process avg 1.68 ms, max 17.37 ms; per frame: advance 1.00, place_grass 0.12, trail 0.41 ms (44 frames)
aiming after shot (idle, new ball position): frames 60, avg 225.5 ms, p95 289.5 ms, max 335.7 ms
putt position (idle, on green): frames 100, avg 128.3 ms, p95 144.7 ms, max 157.2 ms
putt (ball rolling, 2 putt(s)): frames 17, avg 137.7 ms, p95 198.1 ms, max 198.1 ms
  script putt: _process avg 0.55 ms, max 16.62 ms; per frame: advance 0.15, place_grass 0.05, trail 0.02 ms (221 frames)
next-hole preload (hole summary shown, loading bar): 3527 ms wall over 26 frames
  frame times during preload: frames 26, avg 135.6 ms, p95 144.7 ms, max 154.4 ms
Next hole press -> hole 2 swapped in (synchronous): 7 ms
Next hole press -> first drawn frame of hole 2: 491 ms
```
```
== Pinewood Ridge, graphics High, renderer gl_compatibility, driver X11
hole 1 load, synchronous part (Start round press, includes round scene + HUD + hole build): 754 ms
hole 1 ready (first drawn frame): 1801 ms
hole 1 build jobs: terrain_sample 566 ms; terrain_mesh 11 ms; ground_water 0 ms; trees_xform 1 ms; tree_multimeshes_sky 10 ms; details_pin_grass 6 ms; 
tee view (idle, aiming): frames 30, avg 161.3 ms, p95 174.8 ms, max 179.5 ms
  script tee view: _process avg 0.34 ms, max 0.82 ms; per frame: advance 0.01, place_grass 0.00, trail 0.00 ms (30 frames)
tee view counters: nodes 194, objects/frame 883, draw calls/frame 314, primitives/frame 307484, video mem 34.6 MB
full-flight shot (ball moving): frames 54, avg 141.0 ms, p95 181.3 ms, max 190.6 ms
  script flight: _process avg 2.27 ms, max 16.41 ms; per frame: advance 1.47, place_grass 0.09, trail 0.54 ms (59 frames)
aiming after shot (idle, new ball position): frames 30, avg 98.1 ms, p95 109.4 ms, max 115.2 ms
putt position (idle, on green): frames 30, avg 107.5 ms, p95 138.5 ms, max 169.6 ms
putt (ball rolling, 2 putt(s)): frames 19, avg 117.1 ms, p95 155.2 ms, max 155.2 ms
  script putt: _process avg 0.92 ms, max 14.91 ms; per frame: advance 0.37, place_grass 0.08, trail 0.03 ms (123 frames)
next-hole preload (hole summary shown, loading bar): 4402 ms wall over 31 frames
  frame times during preload: frames 31, avg 142.0 ms, p95 194.1 ms, max 202.4 ms
Next hole press -> hole 2 swapped in (synchronous): 7 ms
Next hole press -> first drawn frame of hole 2: 447 ms
```
```
== Jizzy Nash Nash, graphics High, renderer gl_compatibility, driver X11
hole 1 load, synchronous part (Start round press, includes round scene + HUD + hole build): 688 ms
hole 1 ready (first drawn frame): 1876 ms
hole 1 build jobs: terrain_sample 479 ms; terrain_mesh 11 ms; ground_water 0 ms; trees_xform 1 ms; tree_multimeshes_sky 9 ms; details_pin_grass 5 ms; 
tee view (idle, aiming): frames 30, avg 235.5 ms, p95 256.3 ms, max 265.9 ms
  script tee view: _process avg 0.30 ms, max 0.40 ms; per frame: advance 0.01, place_grass 0.00, trail 0.01 ms (30 frames)
tee view counters: nodes 194, objects/frame 883, draw calls/frame 312, primitives/frame 432523, video mem 34.7 MB
full-flight shot (ball moving): frames 56, avg 189.1 ms, p95 242.0 ms, max 263.2 ms
  script flight: _process avg 2.17 ms, max 15.42 ms; per frame: advance 1.43, place_grass 0.08, trail 0.50 ms (61 frames)
aiming after shot (idle, new ball position): frames 30, avg 127.3 ms, p95 146.4 ms, max 154.6 ms
putt position (idle, on green): frames 30, avg 125.6 ms, p95 140.9 ms, max 148.9 ms
putt (ball rolling, 2 putt(s)): frames 17, avg 138.8 ms, p95 170.9 ms, max 170.9 ms
  script putt: _process avg 0.88 ms, max 14.91 ms; per frame: advance 0.35, place_grass 0.08, trail 0.03 ms (121 frames)
next-hole preload (hole summary shown, loading bar): 8498 ms wall over 60 frames
  frame times during preload: frames 60, avg 141.6 ms, p95 161.3 ms, max 172.5 ms
Next hole press -> hole 2 swapped in (synchronous): 7 ms
Next hole press -> first drawn frame of hole 2: 820 ms
```

## Findings
- **Script cost per frame is small**: `_process` averages 0.3 ms idle and 0.5 to 2.3 ms in flight (of which session physics advance 1.0 to 1.5 ms, ball trail rebuild about 0.4 to 0.5 ms with a duplicate of the trail array every frame, `place_grass` about 0.1 ms). Spikes of 15 to 17 ms come from `place_grass` re-scattering about 1800 candidate tufts once when a shot ends. None of this is the bottleneck here.
- **Frame time in the sandbox is render-bound**: about 315 draw calls, about 880 objects, 170k (Starter) to 430k (Jizzy) primitives per frame. Primitive count rises strongly on the tree-heavy / large courses and so does frame time. Which of these (terrain mesh density, tree crowns with 2 shadow cascades, backdrop trees) matters on the phone's GPU is **unmeasured**; it needs an on-device profile.
- **Hole build**: `TerrainBuilder` sampling is the one big script cost, 140 ms (Starter Links), 480 ms (Jizzy), 570 ms (Pinewood) of the first-hole synchronous load; everything else in the build is under 15 ms. Holes after the first are built sliced (9 ms budget per frame) behind the hole summary, so they do not hitch (preload frames max 154 to 172 ms are the same as normal frames here); the swap to the next hole is 7 ms plus about 0.4 to 0.8 s for the first drawn frame (shader/texture first use under llvmpipe).
- First-hole load is 1.3 to 1.9 s to first drawn frame here, of which 0.25 to 0.7 s is synchronous script.

## After
No optimisation was made in this phase. The coordinator asked to wrap up quickly, and no clear, safe script win was found: the per-frame script cost is already under the sandbox noise, and the largest cost (terrain sampling at hole start) would need changes in `TerrainBuilder` that deserve their own measured pass. No visual changes and no screenshots were produced in this phase. Candidate next steps, all unmeasured on device: cheaper terrain sampling at hole 1 start, reuse the trail array instead of duplicating, spreading `place_grass` over frames, reducing shadow cascades / backdrop tree counts on Low, profiling on a real phone.
