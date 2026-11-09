# Foot Golf: handover for ChatGPT (latest, 9 Nov 2026)

Use this to pick up the project. Read `CLAUDE.md` (rules and locked invariants) and `docs/DECISIONS.md` (newest entries at the bottom) first.

## Repo and build
- Repo `stester101/footgolf`, branch `claude/new-chat-handover-docs-k0mlnq`. Latest commit `50bbae5`, pushed and in sync with origin.
- Godot 4.7 GDScript, Android portrait. Build: `godot --headless --path . --export-debug "Android" builds/football-golf-v0.1-debug.apk`, then `tools/scripts/verify_apk.sh`. `builds/` is git-ignored, so the APK is not in the repo.
- Latest APK built from `50bbae5`, sha256 `433b77b2b1491dff54b4f84f164bb017fddf4dc76e8ea42b3dcdcdcb02576c60`.
- **Owner rules:** commits and pushes are allowed freely. **APK builds only when the owner says so.** Keep replies short. Run only the minimum tests (the owner has asked for this repeatedly). Report only what was actually run.

## Test status
- The last full suite was 169 tests, all passing, before the latest physics edits.
- **Three tests in `tests/integration/test_cup_flag.gd` are known to fail** (`test_moderate_pin_strike_stays_in`, `test_fast_ball_deflected_by_pin`, `test_pin_hit_in_air_can_drop`). They assert the old flagstick numbers and need updating to the new speed-dependent bounce (`pin_restitution` 0.6, `pin_bounce_speed` 1.5, `pin_air_loss` 0.8). The owner asked not to run tests before testing on a phone.
- Known-hang caution: `tests/unit/test_save_resume.gd` had to set `holeout_radius_ft = 5.0` for its bot to finish rounds. Other tests may hang similarly if they rely on a 0 ft gimme.

## What the game is now
- Solo, pass-and-play and LAN/hotspot two-phone multiplayer (host phone runs the relay).
- **Shots:** Caps (yards) or Goals (feet), Approach or Putt, Punch/Low/Standard/High trajectory, vertical spin. Footballers used once per round, or once per mode if the option is set.
- **Courses:** Starter Links, Pinewood Ridge, Coastal Links, Lakeside, Jizzy Nash Nash (9 holes, Augusta-inspired), Canyon Mesa (6 holes), Full 9, Grand Tour, plus build-your-own combinations and a mini season (points scaled by hole count).
- **Tees:** blue, yellow, red on every hole. **Pins:** varied positions chosen from the round seed (same on both phones).
- **Round Setup difficulty:** cup size, gimme, footballer rule, wind, max score, aids, tees, pin positions, sort-by-stats option (needs a country filter on). Frozen per round and shared online.
- **Cup:** **default hole is 12 inches** (owner decision, replacing the earlier 4 ft). Settings migrate untouched older defaults.
- **Hole physics:** a real pit under the green, 4 inches deep. The rim and wall are a hard edge (tangential pace kept at 92%), the floor is turf. Hole-out only when the ball comes to rest inside the pit. A gimme default of 0 ft means the ball must drop.
- **Flagstick:** the pole bounces the ball. It is ignored on the green, so putts are decided by the rim and floor. The bounce is speed-dependent (`pin_bounce_speed` 1.5 m/s): gentle touches drop in, firm hits rebound. Still to confirm on a phone whether the feel is right.
- **Shot setup:** Caps/Goals, Approach/Putt, trajectory and spin you choose stay as set through host updates; every new shot starts with no footballer selected.
- **Online (hotspot):** host taps Host, guests auto-find the host or type the address (remembered on the phone), enter the room code. Waiting phones see the shooter's footballer and aim. Mulligans chosen by the host. Refresh button and an automatic 4 s recovery for stalled requests. Pre-picking the next footballer while waiting was **removed** at owner request.
- **Stats and history (merged):** save and resume for offline rounds, round history, personal bests and course records per profile, and shot-level stats (fairways, GIR, putts, Caps vs Goals) with written definitions in `docs/STATS_DEFINITIONS.md`. Stats not reliably computable show N/A. Not yet checked on screen.
- **Graphics:** Tier 1 and Tier 2 (High setting): sky, fog, ridges, clouds, birds, jet, wind-driven sway, optional glow. Performance baseline in `docs/PERFORMANCE_BASELINE.md`; no optimisation done yet.
- **Menus:** page cards fit their content; long pages scroll inside the card.

## Owner decisions (confirmed, newest first)
- Default hole 12 in (replaces 4 ft and 6 ft defaults).
- Mini season and build-your-own combinations stay as separate modes.
- TV (if built): the Chromebook browser draws its own clean broadcast view from the host's redacted state. No video streaming, no web build of the game, no replays, no sound in V1.
- Commits and pushes allowed freely; APK only on request.
- Picker: caps/goals sort only with a country filter on; numbers stay hidden.
- Hole physics: real pit, no speed-threshold shortcut. Battered rolling balls are fine to lose speed on the rim.

## Work not started or paused
- **Career Mode** (spec in `/root/.claude/uploads/.../FOOTBALL_GOLF_MASTER_CLAUDE_HANDOVER_CAREER_TV_1.md`, Appendix A). A Sonnet agent was building foundations, but it stopped when usage ran low. Nothing merged; check its worktree before restarting. Many numbers are unapproved and must stay in one provisional config file.
- **TV spectator view** (Appendix §3, summary only; the full original spec is not in the repo). Not started. Needs a read-only redacted state feed from the host and a Chromebook browser page.
- **Performance fixes and the course graphics upgrade** (GI03/GI04). Baseline only.
- **Pending owner question:** whether the flagstick bounce feels right on a phone.

## Known gaps and risks
- Nothing has been tested on a phone by an agent. The owner tests on the phone.
- Online play has had several stalls; the 4 s recovery and Refresh are workarounds, not a confirmed root cause.
- The stats pages, the flagstick feel, and the 12 in default have not been checked on screen.
- Blue and red tees can fall outside the hole-length ranges (logged as a deliberate exception).
- Varied pins are unproven with humans.

## Next steps (suggested)
1. Update the three failing flagstick tests to the new numbers, when the owner allows tests.
2. Get the owner's phone feedback on the flagstick and 12 in default, then tune `pin_bounce_speed`.
3. Resume Career Mode from the paused agent's work, or start it fresh, with the 22 unapproved numbers kept provisional.
4. TV view and performance work, after Career foundations are stable.
