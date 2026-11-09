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

## Requested 8 Nov (owner), queued after the courses/tees merge
- DONE (8 Nov, headless + screenshots only): Caps/goals SORT option in Round Setup difficulty (picker ordered by caps or goals, numbers stay hidden; off by default; exception to the "never sort by stats outside TEST MODE" invariant, frozen per round, host-frozen online).
- DONE (8 Nov): Custom COURSE COMBINATIONS: pick any courses (or sets of holes) in any order as one round.
- DONE (8 Nov, bonus idea dropped, scaled points as in DECISIONS.md): MINI SEASON (solo, pass-and-play and online lobby): host picks the courses; played back to back in the same room; points per course by finishing place, scaled by hole count (owner to confirm), bonus for the course winner, ties split; season standings screen; host freezes the season so both phones agree. Natural first step of the career-mode ladder (docs/CAREER_MODE_PROPOSAL.md).
- Parity rule: every single-player option must also work online via the host-frozen RoundConfig.

## In progress
- Online play is now DIRECT LAN/hotspot: the host phone runs `LocalRelay` (GDScript port of the relay). Owner dropped the hosted wss:// relay. Headless-tested only; real-phone QA (Wi-Fi and hotspot, 2-4 phones), verification of the merged game_ui and an on-screen check of the new Online screen remain. See `docs/MULTIPLAYER.md`.
- Optional later: hosted wss:// relay (`relay/server.py` still works, no UI for it), mDNS/QR code to avoid typing the host IP.

## Next (owner ticked these, in this order)
1. Round-complete screen check in the new style (the scorecard menu is done, waiting for approval).
2. Restyle settings, tutorial, pause menu and developer panel in the new system.
3. Cup and flag physics (physics update): the ball can hit the flagstick if it arrives too fast, bounce off it, and be affected by the hole (rim, lip-out, drop in). Needs ball_sim and cup changes, calibration tests and a matching drop animation.
4. Trajectory bar on the right edge (from the mockup).

## Parked proposals
- TV companion / spectator view for the owner's Chromebook-on-TV: `docs/TV_COMPANION_PROPOSAL.md` (low-effort sub-agent draft, not reviewed in depth). Recommends a lightweight HTML/JS spectator page on the relay with a read-only seat; needs the hosted relay first.

## Planned: game features (owner ticked, after the above)
- Round setup with a frozen difficulty configuration: cup size, hole-out radius, wind range, numeric values on/off, filter and sort switches, max score (par+5 default, other cap, or none), trail and aim aids on/off. Footballer reuse rule: once per round or once per mode.
- Local profiles with names, favourites tab and stars (pass-and-play itself is done, with default player names).
- DONE (headless-tested, not seen on a device): save and resume (several unfinished offline rounds, `RoundSave`/`RoundAutosave`, user://saves), History + personal bests (`RoundHistory`, user://history.json, Statistics > Round History / Records, `HistoryPages`). No duplicate telemetry after resume. A save is taken at hole intro / aiming / result / hole complete, never mid-flight (killing the app during a flight resumes at the pre-shot state). Still open: richer statistics (fairways, greens, putts).
- Sound and vibration.

## Later / not ticked
- Pin tag restyle (white outline with a pointer), slope on the green (visual treatment), real font for numbers and headings.
- An Augusta-inspired course.
- Check the spin ball dragging on the owner's phone (needs a device).
- Draft or shortlist, match play, challenge codes, online play.
- Do NOT run hole-length simulations (owner decision); lengths are set by ranges.

## Done this session (committed and pushed, NOT in an APK yet; tests pass, only the hole intro and picker were rendered)
- Batch A: full reset between rounds (filters, sort, bands, search), picker search clears on close, Goals + Putt on the green and Caps + Approach elsewhere, swap icon on the footballer chip, smaller aim arrow near the pin and when putting.
- Batch B: gimme measured from the cup EDGE; cup up to 72 in; Round Setup option "Footballer once per mode" (Caps and Goals).
- Batch C: hole intro is a slim bottom bar over the bird's-eye view (camera eases to the tee on Tee off); ball sits on a tee peg; larger tee markers. Real tee box mesh still to do.
- Batch D: trial drag up/down on the aim view changes trajectory (Settings > Audio / Visual toggle, default on).
- Batch F: pass-and-play, furthest from the cup plays next.
- Hold-to-fast-forward button (4x) while the ball is moving.
- Tee box pad tried and removed (owner: looked wrong); tee markers kept, now yellow. Hole-out pulse: soft ring plus a small spark burst at the cup (more sparks for eagle or better). Flyover/intro camera dropped by owner. Hole diameter now shown in feet in Settings and dev panel. Pulse/sparks not yet viewed on screen.
- Post-shot result panel redesign (docs/FOOT_GOLF_POST_SHOT_UI_HANDOFF.md as supplied): glass panel, lie chip above it (ON THE FAIRWAY / IN THE ROUGH / hazard + penalty), 3-4 divided metrics, Details + blue Continue; hole-out shows the real score name (HOLE IN ONE .. +N) with green Continue, HOLE COMPLETE banner, tap card to skip the reveal. Cup pulse/particles not done. Only viewed mid-animation in smoke screenshots.
- Pixel-art ground-level lie under the ball on the spin control (grass, rough tufts, sand, green).
- Lie penalties: rough now 10-20% shorter, bunker 20-40% (flight shots; old saved defaults migrate, custom edits kept). The spin ball sits on the lie colour with the lie name and penalty underneath; Settings > Gameplay "Show exact lie penalty" switches range to this shot's exact value (exact is true, from the shot seed). Rendered once on the tee only; rough/bunker look not seen yet.
- Country filter list: rows now pass drags through so it scrolls by touch (taps ignored if the list moved); list taller. Star has a gap before the arrow. Player 2 red is now a deeper #D63A44. Not tested by touch on a device.
- Picker star icon centred in its row; shorter name/year fonts to cut truncation.

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
