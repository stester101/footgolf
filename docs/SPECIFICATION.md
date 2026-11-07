# FOOTBALL GOLF
## Complete Game Design and Claude Code Implementation Handover

**Document version:** 1.1 — Claude Code edition  
**Date:** 7 November 2026  
**Status:** Approved prototype specification; implementation not yet started in this handover  
**Primary deliverable:** A real, installable, testable Android APK, plus a complete Godot project in GitHub  
**Repository:** `football-golf` (private recommended)  
**Engine:** **Godot 4** (GDScript), replacing the earlier Unity plan  
**First release:** **V0.1 — offline, single-player, three-hole playable mechanics prototype**  
**Future target:** Online 2–4-player game on an 18-hole course, preserving the agreed multiplayer rules

> **INSTRUCTIONS TO CLAUDE CODE**  
> This is an implementation handover, **not a request for another concept document**. Read this specification, create and maintain the actual Godot project, commit working source code, set up automated tests and GitHub Actions, and produce a verified Android debug APK. If development tools, GitHub access, licences or build infrastructure are missing, state the precise limitation and continue with all work still possible. Do not describe unbuilt functionality as complete. Do not make routine questions a prerequisite to building. Select reversible engineering defaults, document them and move forward.

---

## Claude Code execution protocol

This document is the authoritative specification. Operate as an autonomous implementation agent inside the actual Git working tree. Do not rewrite the specification or start another design workshop.

1. Inspect `pwd`, repository status, existing files, remotes, and available Godot/Android tooling before editing. Preserve unrelated existing work; do not force-push, reset, or overwrite user changes.
2. Create `CLAUDE.md` with concise, durable repository instructions: architecture, locked gameplay invariants, build commands, test commands, and the requirement to report only observed results. Keep this specification in `docs/SPECIFICATION.md`.
3. Implement directly in GDScript and `.tscn` scenes. Use small cohesive changes; run headless import and available tests after each phase. Fix errors before declaring a phase complete.
4. Configure GitHub Actions for reproducible Android debug exports early. Pin the actual available stable Godot 4 editor and matching templates. If the proposed 4.7 baseline cannot be obtained or verified, document the chosen stable 4.x fallback and why. Never fabricate successful exports.
5. If GitHub access, Android SDK, emulator, or device testing is unavailable, continue coding and testing locally. State exactly which validation remains unperformed. Do not claim device compatibility from a ZIP inspection alone.
6. Use feature branches and commits when appropriate; push only when repository permissions and the user's working context allow it. Do not delete branches or modify secrets.
7. At each milestone, report implemented files, actual commands and test results, commit SHA where available, APK artifact location if verified, blockers, and the next action. Continue implementation rather than waiting for approval for reversible technical choices.

**First action:** inspect the repository and toolchain, then build the playable first-hole vertical slice and Android export pipeline.

---

# 1. Executive specification

Football Golf is a 3D golf game with an unusual shot mechanic: instead of choosing clubs and manually controlling shot power, a player chooses a real international footballer and uses either the footballer's **senior international caps** or **senior international goals** as the basis for the shot. The resulting ball movement is then simulated as golf.

The core experience must be genuinely playable, not a static mock-up or UI-only proof of concept. The Android APK should show a convincing 3D course, allow touch aiming, allow footballer selection, fire the actual shot, simulate physics, update the ball position and score, and progress through three holes.

## 1.1 Locked V0.1 choices

| Topic | Locked decision |
|---|---|
| Engine | Godot 4 (NOT Unity); standard GDScript project |
| Platform | Android APK sideload for testing |
| Orientation | **Portrait first** |
| Render | Realistic-looking 3D golf; optimise for Android |
| Gameplay | Offline **single-player** |
| Course | **Three complete test holes**, par 3 / par 4 / par 5 |
| Aiming | **Drag to rotate aim**, 360° |
| Shot | Select **Caps** or **Goals**, footballer, then **Take Shot** |
| Caps | **1 cap = 1 yard of exact base aerial carry** |
| Goals | **1 goal = 1 foot of exact base ground travel** |
| Physics | Golf-simulation approach; gravity, bounce, roll, slopes, lies, wind, obstacles |
| Trajectory | Fixed/automatic for each Caps shot; no power or loft control |
| Footballers | Editable local **test database**, not dependent on live API |
| Debug | Full developer controls and repeatable physics diagnostics |
| Water/OOB | Automatic safe recovery **plus one penalty stroke** |
| Online services | **None** in V0.1 |

## 1.2 Definition of done

V0.1 is complete only when a tester can install the APK on Android, open it, play and finish the three holes, use both shot modes, see physics-based outcomes, observe shot and scoring rules, and use developer controls to test distances and conditions. The GitHub Actions APK build must complete successfully, and the resulting downloadable artifact must be verified as an APK. Headless tests alone are insufficient to claim Android-device compatibility.

## 1.3 Development priority

1. **A playable vertical slice**: one hole, one ball, aim, footballer, Caps/Goals, Take Shot, actual motion.
2. **Correct physics and mechanics**: calibrate exact neutral distances, surfaces, stopping, collisions and recovery.
3. **Three complete holes and scoring**.
4. **Useful test tools and reliable Android APK builds**.
5. **Realistic visuals, phone responsiveness and polish**.

The first working APK should emerge as soon as the vertical slice is functional; do not postpone all Android builds until artwork is finished.

---

# 2. Product boundaries and authority

The workshop established many rules for a future multiplayer game. Preserve them, but **do not attempt to implement networked multiplayer before the offline prototype is playable**.

**V0.1 required:** 3D course, camera, aiming, both shot types, editable players, ball physics, collisions, terrain surfaces, hazards, hole detection, scoring, three-hole flow, debug/testing overlay, local persistence of test settings, Android build pipeline.

**V0.1 optional after first playable APK:** offline mulligan rule controls, richer shot history/scorecards, more detailed terrain and vegetation, improved shot animation/audio, fuller course hazards. Optional elements must not block the initial mechanics milestone.

**Deferred:** online lobby, room codes, guest identity, shared network player pool, opponent turns, host migration, late joins, multiplayer reconnect, shot timers, live leaderboards, sudden-death playoffs, 18-hole course, external real-footballer database, online matchmaking, accounts, monetisation and distribution through Google Play.

When a V0.1 simplified mechanism conflicts with a multiplayer rule, keep a **single-player implementation now** and a **future multiplayer rule in the roadmap**. Do not quietly change a locked rule. Treat explicitly marked engineering defaults as tunable rather than user-approved design decisions.

---

# 3. Core shot mechanics — canonical rules

## 3.1 Normal shot flow

1. Player sees ball, pin, current hole, par, score/strokes, lie and measured distance to the pin.
2. Player drags the camera/game aiming control horizontally to choose an aim azimuth (360° unrestricted).
3. Player chooses **Caps** (aerial) or **Goals** (ground) at any point on the course.
4. Player opens the footballer selector, searches by name and optionally filters nationality/country, and chooses an available footballer.
5. Player presses **Take Shot** **once**. No power bar, gesture to shoot, swing-timing meter or separate confirmation dialog.
6. The footballer is consumed at the moment the shot is committed; a valid shot counts one stroke even if the ball does not move.
7. Physics runs, camera tracks the ball, terrain and hazards are resolved, and the ball comes to rest.
8. Only after the ball has stopped/resolution finishes, display that footballer's caps/goals and the shot summary.
9. Update score, remaining distance, current lie, available footballers and state. Continue or finish hole.

