class_name BuildEditor
extends Node
## Uređivač sveta u igri (F2). Uvozi .glb/.gltf modele sa diska, postavlja ih u svet, pomera,
## rotira, skalira, briše i duplira, pravi od modela novo vozilo za garažu i sve čuva u
## user://editor/layout.json — tako da ostane i posle zatvaranja igre.
##
## Tasteri dok je editor otvoren:
##   WASD leti, Space/Ctrl gore/dole, Shift brže, točkić menja brzinu, miš gleda
##   Tab pušta kursor (za panel), LMB postavlja model ili bira objekat
##   Z/X rotira 15°, [ ] skalira, strelice/PageUp/PageDown pomera izabrano
##   Del briše, Ctrl+D duplira, Ctrl+Z poništava, Ctrl+S čuva, F2 zatvara
##   E ulazi u izabrani objekat (nove stvari se prave unutra), E ponovo izlazi
## U mapi City Block se i kuće/blokovi/ulice iz samog grada mogu birati, pomerati,
## rotirati, skalirati i brisati (čuva se u user://editor/city_layout.json).
## Pored modela editor sam pravi i ravan put i ploču terena (proceduralno, sa kolizijom),
## tako da može da se pravi i proširuje mapa bez ijednog spoljnog fajla.

const LAYOUT_PATH := "user://editor/layout.json"
const IMPORT_DIR := "user://editor/models"
## Uvezeni modeli se posle prvog učitavanja pretvaraju u Godot resurs: veliki .glb
## (npr. 112 MB) čita GLTFDocument po nekoliko desetina sekundi pri svakom startu igre.
const CACHE_DIR := "user://editor/cache"
const CAR_DIR := "user://editor/cars"
const MODELS_DIR := "res://assets/models"
## Korak rotacije i pomeranja izabranog objekta
const ROT_STEP := 15.0
const MOVE_STEP := 1.0
const SCALE_STEP := 1.1
const SCALE_MIN := 0.02
const SCALE_MAX := 200.0
## Koliko daleko ide zrak iz kamere
const RAY_LENGTH := 6000.0
## Do koliko trouglova se pravi tačna (trimesh) kolizija za postavljeni model. Veći
## modeli dobijaju pojednostavljenu koliziju od kutija po delu, da se ipak ne može
## proći kroz njih (ranije su veliki modeli ostajali bez ikakve kolizije).
const COLLISION_TRIANGLES := 500000
## Proceduralni delovi koje editor pravi sam (ne postoje kao model): ravan put i ploča terena
const ROAD_MODEL := "@road"
const PAD_MODEL := "@pad"
const ROAD_LENGTH := 40.0
const ROAD_WIDTH := 9.0
const PAD_SIZE := 20.0
## Proceduralni delovi se podignu ovoliko iznad pogodjenog tla (da ne titra sa terenom)
const PROCEDURAL_LIFT := 0.04
## Koliko blizu kraja nekog puta se novi put sam spoji sa njim (metri)
const SNAP_DISTANCE := 12.0

## Emitovan kada je sačuvani raspored (i sve unutar njega) postavljen u svet
signal layout_loaded

## Igra (scenes/main.tscn), postavlja se pre add_child
var game: Node3D
## Auto igrača: dok je editor otvoren stoji
var car: VehicleBody3D
## Mapa City Block (CityMap) dok je otvorena; null u endless svetu. Gradski objekti
## (kuće, blokovi, putevi iz modela) se tada mogu birati, pomerati, rotirati i brisati.
var city_map: Node3D
## Je li editor otvoren
var active: bool = false

var _camera: Camera3D
var _previous_camera: Camera3D
var _objects: Node3D
var _ghost: Node3D
var _ghost_box: MeshInstance3D
var _selection_box: MeshInstance3D
var _ui: CanvasLayer
var _hint: Label
var _crosshair: Label
var _list: ItemList
var _status: Label

var _pos_spins: Array[SpinBox] = []
var _rot_spins: Array[SpinBox] = []
var _scale_spin: SpinBox
var _road_row: HBoxContainer
var _road_length_spin: SpinBox
var _road_width_spin: SpinBox
var _collision_check: CheckBox
var _props_box: VBoxContainer
var _props_title: Label
## Dugmad koja imaju smisla samo za modele koje je editor postavio (ne za grad)
var _model_only: Array[Control] = []

var _placing: String = ""
var _ghost_rotation: float = 0.0
var _ghost_scale: float = 1.0
var _ghost_size := Vector3(2.0, 2.0, 2.0)
## Gde duh stoji u svetu (prikačen za kraj puta ili na nišanu)
var _ghost_position := Vector3.ZERO
## true kada je duh puta prikačen na kraj drugog puta
var _ghost_snapped := false
var _snap_check: CheckBox
var _snap_marker: MeshInstance3D
var _selection: Node3D
## Objekat u koji je korisnik ušao: novi delovi se dodaju unutra (u njegovim koordinatama)
var _inside: Node3D
var _inside_row: HBoxContainer
var _inside_label: Label
## Stanje sveta pre otvaranja editora (pauza i utišan glavni kanal)
var _tree_paused: bool = false
var _master_muted: bool = false
## Učitani modeli (putanja -> Node3D), da se isti model ne učitava više puta
var _cache: Dictionary = {}
## Unosi iz layout.json čiji model ne postoji (ostaju sačuvani)
var _missing: Array = []

var _cam_pos := Vector3.ZERO
var _cam_yaw := 0.0
var _cam_pitch := -0.25
var _cam_speed := 15.0
var _car_was_frozen := false
var _pause_menu_mode: ProcessMode
var _updating_ui := false
## Istorija za undo (Ctrl+Z): svaki unos je snimak svih objekata PRE izmene
var _history: Array = []
const UNDO_LIMIT := 60
## true dok se raspored vraća iz istorije (tada se ne pravi novi undo korak)
var _restoring := false
## Prevlačenje izabranog objekta mišem
var _dragging := false
var _drag_pushed := false
## Kratka poruka na vrhu ekrana (npr. kada F2 ne može da se otvori)
var _toast_layer: CanvasLayer
var _toast_label: Label
var _toast_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_objects = Node3D.new()
	_objects.name = "EditorObjects"
	add_child(_objects)
	_build_camera()
	_build_ghost()
	_build_selection_box()
	_build_ui()
	_build_toast()
	set_process(false)
	_load_layout.call_deferred()


# ---------------------------------------------------------------------------
# Otvaranje i zatvaranje
# ---------------------------------------------------------------------------

## Može li editor da se otvori (svet je učitan, nijedan meni nije otvoren)
func _can_open() -> bool:
	if game == null or not bool(game.get("world_is_ready")):
		return false
	for overlay in ["MainMenu", "Garage", "PauseMenu", "BigMap", "PhotoMode", "Dyno"]:
		var node := game.get_node_or_null(overlay) as CanvasItem
		if node and node.visible:
			return false
	return true


func open() -> void:
	if active:
		return
	active = true
	set_process(true)
	_ui.visible = true
	_previous_camera = get_viewport().get_camera_3d()
	# Auto stoji dok se pravi svet (motor i fizika ne rade)
	if car:
		_car_was_frozen = car.freeze
		car.freeze = true
	# Sve oko tebe stane dok letiš: NPC auta, motor, saobraćaj i vreme
	_tree_paused = get_tree().paused
	get_tree().paused = true
	_master_muted = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	# Pauza meni ne sme da se otvori dok je editor tu (Esc pripada editoru)
	var pause_menu := game.get_node_or_null("PauseMenu") as Node
	if pause_menu:
		_pause_menu_mode = pause_menu.process_mode
		pause_menu.process_mode = Node.PROCESS_MODE_DISABLED
	# Kamera: iza auta, blago nadole
	if car:
		_cam_pos = car.global_position + Vector3(0.0, 6.0, 11.0)
		_cam_yaw = car.global_rotation.y
	_cam_pitch = -0.3
	_place_camera()
	_camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_crosshair.visible = true
	_refresh_library()
	_set_status("F2 zatvara. Izaberi model i klikni „Postavi u svet“. Klik bira objekat, klik na izabrani pa vuci = pomeranje.")
	_update_props()


func close() -> void:
	if not active:
		return
	active = false
	set_process(false)
	_dragging = false
	_cancel_placement()
	_select(null)
	_ui.visible = false
	_save_layout()
	_save_city_layout()
	_refresh_traffic()
	_inside = null
	_refresh_inside()
	if car:
		car.freeze = _car_was_frozen
	# Svet i zvuk se vraćaju tačno u stanje pre editora
	AudioServer.set_bus_mute(0, _master_muted)
	get_tree().paused = _tree_paused
	var pause_menu := game.get_node_or_null("PauseMenu") as Node
	if pause_menu:
		pause_menu.process_mode = _pause_menu_mode
	if _previous_camera and is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	_save_layout()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F2:
		if active:
			if not _modal_open():
				close()
		elif _can_open():
			open()
		else:
			# Kaži zašto se editor ne otvara (otvoren meni ili se svet još učitava)
			_toast(_open_blocker())
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	# Miš gleda samo dok je uhvaćen (Tab pušta kursor za panel); dok se objekat vuče, miš pomera njega
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		if _dragging:
			_drag_by(motion.relative)
		else:
			_cam_yaw -= motion.relative.x * 0.0025
			_cam_pitch = clampf(_cam_pitch - motion.relative.y * 0.0025, -1.5, 1.5)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_speed = minf(_cam_speed * 1.15, 300.0)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_speed = maxf(_cam_speed / 1.15, 1.0)


