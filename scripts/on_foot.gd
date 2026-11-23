extends Node3D
## Zu Fuß unterwegs wie in GTA: F steigt neben dem Auto aus, WASD läuft relativ zur Kamera,
## Maus schaut umher, Shift rennt, F steigt wieder ein. Der Körper ist ein einfacher
## Platzhalter aus Kapsel und Kugel (das Spiel hat kein Figurenmodell).

var car: Car
var follow_camera: FollowCamera
## City traffic (CityTraffic), set by game.gd in the city map; null in the endless world.
## Used to "steal" an AI car when the player presses interact next to one.
var city_traffic: Node
## Traffic on the player's own editor roads (same steal interaction)
var road_traffic: Node

# Der Knoten entsteht im Code (game.gd), darum feste Werte statt @export
const WALK_SPEED: float = 4.2
const RUN_SPEED: float = 7.6
const MOUSE_SENSITIVITY: float = 0.0024
const ENTER_DISTANCE: float = 4.0
const CAMERA_DISTANCE: float = 3.6
const CAMERA_HEIGHT: float = 1.5
# Camera collision: keep this much air between the camera and the wall behind it
const CAMERA_MARGIN: float = 0.28
# Never come closer than this to the player's head (below that the body is hidden)
const CAMERA_MIN_DISTANCE: float = 0.5
# How fast the camera moves in when something is behind (snappy) and back out (soft)
const CAMERA_PULL_IN: float = 24.0
const CAMERA_PULL_OUT: float = 5.0
# Hide the body when the camera is this close, so it does not fill the screen
const CAMERA_BODY_HIDE: float = 0.95
# Physics layer of the world geometry (city, terrain) the camera must not enter
const CAMERA_BLOCK_MASK: int = 1
const GRAVITY: float = 18.0
# Jump: 6 m/s against 18 m/s² gravity is about one metre high and 0.67 s in the air
const JUMP_SPEED: float = 6.0
# Releasing jump early cuts the jump short (variable jump height)
const JUMP_CUT: float = 0.45
# Falling is a little heavier than rising, so the jump does not feel floaty
const FALL_GRAVITY: float = 24.0
# Horizontal acceleration and braking on the ground and in the air (m/s²). The
# character keeps a little momentum instead of changing speed instantly.
const GROUND_ACCEL: float = 20.0
const GROUND_DECEL: float = 24.0
const AIR_ACCEL: float = 7.0
const AIR_DECEL: float = 1.5
# Slopes steeper than this make the character slide down (radians)
const SLIDE_ANGLE: float = 0.72
const SLIDE_ACCEL: float = 9.0
# Highest step the character climbs while walking (kerbs, stairs, small ledges)
const STEP_HEIGHT: float = 0.38
# Still allow a jump this long after walking off a kerb
const COYOTE_TIME: float = 0.12
# Interaction prompt above the nearest car and the quick walk to the driver's door
const PROMPT_HEIGHT_CAR: float = 1.55
const PROMPT_HEIGHT_NPC: float = 2.0
const ENTER_TIME: float = 0.45
# Smooth camera handover between the on-foot boom and the chase camera
const CAMERA_BLEND_TIME: float = 0.42
# Zielgröße der Figur in Metern (Kopf/Mütze). Ein Fahrer mit ~1,78 m ist ca. 1,25x so
# hoch wie ein Sportcoupé (M4 ~1,42 m, M2 ~1,37 m, E30 ~1,35 m).
const CHARACTER_HEIGHT: float = 1.78
# Feinabstimmung gegen Schweben: positiv = Figur tiefer in den Boden, negativ = höher (in Metern)
const FOOT_OFFSET: float = 0.0

const CharacterAnimator := preload("res://scripts/character_animator.gd")
const Footsteps := preload("res://scripts/footsteps.gd")

var is_walking: bool = false

