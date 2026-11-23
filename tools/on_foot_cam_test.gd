extends SceneTree
## Checks the on-foot camera collision (scripts/on_foot.gd).
##   Godot --headless --path . -s res://tools/on_foot_cam_test.gd
## Builds the city, gets out of the car, points the camera at a wall and then down
## the open street, and compares the boom length in both cases. The boom must be
## short (but not zero) with a wall behind, and at full length in the open.
## Without --headless it also saves screenshots/on_foot_cam_wall.png and _open.png.

const OnFootScript := preload("res://scripts/on_foot.gd")
const WALL_CLEAR := 1.0

var city: CityMap
var car: Car
var foot: Node3D
var player: CharacterBody3D

var wall_dir := Vector3.ZERO
var wall_dist := 0.0
var wall_len := 0.0
var open_len := 0.0


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
	await _seconds(0.3)

	# Find the closest wall around the start and stand right in front of it
	var found := _find_wall(car.global_position)
	if found.is_empty():
		print("On-foot camera test: FAIL, no wall found near the start")
		_finish()
		return
	wall_dir = found["dir"]
	wall_dist = found["dist"]
	var hit: Vector3 = found["point"]
	player.global_position = Vector3(hit.x - wall_dir.x * WALL_CLEAR, 0.3, hit.z - wall_dir.z * WALL_CLEAR)
	player.velocity = Vector3.ZERO
	# Camera behind the player must point straight into that wall
	foot.set("_yaw", atan2(wall_dir.x, wall_dir.z))
	foot.set("_pitch", 0.15)
	foot.set("_cam_len", 0.0)
	await _seconds(1.2)
	wall_len = float(foot.get("_cam_len"))
	var cam := foot.get("_camera") as Camera3D
	var cam_gap: float = cam.global_position.distance_to(hit) if cam else -1.0
	await _shot("on_foot_cam_wall")

	# Turn around: open street, the camera should go back to full length
	foot.set("_yaw", atan2(wall_dir.x, wall_dir.z) + PI)
	await _seconds(1.6)
	open_len = float(foot.get("_cam_len"))
	await _shot("on_foot_cam_open")

	var wall_ok: bool = wall_len > 0.3 and wall_len < wall_dist - 0.1
	var open_ok: bool = open_len > 3.2
	print("On-foot camera test")
	print("  wall at %.1f m, player %.1f m in front of it, camera %.1f m from the wall" % [
		wall_dist, WALL_CLEAR, cam_gap])
	print("  boom with the wall behind: %.2f m (must be < %.1f m)  %s" % [
		wall_len, wall_dist - 0.1, "OK" if wall_ok else "FAIL"])
	print("  boom on the open street:   %.2f m (must be > 3.2 m)  %s" % [
		open_len, "OK" if open_ok else "FAIL"])
	print("  %s" % ("OK" if wall_ok and open_ok else "FAIL"))
	_finish()


## Closest wall (world layer 1) around `from`, sampled in 32 directions.
func _find_wall(from: Vector3) -> Dictionary:
	var space := root.world_3d.direct_space_state
	var exclude: Array[RID] = [car.get_rid(), player.get_rid()]
	var best := {}
	for i in 32:
		var a: float = TAU * i / 32.0
		var dir := Vector3(sin(a), 0.0, cos(a))
		var origin: Vector3 = from + Vector3.UP * 1.2
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 20.0, 1)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var d: float = origin.distance_to(hit["position"])
		if d < 1.2:
			continue
		if best.is_empty() or d < float(best["dist"]):
			best = {"dir": dir, "dist": d, "point": hit["position"]}
	return best


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img:
		img.save_png("res://screenshots/%s.png" % name)
		print("  saved screenshots/%s.png" % name)


func _finish() -> void:
	# Let the engine tear the tree down; freeing car/city by hand while OnFoot still
	# processes them crashes at exit (0xC0000005).
	quit()