func _ui_has_focus() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is SpinBox or focus is TextEdit


## Je li otvoren neki dijalog editora (uvoz modela, „Novo vozilo“)
func _modal_open() -> bool:
	for child in get_children():
		if child is AcceptDialog and (child as AcceptDialog).visible:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if _ui_has_focus():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if not button.pressed:
				if _dragging:
					_end_drag()
					get_viewport().set_input_as_handled()
			elif _placing != "":
				_place_current()
				get_viewport().set_input_as_handled()
			else:
				# Klik na već izabran objekat počinje pomeranje, klik na drugi ga bira
				var picked := _pick_at_aim()
				if picked != null and picked == _selection:
					_begin_drag()
				else:
					_select(picked)
				get_viewport().set_input_as_handled()
		elif button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
			if _placing != "":
				_cancel_placement()
			else:
				_select(null)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		_handle_key(key)


func _handle_key(key: InputEventKey) -> void:
	var ctrl := key.ctrl_pressed
	match key.keycode:
		KEY_ESCAPE:
			if _placing != "":
				_cancel_placement()
			elif _selection:
				_select(null)
			elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_set_cursor_free()
		KEY_TAB:
			_set_cursor_free() if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else _grab_cursor()
		KEY_Z:
			if ctrl:
				_undo()
			else:
				_rotate_active(-ROT_STEP)
		KEY_X:
			_rotate_active(ROT_STEP)
		KEY_BRACKETLEFT:
			_scale_active(1.0 / SCALE_STEP)
		KEY_BRACKETRIGHT:
			_scale_active(SCALE_STEP)
		KEY_DELETE:
			_delete_aimed()
		KEY_D:
			if ctrl:
				_duplicate_selection()
		KEY_E:
			if _placing == "":
				if _inside != null:
					_exit_object()
				else:
					_enter_object()
		KEY_S:
			if ctrl:
				_save_layout()
				_set_status("Sačuvano u %s" % LAYOUT_PATH)
		KEY_LEFT:
			_nudge(-_flat_right() * MOVE_STEP)
		KEY_RIGHT:
			_nudge(_flat_right() * MOVE_STEP)
		KEY_UP:
			_nudge(_flat_forward() * MOVE_STEP)
		KEY_DOWN:
			_nudge(-_flat_forward() * MOVE_STEP)
		KEY_PAGEUP:
			_nudge(Vector3.UP * MOVE_STEP)
		KEY_PAGEDOWN:
			_nudge(-Vector3.UP * MOVE_STEP)
		_:
			return
	get_viewport().set_input_as_handled()


func _set_cursor_free() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_crosshair.visible = false


func _grab_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_crosshair.visible = true


# ---------------------------------------------------------------------------
# Kamera
# ---------------------------------------------------------------------------

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "BuilderCamera"
	_camera.fov = 70.0
	_camera.near = 0.05
	_camera.far = 25000.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)


func _place_camera() -> void:
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0.0)), _cam_pos)


func _process(delta: float) -> void:
	if not active:
		return
	_move_camera(delta)
	_update_ghost()
	_update_selection_box()


func _move_camera(delta: float) -> void:
	# Dok se kuca u polje panela (npr. naziv vozila), WASD ne sme da pomera kameru
	if _ui_has_focus():
		return
	var direction := Vector3.ZERO
	var basis := _camera.global_basis
	if Input.is_physical_key_pressed(KEY_W):
		direction -= basis.z
	if Input.is_physical_key_pressed(KEY_S):
		direction += basis.z
	if Input.is_physical_key_pressed(KEY_A):
		direction -= basis.x
	if Input.is_physical_key_pressed(KEY_D):
		direction += basis.x
	if Input.is_physical_key_pressed(KEY_SPACE):
		direction += Vector3.UP
	if Input.is_physical_key_pressed(KEY_CTRL):
		direction -= Vector3.UP
	var speed := _cam_speed * (4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	if direction != Vector3.ZERO:
		_cam_pos += direction.normalized() * speed * delta
	_place_camera()


func _flat_forward() -> Vector3:
	return Vector3(-sin(_cam_yaw), 0.0, -cos(_cam_yaw))


func _flat_right() -> Vector3:
	return Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))


# ---------------------------------------------------------------------------
# Ciljanje (zrak iz kamere)
# ---------------------------------------------------------------------------

## Tačka na ekranu iz koje ide zrak: nišan u sredini dok je miš uhvaćen, inače kursor
func _aim_screen() -> Vector2:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return get_viewport().get_visible_rect().size * 0.5
	return get_viewport().get_mouse_position()


## Polazna tačka i smer zraka iz kamere
func _aim_ray() -> Array:
	var screen := _aim_screen()
	return [_camera.project_ray_origin(screen), _camera.project_ray_normal(screen)]


func _aim_point() -> Variant:
	var ray := _aim_ray()
	var from: Vector3 = ray[0]
	var to := from + (ray[1] as Vector3) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if car:
		query.exclude.append(car.get_rid())
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["position"]


## Objekat pod zrakom (onaj koji je editor postavio), ili null
func _pick_at_aim() -> Node3D:
	var ray := _aim_ray()
	var from: Vector3 = ray[0]
	var direction: Vector3 = ray[1]
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RAY_LENGTH, 1)
	query.collide_with_areas = false
	if car:
		query.exclude.append(car.get_rid())
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	var blocked := INF
	if not hit.is_empty():
		blocked = from.distance_to(hit["position"])
		var node := hit["collider"] as Node
		while node != null:
			if node.has_meta("builder_object") or node.has_meta("city_object"):
				return node as Node3D
			node = node.get_parent()
	# Objekti bez kolizije (veliki modeli): biraj po kutiji, ali samo ako je ispred svega
	# što je zrak već pogodio (inače bi se biralo kroz brdo ili zid)
	var best: Node3D = null
	var best_distance := INF
	for holder in _all_holders():
		var point: Variant = _world_aabb(holder).intersects_ray(from, direction)
		if point == null:
			continue
		var distance := from.distance_to(point)
		if distance <= blocked and distance < best_distance:
			best_distance = distance
			best = holder
	return best


# ---------------------------------------------------------------------------
# Modeli: biblioteka, uvoz, učitavanje
# ---------------------------------------------------------------------------

## Svi modeli u projektu (assets/models/<folder>/…) i uvezeni modeli (user://editor/models)
func _model_entries() -> Array:
	var entries: Array = []
	for folder in ResourceLoader.list_directory(MODELS_DIR):
		var path := _model_in_folder(MODELS_DIR.path_join(folder))
		if path != "":
			entries.append({"path": path, "title": _title_of(path)})
	if DirAccess.dir_exists_absolute(IMPORT_DIR):
		for file in DirAccess.get_files_at(IMPORT_DIR):
			var ext := file.get_extension().to_lower()
			if ext == "glb" or ext == "gltf":
				var path := IMPORT_DIR.path_join(file)
				entries.append({"path": path, "title": _title_of(path)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["title"]).naturalnocasecmp_to(str(b["title"])) < 0)
	return entries


## Prvi model u folderu (ili u folder/source): .glb pre .gltf, kao u CarModel.model_path
func _model_in_folder(folder: String) -> String:
	var found := {}
	for dir in [folder, folder.path_join("source")]:
		for file in ResourceLoader.list_directory(dir):
			var ext := file.get_extension().to_lower()
			if (ext == "glb" or ext == "gltf") and not found.has(ext):
				found[ext] = dir.path_join(file)
	for ext in ["glb", "gltf"]:
		if found.has(ext):
			return found[ext]
	return ""


func _refresh_library() -> void:
	if _list == null:
		return
	var selected := _selected_model()
	_list.clear()
	for entry: Dictionary in _model_entries():
		_list.add_item(entry["title"], null, true)
		_list.set_item_metadata(_list.item_count - 1, entry["path"])
		_list.set_item_tooltip(_list.item_count - 1, entry["path"])
	if selected != "":
		_select_model_in_list(selected)


func _select_model_in_list(path: String) -> void:
	for i in _list.item_count:
		if str(_list.get_item_metadata(i)) == path:
			_list.select(i)
			_list.ensure_current_is_visible()
			return


func _selected_model() -> String:
	var items := _list.get_selected_items()
	if items.is_empty():
		return ""
	return str(_list.get_item_metadata(items[0]))


func _title_of(path: String) -> String:
	var title := path.get_file().get_basename()
	if title == "" or title == "scene":
		title = path.get_base_dir().get_file()
	return title.replace("_", " ").replace("-", " ").strip_edges()


## Model kao Node3D (kopija iz keša)
func _instantiate(path: String) -> Node3D:
	if path == "":
		return null
	var source: Node3D = _cache.get(path)
	if source == null:
		source = _load_model(path)
		if source == null:
			return null
		_cache[path] = source
	return source.duplicate() as Node3D


