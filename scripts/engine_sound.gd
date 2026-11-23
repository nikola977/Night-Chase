extends Node
## Motorsound ohne Sounddateien: Der Klang wird laufend berechnet (AudioStreamGenerator).
##
## So funktioniert es: Ein Viertaktmotor zündet in jedem Zylinder einmal pro Arbeitsspiel
## (zwei Kurbelwellen-Umdrehungen), ein Sechszylinder also 6-mal, ein V8 8-mal. Eine solche
## Periode wird einmal als Tabelle berechnet: kurze Druckstöße, jeder Zylinder etwas anders
## laut und etwas früher oder später (beim V8 mit Kreuzwelle besonders: das Blubbern).
## Beim Abspielen läuft die Tabelle je nach Drehzahl schneller oder langsamer durch.
## Zylinderzahl, Klang, Turbo, Auspuff-Resonanz und Klangfarbe stehen im Profil des Autos.
## Unter Last klingt es härter (Tabelle mit spitzen Stößen), ohne Gas weicher.
## Dazu kommen Ansauggeräusch, Turbo-Pfeifen (steigt mit dem Ladedruck), das Zischen des
## Abblasventils, Begrenzer-Stottern, ein „Krack“ beim Hochschalten unter Vollgas,
## Knallen im Auspuff beim Gaswegnehmen (Pops & Bangs) und die Reifen beim Bremsen und
## Driften. Das Quietschen kommt als Sample aus `assets/sounds/tire_skid_loop.wav` (CC-BY 3.0,
## Tom Haigh); fehlt die Datei, wird es wie alles andere berechnet: zwei verstimmte Töne,
## langsames Zittern, rauer Kern und das tiefe Mahlen der blockierenden Räder.

## Bei jedem Knall im Auspuff (für die Flammen an den Endrohren), strength 0..1
signal popped(strength: float)

## Gesamtlautstärke in Dezibel
@export var volume_db: float = -4.0
## Anteile der einzelnen Geräusche (0 bis 1)
@export_range(0.0, 1.0) var engine_volume: float = 0.6
@export_range(0.0, 1.0) var shift_volume: float = 0.5
## Reifengeräusch (Quietschen und Mahlen beim Bremsen, Driften und mit Handbremse)
@export_range(0.0, 1.0) var squeal_volume: float = 0.26
## Lautstärke des Reifen-Samples in Dezibel (0 dB = volles Rutschen)
@export var tire_sample_db: float = -14.0
@export_range(0.0, 1.0) var pop_volume: float = 0.55
## So schnell baut der Turbo Ladedruck auf und ab (Anteil pro Sekunde)
@export var spool_rate: float = 1.4
@export var spool_down_rate: float = 4.0
## Abtastrate: 48 kHz (klarere Obertöne, Pops und Turbo; kostet 0,53 statt 0,25 ms pro Bild bei 22 kHz)
@export var mix_rate: float = 48000.0
const TABLE_SIZE: int = 2048
## Reifen-Sample (3 s Schleife, rastlos): ersetzt die berechneten Reifentöne, wenn vorhanden
const TIRE_SAMPLE: String = "res://assets/sounds/tire_skid_loop.wav"

var _car: Car
var _wheels: Array[VehicleWheel3D] = []
var _playback: AudioStreamGeneratorPlayback
var _load_table := PackedFloat32Array()
var _coast_table := PackedFloat32Array()
var _phase: float = 0.0
var _turbo_phase: float = 0.0
# Reifen: zwei Töne, langsames Zittern, rauer Kern und tiefes Mahlen (eigene Filterzustände)
var _tire_phase_a: float = 0.0
var _tire_phase_b: float = 0.0
var _tire_wobble: float = 0.0
var _tire_grit: float = 0.0
var _tire_rumble: float = 0.0
## Reifen-Sample: das Quietschen und dieselbe Aufnahme tief und langsam als Mahlen
var _skid_player: AudioStreamPlayer
var _growl_player: AudioStreamPlayer
var _noise_low: float = 0.0
var _limiter_phase: float = 0.0
var _shift_crack: float = 0.0
# Ladedruck 0..1 (aktuell und beim letzten Puffer), Gas im letzten Bild
var _boost: float = 0.0
var _boost_audio: float = 0.0
var _last_throttle: float = 0.0
# Restzeit, in der es im Auspuff knallen kann, und der nächste Knall für den Puffer
var _overrun: float = 0.0
var _pending_pop: float = 0.0
var _pop: float = 0.0
var _pop_phase: float = 0.0
var _blow_off: float = 0.0
var _blow_low: float = 0.0
# Werte vom letzten Puffer (dazwischen wird weich übergeblendet)
var _rpm: float = 900.0
var _load: float = 0.0
var _squeal: float = 0.0
# Auspuff-Resonanz (Biquad) und Tiefpass für die Klangfarbe
var _rb0: float = 0.0
var _rb2: float = 0.0
var _ra1: float = 0.0
var _ra2: float = 0.0
var _rx1: float = 0.0
var _rx2: float = 0.0
var _ry1: float = 0.0
var _ry2: float = 0.0
var _tone: float = 0.0
## Rechenzeit des Klangs (für den Benchmark): Summe in Mikrosekunden und Anzahl Bilder
var cost_usec: int = 0
var cost_frames: int = 0