var _player: CharacterBody3D
var _anim: Node
var _steps: Node
var _camera: Camera3D
var _body_model: Node3D
var _prompt: Label3D
var _yaw: float = 0.0
var _pitch: float = 0.15
# Current camera boom length in metres, smoothed every frame (0 = not set yet)
var _cam_len: float = 0.0
# 0 = on-foot camera, 1 = chase camera (smooth handover when getting in or out)
var _cam_blend: float = 0.0
var _cam_blend_target: float = 0.0
# Jump/landing state: coyote window, whether we stood on the floor last frame, fall speed
var _coyote: float = 0.0
var _was_on_floor: bool = true
var _fall_speed: float = 0.0
# Getting in: the character walks to the driver's door while the camera blends
var _entering: bool = false
var _enter_t: float = 0.0
var _enter_done: bool = false
var _enter_path: PackedVector3Array = PackedVector3Array()
var _enter_total: float = 0.001


func _ready() -> void:
	_build_player()
	_steps = Footsteps.new()
	_steps.name = "Footsteps"
	add_child(_steps)
	_camera = Camera3D.new()
	_camera.fov = 72.0
	_camera.near = 0.05
	_camera.far = 20000.0
	_camera.current = false
	add_child(_camera)
	# "[F] Get in / Steal" above the nearest car, world-space so it stays on the car
	_prompt = Label3D.new()
	_prompt.name = "Prompt"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 48
	_prompt.pixel_size = 0.0035
	_prompt.outline_size = 12
	_prompt.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_prompt.modulate = Color(1.0, 1.0, 1.0)
	_prompt.visible = false
	add_child(_prompt)


func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.name = "Player"
	# Eigene Ebene, damit das Auto nicht gegen die Spielfigur stößt
	_player.collision_layer = 2
	_player.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	_player.add_child(shape)
	# Walk up kerbs and small bumps, stick to the ground on slopes, slide off steep ones
	_player.floor_max_angle = deg_to_rad(52.0)
	_player.floor_snap_length = 0.35
	_player.floor_stop_on_slope = true
	_player.max_slides = 6
	_player.slide_on_ceiling = true
	# Sichtbares Modell: Cyberpunk-Charakter (CC-BY-4.0, 4d_Bob). Fehlt die Datei,
	# bleibt die einfache Kapsel-Platzhalterfigur.
	var model_scene := load("res://assets/models/character_cyberpunk/scene.gltf") as PackedScene
	if model_scene:
		print("ON_FOOT: model loaded OK")
		var model := model_scene.instantiate() as Node3D
		_body_model = model
		_player.add_child(model)
		# Größe unabhängig vom .import (root_scale) automatisch an CHARACTER_HEIGHT anpassen
		call_deferred("_fit_model_height", model)
	else:
		var jacket := StandardMaterial3D.new()
		jacket.albedo_color = Color(0.17, 0.21, 0.3)
		jacket.roughness = 0.85
		var body := MeshInstance3D.new()
		var body_mesh := CapsuleMesh.new()
		body_mesh.radius = 0.3
		body_mesh.height = 1.2
		body.mesh = body_mesh
		body.material_override = jacket
		body.position.y = 0.72
		_player.add_child(body)
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.72, 0.56, 0.45)
		skin.roughness = 0.7
		var head := MeshInstance3D.new()
		var head_mesh := SphereMesh.new()
		head_mesh.radius = 0.16
		head_mesh.height = 0.32
		head.mesh = head_mesh
		head.material_override = skin
		head.position.y = 1.44
		_player.add_child(head)
	_player.visible = false
	add_child(_player)


