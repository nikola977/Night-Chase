extends Node
## Footstep and landing sounds for the on-foot mode, generated at startup so the
## project needs no audio files. A short filtered noise burst plus a low thump
## makes a step; a few variants and a random pitch avoid the machine-gun feel.

const RATE: int = 22050
const VARIANTS: int = 3
const PLAYERS: int = 4
const STEP_LENGTH: float = 0.11
const LAND_LENGTH: float = 0.22

var _steps: Array[AudioStreamWAV] = []
var _landing: AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20261122
	for i in VARIANTS:
		_steps.append(_make_step(_rng))
	_landing = _make_landing(_rng)
	for i in PLAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = "Umgebung"
		add_child(p)
		_players.append(p)


## One footstep. strength 0..1: soft when walking, harder when running.
func play_step(strength: float) -> void:
	if _steps.is_empty():
		return
	var s: float = clampf(strength, 0.0, 1.0)
	_play(_steps[_rng.randi_range(0, _steps.size() - 1)],
		lerpf(-16.0, -7.0, s), _rng.randf_range(0.92, 1.10))


## Landing after a jump. strength 0..1 from the fall speed.
func play_land(strength: float) -> void:
	if _landing == null:
		return
	var s: float = clampf(strength, 0.0, 1.0)
	_play(_landing, lerpf(-12.0, -4.0, s), _rng.randf_range(0.94, 1.02))


func _play(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func _make_step(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n: int = int(RATE * STEP_LENGTH)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp: float = 0.0
	var body: float = rng.randf_range(78.0, 96.0)
	for i in n:
		var t: float = float(i) / RATE
		var env: float = exp(-t * 34.0)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.32)
		var thump: float = sin(TAU * body * t) * exp(-t * 48.0) * 0.7
		var s: float = (lp * 0.6 + thump) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(data)


func _make_landing(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n: int = int(RATE * LAND_LENGTH)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var env: float = exp(-t * 20.0)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.18)
		var thump: float = sin(TAU * 52.0 * t) * exp(-t * 22.0) * 0.9
		var s: float = (lp * 0.45 + thump) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(data)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
