class_name NetTransport
extends Node
## JSON transport boundary; no gameplay decisions belong here.
signal received(data: Dictionary)
signal connected
signal disconnected
signal failed(reason: String)

var socket: WebSocketPeer
var _was_open := false
var _started := 0

func open(url: String) -> void:
	close()
	if not url.begins_with("wss://") and not url.begins_with("ws://127.0.0.1:") and not url.begins_with("ws://localhost:"):
		failed.emit("Use a secure wss:// relay address.")
		return
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 16777216
	socket.outbound_buffer_size = 16777216
	_started = Time.get_ticks_msec()
	var err := socket.connect_to_url(url)
	if err != OK:
		socket = null
		failed.emit("Cannot connect to relay (%d)." % err)

func send(data: Dictionary) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var err := socket.send_text(JSON.stringify(data))
		if err != OK:
			failed.emit("Could not send network message (%d)." % err)

func close() -> void:
	if socket != null:
		socket.close()
	socket = null
	_was_open = false

func _process(_delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			connected.emit()
		while socket != null and socket.get_available_packet_count() > 0:
			var data = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if data is Dictionary:
				received.emit(data)
	elif state == WebSocketPeer.STATE_CLOSED or (state == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() - _started > 15000):
		close()
		disconnected.emit()
