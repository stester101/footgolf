class_name SfxPlayer
extends Node
## Small polyphonic player for SfxSynth cues. Registers itself as Feedback.player while in the tree,
## so every Feedback.sfx() call site plays through it. Warms the synth cache on a worker thread
## (a cue needed before that finishes is built on demand).

const VOICES := 8

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _task := -1
var _built: Dictionary = {}


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	Feedback.player = self
	var todo: Array = []
	for c in SfxSynth.BUILDERS.keys():
		if not SfxSynth.is_cached(c):
			todo.append(c)
	if todo.is_empty():
		set_process(false)
		return
	_task = WorkerThreadPool.add_task(func() -> void:
		var out := {}
		for c in todo:
			out[c] = SfxSynth.build(c)
		_built = out)


func _exit_tree() -> void:
	if Feedback.player == self:
		Feedback.player = null
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_install()


func _process(_d: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_install()
	if _task < 0:
		set_process(false)


func _install() -> void:
	for c in _built.keys():
		if not SfxSynth._cache.has(c) and _built[c] != null:
			SfxSynth._cache[c] = _built[c]
	_built = {}


## gain: linear 0..1 (already includes the volume setting); pitch: playback-rate multiplier.
func play(cue: String, gain: float = 1.0, pitch: float = 1.0) -> void:
	if gain <= 0.001:
		return
	var s := SfxSynth.stream(cue)
	if s == null:
		return
	# prefer a free voice; otherwise steal round-robin
	var p: AudioStreamPlayer = null
	for q in _players:
		if not q.playing:
			p = q
			break
	if p == null:
		p = _players[_next]
		_next = (_next + 1) % _players.size()
	p.stream = s
	p.volume_db = linear_to_db(clampf(gain, 0.0, 1.5))
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.play()