The user must always be able to view selectable footballers without seeing their cap or goal counts in **normal play**. The dedicated developer editor is allowed to display/change numbers. Do not accidentally reveal hidden stats through list ordering, tooltips, previews, logs shown during a live normal shot, or a predicted distance meter before the shot.

## 3.2 Caps = aerial shot

- **Conversion:** `1 senior international cap = 1 yard of base carry`.
- Example: `200 caps => 200 yd = 182.88 m` aerial carry under **defined neutral conditions**.
- Base carry means the **first ground-contact point after takeoff**, not total distance after bounce/roll.
- Use a fixed, automatic initial loft/launch angle; calculate the launch velocity needed for the selected neutral carry.
- Do not provide low/mid/high shot selection, manual chipping, pitching, power control, clubs, spin slider or launch-angle control in the normal UI.
- Wind, air drag model (if enabled), terrain elevation, collisions and lie-related modifiers can affect **actual** carry and final resting position. The player's caps remain the exact **neutral-condition baseline**, not a guaranteed final lie.
- Collisions with trees or obstructions may end flight early.
- Caps may be selected on the green or in a bunker as well as on the tee, fairway or rough.
- A zero-cap record, if present in the editable developer data, follows the zero-distance shot logic: stroke, consumption, no movement.

## 3.3 Goals = ground shot

- **Conversion:** `1 senior international goal = 1 foot of base ground travel`.
- Example: `30 goals => 30 ft = 9.144 m` on a flat neutral reference surface in no wind, with no collision.
- The shot starts as **ground motion**, not an aerial chip.
- The ball can travel differently on slopes, green, fairway, rough, bunker and after hitting obstacles. Realistic undulations and friction matter.
- Goals mode is selectable from **any** lie, not forced only on greens.
- **Zero goals:** the ball remains still; footballer is consumed; one stroke is added. Do not silently reject, substitute a minimum distance, or waive the stroke.
- No separate putter or power meter.

## 3.4 Player information and uncertainty

- At selection, show footballer's **name** and **nationality**; in a full database distinguish duplicate names with birth/career years.
- In normal play, the selected footballer's caps/goals are **hidden until after the ball has stopped**. This applies to the selecting player as well as opponents in the eventual multiplayer game.
- After the shot, show the revealed stat that drove the shot, optionally both career totals, shot mode, base distance, simulated actual carry, roll, final travel, lie/wind effects, penalties and remaining distance.
- Display an approximate lie penalty/range where appropriate; **do not show an exact predicted landing point** in normal gameplay.
- A history view can list prior played footballers and their revealed data.

## 3.5 Shot state integrity

- A shot must be atomic: validate `player + hole + ball state + mode + footballer available`, then commit the footballer and stroke once, and simulate.
- Prevent double taps, UI re-entry, multiple shot execution, repeated shot-result handling or pressing Take Shot while physics is active.
- Input during simulation cannot move the ball or cause a second shot.
- The shot summary must not appear before the simulated ball has fully stopped and recovery/score changes are resolved.
- Failed attempts to initiate a shot due to incomplete selection, invalid state or a transient software error must not consume a footballer or stroke.

---

# 4. Physics and units specification

## 4.1 Coordinate units

Use **1 Godot world unit = 1 metre** for physics. Never mix displayed imperial units with world coordinates without explicit conversion functions.

- `METRES_PER_YARD = 0.9144`
- `METRES_PER_FOOT = 0.3048`
- `FEET_PER_YARD = 3.0`
- Standard Earth gravity baseline approximately `9.81 m/s²`.
- Golf ball radius approximately `0.02135 m` (standard diameter about 42.7 mm), unless art/physics scale requires a documented visual-only enlargement.
- Display course lengths and Caps in yards; Goals and the close-to-hole radius in feet; use clear units everywhere.

Godot's 3D convention is Y-up. Define all horizontal distance measurements in X/Z, unless an explicitly named *3D distance* is required.

## 4.2 Precise baseline for Caps

On an unobstructed, flat reference plane at unchanged elevation, with zero wind and neutral launch modifiers, Caps must yield **exact neutral base carry within a stated calibration tolerance**.

A simple starting derivation without air resistance is:

`R = v² sin(2θ) / g`, so `v = sqrt(Rg / sin(2θ))`

Where `R` is converted carry distance in metres, `θ` is the fixed launch angle, and `v` is launch speed. This is a useful analytical starting point, not a substitute for numerical calibration once drag, integration timestep and the actual ball controller are included.

**Implementation requirement:** Construct a deterministic neutral-flight calibration routine (or lookup/root solve using the very same trajectory integrator as gameplay) to select launch speed for a requested base carry. Use configurable default angle (e.g. **42° engineering starting value**, not a locked game rule). Measure first simulated ground contact and correct for integration error. The neutral carry must not include bounce or roll.

The shot's actual carry may differ for wind, elevation, obstructing objects and lie adjustments. The source stat is not rounded or replaced by an approximate preset distance.

## 4.3 Precise baseline for Goals

On a flat neutral reference surface without wind or collisions, a Goals shot must travel **exact neutral ground distance within tolerance before stopping**. For a simple constant-deceleration rolling model:

`v0 = sqrt(2ad)`

Where `d = goals × 0.3048 m`, `a` is calibrated reference rolling deceleration, and `v0` is initial tangential speed. Correct or solve numerically to account for fixed-step discretisation and stopping logic. For non-neutral lies or surfaces, simulate the changed friction/rolling resistance and terrain gradients, not a scripted snap to a final point.

The developer panel must let testers inspect calculated neutral-distance targets and measured outcomes separately.

## 4.4 Physical motion

Build a coherent simulation with:

- Gravity-based Caps flight; fixed launch angle.
- Optional physically reasonable drag and wind force on the airborne ball, calibrated into the neutral carry solver.
- Terrain/obstacle collisions, including trees; no clipping through collision geometry.
- Surface-specific coefficient of restitution (bounce) and rolling resistance.
- Slopes/terrain surface normals affecting roll and downhill/uphill acceleration.
- Distinct fairway, green, rough and bunker rolling behaviour.
- Stable transition from airborne to contact to bounce to roll to rest.
- A reproducible sleep/stopping detector based on **low speed for a minimum duration**, with a hard timeout/failsafe against endless micro-rolling.
- A defined ball radius and collision layer/mask scheme.
- Consistent physics timestep and recorded simulation parameters/seed where randomness exists.

Use Godot `RigidBody3D` only if calibration and contact behaviour are controllable and testable. A custom fixed-step ball controller with explicit velocity, contact and collision queries is acceptable if it yields more reliable carry and rolling-distance tests. **Correctness and reproducibility matter more than rigid adherence to a specific node.** Avoid hard-coded teleportation to nominal distances.

## 4.5 Neutral physics tests and tolerances

Initial **engineering targets**, subject to calibration in code (not additional user decisions):

