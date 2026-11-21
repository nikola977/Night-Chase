extends Node3D
## Freies Fahren auf der umgewandelten Assetto-Corsa-Strecke „Osaka Nanko“.
##
## Das ist eine eigene Welt neben der endlosen Landschaft: main.tscn bleibt
## unverändert, der prozedurale Generator läuft hier gar nicht. Umgeschaltet wird
## im Pausemenü (Knopf „Osaka Nanko“) oder mit dem Startargument --track=osaka.
##
## Die Geometrie entsteht mit tools/kn5_to_gltf.py (siehe docs/strecken.md).
## Bilder für die Prüfung: -- --shot=osaka --wait=6

@export_group("Daten")
## Ordner mit den Kacheln aus kn5_to_gltf.py
@export var tile_dir: String = "res://assets/tracks/osaka"
## Diese Listen schreibt das Werkzeug mit (eine je .kn5-Datei)
@export var manifests: Array[String] = [
	"90sgdsp_osaka_nanko_manifest.json",
	"buildings_manifest.json",
	"props_manifest.json",
	"metal_pole_manifest.json",
	"trees_manifest.json",
	"vehicles_manifest.json",
	"bg_manifest.json",
	"lights_manifest.json",
]
## Nur für die Physik: Fahrbahn, Randsteine, Gras, unsichtbare Wände
@export_file("*.glb") var collision_file: String = "res://assets/tracks/osaka/collision.glb"

@export_group("Start")
## Stelle auf der Fahrbahn (aus der Physik-Fläche berechnet)
@export var spawn_point: Vector3 = Vector3(130.3, 2.9, 12.3)
## Blickrichtung des Autos in Grad (0 = Richtung +Z)
@export var spawn_heading: float = 90.0

@export_group("Leistung")
## Ab dieser Entfernung (Meter) wird eine Kachel nicht mehr gezeichnet
@export var view_distance: float = 1400.0
## Schatten der Streckengeometrie (kostet Bildrate, bei Bedarf abschalten)
@export var geometry_shadows: bool = true

@export_group("Himmel")
## Tageszeit in Stunden (14 = Nachmittag)
@export var time_of_day: float = 14.0

## Test: nach so vielen Sekunden ein Foto speichern und beenden (0 = aus)
var _shot_name: String = ""
var _shot_delay: float = -1.0
var _shot_time: float = 0.0
## Test: so viele Sekunden Bilder zählen und die Bildrate ausgeben (--bench=S)
var _bench_seconds: float = -1.0
var _bench_time: float = 0.0
var _bench_frames: int = 0
var _bench_worst: float = 999.0

var _car: VehicleBody3D
var _camera: FollowCamera
var _tiles: Node3D
var _speed_label: Label
var _hint_label: Label
var _sun: DirectionalLight3D
var _tile_count: int = 0


func _ready() -> void:
	get_window().title = "Car Driving World – Osaka Nanko"
	_car = get_node("Car")
	_camera = get_node("Camera")
	_tiles = get_node("Tiles")
	_sun = get_node("Sun")
	_read_arguments()
	_setup_sky()
	_load_tiles()
	_build_collision()
	_place_car()
	_build_hud()


## Startargumente wie bei DebugTools: --shot=NAME und --wait=S
func _read_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot="):
			_shot_name = argument.substr(7)
			if _shot_delay < 0.0:
				_shot_delay = 5.0
		elif argument.begins_with("--wait="):
			_shot_delay = maxf(float(argument.substr(7)), 0.1)
		elif argument.begins_with("--time="):
			time_of_day = float(argument.substr(7))
		elif argument.begins_with("--spawn="):
			var parts := argument.substr(8).split(",")
			if parts.size() >= 2:
				spawn_point = Vector3(float(parts[0]), spawn_point.y, float(parts[1]))
		elif argument.begins_with("--heading="):
			spawn_heading = float(argument.substr(10))
		elif argument.begins_with("--bench="):
			_bench_seconds = float(argument.substr(8))


func _setup_sky() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.47, 0.72)
	sky_material.sky_horizon_color = Color(0.70, 0.76, 0.82)
	sky_material.ground_bottom_color = Color(0.18, 0.19, 0.20)
	sky_material.ground_horizon_color = Color(0.55, 0.57, 0.60)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.ssao_enabled = true
	environment.glow_enabled = true
	# Leichter Dunst: gibt der großen Fläche Tiefe (ferne Hafenanlagen verblassen)
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.68, 0.73, 0.80)
	environment.fog_density = 0.0016
	var world_environment := get_node("WorldEnvironment") as WorldEnvironment
	world_environment.environment = environment
	# Sonne passend zur Tageszeit: 6 Uhr flach am Horizont, 12 Uhr senkrecht oben,
	# 18 Uhr wieder flach. Ohne diese Höhe steht das Licht waagerecht und es gibt
	# keine Schatten (alles wirkt dann flach und weiß).
	var day_angle := clampf((time_of_day - 6.0) / 12.0, 0.02, 0.98) * PI
	var elevation := rad_to_deg(asin(clampf(sin(day_angle), 0.1, 1.0)))
	_sun.rotation = Vector3(-deg_to_rad(elevation), deg_to_rad(140.0), 0.0)
	_sun.light_energy = 1.35


