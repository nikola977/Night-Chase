extends Node
## Procedurale Lauf-Animation für die Spielfigur (Gehen, Rennen, Stehen).
## Das Modell hat nur eine A-Pose und keine Lauf-Animation, darum bewegen wir die Knochen
## im Code: Beine und Arme schwingen gegenläufig, der Oberkörper lehnt sich beim Rennen
## nach vorn und die Figur dreht sich in Laufrichtung (wie in GTA).
## Alle Achsen werden aus der Ruhepose berechnet, es steckt keine feste Modell-Orientierung drin.
## Springen und Fallen haben eine eigene Pose, beim Landen geht die Figur kurz in die Knie,
## im Stand atmet sie.

## Wird bei jedem Fußkontakt ausgelöst (Stärke 0..1), damit der Aufrufer den Schritt hört.
signal stepped(strength: float)

# Meter pro Doppelschritt (links + rechts) beim Gehen und beim Rennen
const WALK_STRIDE: float = 1.7
const RUN_STRIDE: float = 3.4
# Ab dieser Geschwindigkeit gilt die Figur als "rennt" (voller Ausschlag)
const WALK_SPEED_REF: float = 3.0
const RUN_SPEED_REF: float = 7.6
# Wie schnell sich die Figur in Laufrichtung dreht (größer = knackiger)
const TURN_SPEED: float = 12.0
# Schwingwinkel in Radiant: [Gehen, Rennen]
const LEG_SWING: Vector2 = Vector2(0.5, 0.95)
const KNEE_BEND: Vector2 = Vector2(0.7, 1.5)
const ARM_SWING: Vector2 = Vector2(0.4, 0.95)
const ELBOW_BEND: Vector2 = Vector2(0.3, 1.4)
const LEAN: Vector2 = Vector2(0.05, 0.28)
# Arme hängen locker nach unten statt in der A-Pose abzustehen
const ARM_DOWN_OUT: float = 0.22
# Dauer des Lande-Knicks und die Atemfrequenz im Stand (Sekunden bzw. rad/s)
const LAND_TIME: float = 0.34
const IDLE_BREATH_SPEED: float = 1.7

var _model: Node3D
var _skel: Skeleton3D
var _ok: bool = false

var _up: Vector3 = Vector3.UP
var _swing_axis: Vector3 = Vector3.RIGHT
var _yaw_offset: float = 0.0
var _leg_len: float = 1.0

var _rest_g: Array[Transform3D] = []
var _parent: PackedInt32Array = PackedInt32Array()
var _b: Dictionary = {}
var _arm_down: Dictionary = {}

var _phase: float = 0.0
var _move_w: float = 0.0
var _run_t: float = 0.0
# Abstand zwischen Spieler-Fußpunkt und dem tiefsten Fußknochen in der Ruhepose (Meter)
var _sole: float = 0.0
# Continuous walk phase for the step sound (the pose uses _phase = fposmod(_step_acc, TAU))
var _step_acc: float = 0.0
# Time standing still (breathing) and the landing crouch
var _idle_t: float = 0.0
var _land_t: float = 999.0
var _land_amount: float = 0.0
# Model offset in the fitted rest pose, so the air pose can glide back to it
var _rest_model_y: float = 0.0


