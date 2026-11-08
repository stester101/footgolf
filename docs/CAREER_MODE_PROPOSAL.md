# Career mode: research note

Status: proposal only, no code changed. Date: 8 November 2026.
Labels: [observed] read in this repo; [opinion] my judgement. No external sources are cited.

## 0. What exists today [observed]

- Courses: `data/courses.json` has Starter Links (1-3), Pinewood Ridge (4-9), Coastal Links (10-13), Lakeside (14-17),
  plus Full 9 and Grand Tour as groupings of the same holes.
- Round setup: `scripts/gameplay/round_config.gd` (`RoundConfig`) already freezes cup size, gimme, reuse rule
  (`reuse_per_mode`), wind mode, max score, aim arrow, trail, lie exactness, stats visibility.
- Mulligans are in DECISIONS (2026-11-07), with a round allowance of off, 1, 3, 5 or unlimited.
- Profiles: `scripts/data/player_profile_store.gd` stores named profiles and favourites (`user://` JSON).
- Pass-and-play (2-4 players) and the LAN relay (host phone) exist. Telemetry: `scripts/data/telemetry_log.gd`.
- Footballers: `FootballerRepository`, `FootballerPool` (once per match), synthetic seed plus generated real records.
- NOT built [observed, from docs/BACKLOG.md]: save and resume, History, personal bests, statistics history, tee/pin
  options. Hole geometry has one tee and one pin per hole in `data/holes/*.json`; there is no tee-box selector.

## 1. Locked invariants that career ideas must respect [observed, CLAUDE.md]

- 1 cap = 1 yd and 1 goal = 1 ft neutral mapping; neutral = flat fairway, zero wind, no obstacles.
- No clubs, no power meter, no loft controls; trajectory is the four owner-approved options; spin is vertical only.
- Footballer usable once per match (new round resets). Career must not make a footballer reusable silently.
- Stats hidden until the ball stops; picker never sorts or filters by stats outside TEST MODE.
- Commit is atomic; failed validation consumes nothing. Water/OOB +1 penalty. No maximum score by default.
- Cup default 12 in (owner-approved). Hole-out only at rest within radius.
- Developer Undo is not a mulligan.

Any concept that changes these needs an explicit owner decision logged in docs/DECISIONS.md.

## 2. Concepts (4-6)

### A. Season ladder across the existing courses
Play the courses in order (Starter, Ridge, Coastal, Lakeside, Grand Tour). A course is "won" when the total is
under a target par, or when the owner-set target is met. Winning unlocks the next course.
- Fit: [opinion] fits fully. Uses only existing holes, pars and rounds; no rule changes.
- Reuses: `courses.json`, `RoundConfig`, `App` hole loading, profiles.
- Save: one season file per profile (`user://career_<profile>.json`): current stage, results per course, unlocks.
- Conflicts: none with locked rules. Pars are editable in Settings, so a "won" flag must record the par set used.
- Effort: M. Risk: low. Good first step.

### B. Squad / manager: footballers gain form or fatigue
Each footballer in your squad has form (up or down after shots) or fatigue (recovers between rounds).
- Fit: [opinion] conflicts. Any change to distance is a change to the 1 cap = 1 yd mapping, and form would
  need a visible number, which breaks "stats hidden until the ball stops" unless it is also hidden.
- Also [opinion]: changes to recorded footballer data raise fabricated-data concerns (CLAUDE.md: seed data is
  synthetic; real data must not be presented as edited records).
- Possible compromise: form affects only flavour text or a cosmetic badge, never distance. Still needs a decision.
- Effort: L. Risk: high. Not recommended for v1.

### C. Per-hole challenges (optional objectives)
Each hole offers one optional bonus objective, for example "reach the green with a Caps shot", "hole in 3 with
one Goals shot", "no water". Completing it adds a badge or a season point. The score never changes.
- Fit: [opinion] fits, as long as it does not change scoring, pool use or the neutral rules.
- Reuses: `ShotResult` (already records mode, trajectory, hazard, holed), `HoleState`, `ScoringService` read-only.
- Save: badge list per profile.
- Effort: S-M. Risk: low. Strong candidate for v1 alongside A.

### D. Rivals and ghosts: beat a saved score
Compare against your own best round on a hole (ghost) or a friend's saved round (file export/import or the
LAN relay). Shows "+1 vs ghost" on the scorecard.
- Fit: [opinion] fits. Ghost data needs only the saved shot list (positions and stroke counts), not footballer pool.
- Reuses: `telemetry_log.gd`, planned History and personal bests, `DataExport`.
- Conflicts: a friend's file must not reveal the friend's unused footballer pool. Import should carry only results.
- Save: result records per hole. Needs History first (not yet built [observed]).
- Effort: M. Risk: medium (format, versioning when pars or holes change).

### E. Progression: unlocks, difficulty tiers and cosmetics
Rewards such as ball or flag skins, lie art packs, or named difficulty tiers (Rookie, Club, Pro) that preset
`RoundConfig` values (cup size, gimme, mulligans, max score).
- Fit: [opinion] cosmetics fit. Difficulty tiers fit only if they are preset values chosen before the round and
  frozen like today's Round Setup. Trajectory or cup-size unlocks conflict with the locked defaults and need an
  owner decision.
- Reuses: `RoundConfig`, settings store, profiles.
- Effort: M (cosmetics and presets), L (anything that changes rules). Risk: medium (balance).

### F. Story and calendar
Dated fixtures ("this week's match") or a narrative season.
- Fit: [opinion] weak. Dated content invites live data, which the spec excludes (no live data APIs), and the
  game is offline. Fixtures can be fixed in JSON with no date logic.
- Effort: M-L. Risk: medium (content writing, scope creep). Defer.

## 3. Recommended minimal first version

Concept A (season ladder with a target score per course) plus concept C (one optional per-hole objective with
badges). Nothing changes in physics, scoring or the footballer rules. It needs:
1. Profiles (already exists) and a season save file.
2. A "stage" screen that reads `courses.json` and the season file.
3. Targets stored per course in data, not hard-coded.
Estimated effort: M (about 1-2 weeks of focused work) [opinion]. Sequence after Save/resume and History, which
the backlog already plans, so the season file and round history share one save path.

## 4. Save and data needs

- New file per profile in `user://`, versioned (`"version": 1`), holding stage, per-course results with par set used,
  badges and unlocks. Written atomically (temp file then rename). Never the footballer pool (that stays per round).
- Must survive editing pars and holes: store the par list and hole ids with each result, and show a warning if the
  hole data hash changed.
- Dev Undo must not rewrite season results; keep it separate from any mulligan logic.

## 5. Risks

- Scope creep into squad management (concept B) that breaks the neutral rules.
- Balance: unlocks that make the game easier without the owner choosing it.
- Stats leakage: ghost or friend-share features must not reveal hidden stats or pool contents.
- Save corruption on phones with mid-round exits; need the same atomic write as the round.

## 6. Open questions for the owner

1. Is a season target par per course fine, or do you want a points table?
2. Should a footballer's real-world form be shown at all (likely not, given the rules), or never change?
3. Do unlocks have to be cosmetic only, or may they change difficulty presets?
4. Are rivals to be asynchronous (file share) or live over the LAN relay?
5. Is a story or calendar wanted, or only a ladder?
6. Should career rounds use mulligans, and how many?
7. Does a career season run with the footballer pool reset per course, or once for the whole season?
