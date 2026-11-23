extends Node
## Temporary: follows an AI car with a close camera so the model's look can be inspected.

var _main: Node
var _cam: Camera3D
var _car: Node3D
var _which: int = 2

func _ready() -> void:
	var mode := load("res://scripts/city_mode.gd")
	mode.enabled = true
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_run()

func _run() -> void:
	for i in 6000:
		await get_tree().process_frame
		if _main.get("world_is_ready") == true:
			break
	var menu := _main.get_node_or_null("MainMenu")
	if menu:
		if menu is CanvasItem:
			(menu as CanvasItem).visible = false
		menu.queue_free()
	get_tree().paused = false
	# A clear midday sky so the colours read properly
	var day: Node = _main.get_node_or_null("DayNight")
	if day:
		day.set("time_of_day", 12.0)
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	for i in 200:
		await get_tree().process_frame
	var traffic: Node = _main.get_node_or_null("CityTraffic")
	var out := ""
	var shown := 0
	if traffic:
		var cars: Array = traffic.get("_cars")
		out += "cars=%d\n" % cars.size()
		if cars.size() > _which:
			_car = (cars[_which] as Object).get("node")
	var f := FileAccess.open("res://screenshots/city_traffic.txt", FileAccess.WRITE)
	if f:
		f.store_string(out)
		f.close()
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 230.0
	_cam.near = 1.0
	_cam.far = 2000.0
	_cam.position = Vector3(-130.0, 320.0, -110.0)
	_cam.rotation_degrees = Vector3(-90, 0, 0)
	_main.add_child(_cam)
	_cam.make_current()

func _process(_delta: float) -> void:
	pass