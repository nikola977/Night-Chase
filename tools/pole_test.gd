extends SceneTree
## Prüft die umfallenden Pfosten: in die ersten drei Laternen fahren, Neigung messen und
## nachsehen, ob sie von selbst wieder aufstehen.
##   Godot --headless --path . -s res://tools/pole_test.gd

var city: CityMap
var car: Car
var posts: Array = []
var index := -1
var t := 0.0
var tilted := 0.0
var fell_at := -1.0
var stood_up_at := -1.0
var closest := 999.0
## Lage (y) des Pfostens, während er liegt
var lying_low := 0.0
var lying_high := 0.0


func _initialize() -> void:
	city = CityMap.new()
	root.add_child(city)
	car = load("res://scenes/car.tscn").instantiate()
	root.add_child(car)
	city.build(car)
	for child in city.get_children():
		if child is FallingPole:
			posts.append(child)
	print("Poles found: %d" % posts.size())
	_next()


func _next() -> void:
	Input.action_release("accelerate")
	if index >= 0 and index < posts.size():
		var post: FallingPole = posts[index]
		var verdict := "did not fall"
		if fell_at >= 0.0:
			verdict = ("stood up again %.1f s after falling" % stood_up_at if stood_up_at >= 0.0
				else "DID NOT STAND UP")
		print("  Pole %d at (%.1f, %.1f): tilted %.0f deg, closest %.1f m, %s, lying y %.2f..%.2f" % [
			index + 1, post.foot.x, post.foot.z, tilted, closest, verdict, lying_low, lying_high])
	index += 1
	if index >= posts.size() or index >= 3:
		_finish()
		return
	var post: FallingPole = posts[index]
	var base: Vector3 = post.foot
	# Kurz vor dem Pfosten aufsetzen und darauf zu rollen (beim ersten Pfosten wird richtig
	# angefahren, danach reicht die Bewegung für den Stoß)
	var from := Vector3(base.x - 2.9, 1.0, base.z - 0.6)
	city.spawn_point = from
	city.spawn_heading = rad_to_deg(atan2(base.x - from.x, base.z - from.z))
	car.teleport(city.start_transform(), true)
	car.linear_velocity = (base + Vector3.UP - from).normalized() * 8.0
	t = 0.0
	tilted = 0.0
	fell_at = -1.0
	stood_up_at = -1.0
	closest = 999.0
	lying_low = 0.0
	lying_high = 0.0
	if index == 0:
		Input.action_press("accelerate")


func _finish() -> void:
	car.free()
	city.free()
	quit()


func _physics_process(delta: float) -> bool:
	if index < 0 or index >= posts.size():
		return false
	t += delta
	var post: FallingPole = posts[index]
	tilted = maxf(tilted, post.angle_degrees())
	var flat := Vector2(car.global_position.x - post.foot.x, car.global_position.z - post.foot.z)
	closest = minf(closest, flat.length())
	if post.angle_degrees() > 80.0 and lying_high == 0.0:
		var visual := post.get_child(0) as MeshInstance3D
		var lying: AABB = visual.global_transform * visual.get_aabb()
		lying_low = lying.position.y
		lying_high = lying.end.y
	if fell_at < 0.0:
		if tilted > 45.0:
			fell_at = t
		elif t > 6.0:
			_next()
		return false
	if post.angle_degrees() <= 0.5 and stood_up_at < 0.0:
		stood_up_at = t - fell_at
	if t > fell_at + 10.0:
		_next()
	return false
