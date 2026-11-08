class_name LocalRelay
extends Node
## GDScript port of relay/server.py that runs inside the host phone (TCPServer + WebSocketPeer),
## polled from _process. Same JSON protocol, seats, room codes, host-only events, readiness,
## caps and rate limits. Does not simulate golf. Plain ws:// on a private network only.

const PROTOCOL := 1
const MAX_ROOMS := 200
const MAX_CONNECTIONS := 64
const GRACE_MS := 60000
const RATE_LIMIT := 40
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const DEFAULT_PORT := 8765
const PREVIEW_MAX_CHARS := 600

class Peer extends RefCounted:
	var name := ""
	var conn: Conn = null
	var token := ""
	var ready := false
	var gone := 0

class Room extends RefCounted:
	var code := ""
	var fingerprint := ""
	var peers: Array = []
	var started := false
	var setup := {}

class Conn extends RefCounted:
	var ws: WebSocketPeer
	var room: Room = null
	var peer: Peer = null
	var window := 0
	var count := 0
	var born := 0

var server: TCPServer
var port := 0
var rooms := {}
var _conns: Array = []

func is_running() -> bool:
	return server != null and server.is_listening()

## Start listening on all interfaces. Returns OK or an Error code.
func start(listen_port: int = DEFAULT_PORT) -> int:
	stop()
	server = TCPServer.new()
	var err := server.listen(listen_port, "*")
	if err != OK:
		server = null
		return err
	port = listen_port if listen_port != 0 else server.get_local_port()
	return OK

func stop() -> void:
	for c: Conn in _conns:
		c.ws.close()
	_conns.clear()
	rooms.clear()
	if server != null:
		server.stop()
	server = null

func _exit_tree() -> void:
	stop()

func _process(_delta: float) -> void:
	if server == null:
		return
	while server.is_connection_available():
		var tcp := server.take_connection()
		if _conns.size() >= MAX_CONNECTIONS:
			tcp.disconnect_from_host()
			continue
		var c := Conn.new()
		c.ws = WebSocketPeer.new()
		c.ws.inbound_buffer_size = 8 * 1024 * 1024 + 1024
		c.ws.outbound_buffer_size = 16 * 1024 * 1024
		c.ws.max_queued_packets = 4096
		c.ws.accept_stream(tcp)
		c.born = Time.get_ticks_msec()
		c.window = c.born
		_conns.append(c)
	for c: Conn in _conns.duplicate():
		c.ws.poll()
		match c.ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while c.ws.get_ready_state() == WebSocketPeer.STATE_OPEN and c.ws.get_available_packet_count() > 0:
					_on_packet(c, c.ws.get_packet().get_string_from_utf8())
			WebSocketPeer.STATE_CLOSED:
				_drop(c)
			WebSocketPeer.STATE_CONNECTING:
				if Time.get_ticks_msec() - c.born > 10000:
					c.ws.close()
					_drop(c)
	var now := Time.get_ticks_msec()
	for room: Room in rooms.values():
		if rooms.get(room.code) != room:
			continue
		for p: Peer in room.peers:
			if p.conn == null and now - p.gone > GRACE_MS:
				_close_room(room, "A player did not reconnect within 60 seconds. Round ended.")
				break

func _drop(c: Conn) -> void:
	_conns.erase(c)
	var room := c.room
	var peer := c.peer
	if room != null and peer != null and peer.conn == c and rooms.get(room.code) == room:
		peer.conn = null
		peer.gone = Time.get_ticks_msec()
		_broadcast(room, _lobby(room))

func _send(c: Conn, data: Dictionary) -> void:
	if c != null and c.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		c.ws.send_text(JSON.stringify(data))

func _broadcast(room: Room, data: Dictionary) -> void:
	for p: Peer in room.peers:
		_send(p.conn, data)

func _lobby(room: Room) -> Dictionary:
	var players: Array = []
	var paused := false
	for p: Peer in room.peers:
		if p.conn == null:
			paused = true
		players.append({"name": p.name, "ready": p.ready, "connected": p.conn != null})
	return {"type": "lobby", "code": room.code, "started": room.started, "paused": paused, "players": players}

func _close_room(room: Room, reason: String) -> void:
	rooms.erase(room.code)
	_broadcast(room, {"type": "ended", "message": reason})
	for p: Peer in room.peers:
		if p.conn != null:
			p.conn.room = null
			p.conn.peer = null
			p.conn.ws.close()

func _new_code() -> String:
	var code := ""
	for i in 6:
		code += CODE_CHARS[randi() % CODE_CHARS.length()]
	return code

func _new_token() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()

func _on_packet(c: Conn, raw: String) -> void:
	var now := Time.get_ticks_msec()
	if now - c.window >= 1000:
		c.window = now
		c.count = 0
	c.count += 1
	if c.count > RATE_LIMIT:
		c.ws.close(1008, "Rate limit")
		return
	var err := _handle(c, raw)
	if err != "":
		_send(c, {"type": "error", "message": err})

