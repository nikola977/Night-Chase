class_name FastTravel
extends CanvasLayer
## Schnellreise (Taste T): Liste der Raststätten („MEET“) im Umkreis. Auswählen, Enter:
## Das Auto springt dorthin und wird dort auf die Straße gestellt – mit Ladebildschirm,
## wie bei einem Teleport (game.jump_to). Solange die Liste offen ist, steht das Spiel
## (wie bei der großen Karte). Später stehen die Garagen in derselben Liste.
##
## Die Raststätten kommen aus der Welt-Formel (highways.rest_areas_in), es wird also nichts
## gebaut und nichts gespeichert: Die Liste ist bei jedem Öffnen dieselbe, solange man
## nicht fährt. Gesucht wird in einem Quadrat um das Auto; die nächsten Einträge kommen
## nach oben, mehr als max_entries zeigt die Liste nicht.

@export var car: Car
@export var roads: RoadNetwork
## Hauptknoten (game.gd): macht den Sprung samt Ladebildschirm
@export var main: Node3D
@export var hud: CanvasLayer
@export var garage: Garage
@export var big_map: BigMap
@export var photo_mode: PhotoMode
## So weit werden Raststätten gesucht (Meter)
@export var radius: float = 25000.0
## So viele Einträge zeigt die Liste höchstens (die nächsten)
@export var max_entries: int = 18
## Näher als das gilt als „du stehst schon hier“ (Meter)
@export var here_distance: float = 300.0

var is_open: bool = false

## Für die Liste: [{"name", "view", "center" (Vector3), "distance"}]
var _entries: Array = []
var _list: VBoxContainer
var _empty: Label
var _buttons: Array[Button] = []

const VIEW_NAMES := {"lake": "lake view", "mountain": "mountain view"}


func _ready() -> void:
	# Die Liste hält das Spiel an, muss aber selbst weiterlaufen (Tasten, Maus)
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 14
	_build()
	visible = false


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Dahinter abdunkeln; die Fläche fängt auch alle Klicks ab
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var panel := GlassPanel.new()
	panel.radius = 24.0
	panel.size = Vector2(640.0, 580.0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(UiStyle.label("Fast travel", 26, "extrabold"))
	var info := UiStyle.label("Rest areas nearby — pick one and the car is placed on the road there.",
		13, "medium", UiStyle.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(info)

	var line := ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, 0.1)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)

	# Eigener Rahmen für die Liste: Er nimmt den freien Platz und schneidet alles ab, was
	# nicht mehr hineinpasst (sonst würden die Zeilen unten aus dem Panel laufen)
	var view := Control.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(0.0, 300.0)
	view.clip_contents = true
	column.add_child(view)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_empty = UiStyle.label("No rest area within %d km." % roundi(radius / 1000.0), 15, "medium",
		UiStyle.TEXT_FAINT)
	_empty.visible = false
	column.add_child(_empty)

	var hint := UiStyle.label("↑ ↓ choose   ·   Enter travel   ·   %s / Esc close"
		% GameSettings.action_key("fast_travel"), 13, "medium", UiStyle.TEXT_FAINT)
	column.add_child(hint)


func open() -> void:
	if is_open or car == null:
		return
	is_open = true
	_entries = _destinations()
	_fill()
	UiFade.set_shown(self, true)
	get_tree().paused = true


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiFade.set_shown(self, false)
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fast_travel"):
		if is_open:
			close()
		elif not get_tree().paused:
			open()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Raststätten rund um das Auto, die nächsten zuerst
func _destinations() -> Array:
	var here := Vector2(car.global_position.x, car.global_position.z)
	var rect := Rect2(here - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	var found: Array = []
	for rest: Dictionary in roads.highways.rest_areas_in(rect):
		var center: Vector3 = rest["center"]
		var distance := Vector2(center.x, center.z).distance_to(here)
		if distance < here_distance:
			continue
		found.append({"name": rest["name"], "view": rest["view"], "center": center, "distance": distance})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	if found.size() > max_entries:
		found.resize(max_entries)
	return found


func _fill() -> void:
	for button in _buttons:
		_list.remove_child(button)
		button.queue_free()
	_buttons.clear()
	_empty.visible = _entries.is_empty()
	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		var text: String = entry["name"]
		var view: String = entry["view"]
		if VIEW_NAMES.has(view):
			text += "   ·   " + VIEW_NAMES[view]
		text += "   ·   %.1f km" % (entry["distance"] / 1000.0)
		var button := Button.new()
		button.text = text
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(0.0, 44.0)
		button.add_theme_font_override("font", UiStyle.font("medium"))
		button.add_theme_font_size_override("font_size", 16)
		_style_row(button)
		button.pressed.connect(_travel.bind(i))
		_list.add_child(button)
		_buttons.append(button)
	if not _buttons.is_empty():
		_buttons[0].grab_focus.call_deferred()


## Zeile: ruhig im Ruhezustand, heller unter der Maus, Akzentfarbe mit Tastatur-Fokus
func _style_row(button: Button) -> void:
	var normal := UiStyle.box(Color(1.0, 1.0, 1.0, 0.05), 10)
	normal.set_content_margin_all(12)
	normal.content_margin_top = 9
	normal.content_margin_bottom = 9
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.11)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(UiStyle.accent, 0.22)
	focus.border_color = Color(UiStyle.accent, 0.9)
	focus.set_border_width_all(1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", UiStyle.TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)


## Reisen: Liste schließen, dann springt das Spiel an die Raststätte und stellt das Auto dort
## auf die Straße (game.jump_to zeigt dabei den Ladebildschirm)
func _travel(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry: Dictionary = _entries[index]
	var center: Vector3 = entry["center"]
	close()
	if main and main.has_method("jump_to"):
		main.jump_to(Vector2(center.x, center.z))
		Toasts.post(get_tree(), "pin", "Fast travel", entry["name"])