func _load_model(path: String) -> Node3D:
	if _is_procedural(path):
		return _procedural_node(path, ROAD_LENGTH if path == ROAD_MODEL else PAD_SIZE,
			ROAD_WIDTH if path == ROAD_MODEL else PAD_SIZE)
	if path.begins_with("res://"):
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("Model se ne može učitati: " + path)
			return null
		return packed.instantiate() as Node3D
	_repair_gltf_textures(path)
	# Uvezeni model: ako je već jednom učitan, uzmi gotov Godot resurs (mnogo brže)
	var cache := _cache_path(path)
	if FileAccess.file_exists(cache):
		var packed := load(cache) as PackedScene
		if packed != null:
			return packed.instantiate() as Node3D
		push_warning("Keš modela nije ispravan, čitam ponovo: " + path)
	# user:// fajlovi nisu importovani: GLTFDocument ih čita direktno
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		push_warning("Model se ne može pročitati: " + path)
		return null
	var node := document.generate_scene(state)
	_save_model_cache(node, path, cache)
	return node


## Stariji uvoz je teksture kopirao u koren foldera iako .gltf traži npr. "textures/x.png".
## Ako fajl nedostaje, a isti takav postoji u korenu, prepiši ga gde model očekuje.
func _repair_gltf_textures(path: String) -> void:
	if path.get_extension().to_lower() != "gltf":
		return
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(json) != TYPE_DICTIONARY:
		return
	var folder := path.get_base_dir()
	for entry in (json as Dictionary).get("images", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var uri := str(entry.get("uri", ""))
		if uri == "" or uri.begins_with("data:") or uri.contains("://"):
			continue
		var target := folder.path_join(uri)
		if FileAccess.file_exists(target):
			continue
		var flat := folder.path_join(uri.get_file())
		if not FileAccess.file_exists(flat):
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
		DirAccess.copy_absolute(flat, ProjectSettings.globalize_path(target))


## Putanja keša zavisi od imena, veličine i datuma fajla: promenjeni model se ponovo čita
func _cache_path(path: String) -> String:
	var size := 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		size = file.get_length()
		file.close()
	var key := "%s_%d_%d" % [path.get_file().get_basename().validate_filename(), size,
		FileAccess.get_modified_time(path)]
	return CACHE_DIR.path_join(key + ".res")


## Sačuvaj učitani model kao Godot resurs (i skloni starije keševe istog modela)
func _save_model_cache(node: Node3D, path: String, cache: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var packed := PackedScene.new()
	if packed.pack(node) != OK:
		return
	if ResourceSaver.save(packed, cache) != OK:
		push_warning("Keš modela nije mogao da se sačuva: " + cache)
		return
	var prefix := path.get_file().get_basename().validate_filename() + "_"
	for file in DirAccess.get_files_at(CACHE_DIR):
		if file.begins_with(prefix) and CACHE_DIR.path_join(file) != cache:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE_DIR.path_join(file)))


## Uvoz sa diska: kopira model (i .bin/teksture pored njega) u user://editor/models
func _ask_import() -> void:
	var dialog := FileDialog.new()
	dialog.title = "Uvezi 3D model"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.glb, *.gltf ; 3D model"])
	dialog.use_native_dialog = true
	dialog.file_selected.connect(_on_file_selected)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)


func _on_file_selected(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(IMPORT_DIR))
	var source_dir := path.get_base_dir()
	var base := path.get_file().get_basename()
	for file in DirAccess.get_files_at(source_dir):
		var ext := file.get_extension().to_lower()
		# Samo fajlovi ovog modela, ne i ostali modeli iz istog foldera
		var wanted := (ext in ["glb", "gltf", "bin"] and file.get_basename() == base) \
			or (ext in ["png", "jpg", "jpeg", "webp", "ktx2"] and file.get_basename().begins_with(base))
		if not wanted:
			continue
		var target := IMPORT_DIR.path_join(file)
		if ProjectSettings.globalize_path(target) == path:
			continue
		DirAccess.copy_absolute(source_dir.path_join(file), ProjectSettings.globalize_path(target))
	# .gltf može da pokazuje na .bin i teksture pod drugim imenom — prepiši i njih
	if path.get_extension().to_lower() == "gltf":
		_copy_gltf_references(path)
	var target := IMPORT_DIR.path_join(path.get_file())
	var probe := _instantiate(target)
	if probe == null:
		_set_status("Model nije mogao da se učita: " + path.get_file())
		_refresh_library()
		return
	probe.free()
	_refresh_library()
	_select_model_in_list(target)
	_set_status("Uvezeno: %s. Klikni „Postavi u svet“." % path.get_file())


# ---------------------------------------------------------------------------
# Postavljanje
# ---------------------------------------------------------------------------

func _build_ghost() -> void:
	_ghost = Node3D.new()
	_ghost.name = "BuilderGhost"
	_ghost.visible = false
	add_child(_ghost)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.25, 1.0, 0.75, 0.25)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	box.material = material
	_ghost_box = MeshInstance3D.new()
	_ghost_box.mesh = box
	_ghost_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(_ghost_box)
	# Mala lopta na kraju puta sa kojim se novi put spaja
	_snap_marker = MeshInstance3D.new()
	_snap_marker.name = "BuilderSnapMarker"
	var marker := SphereMesh.new()
	marker.radius = 0.55
	marker.height = 1.1
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_material.albedo_color = Color(0.3, 1.0, 0.6, 0.6)
	marker.material = marker_material
	_snap_marker.mesh = marker
	_snap_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snap_marker.visible = false
	add_child(_snap_marker)


func _build_selection_box() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.85, 0.2, 0.12)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	box.material = material
	_selection_box = MeshInstance3D.new()
	_selection_box.name = "BuilderSelection"
	_selection_box.mesh = box
	_selection_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_box.visible = false
	add_child(_selection_box)


func _start_placement(path := "") -> void:
	if path == "":
		path = _selected_model()
	if path == "":
		_set_status("Izaberi model u listi.")
		return
	var probe := _instantiate(path)
	if probe == null:
		_set_status("Model nije mogao da se učita.")
		return
	var box := _local_aabb(probe)
	probe.free()
	_ghost_size = Vector3(maxf(box.size.x, 0.2), maxf(box.size.y, 0.2), maxf(box.size.z, 0.2))
	_placing = path
	_ghost_rotation = 0.0
	_ghost_scale = 1.0
	_ghost.visible = true
	_set_status("Postavljanje: %s — LMB postavlja, Z/X rotira, [ ] skalira, Esc otkazuje" % _display_name(path))


func _cancel_placement() -> void:
	_placing = ""
	_ghost.visible = false


func _update_ghost() -> void:
	if _placing == "":
		_ghost.visible = false
		_snap_marker.visible = false
		return
	var point: Variant = _aim_point()
	if point == null:
		_ghost.visible = false
		_snap_marker.visible = false
		return
	_ghost.visible = true
	_ghost_position = point
	_ghost_snapped = false
	# Put se sam prikači na kraj najbližeg puta (nastavak u istoj liniji)
	if _placing == ROAD_MODEL and _snap_check != null and _snap_check.button_pressed \
			and _active_parent() == _objects:
		var snap := _find_road_snap(point)
		if not snap.is_empty():
			_ghost_position = snap["pos"]
			_ghost_rotation = rad_to_deg(snap["yaw"])
			_ghost_snapped = true
			_snap_marker.visible = true
			_snap_marker.global_position = snap["end"]
			_set_status("Spojeno sa putem — LMB postavlja nastavak.")
	if not _ghost_snapped:
		_snap_marker.visible = false
	_ghost.global_position = _ghost_position
	_ghost.rotation.y = deg_to_rad(_ghost_rotation)
	var size := _ghost_size * _ghost_scale
	_ghost_box.scale = size
	_ghost_box.position = Vector3(0.0, size.y * 0.5, 0.0)


func _place_current() -> void:
	var point: Variant = _aim_point()
	if point == null:
		_set_status("Nema tla pod nišanom.")
		return
	var place_at: Vector3 = point
	var procedural := _is_procedural(_placing)
	if _ghost_snapped:
		place_at = _ghost_position
	elif procedural:
		place_at += Vector3.UP * PROCEDURAL_LIFT
	_push_undo()
	var parent := _active_parent()
	# Put i ploča terena uvek dobijaju koliziju, inače se po njima ne može voziti
	var holder := _spawn(_placing, parent.to_local(place_at), Vector3(0.0, deg_to_rad(_ghost_rotation), 0.0),
		_ghost_scale, _collision_check.button_pressed or procedural, 0.0, 0.0, parent)
	if holder == null:
		_history.pop_back()
		return
	# Unutar nagnutog, zarotiranog ili uvećanog objekta deo zadržava svoju svetsku veličinu
	if parent != _objects:
		holder.global_transform = Transform3D(
			Basis(Vector3.UP, deg_to_rad(_ghost_rotation)).scaled(Vector3.ONE * _ghost_scale), place_at)
	_save_layout()
	_refresh_traffic()
	_set_status("Postavljeno. Klikni na njega da ga pomeris (vuci misem), zamenis ili obrises.")


