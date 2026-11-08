# TV companion (spectator view) proposal

Status: proposal only. Nothing in the code has been changed for this.
Date: 8 November 2026. Based on `docs/MULTIPLAYER.md`, `docs/ARCHITECTURE.md` and the top of `relay/server.py`.

## Goal

Two friends each play on their own phone with the normal game UI, using the existing online relay.
The owner opens a browser on a Chromebook plugged into a TV and watches the match as a spectator.
The spectator must never be able to act, and must not see information a player should not see yet.

## What exists today

- The relay (`relay/server.py`) assigns seats, forwards host-only events, and broadcasts room state
  (`lobby` messages and round state). Rooms hold up to four seats. There is no read-only seat yet.
- Clients join by room code. A seat is authenticated by a token.
- Online rounds are host-authoritative: the host runs `GameSession` and sends committed shots and
  snapshots. Clients replay locally.
- Stats are hidden in normal play until a ball stops, and the picker is alphabetical. The relay sends
  full state snapshots, which include shot history, so a spectator feed must be filtered.

## Options compared

**a) Godot Web export, joined as a spectator.**
Export the same game to HTML5 and run it in the Chromebook browser with a spectator flag. It shows the
real 3D course and the same UI, so the TV view matches the phones.
Cons: the export is large (likely tens of MB), and the page must load the whole engine on a Chromebook.
Web export needs specific browser features and a serving setup. It also runs full game code for a
viewer who only needs a picture. Effort is moderate to high, and performance on the target Chromebook is
unknown until tested.

**b) Lightweight HTML/JS spectator page.** (Recommended)
A small static page, a few hundred lines of plain JavaScript, opens a WebSocket to the relay as a
read-only spectator. It draws a simple top-down 2D view of the hole (fairway, rough, bunkers, water,
green, cup, tree markers, ball positions) plus a scoreboard and the last shot line.
Pros: tiny download, works in any browser, easy to make large and readable on a TV, no engine on the
Chromebook. The 2D hole layout can be read from the same hole JSON the game uses.
Cons: not the 3D look. The page must be written and kept in step with the protocol.

**c) Screen mirroring or casting the phone.** No code.
Cons: the TV would show whatever is on one phone, including the footballer picker and the other
player's private choices, and it is small text on a big screen. It does not show both players at once.
Useful only as a stop-gap for a single phone.

## Recommendation: option b

It is the smallest workable path, it runs on any Chromebook, and it keeps spectator data separate from
game logic. The page only reads messages; it never decides scores or consumes footballers, which matches
the rule that UI never mutates authoritative state. Option a can be revisited later if the owner wants
the 3D course on the TV.

## Changes needed

**Relay protocol**
- Join message gets a role field: `player` (default, today's behaviour) or `spectator`.
- Spectators join with the room code only. They receive `lobby` and round-state broadcasts, and their
  inbound messages are rejected except a ping.
- Cap spectators per room (for example 2 to 4). Spectators do not count toward the four player seats and
  do not affect readiness, pause or the 60-second reconnect rule.
- Spectators get a filtered "tv" snapshot: positions, scores, strokes, current turn, last shot summary,
  hole layout reference. No footballer pool contents, no picker data, no hidden stats while a ball is
  moving. The host should send this view once per change; the relay forwards it.

**App (Godot)**
- Setup/lobby screen gets a "Show on TV" action that displays the room code and the spectator page address.
- The host or either player can open this; no gameplay UI changes.
- Round-state messages gain the small extra fields the TV view needs (hole layout id, last shot summary).

**Spectator page**
- Single static HTML file with inline JavaScript and CSS, served over HTTPS from the same reverse proxy
  as the relay. It asks for the room code, connects with `wss://`, and renders.

## Rough effort

1. Relay: spectator role, caps, filtered broadcasts, tests in `tests/network/test_relay.py`. About 1 to 2 days.
2. App: spectator snapshot fields and "Show on TV" screen. About 1 to 2 days.
3. Spectator page: 2D hole renderer from hole JSON, scoreboard, reconnect handling. About 3 to 5 days.
4. Hosting: serve the page next to the relay, test on the real Chromebook and TV. About 1 day.
5. Real multi-phone round watched on the TV: the acceptance check. Also needed for the online feature in general.

## Risks

- **Hidden information leak.** A spectator feed built from the full host snapshot would expose picker
  and stat information. Mitigation: the relay builds a separate filtered view, and a test asserts that
  spectators never receive pool or stat fields.
- **Web export size and speed (option a only).** Not an issue for option b, but it is the main reason
  it is not recommended now.
- **Hosting.** Internet play needs `wss://` behind a valid TLS reverse proxy. The relay is in-memory,
  single-process, and has not been deployed or load-tested. The TV page depends on that same service
  being up.
- **Godot version.** The local run used Godot 4.6.3, while the repo requires 4.7. Validate under 4.7
  before any build.
- **Protocol drift.** The page must track the relay's message shapes. Version the spectator messages
  under the existing `PROTOCOL` number.
- **Reconnect on TV.** A Chromebook that sleeps must reconnect on its own; the page should retry with
  backoff and show a clear "waiting for players" state.

## Open questions for the owner

1. Is the TV page allowed for anyone with the room code, or should it need a second PIN?
2. Should the TV show the 2D top-down view only, or also a 3D flyover of the hole?
3. How many spectators per room (one Chromebook, or a few phones too)?
4. Should the TV show footballer names after each shot, or only strokes and positions?
5. Who hosts the relay and the spectator page (domain, provider, budget)?
6. Is the 2D hole view acceptable for the first version, or is the 3D look needed on day one?
