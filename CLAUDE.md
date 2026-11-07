# CLAUDE.md — Football Golf (Godot 4.7, GDScript)

Authoritative spec: `docs/SPECIFICATION.md`. V0.1 = offline, single-player, 3-hole Android APK.
Do not build multiplayer/networking, clubs, power meters, loft/spin controls, or live data APIs.

## Architecture (see docs/ARCHITECTURE.md)
- `scripts/physics/` — `BallSim` (custom deterministic fixed-step ball controller, NOT RigidBody3D),
  `ShotCalculator` (solves launch speed with the SAME BallSim on a flat neutral plane),
  `PhysicsConfig`, `Surface`, `HazardResolver`.
- `scripts/gameplay/` — `GameSession` (authoritative state machine, atomic shot commit, scoring,
  dev undo/replay), `HoleDefinition` (JSON-driven analytic terrain + lies used by physics AND
  rendering), `ScoringService`, `HoleState`, `RoundState`, `ShotRequest`, `ShotResult`.
- `scripts/data/` — `Footballer`, `FootballerRepository` (seed `data/footballers_seed.json`,
  edits in `user://footballers.json`), `FootballerPool` (`used_footballer_ids`, once per MATCH).
- `scripts/world/`, `scripts/camera/`, `scripts/ui/`, `scripts/round_controller.gd`, `scripts/main.gd`
  — presentation only; UI never decides score or consumption.
- Autoload `App` (`scripts/core/app.gd`): repo, settings, hole loading. Logic classes must not use it.
- Holes: `data/holes/hole_0{1,2,3}.json`. Units: 1 world unit = 1 m, Y up, horizontal = X/Z.
  Bearing 0° = +Z, 90° = +X.

## Locked gameplay invariants (never change silently)
- 1 cap = 1 yd neutral FIRST-CONTACT carry (fixed auto launch angle). 1 goal = 1 ft neutral ground travel.
- Neutral = flat FAIRWAY plane, zero wind, no obstacles. Tolerances: Caps max(0.25 yd, 0.5%),
  Goals max(0.10 ft, 1%).
- Stats hidden in normal play until the ball has stopped; picker is alphabetical, never stat-ordered.
- Take Shot is the only way to shoot; commit is atomic: footballer consumed + 1 stroke exactly once,
  even for 0 distance. Failed validation consumes nothing.
- Footballer usable once per match (all 3 holes); new round resets pool, keeps DB edits.
- Water/OOB: +1 penalty, deterministic safe relief. Max score par+5 ends hole.
- Hole-out only when AT REST within radius (default 5 ft, 0–10); at 0 ft physical cup entry only.
- Developer Undo ≠ mulligan (keep names separate).

## Commands
```bash
tools/scripts/install_godot.sh ~/godot [--templates]   # pinned 4.7-stable, SHA-512 verified
GODOT=~/godot/godot tools/scripts/run_tests.sh         # import + 52 tests + full-round smoke test
godot --headless --path . -s res://tests/run_tests.gd -- --filter=<name>   # subset
godot --path . -- --smoke-test [--screenshots=<dir>]   # play a full round via real UI
godot --headless --path . --export-debug "Android" builds/football-golf-v0.1-debug.apk
tools/scripts/verify_apk.sh builds/football-golf-v0.1-debug.apk
```
Android export needs editor settings (`~/.config/godot/editor_settings-4.7.tres`) with
`export/android/android_sdk_path`, `java_sdk_path` and a debug keystore — see docs/BUILD_AND_INSTALL.md.

## Rules for agents
- Report only observed results. Never claim a build/test/device check passed unless it ran.
- After any change: run `tools/scripts/run_tests.sh`; fix SCRIPT ERRORs before committing.
- Physics changes must keep calibration tests green; tune via `Surface.default_params()`/`PhysicsConfig`.
- Seed footballers are SYNTHETIC; never present them as real players' records.
- Never commit keystores, passwords or secrets.