## Napravi objekat u svetu. Vraća holder ili null ako model ne postoji.
func _spawn(path: String, position: Vector3, rotation: Vector3, object_scale: float,
		collision: bool, road_length := 0.0, road_width := 0.0, parent: Node3D = null) -> Node3D:
	var instance := _instantiate(path)
	if instance == null:
		return null
	var target := parent if parent != null and is_instance_valid(parent) else _active_parent()
	var holder := Node3D.new()
	holder.name = "Prop"
	holder.set_meta("builder_object", true)
	holder.set_meta("model", path)
	holder.set_meta("collision", false)
	# true only when the user deliberately switched the collision off
	holder.set_meta("collision_off", false)
	target.add_child(holder)
	holder.add_child(instance)
	if _is_procedural(path):
		_set_procedural_size(holder, road_length if road_length > 0.0 else _default_length(path),
			road_width if road_width > 0.0 else _default_width(path))
	# Model stoji na tlu i u sredini svog tlocrta
	var box := _local_aabb(instance)
	instance.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	holder.position = position
	holder.rotation = rotation
	holder.scale = Vector3.ONE * clampf(object_scale, SCALE_MIN, SCALE_MAX)
	if collision:
		_set_collision(holder, true)
		if str(holder.get_meta("collision_mode", "")) == "boxes":
			_set_status("Veliki model: kolizija je pojednostavljena (kutije), ali se ne može proći kroz njega.")
	return holder


# ---------------------------------------------------------------------------
# Proceduralni delovi: ravan put i ploča terena
# ---------------------------------------------------------------------------

func _is_procedural(path: String) -> bool:
	return path == ROAD_MODEL or path == PAD_MODEL


func _default_length(path: String) -> float:
	return ROAD_LENGTH if path == ROAD_MODEL else PAD_SIZE


func _default_width(path: String) -> float:
	return ROAD_WIDTH if path == ROAD_MODEL else PAD_SIZE


func _display_name(path: String) -> String:
	if path == ROAD_MODEL:
		return "Put (ravni)"
	if path == PAD_MODEL:
		return "Ploča terena"
	return _title_of(path)


func _procedural_node(kind: String, length: float, width: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Road" if kind == ROAD_MODEL else "Pad"
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = _procedural_mesh(kind, length, width)
	root.add_child(surface)
	return root


## Ravan put (asfalt, ivice i isprekidana srednja linija) ili ploča terena, oba u ravni y = 0
func _procedural_mesh(kind: String, length: float, width: float) -> ArrayMesh:
	var l := clampf(length, 1.0, 5000.0)
	var w := clampf(width, 0.5, 500.0)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.92
	material.metallic = 0.0
	tool.set_material(material)
	var road := kind == ROAD_MODEL
	_procedural_quad(tool, Vector3(-w * 0.5, 0.0, -l * 0.5), Vector3(-w * 0.5, 0.0, l * 0.5),
		Vector3(w * 0.5, 0.0, l * 0.5), Vector3(w * 0.5, 0.0, -l * 0.5),
		Color(0.13, 0.135, 0.145) if road else Color(0.2, 0.27, 0.16))
	if road:
		var paint := Color(0.86, 0.87, 0.88)
		if w > 1.2:
			var edge := minf(w * 0.5 - 0.1, 0.35)
			_flat_rect(tool, -w * 0.5 + edge, -l * 0.5, l * 0.5, 0.12, paint)
			_flat_rect(tool, w * 0.5 - edge, -l * 0.5, l * 0.5, 0.12, paint)
		if w > 0.8:
			var z := -l * 0.5 + 2.0
			while z + 2.0 <= l * 0.5:
				_flat_rect(tool, 0.0, z, z + 2.0, 0.14, paint)
				z += 6.0
	return tool.commit()


func _procedural_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		color: Color) -> void:
	for point: Vector3 in [a, b, c, a, c, d]:
		tool.set_color(color)
		tool.set_normal(Vector3.UP)
		tool.add_vertex(point)


func _flat_rect(tool: SurfaceTool, center_x: float, z0: float, z1: float, width: float,
		color: Color) -> void:
	var y := 0.012
	var half := width * 0.5
	_procedural_quad(tool, Vector3(center_x - half, y, z0), Vector3(center_x - half, y, z1),
		Vector3(center_x + half, y, z1), Vector3(center_x + half, y, z0), color)


## Promena dužine/širine puta ili ploče: nova mreža i nova kolizija
func _set_procedural_size(holder: Node3D, length: float, width: float) -> void:
	holder.set_meta("road_length", length)
	holder.set_meta("road_width", width)
	var meshes := _meshes(holder)
	if meshes.is_empty():
		return
	var surface := meshes[0]
	var collision_on := bool(holder.get_meta("collision", false))
	for child in surface.get_children():
		if child is StaticBody3D:
			surface.remove_child(child)
			child.queue_free()
	surface.mesh = _procedural_mesh(str(holder.get_meta("model", "")), length, width)
	if collision_on:
		surface.create_trimesh_collision()


## Kolizija za postavljeni model (trimesh), dokle god nije previše trouglova
func _set_collision(holder: Node3D, on: bool) -> void:
	if bool(holder.get_meta("collision", false)) == on:
		return
	holder.set_meta("collision", on)
	# Tačna kolizija za normalne modele; za ogromne (npr. 1,6 miliona trouglova) kutije
	# po delu, jer trimesh od toliko trouglova košta previše pri svakom učitavanju
	var mode := "trimesh" if _add_collision_budget(holder) else "boxes"
	holder.set_meta("collision_mode", mode)
	for mesh_instance in _meshes(holder):
		if mesh_instance.mesh == null:
			continue
		var has_body := false
		for child in mesh_instance.get_children():
			if child is StaticBody3D:
				has_body = true
				if not on:
					mesh_instance.remove_child(child)
					child.queue_free()
		if on and not has_body:
			if mode == "trimesh":
				mesh_instance.create_trimesh_collision()
			else:
				_add_box_collision(mesh_instance)


## Pojednostavljena kolizija: jedna kutija oko svakog dela modela. Dovoljno da se
## ne može proći kroz zgradu, a košta skoro ništa (npr. market sa 326 delova).
func _add_box_collision(mesh_instance: MeshInstance3D) -> void:
	var box := mesh_instance.get_aabb()
	if box.size.length_squared() < 0.000001:
		return
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	shape.position = box.get_center()
	body.add_child(shape)
	mesh_instance.add_child(body)


func _add_collision_budget(root: Node3D) -> bool:
	var left := COLLISION_TRIANGLES
	for mesh_instance in _meshes(root):
		if mesh_instance.mesh == null:
			continue
		var count := _triangles(mesh_instance.mesh)
		if count > left:
			return false
		left -= count
	return true


func _triangles(mesh: Mesh) -> int:
	var cached: Variant = mesh.get_meta("tri_count", -1)
	if typeof(cached) == TYPE_INT and int(cached) >= 0:
		return int(cached)
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		# Neke mreže (i proceduralne) nemaju niz indeksa — tada se broje temena
		var raw: Variant = arrays[Mesh.ARRAY_INDEX]
		if typeof(raw) == TYPE_PACKED_INT32_ARRAY and not (raw as PackedInt32Array).is_empty():
			total += (raw as PackedInt32Array).size() / 3
		else:
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			if typeof(vertices) == TYPE_PACKED_VECTOR3_ARRAY:
				total += (vertices as PackedVector3Array).size() / 3
	mesh.set_meta("tri_count", total)
	return total


# ---------------------------------------------------------------------------
# Biranje i menjanje objekta
# ---------------------------------------------------------------------------

## Je li izabrano gradsko objekat (City Block), a ne nešto što je editor postavio
func _is_city(node: Node3D) -> bool:
	return node != null and is_instance_valid(node) and node.has_meta("city_object")


func _city_name() -> String:
	if not _is_city(_selection) or city_map == null:
		return ""
	return str(city_map.call("city_label", _selection))


## Sačuvaj promene gradskih objekata (pozicija, rotacija, skala, obrisano)
func _save_city_layout() -> void:
	if city_map != null and is_instance_valid(city_map) and city_map.has_method("city_save_layout"):
		city_map.call("city_save_layout")


func _select(node: Node3D) -> void:
	_selection = node
	_selection_box.visible = node != null
	_update_selection_box()
	_update_props()


func _update_selection_box() -> void:
	if _selection == null or not is_instance_valid(_selection):
		_selection_box.visible = false
		return
	_selection_box.visible = true
	var box := _world_aabb(_selection)
	if box.size == Vector3.ZERO:
		_selection_box.visible = false
		return
	_selection_box.global_transform = Transform3D(Basis.from_scale(box.size), box.get_center())


func _update_props() -> void:
	_updating_ui = true
	var has := _selection != null and is_instance_valid(_selection)
	_props_box.visible = has
	if has:
		var p := _selection.position
		_pos_spins[0].value = p.x
		_pos_spins[1].value = p.y
		_pos_spins[2].value = p.z
		_rot_spins[0].value = rad_to_deg(_selection.rotation.x)
		_rot_spins[1].value = rad_to_deg(_selection.rotation.y)
		_rot_spins[2].value = rad_to_deg(_selection.rotation.z)
		_scale_spin.value = _selection.scale.x
		_collision_check.button_pressed = bool(_selection.get_meta("collision", false))
		var city := _is_city(_selection)
		if _props_title != null:
			_props_title.text = "GRADSKI OBJEKAT: %s" % _city_name() if city else "IZABRANI OBJEKAT"
		_collision_check.visible = not city
		for control in _model_only:
			control.visible = not city
		var procedural := _is_procedural(str(_selection.get_meta("model", ""))) and not city
		_road_row.visible = procedural
		if procedural:
			_road_length_spin.value = float(_selection.get_meta("road_length", ROAD_LENGTH))
			_road_width_spin.value = float(_selection.get_meta("road_width", ROAD_WIDTH))
	_updating_ui = false