## Muss einmal mit dem geladenen Modell aufgerufen werden. Gibt false zurück, wenn
## Skelett oder Knochen nicht gefunden werden (dann bleibt die Figur in der A-Pose).
func setup(model: Node3D) -> bool:
	_model = model
	_skel = _find_skeleton(model)
	if _skel == null:
		push_warning("ANIM: kein Skeleton3D im Modell gefunden")
		return false
	_stop_players(model)

	var names := {
		"hips": "hips", "head": "head",
		"l_leg": "l_leg", "l_knee": "l_knee", "l_foot": "l_foot", "l_toes": "l_toes",
		"r_leg": "r_leg", "r_knee": "r_knee", "r_foot": "r_foot", "r_toes": "r_toes",
		"l_arm": "l_arm", "l_fore": "l_forearm", "r_arm": "r_arm", "r_fore": "r_forearm",
	}
	for key in names:
		var idx := _find_bone(names[key] as String)
		if idx < 0:
			push_warning("ANIM: Knochen '%s' nicht gefunden" % names[key])
			return false
		_b[key] = idx

	var n := _skel.get_bone_count()
	for i in n:
		_rest_g.append(_skel.get_bone_global_rest(i))
		_parent.append(_skel.get_bone_parent(i))

	# Achsen aus der Ruhepose: oben = Hüfte -> Kopf, vorne = Fuß -> Zehen
	var hips_o: Vector3 = _rest_g[_b["hips"]].origin
	_up = (_rest_g[_b["head"]].origin - hips_o).normalized()
	var fwd := Vector3.ZERO
	for side in ["l", "r"]:
		fwd += _rest_g[_b[side + "_toes"]].origin - _rest_g[_b[side + "_foot"]].origin
	fwd -= _up * fwd.dot(_up)
	if fwd.length() < 0.0001:
		push_warning("ANIM: Blickrichtung des Modells nicht bestimmbar")
		return false
	fwd = fwd.normalized()
	# Positiver Winkel um diese Achse schwingt ein hängendes Bein nach vorne
	_swing_axis = fwd.cross(_up).normalized()
	_leg_len = absf((hips_o - _rest_g[_b["l_foot"]].origin).dot(_up))

	# Arme: Drehung, die den abstehenden A-Pose-Arm nach unten klappt
	for side in ["l", "r"]:
		var d: Vector3 = (_rest_g[_b[side + "_fore"]].origin - _rest_g[_b[side + "_arm"]].origin).normalized()
		var out: Vector3 = d - _up * d.dot(_up)
		out = out.normalized() if out.length() > 0.0001 else Vector3.ZERO
		var target: Vector3 = (-_up + out * ARM_DOWN_OUT).normalized()
		_arm_down[side] = Basis(Quaternion(d, target))

	# In welche Richtung blickt das Modell (Yaw im Modellraum)? Daraus folgt das Drehen.
	var rel: Transform3D = _model.global_transform.affine_inverse() * _skel.global_transform
	var f_model: Vector3 = rel.basis * fwd
	_yaw_offset = atan2(-f_model.x, -f_model.z)
	# Bodenkontakt: Abstand Fußknochen -> Boden merken (Figur steht jetzt in Ruhepose am Boden)
	_sole = _lowest_foot_y() - _base_y()
	_rest_model_y = _model.position.y
	_ok = true
	print("ANIM: bereit, Knochen=%d, Blick-Yaw=%.0f Grad" % [n, rad_to_deg(_yaw_offset)])
	return true


