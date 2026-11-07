# Football Golf (V0.1 prototype)

A 3D golf game where every shot is a footballer: pick **Caps** (aerial — 1 senior international
cap = 1 yard of neutral carry) or **Goals** (ground — 1 goal = 1 foot of neutral roll), choose a
footballer whose stats stay hidden until the ball stops, aim, and press **Take Shot**.

Godot **4.7-stable**, GDScript, Mobile renderer, portrait Android. Offline, single-player, three holes.
Full brief: [`docs/SPECIFICATION.md`](docs/SPECIFICATION.md).

## Current status (evidence-based)
| Area | State |
|---|---|
| Three playable 3D holes (par 3 / 4 / 5: 150 / 360 / 510 yd) with bunkers, trees, lakes, OOB | Implemented; completed by test bot and UI smoke test |
| Calibrated physics (flight, drag, wind, bounce, roll, slopes, lies, trees, cup) | Implemented; calibration error < 0.001% on all spec inputs |
| Atomic shot commit, once-per-match footballer pool, par+5, water/OOB relief, hole-out rules | Implemented + tested |
| Footballer picker (stats hidden), shot result reveal, scorecard + history, round complete | Implemented |
| Developer panel (holes, ball placement, lie/wind/surfaces, hole-out radius, undo/replay, CRUD, pool reset, diagnostics, calibration check, scenario save/load) | Implemented |
| Automated tests | 52 tests + runtime smoke test, all passing locally |
| Android debug APK | Built, signed and structurally verified by GitHub Actions (run #2, artifact `football-golf-v0.1-debug-apk`, 86 MB) and locally |
| On-device install / launch / performance | **Not yet verified** (no device or emulator available to the agent) |
| Audio, mulligans, mid-round resume | Not implemented in V0.1 |

## Play
Download the APK artifact from **Actions → Android debug APK → Artifacts**
(see [`docs/BUILD_AND_INSTALL.md`](docs/BUILD_AND_INSTALL.md) for sideloading and controls).

Controls: drag the course to aim (360°) · Caps/Goals · Choose footballer · **TAKE SHOT** ·
Overhead (tap to measure) · Card · DEV · II (pause).

## Footballer data
- Countries: edit `tools/data/countries.json`; manual fixes: `tools/data/corrections.json`.
- Re-import: GitHub → Actions → **Import footballers (Wikidata)** → Run workflow (also runs on changes
  under `tools/data/`). The job commits `data/footballers_real.json` + a validation report to the branch.
- Rules applied: senior men's national team only; final national team only (regional/non-FIFA sides
  ignored); records without caps or goals excluded; negative goals (goals-conceded convention) → 0.
- Player edits made in the DEV panel are tied to the dataset snapshot; a new snapshot backs them up
  instead of applying them to different data.

## Develop
```bash
tools/scripts/install_godot.sh ~/godot --templates
GODOT=~/godot/godot tools/scripts/run_tests.sh
~/godot/godot --path .                         # run on desktop (portrait window)
~/godot/godot --path . -- --smoke-test         # auto-play a full round through the UI
```
Docs: [Architecture](docs/ARCHITECTURE.md) · [Physics calibration](docs/PHYSICS_CALIBRATION.md) ·
[Test plan](docs/TEST_PLAN.md) · [Build & install](docs/BUILD_AND_INSTALL.md) ·
[Asset licences](docs/ASSET_LICENCES.md) · [Agent rules](CLAUDE.md)

## Known limitations
- **TEST MODE is ON by default in this build:** the footballer picker shows caps/goals before the
  shot so mechanics can be checked. Turn it off (Settings or DEV → Players) for normal hidden-stat rules.
- Footballers: a **provisional Wikidata snapshot** of complete senior men's caps/goals lists for 14 countries
  (~9,800 players; see `data/footballers_real_report.md`). Wikidata can be incomplete or out of date.
  Synthetic test players remain available (Settings → "Use real footballers" off).
- Overhead map edges are noise-warped for a natural look, so visual surface boundaries can differ from
  the physics boundary by up to ~1.5 m.
- Visuals are procedural (no imported art); the ball is drawn larger than its physical 42.7 mm when
  far from the camera so it stays visible.
- Debug signing identity can change between CI builds unless a keystore secret is configured
  (uninstall before reinstalling in that case).
- Multiplayer and the 18-hole course are deliberately out of scope for V0.1 (spec §15).
