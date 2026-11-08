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

## 2. Verified repository state (checked 2026-11-08, new chat)

| Item | Observed |
|---|---|
| Local branch | `claude/new-chat-handover-docs-k0mlnq`, HEAD `ec3974a`, working tree clean |
| Remote | `git fetch origin claude/new-chat-handover-docs-k0mlnq` fails: **ref not found on origin**, so HEAD is not confirmed pushed. The local `origin/...` tracking ref is stale. Push only when the owner says so |
| Commits on top of `5702ab2` | `230c31c` player names/colours, favourites, custom ranges, handover docs; `a11fc68` relay multiplayer from the Codex package; `ec3974a` quick wins 1 to 6 |
| In code | `Input.vibrate_handheld` (game_ui.gd), `PLAYER_COLS`, `player_names` in GameSession, `scripts/network/*`, `relay/`, `tests/network/`, `permissions/internet=true` in export_presets.cfg |

Not re-run this session: Godot import, tests, renders. Earlier claims (APK built, patch clean) are from the previous chat and unverified here.

## 3. Multiplayer status

Relay-based online play (private six-character codes, live turns) is integrated but NOT deployed. Known limits: no hosted `wss://` relay; reconnect only within one app process, 60 s pause then room ends; no host migration, kick or replacement; no live aim preview for waiting players; lobby cannot change mulligans; online pages not visually approved; untested on phones, 4 clients or mobile networks. Never claim it is playable.

## 4. Next steps (only when the owner says go)

1. Targeted verification: `--import` (no script errors), `tests/network/test_relay.py`, `test_online_session`, `test_game_session`, one solo smoke run, one render of the shot screen (player colours, online waiting state).
2. Provision a real `wss://` relay (Dockerfile in `relay/`), build one APK with Godot 4.7, two-phone test on different networks.
3. Open owner questions: `docs/MULTIPLAYER_BRIEF.md` section 6.

## 5. Owner's quick wins 1 to 6

All done and committed in `ec3974a` (pin tag, vibration toggle, themed check boxes, pause header, round-complete layout, editable player names). Remaining items are in `docs/BACKLOG.md`.

## 6. Useful facts

- Run a menu or screen render without playing a round: `xvfb-run -a godot --path . --rendering-method mobile --resolution 450x800 -- --smoke-test --screenshots=<dir> --smoke-stop=<shot name>`. Extra switches in `scripts/core/smoke_driver.gd`: `--smoke-tour`, `--smoke-filters`, `--smoke-card`, `--smoke-players=N`, `--smoke-course="Name"`.
- Real-input routing check: `xvfb-run -a godot --path . --rendering-method mobile --resolution 720x1280 -s res://tools/scripts/ui_input_test.gd`.
- Release build: `godot --headless --path . --export-debug "Android" builds/football-golf-v0.1-debug.apk`, then `tools/scripts/verify_apk.sh`. Only when asked.
- Shared shot rules: atomic commit (footballer consumed and one stroke exactly once), deterministic `BallSim`, `ShotRequest` fully describes a shot.
