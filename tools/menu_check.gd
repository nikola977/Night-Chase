extends SceneTree
## Check: are the pause menu buttons right in city mode? The city has no road
## network, so "Map" and "Chill mode" stay out and the map button offers
## "Endless world" instead of "City block".
##   Godot --headless --path . -s res://tools/menu_check.gd

var main: Node
var t := 0.0


func _initialize() -> void:
	CityMode.enabled = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	if t < 2.5:
		return false
	var pause := main.get_node_or_null("PauseMenu")
	if pause == null:
		print("no pause menu")
		quit()
		return false
	pause.open()
	var labels := PackedStringArray()
	_collect(pause, labels)
	print("Pause menu buttons in city mode: ", ", ".join(labels))
	print("Minimap visible: %s" % str((main.get_node("HUD/Minimap") as Control).visible))
	quit()
	return false


func _collect(node: Node, labels: PackedStringArray) -> void:
	if node is Button and (node as Button).text != "":
		labels.append((node as Button).text.split("\n")[0])
	for child in node.get_children():
		_collect(child, labels)
