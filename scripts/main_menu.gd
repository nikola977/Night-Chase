extends CanvasLayer
## Startmenü: erscheint nach dem Ladebildschirm. Fahren, Garage, Einstellungen, Credits, Beenden.

var garage: Garage
var pause_menu: PauseMenu

var _credits: Control


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_credits.visible = false


func _close() -> void:
	visible = false
	get_tree().paused = false


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := Control.new()
	panel.size = Vector2(640.0, 560.0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	root.add_child(panel)
	var glass := GlassPanel.new()
	glass.radius = 32.0
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(glass)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	box.add_child(UiStyle.label("NIGHT CHASE", 34, "extrabold"))
	box.add_child(UiStyle.label("Endless roads, eight cars, every season", 16, "regular", UiStyle.TEXT_DIM))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 18.0)
	box.add_child(spacer)
	box.add_child(_button("Drive", true, _close))
	# Second map: offer the other world instead of the one already loaded
	if _city_loaded():
		box.add_child(_button("Endless world", false, _open_endless))
	else:
		box.add_child(_button("City Block", false, _open_city))
	box.add_child(_button("Garage", false, _open_garage))
	box.add_child(_button("Settings", false, _open_settings))
	box.add_child(_button("Credits", false, func() -> void: _credits.visible = true))
	box.add_child(_button("Quit", false, func() -> void: get_tree().quit()))
	_credits = _build_credits()
	_credits.visible = false
	root.add_child(_credits)


## Is the second map loaded? Set by the menus themselves or by --track=city
func _city_loaded() -> bool:
	return CityMode.enabled or OS.get_cmdline_user_args().has("--track=city")


func _button(text: String, accent: bool, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 58.0)
	button.add_theme_font_override("font", UiStyle.font("semibold"))
	button.add_theme_font_size_override("font_size", 20)
	if accent:
		for state in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, UiStyle.box(UiStyle.accent, 16))
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(state, Color(0.043, 0.082, 0.188))
	else:
		var normal := UiStyle.box(Color(1, 1, 1, 0.06), 16, Color(1, 1, 1, 0.2), 1)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", UiStyle.box(Color(1, 1, 1, 0.14), 16))
		button.add_theme_stylebox_override("pressed", UiStyle.box(Color(1, 1, 1, 0.1), 16))
		button.add_theme_color_override("font_color", UiStyle.TEXT)
	button.pressed.connect(on_press)
	return button


## Second map: the main scene reloads and loads the city instead of the endless world
func _open_city() -> void:
	visible = false
	get_tree().paused = false
	CityMode.enabled = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## … and back to the endless world
func _open_endless() -> void:
	visible = false
	get_tree().paused = false
	CityMode.enabled = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _open_garage() -> void:
	visible = false
	if garage:
		garage.open()
	else:
		get_tree().paused = false


func _open_settings() -> void:
	visible = false
	if pause_menu:
		pause_menu.open()
		pause_menu.show_settings_tab(0)
	else:
		get_tree().paused = false


func _build_credits() -> Control:
	var overlay := Control.new()
	overlay.size = Vector2(820.0, 520.0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	var glass := GlassPanel.new()
	glass.radius = 28.0
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(glass)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 34)
	overlay.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := UiStyle.label("Credits", 26, "extrabold")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 14)
	close.pressed.connect(func() -> void: overlay.visible = false)
	header.add_child(close)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_override("normal_font", UiStyle.font("regular"))
	text.add_theme_font_override("bold_font", UiStyle.font("semibold"))
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 16)
	text.text = "[b]Night Chase 1.0[/b]\n© 2026 N1ko7a — game, code, world generation, sound\n\n" \
		+ "Car models from Sketchfab (see the garage credits for every model and licence).\n" \
		+ "Font: Inter (SIL Open Font License). Textures: Poly Haven (CC0).\n" \
		+ "Engine: Godot 4 (MIT), physics: Jolt (MIT)."
	box.add_child(text)
	return overlay
