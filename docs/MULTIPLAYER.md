# Multiplayer implementation — 8 November 2026

## Direct LAN / hotspot play (current plan)

Owner decision: no hosted relay. 2 to 4 friends in the same room play over the same Wi-Fi, or over
one phone's Wi-Fi hotspot. The host phone runs the relay itself.

- `scripts/network/local_relay.gd` (`LocalRelay`, owned by the `App` autoload) is a GDScript port of
  `relay/server.py`: same JSON messages, seats, 6-character room codes, host-only events, readiness,
  4-seat cap, 200-room cap, 40 messages/s rate limit, 60 s reconnect grace. It uses `TCPServer` plus
  `WebSocketPeer.accept_stream()` polled from `_process` (no threads) on port 8765.
- Host: Online Multiplayer -> "Host on this phone". The relay starts and the host connects to itself via
  `ws://127.0.0.1:8765`. The screen and lobby show the phone's private IPv4 address(es)
  (`IP.get_local_addresses()`) and the room code. Guests: "Join", type host IP, port (8765), room code and name.
- `NetTransport` accepts plain `ws://` only to 127.x, 10.x, 172.16-31.x, 192.168.x, 169.254.x (and localhost).
  Anything public must be `wss://`. The hosted relay code path still exists but has no UI.
- OnlineRoom / OnlineSession / NetCodec are unchanged. The host phone's relay and host game share one app.

Honest limits (nothing here has been run on phones):
- Verified only headless on a desktop: relay + two clients in one process through a short fixture hole,
  including a guest disconnect/reconnect (`tests/network/local_relay_smoke.gd`). No Wi-Fi, hotspot,
  Android or multi-device test has been done.
- The host phone must keep the app in the foreground and the screen on. If Android suspends it, the relay stops
  and the round pauses, then ends after 60 s. Backgrounding or killing the host app ends the room.
- Hotspot: join the host's hotspot and use the host's address shown in the app (often 192.168.43.1 on Android
  hotspots; use whatever the app displays). Same Wi-Fi: both on one router, using the host's Wi-Fi address.
- Router "AP/client isolation" (common on guest Wi-Fi and some public networks) or a firewall can block
  phone-to-phone traffic; use the hotspot instead. Mobile data does not matter, no internet is needed.
- Traffic is unencrypted plain ws:// on a private network; room code is the only gate. Do not use on untrusted Wi-Fi.
- Android needs the INTERNET permission (already enabled) to listen and connect; no extra permission was added.
- Host must type or read out the IP; no discovery/QR yet. Port is fixed at 8765.

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