func _apply_props() -> void:
	if _updating_ui or _selection == null or not is_instance_valid(_selection):
		return
	_push_undo()
	_selection.position = Vector3(_pos_spins[0].value, _pos_spins[1].value, _pos_spins[2].value)
	_selection.rotation = Vector3(deg_to_rad(_rot_spins[0].value), deg_to_rad(_rot_spins[1].value),
		deg_to_rad(_rot_spins[2].value))
	var s := clampf(_scale_spin.value, SCALE_MIN, SCALE_MAX)
	_selection.scale = Vector3.ONE * s
	if _is_city(_selection):
		_update_selection_box()
		_save_city_layout()
		return
	if _is_procedural(str(_selection.get_meta("model", ""))):
		_set_procedural_size(_selection, _road_length_spin.value, _road_width_spin.value)
	_selection.set_meta("collision_off", not _collision_check.button_pressed)
	_set_collision(_selection, _collision_check.button_pressed)
	_update_selection_box()
	_save_layout()


func _rotate_active(degrees: float) -> void:
	if _placing != "":
		_ghost_rotation = wrapf(_ghost_rotation + degrees, -180.0, 180.0)
		return
	if _selection == null or not is_instance_valid(_selection):
		return
	_push_undo()
	_selection.rotation.y = deg_to_rad(wrapf(rad_to_deg(_selection.rotation.y) + degrees, -180.0, 180.0))
	_update_selection_box()
	_update_props()
	_save_layout()


func _scale_active(factor: float) -> void:
	if _placing != "":
		_ghost_scale = clampf(_ghost_scale * factor, SCALE_MIN, SCALE_MAX)
		return
	if _selection == null or not is_instance_valid(_selection):
		return
	_push_undo()
	var s := clampf(_selection.scale.x * factor, SCALE_MIN, SCALE_MAX)
	_selection.scale = Vector3.ONE * s
	_update_selection_box()
	_update_props()
	_save_layout()


func _nudge(offset: Vector3) -> void:
	if _selection == null or not is_instance_valid(_selection):
		return
	_push_undo()
	_selection.global_position += offset
	_update_selection_box()
	_update_props()
	_save_layout()


func _delete_selection() -> void:
	if _selection == null or not is_instance_valid(_selection):
		return
	if _is_city(_selection):
		var node := _selection
		if city_map != null and city_map.has_method("city_delete"):
			city_map.call("city_delete", node)
		_select(null)
		_set_status("Gradski objekat obrisan (nema Ctrl+Z za grad).")
		return
	_push_undo()
	# Odmah iz drveta, inače bi se obrisani objekat i dalje sačuvao u layout.json
	if _inside != null and (_inside == _selection or _inside.is_ancestor_of(_selection)):
		_inside = null
		_refresh_inside()
	var parent := _selection.get_parent()
	if parent:
		parent.remove_child(_selection)
	_selection.queue_free()
	_selection = null
	_selection_box.visible = false
	_update_props()
	_save_layout()
	_refresh_traffic()
	_set_status("Obrisano. Ctrl+Z ga vraca nazad.")


## Del briše izabrano, a ako ništa nije izabrano — ono što je pod nišanom
func _delete_aimed() -> void:
	if _selection == null or not is_instance_valid(_selection):
		var picked := _pick_at_aim()
		if picked != null:
			_select(picked)
	if _selection == null or not is_instance_valid(_selection):
		_set_status("Nišan nije na objektu. Klikni objekat pa Del, ili naciljaj i pritisni Del.")
		return
	_delete_selection()


## Obriši izabrani uvezeni model iz biblioteke (zahteva potvrdu)
func _ask_delete_model() -> void:
	var path := _selected_model()
	if path == "":
		_set_status("Izaberi model u listi koji hoćeš da obrišeš.")
		return
	if _is_procedural(path):
		_set_status("Put i ploča terena se ne brišu iz biblioteke.")
		return
	if not path.begins_with("user://"):
		_set_status("Modeli iz projekta (res://assets/models) se ne brišu iz igre.")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Obriši model"
	dialog.dialog_text = "Obrisati \u201e%s\u201c iz biblioteke?\nFajl se briše iz %s." % [_title_of(path), IMPORT_DIR]
	dialog.ok_button_text = "Obriši"
	dialog.confirmed.connect(func() -> void:
		_delete_model_file(path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(460, 170))


func _delete_model_file(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var prefix := path.get_file().get_basename().validate_filename() + "_"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CACHE_DIR)):
		for file in DirAccess.get_files_at(CACHE_DIR):
			if file.begins_with(prefix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE_DIR.path_join(file)))
	_cache.erase(path)
	_refresh_library()
	_set_status("Model \u201e%s\u201c je obrisan iz biblioteke." % _title_of(path))


## Reci igri da se promenio raspored puteva (NPC saobraćaj se ponovo pravi)
func _refresh_traffic() -> void:
	if game != null and game.has_method("refresh_road_traffic"):
		game.call("refresh_road_traffic")


## Oba kraja puta u svetu: pozicija kraja i smer u kome put izlazi iz njega
func _road_ends(holder: Node3D) -> Array:
	var length := float(holder.get_meta("road_length", ROAD_LENGTH))
	var scale := holder.global_basis.get_scale().x
	var forward := holder.global_basis.z.normalized()
	var center := holder.global_position
	return [
		{"pos": center - forward * length * scale * 0.5, "dir": -forward},
		{"pos": center + forward * length * scale * 0.5, "dir": forward},
	]


## Najbliži kraj nekog puta (unutar SNAP_DISTANCE) za postavljanje novog puta
func _find_road_snap(point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := SNAP_DISTANCE
	for holder in _all_holders():
		if str(holder.get_meta("model", "")) != ROAD_MODEL:
			continue
		for end: Dictionary in _road_ends(holder):
			var distance: float = point.distance_to(end["pos"])
			if distance < best_distance:
				best_distance = distance
				best = end
	if best.is_empty():
		return {}
	var outward: Vector3 = best["dir"]
	var half := _ghost_size.z * _ghost_scale * 0.5
	var snapped: Vector3 = (best["pos"] as Vector3) + outward * half
	return {"pos": snapped, "end": best["pos"], "yaw": atan2(outward.x, outward.z)}


## Spoji izabrani put sa najbližim drugim putem (kraj na kraj)
func _snap_selection(quiet := false) -> void:
	if _is_city(_selection):
		if not quiet:
			_set_status("Gradski objekat nije put za spajanje. Izaberi svoj put („Put (ravni)“).")
		return
	if _selection == null or not is_instance_valid(_selection) \
			or str(_selection.get_meta("model", "")) != ROAD_MODEL:
		if not quiet:
			_set_status("Izaberi put koji hoćeš da spojiš.")
		return
	var mine := _road_ends(_selection)
	var best: Dictionary = {}
	var best_distance := SNAP_DISTANCE
	for holder in _all_holders():
		if holder == _selection or str(holder.get_meta("model", "")) != ROAD_MODEL:
			continue
		for end: Dictionary in _road_ends(holder):
			for i in 2:
				var distance: float = (mine[i]["pos"] as Vector3).distance_to(end["pos"])
				if distance < best_distance:
					best_distance = distance
					best = {"end": end, "own": i}
	if best.is_empty():
		if not quiet:
			_set_status("Nema drugog puta blizu (do %.0f m)." % SNAP_DISTANCE)
		return
	var target: Vector3 = best["end"]["pos"]
	var outward: Vector3 = best["end"]["dir"]
	var scale := _selection.global_basis.get_scale().x
	var half := float(_selection.get_meta("road_length", ROAD_LENGTH)) * scale * 0.5
	var yaw: float
	var pos: Vector3
	if int(best["own"]) == 0:
		# Njegov -Z kraj ide na cilj, put se nastavlja u smeru izlaza
		yaw = atan2(outward.x, outward.z)
		pos = target + outward * half
	else:
		# Njegov +Z kraj ide na cilj, put se nastavlja u suprotnom smeru
		yaw = atan2(-outward.x, -outward.z)
		pos = target - outward * half
	pos.y = target.y
	_push_undo()
	_selection.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos)
	_update_selection_box()
	_update_props()
	_save_layout()
	_refresh_traffic()
	if not quiet:
		_set_status("Spojeno sa najbližim putem.")


## Svi postavljeni putevi kao segmenti za NPC saobraćaj
func placed_roads() -> Array:
	var roads: Array = []
	for holder in _all_holders():
		if str(holder.get_meta("model", "")) != ROAD_MODEL:
			continue
		var ends := _road_ends(holder)
		roads.append({"a": ends[0]["pos"], "b": ends[1]["pos"],
			"width": float(holder.get_meta("road_width", ROAD_WIDTH))})
	return roads