- Caps neutral carry target: within `max(0.25 yd, 0.5% of target)` across representative test inputs.
- Goals neutral roll target: within `max(0.10 ft, 1% of target)` across representative test inputs.
- Test inputs must include 0, small, medium and long values, and at minimum Caps 1/10/50/150/200/400 and Goals 0/1/5/30/100/200.
- Identical inputs and unchanged conditions must produce repeatable results within declared numerical tolerances.
- Separately record first contact, total airborne travel, roll, final position and any hazard recovery.

Do not mislabel the 200-cap **total** result as 200 yards; the correct baseline assertion is **200-yard first-contact carry**.

## 4.6 Lie handling

Maintain surface metadata independently from visual textures. A shot begins in a clearly resolved lie (`TEE`, `FAIRWAY`, `ROUGH`, `BUNKER`, `GREEN`, optionally `FRINGE`). Classify the actual ball contact point, not only camera position. Allow developer override for controlled tests.

Engineering starting behaviour (all tunable):

- Tee/fairway: neutral or nearly neutral launch and normal roll.
- Green: low rolling resistance for Goals shots.
- Rough: greater resistance and some impact on Caps outcome.
- Bunker: strong rolling resistance and visibly reduced rollout.
- Slope: meaningful acceleration/deflection during ground travel.

Show the lie and **approximate** expected modifier to the player, without revealing an exact final-distance prediction. Expose exact coefficients and results only in the developer panel.

## 4.7 Wind

- Wind affects airborne Caps shots, not an artificial guaranteed carry readout.
- Default should be mild and can be set to zero for baseline testing.
- Wind direction and magnitude are configurable in the developer panel.
- Display a small wind indicator in normal UI once implemented; do not let it dominate portrait screen space.
- Use a consistent coordinate system and do not confuse compass heading with the direction wind *blows toward*.

## 4.8 Terrain and obstacles

- Trees must have actual collision proxies, not only visual meshes.
- Bunker boundaries, green/fairway/rough boundaries, water and OOB are scene or metadata regions used by scoring/physics.
- Ball must not pass below a terrain collider or fall indefinitely through tiny geometry gaps.
- A hard collision, hazard or maximum-speed condition must not crash, freeze or generate non-finite ball coordinates.

---

# 5. Hazards, hole-out and scoring

## 5.1 Automatic water/out-of-bounds recovery (V0.1 locked)

When the ball enters a water region or goes out of bounds:

1. Stop the current shot / mark it as a hazard event.
2. Charge **one penalty stroke** in addition to the shot that caused the hazard.
3. Find an automatic, deterministic, safe relief position near the last valid point or boundary that is in bounds, not in a water hazard, not inside an obstacle and safely above terrain.
4. Place the ball at rest at relief, update lie and remaining distance, and show a concise result including `+1 penalty`.
5. If boundary-based recovery fails, fall back to the last validated safe ball position, then the original shot position if necessary; never spawn inside water/OOB or silently erase the penalty.

The exact placement algorithm is an **engineering default to document**, not a separate user-level decision. The simplified V0.1 recovery is intentionally different from manual choice of legal golf relief in future versions.

## 5.2 Hole-out

- Default auto hole-out is **5 feet** from pin/cup centre.
- Configurable radius **0–10 feet**.
- Hole out only when the **ball has stopped** within the configured radius; merely passing through the radius while rolling does not complete a hole.
- A ball that stops 5.1 ft away with a 5 ft setting remains in play.
- At **0 ft**, physical cup entry is required; a numerical radius-zero proximity condition must **not** make hole-out impossible.
- Once holed, prevent further shooting and forbid mulligans of that completed shot.
- A hole-out from any distance/lie counts; no extra putt stroke is added.

Use clear horizontal distance-to-cup logic consistently for threshold tests, along with reliable cup-entry detection in 0-foot mode.

## 5.3 Stroke count and score caps

- Each committed shot counts **1 stroke**.
- Water or OOB: **+1 additional penalty stroke**.
- A zero-distance shot counts **1 stroke**.
- Par 3: automatic maximum **8 strokes**.
- Par 4: automatic maximum **9 strokes**.
- Par 5: automatic maximum **10 strokes**.
- The player's hole ends immediately upon reaching **par + 5**; do not wait for a ball to be physically holed.
- If hazard penalty would exceed the maximum, clamp displayed hole score to `par + 5` and finish hole, while retaining unambiguous internal history of what happened.
- On a completed hole, store strokes, penalties, relative-to-par result, used footballers, shot history and hole completion type (`HOLED` or `MAX_SCORE`).

## 5.4 Three-hole overall result

- Stroke play: the **lowest total strokes across the three holes wins**. In V0.1 with one player, simply report final round total and relative-to-par score.
- A working scorecard should show each hole's par, strokes, +/- par, penalties and aggregate.
- Player can continue from hole 1 to hole 2 to hole 3 and reach a proper round-complete screen.
- Do not require opponent data or a multiplayer server for completion.

---

# 6. Test golf course design

Build **three complete, navigable, playable holes** rather than a menu with decorative scenery or one repeated tee/green scene.

| Hole | Par | Approx. centreline length | Main features | Principal tests |
|---|---:|---:|---|---|
| 1 | 3 | 150 yd / 137.16 m | Tee, short fairway/apron, guarded green, bunker, modest slope | Basic Caps carry, green bounce, Goals putting, auto hole-out |
| 2 | 4 | 360 yd / 329.18 m | Dogleg, trees with colliders, fairway, rough, green | 360° aiming, obstruction, lies, sequential shots |
| 3 | 5 | 510 yd / 466.34 m | Long sloping fairway, lake/water crossing or adjacent hazard, bunker, green and OOB | Long flight, wind/slope, recovery, penalties, par+5 |

Distances are **provisional design lengths** from the workshop, not an obligation to match a named real-world golf course. Plan each hole around a unique camera opening vista and plausible line of play. The designer may tune layout while preserving nominal lengths and objectives.

## 6.1 Course construction requirements

- Prefer native Godot scenes, meshes, height data, materials and collisions. Do not rely on a proprietary paid course package to make the project run.
- Terrain must be visually graded by fairway/rough/green/bunker; actual physics surface metadata must correspond to visual regions.
- Include tee marker, visible hole flag/pin and cup region.
- Add trees/vegetation, modest shadows, sky, lighting and atmospheric depth appropriate to a realistic 3D mobile golf game.
- Construct a physical ball collision surface; decorative grass blades are not individual physics colliders.
- Make each hole's camera entry and tee position usable in portrait framing.
- Avoid complex high-poly scenes, dense grass transparency, large post-processing costs or unlicensed third-party assets.
- Document asset source and licence for anything imported. Generated geometry and self-authored textures are acceptable for the initial deliverable.
- If full photorealism is not achievable in the first APK, prefer **cohesive believable landscape and a responsive game** over a slow or incomplete photorealistic demo.

## 6.2 Data-driven scene schema

Give each hole a reusable `HoleDefinition` containing at least: stable ID, display name, par, nominal yardage, tee spawn, pin/cup transform, fairway/green/rough/bunker classification, obstacle references, hazard/OOB regions, camera defaults and relief-safe points. Store game-state-independent data separately from runtime round progress.

---

# 7. Footballer data and identity

## 7.1 V0.1 local editable test database

