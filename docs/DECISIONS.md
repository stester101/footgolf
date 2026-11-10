# Product decisions log

## 2026-11-08 — Online relay implementation authorized
- Owner selected relay-based online play and instructed implementation. Solo and pass-and-play remain.
- Host-authoritative WebSocket relay prototype implemented locally; see `docs/MULTIPLAYER.md`.
- Provisional disconnect policy is pause/reconnect for 60 seconds, then end the room. Any explicit
  departure ends the room. Host migration/removal and persistent resume are not implemented.
- No public deployment, commit, push or APK was performed for this multiplayer work.


## 2026-11-07 — Independent distance source and shot style, mulligans, golf-ball bounce
- Caps gives yards and Goals gives feet. Either can be played as a flight or a roll from any lie.
  Flight uses first-contact carry calibration and offers trajectory and spin; roll uses ground-travel
  calibration. The game suggests roll from a green or within 20 m, and players can override it.
- The aiming aid is one short arrow at the start of the chosen path. The result and shot history
  record both the distance source and shot style.
- Before a round, mulligans can be off, 1, 3, 5 or unlimited. A mulligan may replace the just-finished
  shot from its result screen, restoring the score, ball, footballer pool and shot history. The round
  allowance is locked. Telemetry logs a mulligan event; played-shot exports exclude undone shots.
- Fairway and green landings now have quicker, diminishing skips. Deep grass and sand stop very slow
  hillside creeping. Neutral first-contact and ground-distance calibration remain unchanged.
- Rough reduces flight distance by 3–10%; bunker by 7–18%, for either stat source. Ground shots
  respond to their rolling surface and slope instead of this launch factor.

Changes to locked rules in `docs/SPECIFICATION.md`, made explicitly by the product owner.

## 2026-11-07 — Pre-shot spin (topspin/backspin) added
- **Change:** the spec (§3.2, §16) excluded spin controls. The product owner requested a strike-point
  control: a ball graphic (bottom-right of the shoot panel) with a dot dragged up (topspin) or down
  (backspin). Vertical only — **no sidespin**. Double-tap resets.
- **Rule preserved:** 1 cap = 1 yard of neutral FIRST-CONTACT carry holds for every spin setting. The
  launch-speed solver includes spin, exactly as it includes drag.
- **Effect:** spin changes trajectory shape (Magnus lift: backspin higher/steeper, topspin lower/flatter),
  wind sensitivity, and landing behaviour (backspin bites and can draw back on greens; topspin runs out).
- **Scope:** Caps (aerial) shots only. Goals (ground) shots carry no spin so 1 goal = 1 ft stays exact.
- Spin is part of `ShotRequest` (recorded, replayed, shown in results and diagnostics).

## 2026-11-07 — Test mode stat visibility
- TEST MODE (default on during testing) shows caps/goals before the shot. Turning it off restores the
  locked hidden-stats rule.

## 2026-11-07 — Real footballer data
- Wikidata (CC0) snapshot, men only, complete squads for selected countries (`tools/data/countries.json`).

## 2026-11-07 — Bigger hole, hole-size setting
- Default cup is now 12 in diameter (regulation 4.25 in) so more shots drop; adjustable 4.25–40 in in
  Settings and the DEV panel. Larger cups also accept slightly faster balls (sqrt scaling of capture speed).
  Old saved settings are migrated to the new default (settings_version 2).

## 2026-11-07 — No chips from the green
- A ball on the GREEN may only be played with Goals. Caps is disabled in the UI, the mode switches to
  Goals automatically when the ball reaches the green, and `take_shot()` refuses a Caps shot there
  (nothing consumed). Fringe is not green. Overrides spec §3.2 ("Caps may be selected on the green").
- Spin resets to none after every shot.

## 2026-11-07 — Stat sorting/filtering in TEST MODE only
- The picker has search, sort (name, country, birth year), country chips with live counts, era filters,
  "available only" and Random for everyone. Sorting/filtering by caps/goals exists ONLY in TEST MODE
  (stats visible); in normal play it is hidden, preserving the "no pre-shot stat sorting or filtering" rule.

