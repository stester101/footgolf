# Foot Golf: multiplayer brief for ChatGPT

Implementation brief for online/LAN multiplayer. Read `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` and `docs/BACKLOG.md` first. Do not rebuild existing systems. Keep changes small and report only observed results.

## 0. Important: what you can see on GitHub

- Repo: `stester101/footgolf`. Working branch: `ccr-1f62a11c-rk743j`.
- **Recent work is still uncommitted in the owner's working tree** (the owner is holding commits until they approve): new main menu and navigation, picker redesign, scorecard redesign and modal fix, pass-and-play player colours and names, favourites, custom dev range filters. Pass-and-play v1 itself, the main menu and the picker redesign were committed in the last pushed commit; the player colours, favourites and range filters were not. Ask the owner to say "commit" before you rely on those, and check `git log` first.
- Owner rules: update code only when told; no pushes or tests unless asked; minimal token use; never commit secrets or keystores; do not open a PR unless asked.

## 1. Goal

Let 2 to 4 players play one round on separate phones. Start with a private game joined by a code or address. Reuse everything that already works in pass-and-play (turn rotation, per-player state, shared footballer pool, shared wind).

Out of scope for the first milestone: matchmaking, accounts, ranked play, chat, cloud saves, spectators.

## 2. What already exists

- **Menu:** `scripts/ui/main_menu.gd` has a disabled "Multiplayer / Coming Soon" card (`_multiplayer_card`). Planned flow in its header comment: Host / Join -> Lobby -> Course Select -> Round Setup.
- **Pass-and-play (one phone):** `scripts/gameplay/game_session.gd`
  - `slots: Array[PlayerSlot]`, `turn`, `player_names`, `player_count()`, `active_name()`.
  - After each acknowledged shot the turn moves to the next player not finished with the hole (`acknowledge_result`, `_next_unfinished`, `_switch_to`).
  - Session variables (`round_state`, `ball_pos`, `last_safe_pos`, `aim_bearing_deg`) always describe the ACTIVE player.
  - Players 1 to 4 have colours green, red, yellow, blue (`game_ui.gd`: `PLAYER_COLS`).
- **Deterministic shots:** `BallSim` is a fixed-step deterministic simulation. A shot is fully described by `ShotRequest` (`scripts/gameplay/shot_request.gd`): footballer, mode (CAPS/GOALS), style (FLIGHT/ROLL), aim, spin, trajectory, start position, lie, wind, seed. The same request on the same hole gives the same result, so a client can replay a shot from the request instead of streaming the ball.
- **Atomic commit:** `GameSession.take_shot()` validates, consumes the footballer and adds one stroke exactly once. Failed validation consumes nothing. Keep this rule.
- **Shared pool:** `FootballerPool` (once per round, or once per mode). One pool for all players.
- **Scoring:** `RoundState`/`HoleState` per player. No maximum score by default (setup option planned).
- **Telemetry:** `scripts/data/telemetry_log.gd` records shots/holes/rounds from session signals. It is not a save game.

## 3. Recommended architecture (change if you find a better fit)

**Host-authoritative, command/event model.**

- One phone is the **host** and runs the real `GameSession`. Clients run a read-only mirror of the same code for rendering.
- Clients send **intents** only: choose footballer, set aim/spin/trajectory/mode/style (for preview), press Take Shot, mulligan, acknowledge result. The host validates that it is that player's turn.
- The host broadcasts **events**: round setup (course, seed, rules, players), turn changes, the committed `ShotRequest`, then the resolved result (final positions, score, penalties), hole/round complete.
- Clients replay the committed `ShotRequest` locally for animation, but the host's resolved result is the truth. If a client's replay disagrees, show the host's final position.
- Anything that affects state goes through `GameSession`, never through the UI. Keep the UI presentation-only.
- Transport behind one interface (`NetTransport`) so it can be swapped. Milestone 1: Godot high-level multiplayer with ENet (LAN/direct address) or a small relay; later internet play via a relay/lobby service. Do not hard-code one provider.

## 4. Suggested phases

1. **Transport and lobby:** Host Game creates a room with a short code; Join Game enters it. Lobby shows players, colours (P1 green, P2 red, P3 yellow, P4 blue), ready state, host picks course and rules. Reuse Round Setup controls.
2. **Synced start:** host sends course, seed, rules and player order; every device builds the same round. Per-hole wind comes from the hole definition (already shared).
3. **Turn sync:** turn indicator and "your shot" flash already exist; gate input so only the active player can aim/choose/shoot. Show other players' aim optionally later.
4. **Shot sync:** send the committed `ShotRequest`, replay on all devices, apply the host result.
5. **Robustness:** disconnect/reconnect, host migration (maybe "host leaves ends the round" for v1), timeouts, kicking.
6. **Records:** keep multiplayer rounds out of personal bests until History exists.

## 5. Constraints

- Godot 4.7 stable, GDScript, Android portrait, offline-capable solo and pass-and-play must keep working unchanged.
- Do not modify physics calibration, scoring rules, the footballer database, or the approved screens' layouts (shot screen, picker, scorecard, hole-complete, menus). Add only what multiplayer needs (lobby screens, a connection status chip, a turn waiting state).
- Follow the shared design system in `scripts/ui/ui_kit.gd` (`UiKit.skin(...)`, frosted glass, lime selected, electric-blue primary buttons) and the page framework in `main_menu.gd` (`_page`, `_nav_row`, `_primary_button`, Back handling).
- No secrets in the repo. Any server URL or key must be configurable, not committed.
- Android needs the INTERNET permission in the export preset if you use online transport.

## 6. Open questions for the owner (ask before building)

1. LAN/direct only first, or internet play from the start?
2. Real-time turns on all phones at once, or asynchronous (take your shot whenever, notify)?
3. Is a host-leaves-ends-the-round rule acceptable for v1?
4. Do you want player names/profiles before multiplayer (currently "Player 1" to "Player 4")?
5. Private codes only, or a public list of open games later?

## 7. Acceptance checks (keep tests targeted)

- Two instances (headless or two devices) start the same round from the same seed and finish a hole with identical per-player strokes and positions.
- A non-active player cannot take or commit a shot; a failed validation consumes nothing.
- One footballer cannot be committed twice across all players (once per round rule).
- A dropped client does not corrupt the host's state.
- Solo and local pass-and-play smoke tests still pass.

## 8. Report format

Files changed, what runs on host vs client, observed test results only, anything left as a placeholder, and the questions you still need answered.