Implement JSON or Godot Resource-based persistence. The game **must work entirely offline**. Provide a useful seed dataset with clearly labelled **fictional/synthetic test players** unless actual historic figures and verified data are sourced. A fabricated stat must never be presented as a verified real player's record.

Recommended editor fields:

```text
id: stable unique ID (string/UUID)
name: string
country_code / nationality: string
senior_international_caps: nonnegative integer
senior_international_goals: nonnegative integer
birth_year: optional integer
career_years: optional display text
notes: optional developer field
```

Player usage and shot history are **match state**, not immutable database fields. Do not permanently mark a footballer unavailable across new rounds.

Test database needs small, medium and extreme stat values; intentionally include zero goals, very low caps, long Caps carries, near-hole Goals amounts and duplicate-looking names to exercise selection UX. Test values need not correspond to a real footballer.

## 7.2 Editor functions

- Add, edit, duplicate and delete local footballer records.
- Validate caps/goals as nonnegative integers; reject invalid strings, NaN, negative values and duplicate IDs.
- Persist edits between launches.
- Search name, filter nationality and reset to seed database.
- Hide stats in normal selection, but show numeric fields in the developer editor and after played shots.
- Allow developer-created arbitrary test caps/goals without needing to invent a corresponding real person.

## 7.3 Consumed footballer pool

- Each player can be used **only once per match**. In V0.1, this means once across all three holes, **not once per hole**.
- Consume on a successful Take Shot commit, even if zero distance or hazard.
- Used footballers appear greyed out/unselectable in the normal selector.
- Used footballers' stats become visible in history/used list after the ball stops.
- New round resets availability while retaining editable footballer data.
- Developer `Reset Pool` can explicitly restore availability for tests, distinct from ordinary play.
- Build internal data structures with a `used_footballer_ids` set to support eventual shared multiplayer pool without rewriting the mechanic.

## 7.4 Future full database rules — locked but deferred

- Cover **active and retired international footballers** from **all countries and eras** where credible records can be obtained.
- Only **official senior international appearances and goals** count. Do not include youth, Olympic where not senior, club, reserve or unofficial data.
- If a footballer has represented multiple national teams, use the stats for their **final national team only** (confirmed game rule, even though it differs from a total-career aggregate).
- Disambiguate identical names using birth/career years and nationality.
- Search by name and filter by country; **do not introduce pre-shot stat sorting or filtering**.
- Stats remain hidden until after shot resolves.
- Provisional records may be used in full game without displaying a visible provisional label; maintain data provenance internally.
- Freeze the loaded data snapshot at the start of a multiplayer match. Corrections apply to **future matches only**, not one currently in progress.
- Actual source licensing, verified datasets and ingestion are future work; no live data dependency in V0.1.

---

# 8. Touch control and camera design

## 8.1 Portrait-screen gameplay

Prioritise a modern Android phone in portrait orientation. The 3D course should occupy most of the screen; essential controls should remain reachable with one thumb and outside device gesture bars/cutouts.

**Top HUD:** hole number, par, strokes, perhaps score total; wind and compact current-lie indicator.  
**Main view:** ball at a comfortable near-foreground position, visible fairway/target, non-intrusive aim indicator and approximate pin distance.  
**Bottom control region:** Caps/Goals segmented selection, searchable footballer selection, strong **Take Shot** primary action.  
**Additional small actions:** behind-ball/overhead toggle, scorecard, pause, developer testing panel.

Keep large touch targets, readable typography, sufficient contrast over bright grass/sky and safe-area padding. Avoid crowding the course view with debug text when debug panel is closed.

## 8.2 Aiming

- Horizontal drag on the **course viewport** changes **aim direction**, with full **360° rotation**.
- Shot direction follows selected azimuth; camera can smoothly rotate behind ball to support aiming.
- Do **not** fire shots with a swipe, drag release or anywhere except the Take Shot button.
- When overlays are open, touch/scroll gestures must manipulate the overlay, not accidentally change aim.
- Pressing Take Shot must have no effect while a modal is open, shot simulation is active or footballer selection is invalid.
- Preserve aim where reasonable when switching between Caps and Goals.

## 8.3 Camera modes

**Behind ball:** default aiming view, framed so ball, near terrain and approximate shot direction are legible. Track ball in flight and during roll without nauseating or extreme camera snaps.

**Overhead:** optional tactical top-down view showing the hole and ball position. Allow tapping or dragging to measure horizontal yardage from the ball to a chosen point. Measurements do **not** claim to predict the landing position; a distance marker is not a shot preview.

Return to behind-ball mode easily. The camera must behave sensibly on long holes and near the green. Camera transitions can be simple at first, then polished.

## 8.4 Feedback and shot summary

After the shot finishes, show a small expandable panel:

- Footballer and country.
- Caps/Goals mode and **revealed** stat value.
- Base (neutral) distance.
- Actual first contact/carry (for Caps), actual roll and total travel.
- Penalty, if any.
- Remaining distance and lie.
- Stroke/hole-score update.

Keep the primary UI uncluttered. Add optional detailed diagnostic values only behind expansion or developer mode.

---

# 9. Game states, data and architecture

## 9.1 State machine

A robust minimal state progression:

```text
BOOT / MAIN_MENU
    -> ROUND_SETUP
    -> HOLE_INTRO
    -> AIMING
    -> FOOTBALLER_SELECTION (overlay)
    -> AIMING (selection confirmed)
    -> SHOT_COMMITTED
    -> BALL_IN_MOTION
    -> BALL_SETTLING / HAZARD_RESOLUTION
    -> SHOT_RESULT
    -> AIMING (next shot) OR HOLE_COMPLETE
    -> HOLE_INTRO (next hole) OR ROUND_COMPLETE
```

Developer testing may insert a controlled reset/replay transition, but must not leave phantom strokes or duplicate used-player entries.

## 9.2 Separation of responsibility

Recommended high-level modules:

- `GameManager`: transitions and overall play session.
- `RoundManager`: three-hole order, scorecard and cumulative result.
- `HoleManager`: tee/pin, par, hazards and hole completion.
- `BallController`: physics and stopping.
- `ShotPlanner`/`ShotCalculator`: stats-to-distance conversion and calibrated initial velocity.
- `SurfaceResolver`: lies, material coefficients and ball contact classification.
- `HazardResolver`: water/OOB detection and automatic safe recovery.
- `AimingController`: drag-to-aim and orientation.
- `CameraController`: behind ball, follow and overhead.
- `FootballerRepository`: local JSON/resource CRUD.
- `FootballerPool`: available/consumed set for current round.
- `ShotRecorder`: snapshots, shot summaries and replay state.
- `ScoringService`: strokes, penalties, maximum score and completion.
- `GameHUD`/`FootballerPicker`/`ScorecardUI`: player-facing UI.
- `DeveloperPanel`: test state manipulation and diagnostics.
- `SettingsStore`: local preferences and test presets.

Prefer clear Godot scenes/resources/signals over tightly coupled node paths. Keep physics calculations independently testable; UI must not be authoritative for score or consumption.

## 9.3 Suggested repo layout

