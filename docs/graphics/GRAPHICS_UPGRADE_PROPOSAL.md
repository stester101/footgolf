# Graphics upgrade proposal (compact)

Evidence labels: **[observed]** = seen in the repo or in screenshots I rendered; **[opinion]** = my judgement; **[unverified]** = from memory, not checked.
No web research was done (the coordinator asked to wrap up), so there are NO external citations. Claims about other golf games and about Godot feature support are [unverified] and should be checked before committing to a tier.

## 1. Current state [observed, from code and screenshots]
- Sky: `ProceduralSkyMaterial` (blue gradient, no clouds, no sun glow). Filmic tonemap, saturation 1.15, contrast 1.06. Fog density 0.00045 with a fixed colour, and `fog_sky_affect = 0`. No glow, SSAO or SSR. (`scripts/round_controller.gd::_build_environment`)
- Sun: one DirectionalLight3D, 2 shadow cascades, 160 m range, 2048 map, MSAA 2x. The sun direction is the same on every hole.
- Ground: analytic terrain mesh plus an outer-ground frame out to 1500 m. The `turf.gdshaderinc` shader already has mowing stripes, 4 noise scales (170/41/7/1.4 m), warm/cool drift, rough clumps, a bunker lip, a micro normal, and a grass-blade MultiMesh near the ball. Macro variation is already there, but it looks blotchy in the map view and a little mushy in the far rough.
- Trees: procedural low-poly crowns and conifers in MultiMeshes with a wind-sway foliage shader. Backdrop: 3 rows of low-poly trees just outside OOB. Water: a custom ripple/Fresnel shader. Flag: waving cloth.
- Missing [observed]: clouds, sun glow, any distant horizon (hills, mountains) beyond the tree belt, any ambient life, weather, time-of-day, and cloud shadows. The upper 40% of the aim view is flat blue.
- Screenshots: `docs/graphics/mockups/before_*.png`. Scene shots from the real smoke test were viewed but not saved.

## 2. Mockups [observed]
Made by `docs/graphics/mock/mock_render.gd`. It builds the REAL CourseView and the game's env/sun/camera settings, then layers the extras on top. No game file is edited and no image editing was used.
Run: `xvfb-run -a godot --path . --rendering-method mobile --resolution 450x800 -s res://docs/graphics/mock/mock_render.gd -- --level=before|tier1|tier2|tier2_golden [--hole=hole_10 --view=high] --out=docs/graphics/mockups/x.png`

| Image | Content |
|---|---|
| `before_hole01_aim.png` | current look (same env code) |
| `tier1_hole01_aim.png` | sky shader (3-stop gradient, sun halo, noise clouds), fog tint matched to the horizon, macro hue/brightness drift on the ground |
| `tier2_hole01_aim.png` | tier 1 plus 3 layered ridge silhouettes, billboard cumulus, 9 flapping birds, a contrail, drifting cloud shadows, glow |
| `tier2_golden_hole01_aim.png` | the same with only parameters changed (low warm sun, warm fog) |
| `before_hole10_high.png`, `tier2_hole10_high.png` | high flight-style camera on a Coastal hole. Rendered, but I did not look at them. |

**Caveat:** the sandbox has no Vulkan, so Godot silently fell back to **gl_compatibility on llvmpipe**. These are NOT mobile-renderer images and I measured no performance. Colours, glow and shadow softness will differ on device. Shaders are plain spatial/sky shaders and should port, but that is unchecked. Billboard clouds look noisy and mottled up close, and the golden-hour ground is too brown. The mockups show what is possible, not tuned art.

## 3. Tiers (effort = my estimate for one dev; cost = my estimate, NOT measured)

### Tier 1: quick wins (about 1 day each)
| Item | Effort | Perf cost | Risk |
|---|---|---|---|
| Replace the procedural sky with a custom sky shader (gradient, sun glow, cloud layer). `sky_mock.gdshader` is a starting point. Use the process mode that renders the sky once, with a slow uniform drift, so it is not re-rendered every frame. | 1 d | low (cubemap rendered once) [unverified] | low |
| Fog colour follows the horizon colour, `fog_sky_affect` about 0.15, slightly higher density | 0.25 d | about 0 | low |
| Ground macro variation at 260 and 620 m, plus distance mottling (`terrain_mock.gdshader`, about 12 extra lines) | 0.5 d | 3 extra texture taps | low. The tint must stay subtle so mowing-stripe readability is not hurt. |
| Per-hole sun azimuth and elevation, and sky tint, from hole JSON. This is data only and is the cheapest "variety" win. | 0.5 d | 0 | low. Check that shadows do not hide the ball line. |

