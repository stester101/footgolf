# Architecture

## Layers
```
main.tscn (scripts/main.gd) ── MainMenu ──► round.tscn (scripts/round_controller.gd)
                                              │  owns
                                              ▼
                                     GameSession (pure logic, RefCounted)
                     ┌──────────────┬────────┴─────┬───────────────┬──────────────┐
               HoleDefinition    BallSim     ShotCalculator   ScoringService  HazardResolver
               (JSON hole data,  (fixed-step  (launch speed    (par+5,         (line-of-entry
                terrain, lies,    sim)         solver, same     hole-out)       relief)
                trees, hazards)                 BallSim)
                     FootballerRepository (DB) · FootballerPool (match) · RoundState/HoleState
```
Presentation (`CourseView`, `TerrainBuilder`, `CameraRig`, `LineDrawer`, `GameUI`,
`FootballerPicker`, `DeveloperPanel`) only reads `GameSession` and calls its public API.

## Module map (spec §9.2 → code)
| Spec module | Implementation |
|---|---|
| GameManager | `GameSession` state machine + `round_controller.gd` |
| RoundManager | `RoundState`, `GameSession.start_round/next_hole` |
| HoleManager | `HoleDefinition` + `GameSession.start_hole` |
| BallController | `BallSim` |
| ShotPlanner/Calculator | `ShotCalculator`, `GameSession._plan_shot` |
| SurfaceResolver | `HoleDefinition.surface_at`, `Surface`, `PhysicsConfig.surfaces` |
| HazardResolver | `HazardResolver` |
| AimingController | `round_controller._unhandled_input` → `GameSession.set_aim` |
| CameraController | `CameraRig` (behind / follow / overhead + measure) |
| FootballerRepository / Pool | `FootballerRepository`, `FootballerPool` |
| ShotRecorder | `ShotRequest`, `ShotResult`, `GameSession.history`, undo snapshots |
| ScoringService | `ScoringService` |
| GameHUD / Picker / Scorecard | `GameUI`, `FootballerPicker` |
| DeveloperPanel | `DeveloperPanel` |
| SettingsStore | `SettingsStore` (`user://settings.json`) |

## State machine
`ShotTypes.State`: BOOT → ROUND_SETUP → HOLE_INTRO → AIMING ⇄ (picker overlay) → SHOT_COMMITTED →
BALL_IN_MOTION → [HAZARD_RESOLUTION] → SHOT_RESULT → AIMING | HOLE_COMPLETE → HOLE_INTRO | ROUND_COMPLETE.
`take_shot()` validates and plans first (no side effects), then commits synchronously
(snapshot → consume → +1 stroke → launch). It only succeeds in AIMING, so double taps,
taps during motion or during the result are rejected.

## Data contracts
- `Footballer`: id, name, country_code, nationality, caps, goals, birth_year, career_years, notes.
- `ShotRequest`: shot_id, hole_id, footballer_id, mode, aim_bearing_deg, start_pos, launch_lie, wind, seed.
- `ShotResult`: base/target distance, lie factor, launch speed/angle, carry_m, roll_m, total_m,
  first contact, collisions, hazard, relief, penalty, final lie/pos, time, calibration error.
- `HoleState`: strokes, penalties, complete, completion (`HOLED`/`MAX_SCORE`), shots, used ids.
- `RoundState`: hole states, current index, round seed. Pool consumption lives in `FootballerPool`.
- Developer scenarios: `tests/scenarios/scenarios.json` (+ one saved slot in settings).

## Terrain and lies
`HoleDefinition` defines an analytic height function (plane + Gaussian bumps, flattened tees,
tilted/undulating greens, carved bunkers, lowered lake beds) and a priority classifier
(OOB > water > bunker > green > fringe > tee > fairway > rough). OOB is only the outer 25 m band of the
rendered terrain (`play_area` = `bounds` inset by `oob_inset`); everything visible inside it is in play. Physics queries it directly;
`TerrainBuilder` samples the same functions on a 2 m grid for the mesh and vertex colours, so
visual and physical regions agree to within one grid cell. Trees are generated deterministically
from JSON lines/clusters; each has a trunk cylinder + canopy ellipsoid collision proxy in
`BallSim` and a matching MultiMesh visual.

## Future multiplayer seams
`FootballerPool.used_footballer_ids`, immutable `ShotRequest`s with seeds, and a UI that never
mutates authoritative state are intended to let a server-authoritative implementation replace
`GameSession` without rewriting the shot mechanic. No networking exists in V0.1.