```text
football-golf/
├── README.md
├── CLAUDE.md
├── project.godot
├── export_presets.cfg
├── .gitignore
├── .github/
│   └── workflows/
│       ├── validate.yml
│       └── android-debug.yml
├── docs/
│   ├── SPECIFICATION.md
│   ├── ARCHITECTURE.md
│   ├── PHYSICS_CALIBRATION.md
│   ├── TEST_PLAN.md
│   ├── ASSET_LICENCES.md
│   └── BUILD_AND_INSTALL.md
├── scenes/
│   ├── main.tscn
│   ├── round.tscn
│   ├── ball.tscn
│   ├── holes/
│   │   ├── hole_01.tscn
│   │   ├── hole_02.tscn
│   │   └── hole_03.tscn
│   └── ui/
├── scripts/
│   ├── core/
│   ├── gameplay/
│   ├── physics/
│   ├── data/
│   ├── camera/
│   └── ui/
├── resources/
│   ├── holes/
│   └── materials/
├── data/
│   └── footballers_seed.json
├── assets/
│   ├── models/
│   ├── textures/
│   ├── audio/
│   └── fonts/
├── tests/
│   ├── unit/
│   ├── integration/
│   └── scenarios/
└── tools/
    └── scripts/
```

Directory names are a proposed structure, not sacred; actual work must be consistent and maintainable.

## 9.4 Runtime data contracts

At minimum:

**Footballer** — immutable test identity and editable stat data.  
**BallState** — position, velocity, spin if modelled, lie, sleeping/airborne, safe position.  
**ShotRequest** — hole ID, footballer ID, mode, aim direction, launch lie, wind, timestamp/state version.  
**ShotResult** — consumed player, baseline target, launch conditions, carry, roll, total, hazard type, penalty, resulting ball position, next lie, score impact.  
**HoleState** — score, penalties, complete flag, completion reason, shot history.  
**RoundState** — current hole, aggregate, all hole states and consumed-player IDs.  
**DeveloperScenario** — optional deterministic physics setup, ball position, environment and expected output.

Use strongly named units in fields (e.g., `carry_m`, `distance_yd`, `radius_ft`) to prevent errors. Serialize only meaningful state; generated scenery does not need to be stored inside round snapshots.

## 9.5 Save and reset behaviour

- Footballer edits and developer settings survive app restart.
- V0.1 may start a **new round** on launch; robust mid-round resume is desirable but not a blocker for the first mechanics APK. Do not claim resume exists unless implemented.
- Restart hole restores tee/score for that hole with clear handling of player consumption; **developer reset** may rewind consumed IDs according to a stored snapshot.
- Starting a completely new round resets all consumed IDs and scores while keeping saved test players.
- Keep data structures compatible with later network-authoritative multiplayer, but do not add remote infrastructure yet.

---

# 10. Developer control panel — first-class requirement

The test panel is a core V0.1 deliverable, not a late optional admin screen.

## 10.1 Required actions

| Control | Expected operation |
|---|---|
| Place ball | Place at chosen safe coordinates or tap in overhead map; clamp to terrain |
| Set lie | Select tee/fairway/rough/bunker/green reference state for testing |
| Reset ball | Restore ball to hole start or saved test position |
| Undo shot | Restore the most recent shot snapshot: ball, strokes, penalties, footballer, hole state |
| Replay shot | Re-run same mode, stats, aim and environmental inputs, with no duplicate authoritative scoring |
| Set footballer stats | Edit caps/goals and instantly save local test record |
| Add/delete footballer | Modify editable test database |
| Reset player pool | Mark all footballers available for a test reset |
| Set wind | Speed and direction; include zero-wind shortcut |
| Surface configuration | View/adjust rolling resistance, restitution and lie effects |
| Configure hole-out | Radius 0–10 ft, default 5 ft |
| Restart hole | Reset and reload test hole |
| Skip/select hole | Open any of the three holes without playing previous holes |
| Diagnostics | Show base target, initial velocity, first-contact carry, roll, final distance, slopes, collisions, time to rest |
| Save/load scenario | Save deterministic setup for repeatability, if practical |

The editor should not require direct manual edits to game source for routine test inputs. Avoid allowing test changes to corrupt round state silently; label developer actions and explicitly distinguish them from normal gameplay rules.

## 10.2 Diagnostics overlay

Include current/last-shot readings with explicit units:

```text
Shot ID / test seed
Mode and footballer ID
Caps/goals input
Neutral target: yards or feet
Aim bearing (degrees)
Launch angle and speed (m/s)
Wind direction/speed
Initial and final lie
Actual carry (yards) / roll (feet) / total distance (yards)
First-contact coordinates
Number/type of collisions
Hazard and relief coordinates
Ball time in motion
Stroke delta and penalties
Measured baseline error (%)
```

Provide simple `Copy Diagnostic Report` where supported or structured device log output. A developer toggle can force all stats visible in the editor; the normal picker must remain stat-hidden.

---

# 11. UX and visual design direction

## 11.1 Design target

Aim for the visual credibility of a contemporary golf game on Android, not block-coloured mini-golf or a spreadsheet over a 3D scene. The course should have natural colours, plausible grass and fairway shapes, soft sunlight, terrain relief, trees and clear pin visibility. The UI should be clean, restrained, readable in daylight and functional in portrait.

A prior concept mock-up established the broad product direction: polished football/golf identity, green outdoor course and simple game screens. It is a **visual reference**, not evidence of a working prototype or a demand to replicate every mock-up element. The current build must prioritise live 3D gameplay.

## 11.2 Main screens for V0.1

1. **Main menu** — Play Three Holes, Developer Test, Settings, version/build info.
2. **Hole intro** — hole number, par, yardage, basic top-down thumbnail or camera preview.
3. **Gameplay** — course + aim + Caps/Goals + footballer + Take Shot.
4. **Footballer picker** — search, nationality filter, used/available state, no pre-shot stats.
5. **Shot result** — actual outcome and post-shot stat reveal.
6. **Scorecard** — hole pars, strokes, penalties, total.
7. **Developer panel** — testing tools and numerical diagnostics.
8. **Round complete** — final total and options to restart or return to menu.

Future UI (do not build now): create/join private game, multiplayer lobby, waiting for turn, other player indicators, live scorecard, host panel, playoff, shared history and multiplayer results.

## 11.3 Usability details

- Do not block the main camera with large modal panels except when the user intentionally opens the picker/developer menu.
- Keep every crucial button accessible with typical one-handed phone use.
- Use high-contrast text and scalable controls across different portrait aspect ratios.
- Clear disabled state for Take Shot before footballer selection or while ball moves.
- No app permission should be needed for playing three holes offline.
- Use short functional camera follow and feedback sound where practical; silence/mute must be supported if audio is added.
- Support Android back navigation and interruption gracefully; do not trap the user in a view or abruptly exit during a test.

---

# 12. Implementation plan — build actual code in stages

## Phase A — Build foundation and first APK

**Deliverables:** clean Godot project, portrait viewport, working menu, one terrain scene, ball mesh/collider, behind-ball camera, touch input, Android export preset, build workflow. Use actual Godot 4 scene files and runnable GDScript from the start. Verify a debug APK export early.

**Exit gate:** app launches on an Android device or emulator into a 3D playable scene, and a GitHub workflow can produce an APK artifact.

## Phase B — One-hole vertical slice and footballer loop