func _duplicate_selection() -> void:
	if _selection == null or not is_instance_valid(_selection):
		return
	if _is_city(_selection):
		_set_status("Gradski objekat se ne duplira; možeš ga pomeriti, rotirati, skalirati ili obrisati.")
		return
	var path := str(_selection.get_meta("model", ""))
	if path == "":
		return
	_push_undo()
	var copy := _spawn(path, _selection.position + Vector3(2.0, 0.0, 0.0),
		_selection.rotation, _selection.scale.x, bool(_selection.get_meta("collision", false)),
		float(_selection.get_meta("road_length", 0.0)), float(_selection.get_meta("road_width", 0.0)),
		_selection.get_parent() as Node3D)
	if copy:
		_select(copy)
		_save_layout()
	else:
		_history.pop_back()


## Zameni izabrani objekat modelom koji je izabran u listi — na istom mestu, ista rotacija i skala
func _replace_selection() -> void:
	if _is_city(_selection):
		_set_status("Gradski objekat se ne zamenjuje modelom; pomeri ga, rotiraj, skaliraj ili obriši.")
		return
	var path := _selected_model()
	if path == "":
		_set_status("Prvo izaberi model u listi, pa klikni „Zameni“.")
		return
	if _selection == null or not is_instance_valid(_selection):
		_set_status("Klikni na objekat koji hoćeš da zameniš.")
		return
	var old := _selection
	var parent := old.get_parent() as Node3D
	_push_undo()
	var holder := _spawn(path, parent.to_local(old.global_position), old.rotation, old.scale.x,
		bool(old.get_meta("collision", false)), float(old.get_meta("road_length", 0.0)),
		float(old.get_meta("road_width", 0.0)), parent)
	if holder == null:
		_history.pop_back()
		_set_status("Model nije mogao da se učita.")
		return
	parent.remove_child(old)
	old.queue_free()
	_select(holder)
	_save_layout()
	_set_status("Zamenjeno sa „%s“." % _display_name(path))


## Poravnaj izabrani objekat sa tlom (nagib terena) — za puteve i kuće na strmini
func _align_to_ground() -> void:
	if _selection == null or not is_instance_valid(_selection):
		_set_status("Klikni na objekat koji hoćeš da poravnaš sa tlom.")
		return
	if _is_city(_selection):
		_set_status("Gradski objekat već stoji na svom mestu; poravnavanje važi za tvoje modele.")
		return
	var box := _world_aabb(_selection)
	var hit := _ground_hit(box.get_center())
	if hit.is_empty():
		_set_status("Nema tla ispod objekta.")
		return
	var up: Vector3 = hit["normal"]
	if up.dot(Vector3.UP) < 0.5 or up.length() < 0.001:
		up = Vector3.UP
	up = up.normalized()
	var forward := _selection.global_basis.z
	forward = (forward - up * forward.dot(up))
	if forward.length() < 0.001:
		return
	var right := up.cross(forward).normalized()
	var front := right.cross(up).normalized()
	var s := _selection.scale.x
	_push_undo()
	_selection.global_transform = Transform3D(Basis(right * s, up * s, front * s),
		_selection.global_position)
	_update_selection_box()
	_update_props()
	_save_layout()
	_set_status("Poravnato sa tlom.")


## Prvo tlo ispod tačke, preskačući objekte koje je napravio editor
func _ground_hit(point: Vector3) -> Dictionary:
	var from := point + Vector3.UP * 5.0
	var to := point - Vector3.UP * 250.0
	for _attempt in 8:
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		query.collide_with_areas = false
		if car:
			query.exclude.append(car.get_rid())
		var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var node := hit["collider"] as Node
		var builder := false
		while node != null:
			if node.has_meta("builder_object"):
				builder = true
				break
			node = node.get_parent()
		if not builder:
			return hit
		from = (hit["position"] as Vector3) - Vector3.UP * 0.05
	return {}


# ---------------------------------------------------------------------------
# Unutar objekta: pravljenje detalja
# ---------------------------------------------------------------------------

## Gde idu novi objekti: u svet ili unutar objekta u koji je korisnik ušao
func _active_parent() -> Node3D:
	if _inside != null and is_instance_valid(_inside):
		return _inside
	return _objects


## Ušao si u objekat: sve novo se pravi unutra, u njegovim koordinatama
func _enter_object() -> void:
	if _selection == null or not is_instance_valid(_selection):
		_set_status("Klikni na objekat u koji hoćeš da uđeš, pa pritisni E.")
		return
	if _is_city(_selection):
		_set_status("U gradske objekte se ne ulazi. Za svoje objekte: klikni svoj model, pa E.")
		return
	_inside = _selection
	_select(null)
	_refresh_inside()
	_set_status("Ušao si u „%s“. Novi delovi idu unutra. E ili „Izađi“ vraća napolje." % _inside_title())


## Jedan nivo napolje (ako je objekat unutar drugog objekta, nazad u njega)
func _exit_object() -> void:
	if _inside == null or not is_instance_valid(_inside):
		_inside = null
		_refresh_inside()
		return
	var parent := _inside.get_parent() as Node3D
	if parent != null and parent != _objects and parent.has_meta("builder_object"):
		_inside = parent
	else:
		_inside = null
	_refresh_inside()
	_set_status("Napolju." if _inside == null else "Nazad u „%s“." % _inside_title())


func _inside_title() -> String:
	if _inside == null or not is_instance_valid(_inside):
		return ""
	return _display_name(str(_inside.get_meta("model", "")))


func _refresh_inside() -> void:
	if _inside != null and not is_instance_valid(_inside):
		_inside = null
	if _inside_row == null:
		return
	_inside_row.visible = _inside != null
	if _inside:
		_inside_label.text = "UNUTRA: %s  ·  E izlazi" % _inside_title()


## Svi postavljeni objekti, i oni unutar drugih objekata
func _all_holders() -> Array[Node3D]:
	var result: Array[Node3D] = []
	_collect_holders(_objects, result)
	return result


func _collect_holders(parent: Node, result: Array[Node3D]) -> void:
	for child in parent.get_children():
		var holder := child as Node3D
		if holder == null or not is_instance_valid(holder) or not holder.has_meta("builder_object"):
			continue
		result.append(holder)
		_collect_holders(holder, result)


# ---------------------------------------------------------------------------
# Pomeranje mišem i undo
# ---------------------------------------------------------------------------

func _begin_drag() -> void:
	if _selection == null or not is_instance_valid(_selection):
		return
	_dragging = true
	_drag_pushed = false
	_set_status("Pomeranje: vuci mišem, LMB otpušta. Ctrl+Z poništava.")


## Dok se vuče, miš pomera izabrani objekat po ravni (kamera se tada ne okreće)
func _drag_by(relative: Vector2) -> void:
	if _selection == null or not is_instance_valid(_selection):
		_dragging = false
		return
	if not _drag_pushed:
		_push_undo()
		_drag_pushed = true
	var distance := _camera.global_position.distance_to(_selection.global_position)
	var factor := clampf(distance * 0.0015, 0.001, 1.0)
	_selection.global_position += (_flat_right() * relative.x - _flat_forward() * relative.y) * factor
	_update_selection_box()
	_update_props()


func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	if _drag_pushed:
		_drag_pushed = false
		_save_layout()
		_set_status("Pomereno.")
		# Put se posle pomeranja sam spoji sa najbližim putem
		if _snap_check != null and _snap_check.button_pressed and _selection != null \
				and str(_selection.get_meta("model", "")) == ROAD_MODEL:
			_snap_selection(true)
		_refresh_traffic()


# ---------------------------------------------------------------------------
# Novo vozilo za garažu
# ---------------------------------------------------------------------------