### Tier 2 (2 to 4 days)
| Item | Effort | Perf cost | Risk |
|---|---|---|---|
| Distant hill/mountain silhouettes: 2 or 3 layered ridge meshes with colour fading to haze (`_add_hills`) | 1 d | 3 draw calls, very cheap | low. Silhouettes are flat walls, so keep them far away. |
| Billboard cloud puffs near the horizon (about 16 quads, alpha) | 1 d | overdraw; keep quads few and small [opinion] | medium. Needs a better texture than my noise puffs; consider a hand-painted or generated atlas. |
| Cloud shadows drifting on the ground (in the ground shader) | 0.5 d | 1 tap | low |
| Birds: 1 or 2 flocks, vertex-shader flapping, spawned at random per hole | 1 d | negligible | low |
| Jet with contrail high in the sky, occasional | 0.5 d | negligible | low |
| Wind-blown flag and tree sway tied to the HUD wind (the shaders already sway; this only wires in the wind value) | 0.5 d | 0 | low. Must be visual only, not physics. |
| Bloom/glow, subtle | 0.25 d | noticeable on low-end GPUs [unverified] | medium. Make it a quality-setting toggle. |

### Tier 3 (ambitious, 1 to 3 weeks)
- Time of day per hole (dawn, noon, golden hour, overcast), driven by a few parameters: sun angle/colour, sky colours, fog, ambient. The golden mock shows this works with parameters only. Needs per-preset art tuning. Cost: low runtime, high tuning effort.
- Weather: light rain (GPUParticles3D near the camera plus darker, desaturated grade and wet-looking specular), mist banks, overcast cloud cover. Risk: particles are a battery and fill-rate cost on mid-range phones, so add a quality toggle.
- Foliage upgrade: more tree variety, grass/flower MultiMesh patches in the rough and edges within a short distance, a dedicated far-LOD. Cost: draw calls and vertex count. Needs profiling on device.
- Real hand-authored texture sets (tileable fairway/rough/sand/dirt with a normal map) via triplanar blending with a splat map. Needs art assets and licensing care. The current all-procedural approach avoids that; keep it unless art quality is the bottleneck.
- Volumetric fog and light shafts: I believe volumetric fog is not available in the Mobile renderer [unverified]. Fake it with additive cone/quad shafts or a screen-space radial blur only if profiling allows.

## 4. Ground texture options [opinion]
1. Stay procedural (current) and extend with macro variation, cloud shadows and distance mottling. This is cheap and needs no assets.
2. Add a small tileable detail texture (a grass blade normal/albedo) that fades in within about 20 m, to improve the close-up grain beyond the noise.
3. Splat-map-driven triplanar sets, which are the most flexible but heavier and asset-dependent.

## 5. Ambient-life idea list
Birds (flocks across the sky, perched on trees), a plane with a contrail, drifting cloud shadows, wind-blown flags and tree sway tied to wind, butterflies or insects near the rough, a distant spectator or maintenance cart on a far fairway, ducks or ripples on water, falling leaves in autumn variants, light rain, mist at dawn, a sun-position change per hole.

## 6. Recommended order
1. Tier 1: sky shader plus fog match, ground macro variation, and per-hole sun/sky tint.
2. Tier 2: distant hills, cloud shadows, birds, contrail, and wind wired to flags and trees.
3. Tier 2 billboard clouds, once I have a better cloud texture, followed by the glow toggle.
4. Tier 3: time-of-day presets, then weather.
Before each step: profile on a real mid-range Android device with the actual Mobile renderer, and add a Low/High quality switch.

## 7. What I could not verify
- Real Mobile-renderer output and any performance number (no Vulkan in the sandbox).
- External claims about other golf games, and Godot mobile feature support such as volumetric fog, sky update modes, and glow cost. None were researched.
- The two hole 10 "high" images were rendered but not inspected.

## 8. Tier 1 implementation status (done in the game)
Behind Settings > Audio / Visual > "High graphics" (`SettingsStore.graphics_quality`, 0 = Low, 1 = High, default High). Low is the previous code path: procedural sky, original fog, fixed sun, `macro_amt = 0` (the new ground code is skipped). The setting is read when a round starts (`HoleAtmosphere.high_quality`).
- Sky: `assets/shaders/sky.gdshader` (gradient, sun halo, soft clouds, no `TIME`, so it should render once). Fog density 0.0007, `fog_sky_affect` 0.15, fog colour taken from each hole's horizon colour.
- Ground: `macro_amt` in `turf.gdshaderinc` (620 m / 260 m hue and brightness drift, mottling beyond 25 m). It is weighted down on green (x0.15) and mown fairway/tee (x0.45), and skipped on sand, so lie colours and stripes are only slightly affected. The grass tufts use the same function.
- Per hole: `scripts/world/hole_atmosphere.gd` derives sun direction (110 to 160 deg off the line of play, never ahead; elevation about 30 to 55 deg), colours, light energy and cloud cover from a hash of the hole id, using 4 bright presets. No hole JSON changed. Applied in `RoundController._apply_atmosphere` on hole start.
- Screenshots: `docs/graphics/mockups/t1_low_*` vs `t1_high_*` (Starter Links holes 1 and 3, Coastal hole 1, plus Coastal hole 4 and the map view).
- Observed limits: rendered in the sandbox on gl_compatibility (llvmpipe), not the mobile renderer; no performance measured. Macro variation is subtle on the fairway (by design) and mostly visible in far rough and the map view. Clouds are faint. Only about 6 holes of 17 were looked at.