Implement first tee/hole, aim drag, mode switch, editable test footballer chooser, Take Shot, shot commit, consumption, shot simulation, stop detector, result panel and incremented score.

**Exit gate:** one player can repeatedly play a real Caps/Goals shot and see state update without errors or duplicate scoring.

## Phase C — Physics calibration

Implement neutral-distance solvers, reproducible baseline physics scenarios, slope and lie friction, bounce, wind and collision tests. Persist diagnostics. Calibrate using the **same integrator/model** as gameplay. A unit-test result that differs from on-device behaviour should be treated as a bug to investigate.

**Exit gate:** representative Caps and Goals inputs meet calibration tolerances and repeatability tests.

## Phase D — Complete all three holes

Create par 3, par 4 and par 5 layouts, distinct terrains and hazards, shot-to-shot progression, hole-out detection, max-score handling, new-hole transitions, scorecard and final summary.

**Exit gate:** start round, play all three holes, finish and restart without editor intervention.

## Phase E — Full developer tools

Implement ball placement, wind/lie editing, player CRUD, pool reset, scenario replay, safe undo, hole skip, rich numerical diagnostics and scenario persistence where practical.

**Exit gate:** a tester can validate representative shot mechanics without laborious full-hole replay.

## Phase F — Visual and performance pass

Improve fairway/green transitions, materials, trees, lighting, ball/pin readability, camera follow, HUD, touch targets, load times and frame pacing. Optimise from actual Android measurements, not solely desktop screenshots.

**Exit gate:** readable, usable portrait game on the target Android handset with acceptable frame rates and no serious stability problems.

## Phase G — Validation and deliverables

Fix issues found in regression tests, maintain docs and commit evidence of real builds. Produce a final versioned APK artifact and install/test instructions.

**Exit gate:** GitHub Actions passes, debug APK is downloadable and the acceptance checklist is backed by test evidence.

---

# 13. Automated and manual test plan

## 13.1 Unit tests

- Unit conversion exactly matches 1 yd = 0.9144 m, 1 ft = 0.3048 m.
- Caps input 200 produces neutral carry target of 182.88 m.
- Goals input 30 produces neutral ground target of 9.144 m.
- Negative caps/goals rejected at data validation.
- Duplicate footballer IDs rejected.
- Used footballer becomes unavailable across all holes in a match.
- Used footballer resets on new match, not new hole.
- Zero-goal shot consumes footballer and stroke while leaving ball unmoved.
- Shot commit cannot run twice.
- Invalid/pre-commit shot does not consume a stroke.
- Score maximum applies at par + 5.
- Hole-out radius conversion and 0-foot physical-cup semantics correct.

## 13.2 Physics integration tests

- Caps 1, 10, 50, 150, 200 and 400 on neutral unobstructed flat test plane meet calibrated first-contact carry tolerance.
- Goals 0, 1, 5, 30, 100 and 200 on neutral flat reference surface meet calibrated stopping distance tolerance.
- Identical scenario replay produces consistent outcomes.
- Wind creates measurable carry and crosswind deflection.
- Green/fairway/rough/bunker conditions produce observably different ground behaviour.
- Uphill versus downhill shots show correct distance response.
- Tree collider stops/deflects motion appropriately.
- Water/OOB gives exactly one extra penalty stroke and relocates to a legal safe state.
- Ball eventually stops after shallow rolling and does not run indefinitely.
- No NaN/infinite positions/velocities or fall-through on representative tests.

## 13.3 Gameplay end-to-end tests

1. Start new three-hole round; hole 1 is playable.
2. Search and choose a footballer; stats hidden before shot.
3. Take Caps shot; one stroke, player consumed, flight/bounce/roll resolved.
4. Stats revealed **after** stop; result data coherent.
5. Take Goals shot from fairway/rough/bunker/green; simulate ground travel.
6. Zero-goal shot increments stroke and consumes footballer.
7. Used footballer greyed out and cannot be selected again in same match.
8. Ball passing near flag without stopping inside hole-out radius does **not** finish.
9. Ball stopping inside configured radius **does** finish.
10. At 0-foot setting, physical cup entry works.
11. Recover from water/OOB and count one penalty.
12. Par+5 auto-completes the hole.
13. Hole transitions preserve the global used pool and cumulative score.
14. Complete all three holes, view result and restart new round.
15. Developer undo restores ball/strokes/usage and can replay same scenario without extra authoritative strokes.
16. Move ball and adjust wind/lie/test footballer values.
17. Run in portrait without cut-off controls on Android.
18. Close/reopen app and verify editor settings/footballer edits persist.

## 13.4 CI and device evidence

- Headless import and scene parsing pass with no relevant errors.
- Automated script/unit/integration tests pass.
- `--export-debug` returns success and creates a valid nonzero `.apk`.
- Upload exact APK through GitHub Actions workflow artifacts; record artifact name, size and build commit.
- Test installation on Android (physical phone preferred, emulator acceptable initial validation) and record launch/smoke result.
- Capture meaningful screenshots or gameplay recording once runtime works; **do not substitute screenshots of concept art for working proof**.
- Record known limitations and failing tests honestly; do not claim unexecuted tests passed.

---

# 14. Godot 4, GitHub and Android build requirements

## 14.1 Engine and scripting

- Use **Godot 4.7 stable** as the initial **pinned engineering baseline**, unless an actual toolchain compatibility issue requires changing to another stable Godot 4 release. Keep editor and export-template versions identical.
- Prefer **GDScript** over C# for this release to avoid unnecessary cross-platform .NET packaging complexity.
- Start with Godot's **Mobile renderer** where supported. If the target device/GPU cannot run it properly, use a documented **Compatibility renderer** fallback; verify actual device behaviour.
- Android orientation **portrait**.
- No requirement for Godot or Android Studio to be installed on the user's Chromebook if GitHub cloud builds work.

Official references:  
- Godot 4.7 archive: https://godotengine.org/download/archive/4.7-stable/  
- Godot 4.7 Android export: https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html  
- Godot command-line build/import/export: https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html

## 14.2 Android toolchain

Use the official Godot 4.7 Android export guidance and install matching SDK/toolchain dependencies inside CI. At the time of this handover, the 4.7 guidance specifies **OpenJDK 17**, Android SDK platform tools, platform/build tools, and other Android packages appropriate to its export path. Use official templates for the pinned editor build. Prefer **standard APK export templates** rather than custom Gradle configuration until an actual need arises.

For debug sideloading, release-store signing and publishing are **not** required. A consistent debug keystore is useful to avoid Android package-signature conflicts between builds. Never commit private keystore passwords or production signing keys. Document uninstall/reinstall behaviour if a debug signing identity changes.

Suggested Android package identity: `com.footballgolf.prototype` **as an editable engineering default**, not a legally cleared brand identity.

## 14.3 GitHub Actions requirements

Create GitHub workflows triggered by push to main and manually via `workflow_dispatch`:

1. Checkout repository.
2. Download **exact pinned** Godot editor (use SHA verification where practical).
3. Install matching Godot Android export templates.
4. Set up JDK 17 / Android SDK as required by Godot's documented export method.
5. Run `godot --headless --path . --import` (or exact executable path).
6. Run parser/automated tests using documented CLI with nonzero failure exit.
7. Make a `builds/` directory.
8. Export debug APK using the `Android` export preset.
9. Verify the file exists, is nonempty and is structurally an APK ZIP with manifest/native library resources.
10. Upload `builds/football-golf-v0.1-debug.apk` as a GitHub Actions artifact.
11. Expose artifact name and commit SHA in build summary.

