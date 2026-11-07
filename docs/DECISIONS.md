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
