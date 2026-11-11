class_name SfxSynth
extends RefCounted
## Procedural sound effects: every cue is synthesised at runtime into a 16-bit mono AudioStreamWAV
## (no audio assets are bundled). Each cue uses a fixed RNG seed, so the same cue always sounds
## the same. Generation costs tens of ms per cue; SfxPlayer warms the cache on a worker thread.

const RATE := 22050

## Cue -> builder method. Aliases ("shot", "holed", "penalty") map the older Feedback cue names.
const BUILDERS := {
	"kick_soft": "_kick_soft", "kick": "_kick", "kick_hard": "_kick_hard", "putt": "_putt",
	"land_fairway": "_land_fairway", "land_rough": "_land_rough", "land_green": "_land_green",
	"land_sand": "_land_sand", "cup": "_cup", "flag": "_flag", "rim": "_rim", "tree": "_tree",
	"splash": "_splash", "cheer": "_cheer", "groan": "_groan", "applause": "_applause", "tap": "_tap",
}
const ALIASES := {"shot": "kick", "holed": "applause", "penalty": "groan"}

static var _cache: Dictionary = {}


static func resolve(cue: String) -> String:
	return String(ALIASES.get(cue, cue))


static func has_cue(cue: String) -> bool:
	return BUILDERS.has(resolve(cue))


static func is_cached(cue: String) -> bool:
	return _cache.has(resolve(cue))


static func stream(cue: String) -> AudioStreamWAV:
	var c := resolve(cue)
	if _cache.has(c):
		return _cache[c]
	var w := build(c)
	if w != null:
		_cache[c] = w
	return w


## Synthesise a cue without touching the cache (safe on a worker thread).
static func build(cue: String) -> AudioStreamWAV:
	var c := resolve(cue)
	if not BUILDERS.has(c):
		return null
	var s := SfxSynth.new()
	var samples: PackedFloat32Array = s.call(String(BUILDERS[c]))
	return _to_wav(samples)


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0
	for v in samples:
		peak = maxf(peak, absf(v))
	var g := 0.89 / peak if peak > 0.89 else 1.0
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


# ------------------------------------------------------------------ building blocks

var rng := RandomNumberGenerator.new()


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Noise through a one-pole low-pass (lp 0..1, smaller = darker) and optional high-pass.
func _noise(b: PackedFloat32Array, start: float, dur: float, amp: float, attack: float, decay: float,
		lp: float, hp: float = 0.0) -> void:
	var i0 := int(start * RATE)
	var n := int(dur * RATE)
	var y := 0.0
	var hy := 0.0
	var px := 0.0
	for k in n:
		var i := i0 + k
		if i >= b.size():
			break
		var t := float(k) / RATE
		var env := (minf(1.0, t / attack) if attack > 0.0 else 1.0) * exp(-t / decay)
		y += lp * (rng.randf_range(-1.0, 1.0) - y)
		var o := y
		if hp > 0.0:
			hy = hp * (hy + y - px)
			px = y
			o = hy
		b[i] += o * amp * env


