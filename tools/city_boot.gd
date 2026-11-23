extends SceneTree
## Saves the first rendered frames of the city boot, so a flash of wrong
## geometry (for example the placeholder cars) can be found.
##
##   Godot_v4.7.2-stable_win64.exe --path . --resolution 1280x800 -s res://tools/city_boot.gd

const FRAMES := 90

var _main: Node
var _frame := 0
var _saved := 0


func _initialize() -> void:
	var mode = load("res://scripts/city_mode.gd")
	mode.enabled = true
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	var image := root.get_texture().get_image()
	if image != null and not image.is_empty() and _saved < FRAMES:
		image.save_png("res://screenshots/boot_%03d.png" % _saved)
		_saved += 1
		if _saved % 10 == 0:
			print("BOOT: frame %d (t=%d ms, world ready=%s)" % [_saved, Time.get_ticks_msec(), str(_main.world_is_ready)])
	if _saved == 30:
		print("BOOT: taa=%s, loading screen visible=%s" % [str(root.use_taa),
			str((_main.get_node_or_null("Loading/LoadingScreen") as CanvasItem).visible)])
	if _saved >= FRAMES:
		print("BOOT: done, %d frames" % _saved)
		quit()
		return true
	return false