func _process(_delta: float) -> void:
	if not is_walking:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_walking:
		return
	# Getting in: glide to the driver's door and hand the camera over to the chase camera
	if _entering:
		_enter_step(delta)
		_place_camera(delta)
		if _enter_done and _cam_blend >= 0.999:
			_finish_enter()
		return
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := forward.cross(Vector3.UP)
	var input := Input.get_vector("steer_left", "steer_right", "accelerate", "brake")
	var move := forward * -input.y + right * input.x
	if move.length() > 0.01:
		move = move.normalized()
	var speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	# Inertia: accelerate towards the wanted speed, brake smoothly, and keep only weak
	# control in the air (no instant direction changes any more)
	var has_input: bool = move.length() > 0.01
	var target := Vector2(move.x, move.z) * speed
	# On a steep slope the ground no longer brakes the character: it slides instead
	var on_steep := _player.is_on_floor() \
		and _player.get_floor_normal().angle_to(Vector3.UP) > SLIDE_ANGLE
	var accel := AIR_ACCEL
	if _player.is_on_floor() and not on_steep:
		accel = GROUND_ACCEL if has_input else GROUND_DECEL
	elif not has_input:
		accel = AIR_DECEL
	var horizontal := Vector2(_player.velocity.x, _player.velocity.z).move_toward(target, accel * delta)
	_player.velocity.x = horizontal.x
	_player.velocity.z = horizontal.y

	# Jump, with a short coyote time so a step off a kerb still allows jumping
	var on_floor: bool = _player.is_on_floor()
	_coyote = COYOTE_TIME if on_floor else maxf(_coyote - delta, 0.0)
	if Input.is_action_just_pressed("jump") and _coyote > 0.0:
		_player.velocity.y = JUMP_SPEED
		_coyote = 0.0
	else:
		# Letting go of Space early shortens the jump; falling uses heavier gravity
		var gravity := GRAVITY if _player.velocity.y > 0.0 else FALL_GRAVITY
		_player.velocity.y -= gravity * delta
		if Input.is_action_just_released("jump") and _player.velocity.y > 0.0:
			_player.velocity.y *= JUMP_CUT
	var feet_before := _player.global_position
	# move_and_slide zeroes the velocity along a wall, so remember what was wanted
	var wish := _player.velocity
	_player.move_and_slide()
	_try_step_up(feet_before, delta, wish)
	# Too steep to stand on: slide downhill instead of walking up the wall
	if _player.is_on_floor():
		var floor_normal := _player.get_floor_normal()
		if floor_normal.angle_to(Vector3.UP) > SLIDE_ANGLE:
			var downhill := Vector3(floor_normal.x, 0.0, floor_normal.z)
			if downhill.length() > 0.001:
				_player.velocity += downhill.normalized() * SLIDE_ACCEL * delta

	# Touchdown: crouch and a thud, scaled by the fall speed
	if not _was_on_floor and _player.is_on_floor():
		var impact: float = clampf(_fall_speed / 8.0, 0.0, 1.0)
		if _anim:
			_anim.call("land", impact)
		if _steps:
			_steps.call("play_land", impact)
		_fall_speed = 0.0
	elif not _player.is_on_floor():
		_fall_speed = maxf(_fall_speed, -_player.velocity.y)
	_was_on_floor = _player.is_on_floor()

	if _anim:
		_anim.call("update", delta, Vector2(_player.velocity.x, _player.velocity.z).length(), move,
			not _player.is_on_floor(), _player.velocity.y)
	_place_camera(delta)
	_update_prompt()


## Walk up kerbs and low steps: when the character is blocked although it wanted to
## move, lift it over the obstacle and forward. Without this the capsule just stops at
## a 20 cm step (move_and_slide slides along the vertical face, it never climbs).
func _try_step_up(feet_before: Vector3, delta: float, wish: Vector3) -> void:
	if not _player.is_on_floor():
		return
	var wanted := Vector2(wish.x, wish.z) * delta
	if wanted.length() < 0.0005:
		return
	var actual := Vector2(_player.global_position.x - feet_before.x,
		_player.global_position.z - feet_before.z)
	# Free to move? No step needed
	if actual.dot(wanted) > wanted.length_squared() * 0.6:
		return
	var xf := _player.global_transform
	var up := Vector3.UP * STEP_HEIGHT
	# No room to lift the body (under a car, low doorway): stay on the floor
	if _player.test_move(xf, up):
		return
	var raised := xf.translated(up)
	var forward := Vector3(wanted.x, 0.0, wanted.y)
	# Something solid at chest height: not a step, a wall
	if _player.test_move(raised, forward):
		return
	_player.global_position = raised.translated(forward).origin