func _ask_car_from_selected() -> void:
	var path := _selected_model()
	if path == "":
		_set_status("Izaberi model u listi, pa ga dodaj kao vozilo.")
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Novo vozilo"
	dialog.ok_button_text = "Dodaj u garažu"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(340.0, 0.0)
	var title_from_file := _title_of(path)
	var brand_edit := _dialog_field(box, "Marka (npr. Nissan)", title_from_file.split(" ")[0])
	var name_edit := _dialog_field(box, "Naziv (npr. Skyline GT-R R34)", title_from_file)
	var year_spin := SpinBox.new()
	year_spin.min_value = 1950
	year_spin.max_value = 2035
	year_spin.value = 2024
	box.add_child(_dialog_label("Godina"))
	box.add_child(year_spin)
	dialog.add_child(box)
	dialog.confirmed.connect(func() -> void:
		_save_car_profile(path, brand_edit.text, name_edit.text, int(year_spin.value))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _dialog_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	return label


func _dialog_field(box: VBoxContainer, caption: String, value: String) -> LineEdit:
	box.add_child(_dialog_label(caption))
	var edit := LineEdit.new()
	edit.text = value
	box.add_child(edit)
	return edit


func _slug(text: String) -> String:
	var slug := ""
	for i in text.length():
		var c := text[i].to_lower()
		if c == " " or c == "-" or c == "." or c == "_":
			if not slug.ends_with("_"):
				slug += "_"
		elif c.to_lower() != c.to_upper() or (c >= "0" and c <= "9"):
			slug += c
	if slug.ends_with("_"):
		slug = slug.substr(0, slug.length() - 1)
	return slug if slug != "" else "auto"


func _save_car_profile(path: String, brand_text: String, name_text: String, year: int) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAR_DIR))
	var display := name_text.strip_edges()
	if display == "":
		display = _title_of(path)
	var profile := CarProfile.new()
	profile.id = _slug("%s_%s" % [display, year])
	profile.display_name = display
	profile.subtitle = str(year)
	profile.brand = brand_text.strip_edges() if brand_text.strip_edges() != "" else "Moja vozila"
	profile.year = year
	profile.model_path_override = path
	# Mere iz modela: dužina, širina i visina
	var instance := _instantiate(path)
	if instance == null:
		_set_status("Model nije mogao da se učita.")
		return
	var size := _local_aabb(instance).size
	instance.free()
	var length := clampf(size.z, 2.5, 6.5)
	var width := clampf(size.x, 1.4, 2.4)
	var height := clampf(size.y, 1.0, 1.9)
	profile.body_size = Vector3(width, height * 0.55, length)
	profile.body_center = Vector3(0.0, profile.body_size.y * 0.5, 0.0)
	profile.cabin_size = Vector3(width * 0.78, height * 0.38, length * 0.42)
	profile.cabin_center = Vector3(0.0, profile.body_size.y + profile.cabin_size.y * 0.5, -0.2)
	profile.wheelbase = length * 0.6
	profile.track_front = width * 0.82
	profile.track_rear = profile.track_front
	profile.wheel_radius = clampf(height * 0.16, 0.24, 0.45)
	profile.mass = 1300.0 + width * length * 180.0
	profile.power_ps = 300
	# Prepoznavanje delova po imenima (kod većine modela radi; ako ne, auto i dalje stoji na točkovima)
	profile.wheel_parts = PackedStringArray(["*wheel*", "*tire*", "*tyre*", "*rim*", "*reifen*", "*felge*", "*rueda*"])
	profile.paint_materials = PackedStringArray(["*carpaint*", "*paint*", "*lack*", "*body*", "*carrosserie*"])
	profile.glass_materials = PackedStringArray(["*glass*", "*window*", "*windshield*", "*scheibe*"])
	profile.tire_materials = PackedStringArray(["*tire*", "*tyre*", "*rubber*"])
	profile.rim_materials = PackedStringArray(["*rim*", "*felge*"])
	profile.headlight_materials = PackedStringArray(["*headlight*", "*scheinwerfer*"])
	profile.taillight_materials = PackedStringArray(["*taillight*", "*brakelight*", "*ruecklicht*"])
	profile.paint_colors = [Color(0.72, 0.05, 0.05), Color(0.04, 0.04, 0.05),
		Color(0.78, 0.78, 0.8), Color(0.05, 0.18, 0.55)]
	var target := CAR_DIR.path_join(profile.id + ".tres")
	if ResourceSaver.save(profile, target) != OK:
		_set_status("Profil nije mogao da se sačuva.")
		return
	_set_status("„%s“ je dodat u garažu (marka %s). Vidiš ga kada ponovo pokreneš igru." % [display, profile.brand])


# ---------------------------------------------------------------------------
# Čuvanje i učitavanje rasporeda
# ---------------------------------------------------------------------------

func _start_road_placement() -> void:
	_start_placement(ROAD_MODEL)


func _start_pad_placement() -> void:
	_start_placement(PAD_MODEL)


