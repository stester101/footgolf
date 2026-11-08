# TV view (browser spectator) proposal

Status: proposal only, no code changed. Date: 8 November 2026. Replaces `docs/TV_COMPANION_PROPOSAL.md`, whose
hosted-relay and HTTPS assumptions are outdated (the relay now runs inside the host phone on a hotspot, ws:// only).
Labels: [observed] read in this repo, [opinion] my judgement, [unverified] browser/Android/Godot behaviour from
general knowledge that has NOT been tested here. No web search was used; no external sources are cited.

## 0. Goal and constraints

A Chromebook on the same hotspot opens a page and shows the live match, landscape, TV-golf style: wide hole shot,
ball-following camera, tracer, scoreboard bug, distance to pin, hole info and wind, slow-mo replay, leaderboard
between holes. Read-only. No internet, no server, no extra install on the Chromebook.

Facts about the current code that shape everything:
- [observed] `LocalRelay` listens on TCP 8765 and hands each socket straight to `WebSocketPeer.accept_stream()`.
  It forwards: `lobby`, `start{setup}`, host `event`s, `preview`. Seats are capped at 4; `fingerprint` (64-char hash
  of game files + footballer DB) must match to join.
- [observed] The host's `event` carries `snapshot()` = round state, **pool snapshot**, full **history**, `selected`,
  `last_result`, `request`. Forwarding this to a spectator would leak the used-footballer pool and stats. Spectators
  must get a different, host-built message.
- [observed] Clients do not receive the ball path. They re-simulate the shot locally from `ShotRequest`
  (`apply_snapshot` -> `_plan_shot` -> `_launch`), relying on deterministic `BallSim` (fixed `dt = 1/240`).
  `BallSim.trail` holds a position every 4th step (60 Hz) and `RoundController._update_trail` already draws it.
- [observed] `ShotResult` already has: footballer name/nationality, mode (Caps/Goals), style, stat_value, trajectory,
  spin, aim, wind, start/final pos, carry/roll/total, max_height, bounces, hazard, penalty, remaining_m, holed.
- [observed] Hole geometry is plain JSON (`data/holes/*.json`, 280 KB for all 17): tee, pin, fairway polylines with
  width, green/bunker ellipses, water, bounds, terrain bumps, tree lines, wind, par, yards. `HoleDefinition` is analytic.
- [observed] `preview` messages (aim, trajectory, spin, footballer id) are forwarded only to *other seats*, ~4/s.
- [observed] `NetTransport` allows ws:// only to private IPv4 literals; no test on real phones has been done.

## 1. Options

### A) Godot HTML5 export as spectator client
Real 3D course, reuses `CourseView`, `CameraRig`, replay code.
- Size/load [unverified]: Godot 4 web builds are typically ~10 MB (compressed) engine wasm plus the project pack.
  Served from a phone over hotspot Wi-Fi with no compression, expect tens of seconds first load; the footballer
  DB, textures and all 17 holes would be in the pack.
- Threads [unverified]: a threaded web export needs cross-origin isolation (`Cross-Origin-Opener-Policy`,
  `Cross-Origin-Embedder-Policy` headers, and a secure context). A plain `http://192.168.x.x` page is NOT a secure
  context, so SharedArrayBuffer is unavailable; a single-threaded export would be required (Godot 4.3+ offers one;
  confirm for 4.7). Plain-HTTP delivery also blocks service workers.
- WebGL [unverified]: Godot 4 web uses WebGL2 with the Compatibility renderer; the game's shaders/terrain would
  need testing on the actual Chromebook GPU. Low-end ARM/Celeron Chromebooks may hold only 20-30 fps.
- Needs web-export templates (the project currently only exports Android) and a new export preset, plus a
  spectator mode inside the game (not built; the game code assumes a seat).
- Fingerprint: the web build would carry the same data, so it matches, but it also ships the full footballer database to a spectator.
- Effort 8-15 days, risk high (load time, perf, headers, delivery from a phone). [opinion] Best look, worst fit now.

### B) Lightweight JS spectator page (recommended)
One static HTML file (~100-200 KB with inline JS/CSS and, optionally, the 17 hole JSONs) rendering with Canvas 2D or
a tiny WebGL/three.js scene, fed by new `tv` messages. Download is instant even on hotspot; works offline; runs fine
on any Chromebook. Cost: a second renderer (no reuse of `CourseView`), and a protocol to keep in sync.
- Look [opinion]: 2.5D "TV coverage" is achievable in Canvas with a perspective-projected ground plane, painted
  fairway/green/bunker/water polygons from the hole JSON, sprite trees, and animated ball with shadow and height.
  With three.js (vendored locally, ~600 KB; no CDN offline) a genuine 3D flyover is possible at higher effort.
- Effort: TV Lite 2D 5-8 days; 2.5D broadcast look 10-15 days; three.js 3D 15-25 days.

### C) Cast/mirror a phone
No code. [opinion] Poor fit: shows one player's UI incl. the picker; portrait; no tracer/camera work;
Android casting may need a Google Home/Chromecast device on the same network, which a hotspot may not provide [unverified].
Acceptable only as a stop-gap.

## 2. Delivering the page with no internet and no server

The Chromebook only needs to open `http://<hotspot-ip>:<port>/`. The host screen already shows the best hotspot
address (`best_host_address()`); it can add a line "TV: http://192.168.43.1:8766". Typing is acceptable. [opinion]

Options:
1. **Plain HTTP from the host phone (recommended).** Page and WebSocket share the same host, so no mixed content.
   [unverified] A page loaded over http from a private IP may open `ws://` to a private IP; Chrome blocks `ws://` from
   `https` pages (mixed content), and Private Network Access restrictions target public->private requests, not
   private->private. Test on the actual Chromebook before building more.
2. Hosting the page on the internet (https): [unverified, fairly confident] blocked, an https page cannot open
   `ws://192.168...` (mixed content; `ws://localhost` is the exemption). Also needs internet, which the hotspot lacks. Rejected.
3. Same port 8765 for both: the relay would have to read the first bytes to tell an HTTP GET from a WebSocket
   upgrade. [unverified] `WebSocketPeer.accept_stream()` reads the stream itself and `StreamPeerTCP` has no peek, so the
   request cannot be inspected then handed over. Not practical. **Use a second `TCPServer` on port 8766.**

GDScript needed (small, ~80-120 lines, new `scripts/network/tv_http.gd`, polled from `_process` like the relay):
- `TCPServer.listen(8766, "*")`; per connection read bytes until `\r\n\r\n` (cap ~4 KB, 5 s timeout, max ~8 connections).
- Respond to `GET /` with `HTTP/1.1 200`, `Content-Type: text/html; charset=utf-8`, `Content-Length`, `Connection: close`,
  `Cache-Control: no-store`, body from `FileAccess.get_file_as_string("res://web/tv.html")`. Optionally `GET /hole/<n>.json`
  from `res://data/holes/` so the page always matches the installed build. Anything else -> 404.
- Write with `put_data`; a 200 KB page may need a loop over partial writes (`put_partial_data`).
- Export: add `*.html` to the Android preset's `include_filter` (non-resource files are otherwise stripped).
  [unverified] confirm in the built APK with `verify_apk.sh`.
- Android limits [unverified]: same as the relay: app in foreground, screen on; INTERNET permission already covers
  listening; ports above 1024 need no permission. Hotspot client isolation could block the Chromebook, as for guests.
  HTTP/WS are clear-text; the room code is the only gate (page asks for it).
- Serve only while hosting, behind a "Show on TV" toggle, tied to the `LocalRelay` lifecycle.

## 3. Protocol additions (relay + OnlineSession)

- **Role**: `{"type":"join","role":"spectator","code":"ABC123","protocol":1,"name":"TV"}`. Spectator skips the
  fingerprint (a browser cannot compute it) but needs a valid room code. Welcome returns `{"seat":-1,"role":"spectator"}`.
  Spectators are not in `room.peers`: they never affect readiness, the 4-seat cap, pause or the 60 s grace. Keep them in `room.spectators`.
- **Read-only**: all inbound messages from spectators rejected except `ping`. The relay forwards nothing from spectators.
- **Cap**: 2 spectators per room (configurable, max 4); excess -> `error "Spectator limit"`. Allowed before and after round start.
- **Late join**: the relay caches the last `tv` state from the host and sends it on join.
- **Privacy**: the relay must not forward `event`/`preview` raw to spectators. The host (OnlineSession) emits a separate
  `{"type":"tv", ...}` message (host seat only) which the relay sends to spectators only. Allowed fields: hole id, par,
  yards, wind, per-player name/colour/strokes/to-par, turn, state, reduced aim info (bearing, trajectory, spin, mode) while
  aiming; after Take Shot: footballer name, nationality, mode, stat value (follow phone behaviour: only when
  `rules.show_stats` or once the ball stopped [opinion]), ball path samples, result summary. Never: pool contents, ids of
  unplayed footballers, DB records, raw history, `selected`.
  Add a test that a spectator never receives `pool`, `history`, `selected`.
- **Preview for TV**: the raw `preview` contains the footballer id before Take Shot; do not forward it. The host re-publishes a
  reduced version in `tv`.
- **Version**: add `tv_protocol`; page shows "update the app" on mismatch. `relay/server.py` stays untouched (unused).

## 4. Cinematic camera and data

Ball in flight:
- **Trajectory samples (recommended).** On commit the host already has the sim result. Include `trail` (60 Hz), quantised
  to centimetres as ints, thinned where flat: about 300-600 points, roughly 5-9 KB JSON per shot [estimate from
  240 Hz / 4 and ~10 s of motion], sent once. The page interpolates, so slow-mo and replay are exact (bounces, trees,
  water). Needs one getter on `GameSession`/`BallSim` and the message; the simulation is untouched.
- Re-simulating in JS/GDScript: needs a port of `BallSim`, terrain, surfaces, trees, hazards and `ShotCalculator`; risk of
  drift from the locked calibration. Rejected [opinion].
- Fallback: if samples are absent, draw a parabola from start via `carry_m` and `max_height_m` to final pos.

Auto-director (state machine on the page driven by `tv` messages):
1. Hole intro (5 s): high wide flyover tee->green with hole name, par, yards, wind arrow, leaderboard bug.
2. Aiming: wide shot from behind/above the tee with aim line (reduced preview); player/footballer bug appears only after the shot is committed.
3. Ball in flight: chase camera behind, lead the target, pull back with the apex, coloured tracer; cut to a landing-area
   camera for the last ~20 % of flight; follow slowly through bounce and roll.
4. At rest: hold 2 s, show distance to pin (m/yd/ft), lie, penalty text; slow-mo (0.25x) side-angle replay for notable
   shots (holed, hazard, many bounces, long drive).
5. Green close-up when remaining < ~25 m or on the green; optional split picture-in-picture tee | green.
6. Hole complete: scorecard/leaderboard (strokes, to-par, per-hole), then next-hole intro.
7. Idle/paused: "Waiting for player" slate. Optional keyboard override (wide/follow/overhead); no input ever reaches the game.

Overlays [opinion]: lower-third bug (player colour bar, name, footballer + flag, Caps/Goals stat, Flight/Roll,
trajectory chip, spin), hole card, wind dial, distance to pin, result banner ("Water, +1 penalty"). Keep 5 % safe margins for TV overscan.

## 5. Staged plan (rough, one developer, excluding device-test time)

0. **Feasibility spike (0.5-1 d)**: a static HTML page opening `ws://` to the relay from the actual Chromebook
   (served by a tiny responder). Confirms the mixed-content/PNA assumptions. Do this first.
1. **TV Lite MVP (6-9 d)**:
   - Relay: spectator role, cap, `tv` forward, cached state, tests (1-1.5 d).
   - `OnlineSession`: `tv_payload()` on commit/hole change/aim, reduced preview, trail export (1.5-2 d).
   - `tv_http.gd` on port 8766 + "Show on TV" host UI + `res://web/tv.html` in export filter (1-1.5 d).
   - Page: join by code, landscape 2D hole drawn from hole JSON, ball animated along the trail, tracer, scoreboard bug,
     distance to pin, hole info, wind arrow, between-hole leaderboard, reconnect with backoff (3-4 d).
2. **Broadcast polish (5-8 d)**: 2.5D perspective ground, follow camera, auto-director, slow-mo replay, lower-thirds.
3. **Optional 3D (10-20 d)**: three.js (vendored) or Godot web export (option A) if the 2.5D look is not enough.
No change to rules, physics or scoring in any stage.

Tests: extend `tests/network/local_relay_smoke.gd` (spectator joins, cannot send, never receives pool); loopback test for the
HTTP responder; page tested against a mock WebSocket (a `docs/tv_prototype/` can be added later; not added now).

## 6. Risks

- Hotspot client isolation or Chromebook Wi-Fi behaviour [unverified] might block the TV; same exposure as guests.
- Host phone load (relay + HTTP + sim + rendering, battery, heat): send `tv` messages on change only.
- Privacy leak by reusing snapshots: separate `tv` message plus a test.
- Version drift: serve the page from the app itself so it always matches the installed build; `tv_protocol` check.
- Clear-text HTTP/WS on the hotspot; the room code is the only gate.
- Nothing here has been run: no Chromebook, hotspot or Android test.

## 7. Open questions for the owner

1. Which Chromebook model and TV resolution (decides 2D vs three.js)?
2. Is typing `http://192.168.x.x:8766` acceptable, or do you want something easier?
3. Footballer and stat on the TV only after Take Shot (my default), or also while the player is choosing?
4. Show Caps/Goals numbers on the TV even when "show stats" is off for phones?
5. Is 2D/2.5D acceptable for the first version, or is a true 3D course view required (+10-20 days)?
6. Auto-director only, or also keyboard camera control? Replays for every shot or only notable ones?
7. How many spectators (one TV, or friends' browsers too)? Need a PIN beyond the room code?
8. Should the TV keep a fixed address and re-join automatically when the host starts a new room (new code)?
9. Generic crowd sound on the TV? Player colours fixed per seat or chosen?