## Third-person boom with collision: the camera sits behind the player, but never
## inside a wall. A ray from the head to the wanted camera spot shortens the boom
## when something blocks it (snappy in, soft back out), so the camera glides along
## building corners instead of jumping through them. While getting in or out, the
## boom is blended smoothly into the chase camera transform (`_cam_blend`).
func _place_camera(delta: float = 0.016) -> void:
	_cam_blend = move_toward(_cam_blend, _cam_blend_target, delta / CAMERA_BLEND_TIME)
	var target := _player.global_position + Vector3.UP * CAMERA_HEIGHT
	var behind := Basis(Vector3.UP, _yaw) * Vector3(0.0, 0.0, CAMERA_DISTANCE)
	behind.y = sin(_pitch) * CAMERA_DISTANCE
	var dir := behind.normalized()
	var wanted := behind.length()
	var allowed := _free_camera_length(target, dir, wanted)
	if _cam_len <= 0.0:
		_cam_len = allowed
	else:
		var speed: float = CAMERA_PULL_IN if allowed < _cam_len else CAMERA_PULL_OUT
		_cam_len = lerpf(_cam_len, allowed, 1.0 - exp(-speed * delta))
	var pos := target + dir * _cam_len
	var foot_xf := Transform3D(Basis.IDENTITY, pos).looking_at(target, Vector3.UP)
	if follow_camera and _cam_blend > 0.0001:
		var w: float = _cam_blend * _cam_blend * (3.0 - 2.0 * _cam_blend)
		var chase_xf := follow_camera.global_transform
		var q := foot_xf.basis.get_rotation_quaternion().slerp(
			chase_xf.basis.orthonormalized().get_rotation_quaternion(), w)
		_camera.global_transform = Transform3D(Basis(q), pos.lerp(chase_xf.origin, w))
	else:
		_camera.global_transform = foot_xf
	# Backed into a corner: the head would fill the whole screen, so hide the body.
	# Measured on the actual (possibly blended) camera, not just the boom length.
	if _body_model:
		_body_model.visible = _camera.global_position.distance_to(target) > CAMERA_BODY_HIDE


## Longest unobstructed boom length from `from` along `dir` (world geometry only).
func _free_camera_length(from: Vector3, dir: Vector3, wanted: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return wanted
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * wanted, CAMERA_BLOCK_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _camera_ignored_rids()
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return wanted
	var dist: float = from.distance_to(hit["position"]) - CAMERA_MARGIN
	return clampf(dist, CAMERA_MIN_DISTANCE, wanted)


## The player capsule and the player's own car never block the camera.
func _camera_ignored_rids() -> Array[RID]:
	var out: Array[RID] = []
	if is_instance_valid(_player):
		out.append(_player.get_rid())
	if is_instance_valid(car):
		var body := car as CollisionObject3D
		if body:
			out.append(body.get_rid())
	return out


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	var motion := event as InputEventMouseMotion
	if is_walking and motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch + motion.relative.y * MOUSE_SENSITIVITY, -0.3, 0.9)
		return
	if event.is_action_pressed("interact"):
		if is_walking:
			if _entering:
				return
			# The nearest car wins: steal an AI car only if it is closer than our own
			var target := _interact_target()
			if not target.is_empty() and target["steal"]:
				var stolen := _steal_nearest()
				# The stolen car appears somewhere else: put the chase camera there at once
				if stolen and follow_camera and follow_camera.has_method("snap"):
					follow_camera.call("snap")
			enter_car()
		else:
			leave_car()
		get_viewport().set_input_as_handled()


## Nearest car the player can interact with ({} when none is in reach).
## `steal` is true for an AI car, false for the player's own car.
func _interact_target() -> Dictionary:
	var best: Node3D = null
	var best_distance := INF
	var best_steal := false
	if is_instance_valid(car):
		var distance := _player.global_position.distance_to(car.global_position)
		if distance <= ENTER_DISTANCE:
			best = car
			best_distance = distance
	for traffic in [city_traffic, road_traffic]:
		if traffic == null or not traffic.has_method("steal_target"):
			continue
		var npc := traffic.call("steal_target", _player.global_position) as Node3D
		if npc == null:
			continue
		var distance := _player.global_position.distance_to(npc.global_position)
		if distance < best_distance:
			best = npc
			best_distance = distance
			best_steal = true
	if best == null:
		return {}
	return {"node": best, "steal": best_steal, "distance": best_distance}