## Jeden Physik-Frame aufrufen: speed = Laufgeschwindigkeit (m/s), move_dir = Wunsch-Richtung
## (Welt), airborne/vertical kommen vom CharacterBody3D (Sprung und Fall).
func update(delta: float, speed: float, move_dir: Vector3, airborne: bool = false,
		vertical: float = 0.0) -> void:
	if not _ok:
		return
	_idle_t += delta

	# Figur in Laufrichtung drehen (im Stand bleibt die letzte Richtung)
	if not airborne and speed > 0.3 and move_dir.length() > 0.01:
		var target_yaw: float = atan2(-move_dir.x, -move_dir.z) - _yaw_offset
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, 1.0 - exp(-TURN_SPEED * delta))

	var k: float = 1.0 - exp(-10.0 * delta)
	_move_w = lerpf(_move_w, clampf(speed / 1.5, 0.0, 1.0), k)
	_run_t = lerpf(_run_t, clampf((speed - WALK_SPEED_REF) / (RUN_SPEED_REF - WALK_SPEED_REF), 0.0, 1.0), k)

	if airborne:
		_air_pose(delta, vertical)
		return

	var stride: float = lerpf(WALK_STRIDE, RUN_STRIDE, _run_t)
	_step_acc += TAU * speed / stride * delta
	# Every half cycle a foot lands: exactly where the step sound belongs
	while _step_acc >= PI:
		_step_acc -= PI
		stepped.emit(clampf(0.55 + _run_t * 0.45, 0.0, 1.0))
	_phase = fposmod(_step_acc, TAU)

	var leg_amp: float = lerpf(LEG_SWING.x, LEG_SWING.y, _run_t) * _move_w
	var knee_amp: float = lerpf(KNEE_BEND.x, KNEE_BEND.y, _run_t)
	var arm_amp: float = lerpf(ARM_SWING.x, ARM_SWING.y, _run_t) * _move_w
	var elbow: float = lerpf(ELBOW_BEND.x, ELBOW_BEND.y, _run_t) * _move_w + 0.12
	var lean: float = lerpf(LEAN.x, LEAN.y, _run_t) * _move_w

	# Standing still: breathe (arms sway a little, chest rises) instead of freezing
	var idle: float = 1.0 - _move_w
	var breath: float = sin(_idle_t * IDLE_BREATH_SPEED) * idle

	# Landing crouch: knees bend and recover over LAND_TIME
	var dip: float = 0.0
	if _land_amount > 0.0:
		_land_t += delta
		if _land_t >= LAND_TIME:
			_land_amount = 0.0
		else:
			var f: float = 1.0 - _land_t / LAND_TIME
			dip = _land_amount * f * f

	var targets: Dictionary = {}
	# Positiver Winkel um die Schwingachse kippt den Körper nach hinten, also Minus = nach vorn
	targets[_b["hips"]] = Basis(_swing_axis, -lean - dip * 0.25)
	targets[_b["head"]] = Basis(_swing_axis, 0.03 * breath)
	for side in ["l", "r"]:
		var ph: float = _phase + (0.0 if side == "l" else PI)
		var thigh: float = leg_amp * sin(ph)
		# Knie beugt sich, solange das Bein nach vorne schwingt
		var flex: float = (0.12 + knee_amp * maxf(0.0, cos(ph))) * _move_w + dip * 0.85
		targets[_b[side + "_leg"]] = Basis(_swing_axis, thigh)
		targets[_b[side + "_knee"]] = Basis(_swing_axis, thigh - flex)
		targets[_b[side + "_foot"]] = Basis(_swing_axis, 0.0)
		# Arme schwingen gegenläufig zum Bein derselben Seite
		var arm: float = arm_amp * sin(ph + PI) + 0.02 * breath
		var down: Basis = _arm_down[side]
		targets[_b[side + "_arm"]] = Basis(_swing_axis, arm) * down
		targets[_b[side + "_fore"]] = Basis(_swing_axis, arm + elbow) * down

	_apply(targets)

	# Hüfte etwas absenken, damit die Füße trotz schwingender Beine am Boden bleiben
	var drop: float = _leg_len * (1.0 - cos(leg_amp)) * 0.9 + _leg_len * 0.02 * _move_w * (0.5 + 0.5 * cos(_phase * 2.0))
	drop += dip * 0.18 + 0.004 * breath
	_skel.set_bone_pose_position(_b["hips"], _hip_pose(drop))

	# Füße am Boden halten: tiefsten Fußknochen messen und das Modell genau so verschieben,
	# dass er auf Bodenhöhe liegt (sonst schwebt die Figur, wenn die Beine schwingen)
	var err: float = _lowest_foot_y() - (_base_y() + _sole)
	_model.position.y -= err


