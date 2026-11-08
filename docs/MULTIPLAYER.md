# Relay multiplayer implementation — 8 November 2026

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