## Takes the AI car the player is standing next to (from any traffic system)
func _steal_nearest() -> bool:
	for traffic in [city_traffic, road_traffic]:
		if traffic != null and traffic.has_method("try_steal"):
			if bool(traffic.call("try_steal", _player.global_position)):
				return true
	return false


## Shows "[F] Get in" / "[F] Steal" above the nearest car, hides it otherwise.
func _update_prompt() -> void:
	if _prompt == null:
		return
	if not is_walking or _entering or get_tree().paused:
		_prompt.visible = false
		return
	var target := _interact_target()
	if target.is_empty():
		_prompt.visible = false
		return
	var node := target["node"] as Node3D
	if node == null or not is_instance_valid(node):
		_prompt.visible = false
		return
	var steal: bool = target["steal"]
	_prompt.text = "[F]  " + ("Steal" if steal else "Get in")
	var lift := PROMPT_HEIGHT_NPC if steal else PROMPT_HEIGHT_CAR
	_prompt.global_position = node.global_position + Vector3.UP * lift
	_prompt.visible = true


## Aussteigen: nur im Stand, die Figur landet neben der Fahrertür. Die Kamera gleitet
## vom Verfolger weich zum Fußgänger-Boom (kein harter Schnitt).
func leave_car() -> void:
	print("ON_FOOT: leave_car called, vel=", car.linear_velocity.length() if car else -1)
	if car == null:
		return
	if car.linear_velocity.length() > 2.5:
		Toasts.post(get_tree(), "warning", "Stop first", "F gets you out when standing")
		return
	_player.global_position = car.global_position - car.global_basis.x * 1.35 + Vector3.UP * 0.4
	_player.velocity = Vector3.ZERO
	_player.visible = true
	is_walking = true
	_entering = false
	_enter_done = false
	_yaw = atan2(-car.global_basis.z.x, -car.global_basis.z.z)
	_pitch = 0.15
	_coyote = 0.0
	_was_on_floor = true
	_fall_speed = 0.0
	car.freeze = true
	car.throttle_enabled = false
	if follow_camera:
		follow_camera.current = false
		# Start exactly where the chase camera was, then glide to the character
		_camera.global_transform = follow_camera.global_transform
	_camera.current = true
	_cam_blend = 1.0
	_cam_blend_target = 0.0
	_cam_len = 0.0
	if _body_model:
		_body_model.visible = true
	_place_camera(0.0)
	_update_prompt()
	Toasts.post(get_tree(), "check", "On foot", "WASD walk · Shift run · Space jump · F get in")


## Einsteigen: nur wenn die Figur nah genug am Auto steht. Die Figur geht zur
## Fahrertür (bei Annäherung von der Beifahrerseite außen herum), die Kamera
## blendet währenddessen zum Verfolger.
func enter_car() -> void:
	if car == null or _entering:
		return
	if _player.global_position.distance_to(car.global_position) > ENTER_DISTANCE:
		Toasts.post(get_tree(), "warning", "Too far", "Walk to the car, then press F")
		return
	_entering = true
	_enter_t = 0.0
	_enter_done = false
	_enter_path = _make_enter_path()
	_enter_total = 0.001
	for i in _enter_path.size() - 1:
		_enter_total += _enter_path[i].distance_to(_enter_path[i + 1])
	_cam_blend_target = 1.0
	_prompt.visible = false
	car.freeze = true
	car.throttle_enabled = false
	_player.velocity = Vector3.ZERO


## Waypoints from the player to the driver's door. If the player stands on the
## passenger side, the path goes around the nearer end of the car instead of
## straight through it.
func _make_enter_path() -> PackedVector3Array:
	var path := PackedVector3Array()
	path.append(_player.global_position)
	var ground_y := _player.global_position.y
	var basis := car.global_basis
	var door := car.global_position - basis.x * 1.35
	door.y = ground_y
	var rel := basis.inverse() * (_player.global_position - car.global_position)
	if rel.x > 0.15 and absf(rel.z) < 2.6:
		# Passenger side: walk around the front (or rear) bumper first
		var side := -1.0 if absf(rel.z) < 0.15 else signf(rel.z)
		var around := car.global_position + basis * Vector3(1.6, 0.0, side * 3.0)
		around.y = ground_y
		path.append(around)
	path.append(door)
	return path


