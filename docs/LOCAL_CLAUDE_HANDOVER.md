# Foot Golf: handover for a fresh local Claude Code chat (11 Nov 2026)

Read `CLAUDE.md` (rules, locked invariants) and the newest entries at the bottom of `docs/DECISIONS.md` first. This file replaces re-reading the old chat.

## 1. Get the code
- Repo `stester101/footgolf`, branch **`claude/new-chat-handover-docs-k0mlnq`**, HEAD `587217e` (pushed; this handover commit sits on top).
- `git fetch origin claude/new-chat-handover-docs-k0mlnq && git checkout claude/new-chat-handover-docs-k0mlnq`
- Godot 4.7-stable: `tools/scripts/install_godot.sh ~/godot --templates` (or point `GODOT` at a local 4.7 install).
- Tests: `GODOT=<godot> tools/scripts/run_tests.sh` (last run on `587217e`: **256 tests, 0 failed, 0 script errors, both smoke rounds PASS**). Subset: `godot --headless --path . -s res://tests/run_tests.gd -- --filter=career`.
- APK: `godot --headless --path . --export-debug "Android" builds/football-golf-v0.1-debug.apk` then `tools/scripts/verify_apk.sh <apk>`. Needs Android SDK/JDK/debug keystore in `~/.config/godot/editor_settings-4.7.tres` (see `docs/BUILD_AND_INSTALL.md`). Last APK built from `587217e`, sha256 `e6d0c4b310c7c3cc2ee7b1eb14424720b0d889c86abf8c79bfc420d89b02dd04`. Locally you can `adb install -r` it straight to the phone.
- Screens without a phone: `godot --path . --rendering-method mobile --resolution 450x800 -- --smoke-test --screenshots=<dir>`; Career pages: `-- --smoke-career --screenshots=<dir>` (prints PASS, then aborts with a malloc error at exit under llvmpipe, not investigated). More switches in `scripts/core/smoke_driver.gd`.

## 2. Owner rules (Simon)
- Commits and pushes allowed freely. **APK builds only when he asks.** No PRs. Never commit keystores/secrets.
- Short replies, report only what actually ran. Targeted tests; full suite once before an APK or after physics/gameplay changes.
- Keep the CLAUDE.md locked invariants (4 trajectories, vertical spin only, stats hidden until the ball stops, picker alphabetical except the opt-in, atomic shot commit, carry calibration).
- Sub-agents are welcome for bounded parallel work (use git worktrees, merge back yourself).

## 3. What exists now
- Solo, pass-and-play, two-phone hotspot multiplayer (host phone runs relay on 8765). 32 holes / 6 courses, tees and varied pins, Round Setup difficulty, stats/history, Tier 1/2 graphics, real cup pit (default 12 in cup, gimme 0 ft), speed-dependent flagstick.
- **Career mode** (`career/`): tour is called **LBT**; Q-School dropped; start rank ~180 with a card. Fictional sound-alike golfers (`career/data/golfer_roster.json`). Real seeded sim (fields, results, World Ranking, Season Standings, form/injuries, ageing), skip any event, ledger, trophies, rivals, tournament report, save v2 (atomic, checksummed, fail-closed Save Error/Retry), footballer once per SEASON (pool resets each season). Lose the card outside the retention line -> 4 wildcard entries per season, top-10 in one wins it back. Guided resumable off-season (review, sponsors, shop, news, start). Sponsors (12 fictional brands, 3 offers, sign one, objectives), shop (30 cosmetics, only ball/flag colour applied in rounds). Adaptive difficulty: opponents only, Off/Balanced/Hard-lock. All Career numbers are PROVISIONAL (`career/data/career_config.gd`, `sponsor_manager.gd`, JSON data) pending owner approval.
- Polish: crash-safe saves, FPS cap, keep-awake toggle, log export, back-to-exit, reduced motion, larger text, auto-pause on background, copy round summary, sound hook stub (no audio assets yet). Ranked ideas in `docs/IMPROVEMENT_PROPOSALS.md`.

## 4. The owner's latest request (not done yet — start here)
Verbatim: *"ok cool - i want next level shit now - the menu ui etc for the season was shite. i also want to see other players on the leaderboard during tournament rounds. come on shit like this is a must in games like this. spawn sub agents for research, development, ui, graphics, physics etc and vastly improve the entire game experience."*

Plan that was started in the cloud (four parallel agents; **their work was NOT pushed and is not in this branch**, so redo it locally):
1. **Career UI redesign** (owns `career/ui/*` except `career_round_run.gd`, new `scripts/ui/career_kit.gd`): research EA PGA / 2K / FC career / Football Manager, write `docs/career/CAREER_UI_DESIGN.md`, then rebuild every Career screen: hero header (rank, season progress), tab bar (Hub/Schedule/Rankings/Me), big "Play next event" CTA, calendar strip, tier-coloured event cards, standings with movement arrows, news/inbox feed, trophy shelf, count-up animations (respect reduced motion), 48dp targets, Android Back everywhere, keep fail-closed save UI.
2. **Live tournament leaderboard** during Career rounds: new `career/simulation/live_progress.gd` splits each opponent's frozen round score into seeded per-hole scores (sums must equal the official result; restart-safe; tee-time offsets so leaders are holes ahead/behind). New `scripts/ui/live_leaderboard.gd`: compact collapsible board (pos, name, to-par, thru, player highlighted, top 5 + player ±1, projected cut line), ticker ("X birdies the 4th to take the lead"), player position change after each hole. Read APIs added in one block at the end of `career_manager.gd`; tiny hook in `game_ui.gd`. Tests in `tests/unit/test_career_live.gd`.
3. **Graphics** (`scripts/world/*`, `assets/shaders/*`): mowing stripes, fringe collar, bunker lip/grain, water foam/fresnel, tree variety, fake AO/shadows, grandstands/crowds and fictional sponsor boards, yardage markers, flag cloth. Behind High/Low toggle; render must match analytic terrain; keep stencil hole shaders working.
4. **Game feel/camera/audio/physics**: procedurally synthesised SFX via existing `Feedback.sfx` hooks (kick, landing by surface, cup drop, splash, crowd reactions), better flight/putt cameras, impact particles, outcome callouts; physics realism audit only where calibration tests stay green, log changes in `docs/DECISIONS.md`.
Then: merge, full suite once, build/install the APK when Simon says.

## 5. Open items / risks
- Nothing Career-related has been seen on a phone yet; balance unvalidated.
- Online stalls: Refresh/4 s recovery are workarounds, root cause unknown (use the new log export).
- Flagstick feel and 12 in cup still awaiting owner feedback.
- TV spectator view not started (`docs/TV_VIEW_PROPOSAL.md`).
- `docs/CHATGPT_HANDOVER_LATEST.md` predates Career work.