## Returns an error message, or "" on success. Mirrors handler() in relay/server.py.
func _handle(c: Conn, raw: String) -> String:
	var msg = JSON.parse_string(raw)
	if not msg is Dictionary:
		return "Invalid message"
	var kind = msg.get("type")
	if c.room == null:
		var proto = msg.get("protocol")
		if not (proto is float or proto is int) or int(proto) != PROTOCOL:
			return "Incompatible app version"
		var name = msg.get("name", "Player")
		var fingerprint = msg.get("fingerprint", "")
		if not name is String or name.strip_edges().length() < 1 or name.strip_edges().length() > 24:
			return "Enter a name (1–24 characters)"
		if not fingerprint is String or fingerprint.length() != 64:
			return "Invalid game content signature"
		name = name.strip_edges()
		var room: Room
		var peer: Peer
		if kind == "host":
			if rooms.size() >= MAX_ROOMS:
				return "Relay is full"
			var code := _new_code()
			while rooms.has(code):
				code = _new_code()
			room = Room.new()
			room.code = code
			room.fingerprint = fingerprint
			peer = Peer.new()
			peer.name = name
			peer.conn = c
			peer.token = _new_token()
			room.peers.append(peer)
			rooms[code] = room
		elif kind == "join" or kind == "resume":
			var join_code = msg.get("code", "")
			if not join_code is String:
				return "Invalid code"
			room = rooms.get(join_code.to_upper())
			if room == null:
				return "Room not found"
			if fingerprint != room.fingerprint:
				return "Game files or footballer data differ. Install the same build and dataset."
			if kind == "resume":
				var token := str(msg.get("token", ""))
				peer = null
				for p: Peer in room.peers:
					if p.token == token:
						peer = p
						break
				if peer == null or peer.conn != null:
					return "Reconnect token is invalid or already in use"
				peer.conn = c
			else:
				if room.started or room.peers.size() >= 4:
					return "Room has started or is full"
				peer = Peer.new()
				peer.name = name
				peer.conn = c
				peer.token = _new_token()
				room.peers.append(peer)
				for p: Peer in room.peers:
					p.ready = false
		else:
			return "Host or join a room first"
		c.room = room
		c.peer = peer
		_send(c, {"type": "welcome", "code": room.code, "seat": room.peers.find(peer), "token": peer.token})
		_broadcast(room, _lobby(room))
		if kind == "resume" and room.started:
			_send(room.peers[0].conn, {"type": "resync", "seat": room.peers.find(peer)})
		return ""
	var cur: Room = c.room
	var me: Peer = c.peer
	var seat := cur.peers.find(me)
	if kind == "resync" and cur.started and seat > 0:
		_send(cur.peers[0].conn, {"type": "resync", "seat": seat})  # a guest asks the host to send the current state again
		return ""
	if kind == "ready" and not cur.started:
		me.ready = msg.get("ready") == true
		_broadcast(cur, _lobby(cur))
	elif kind == "start" and seat == 0 and not cur.started:
		var all_ready := cur.peers.size() >= 2
		for p: Peer in cur.peers:
			all_ready = all_ready and p.ready and p.conn != null
		if not all_ready:
			return "At least two connected, ready players are required"
		var setup = msg.get("setup")
		if not setup is Dictionary:
			return "Invalid round setup"
		cur.setup = setup
		cur.started = true
		_broadcast(cur, {"type": "start", "setup": setup, "players": _lobby(cur).players})
	elif kind == "intent" and cur.started:
		for p: Peer in cur.peers:
			if p.conn == null:
				return "Waiting for reconnection"
		var command = msg.get("command")
		if not command is Dictionary:
			return "Invalid command"
		_send(cur.peers[0].conn, {"type": "intent", "seat": seat, "command": command})
	elif kind == "event" and cur.started and seat == 0:
		# Seat is assigned by the relay, never supplied by a client.
		var target = msg.get("target", -1)
		var event := {"type": "event", "event": msg.get("event", {})}
		if (target is float or target is int) and int(target) == target and int(target) >= 0 and int(target) < cur.peers.size():
			_send(cur.peers[int(target)].conn, event)
		else:
			_broadcast(cur, event)
	elif kind == "preview" and cur.started:
		# Throttled, non-authoritative live-aim info from the active player. Forwarded to the other
		# seats tagged with the sender's relay-assigned seat; dropped silently if oversized/invalid.
		var data = msg.get("data")
		if data is Dictionary and JSON.stringify(data).length() <= PREVIEW_MAX_CHARS:
			var fwd := {"type": "preview", "seat": seat, "data": data}
			for p: Peer in cur.peers:
				if p != me:
					_send(p.conn, fwd)
	elif kind == "leave":
		_close_room(cur, "A player left the room.")
	else:
		return "Action is not allowed"
	return ""

## Private IPv4 addresses of this device (not loopback), for showing to the host.
static func private_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or not NetTransport.is_private_host(a):
			continue
		out.append(a)
	return out