## Point at `distance` metres along the enter path.
func _path_point(distance: float) -> Vector3:
	var left := clampf(distance, 0.0, _enter_total)
	for i in _enter_path.size() - 1:
		var segment := _enter_path[i].distance_to(_enter_path[i + 1])
		if left <= segment or i == _enter_path.size() - 2:
			return _enter_path[i].lerp(_enter_path[i + 1], clampf(left / maxf(segment, 0.0001), 0.0, 1.0))
		left -= segment
	return _enter_path[_enter_path.size() - 1]


## One step of the get-in animation: smooth walk along the path, legs animated.
func _enter_step(delta: float) -> void:
	_enter_t += delta
	var w: float = clampf(_enter_t / ENTER_TIME, 0.0, 1.0)
	w = w * w * (3.0 - 2.0 * w)
	var pos := _path_point(w * _enter_total)
	var moved := pos - _player.global_position
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_enter_done = w >= 1.0
	if _anim:
		var speed: float = moved.length() / maxf(delta, 0.0001)
		var dir := moved.normalized() if moved.length() > 0.001 else Vector3.ZERO
		_anim.call("update", delta, speed, dir, false, 0.0)


## Get-in finished: hide the character, hand over to the chase camera, release the car.
func _finish_enter() -> void:
	_entering = false
	_enter_done = false
	is_walking = false
	_player.visible = false
	_player.velocity = Vector3.ZERO
	_coyote = 0.0
	_fall_speed = 0.0
	_cam_blend = 0.0
	_cam_blend_target = 0.0
	_camera.current = false
	if follow_camera:
		follow_camera.current = true
	car.freeze = false
	car.throttle_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Toasts.post(get_tree(), "check", "Drive", "Tab changes the camera")


## Misst die Figur (Mesh-Boxen), skaliert sie auf CHARACTER_HEIGHT und setzt die Füße
## genau auf den Boden (Ursprung des Spielers = Fußpunkt). Danach startet die Lauf-Animation.
func _fit_model_height(model: Node3D) -> void:
	await get_tree().process_frame
	var box := _model_aabb(model, "")
	if box.size.y < 0.0001:
		push_warning("ON_FOOT: Modellhöhe nicht messbar, Skalierung bleibt unverändert")
		return
	# Die Fußsohle kommt vom Körper-Mesh (Brille, Hut usw. haben eigene Boxen, die den
	# Tiefpunkt verfälschen und die Figur sonst schweben lassen)
	var body := _model_aabb(model, "body")
	var bottom: float = body.position.y if body.size.y > 0.0001 else box.position.y
	var factor: float = CHARACTER_HEIGHT / (box.end.y - bottom)
	model.scale *= factor
	var feet_y: float = (bottom - _player.global_position.y) * factor
	model.position.y -= feet_y + FOOT_OFFSET
	print("ON_FOOT: Figur skaliert, Faktor %.3f, Höhe jetzt %.2f m" % [factor, CHARACTER_HEIGHT])
	_anim = CharacterAnimator.new()
	add_child(_anim)
	_anim.call("setup", model)
	if _anim.has_signal("stepped"):
		_anim.connect("stepped", _on_stepped)


func _on_stepped(strength: float) -> void:
	if _steps:
		_steps.call("play_step", strength)


## Welt-Box aller Meshes unter dem Modell. Mit name_filter nur Meshes, deren Name den Text enthält.
func _model_aabb(model: Node3D, name_filter: String) -> AABB:
	var aabb := AABB()
	var first := true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		var mi := c as MeshInstance3D
		if mi and mi.mesh and (name_filter == "" or String(mi.name).to_lower().contains(name_filter)):
			var b: AABB = mi.get_aabb()
			var t: Transform3D = mi.global_transform
			for x in [b.position.x, b.end.x]:
				for y in [b.position.y, b.end.y]:
					for z in [b.position.z, b.end.z]:
						var pt: Vector3 = t * Vector3(x, y, z)
						if first:
							aabb = AABB(pt, Vector3.ZERO)
							first = false
						else:
							aabb = aabb.expand(pt)
		stack.append_array(c.get_children())
	return aabb
