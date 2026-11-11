# Course visuals upgrade (Nov 2026)

Presentation only; physics, gameplay, UI and camera untouched. Terrain still comes from the analytic
`HoleDefinition` (no visual offset); the stencil cup/pit shaders are unchanged.

| Feature | Where | High | Low |
|---|---|---|---|
| Fringe collar (cross-hatched, richer band round the green) | `turf.gdshaderinc` (`detail_amt`), fringe flag in surface-map alpha (`TerrainBuilder`) | yes | no |
| Fairway cross-cut (soft checkerboard over the mowing stripes) | `turf.gdshaderinc` | yes | no |
| Sand grain, pebbles, glints, bright turf crest at the bunker lip | `turf.gdshaderinc` | yes | no |
| Baked AO: under tree crowns, round trunks, bunker lip, grandstand footprints | `TerrainBuilder.bake_ao` (load time, 0 runtime cost) | yes | no |
| Water shore foam + stronger Fresnel | `water.gdshader` (`foam_amt`) | yes | no |
| Cloth flag (travelling ripples, analytic normals, 18x6 quad) | `flag.gdshader`, `CourseView._build_pin` | yes | old flag |
| Tree variety: columnar, birch (pale bark, airy crown), autumn / copper tints, blue spruce, 3 pine shapes | `TreeMeshes`, `CourseView._step_trees` | yes | yes (no extra cost beyond 2-3 multimeshes) |
| Grandstands with seated crowd and FICTIONAL sponsor boards near the green | `CourseDressing` (+ `crowd.gdshader`) | yes | no |
| Yardage plates (fairway centre, 200 blue / 150 white / 100 red / 50 yellow) + edge posts | `CourseDressing.build_yardage_markers` | + number labels, contact shadows | plates + posts |

Grandstands are placed only on rough/OOB ground, inside the rendered terrain, clear of tree canopies,
on ground with < 2.2 m height range; at most two per hole. They have **no collision** (visual only),
so a wild shot can fly through one.

Measured (Windows dev PC, gl_compatibility, Pinewood Ridge hole 1 tee view, `--smoke-perf`):
Low 320 draw calls / 303k primitives / 38.8 MB; High 340 / 329k / 42.5 MB. High build cost: AO bake
+ stand planning inside `terrain_mesh` (~30 ms total), `dressing` job 5 ms. Not measured on a phone.