## Sprung- und Fallpose: beim Steigen Beine angezogen, beim Fallen gestreckt.
func _air_pose(delta: float, vertical: float) -> void:
	var fall: float = clampf(-vertical / 9.0, 0.0, 1.0)
	var targets: Dictionary = {}
	var lean: float = lerpf(0.12, -0.05, fall)
	targets[_b["hips"]] = Basis(_swing_axis, -lean)
	targets[_b["head"]] = Basis(_swing_axis, 0.05 * fall)
	for side in ["l", "r"]:
		var thigh: float = lerpf(0.55, 0.18, fall) if side == "l" else lerpf(0.32, 0.10, fall)
		var knee: float = lerpf(1.05, 0.30, fall) if side == "l" else lerpf(0.72, 0.22, fall)
		targets[_b[side + "_leg"]] = Basis(_swing_axis, thigh)
		targets[_b[side + "_knee"]] = Basis(_swing_axis, thigh - knee)
		targets[_b[side + "_foot"]] = Basis(_swing_axis, -thigh * 0.3)
		var arm: float = lerpf(-0.45, 0.35, fall)
		var elbow: float = lerpf(0.55, 0.25, fall)
		var down: Basis = _arm_down[side]
		targets[_b[side + "_arm"]] = Basis(_swing_axis, arm) * down
		targets[_b[side + "_fore"]] = Basis(_swing_axis, arm + elbow) * down
	_apply(targets)
	# No ground correction in the air: glide back to the fitted rest offset instead
	_skel.set_bone_pose_position(_b["hips"], _skel.get_bone_rest(_b["hips"]).origin)
	_model.position.y = lerpf(_model.position.y, _rest_model_y, 1.0 - exp(-9.0 * delta))


## Aufrufen, wenn die Figur wieder Boden berührt: strength 0..1 (Fallgeschwindigkeit / 8 m/s).
func land(strength: float) -> void:
	if not _ok:
		return
	_land_amount = clampf(strength, 0.0, 1.0)
	_land_t = 0.0


## Setzt die absoluten Zielausrichtungen in Knochenrotationen um (Eltern zuerst).
func _apply(targets: Dictionary) -> void:
	var desired: Dictionary = {}
	for i in _rest_g.size():
		_desired(i, targets, desired)
	for i in targets:
		var p: int = _parent[i]
		var local: Basis = desired[i]
		if p >= 0:
			var pd: Basis = desired[p]
			local = pd.inverse() * local
		_skel.set_bone_pose_rotation(i, local.orthonormalized().get_rotation_quaternion())


## Hüftposition mit Absenkung `drop` (Meter) im Raum des Elternknochens.
func _hip_pose(drop: float) -> Vector3:
	var hips: int = _b["hips"]
	var hp: int = _parent[hips]
	var shift: Vector3 = -_up * drop
	if hp >= 0:
		shift = _rest_g[hp].basis.inverse() * shift
	return _skel.get_bone_rest(hips).origin + shift


## Berechnet (mit Zwischenspeicher) die absolute Ausrichtung eines Knochens
func _desired(i: int, targets: Dictionary, cache: Dictionary) -> Basis:
	if cache.has(i):
		return cache[i]
	var rb: Basis = _rest_g[i].basis
	var result: Basis
	var p: int = _parent[i]
	if targets.has(i):
		var t: Basis = targets[i]
		result = t * rb
	elif p < 0:
		result = rb
	else:
		var pd: Basis = _desired(p, targets, cache)
		result = pd * (_rest_g[p].basis.inverse() * rb)
	cache[i] = result
	return result


## Höhe (Welt-y) des Spieler-Fußpunkts, also des Eltern-Knotens vom Modell
func _base_y() -> float:
	var parent := _model.get_parent() as Node3D
	return parent.global_position.y if parent else 0.0


## Tiefster Punkt der Fuß- und Zehenknochen in Welt-Koordinaten
func _lowest_foot_y() -> float:
	var lowest: float = INF
	for key in ["l_foot", "l_toes", "r_foot", "r_toes"]:
		var pos: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(_b[key] as int).origin
		lowest = minf(lowest, pos.y)
	return lowest


func _find_bone(prefix: String) -> int:
	for i in _skel.get_bone_count():
		var n: String = _skel.get_bone_name(i).to_lower().replace(" ", "_")
		if n.begins_with(prefix):
			return i
	return -1


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null


## Die mitgelieferte A-Pose-Animation darf die Knochen nicht überschreiben
func _stop_players(node: Node) -> void:
	if node is AnimationPlayer:
		(node as AnimationPlayer).stop()
		(node as AnimationPlayer).active = false
	for c in node.get_children():
		_stop_players(c)
