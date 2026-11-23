extends SceneTree
## Checks jump, landing and footsteps in the on-foot mode.
##   Godot --headless --path . -s res://tools/on_foot_move_test.gd
## Builds the city, gets out, walks for 2 s (counts the "stepped" signals), jumps
## and measures the apex and the landing. Without --headless it saves
## screenshots/on_foot_walk.png, on_foot_jump.png and on_foot_land.png.

const OnFootScript := preload("res://scripts/on_foot.gd")
const DT := 1.0 / 60.0

var city: CityMap
var car: Car
var foot: Node3D
var player: CharacterBody3D
var steps: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	city = CityMap.new()
	root.add_child(city)
	car = load("res://scenes/car.tscn").instantiate()
	root.add_child(car)
	city.build(car)
	car.teleport(city.start_transform(), true)
	foot = OnFootScript.new()
	foot.set("car", car)
	root.add_child(foot)
	await process_frame
	await process_frame
	player = foot.get("_player") as CharacterBody3D
	foot.call("leave_car")
	await _wait(0.4)

	var anim := foot.get("_anim") as Node
	for i in 180:
		if anim:
			break
		await physics_frame
		anim = foot.get("_anim") as Node
	if anim == null:
		print("On-foot move test: FAIL, character animator did not start")
		quit()
		return
	anim.connect("stepped", _on_stepped)
	var sounds := foot.get("_steps") as Node
	var variants: int = 0
	if sounds:
		var list: Variant = sounds.get("_steps")
		if list != null:
			variants = (list as Array).size()

	# Walk straight ahead for 2 s and count the steps
	var start := player.global_position
	Input.action_press("accelerate")
	await _wait(1.0)
	await _shot("on_foot_walk")
	await _wait(1.0)
	Input.action_release("accelerate")
	var walked: float = Vector2(player.global_position.x - start.x,
		player.global_position.z - start.z).length()
	await _wait(0.5)

	# Rest pose before the jump (after the walk has settled, no landing crouch active)
	var stand_foot: float = _lowest_foot(anim) - player.global_position.y
	var stand_head: float = _bone_y(anim, "head") - player.global_position.y
	var stand_knee: Quaternion = _knee_rot(anim)

	# Jump and watch the height every physics frame
	var ground_y: float = player.global_position.y
	# Side view for the screenshots: the jump pose is best seen in profile
	foot.set("_yaw", float(foot.get("_yaw")) + PI * 0.5)
	foot.set("_pitch", 0.08)
	Input.action_press("jump")
	await _wait(0.06)
	Input.action_release("jump")
	var apex: float = 0.0
	var landed_at: float = -1.0
	var elapsed: float = 0.0
	var shot_jump: bool = false
	var shot_land: bool = false
	var air_foot: float = -INF
	var knee_deg: float = 0.0
	var land_head: float = INF
	while elapsed < 2.0:
		await physics_frame
		elapsed += DT
		apex = maxf(apex, player.global_position.y - ground_y)
		if elapsed > 0.22 and elapsed < 0.45:
			air_foot = maxf(air_foot, _lowest_foot(anim) - player.global_position.y)
			knee_deg = maxf(knee_deg, rad_to_deg(stand_knee.angle_to(_knee_rot(anim))))
		if elapsed > 0.65 and elapsed < 1.0:
			land_head = minf(land_head, _bone_y(anim, "head") - player.global_position.y)
		if not shot_jump and elapsed > 0.28:
			shot_jump = true
			await _shot("on_foot_jump")
		if not shot_land and elapsed > 0.72:
			shot_land = true
			await _shot("on_foot_land")
		if elapsed > 0.3 and landed_at < 0.0 and player.is_on_floor():
			landed_at = elapsed
	if landed_at < 0.0 and player.is_on_floor():
		landed_at = elapsed

	var walk_ok: bool = walked > 6.0
	var steps_ok: bool = steps >= 6
	var jump_ok: bool = apex > 0.6
	var land_ok: bool = landed_at > 0.0 and landed_at < 1.5
	var pose_ok: bool = air_foot > stand_foot + 0.08
	var knee_ok: bool = knee_deg > 15.0
	var crouch_ok: bool = land_head < stand_head - 0.015
	print("On-foot move test")
	print("  walked %.1f m in 2 s, %d step sounds (3 variants generated: %d)  %s" % [
		walked, steps, variants, "OK" if walk_ok and steps_ok and variants > 0 else "FAIL"])
	print("  jump apex %.2f m (must be > 0.6 m)  %s" % [apex, "OK" if jump_ok else "FAIL"])
	print("  landed after %.2f s (must be < 1.5 s)  %s" % [landed_at, "OK" if land_ok else "FAIL"])
	print("  air pose: lowest foot %.2f m above rest, knee %.0f deg  %s" % [
		air_foot - stand_foot, knee_deg, "OK" if pose_ok and knee_ok else "FAIL"])
	print("  landing crouch: head %.1f cm lower  %s" % [
		(stand_head - land_head) * 100.0, "OK" if crouch_ok else "FAIL"])
	print("  %s" % ("OK" if walk_ok and steps_ok and jump_ok and land_ok
		and pose_ok and knee_ok and crouch_ok else "FAIL"))
	quit()


func _skel(anim: Node) -> Skeleton3D:
	return anim.get("_skel") as Skeleton3D


func _bone(anim: Node, key: String) -> int:
	var b: Dictionary = anim.get("_b")
	return int(b[key])


func _bone_y(anim: Node, key: String) -> float:
	var s := _skel(anim)
	return (s.global_transform * s.get_bone_global_pose(_bone(anim, key)).origin).y


func _lowest_foot(anim: Node) -> float:
	var lowest: float = INF
	for key in ["l_foot", "l_toes", "r_foot", "r_toes"]:
		lowest = minf(lowest, _bone_y(anim, key))
	return lowest


func _knee_rot(anim: Node) -> Quaternion:
	return _skel(anim).get_bone_pose_rotation(_bone(anim, "l_knee"))


func _on_stepped(_strength: float) -> void:
	steps += 1


## Wait in physics frames (game time, independent of the real frame rate).
func _wait(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await physics_frame
		t += DT


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img:
		img.save_png("res://screenshots/%s.png" % name)
		print("  saved screenshots/%s.png" % name)