## Sine with an exponential pitch glide f0 -> f1 and exponential decay.
func _tone(b: PackedFloat32Array, start: float, dur: float, amp: float, f0: float, f1: float,
		decay: float, attack: float = 0.002) -> void:
	var i0 := int(start * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	for k in n:
		var i := i0 + k
		if i >= b.size():
			break
		var t := float(k) / RATE
		var f := f0 * pow(f1 / f0, t / dur)
		ph += TAU * f / RATE
		b[i] += sin(ph) * amp * minf(1.0, t / attack) * exp(-t / decay)


# ------------------------------------------------------------------ cues

func _kick_base(power: float) -> PackedFloat32Array:
	rng.seed = 11
	var b := _buf(0.35)
	_tone(b, 0.0, 0.3, 0.9 * power, 150.0, 48.0, 0.07)  # leather thump
	_noise(b, 0.0, 0.03, 0.55 * power, 0.0, 0.008, 0.55)  # boot slap
	_noise(b, 0.0, 0.25, 0.12 * power, 0.01, 0.06, 0.08)  # air
	return b


func _kick_soft() -> PackedFloat32Array:
	return _kick_base(0.55)


func _kick() -> PackedFloat32Array:
	return _kick_base(0.8)


func _kick_hard() -> PackedFloat32Array:
	var b := _kick_base(1.0)
	rng.seed = 12
	_noise(b, 0.0, 0.45, 0.18, 0.02, 0.12, 0.25, 0.9)  # whoosh away
	return b


func _putt() -> PackedFloat32Array:
	rng.seed = 13
	var b := _buf(0.2)
	_tone(b, 0.0, 0.15, 0.45, 220.0, 120.0, 0.035)
	_noise(b, 0.0, 0.02, 0.35, 0.0, 0.005, 0.7)
	return b


func _land_fairway() -> PackedFloat32Array:
	rng.seed = 21
	var b := _buf(0.25)
	_tone(b, 0.0, 0.2, 0.7, 95.0, 55.0, 0.045)
	_noise(b, 0.0, 0.18, 0.4, 0.003, 0.04, 0.18)
	return b


func _land_rough() -> PackedFloat32Array:
	rng.seed = 22
	var b := _buf(0.32)
	_tone(b, 0.0, 0.2, 0.45, 80.0, 50.0, 0.04)
	_noise(b, 0.0, 0.3, 0.5, 0.01, 0.07, 0.35, 0.6)  # grass swish
	return b


func _land_green() -> PackedFloat32Array:
	rng.seed = 23
	var b := _buf(0.2)
	_tone(b, 0.0, 0.16, 0.6, 120.0, 70.0, 0.03)
	_noise(b, 0.0, 0.08, 0.25, 0.002, 0.02, 0.25)
	return b


func _land_sand() -> PackedFloat32Array:
	rng.seed = 24
	var b := _buf(0.45)
	_tone(b, 0.0, 0.15, 0.35, 70.0, 45.0, 0.03)
	_noise(b, 0.0, 0.42, 0.7, 0.015, 0.11, 0.5, 0.85)  # "pfff"
	return b


func _cup() -> PackedFloat32Array:
	rng.seed = 31
	var b := _buf(0.7)
	# a couple of rattles on the liner, then the hollow drop
	_tone(b, 0.0, 0.06, 0.35, 1650.0, 1500.0, 0.012)
	_noise(b, 0.0, 0.02, 0.25, 0.0, 0.004, 0.8)
	_tone(b, 0.07, 0.06, 0.3, 1320.0, 1250.0, 0.012)
	_noise(b, 0.07, 0.02, 0.2, 0.0, 0.004, 0.8)
	_tone(b, 0.16, 0.5, 0.8, 240.0, 150.0, 0.09)
	_tone(b, 0.16, 0.5, 0.25, 480.0, 300.0, 0.05)
	_noise(b, 0.16, 0.08, 0.3, 0.0, 0.02, 0.3)
	return b


func _flag() -> PackedFloat32Array:
	rng.seed = 32
	var b := _buf(0.9)
	for p in [[880.0, 0.5], [2390.0, 0.3], [4150.0, 0.18], [6020.0, 0.08]]:
		_tone(b, 0.0, 0.88, float(p[1]) * 0.6, float(p[0]), float(p[0]) * 0.995, 0.22)
	_noise(b, 0.0, 0.015, 0.4, 0.0, 0.004, 0.9)
	return b


func _rim() -> PackedFloat32Array:
	rng.seed = 33
	var b := _buf(0.12)
	_tone(b, 0.0, 0.1, 0.5, 1400.0, 1300.0, 0.015)
	_noise(b, 0.0, 0.015, 0.3, 0.0, 0.004, 0.8)
	return b


func _tree() -> PackedFloat32Array:
	rng.seed = 34
	var b := _buf(0.5)
	_tone(b, 0.0, 0.12, 0.5, 300.0, 200.0, 0.02)  # wooden knock
	_noise(b, 0.0, 0.45, 0.45, 0.02, 0.12, 0.6, 0.7)  # leaves
	return b


func _splash() -> PackedFloat32Array:
	rng.seed = 41
	var b := _buf(1.1)
	_tone(b, 0.0, 0.12, 0.6, 110.0, 60.0, 0.03)  # plop
	_noise(b, 0.0, 1.0, 0.8, 0.008, 0.18, 0.7, 0.8)  # spray
	_noise(b, 0.05, 0.9, 0.35, 0.05, 0.3, 0.15)  # wash
	for k in 7:  # bubbles
		var t0 := 0.15 + rng.randf() * 0.6
		var f := rng.randf_range(500.0, 1100.0)
		_tone(b, t0, 0.06, 0.12, f, f * 1.8, 0.02)
	return b


## Crowd bed: band-limited noise with a slow random "murmur" amplitude, shaped by an envelope.
func _crowd(b: PackedFloat32Array, amp: float, attack: float, hold: float, release: float, lp: float, hp: float) -> void:
	var y := 0.0
	var hy := 0.0
	var px := 0.0
	var m := 0.0
	var mt := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(1.0, t / attack) if t < attack + hold else exp(-(t - attack - hold) / release)
		if i % 400 == 0:
			mt = rng.randf_range(0.55, 1.0)
		m += 0.004 * (mt - m)
		y += lp * (rng.randf_range(-1.0, 1.0) - y)
		hy = hp * (hy + y - px)
		px = y
		b[i] += hy * amp * env * m


## A voice "ooh/woo": sawtooth-ish glide with vibrato, through a soft low-pass.
func _voice(b: PackedFloat32Array, start: float, dur: float, amp: float, f0: float, f1: float) -> void:
	var i0 := int(start * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	var y := 0.0
	var vib := rng.randf_range(4.5, 6.5)
	for k in n:
		var i := i0 + k
		if i >= b.size():
			break
		var t := float(k) / RATE
		var u := t / dur
		var f := lerpf(f0, f1, u) * (1.0 + 0.015 * sin(TAU * vib * t))
		ph = fmod(ph + f / RATE, 1.0)
		var saw := ph * 2.0 - 1.0
		y += 0.08 * (saw - y)
		var env := minf(1.0, t / 0.12) * minf(1.0, (dur - t) / 0.3)
		b[i] += y * amp * env


func _cheer() -> PackedFloat32Array:
	rng.seed = 51
	var b := _buf(2.6)
	_crowd(b, 0.9, 0.25, 0.9, 0.6, 0.5, 0.9)
	for k in 14:
		var f := rng.randf_range(260.0, 520.0)
		_voice(b, rng.randf() * 0.4, rng.randf_range(1.0, 1.9), 0.18, f, f * rng.randf_range(1.1, 1.35))
	b = _mix(b, _claps(2.6, 30.0, 0.5, 52))
	return b


func _groan() -> PackedFloat32Array:
	rng.seed = 61
	var b := _buf(1.8)
	_crowd(b, 0.5, 0.15, 0.4, 0.5, 0.25, 0.92)
	for k in 12:
		var f := rng.randf_range(170.0, 300.0)
		_voice(b, rng.randf() * 0.2, rng.randf_range(1.1, 1.6), 0.2, f * 1.05, f * 0.72)
	return b


func _applause() -> PackedFloat32Array:
	return _claps(2.4, 26.0, 0.9, 71)


func _claps(seconds: float, per_s: float, amp: float, seed_v: int) -> PackedFloat32Array:
	rng.seed = seed_v
	var b := _buf(seconds)
	var t := 0.0
	while t < seconds - 0.05:
		var env := minf(1.0, t / 0.2) * clampf((seconds - t) / (seconds * 0.6), 0.0, 1.0)
		_noise(b, t, 0.03, amp * env * rng.randf_range(0.4, 1.0), 0.0, 0.006, rng.randf_range(0.5, 0.85), 0.8)
		t += -log(maxf(rng.randf(), 1e-4)) / per_s
	return b


func _mix(a: PackedFloat32Array, c: PackedFloat32Array) -> PackedFloat32Array:
	for i in mini(a.size(), c.size()):
		a[i] += c[i]
	return a


func _tap() -> PackedFloat32Array:
	rng.seed = 81
	var b := _buf(0.06)
	_tone(b, 0.0, 0.05, 0.4, 1050.0, 950.0, 0.012)
	return b
