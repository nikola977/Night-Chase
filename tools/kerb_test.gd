extends SceneTree
## Kerb test: drive north from the road over the 20 cm kerb onto the pavement at
## several spots and report whether the car gets up there.
##   Godot --headless --path . -s res://tools/kerb_test.gd

const SPOTS: Array[Vector3] = [
	Vector3(-300.0, 1.0, -72.0), Vector3(-250.0, 1.0, -72.0), Vector3(-200.0, 1.0, -72.0),
	Vector3(-170.0, 1.0, -72.0), Vector3(-100.0, 1.0, -72.0), Vector3(-40.0, 1.0, -72.0),
]

var car: Car
var city: CityMap
var index := -1
var t := 0.0
var start_z := 0.0
var best_z := 0.0
var best_y := 0.0


func _initialize() -> void:
	city = CityMap.new()
	root.add_child(city)
	car = load("res://scenes/car.tscn").instantiate()
	root.add_child(car)
	city.build(car)
	_next()


func _next() -> void:
	Input.action_release("accelerate")
	index += 1
	if index >= SPOTS.size():
		quit()
		return
	city.spawn_point = SPOTS[index]
	city.spawn_heading = 180.0
	var start := city.start_transform()
	car.teleport(start, true)
	car.linear_velocity = Vector3.ZERO
	start_z = start.origin.z
	best_z = start_z
	best_y = 0.0
	t = 0.0
	Input.action_press("accelerate")


func _physics_process(delta: float) -> bool:
	if car == null:
		return false
	t += delta
	if car.global_position.z < best_z:
		best_z = car.global_position.z
	best_y = maxf(best_y, car.global_position.y)
	if t > 4.0:
		var climbed := best_z < start_z - 8.0
		print("  x %6.1f: z %.1f -> %.1f (%+.1f m), höchste y %.2f, Tempo %.0f km/h  %s" % [
			SPOTS[index].x, start_z, best_z, best_z - start_z, best_y,
			car.linear_velocity.length() * 3.6, "über den Bordstein" if climbed else "bleibt hängen"])
		_next()
	return false