func _ready() -> void:
	_car = get_parent() as Car
	for child in _car.get_children():
		if child is VehicleWheel3D:
			_wheels.append(child)
	_car.profile_changed.connect(_on_profile_changed)
	if _car.profile:
		_on_profile_changed(_car.profile)
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = mix_rate
	stream.buffer_length = 0.12
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()
	_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	_car.gear_changed.connect(_on_gear_changed)
	_setup_tire_samples()


## Reifen-Sample laden (eine Schleife, zwei Stimmen): fehlt die Datei, bleiben die berechneten
## Reifentöne. Die Schleife wird hier gesetzt, damit sie unabhängig von den Import-Einstellungen gilt.
func _setup_tire_samples() -> void:
	if not ResourceLoader.exists(TIRE_SAMPLE):
		return
	var stream := load(TIRE_SAMPLE) as AudioStreamWAV
	if stream == null:
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_skid_player = _make_tire_player(stream)
	_growl_player = _make_tire_player(stream)
	_skid_player.play(randf() * stream.get_length())
	_growl_player.play(randf() * stream.get_length())


func _make_tire_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -80.0
	add_child(player)
	return player


## Lautstärke und Tonhöhe der beiden Reifenstimmen einmal pro Puffer: lauter und höher, je mehr
## die Räder rutschen und je schneller das Auto fährt; unter 2 % Rutschen ganz aus.
func _update_tire_voices(level: float, speed: float) -> void:
	if _skid_player == null:
		return
	if level < 0.02:
		_skid_player.volume_db = -80.0
		_growl_player.volume_db = -80.0
		return
	var fast := clampf(speed / 34.0, 0.0, 1.0)
	var loud := tire_sample_db + linear_to_db(level)
	_skid_player.volume_db = loud
	_skid_player.pitch_scale = lerpf(0.85, 1.25, fast)
	# Dieselbe Aufnahme eine Oktave tiefer und langsamer: das Mahlen der blockierenden Räder
	_growl_player.volume_db = loud - 4.0
	_growl_player.pitch_scale = lerpf(0.3, 0.42, fast)


func _on_profile_changed(profile: CarProfile) -> void:
	# Resonanz und Klangfarbe stehen im Profil des Autos, damit jeder Motor eigen klingt
	_update_resonator(profile)
	_load_table = _make_table(profile, profile.sound_sharpness, 7.0)
	_coast_table = _make_table(profile, profile.sound_sharpness * 0.35, 3.0)