## Lädt alle Kacheln aus den Listen. Ohne Liste (z. B. alte Umwandlung) werden
## einfach alle .glb im Ordner genommen.
func _load_tiles() -> void:
	var files: Array[String] = []
	for manifest_name in manifests:
		var manifest := _read_json(tile_dir.path_join(manifest_name))
		for tile in manifest.get("tiles", []):
			var file: String = String(tile.get("file", ""))
			if file != "":
				files.append(file)
	if files.is_empty():
		var directory := DirAccess.open(tile_dir)
		if directory == null:
			push_error("Strecken-Ordner fehlt: %s" % tile_dir)
			return
		for file in directory.get_files():
			if file.ends_with(".glb") and not file.begins_with("collision"):
				files.append(file)
	var started := Time.get_ticks_msec()
	for file in files:
		var path := tile_dir.path_join(file)
		if not ResourceLoader.exists(path):
			push_warning("Kachel fehlt: %s" % path)
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var tile := scene.instantiate()
		_tiles.add_child(tile)
		_apply_draw_settings(tile)
		_tile_count += 1
	print("Osaka: %d Kacheln in %.1f s geladen" % [_tile_count, (Time.get_ticks_msec() - started) / 1000.0])


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## Sichtweite und Schatten für jedes Mesh in einer Kachel setzen
func _apply_draw_settings(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.visibility_range_end = view_distance
		mesh_instance.visibility_range_end_margin = view_distance * 0.1
		if not geometry_shadows:
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_draw_settings(child)


## Physik aus der eigenen Physik-Datei (nicht aus der Anzeige-Geometrie:
## die hat viel zu viele Dreiecke und wäre als Kollision zu teuer).
func _build_collision() -> void:
	if not ResourceLoader.exists(collision_file):
		push_error("Kollisions-Datei fehlt: %s" % collision_file)
		return
	var scene := load(collision_file) as PackedScene
	if scene == null:
		return
	var source := scene.instantiate()
	var mesh_instance := _find_mesh(source)
	if mesh_instance == null:
		push_error("Keine Fahrbahn-Fläche in %s" % collision_file)
		source.queue_free()
		return
	var body := StaticBody3D.new()
	body.name = "TrackCollision"
	var shape := CollisionShape3D.new()
	shape.shape = mesh_instance.mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
	source.queue_free()
	print("Osaka: Fahrbahn-Physik mit %d Dreiecken" % (mesh_instance.mesh.get_faces().size() / 3))


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _place_car() -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(spawn_heading))
	_car.teleport(Transform3D(basis, spawn_point), true)
	_car.freeze = false
	_camera.target = _car
	_camera.current = true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TrackHud"
	add_child(layer)

	_speed_label = Label.new()
	_speed_label.position = Vector2(28, 22)
	_speed_label.add_theme_font_size_override("font_size", 34)
	_speed_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_speed_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_speed_label.add_theme_constant_override("shadow_offset_x", 2)
	_speed_label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_speed_label)

	_hint_label = Label.new()
	_hint_label.position = Vector2(28, 70)
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_hint_label.text = "Osaka Nanko · Tab camera · Esc back to the endless world"
	layer.add_child(_hint_label)


func _process(delta: float) -> void:
	if _car != null and _speed_label != null:
		_speed_label.text = "%d km/h" % int(round(_car.linear_velocity.length() * 3.6))
	if _shot_delay > 0.0 and _shot_name != "":
		_shot_time += delta
		if _shot_time >= _shot_delay:
			_shot_delay = -1.0
			_save_shot()
	if _bench_seconds > 0.0:
		_bench_time += delta
		_bench_frames += 1
		_bench_worst = minf(_bench_worst, 1.0 / maxf(delta, 0.0001))
		if _bench_time >= _bench_seconds:
			_bench_seconds = -1.0
			print("Osaka-Bench: %.0f FPS im Schnitt, schlechtestes Bild %.0f FPS, %d Bilder, %d Kacheln" % [
				_bench_frames / _bench_time, _bench_worst, _bench_frames, _tile_count])
			get_tree().quit()


func _save_shot() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://screenshots")
	var path := "res://screenshots/%s.png" % _shot_name
	image.save_png(ProjectSettings.globalize_path(path))
	print("Foto gespeichert: %s (%d Kacheln)" % [path, _tile_count])
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main.tscn")
