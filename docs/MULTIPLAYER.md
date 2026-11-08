# Multiplayer implementation — 8 November 2026

## Direct hotspot play (current plan)

Owner decision: no hosted relay. 2 to 4 friends play phone-to-phone over ONE phone's Wi-Fi hotspot
(home Wi-Fi is not a supported flow). The host phone runs the relay itself.

Flow: Host turns on the phone's hotspot and taps Online Multiplayer -> Host a game -> Start hosting.
Friends connect their phones to that hotspot and tap Join a game: the app finds the host by itself, the
guest types only the 6-character room code (and name is remembered). "Enter address manually" remains as a fallback.

- `scripts/network/local_relay.gd` (`LocalRelay`, owned by the `App` autoload) is a GDScript port of
  `relay/server.py`: same JSON messages, seats, 6-character room codes, host-only events, readiness,
  4-seat cap, 200-room cap, 40 messages/s rate limit, 60 s reconnect grace. `TCPServer` plus
  `WebSocketPeer.accept_stream()` polled from `_process` (no threads) on fixed port 8765.
  New: a `preview` message (any seated player, room started) is forwarded to the other seats tagged with the
  sender's relay-assigned seat; payloads over 600 characters are dropped. `relay/server.py` was NOT updated.
- `scripts/network/host_finder.gd` (`HostFinder`): auto-find. Candidates are `x.y.z.1` of every private /24 of
  the guest's own addresses (`IP.get_local_addresses()`), plus 192.168.43.1, 192.168.49.1, 172.20.10.1,
  192.168.137.1 (own address and loopback/link-local/public/IPv6 excluded). Each is probed in parallel with a
  WebSocket handshake to port 8765 (1.8 s timeout); answers are reported as the host. No UDP broadcast discovery.
  If several hosts answer, the first is used and the manual address field can pick another.
  `best_host_address()` chooses the address shown on the host screen (known hotspot gateway, then `.1`, then first private).
- Host: shows the detected hotspot address, then in the lobby the room code (large) and the connected players.
- `NetTransport` accepts plain `ws://` only to 127.x, 10.x, 172.16-31.x, 192.168.x, 169.254.x (and localhost).
  Anything public must be `wss://`. The hosted relay code path still exists but has no UI.
- OnlineRoom / OnlineSession keep their authoritative logic. The host phone's relay and host game share one app.

Waiting-player view (OnlineSession, GameUI, RoundController):
- While a player aims, their phone sends a throttled (about 4 per second, plus a 1.5 s heartbeat) `preview`
  `{rev, id, mode, style, traj, spin, aim}` to the others. Spectators ignore it unless it is from the player whose
  turn it is, matches their current revision, parses cleanly (`OnlineSession.sanitize_preview`) and is under 5 s old.
  It is never stored in snapshots and no rule reads it; the commit path (Take Shot intent, host-authoritative) is unchanged.
- A compact card replaces the shot controls on the waiting phone: active player, footballer name and flag, stat
  (Caps/Goals), Flight/Roll, trajectory, spin and aim bearing; the aim arrow in the 3D view and the camera heading
  follow the live aim. Caps/goals counts are shown only if show_stats is on. Result stats appear after the ball stops as before.
- When the shot is played, the existing replay runs (same behind-the-ball follow camera as any shot) with the card
  showing the shooter's footballer and shot type. There is no extra camera work beyond that. Waiting players cannot act
  (`controls_turn()` is false; shot controls are hidden).

Honest limits (nothing here has been run on phones):
- Verified only on a desktop: headless relay + two clients in one process through a short fixture hole including a guest
  disconnect/reconnect, preview delivery both ways, address derivation, and probing of 127.0.0.1 (found) and a closed port
  (not found) (`tests/network/local_relay_smoke.gd`). Screens were rendered with xvfb and viewed. No Wi-Fi, hotspot,
  Android or multi-device test has been done. Whether Android exposes the hotspot interface address through
  `IP.get_local_addresses()` on the host phone, and whether guest phones can reach the gateway while Android hotspot
  client isolation settings apply, is unknown; the host screen says "No hotspot found" if no private address is present.
- The host phone must keep the app in the foreground and the screen on. If Android suspends it, the relay stops
  and the round pauses, then ends after 60 s. Backgrounding or killing the host app ends the room.
- A guest phone that must keep mobile data off or auto-switch away from a no-internet hotspot may drop the connection;
  Android may ask whether to stay on a Wi-Fi without internet.
- Traffic is unencrypted plain ws:// on a private network; room code is the only gate.
- Android needs the INTERNET permission (already enabled) to listen and connect; no extra permission was added.
- Port is fixed at 8765. The manual address field accepts `ip` or `ip:port`.

Run the LAN test: `godot --headless --path . -s res://tests/network/local_relay_smoke.gd`.

The rest of this document describes the original hosted-relay implementation, still present but unused by the UI.

## Hosted relay (original design, not used)

