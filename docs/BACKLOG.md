# Football Golf: backlog and tracker

Single list of what the owner has asked for. Keep it short. Move items between sections as work happens. Quick fixes are done inside the current change; bigger items wait for their batch.

Last updated: 2026-11-08

## Phone-test notes (8 Nov 2026, owner; code status from a read-only code scan, not tested on device)
Possibly already done (owner has not tested the latest APK): hole-out drop animation; pass-and-play standings on hole-complete/round-complete; units reset to yd/ft each shot; dev custom caps/goals ranges.
To do:
- Hole intro: do not block the hole; or bird's-eye flyover that glides to the tee, then controls appear.
- Tee boxes (real mesh) and ball sitting on a tee.
- Manual trajectory by dragging the aim arrow up/down as well as left/right (trial).
- Bigger cup (e.g. 5 ft) plus separate gimme range (e.g. 3 ft, auto-award, from cup centre; confirm centre vs edge). Needs a "no gimme" option. Both belong in Round Setup difficulty.
- Pass-and-play: furthest from the hole plays first. Owner wrote "closest plays next"; confirm (golf rule is furthest first).
- Reset filters, sort, spin and shot setup between rounds (only search/scroll reset today).
- Picker: clear search text on close, keep filters/sort (today it is kept within a round).
- Default mode/style/unit by lie: goals + putt + feet on the green, caps + approach + yards elsewhere (style-by-lie exists; mode does not).
- Allow caps for one shot and goals for the same footballer later in the round (pool supports once-per-mode; needs a Round Setup option).
- Selected footballer name on the shot view clearly tappable, with a swap icon.
- Smaller aim arrow, shrinking near the green and when putting.
- Wind should affect high and low trajectories differently (physics change: calibration tests needed).
- Idea: four clubs (Driver, Iron, Wedge, Putter). Conflicts with the locked "no clubs" rule in CLAUDE.md/spec; needs an explicit owner decision.

## In progress
- Online relay code is integrated and committed (`a11fc68`), not deployed. Relay hosting, verification of the merged game_ui and phone QA remain. See `docs/MULTIPLAYER.md`.

## Next (owner ticked these, in this order)
1. Round-complete screen check in the new style (the scorecard menu is done, waiting for approval).
2. Restyle settings, tutorial, pause menu and developer panel in the new system.
3. Cup and flag physics (physics update): the ball can hit the flagstick if it arrives too fast, bounce off it, and be affected by the hole (rim, lip-out, drop in). Needs ball_sim and cup changes, calibration tests and a matching drop animation.
4. Trajectory bar on the right edge (from the mockup).

## Planned: game features (owner ticked, after the above)
- Round setup with a frozen difficulty configuration: cup size, hole-out radius, wind range, numeric values on/off, filter and sort switches, max score (par+5 default, other cap, or none), trail and aim aids on/off. Footballer reuse rule: once per round or once per mode.
- Local profiles with names, favourites tab and stars (pass-and-play itself is done, with default player names).
- Save and resume (several unfinished rounds), History, personal bests, statistics. No duplicate telemetry after resume.
- Sound and vibration.

## Later / not ticked
- Pin tag restyle (white outline with a pointer), slope on the green (visual treatment), real font for numbers and headings.
- An Augusta-inspired course.
- Check the spin ball dragging on the owner's phone (needs a device).
- Draft or shortlist, match play, challenge codes, online play.
- Do NOT run hole-length simulations (owner decision); lengths are set by ranges.

## Done (committed and in an APK)
- Quick wins: pin tag with white outline and pointer; vibration on shots and hole-outs (toggle in Audio / Visual); check boxes re-skinned in the shared theme; pause menu header rule; round-complete screen matches hole-complete; editable pass-and-play player names in Round Setup.
- Favourites (star on rows, Favourites filter), dev custom caps/goals ranges, player colours (green, red, yellow, blue) and turn flash.
- Relay-based online multiplayer code integrated from the Codex package (relay server, lobby, online session). NOT deployed; no hosted relay, untested on phones. See docs/MULTIPLAYER.md and docs/CLAUDE_NEW_CHAT_HANDOVER.md.
- Pass-and-play (v1): 2 to 4 local players on one phone, one shot each in turn, per-player ball, strokes and scorecard, shared footballer pool and wind, standings on hole-complete and round-complete. Players are "Player 1..4" (named profiles are still planned).
- Main menu and navigation redesign: Foot Golf branding and FG logo, new menu, Course Select, Round Setup, Settings sub-pages, Statistics (overview real, history and records placeholders), consistent Back.
- Picker redesign: compact rows, Filters panel, removable chips. Scorecard redesign and modal fix (menus no longer move or show through the HUD).
- Hole-complete screen, Option B: summary strip, scorecard board (only the holes in the round), "Up next" tile with loading bar pinned to the bottom. Headline uses the app font.
- No maximum score, editable pars. Caps or Goals from any lie. Trajectory options (Punch, Low, Standard, High).
- Whole visible course in play. New courses: Coastal Links, Lakeside, Grand Tour. Hole lengths set to the owner's ranges.
- Graphics pass: grass, tufts, trees, water, larger flag. Post-hole loading bar.
- Picker keeps search text. Data export. Mulligan rules restored. Settings v3 physics migration.
- Yards and feet by source (CAPS yards, GOALS feet). Short translucent aim arrow.
- Shot screen redesign: banner with shot strip, single action button (Choose footballer, Take shot, Skip), Approach / Putt, units on the right.
- Premium design system: frosted glass skins, shader golf ball spin control, display and caps type, taller picker.
