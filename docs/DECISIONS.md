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