Illustrative CLI sequence **only** — the implementer must supply working dependencies/presets and validate against actual Godot CLI:

```bash
mkdir -p builds
godot --headless --path . --import
godot --headless --path . --export-debug "Android" builds/football-golf-v0.1-debug.apk
```

Configure `export_presets.cfg` appropriately. Do not pretend the commands are enough without installed export templates and the Android SDK/JDK settings.

## 14.4 Git and repository hygiene

- Use private repo `football-golf` unless user changes visibility.
- Include usable README with installation, controls, project requirements and current implementation status.
- Include a `CLAUDE.md` for Claude Code with project rules and test/build commands distilled from this spec.
- `.gitignore` Godot import caches, generated builds, platform caches, logs and sensitive signing material. Keep source assets and required `uid`/metadata files.
- Commit real source scenes, scripts, seed data, settings, workflows and docs.
- No secrets, paid-license assets or private signing credentials in Git.
- Use incremental commits/PRs where the environment supports them; do not stop at an empty repository with a README.

---

# 15. Future multiplayer and complete-game rules — preserved, not V0.1 scope

This section prevents earlier decisions from being lost. These are intended **future build rules** unless explicitly marked unresolved. Do not spend V0.1 implementation effort building lobby/server systems.

## 15.1 Core online format

- **2–4 players**, live online, in one shared 3D golf environment.
- **Stroke play only**: fewest total strokes wins. **Match play removed**.
- All players' golf balls visible on the same course, but **balls do not collide with each other**.
- First tee order random; subsequent tee honour based on best score on prior hole. Tied players retain relative order.
- After players have teed off, **farthest ball from the hole shoots next**.
- Waiting players may aim, switch camera and select a footballer, but cannot shoot until their turn.
- Selecting a footballer **does not reserve** it. The shared pool is locked/consumed **only when an authorised shot is committed**.
- Future online state should be server-authoritative to avoid race conditions, disputes and double-consumption.

## 15.2 Shared footballer pool and stats

- Single shared footballer pool across **all players and all holes** in a match.
- Each footballer can be used **once per entire match** across every player, regardless of whether Caps or Goals mode was chosen.
- Name/nationality are visible before shot; caps/goals hidden from **everyone** until ball stops.
- Used names greyed out and their revealed stats shown afterwards.
- Stats frozen at match start; corrections do not alter in-progress matches.
- Shared shot history should include footballer, mode, revealed stats, shot result, locations and penalties.
- The V0.1 local single-player `FootballerPool` should be written so future network-authoritative sharing is possible.

## 15.3 Course and scoring

- One complete **18-hole course** for initial full-game launch, rather than numerous courses.
- Host may choose **1–18 holes**, in consecutive order or a custom selected sequence.
- Pool reset occurs for **new matches**, not each hole.
- Automatic hole-out default 5 ft; host-configurable 0–10 ft; only when resting inside radius, except real cup entry at 0 ft.
- Automatic **par + 5** maximum score on each hole.
- Hole-out ends the player's hole immediately.

## 15.4 Mulligans — agreed rules

- Host-configurable **0, 1, 2, 3 or 5 per player per match**.
- Mulligan must be taken **immediately after the original shot**, before the next player takes a shot.
- Undo ball position, original stroke and any original-shot penalty.
- **Original footballer remains consumed** after mulligan.
- Replay uses a **different footballer** and counts as a normal replacement shot.
- The replacement/mulligan replay **cannot itself be mulliganed**.
- No mulligan once original shot holed the ball.
- No mulligans in playoffs.
- **Host administrative undo is a different operation:** only the **most recent shot**, restoring footballer availability, ball position, strokes, penalties and hole-completion state. Host undo is not a mulligan and must not be implemented as one.

V0.1 can include local mulligans later if useful, but **developer Undo** must already exist. Keep the two concepts separately named in code.

## 15.5 Tie-break and playoff

- If leaders tie after scheduled holes, only tied first-place players enter **sudden death**.
- Play next hole in normal course order, wrapping around course as needed.
- Continue for **unlimited playoff holes until a single winner**.
- Consumed footballers **stay consumed**; no pool reset between regulation and playoffs.
- No mulligans in playoff.
- **Open design edge case:** if the shared footballer pool becomes exhausted during an unlimited playoff, fallback handling has **not been approved**. Preserve as unresolved rather than inventing a winner or quietly recycling players.

## 15.6 Private lobby and identity

- **Private room code** is the only agreed join mechanism; **no invite-link requirement** and no public matchmaking for the initial multiplayer version.
- Players use **guest display names**; no sign-in or registration.
- Host may configure selected holes, mulligans, shot timer and other approved room options.
- Host can start a match with a room of 2–4 players once final lobby rule is confirmed.
- If host disconnects, host authority must **automatically transfer** to a remaining player; exact replacement selection method is not yet confirmed.
- Robust reconnect/session binding is an implementation requirement to prevent guest names alone being used to take over another player.

## 15.7 Turn timer and disconnect controls

- Shot timer is **off by default**.
- Host may select **Off / 30 / 45 / 60 / 90 / 120 seconds**.
- On timer expiry, **host chooses**: extend, skip, pause or remove.
- **Skip adds one stroke** without moving the ball; extend/pause/remove do not automatically add a stroke by themselves.
- Host can pause/resume, handle disconnects, skip turns, concede holes, remove players, correct scores and adjust shots.
- Host changes notify players; a shared permanent administrative audit log was **not** required.

## 15.8 Round 24 questions left unanswered (DO NOT ASSUME APPROVED)

The workshop presented the following multiple-choice decisions but no submitted selections were recorded before the implementation pivot:

1. **Disconnect behaviour:** auto-reconnect/restoring score and turn; host decides; or both. UI proposal: both, **unconfirmed**.
2. **Minimum lobby size:** start with 2–4 vs only when 4 present. UI proposal: 2–4, **unconfirmed**.
3. **Late joins:** disallow vs allow with a score adjustment. UI proposal: disallow, **unconfirmed**.
4. **Replacement host selection:** longest-connected remaining player vs manual vote. UI proposal: automatic/longest-connected, **unconfirmed**.
5. **Permanent departure:** remove leaderboard score vs keep completed scores marked withdrawn. UI proposal: retain/withdrawn, **unconfirmed**.

No implementation blocker for V0.1 comes from these unresolved multiplayer questions. They should be revisited at the multiplayer phase only.

---

# 16. Deliberate exclusions / avoid feature creep

Do not implement in V0.1:

- Multiplayer networking, host/admin dashboards or guest-room codes.
- Match play, skins, tournaments, leagues or betting systems.
- Club bag, selecting a golf club or manual power meter.
- Shot swing animation requiring skill/timing input.
- Manual launch loft, manual chip/pitch selectors or spin controls.
- A forced putting mode on greens.
- Real footballer data API, paid sports data contract or automatic online synchronisation.
- Player accounts, social/friends system, cloud saves, analytics, ads or in-app payments.
- Public matchmaking or notifications.
- Full 18-hole course prior to the three-hole acceptance milestone.
- Replacing real physics with a ball that teleports to a distance marker.
- UI-only mock-ups represented as playable game code.

