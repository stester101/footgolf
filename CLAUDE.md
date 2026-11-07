# CLAUDE.md — Football Golf (Godot 4.7, GDScript)

Authoritative spec: `docs/SPECIFICATION.md`. V0.1 = offline, single-player, 3-hole Android APK.
Do not build multiplayer/networking, clubs, power meters, loft controls, sidespin, or live data APIs.
Owner-approved deviations from the spec are logged in `docs/DECISIONS.md`.

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
- Holes: `data/holes/hole_01..09.json`; courses in `data/courses.json` (Starter Links 1-3, Pinewood Ridge 4-9,
  Full 9). Ridge holes come from `tools/data/gen_forest_holes.py`. Units: 1 world unit = 1 m, Y up, horizontal = X/Z.
  Bearing 0° = +Z, 90° = +X.

## Locked gameplay invariants (never change silently)
- 1 cap = 1 yd neutral FIRST-CONTACT carry at the chosen trajectory (Punch 12°/Low 24°/Standard 42°/High 56°;
  owner-approved, carry exact for every trajectory via the solver). 1 goal = 1 ft neutral ground travel.
- Pre-shot SPIN (owner-approved change, see docs/DECISIONS.md): vertical only (top/back, no sidespin),
  Caps shots only, never changes neutral carry (solver includes spin). No other loft/power/club controls.
- Neutral = flat FAIRWAY plane, zero wind, no obstacles. Tolerances: Caps max(0.25 yd, 0.5%),
  Goals max(0.10 ft, 1%).
- Stats hidden in normal play until the ball has stopped; picker is alphabetical, never stat-ordered.
- Take Shot is the only way to shoot; commit is atomic: footballer consumed + 1 stroke exactly once,
  even for 0 distance. Failed validation consumes nothing.
- Footballer usable once per match (all 3 holes); new round resets pool, keeps DB edits.
- Water/OOB: +1 penalty, deterministic safe relief. Max score par+5 ends hole.
- Hole-out only when AT REST within radius (default 5 ft, 0–10); at 0 ft physical cup entry only.
- Cup default is 12 in diameter (owner-approved); Caps or Goals allowed from ANY lie incl. the green (owner-approved,
  replaces the old Goals-only green rule); spin and trajectory reset to none/Standard after each shot.
- Picker never sorts/filters by stats outside TEST MODE.
- Developer Undo ≠ mulligan (keep names separate).

## Commands
```bash
tools/scripts/install_godot.sh ~/godot [--templates]   # pinned 4.7-stable, SHA-512 verified
GODOT=~/godot/godot tools/scripts/run_tests.sh         # import + 64 tests + 2 full-round smoke tests
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
- `data/footballers_seed.json` is SYNTHETIC test data; never present it as real records.
- `data/footballers_real.json` is generated (Wikidata, CC0) by `tools/data/import_wikidata.py` via the
  "Import footballers" workflow — do not hand-edit it; use `tools/data/corrections.json`.
- Never commit keystores, passwords or secrets.