Local implementation, not deployed or phone-verified. Solo and local pass-and-play still use
GameSession. Online uses OnlineSession, a host-authoritative subclass. No physics or scoring
calibration changes were made.

## Ownership and protocol

- `OnlineRoom`: connection, private room, readiness, frozen setup and in-memory reconnect token.
- `NetTransport`: Godot WebSocketPeer JSON transport; replaceable without moving gameplay into UI.
- `OnlineSession`: authenticated seat + monotonically increasing revision gates every command.
  Host calls existing GameSession methods for atomic commits, mulligans and turn changes.
- `NetCodec`: JSON-safe data codec restricted to ShotRequest, ShotResult, HoleState and RoundState.
- `relay/server.py`: Python WebSocket relay; assigns seats, enforces host-only events, limits rooms to
  four, checks readiness and content signature, forwards commands to host. Does not simulate golf.
- Host sends an immutable committed request plus consumed pool/score state. Clients replay locally.
  Host result replaces positions/scores/history; a slow client's animation may snap to that result.
- Setup freezes host physics, seed, course pars, wind overrides, hole-out radius, mulligans and stat
  visibility. Local developer controls are blocked online. Online rounds do not enter personal telemetry.
- App/content fingerprints reject different engine/build/data/local database combinations. Exported
  APK fingerprint compatibility is not yet device-tested.

## Current v1 limits

Live turns only. Host starts each hole and advances after hole completion. The active player
acknowledges their shot. A socket interruption pauses play for up to 60 seconds. The same running
app reconnects using an in-memory token and receives the host's state. If any player fails to
return, or explicitly leaves, the whole room ends. No host migration, kicking, replacement player,
async rounds, disk resume or server persistence. No retained next-turn shot plan.

The relay keeps rooms in memory: use one process/replica. A restart ends rooms. Production needs
TLS termination, connection/handshake limits at the reverse proxy, monitoring and an always-running
service. The relay has a 200-room cap, 40 messages/second/connection cap and 8 MiB message limit.
Full snapshots duplicate some history and will need incremental/deduplicated transfer for long rounds.
Do not claim load testing, security audit or production readiness.

## Run the relay

```sh
python -m pip install -r relay/requirements.txt
python relay/server.py
```

Or build the Dockerfile with `relay/` as context. `PORT` defaults to 8765. Put the service behind a
valid HTTPS/WebSocket reverse proxy. Configure `network/relay_url` in the local Godot project settings
or enter the `wss://` endpoint on the online connection screen. That screen stores address/name only
in `user://online.cfg`; reconnect tokens are not persisted. Local tests accept ws://127.0.0.1 or
ws://localhost only. Internet connections require wss://. No provider URL or credential is committed.
Android INTERNET permission is enabled in the existing export preset.

No public endpoint was provisioned, no container was deployed, and no APK was built in this task.

## Targeted checks observed

Installed Godot was **4.6.3**, despite the repo/brief stating **4.7**. Do not claim 4.7 validation.
Python websockets was 16.0 (pinned in relay requirements).

- Godot import and normal headless startup: no script errors.
- `tests/network/test_relay.py`: two protocol tests passed (four seats/capacity/readiness,
  authenticated sender identity, forged event rejection, resume, mismatched content/malformed JSON).
- `tests/integration/test_online_session.gd`: passed (out-of-turn, duplicate, spent footballer,
  guest mulligan, paused-round rejection, JSON state roundtrip).
- Existing `test_pass_and_play_alternates_turns_with_separate_scores`: passed.
- `tests/network/ui_smoke.gd`: actual connection page/lobby/online round start, then pass-and-play
  and solo starts passed headlessly. This is not visual/device QA.
- Two separate Godot processes through a real local WebSocket relay finished a short fixture hole
  after BOTH host and guest disconnected/reconnected. Final positions, scores, pool, history,
  turn and state matched exactly. This is not a real-course/full-round or external-network test.
- `git diff --check`: passed.

Focused rerun commands:

```sh
python tests/network/test_relay.py
godot --headless --path . -s res://tests/run_tests.gd -- --filter=online
godot --headless --path . -s res://tests/run_tests.gd -- --filter=pass_and_play
godot --headless --path . -s res://tests/network/ui_smoke.gd
# Start relay/server.py in another terminal first:
python tests/network/run_smoke.py
```

The broad physics/calibration/full-round suite was not run. Keep follow-up validation targeted to
integration edits; a real multi-phone round is the next substantial acceptance check.

## Combined rounds, mini seasons and picker sort online
- Host lobby has a format row: One course / Combined (course id `combo:a+b`, sent as the normal `course`) / Mini season (`rules.season_courses`, frozen with the rest of RoundConfig; `course` = the first one). `rules.order_by_stats` is also part of the frozen rules.
- Season: each phone records the finished course from the synced round states (`Season.record_course`), so standings are identical. The host's "Next course" sends `{kind:"season_next", course, pars, season}`; guests adopt the season state, point their setup at the new course and start a fresh `OnlineSession`. Verified headless only with a simulated guest (no real two-phone test).
