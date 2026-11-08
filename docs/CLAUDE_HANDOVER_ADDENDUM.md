# Foot Golf: handover addendum (verified answers for the new chat)

Date: 8 November 2026. Read after `docs/CLAUDE_NEW_CHAT_HANDOVER.md`. This answers the new chat's seven questions with facts only. Nothing here changes code.

## 1. Where the pushed code is

- Pushed branch: `ccr-1f62a11c-rk743j`. `git ls-remote origin` returned `ec3974afecba9844d7cebf46811dc477c91c6a55`, equal to the local HEAD `ec3974a`.
- The branch `claude/new-chat-handover-docs-k0mlnq` was never created or pushed by me. The code is on `ccr-1f62a11c-rk743j`.
- Commits on top of the earlier `5702ab2`: `230c31c` (player names/colours, favourites, dev ranges, docs), `a11fc68` (Codex multiplayer patch), `ec3974a` (quick wins 1 to 6 and doc updates).
- The APK was built from `ec3974a` with a clean working tree. sha256 `5c0783e977b892b701ea0e23413982d329eef68d3e0690ebc814e10cdfb5b82a`. The APK file itself is git-ignored and only existed in the old sandbox's `builds/`.

## 2. Merge into `game_ui.gd refresh()`

- The Codex patch applied cleanly with `git apply --3way --index` (no conflict markers). Its `game_ui.gd` hunks were in `refresh()`, `show_picker()`, `show_hole_intro()` and `_on_hole_completed()`.
- **I did not read the merged `refresh()` hunks by eye and did not render the online "waiting / not your turn" state.** The only evidence is: the file parses, and offline solo and 3-player smoke rounds pass.
- Unresolved question: `_apply_player_style()` (my player colours, names, turn flash) reads `session.turn` and `session.active_name()`, which describe the offline session. It is unverified what these show during an online round, or whether it conflicts with the online waiting state. Review this first.

## 3. What was run after the merge

| Check | Result |
|---|---|
| `godot --headless --path . --import` | 0 script errors |
| `test_online_session` | 1 test, 0 failed |
| `test_game_session` | 25 tests, 0 failed |
| `tests/network/test_relay.py` | NOT run: sandbox had no pytest and no `websockets` library |
| Smoke run, solo (through the real UI) | PASS |
| Smoke run, `--smoke-players=3` | PASS |
| Screenshot render after the merge or after quick wins | none |

Not run at all: the full test suite, physics calibration tests, an Android run on a phone, a hosted relay.

## 4. What was never looked at on screen

| Item | Status |
|---|---|
| 1. Pin tag pointer (`hud_markers.gd`) | parse-checked only |
| 2. Vibration toggle (Audio / Visual, `Input.vibrate_handheld`) | parse-checked only |
| 3. Themed check boxes (`UiKit.make_theme`) | parse-checked only |
| 4. Pause menu header rule | parse-checked only |
| 5. Round-complete screen layout | ran in the solo and 3-player smoke rounds, never viewed |
| 6. Editable player names in Round Setup | parse-checked only |

Also parse-checked only: player colours/names/turn flash, favourites (stars and filter), dev custom caps/goals ranges. The online pages from Codex were checked headlessly by Codex only, never visually.

## 5. Tracker and backlog

- `docs/BACKLOG.md` is tracked in git (up to date at `ec3974a`).
- `builds/format/tracker.html` is in the git-ignored `builds/` folder, so it is not in the repo. The published artifact is the live copy: https://claude.ai/artifact/Nvzb7p1Yxn2ckej6rYV7ec (version 8, published after the quick wins, with "Quick wins 1 to 6" and "Multiplayer code integrated" in Done). It mirrors BACKLOG.md. If the new chat cannot edit that artifact, publish a fresh tracker from BACKLOG.md and give the owner the new link.

## 6. Owner preferences not in the other docs

- **Commits:** commit only when the owner says so, even though a stop hook asks every turn. Update code only when told. Do not push or run tests unless asked.
- **Cost:** the owner is almost out of usage. Minimal tokens, minimal tests, short replies.
- **Showing work:** show screenshots rendered from the real game, not mockups drawn over old images. Preview one change on its own and wait for approval before moving on. Send the tracker link after every update.
- **Design:** do not redesign the approved screens (shot screen, picker, scorecard, hole-complete, menus). Premium sports-game look, not flat or cartoonish.
- **Decisions made in chat:** hole-complete uses Option B; distance unit follows CAPS (yards) or GOALS (feet), resetting each shot; player colours green, red, yellow, blue; app renamed Foot Golf; no hole-length simulations; the owner reviews APKs on their phone.
- **Quick screenshot method:** `xvfb-run -a godot --path . --rendering-method mobile --resolution 450x800 -- --smoke-test --screenshots=<dir> --smoke-stop=<name>` with the switches in `scripts/core/smoke_driver.gd` (`--smoke-tour`, `--smoke-filters`, `--smoke-card`, `--smoke-players=N`, `--smoke-course="Name"`).

## 7. What exists only outside git (will be lost)

- `builds/` is git-ignored: the built APK, build logs and the mockup HTML in `builds/format/`. Published artifact pages survive; the files do not.
- Sandbox scratchpad: screenshots and the unzipped Codex package.
- Uploads folder `/root/.claude/uploads/60f7d1c0-5866-5e77-a529-10e53dfc592f/`: the Codex ZIP and its handover. The patch is already applied and committed, so these are reference copies only.
- The working tree was clean at the last check (before this file was added).

## 8. First steps for the new chat

1. `git log -5 --oneline` and confirm you are on `ec3974a` or later on `ccr-1f62a11c-rk743j`.
2. Review `refresh()` and `_apply_player_style()` in `scripts/ui/game_ui.gd` together with the online waiting state (question 2 above). Render it once if the owner allows.
3. If the owner allows tests: install `pytest` and `websockets` and run `tests/network/test_relay.py`.
4. Ask the owner whether to render and review the six quick wins (one or two screenshots each).
5. Only after the owner says so: deploy the relay (`relay/`, `docs/MULTIPLAYER.md`), build with Godot 4.7, test on two phones on different networks.