## Eine Periode (720° Kurbelwinkel) mit einer Zündung pro Zylinder. sharpness: wie spitz ein
## Druckstoß ansteigt, decay: wie schnell er abklingt (größer = härterer, hellerer Klang)
func _make_table(profile: CarProfile, sharpness: float, decay: float) -> PackedFloat32Array:
	var cylinders := maxi(profile.cylinders, 1)
	# Feste „Zufalls“-Werte pro Zylinder (bei jedem Start gleich): Lautstärke und Zeitpunkt
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * cylinders
	var gains := PackedFloat32Array()
	var starts := PackedFloat32Array()
	for c in cylinders:
		gains.append(1.0 + rng.randf_range(-1.0, 1.0) * (0.05 + 0.15 * profile.firing_unevenness))
		starts.append((c + rng.randf_range(-0.5, 0.5) * profile.firing_unevenness * 0.6) / cylinders)
	var table := PackedFloat32Array()
	table.resize(TABLE_SIZE)
	for i in TABLE_SIZE:
		var x := float(i) / TABLE_SIZE
		var value := 0.0
		for c in cylinders:
			# Zeit seit der Zündung dieses Zylinders, in „Zündabständen“
			var since := fposmod(x - starts[c], 1.0) * cylinders
			var pulse := (1.0 - exp(-since * sharpness)) * exp(-since * decay)
			# Etwas Nachschwingen im Auspuff
			pulse += 0.25 * sin(since * TAU * 2.0) * exp(-since * 4.0)
			value += pulse * gains[c]
		# Tiefer Anteil einmal pro Kurbelwellen-Umdrehung (V8-Bass)
		value += profile.sound_rumble * 2.0 * sin(x * TAU * 2.0)
		table[i] = value
	# Gleichanteil entfernen und auf -1..1 bringen
	var mean := 0.0
	for v in table:
		mean += v
	mean /= TABLE_SIZE
	for i in TABLE_SIZE:
		table[i] -= mean
	# Zu feine Zacken wegnehmen, sonst kratzt es bei hoher Drehzahl (siehe _bandlimit)
	_bandlimit(table, 30.0)
	var peak := 0.0
	for i in TABLE_SIZE:
		peak = maxf(peak, absf(table[i]))
	for i in TABLE_SIZE:
		table[i] /= maxf(peak, 0.001)
	return table


## Die Tabelle enthält bei hoher Drehzahl viel zu feine Zacken: Beim Abspielen würden sie
## unterabgetastet und klingen als digitales Kratzen. Deshalb bleiben nur Obertöne bis zum
## 30-Fachen der Zündfrequenz übrig (zwei Durchgänge eines Tiefpasses, im Kreis).
func _bandlimit(table: PackedFloat32Array, harmonics: float) -> void:
	var alpha := 1.0 - exp(-TAU * harmonics / TABLE_SIZE)
	for _pass in 2:
		var low := table[TABLE_SIZE - 1]
		for i in TABLE_SIZE:
			low += alpha * (table[i] - low)
			table[i] = low


## Koeffizienten der Auspuff-Resonanz (Bandpass nach RBJ) aus dem Profil
func _update_resonator(profile: CarProfile) -> void:
	var w0 := TAU * clampf(profile.body_resonance_hz, 30.0, 400.0) / mix_rate
	var alpha := sin(w0) / (2.0 * maxf(profile.body_resonance_q, 0.5))
	var a0 := 1.0 + alpha
	_rb0 = alpha / a0
	_rb2 = -alpha / a0
	_ra1 = -2.0 * cos(w0) / a0
	_ra2 = (1.0 - alpha) / a0


func _on_gear_changed(new_gear: int) -> void:
	# Beim schnellen Hochschalten unter Last knallt es kurz im Auspuff
	if new_gear > 1 and _car.throttle_input > 0.6:
		_shift_crack = 1.0


## Ladedruck, Abblasventil und Knallen beim Gaswegnehmen (einmal pro Bild)
func _update_exhaust(delta: float) -> void:
	var profile := _car.profile
	var throttle := _car.throttle_input
	var rpm := _car.engine_rpm
	# Ladedruck: baut sich mit Gas und Drehzahl verzögert auf, fällt ohne Gas schnell ab
	var target := throttle * clampf((rpm - 1800.0) / 2500.0, 0.0, 1.0)
	var boost_before := _boost
	_boost = move_toward(_boost, target, (spool_rate if target > _boost else spool_down_rate) * delta)
	# Gas schnell weg: Abblasventil zischt, der Auspuff knallt 1–2 Sekunden lang
	var lifted := _last_throttle > 0.5 and throttle < 0.15
	_last_throttle = throttle
	if lifted and boost_before > 0.35:
		_blow_off = maxf(_blow_off, boost_before)
	if lifted and rpm > 3000.0:
		_overrun = lerpf(1.0, 2.0, profile.pops_strength)
	if _overrun <= 0.0:
		return
	_overrun -= delta
	if throttle > 0.3 or rpm < 1800.0:
		_overrun = 0.0
		return
	# Ohne Sportauspuff nur ganz leise; je höher die Drehzahl, desto öfter
	var strength := profile.pops_strength * (1.0 if _car.sport_exhaust else 0.12)
	var per_second := (4.0 + 12.0 * strength) * clampf((rpm - 1800.0) / 3000.0, 0.2, 1.0)
	if randf() < per_second * delta:
		var bang := strength * randf_range(0.5, 1.0)
		_pending_pop = maxf(_pending_pop, bang)
		popped.emit(bang)


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_timed_process(delta)
	FrameCosts.add("Engine sound", started)


