# Foot Golf: handover for a new Claude chat

Date: 8 November 2026. The previous chat's context was full. Read this first, then `CLAUDE.md`, `docs/BACKLOG.md` and the Codex handover. **Nothing in this file has been acted on yet**: it is a status report and a plan, not a record of finished work.

> **Update (end of this chat):** everything below was done: my uncommitted work committed, the Codex multiplayer patch applied cleanly (no conflicts) and committed, items 1 to 6 done and committed, all pushed, one APK built. Remaining work is the deployment steps in section 4 (relay, phones) and the other backlog items.

## 1. Owner rules (standing)

- Edit code only when asked. **No commits, pushes, tests or APK builds unless the owner says so.** The stop hook will keep asking for a commit; ignore it unless told to commit.
- Minimal token use. When tests are allowed, run only the targeted ones. Report observed results only.
- Do not change physics, scoring or the already-approved screens' layouts (shot screen, picker, scorecard, hole-complete, menus) unless asked.
- Do not open a PR. Never commit secrets or keystores. No hole-length simulations.
- Colour/design source of truth: `scripts/ui/ui_kit.gd` (`UiKit.skin`, frosted glass, lime selected, electric-blue primary).
- Keep the project tracker current and give the owner the link after each update: https://claude.ai/artifact/Nvzb7p1Yxn2ckej6rYV7ec (file `builds/format/tracker.html`, same list as `docs/BACKLOG.md`).

## 2. Verified repository state

| Item | Observed |
|---|---|
| Repo / branch | `stester101/footgolf`, `ccr-1f62a11c-rk743j` |
| Local HEAD = remote head | `5702ab245dc3856ec23ac3cb24f7384341217dbf` (checked with `git ls-remote`) |
| That commit contains | main menu and navigation redesign, picker redesign, scorecard redesign and modal fix, pass-and-play (2 to 4 local players), settings and statistics pages, Foot Golf branding |
| Last APK built | from `5702ab2` plus nothing else (pass-and-play, new menu, picker, scorecard) |
| Godot in this sandbox | 4.7.stable |

### My uncommitted work (still only in this sandbox's working tree; will be lost if the sandbox is reset)

- `scripts/ui/game_ui.gd`: pass-and-play player names and colours (P1 green, P2 red, P3 yellow, P4 blue) on the banner, shot-card header, spin markers and selected stat/shot buttons; "PLAYER N · YOUR SHOT" fade between turns (`_apply_player_style`, `_flash_turn`, `PLAYER_COLS`).
- `scripts/ui/spin_control.gd`: `accent` colour variable for the markers.
- `scripts/core/settings_store.gd`: `favourites` array, saved and loaded.
- `scripts/ui/footballer_picker.gd`: favourite stars on rows, Favourites filter chip and star button, and dev-only custom caps/goals ranges (min/max boxes, "Caps 80–120" chip).
- `scripts/ui/line_icon.gd`: `star` icon.
- `docs/MULTIPLAYER_BRIEF.md` (untracked), plus this file.
- **Parse-checked only. Never rendered or tested.** Expect to look at them on screen once.

## 3. Codex multiplayer package (reviewed, not integrated)

Files supplied: `/root/.claude/uploads/60f7d1c0-5866-5e77-a529-10e53dfc592f/9983e9ae-Foot_Golf_Multiplayer_Claude_Source.zip` and its handover `.../ed0fe56d-FOOT_GOLF_MULTIPLAYER_CLAUDE_HANDOVER.md`. Contents: `multiplayer.patch`, `base_files/` (ancestors), `changed_files/` (their versions), `manifest.json`. A copy was unzipped to the scratchpad `.../scratchpad/mpzip/` (may not survive; re-extract from the ZIP with `python3 -I`).

