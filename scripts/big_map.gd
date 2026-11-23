class_name BigMap
extends CanvasLayer
## Große Karte (Taste M). Das Spiel pausiert, solange sie offen ist.
## Mausrad = zoomen (um den Mauszeiger), linke Maustaste ziehen = verschieben,
## Linksklick = Ziel setzen, Rechtsklick = Ziel löschen, M oder Esc = schließen.

@export var car: Car
@export var roads: RoadNetwork
@export var navigation: Navigation
@export var tiles: MapTiles
@export var viewpoints: Viewpoints
@export var exploration: Exploration
## Start-Maßstab und Grenzen (Meter pro Pixel)
@export var start_meters_per_pixel: float = 6.0
@export var min_meters_per_pixel: float = 1.0
@export var max_meters_per_pixel: float = 48.0
## City map: the block is 558 x 234 m, so it needs a smaller scale than the endless world
@export var city_meters_per_pixel: float = 0.6
@export var city_min_meters_per_pixel: float = 0.25

var is_open: bool = false
var _map: MapView
var _info: Label
var _dragging: bool = false
var _drag_distance: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(_on_map_input)
	add_child(catcher)
	_map = MapView.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.car = car
	_map.roads = roads
	_map.tiles = tiles
	_map.viewpoints = viewpoints
	_map.exploration = exploration
	_map.show_unknown = true
	if navigation:
		_map.set_navigation(navigation)
	catcher.add_child(_map)
	# Hinweise unten in einer Glas-Leiste
	var bar := GlassPanel.new()
	bar.radius = 20.0
	bar.size = Vector2(1100.0, 76.0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 40)
	add_child(bar)
	_info = UiStyle.label("", 15, "medium", UiStyle.TEXT)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(_info)
	visible = false


## City map: hand the picture and its world rectangle (x/z) to the map view
func set_city_map(texture: Texture2D, bounds: Rect2) -> void:
	if texture == null:
		return
	_map.city_texture = texture
	_map.city_bounds = bounds
	# The picture may arrive while the map is already open (it is drawn in the background)
	if is_open:
		_fit_city()
	_map.queue_redraw()


## City map (second map): a picture instead of the road network, so there are no
## destinations there and the map opens showing the whole block
func _is_city() -> bool:
	return _map.city_texture != null


func open() -> void:
	is_open = true
	UiFade.set_shown(self, true)
	get_tree().paused = true
	# Die große Karte ist komplett offen: kein Nebel mehr
	if exploration:
		exploration.enabled = false
	if _is_city():
		# Die Stadt ist nur 558 x 234 m groß: den ganzen Block so groß zeigen, wie der
		# Bildschirm es zulässt (statt eines festen Maßstabs, der nur zwei Drittel füllte)
		_fit_city()
	else:
		_map.center = Vector2(car.global_position.x, car.global_position.z)
		_map.meters_per_pixel = start_meters_per_pixel


## Stadtkarte: Maßstab so wählen, dass der ganze Block ins Bild passt, und auf die Mitte
## des Blocks zentrieren (am Auto zentriert würde ein Rand den Block aus dem Bild schieben)
func _fit_city() -> void:
	var bounds := _map.city_bounds
	var view := _map.size
	if bounds.size.x < 1.0 or bounds.size.y < 1.0 or view.x < 1.0 or view.y < 1.0:
		_map.center = Vector2(car.global_position.x, car.global_position.z)
		_map.meters_per_pixel = city_meters_per_pixel
		return
	# Rundherum 4 % Luft, damit der Rahmen der Karte nicht am Bildrand klebt
	var fit := maxf(bounds.size.x / view.x, bounds.size.y / view.y) / 0.96
	_map.meters_per_pixel = clampf(fit, city_min_meters_per_pixel, max_meters_per_pixel)
	_map.center = bounds.get_center()


func close() -> void:
	is_open = false
	UiFade.set_shown(self, false)
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		if is_open:
			close()
		elif not get_tree().paused:
			open()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_open:
		return
	_map.queue_redraw()
	if _is_city():
		_info.text = "City Block  ·  Mouse wheel zoom  ·  Drag to pan  ·  M close"
		return
	var text := "Left click set destination  ·  Right click clear destination  ·  Mouse wheel zoom  ·  Drag to pan  ·  M close"
	if navigation.has_target and not navigation.route_points.is_empty():
		text = "Destination: %s · approx. %d min      " % [Navigation.format_distance(navigation.remaining_distance()),
			maxi(roundi(navigation.remaining_minutes()), 1)] + text
	text += "\nParking areas and rest stops are car meet spots  ·  Dashed: connections and tunnels not calculated yet"
	if exploration and exploration.enabled:
		text += "  ·  In the fog: not discovered yet"
	_info.text = text


func _on_map_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse:
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mouse.pressed:
				_zoom_at(mouse.position, 0.85 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.85)
		elif mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_dragging = true
				_drag_distance = 0.0
			else:
				_dragging = false
				# Kaum bewegt: das war ein Klick, kein Verschieben. Die Stadt hat keine Straßen,
				# also gibt es dort auch kein Ziel
				if _drag_distance < 5.0 and navigation and not _is_city():
					var p := _map.screen_to_world(mouse.position)
					navigation.set_target(Vector3(p.x, 0.0, p.y))
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed and navigation:
			navigation.clear_target()
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		_drag_distance += motion.relative.length()
		_map.center -= motion.relative * _map.meters_per_pixel


## Zoomen, ohne dass sich der Punkt unter der Maus bewegt
func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var before := _map.screen_to_world(screen_position)
	var low := city_min_meters_per_pixel if _is_city() else min_meters_per_pixel
	_map.meters_per_pixel = clampf(_map.meters_per_pixel * factor, low, max_meters_per_pixel)
	var after := _map.screen_to_world(screen_position)
	_map.center += before - after
