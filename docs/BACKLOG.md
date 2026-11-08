# Football Golf: backlog and tracker

Single list of what the owner has asked for. Keep it short. Move items between sections as work happens. Quick fixes are done inside the current change; bigger items wait for their batch.

Last updated: 2026-11-08

## In progress
- Nothing building right now.

## Next (agreed)
- Restyle remaining screens in the same system once the owner reviews the hole-complete screen on the phone.
- Restyle the in-round Scorecard menu (Card button) to match the Option B board.
- Check the round-complete screen in the new style.
- Commit, run the full test suite once, build the APK (only when the owner says so).

## Planned: physics update (owner request, not started)
- Cup and flag physics: the ball can hit the flagstick if it arrives too fast, bounce off it, be affected by the hole (rim, lip-out, drop in). Should behave like a real flag and cup. Needs ball_sim and cup changes, new calibration tests, and a drop animation that matches.

## Planned: UI and graphics
- Pin tag styling per the mockup (white outline with a pointer).
- Slope on the green (text was removed; "we'll come back to it"). Needs a visual treatment.
- Real font for numbers and headings.
- Restyle remaining plain screens: settings pages, tutorial, pause, developer panel.
- Trajectory bar on the right edge (mockup idea, parked).
- Spin ball: check dragging on the owner's phone.

## Planned: game features (from the handover brief)
- Round setup screen with a frozen difficulty configuration: cup size, hole-out radius, wind range, numeric values on/off, filter and sort switches, max score (par+5 default, other cap, or none), trail and aim aids on/off.
- Footballer reuse rule at setup: once per round, or once per mode.
- Local profiles, favourites tab and stars in the picker.
- Pass-and-play, 2 to 4 local players, one shot each in turn.
- Save and resume, several unfinished rounds, History, personal bests, statistics.
- Telemetry check: no duplicate events after resume.

## Later / parked
- An Augusta-inspired course.
- Sound and vibration, draft or shortlist, match play, challenge codes, online play.
- Do NOT run hole-length simulations (owner decision); lengths are set by ranges.

## Done (committed and in an APK)
- Hole-complete screen, Option B: summary strip, scorecard board (only the holes in the round), "Up next" tile with loading bar pinned to the bottom. Headline uses the app font.
- No maximum score, editable pars. Caps or Goals from any lie. Trajectory options (Punch, Low, Standard, High).
- Whole visible course in play. New courses: Coastal Links, Lakeside, Grand Tour. Hole lengths set to the owner's ranges.
- Graphics pass: grass, tufts, trees, water, larger flag. Post-hole loading bar.
- Picker keeps search text. Data export. Mulligan rules restored. Settings v3 physics migration.
- Yards and feet by source (CAPS yards, GOALS feet). Short translucent aim arrow.
- Shot screen redesign: banner with shot strip, single action button (Choose footballer, Take shot, Skip), Approach / Putt, units on the right.
- Premium design system: frosted glass skins, shader golf ball spin control, display and caps type, taller picker.
