# Product decisions log

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