Observed in this review:
- Base commit in the manifest is **exactly my HEAD** `5702ab2`. Codex made no commits and pushed nothing.
- 26 files: relay server and tests (`relay/`, `tests/network/`), network scripts (`scripts/network/`: codec, transport, `online_room.gd`, `online_session.gd`), `tests/integration/test_online_session.gd`, docs (`docs/MULTIPLAYER.md` and notes in ARCHITECTURE, DECISIONS, BACKLOG), `export_presets.cfg` (INTERNET permission), and edits to `app.gd`, `main.gd`, `round_controller.gd`, `main_menu.gd`, `game_ui.gd`.
- **Overlap with my uncommitted files: only `scripts/ui/game_ui.gd`.** `git apply --check` of the whole patch against my dirty working tree reported no errors. Their game_ui hunks are in `refresh()` (around lines 775 to 820), `show_picker()`, `show_hole_intro()` and `_on_hole_completed()`. My uncommitted hunks are near `refresh()` lines 804 to 814 and in the shot-card and banner builders, so **review `refresh()` by eye after applying**: the textual merge is clean but the logic (their "waiting for host / not your turn" shot state versus my colour and name updates) must be checked together.
- No overlap in `main_menu.gd`, `round_controller.gd`, `main.gd`, `app.gd`, docs or `export_presets.cfg` with anything uncommitted, because my menu work is already in the base commit. Check `export_presets.cfg` only for the permission line; never copy keystores.
- Codex tested with Godot 4.6.3 (this sandbox has 4.7). Their claimed checks: relay protocol tests (2), OnlineSession integration test, pass-and-play turn test, headless menu/lobby flow, a two-process relay run with reconnect. Not tested: real course, 4 clients, phones, Android export, hosted relay, mobile networks.
- Their known limits (do not claim multiplayer is playable yet): no hosted `wss://` relay; reconnect only within one app process, 60 s pause then room ends; no host migration, kick or replacement players; no live aim preview for waiting players; lobby shows but cannot change mulligans; new online pages not visually approved.

## 4. Plan for the next chat (do these only when the owner says go)

1. **Protect work.** Back up my uncommitted diff outside the repo (`git diff > backup.patch`, copy untracked files). Ask the owner whether to commit the uncommitted work first as its own commit (recommended: yes, so the merge has a clean base), then push only if the owner says so.
2. **Integrate in an isolated worktree** at `5702ab2` (or on a new branch off the committed result): `git apply --check` then `git apply --3way --index multiplayer.patch`. Resolve `game_ui.gd` carefully, keeping both sets of behaviour. Do not copy `changed_files/` wholesale.
3. **Verify the merge, targeted only:** `godot --headless --path . --import` (no script errors), Codex's relay tests (`tests/network/test_relay.py`), `test_online_session`, the existing pass-and-play test (`test_game_session`), and a solo smoke run. Render the shot screen once to confirm the player colours still work and the online waiting state looks right.
4. **Then, only if asked:** provision and configure a real `wss://` relay endpoint (Docker file in `relay/`), build one APK with Godot 4.7, and play a short round on two phones on different networks (reconnect, background/resume, mulligans, next hole, back to offline).
5. Open question list for the owner is in `docs/MULTIPLAYER_BRIEF.md` section 6; Codex's implementation already chose relay-based online play with private six-character codes and live turns.

## 5. Owner's pending small requests (not started)

Quick wins list, in the owner's words "1 to 6", requested next after multiplayer prep:
1. Pin tag restyle (white outline with a pointer), `scripts/ui/hud_markers.gd` `_marker()`.
2. Vibration on shot, bounce and hole-out, with an Audio / Visual toggle (`Input.vibrate_handheld`).
3. Re-skin check boxes and number boxes in the shared theme (`UiKit.make_theme`).
4. Pause menu and confirm dialogs restyled like the Scorecard (`show_pause`, `confirm` in `game_ui.gd`).
5. Round-complete screen to match the hole-complete layout (`_on_round_completed`).
6. Editable player names in Round Setup (needs the names passed through `play_requested` to `GameSession.start_round`).

Other backlog items (cup and flag physics, trajectory bar, round setup difficulty options, save/History/records, profiles with favourites per profile, sound) are in `docs/BACKLOG.md`.

## 6. Useful facts

- Run a menu or screen render without playing a round: `xvfb-run -a godot --path . --rendering-method mobile --resolution 450x800 -- --smoke-test --screenshots=<dir> --smoke-stop=<shot name>`. Extra switches in `scripts/core/smoke_driver.gd`: `--smoke-tour`, `--smoke-filters`, `--smoke-card`, `--smoke-players=N`, `--smoke-course="Name"`.
- Real-input routing check: `xvfb-run -a godot --path . --rendering-method mobile --resolution 720x1280 -s res://tools/scripts/ui_input_test.gd`.
- Release build: `godot --headless --path . --export-debug "Android" builds/football-golf-v0.1-debug.apk`, then `tools/scripts/verify_apk.sh`. Only when asked.
- Shared shot rules: atomic commit (footballer consumed and one stroke exactly once), deterministic `BallSim`, `ShotRequest` fully describes a shot.