## 9. Tier 2 implementation status (done in the game, all High-only)
Everything below is gated on `HoleAtmosphere.high_quality`; Low builds none of it (no SkyLife node, wind/cloud-shadow uniforms stay at their off defaults, flag pivot not yawed). Nothing touches physics, gameplay or data; wind visuals only READ `session.wind_vector()` (the same value as the HUD chip).
- Hills, billboard clouds, birds, jet: `scripts/world/sky_life.gd` (`SkyLife`, one per `CourseView`, built in the tree-meshes job). Shaders: `ridge.gdshader`, `cloud_puff.gdshader`, `bird.gdshader`, `contrail.gdshader`.
  - Ridges: 3 unshaded wall meshes at 820/1100/1380 m around the hole centre (3 draws). Palette family, height (tallest layer 90-300 m), noise and a "flatter side" envelope come from the hole-id hash; colours are hazed towards the hole's fog colour and the foot fades into it. Behind the tree belt they only show above it, so they read best on open holes (Coastal, Lakeside).
  - Billboard cloud puffs: DONE, kept. 7-10 puffs in ONE MultiMesh draw, drawn analytically from soft overlapping lobes with a flat base (no noise texture, so no mottling), mostly ahead of the player, 1500-2250 m away, behind the ridges. Looked good in screenshots (soft cumulus), so not skipped.
  - Birds: up to 3 flocks per hole (4-8 birds, one small mesh each, vertex-shader flap), first one 4-12 s after the hole is shown, then every 14-40 s. Spawned relative to the camera at 95-170 m, 9-19 deg above the horizon, crossing sideways; never spawned in the overhead map or when looking steeply down. Cost: moving at most 3 nodes per frame.
  - Jet: one per hole with probability 0.6, appearing 6-25 s in, 13-19 deg above the camera horizon about 1.8 km away, flying across in about 37 s at 70 m/s (one quad, contrail shader with a built-in aircraft glint, fades in/out).
- Cloud shadows: `cloud_shadow`/`cloud_thr`/`cloud_drift` in `turf.gdshaderinc` (1 extra tap, 1300 m tile, strength 0.18, bluish, x0.4-ish on green; same code path used by the grass tufts so they match the ground). Drift follows the wind direction at 2 + 2.2 x wind m/s. Coverage threshold follows the hole's sky cloud cover.
- Wind-driven visuals (`CourseView.set_wind`, called from `RoundController._apply_wind` on hole start and on each AIMING state): flag cloth is on a pivot yawed downwind, hangs/droops in calm and streams and flutters faster in strong wind (`flag.gdshader`); tree crowns lean downwind with gusts travelling along the wind and sway scaled by wind speed (`foliage.gdshader`); grass tufts lean and flutter (`grass_blades.gdshader`). Strength = speed / 7 m/s (clamped). The tree materials are shared by all holes, so `set_wind` runs whenever a hole becomes active.
- Glow: optional second toggle in Settings > Audio / Visual ("Glow (subtle bloom, High only)", `SettingsStore.graphics_glow`, default off). It only sets `Environment.glow_*` (soft-light, intensity 0.35, HDR threshold 1.15) when High and on. One extra post pass, so left off by default.
- Screenshots: `docs/graphics/mockups/t2_*` (Coastal hole 1 with/without glow and its map view, Pinewood hole 1, Lakeside hole 1, Starter hole 3, Low Coastal hole 1). Birds and the jet in those frames were forced into view with the smoke flag `--smoke-skylife` (not random).
- Not verified: rendered only in the sandbox on gl_compatibility (llvmpipe), NOT the mobile renderer; no performance measured on any device; flapping and tree sway are animations and were only checked as still frames (flag direction was checked: the cloth points downwind); glow looked almost invisible in the sandbox so its strength is untuned; cloud-shadow strength is subtle by design (hard to see in the aim view, clearer from the map). Only 6 holes of 17 were looked at.

Remaining: Tier 3 (time-of-day presets, weather, foliage, textures). The optional hole-JSON atmosphere block was not added (derivation from the id was enough).