## Fajlovi na koje .gltf pokazuje (buffers/images sa uri) — inače model nema tekstura
func _copy_gltf_references(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var json: Variant = JSON.parse_string(text)
	if typeof(json) != TYPE_DICTIONARY:
		return
	var source_dir := path.get_base_dir()
	for key: String in ["buffers", "images"]:
		for entry in (json as Dictionary).get(key, []):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var uri := str(entry.get("uri", ""))
			if uri == "" or uri.begins_with("data:") or uri.contains("://"):
				continue
			var from := source_dir.path_join(uri)
			if not FileAccess.file_exists(from):
				continue
			# Put the file where the model expects it (e.g. "textures/wall.png" keeps its folder),
			# otherwise the model loads without its textures
			var target := IMPORT_DIR.path_join(uri)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
			DirAccess.copy_absolute(from, ProjectSettings.globalize_path(target))


func _save_layout() -> void:
	if _objects == null:
		return
	# Ako je izabran gradski objekat, sačuvaj i njegov novi transform
	if _is_city(_selection):
		_save_city_layout()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://editor"))
	var objects := _snapshot()
	objects.append_array(_missing)
	var data := {
		"version": 1,
		"camera": {"pos": [_cam_pos.x, _cam_pos.y, _cam_pos.z], "yaw": _cam_yaw, "pitch": _cam_pitch},
		"objects": objects,
	}
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Ne mogu da sačuvam raspored: " + LAYOUT_PATH)
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()


## Svi postavljeni objekti kao podaci (za layout.json i za undo)
func _snapshot() -> Array:
	var objects: Array = []
	for child in _objects.get_children():
		var holder := child as Node3D
		if holder == null or not is_instance_valid(holder):
			continue
		objects.append(_snapshot_holder(holder))
	return objects


## Jedan postavljeni objekat kao podatak, sa svim što je stavljeno unutar njega
## ("children"), tako da se unutrašnjost čuva zajedno sa objektom
func _snapshot_holder(holder: Node3D) -> Dictionary:
	var entry := {
		"model": str(holder.get_meta("model", "")),
		"pos": [holder.position.x, holder.position.y, holder.position.z],
		"rot": [rad_to_deg(holder.rotation.x), rad_to_deg(holder.rotation.y), rad_to_deg(holder.rotation.z)],
		"scale": holder.scale.x,
		"collision": bool(holder.get_meta("collision", false)),
		"collision_off": bool(holder.get_meta("collision_off", false)),
		"road_length": float(holder.get_meta("road_length", 0.0)),
		"road_width": float(holder.get_meta("road_width", 0.0)),
	}
	var children: Array = []
	for child in holder.get_children():
		var inner := child as Node3D
		if inner == null or not is_instance_valid(inner) or not inner.has_meta("builder_object"):
			continue
		children.append(_snapshot_holder(inner))
	if not children.is_empty():
		entry["children"] = children
	return entry


## Zapamti stanje pre izmene (za Ctrl+Z)
func _push_undo() -> void:
	if _restoring or _objects == null:
		return
	# Gradski objekti nemaju undo (oni se menjaju u samom modelu grada)
	if _is_city(_selection):
		return
	_history.append(_snapshot())
	if _history.size() > UNDO_LIMIT:
		_history.pop_front()


## Ctrl+Z: vrati svet na stanje pre poslednje izmene
func _undo() -> void:
	if _history.is_empty():
		_set_status("Nema šta da se poništi.")
		return
	_restore(_history.pop_back())
	_set_status("Poništeno (Ctrl+Z).")


## Obriši sve postavljene objekte i napravi ih ponovo iz snimka
func _restore(objects: Array) -> void:
	_restoring = true
	_select(null)
	_inside = null
	_refresh_inside()
	for child in _objects.get_children():
		_objects.remove_child(child)
		child.queue_free()
	_restore_into(_objects, objects)
	_restoring = false
	_save_layout()


## Napravi objekte jednog nivoa; sve što je bilo unutar objekta vraća se sa njim
func _restore_into(parent: Node3D, objects: Array, missing: Array = []) -> void:
	for entry in objects:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var model := str(entry.get("model", ""))
		var pos: Array = entry.get("pos", [])
		if model == "" or pos.size() != 3:
			continue
		var holder := _spawn(model, Vector3(pos[0], pos[1], pos[2]), _entry_rotation(entry),
			float(entry.get("scale", 1.0)), _entry_solid(entry),
			float(entry.get("road_length", 0.0)), float(entry.get("road_width", 0.0)), parent)
		if holder == null:
			missing.append(entry)
			continue
		_restore_into(holder, entry.get("children", []), missing)


func _load_layout() -> void:
	_read_layout()
	layout_loaded.emit()


## Čita user://editor/layout.json i postavlja objekte u svet
func _read_layout() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("layout.json nije ispravan.")
		return
	var camera: Dictionary = data.get("camera", {})
	var cam_pos: Array = camera.get("pos", [])
	if cam_pos.size() == 3:
		_cam_pos = Vector3(cam_pos[0], cam_pos[1], cam_pos[2])
		_cam_yaw = float(camera.get("yaw", 0.0))
		_cam_pitch = float(camera.get("pitch", -0.3))
	_place_camera()
	for entry in data.get("objects", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var model := str(entry.get("model", ""))
		var pos: Array = entry.get("pos", [])
		if model == "" or pos.size() != 3:
			continue
		var holder := _spawn(model, Vector3(pos[0], pos[1], pos[2]), _entry_rotation(entry),
			float(entry.get("scale", 1.0)), _entry_solid(entry),
			float(entry.get("road_length", 0.0)), float(entry.get("road_width", 0.0)))
		if holder == null:
			_missing.append(entry)
		else:
			_restore_into(holder, entry.get("children", []), _missing)


## Je li objekat iz layout.json pun (kroz njega se ne može proći). Stariji fajlovi
## imaju "collision": false za velike modele kojima je kolizija nekada odbijena, zato
## se takvi objekti sada učitavaju puni; isključena kolizija ostaje isključena samo ako
## je zaista sačuvana kao takva ("collision_off").
func _entry_solid(entry: Dictionary) -> bool:
	if bool(entry.get("collision", false)):
		return true
	return not bool(entry.get("collision_off", false))


## Rotacija iz layout.json: novo je [x, y, z], stari fajlovi imaju samo y kao broj
func _entry_rotation(entry: Dictionary) -> Vector3:
	var rot: Variant = entry.get("rot", 0.0)
	if typeof(rot) == TYPE_ARRAY:
		var list: Array = rot
		if list.size() == 3:
			return Vector3(deg_to_rad(float(list[0])), deg_to_rad(float(list[1])),
				deg_to_rad(float(list[2])))
		return Vector3.ZERO
	return Vector3(0.0, deg_to_rad(float(rot)), 0.0)


# ---------------------------------------------------------------------------
# Pomoćne funkcije za geometriju
# ---------------------------------------------------------------------------

func _meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			result.append(node)
		stack.append_array(node.get_children())
	return result


## Kutija modela u koordinatama korena (bez obzira gde model stoji u sceni)
func _local_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh_instance in _meshes(root):
		var part := _relative_transform(mesh_instance, root) * mesh_instance.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func _world_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh_instance in _meshes(root):
		var part := mesh_instance.global_transform * mesh_instance.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current and current != ancestor:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _set_status(text: String) -> void:
	if _status:
		_status.text = text


func _save_and_report() -> void:
	_save_layout()
	_set_status("Sačuvano u %s" % LAYOUT_PATH)


## Kratka poruka na vrhu ekrana (radi i kada je igra pauzirana)
func _toast(text: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_layer.visible = true
	_toast_timer.start()


## Zašto se editor ne može otvoriti sada
func _open_blocker() -> String:
	if game == null or not bool(game.get("world_is_ready")):
		return "Sačekaj da se svet učita, pa pritisni F2."
	for overlay in ["MainMenu", "Garage", "PauseMenu", "BigMap", "PhotoMode", "Dyno"]:
		var node := game.get_node_or_null(overlay) as CanvasItem
		if node and node.visible:
			return "Zatvori meni „%s“ (Esc) pa pritisni F2." % overlay
	return "Editor trenutno ne može da se otvori."


func _build_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.name = "BuildEditorToast"
	_toast_layer.layer = 27
	_toast_layer.visible = false
	add_child(_toast_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(root)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 80.0
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(column)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.92)
	style.border_color = Color(0.4, 1.0, 0.8, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 15)
	panel.add_child(_toast_label)
	row.add_child(panel)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 4.0
	_toast_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_toast_timer)
	_toast_timer.timeout.connect(func() -> void: _toast_layer.visible = false)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "BuildEditorUI"
	_ui.layer = 26
	_ui.visible = false
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	# Panel desno
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -382.0
	panel.offset_right = -14.0
	panel.offset_top = 14.0
	panel.offset_bottom = -14.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.05, 0.07, 0.93)
	panel_style.border_color = Color(1.0, 1.0, 1.0, 0.14)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(14)
	panel_style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "UREĐIVAČ SVETA"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.65, 0.85, 0.8))
	box.add_child(_status)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0.0, 210.0)
	_list.item_activated.connect(func(_index: int) -> void: _start_placement())
	_list.item_selected.connect(func(_index: int) -> void:
		_set_status(_title_of(_selected_model())))
	box.add_child(_list)
	box.add_child(_row([_button("Uvezi .glb", _ask_import), _button("Osvezi", _refresh_library)]))
	box.add_child(_button("Obriši model iz liste", _ask_delete_model))
	box.add_child(_button("Postavi u svet", _start_placement))
	box.add_child(_row([_button("Put (ravni)", _start_road_placement),
		_button("Ploča terena", _start_pad_placement)]))
	box.add_child(_button("Obriši pod nišanom (Del)", _delete_aimed))
	_snap_check = CheckBox.new()
	_snap_check.text = "Spajaj puteve (kraj na kraj)"
	_snap_check.button_pressed = true
	box.add_child(_snap_check)
	box.add_child(_button("Dodaj kao vozilo u garazu", _ask_car_from_selected))
	box.add_child(HSeparator.new())
	# Unutar objekta: pokaži gde si i kako se izlazi
	_inside_row = HBoxContainer.new()
	_inside_row.add_theme_constant_override("separation", 6)
	_inside_row.visible = false
	_inside_label = Label.new()
	_inside_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inside_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inside_label.add_theme_font_size_override("font_size", 13)
	_inside_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_inside_row.add_child(_inside_label)
	_inside_row.add_child(_button("Izađi", _exit_object))
	box.add_child(_inside_row)
	# Izabrani objekat
	var props := VBoxContainer.new()
	props.add_theme_constant_override("separation", 6)
	props.visible = false
	box.add_child(props)
	_props_box = props
	var props_title := Label.new()
	props_title.text = "IZABRANI OBJEKAT"
	props_title.add_theme_font_size_override("font_size", 14)
	props.add_child(props_title)
	_props_title = props_title
	for axis in ["X", "Y", "Z"]:
		var spin := _spin(0.0, 0.1, func(_value: float) -> void: _apply_props())
		spin.suffix = " m"
		_pos_spins.append(spin)
	props.add_child(_row([_label("Pozicija"), _pos_spins[0], _pos_spins[1], _pos_spins[2]]))
	var rotation_row: Array = [_label("Rotacija")]
	for _axis in 3:
		var spin := _spin(0.0, 5.0, func(_value: float) -> void: _apply_props())
		spin.min_value = -360.0
		spin.max_value = 360.0
		spin.suffix = "°"
		spin.allow_greater = false
		spin.allow_lesser = false
		_rot_spins.append(spin)
		rotation_row.append(spin)
	props.add_child(_row(rotation_row))
	_scale_spin = _spin(1.0, 0.05, func(_value: float) -> void: _apply_props())
	_scale_spin.min_value = SCALE_MIN
	_scale_spin.max_value = SCALE_MAX
	props.add_child(_row([_label("Skala"), _scale_spin]))
	_road_row = HBoxContainer.new()
	_road_row.add_theme_constant_override("separation", 6)
	_road_row.visible = false
	_road_length_spin = _spin(ROAD_LENGTH, 5.0, func(_value: float) -> void: _apply_props())
	# Minimum mora da bude na mreži koraka, inače SpinBox zaokruži 40 na 42
	_road_length_spin.min_value = 5.0
	_road_length_spin.max_value = 1000.0
	_road_length_spin.suffix = " m"
	_road_width_spin = _spin(ROAD_WIDTH, 0.5, func(_value: float) -> void: _apply_props())
	_road_width_spin.min_value = 1.0
	_road_width_spin.max_value = 200.0
	_road_width_spin.suffix = " m"
	_road_row.add_child(_label("Dužina"))
	_road_row.add_child(_road_length_spin)
	_road_row.add_child(_label("Širina"))
	_road_row.add_child(_road_width_spin)
	props.add_child(_road_row)
	var snap_button := _button("Spoji sa najbližim putem", _snap_selection)
	props.add_child(snap_button)
	_model_only.append(snap_button)
	props.add_child(_row([_button("↺ 15°", func() -> void: _rotate_active(-ROT_STEP)),
		_button("↻ 15°", func() -> void: _rotate_active(ROT_STEP))]))
	var enter_button := _button("Uđi u objekat (E) — dodaj detalje unutra", _enter_object)
	props.add_child(enter_button)
	_model_only.append(enter_button)
	var ground_button := _button("Poravnaj sa tlom", _align_to_ground)
	props.add_child(ground_button)
	_model_only.append(ground_button)
	_collision_check = CheckBox.new()
	_collision_check.text = "Kolizija (može se udariti)"
	_collision_check.button_pressed = true
	_collision_check.toggled.connect(func(_on: bool) -> void: _apply_props())
	props.add_child(_collision_check)
	_model_only.append(_collision_check)
	var replace_button := _button("Zameni izabranim modelom iz liste", _replace_selection)
	props.add_child(replace_button)
	_model_only.append(replace_button)
	var duplicate_button := _button("Dupliraj", _duplicate_selection)
	props.add_child(_row([duplicate_button, _button("Obriši", _delete_selection)]))
	_model_only.append(duplicate_button)
	box.add_child(HSeparator.new())
	box.add_child(_row([_button("Sačuvaj", _save_and_report), _button("Zatvori (F2)", close)]))
	# Nišan i podsetnik na tastere
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 26)
	_crosshair.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8))
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_right = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.anchor_bottom = 0.5
	_crosshair.offset_left = -10.0
	_crosshair.offset_right = 10.0
	_crosshair.offset_top = -18.0
	_crosshair.offset_bottom = 18.0
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)
	_hint = Label.new()
	_hint.text = "WASD leti · miš gleda · LMB bira · LMB na izabranom pa vuci = pomeranje · Z/X rotira · [ ] skalira · E ulazi/izlazi iz objekta · Del briše i pod nišanom · Del briše · Ctrl+Z poništava · F2 zatvara"
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 20.0
	_hint.offset_right = -400.0
	_hint.offset_top = -42.0
	_hint.offset_bottom = -14.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.75))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("shadow_offset_x", 1)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_press)
	return button


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(64.0, 0.0)
	return label


func _row(controls: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for control: Control in controls:
		row.add_child(control)
	return row


func _spin(value: float, step: float, on_change: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -100000.0
	spin.max_value = 100000.0
	spin.step = step
	spin.value = value
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(new_value: float) -> void: on_change.call(new_value))
	return spin