## 2026-11-07 — Courses and nine holes
- Courses are data (`data/courses.json`): Starter Links (holes 1-3), Pinewood Ridge (holes 4-9, hilly forest
  mountainside, par 24) and Full 9. Future themed courses are added the same way.
- Pinewood Ridge holes are authored with `tools/data/gen_forest_holes.py`; the JSON is the source of truth.

## 2026-11-07 — No maximum score; editable pars
- There is no maximum score per hole: a hole ends only when holed (overrides "max score par+5").
  Each hole's par can be edited in Settings → "Edit hole pars…" (2–8, stored in settings `par_overrides`).

## 2026-11-07 — Caps or Goals from any lie; Caps trajectory options
- Replaces "No chips from the green": Caps or Goals may be played from any lie, including the green.
- Caps shots have a trajectory choice: Punch 12°, Low 24°, Standard (PhysicsConfig.launch_angle_deg, 42°),
  High 56°. The neutral first-contact carry stays exactly 1 cap = 1 yd for every trajectory (the launch
  speed is solved with the same BallSim at the chosen angle). Low/Punch shots stay under tree canopies and
  run out further; High stops quicker. Trajectory resets to Standard after each shot, like spin.
  Recorded in ShotRequest/ShotResult (`trajectory`, `launch_angle_deg`).
## 2026-11-07 — Make all visible course playable (owner-approved)
- Owner request: "Make all visible course playable". There are no per-hole OOB stake lines any more.
  `HoleDefinition.play_area` = the rendered terrain `bounds` inset by 25 m (`oob_inset`, default
  `OOB_INSET_M`); only that outer edge band of the map is OOB (+1 penalty, line-of-entry relief as before).
  `HoleDefinition.boundary` is now that rectangle, so OOB stakes only mark the far map edge.
- Legacy `"boundary"` polygons were removed from the hole JSON (and are ignored if present). Starter Links
  terrain bounds were padded (features + 75 m) so the rough around every feature is visible and in play.
- Trees, water (+1, relief), bunkers are unchanged. `HazardResolver` is unchanged: relief walks back
  along the ball path to the first in-bounds dry spot, which now always exists inside the play area.
- Overrides spec §6 hole 3 "OOB" feature and the old per-hole boundary polygons.

## 2026-11-07 — More themed courses
- Coastal Links (holes 10-13, par 16): open links, dune humps, deep pot bunkers (some in the fairway),
  a burn on hole 13, few trees, strong wind (5.5-7 m/s).
- Lakeside (holes 14-17, par 16): parkland, water carries off the tee / into greens, a long lake on
  hole 17, mostly deciduous trees, gentle hills, light wind.
- Both come from `tools/data/gen_forest_holes.py` (now theme-parametrised; Pinewood Ridge regenerates
  identically apart from the boundary). Lengths: see "Hole lengths" below.
- Course list: Starter Links, Pinewood Ridge, Coastal Links, Lakeside, Full 9 (id `full9`, holes 1-9)
  and Grand Tour (id `all`, all 17 holes; Developer Test plays it). The main-menu course list scrolls.

