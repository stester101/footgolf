"""Private Foot Golf relay. Run behind a TLS reverse proxy in production."""
import asyncio
import json
import os
import secrets
import time
from dataclasses import dataclass, field
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

PROTOCOL = 1
ROOMS = {}
MAX_ROOMS = 200
GRACE_SECONDS = 60

@dataclass
class Peer:
    name: str
    socket: object
    token: str = field(default_factory=lambda: secrets.token_urlsafe(32))
    ready: bool = False
    gone: float = 0

@dataclass
class Room:
    code: str
    fingerprint: str
    peers: list = field(default_factory=list)
    started: bool = False
    setup: dict = field(default_factory=dict)

async def send(ws, data):
    if ws is not None:
        try:
            await ws.send(json.dumps(data, allow_nan=False, separators=(",", ":")))
        except ConnectionClosed:
            pass

async def broadcast(room, data):
    await asyncio.gather(*(send(p.socket, data) for p in room.peers))

def lobby(room):
    return {"type": "lobby", "code": room.code, "started": room.started,
            "paused": any(p.socket is None for p in room.peers),
            "players": [{"name": p.name, "ready": p.ready, "connected": p.socket is not None}
                        for p in room.peers]}

async def close_room(room, reason):
    ROOMS.pop(room.code, None)
    await broadcast(room, {"type": "ended", "message": reason})
    await asyncio.gather(*(p.socket.close() for p in room.peers if p.socket is not None))

async def expire(room, peer, gone):
    await asyncio.sleep(GRACE_SECONDS)
    if ROOMS.get(room.code) is room and peer.socket is None and peer.gone == gone:
        await close_room(room, "A player did not reconnect within 60 seconds. Round ended.")

async def handler(ws):
    room = None
    peer = None
    window, count = time.monotonic(), 0
    try:
        async for raw in ws:
            now = time.monotonic()
            if now - window >= 1:
                window, count = now, 0
            count += 1
            if count > 40:
                await ws.close(1008, "Rate limit")
                break
            try:
                msg = json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
                if not isinstance(msg, dict):
                    raise ValueError()
                kind = msg.get("type")
                if room is None:
                    if msg.get("protocol") != PROTOCOL:
                        raise ValueError("Incompatible app version")
                    name = msg.get("name", "Player")
                    fingerprint = msg.get("fingerprint", "")
                    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 24:
                        raise ValueError("Enter a name (1–24 characters)")
                    if not isinstance(fingerprint, str) or len(fingerprint) != 64:
                        raise ValueError("Invalid game content signature")
                    if kind == "host":
                        if len(ROOMS) >= MAX_ROOMS:
                            raise ValueError("Relay is full")
                        code = "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(6))
                        while code in ROOMS:
                            code = "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(6))
                        room = Room(code, fingerprint)
                        peer = Peer(name.strip(), ws)
                        room.peers.append(peer)
                        ROOMS[code] = room
                    elif kind in ("join", "resume"):
                        code = msg.get("code", "")
                        if not isinstance(code, str):
                            raise ValueError("Invalid code")
                        candidate = ROOMS.get(code.upper())
                        if candidate is None:
                            raise ValueError("Room not found")
                        if fingerprint != candidate.fingerprint:
                            raise ValueError("Game files or footballer data differ. Install the same build and dataset.")
                        if kind == "resume":
                            found = next((p for p in candidate.peers if secrets.compare_digest(p.token, str(msg.get("token", "")))), None)
                            if found is None or found.socket is not None:
                                raise ValueError("Reconnect token is invalid or already in use")
                            peer = found
                            peer.socket = ws
                        else:
                            if candidate.started or len(candidate.peers) >= 4:
                                raise ValueError("Room has started or is full")
                            peer = Peer(name.strip(), ws)
                            candidate.peers.append(peer)
                            for p in candidate.peers:
                                p.ready = False
                        room = candidate
                    else:
                        raise ValueError("Host or join a room first")
                    await send(ws, {"type": "welcome", "code": room.code, "seat": room.peers.index(peer), "token": peer.token})
                    await broadcast(room, lobby(room))
                    if kind == "resume" and room.started:
                        await send(room.peers[0].socket, {"type": "resync", "seat": room.peers.index(peer)})
                    continue
                seat = room.peers.index(peer)
                if kind == "ready" and not room.started:
                    peer.ready = msg.get("ready") is True
                    await broadcast(room, lobby(room))
                elif kind == "start" and seat == 0 and not room.started:
                    if len(room.peers) < 2 or not all(p.ready and p.socket is not None for p in room.peers):
                        raise ValueError("At least two connected, ready players are required")
                    setup = msg.get("setup")
                    if not isinstance(setup, dict):
                        raise ValueError("Invalid round setup")
                    room.setup = setup
                    room.started = True
                    await broadcast(room, {"type": "start", "setup": setup, "players": lobby(room)["players"]})
                elif kind == "intent" and room.started:
                    if any(p.socket is None for p in room.peers):
                        raise ValueError("Waiting for reconnection")
                    command = msg.get("command")
                    if not isinstance(command, dict):
                        raise ValueError("Invalid command")
                    await send(room.peers[0].socket, {"type": "intent", "seat": seat, "command": command})
                elif kind == "event" and room.started and seat == 0:
                    # Seat is assigned by the relay, never supplied by a client.
                    target = msg.get("target", -1)
                    event = {"type": "event", "event": msg.get("event", {})}
                    if isinstance(target, int) and 0 <= target < len(room.peers):
                        await send(room.peers[target].socket, event)
                    else:
                        await broadcast(room, event)
                elif kind == "leave":
                    await close_room(room, "A player left the room.")
                    break
                else:
                    raise ValueError("Action is not allowed")
            except (ValueError, TypeError, KeyError) as exc:
                await send(ws, {"type": "error", "message": str(exc) or "Invalid message"})
    except ConnectionClosed:
        pass
    finally:
        if room is not None and peer is not None and peer.socket is ws and ROOMS.get(room.code) is room:
            peer.socket = None
            peer.gone = time.monotonic()
            await broadcast(room, lobby(room))
            asyncio.create_task(expire(room, peer, peer.gone))

async def main():
    port = int(os.environ.get("PORT", "8765"))
    async with serve(handler, "0.0.0.0", port, max_size=8 * 2**20, max_queue=4, ping_interval=15, ping_timeout=20):
        print(f"Foot Golf relay listening on {port}", flush=True)
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