func _timed_process(delta: float) -> void:
	if _playback == null or _car.profile == null:
		return
	var started := Time.get_ticks_usec()
	_fill(delta)
	cost_usec += Time.get_ticks_usec() - started
	cost_frames += 1


## Mittlere Rechenzeit des Klangs pro Bild in Millisekunden
func average_cost_ms() -> float:
	return cost_usec / 1000.0 / maxf(cost_frames, 1)


func _fill(delta: float) -> void:
	_update_exhaust(delta)
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var profile := _car.profile
	var redline := profile.redline_rpm
	var intake_volume := profile.intake_volume
	var turbo_volume := profile.turbo_volume
	var blow_off_volume := profile.blow_off_volume
	var body_mix := profile.body_mix
	# Knall an einer zufälligen Stelle im Puffer (klingt natürlicher als immer am Anfang)
	var pop_at := randi() % frames if _pending_pop > 0.0 else -1
	var pop_decay := exp(-1.0 / (0.035 * mix_rate))
	var blow_decay := exp(-1.0 / (0.16 * mix_rate))
	var start_boost := _boost_audio
	var target_rpm := _car.engine_rpm
	var target_load := _car.throttle_input
	var speed := _car.linear_velocity.length()
	var target_squeal := 0.0
	for wheel in _wheels:
		target_squeal = maxf(target_squeal, _car.wheel_slip(wheel))
	target_squeal *= clampf(speed / 8.0, 0.0, 1.0)
	# Schneller schleifende Reifen klingen höher; auf nasser Fahrbahn wird es rauer (Zischen)
	var tire_pitch := lerpf(0.78, 1.3, clampf(speed / 34.0, 0.0, 1.0))
	var tire_wet := clampf(_car.wetness, 0.0, 1.0)
	_update_tire_voices(target_squeal, speed)
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	var start_rpm := _rpm
	var start_load := _load
	var start_squeal := _squeal
	# Klangfarbe einmal pro Puffer: unter Last heller, im Stand dumpfer
	var brightness := clampf(0.4 * clampf(target_rpm / redline, 0.0, 1.0) + 0.6 * target_load, 0.0, 1.0)
	var tone_coeff := 1.0 - exp(-TAU * lerpf(profile.tone_idle_hz, profile.tone_load_hz, brightness) / mix_rate)
	for i in frames:
		var t := float(i + 1) / frames
		var rpm := lerpf(start_rpm, target_rpm, t)
		var engine_load := lerpf(start_load, target_load, t)
		var squeal := lerpf(start_squeal, target_squeal, t)
		var rev := rpm / redline
		# Motor: Tabelle mit der Arbeitsspiel-Frequenz (Drehzahl / 120) abspielen
		_phase = fmod(_phase + rpm / 120.0 / mix_rate * TABLE_SIZE, TABLE_SIZE)
		var index := int(_phase)
		var frac := _phase - index
		var next := (index + 1) % TABLE_SIZE
		var hard := lerpf(_load_table[index], _load_table[next], frac)
		var soft := lerpf(_coast_table[index], _coast_table[next], frac)
		var engine := lerpf(soft, hard, engine_load) * (0.35 + 0.65 * engine_load) * (0.55 + 0.45 * rev)
		# Begrenzer: Zündung wird ganz schnell aus- und eingeschaltet
		if rpm > redline - 60.0 and engine_load > 0.5:
			_limiter_phase = fmod(_limiter_phase + 18.0 / mix_rate, 1.0)
			if _limiter_phase < 0.4:
				engine *= 0.25
		# Auspuff-Körper: Resonanz der Luftsäule, das gibt Volumen statt nur Zacken
		var body := _rb0 * engine + _rb2 * _rx2 - _ra1 * _ry1 - _ra2 * _ry2
		_rx2 = _rx1
		_rx1 = engine
		_ry2 = _ry1
		_ry1 = body
		engine = engine * (1.0 - body_mix) + body * body_mix * 1.8
		# Klangfarbe: Tiefpass, der mit Last und Drehzahl heller wird
		_tone += tone_coeff * (engine - _tone)
		engine = lerpf(engine, _tone, 0.5)
		# Ansauggeräusch: gefiltertes Rauschen, lauter mit Gas und Drehzahl
		_noise_low = lerpf(_noise_low, randf_range(-1.0, 1.0), 0.08 + 0.25 * rev)
		var intake := _noise_low * engine_load * rev * rev
		# Turbo: Pfeifen, Tonhöhe und Lautstärke steigen mit dem Ladedruck
		var boost := lerpf(start_boost, _boost, t)
		_turbo_phase = fmod(_turbo_phase + (1400.0 + boost * 5200.0) / mix_rate, 1.0)
		var turbo := (sin(_turbo_phase * TAU) + 0.3 * sin(_turbo_phase * TAU * 2.0)) * boost * boost
		# Abblasventil: helles Zischen (Rauschen ohne tiefe Anteile), etwa 0,4 s
		var blow := 0.0
		if _blow_off > 0.002:
			var hiss := randf_range(-1.0, 1.0)
			_blow_low = lerpf(_blow_low, hiss, 0.15)
			blow = (hiss - _blow_low) * _blow_off
			_blow_off *= blow_decay
		# Knall im Auspuff: breites Krachen und ein tiefer Schlag, klingt in ~40 ms ab
		if i == pop_at:
			_pop = _pending_pop
			_pending_pop = 0.0
			_pop_phase = 0.0
		var bang := 0.0
		if _pop > 0.002:
			_pop_phase += 55.0 / mix_rate
			bang = (randf_range(-1.0, 1.0) * 0.75 + sin(_pop_phase * TAU) * 1.1
				+ sin(_pop_phase * TAU * 0.45) * 0.7) * _pop
			_pop *= pop_decay
		# Schalt-Knall: kurzes Rauschen, klingt in ca. 60 ms ab
		var crack := 0.0
		if _shift_crack > 0.001:
			crack = randf_range(-1.0, 1.0) * _shift_crack
			_shift_crack *= 0.9985
		# Reifen: mit Sample kommt das Quietschen aus den beiden Lautsprechern (siehe
		# _update_tire_voices), hier bleibt nur das Mahlen der blockierenden Räder. Ohne Sample
		# wird das Quietschen berechnet: zwei verstimmte Töne (sie schweben gegeneinander, das
		# klingt lebendig statt wie ein Pfeifton), ein langsam zitternder Ton und ein rauer Kern.
		var grit := randf_range(-1.0, 1.0)
		var tire := 0.0
		if _skid_player == null:
			_tire_wobble = fmod(_tire_wobble + 4.6 / mix_rate, 1.0)
			var waver := 1.0 + sin(_tire_wobble * TAU) * 0.013
			_tire_phase_a = fmod(_tire_phase_a + 1130.0 * tire_pitch * waver / mix_rate, 1.0)
			_tire_phase_b = fmod(_tire_phase_b + 1720.0 * tire_pitch * waver / mix_rate, 1.0)
			var squeal_tone := sin(_tire_phase_a * TAU) * 0.65 + sin(_tire_phase_b * TAU) * 0.22
			tire = (squeal_tone + (grit - _tire_grit) * (0.5 + 1.2 * tire_wet)) * squeal * squeal
			tire += _tire_rumble * 2.2 * squeal
		else:
			tire = _tire_rumble * 1.2 * squeal
		_tire_grit = lerpf(_tire_grit, grit, 0.3)
		_tire_rumble = lerpf(_tire_rumble, grit, 0.02 + 0.05 * squeal)
		var sample := engine * engine_volume + intake * intake_volume + turbo * turbo_volume \
			+ blow * blow_off_volume + bang * pop_volume + crack * shift_volume + tire * squeal_volume
		# Weich begrenzen, damit es nie hart übersteuert
		sample = sample / (1.0 + absf(sample))
		buffer[i] = Vector2(sample, sample)
	_rpm = target_rpm
	_load = target_load
	_boost_audio = _boost
	_squeal = target_squeal
	_playback.push_buffer(buffer)