Future options may be considered after V0.1 feedback, but no such extras should delay the mechanics APK.

---

# 17. Known risks and recommended handling

| Risk | Handling |
|---|---|
| 'Exact carry' versus realistic physics | Calibrate launch speed using same simulation; declare tolerance and neutral conditions clearly |
| Goals shot travels differently by lie | Define reference flat surface; use physical rolling resistance elsewhere |
| Mobile performance with realistic graphics | Profile on Android; optimise materials, LOD and physics; maintain coherent visuals |
| Course scenery but no real collisions | Keep a terrain/obstacle collision acceptance test for every hole |
| Godot Android export problems | Configure CI in Phase A; pin editor/templates/SDK, use repeatable debug signing |
| Android APK exists but game fails at launch | Require physical-device/emulator launch smoke testing before declaring ready |
| Headless tests misrepresent physics | Exercise actual game simulation model, not disconnected formula-only tests |
| Fabricated sports stats | Seed as synthetic test data with clear labelling; verified official stats only for future full database |
| Used footballers accidentally reset every hole | Round-owned pool persists across all three holes; verify by automated test |
| Duplicate shot counted after fast taps | Atomic shot state transition and input lock |
| No legal relief point found | Deterministic safe fallback from known valid shot/ball snapshot |
| Hard-coded asset paths and generated resources | Validate clean fresh checkout/import/build |
| Endless speculative design revisions | Scope lock: produce source and APK before optional art/features |

---

# 18. Required output from implementation agent

The implementation agent must leave the repository with:

1. A complete opening Godot 4 project, with correct `project.godot` and startup scene.
2. Runnable GDScript gameplay and three fully playable 3D hole scenes.
3. A shot simulation calibrated against Caps carry and Goals ground distance.
4. Local editable player database and normal search/picker with hidden pre-shot stats.
5. Shot consumption, scoring, hole-out, par+5 and automatic hazard recovery.
6. Functional portrait HUD, touch controls, camera modes and shot result panel.
7. Developer tools for testing, editing, replay, reset and diagnostics.
8. Automated physics, scoring and mechanics tests with runnable instructions.
9. Passing GitHub Actions validation and Android APK build workflow.
10. A **real** downloadable APK workflow artifact when environment supports it.
11. Readable docs: build instructions, install/sideload procedure, controls, known limitations and test evidence.
12. Source/control code committed to the intended GitHub repository; work should be reviewable in commits, not only pasted into a chat.

## 18.1 Reporting format after each meaningful implementation milestone

```text
Milestone:
Implemented:
Files / commits:
Tests actually run and results:
APK build status and artifact link (only if real):
Known blockers or failures:
Next implementation task:
```

Do not state that a build/test has passed unless it ran. If a link cannot be verified, do not invent one. Continue independent tasks when CI, network access or signing are temporarily blocked.

---

# 19. Instructions to Claude Code — execute, do not redesign

**Immediately after receiving this file:**

1. Review it as authoritative requirements, including the distinction between **V0.1 now** and **future multiplayer**.
2. Inspect the current working directory and Git remote first; verify access to the actual `football-golf` GitHub repository. If it does not exist and repository-creation permission is available, create it private. If not, create the full local project and report the exact repository access limitation; do not invent successful pushes.
3. Create `CLAUDE.md` and a concise README, then initialise the Godot 4.7 project.
4. Implement a playable first-hole vertical slice as the first coding priority.
5. Add and run calibration tests before expanding complex 3D artwork.
6. Configure GitHub Actions Android debug APK export as early as possible.
7. Expand to three holes, scoring and developer tools.
8. Test on Android if device/emulator access exists; report untested device steps otherwise.
9. Iterate on bugs and usability until the acceptance criteria are satisfied.
10. Finish with an evidence-based status and precise download/install details.

**Do not stop after returning a plan, recommendations, wireframes, pseudocode, static concept images or a single empty project skeleton. Build code. Work in small validated commits, and continue to the next milestone without asking routine permission.**

## 19.1 What the user must do outside the agent

- Ensure the agent/Claude Code can access a GitHub repository named `football-golf` with write permissions.
- Start Claude Code in the cloned `football-golf` repository, add **this Markdown file** to the repository (for example `docs/SPECIFICATION.md`), and instruct Claude Code to implement it.
- Claude Code should directly edit the repository, execute available tests, and configure the Android build workflow.
- Once a successful workflow uploads an actual APK artifact, download it from **GitHub → Actions → successful Android build → Artifacts** and sideload it onto an Android device. The phone may require permission to install apps from the downloading source.

No installation of a local desktop Godot editor is intrinsically needed if the remote build/test environment can run Godot and produce the APK. **A working cloud build is a requirement to fulfil that claim**, not something that Claude Code alone guarantees.

---

# 20. Acceptance checklist for V0.1 release candidate

- [ ] Project opens in pinned Godot 4 engine without fatal import errors.
- [ ] Android build produces a structurally valid debug APK.
- [ ] APK starts and renders correctly in **portrait** on Android.
- [ ] Three distinct realistic-looking 3D holes are playable.
- [ ] Touch dragging rotates aim 360°.
- [ ] Behind-ball camera works; overhead camera and distance measuring work.
- [ ] Caps and Goals work from **every lie**.
- [ ] Caps neutral baseline is **first-contact carry**, 1 cap = 1 yard, within declared tolerance.
- [ ] Goals neutral baseline is **ground stopping distance**, 1 goal = 1 foot, within tolerance.
- [ ] No power meter or manual loft mode exists.
- [ ] The ball actually flies, bounces, rolls and responds to terrain and obstacles.
- [ ] Lies and wind make testable differences.
- [ ] Real/seed footballer selection works; normal pre-shot stats are hidden.
- [ ] Shot input is atomic; footballers are consumed once per match.
- [ ] Used footballers stay used across the three holes.
- [ ] Zero-goal shot counts a stroke and consumes the footballer.
- [ ] Results reveal stats only after ball resolves.
- [ ] Water/OOB adds one penalty and auto-relocates to safe terrain.
- [ ] 5 ft default auto hole-out works only after the ball stops.
- [ ] Configurable 0–10 ft hole-out works, including cup-entry at zero.
- [ ] Hole auto-ends at par + 5.
- [ ] Scorecard and round-complete screen function across all three holes.
- [ ] Developer panel supports ball placement, editing, undo/replay, wind/lie and pool reset.
- [ ] Diagnostics provide neutral target, actual carry, actual roll and error.
- [ ] Headless tests pass and CI uploads a downloadable APK artifact.
- [ ] Build/install instructions and actual known limitations are documented.

---

# 21. Final mandate

**Create a playable, installable Football Golf Android APK, not another speculative product specification.**

The first version should demonstrate the distinctive mechanic immediately: choose a footballer, aim, select Caps or Goals, fire a realistic ball, watch it interact with the golf course, and score the result. The offline prototype is the engineering foundation for the much larger multiplayer design preserved above.

If this document is provided to a Claude Code session, use it as the full project brief and start implementing the Godot source project immediately.