## 2026-11-07 — Hole lengths (owner-approved)
- New owner ranges for ALL holes: **par 3 = 50-100 yd, par 4 = 100-200 yd, par 5 = 200-300 yd**
  (overrides spec §6's 150 / 360 / 510 yd test holes). Geometry was set from the ranges only; no length
  simulations or tuning loops were run.
- Starter Links 75 / 160 / 260; Pinewood Ridge 170 / 90 / 270 / 150 / 70 / 290; Coastal Links 175 / 80 / 275 / 155;
  Lakeside 165 / 85 / 250 / 185 yd.
- How: the centreline is scaled to the new length; features keep their lateral offsets, tee and green
  surrounds (first 15 m / last 35 m) keep their metres and only the middle of the hole is compressed. Water
  radii along the line of play shrink with the middle (to >= 50 %). Sizes of greens, bunkers, fairway
  widths and trees are unchanged. Generated holes: `design_yards` (original layout) + `yards` in
  `tools/data/gen_forest_holes.py`; Starter Links: one-off `tools/data/rescale_starter_holes.py`.

## 2026-11-08 — Mulligan rules restored to the agreed rules
- A mulligan replaces only the immediately preceding shot, before the next shot. The original footballer stays consumed (not returned to the pool). The replacement cannot be mulliganed. No mulligan after the original shot holed out. The original attempt is kept in `round_state.mulligan_audit` and does not score. Developer Undo remains separate and may restore availability (docs/SPECIFICATION.md §15.4).

## 2026-11-08 — Settings v3 physics migration
- Untouched settings_version 2 physics defaults (bounce thresholds and surface factors from before the golf-ball tuning) are replaced by the v3 defaults on upgrade. Any other saved value is treated as a deliberate edit and kept.

## 2026-11-08: gimme from cup edge, bigger cups, once-per-mode option (owner)
- The auto hole-out ("gimme") distance is measured from the EDGE of the cup (centre distance <= gimme + cup radius). 0 ft = no gimme, physical entry only. Cup diameter may now be up to 72 in, so e.g. a 5 ft hole with a 3 ft gimme works.
- Round Setup has an optional "Footballer once per mode" rule (same footballer once for Caps and once for Goals). Default off keeps once per match. Not offered for online rounds.
- New-shot defaults: Goals + Putt on the green, Caps + Approach elsewhere. Furthest from the hole plays first in pass-and-play (next).

## 2026-11-08: Round Setup difficulty (frozen per round) and local profiles (owner)
- Round Setup has a Difficulty section (`RoundConfig`): hole size, gimme from the cup edge, footballer rule (once per match / once per mode), wind (course / none / scaled 0.25-2x), maximum score (None default / par + 5 / custom strokes over par), aim arrow, ball trail, lie read-out range/exact, footballer numbers on/off. Values are frozen when the round starts (GameSession.rules). Settings > Gameplay keeps the DEFAULTS that pre-fill Round Setup. Defaults equal the previous behaviour (no maximum score).
- Optional maximum score: the hole ends when strokes + penalties reach par + N; the recorded score is capped at that value (`HoleState.max_score`, completion `MAX_SCORE`). Holing on the capping shot is a normal HOLED score. Mulligan can undo the capping shot.
- Online rounds still use the host's setup (cup, gimme, wind, stats); the new options are not part of the online setup and default to off/standard there.
- Profiles: up to 8 named local profiles (`PlayerProfileStore`), each with its own favourites. The old global favourites migrate into the first profile ("Player 1") on first run. Each Round Setup player slot picks a profile or Guest (Guest uses the first profile's favourites). The picker's star and Favourites filter use the active player's profile. Profiles page: Settings > Profiles.

## 2026-11-08: Two new courses, three tees, varied pins (owner-approved)
- New courses (generated by `tools/data/gen_new_courses.py`, JSON is the source of truth, registered in `data/courses.json`):
  **Jizzy Nash Nash** (id `jizzy`, holes 18-26, par 36; owner-chosen name, held in the `JIZZY_NAME` constant and
  the courses.json `name`): Augusta-inspired parkland with rolling pine/dogwood-style tree rows, azalea-style tree
  clusters, white-sand bunkers (normal bunker surface), elevation, big sloping greens with front bunkers, a
  water-carry par 3 (hole 23) and creek-fronted greens (holes 21, 25 crosses a creek mid-fairway). Inspired only;
  no real layouts or trademarked names. **Canyon Mesa** (id `mesa`, holes 27-32, par 24): desert, mesas, big
  shallow waste bunkers, a small oasis pond, steady wind, few trees. Grand Tour and Full 9 are unchanged.
- Tees: every hole has `tee_options` blue / yellow / red. Yellow is the existing tee and the nominal `yards`
  (default; the owner's par ranges 50-100 / 100-200 / 200-300 yd apply to yellow). Blue sits behind it (12-18 % longer),
  red forward on the centreline (12-18 % shorter); blue/red may fall outside the owner's ranges (e.g. par 3 blue up to
  ~104 yd, par 4 blue ~218 yd, par 5 blue up to ~334 yd; par 3 red down to ~53 yd). Each non-yellow tee has its own small tee box.
  Round Setup > "Tees" (Blue / Yellow / Red) is stored in `RoundConfig.tee_color` (frozen, included in to_dict / from_dict for online).
- Pins: every hole has `pin_options` (3-4 positions, index 0 = the fixed pin, others front/back/side at least 3 m inside the
  green edge and 3 m from bunkers/water; slope under the green limit 0.09 for the non-fixed ones; hole_05's fixed pin already
  sat on a 0.24 slope, left as is). Round Setup > "Pin positions" Fixed / Varied (default Varied, `RoundConfig.pin_varied`).
  Varied picks one option per hole from the ROUND SEED (FNV-1a of "seed:hole_id:pin"), so both online phones and any
  rebuild of the round agree.
- Displayed length: chosen tee's yards plus the straight-line tee-to-pin change of the chosen pin versus the fixed pin
  (`HoleDefinition.apply_round_options`); yellow stays inside the owner's ranges for every pin (tested).
## 2026-11-08: picker stat sort (opt-in), custom course combinations, mini season (owner)
- EXCEPTION to "picker never sorts/filters by stats outside TEST MODE": Round Setup > Difficulty has "Order picker by caps / goals (numbers stay hidden)" (`RoundConfig.order_by_stats`, default OFF, a Settings default, host-frozen online). When on, the picker's Sort menu adds Caps most/fewest first and Goals most/fewest first; the numbers stay hidden unless "Footballer numbers" is on, and stat FILTERS stay TEST MODE only. When off the picker is alphabetical-by-default with no stat sorting, exactly as before.
- Custom course combinations: Course Select > Build your own > "One combined round". Any courses from `data/courses.json`, in any order, become ONE round (hole list concatenated; a hole id already included is skipped). Encoded as the course id `combo:a+b+c` (`CourseCombo`), so Round Setup, telemetry and the online setup carry it unchanged.
- Mini season (`Season`, `SeasonPages`): an ordered list of courses (repeats allowed) played back to back in one sitting, no save/resume. Each course is its own normal round (own History/telemetry), same players, profiles, rules and tees. Multi-player points per course by place (lowest strokes-to-par): 1st 2.0 x holes, 2nd 1.2 x, 3rd 0.7 x, 4th 0.4 x, each rounded to the nearest integer, minimum 1; tied players share the average of the places they cover (then rounded). No bonus beyond that (the earlier "bonus for the course winner" idea was dropped). One player: no points, per-course scores are summed. A standings page follows each course; the final page shows the winner (ties share). Leaving to the menu ends the season.
- Online: the host freezes the course list in `RoundConfig.season_courses` (inside the setup `rules`), so both phones build the same season; each phone computes the course result from the synced round states. "Next course" is host-driven (a `season_next` event carries the course, its pars and the host's season state, which the guest adopts).

## 2026-11-09: the hole is a real physical pit (owner)
- Replaces the heuristic hole (speed-threshold capture, landing capture 7 m/s, `cup_sink_fraction`, lip deflection
  rules, canned drop animation). `BallSim` simulates a cylindrical pit (radius `cup_radius`, default 6 ft across,
  4.25-72 in allowed; flat floor `cup_depth()` deep; vertical wall): rim-edge support and deflection, free fall into
  the pit, wall/floor bounces. HOLED = ball at rest in the pit. Details in docs/PHYSICS_CALIBRATION.md.
- Neutral plane and `ShotCalculator` unchanged; calibration unchanged. Old saved cup keys are ignored on load.
- Rendering: the ball inside the pit is drawn over the hole disc (depth test off, darker/smaller with depth); the
  hole-out shows the simulated path. Banner, ring/spark effect and vibration unchanged.

## 2026-11-09: hole uses the course physics, 4 ft default (owner)
The pit rim, wall and floor use the SAME bounce/roll model as the green (speed-dependent restitution, retention, roll decel/drag); no special cup constants. Pit is 4 in deep. Default hole 4 ft; untouched 6 ft and 1 ft saved defaults migrate. Probe (4 ft hole): rolling balls stay in up to ~22 m/s and skim over at ~30 m/s; balls landing at 20+ m/s bounce back out at every descent angle tried, 8-14 m/s mostly stay in.

## 2026-11-09: master handover (Career + TV + GI01-GI14) clarifications (OWNER-CONFIRMED)
- Default hole stays **4 ft** for all modes (replaces the handover's 12 in locked default); Round Setup still offers other sizes.
- **Mini season and build-your-own course combos stay** as separate modes; GI10 (return to menu, no rematch/series) applies to an ordinary single round only.
- Handover gate in force: no commit, push, tag or APK build without explicit owner authorisation for that action.
- **TV (Q-M3):** the Chromebook browser draws its own broadcast view from the host's authoritative, redacted state (no video streaming, no web build of the game in V1).
- **TV (Q-M4):** clean broadcast style for V1: leaderboard, player bar (name, colour, footballer name), distance to pin, ball tracer, hole graphics, lead-change banner; no replays, no sound.
- **Workflow (owner, 9 Nov):** commits and pushes are allowed freely; **APK builds only when the owner says**.

## 2026-11-10: Career footballer-per-season and Q-School (OWNER-CONFIRMED)
- Career footballer rule: a footballer can be used once per SEASON (option, default on). The pool resets at the start of each season. A mulliganed shot still counts as used.
- Q-School: if the player fails it, they try again the next season. The same once-per-season footballer rule applies in Q-School (Q-School rounds draw from the same season pool; reading: Q-School is part of the upcoming season's pool; owner to correct if Q-School should have its own pool).

## 2026-11-10: Career integration choices (IMPLEMENTER, numbers unapproved)
- The live Career uses the real opponent simulation (QualificationManager fields, OpponentSimulation scores, RankingManager tables, WorldEvolution form/injuries/ageing). Every unapproved number stays in `CareerConfig` (PROPOSED DEFAULT - OWNER APPROVAL REQUIRED), including the new rival/report/ledger constants.
- Ties for first that include the player are settled by a seeded simulated sudden-death playoff (the player counts as an average member of the tied group); an interactive playoff is a documented TODO. AI-only ties use the same simulated playoff.
- Ledger/trophies/rivals/records are step-5 extras in schema v2 (migration from v1 fills defaults and rebuilds ledger/trophies from history). Sponsors, shop, off-season, Q-School, tour-card retention and adaptive difficulty are NOT started.

## 2026-11-10: small behaviour changes from the polish pass (no gameplay rules touched)
- Settings > Audio / Visual: frame-rate cap (device default / 30 / 60) and "Keep screen awake during a round" (default on, as before).
- Round Setup remembers the last mulligan and player-count choices across launches.
- Android Back on the home screen needs a second press within 2 s to exit.
- Settings > Developer > "Reset footballer database" needs a second tap to confirm.
- Export data has "Save diagnostic log" (recent engine log lines plus build info).

## 2026-11-10: polish round 2 behaviour changes (no gameplay rules touched)
- New Settings > Audio / Visual toggles: Sound effects (stub, muted by default), Reduced motion, Larger text (Settings pages), Pause when backgrounded (default on).
- Haptics: penalty shots and eagle-or-better hole-outs vibrate with their own strength; ordinary shots and hole-outs unchanged.
- Android backgrounding mid-aim opens the Pause menu (offline only).
- Result screen of a finished round has "Copy round summary" (plain text to the clipboard).
- Tutorial: removed "all three holes" wording, added a Trajectory and spin page.
