# Test plan and evidence

Run everything: `GODOT=<godot> tools/scripts/run_tests.sh` (import + automated tests + runtime smoke test).

## Automated tests (`tests/`)
| Spec item (§13) | Test |
|---|---|
| Unit conversions, 200 caps = 182.88 m, 30 goals = 9.144 m | `unit/test_units.gd` |
| Negative / invalid / NaN stats rejected; duplicate ids rejected; edits persist; seed reset | `unit/test_footballers.gd` |
| Stats never in picker labels; alphabetical order; pool consume-once | `unit/test_footballers.gd` |
| par+5 maximum, penalty clamp, hole-out radius semantics incl. 0 ft and 5.1 ft | `unit/test_scoring.gd` |
| Caps 1/10/50/150/200/400 first-contact carry within tolerance (gameplay sim) | `integration/test_physics_calibration.gd` |
| Goals 0/1/5/30/100/200 ground distance within tolerance | `integration/test_physics_calibration.gd` |
| 200 caps total ≠ carry; repeatability | `integration/test_physics_calibration.gd` |
| Wind carry + crosswind; surfaces differ; uphill vs downhill; trunk + canopy; stops; finite | `integration/test_physics_behaviour.gd` |
| Zero goals / zero caps consume + stroke; double commit blocked; invalid shot consumes nothing | `integration/test_game_session.gd` |
| Used footballer stays used across holes, resets on new round | `integration/test_game_session.gd` |
| Rolling through radius ≠ holed; stopping inside = holed; 0 ft physical cup entry | `integration/test_game_session.gd` |
| Water and OOB: exactly +1 penalty, safe relief on terrain | `integration/test_game_session.gd` |
| Dev undo restores ball/strokes/pool; replay = same result, no duplicate scoring | `integration/test_game_session.gd` |
| Stats unavailable while in motion | `integration/test_game_session.gd` |
| Three holes: par, nominal length, tee/pin lies, hazards, finite terrain, bot completes round | `integration/test_course.gd` |
| Ridge holes: valid polygon/tee/pin/length, relief ≥ 12 m, fairway/green slope limits, ≥150 trees; bot completes Pinewood Ridge | `integration/test_course.gd` |
| No Caps on the green (UI, mode switch, `take_shot` refusal), spin resets, cup size default/clamp | `integration/test_game_session.gd` |
| Picker query: filters, sorts, facets, accent-insensitive search | `unit/test_footballers.gd` |
| Deterministic developer scenarios (water, OOB, tree, zero goals, neutral tee shot) | `scenarios/test_scenarios.gd` + `scenarios.json` |

## Runtime smoke test (`scripts/core/smoke_driver.gd`, `-- --smoke-test`)
Launches the real `main.tscn`, presses **Play Three Holes**, **Tee off**, Caps/Goals,
**Choose footballer** + a picker entry, **TAKE SHOT** (and a second tap, which must be ignored),
**Skip**, **Continue**, **Next hole/Finish round** until ROUND_COMPLETE, opens/closes the developer
panel and returns to the main menu. `--screenshots=<dir>` saves frames when a renderer exists.

## Not automatable here (manual, on device)
- Install + launch on an Android phone/emulator; portrait rendering; touch-drag aiming feel;
  safe areas/cutouts; frame rate; Back button; persistence across app restart.
  **These have not been performed by the implementation agent** (no device/emulator was available).
  Use the checklist in `docs/SPECIFICATION.md` §13.3 / §20 and record results here.

## Evidence log
| Date | Where | What ran | Result |
|---|---|---|---|
| 2026-11-07 | Local cloud container, Godot 4.7-stable headless | 52 automated tests | 52 passed |
| 2026-11-07 | Same | Smoke test (full round through UI) | PASS |
| 2026-11-07 | Same, Xvfb + llvmpipe Vulkan, Mobile renderer | Smoke test with screenshots | PASS, frames inspected |
| 2026-11-07 | Same, Ubuntu `apksigner`/`adb` packages as SDK stand-in | `--export-debug "Android"` | 86 MB APK, v2+v3 signature verifies, manifest portrait, package `com.footballgolf.prototype` |
| 2026-11-07 | GitHub Actions run #2 of "Android debug APK" (commit 6818839, ubuntu-24.04, JDK 17, Android SDK build-tools 36.0.0 used by Godot for signing) | install (SHA-512 OK) → 52 tests → smoke test → export → verify_apk.sh → upload | Success; artifact `football-golf-v0.1-debug-apk` (ID 13572259472), APK 86,391,864 bytes, sha256 `f9fb4f91…acbf`, v2 signature verifies |
| 2026-11-07 | GitHub Actions "Validate (headless tests)" runs #1 and #2 | import + tests + smoke | Success |
