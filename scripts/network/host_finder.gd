class_name HostFinder
extends Node
## Finds the host phone on the guest's own hotspot link, so nobody has to type an IP.
## Candidate addresses are derived from this phone's own addresses (x.y.z.1 of each private /24, the
## usual hotspot gateway) plus well-known hotspot gateways. Each is probed in parallel with a short
## WebSocket handshake to the relay port; whatever answers is reported. Polled from _process.

signal found(ip: String)
signal finished(hosts: Array)

const KNOWN_GATEWAYS := ["192.168.43.1", "192.168.49.1", "172.20.10.1", "192.168.137.1"]
const PROBE_TIMEOUT_MS := 1800

class Probe extends RefCounted:
	var ip := ""
	var ws: WebSocketPeer
	var started := 0
	var done := false

var port := 8765
var searching := false
var results: Array = []
var _probes: Array[Probe] = []

## Pure and unit-testable. Order: gateways on this phone's own subnets first, then known hotspot
## gateways. Own addresses, loopback, link-local, public and IPv6 are never candidates.
static func candidate_hosts(local_addresses: PackedStringArray) -> PackedStringArray:
	var own := {}
	var out := PackedStringArray()
	for a in local_addresses:
		if _is_lan_ipv4(a):
			own[a] = true
	for a in local_addresses:
		if not _is_lan_ipv4(a):
			continue
		var p := a.split(".")
		var gw := "%s.%s.%s.1" % [p[0], p[1], p[2]]
		if not own.has(gw) and not out.has(gw):
			out.append(gw)
	for gw in KNOWN_GATEWAYS:
		if not own.has(gw) and not out.has(gw):
			out.append(gw)
	return out

static func _is_lan_ipv4(a: String) -> bool:
	if not a.is_valid_ip_address() or a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
		return false
	return NetTransport.is_private_host(a)

## Which of this phone's addresses to show the host as "the hotspot address": a known hotspot
## gateway first, then any x.y.z.1, then the first private address. "" if none.
static func best_host_address(local_addresses: PackedStringArray) -> String:
	var lan: Array = []
	for a in local_addresses:
		if _is_lan_ipv4(a):
			lan.append(a)
	for a in lan:
		if KNOWN_GATEWAYS.has(a):
			return a
	for a in lan:
		if String(a).ends_with(".1"):
			return a
	return "" if lan.is_empty() else String(lan[0])

func start(addresses: PackedStringArray = PackedStringArray(), probe_port: int = 8765) -> int:
	cancel()
	port = probe_port
	var list := addresses if not addresses.is_empty() else candidate_hosts(IP.get_local_addresses())
	results.clear()
	searching = true
	for ip in list:
		var p := Probe.new()
		p.ip = ip
		p.ws = WebSocketPeer.new()
		p.started = Time.get_ticks_msec()
		if p.ws.connect_to_url("ws://%s:%d" % [ip, port]) != OK:
			p.done = true
		_probes.append(p)
	if _probes.all(func(p: Probe) -> bool: return p.done):
		_finish.call_deferred()
	return list.size()

func cancel() -> void:
	for p in _probes:
		if p.ws != null: p.ws.close()
	_probes.clear()
	searching = false

func _finish() -> void:
	if not searching: return
	searching = false
	_probes.clear()
	finished.emit(results.duplicate())

func _process(_delta: float) -> void:
	if not searching:
		return
	var now := Time.get_ticks_msec()
	var open := 0
	for p in _probes:
		if p.done:
			continue
		p.ws.poll()
		var st := p.ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			p.done = true
			p.ws.close()
			results.append(p.ip)
			found.emit(p.ip)
		elif st == WebSocketPeer.STATE_CLOSED or now - p.started > PROBE_TIMEOUT_MS:
			p.done = true
			p.ws.close()
		else:
			open += 1
	if open == 0:
		_finish()
