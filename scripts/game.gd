extends Node3D
## Startet die Welt: richtet die Welt-Formel ein, sucht einen Startplatz für das Auto
## und lässt es erst losfahren, wenn das Gelände drumherum geladen ist.

## Name der App im Fenstertitel
const APP_TITLE := "Night Chase"

## Die Welt-Formel mit allen Einstellungen (Seed, Bergeshöhe, ...)
@export var world_gen: WorldGen
@export var terrain: TerrainManager
@export var horizon: HorizonRing
@export var car: VehicleBody3D
@export var loading_screen: Control
@export var debug_tools: DebugTools
@export var day_night: DayNight
@export var garage: Garage
@export var map_tiles: MapTiles
@export var roads: RoadNetwork
@export var water: WaterManager
@export var grass: GrassManager
@export var weather: Weather
## Fenster „Was ist neu“ (einmal pro Version beim Start)
@export var whats_new: WhatsNew

const OnFootScript = preload("res://scripts/on_foot.gd")
const MainMenuScript = preload("res://scripts/main_menu.gd")

## Zu Fuß unterwegs (F) und Startmenü, beide im Code gebaut
var _on_foot
var _menu
## Editor im Spiel (F2): Modelle importieren und in die Welt stellen (scripts/build_editor.gd)
var _builder: BuildEditor
## true = the second map "City Block" instead of the endless world
var _city_mode: bool = false
## The city map node from main.tscn (only used in city mode)
var _city_map: CityMap
## AI traffic on the city streets (only used in city mode)
var _city_traffic: CityTraffic
## NPC traffic on the player's own roads from the editor (both maps)
var _road_traffic: CityTraffic
## City mode: seconds spent waiting for the car model behind the loading screen
var _city_car_wait: float = 0.0
## City mode: how long the loading screen may wait for the car model (seconds)
const CITY_CAR_TIMEOUT: float = 6.0

var world_is_ready: bool = false
var _car_on_road: bool = false
var _start_point: Vector2 = Vector2.ZERO
var _start_heading: float = 0.0
var _place_timer: float = 0.0
var _last_car_position := Vector3.ZERO
var _started: bool = false
## Loading watchdog: after this many seconds the car is released as soon as the tile under it has collision,
## even if the full area or the horizon ring is still not ready (so loading can never hang forever)
const LOAD_TIMEOUT: float = 45.0
var _load_time: float = 0.0
var _load_warned: bool = false
## Normal terrain limits (the terrain is loaded faster behind the loading screen, see _boost_loading)
var _normal_jobs: int = 6
var _normal_uploads: int = 2


func _ready() -> void:
	# Second map: -- --track=city on the command line, or the menus set CityMode.enabled
	# and reload this scene. Everything else (car, garage, HUD, pause menu, weather,
	# settings) stays the same and only the procedural world is left out.
	_city_mode = CityMode.enabled or OS.get_cmdline_user_args().has("--track=city")
	# Name of the app (the project name stays; the save folder user:// is named after it)
	get_window().title = APP_TITLE
	world_gen.setup()
	_on_foot = OnFootScript.new()
	_on_foot.name = "OnFoot"
	_on_foot.car = car
	_on_foot.follow_camera = get_node_or_null("Camera")
	add_child(_on_foot)
	_menu = MainMenuScript.new()
	_menu.name = "MainMenu"
	_menu.garage = garage
	_menu.pause_menu = get_node_or_null("PauseMenu")
	add_child(_menu)
	# Welt-Editor: Modelle importieren, aufstellen und speichern (F2)
	_builder = BuildEditor.new()
	_builder.name = "BuildEditor"
	_builder.game = self
	_builder.car = car
	add_child(_builder)
	_builder.layout_loaded.connect(_on_layout_loaded)
	var start_point := Vector2.ZERO
	var heading := 0.0
	if debug_tools.has_start_position:
		start_point = debug_tools.start_position
		heading = debug_tools.start_heading
	if debug_tools.time_of_day >= 0.0:
		day_night.time_of_day = debug_tools.time_of_day
		day_night.paused = true
	if debug_tools.volumetric_fog:
		day_night.set_volumetric_fog(true)
	# Tests fahren immer mit dem angegebenen Auto oder dem ersten (nicht dem gespeicherten)
	if debug_tools.car_id != "":
		car.apply_profile(load("res://cars/%s.tres" % debug_tools.car_id))
	elif debug_tools.is_active() and garage and not garage.cars.is_empty():
		car.apply_profile(garage.cars[0])
	_start_point = start_point
	_start_heading = heading
	car.freeze = true
	# Second map: no procedural world at all, the city is loaded in its place
	if _city_mode:
		_start_city(start_point, heading)
		return
	# Vorläufiger Platz, bis die Straßen in der Nähe berechnet sind
	car.teleport(find_start(start_point, heading), true)
	roads.start(world_gen, car)
	if map_tiles:
		map_tiles.world_gen = world_gen
	if weather:
		weather.world_gen = world_gen
		# Tests: festes Wetter (Standard klar, Sommer), damit Bilder und Messungen vergleichbar sind
		if debug_tools.is_active():
			weather.set_debug(debug_tools.weather_id, debug_tools.season_id)
	# Vergleichsmessungen (DebugTools): ohne nahe Detail-Bäume bzw. ohne Impostoren
	if OS.get_cmdline_user_args().has("--nonear"):
		terrain.near_tree_distance = 0.0
	if OS.get_cmdline_user_args().has("--noimpostor"):
		terrain.use_impostors = false
	_normal_jobs = terrain.max_parallel_jobs
	_normal_uploads = terrain.max_uploads_per_frame
	_boost_loading()
	terrain.start(world_gen, car, roads)
	horizon.start(world_gen, car, terrain)
	water.start(world_gen, car, roads)
	grass.start(world_gen, car, terrain, roads)
	loading_screen.visible = true
	# Shader, die erst später gebraucht werden (Regen, Tunnel, Übergänge …), hinter dem Ladebildschirm übersetzen
	if not OS.get_cmdline_user_args().has("--nowarmup"):
		var warmup := ShaderWarmup.new()
		add_child(warmup)
		var extra: Array[Material] = [terrain.foliage_material, roads.road_material]
		warmup.start(get_viewport().get_camera_3d(), extra)
	# Die Garage öffnet sich, sobald die Welt geladen ist (siehe _process)


## Second map: switch the procedural world off and load the city instead.
## The nodes stay in the scene, so garage, HUD, pause menu, weather and settings
## keep working exactly as in the endless world.
func _start_city(start_point: Vector2, heading: float) -> void:
	CityMode.enabled = true
	get_window().title = "%s – City Block" % APP_TITLE
	# Systems that need roads or terrain must not run (they would query roads that never started)
	for part in ["Terrain", "Roads", "Water", "Grass", "HorizonRing", "Traffic", "SpeedLimits",
			"CruiseControl", "Race", "Puddles", "Waterfalls", "LakeLife", "Exploration",
			"Viewpoints", "FastTravel", "MapTiles", "Navigation", "CarReset", "ChillMode",
			"PassbySound", "TunnelEffects", "KeyHints"]:
		var node := get_node_or_null(part)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED
		if node is Node3D:
			(node as Node3D).visible = false
	# The map has no roads, so the minimap and the navigation banner stay hidden
	var hud := get_node_or_null("HUD")
	if hud:
		for part in ["Minimap", "NavBanner"]:
			var control := hud.get_node_or_null(part)
			if control:
				control.visible = false
	_city_map = get_node_or_null("CityMap") as CityMap
	if _city_map == null:
		push_error("CityMap node missing in main.tscn")
		return
	if debug_tools.has_start_position:
		_city_map.spawn_point = Vector3(start_point.x, _city_map.spawn_point.y, start_point.y)
		_city_map.spawn_heading = heading
	if not _city_map.map_ready.is_connected(_on_city_map_ready):
		_city_map.map_ready.connect(_on_city_map_ready)
	_city_map.build(car)
	# F2 can edit the city's own houses and blocks (move, rotate, scale, delete)
	if _builder:
		_builder.city_map = _city_map
	car.teleport(_city_map.start_transform(), true)
	# GTA-style AI traffic on the city streets (its own street grid, see CityTraffic)
	if _city_traffic == null:
		_city_traffic = CityTraffic.new()
		_city_traffic.name = "CityTraffic"
		add_child(_city_traffic)
	_city_traffic.car = car
	_city_traffic.on_foot = _on_foot
	_city_traffic.build()
	if _on_foot:
		_on_foot.set("city_traffic", _city_traffic)
	# The city has no road network, so the big map shows a picture of the city instead.
	# The picture is drawn in the background (see CityMap._build_map_async).
	_on_city_map_ready(_city_map.map_texture, _city_map.map_bounds)
	if weather:
		weather.world_gen = world_gen
	# The city is still and full of straight edges (poles, railings, kerbs); without
	# anti-aliasing they sparkle while driving, so temporal anti-aliasing is on here
	get_viewport().use_taa = true
	# The loading screen stays until the car model is built: until then the car is a
	# painted box, and in the endless world the terrain loading hides that moment
	_city_car_wait = 0.0
	loading_screen.visible = true
	var screen := loading_screen as LoadingScreen
	if screen:
		screen.set_progress(0.9, "Loading car …")
	world_is_ready = false


## The editor has put the saved layout into the world (or changed it)
func _on_layout_loaded() -> void:
	refresh_road_traffic()


## NPC cars drive on the player's own roads (the editor's @road pieces). Called when the
## layout is loaded and whenever the roads are placed, moved or deleted.
func refresh_road_traffic() -> void:
	if _builder == null:
		return
	var segments: Array = _builder.placed_roads()
	if segments.is_empty():
		if _road_traffic != null and is_instance_valid(_road_traffic):
			_road_traffic.queue_free()
			_road_traffic = null
		return
	if _road_traffic == null or not is_instance_valid(_road_traffic):
		_road_traffic = CityTraffic.new()
		_road_traffic.name = "RoadTraffic"
		add_child(_road_traffic)
		_road_traffic.car = car
		_road_traffic.on_foot = _on_foot
	if not _road_traffic.build_on_roads(segments):
		_road_traffic.queue_free()
		_road_traffic = null
		return
	if _on_foot:
		_on_foot.set("road_traffic", _road_traffic)


## City map: the picture is finished (drawn in a background thread), hand it to the big map
func _on_city_map_ready(texture: Texture2D, bounds: Rect2) -> void:
	if texture == null:
		return
	var big_map := get_node_or_null("BigMap") as BigMap
	if big_map:
		big_map.set_city_map(texture, bounds)


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_timed_process(delta)
	FrameCosts.add("Spiel", started)


func _timed_process(delta: float) -> void:
	if _city_mode and not world_is_ready:
		_update_city_loading(delta)
		return
	if world_is_ready:
		_check_for_jump()
		return
	_update_loading()
	_load_time += delta
	if not _car_on_road:
		_place_car_on_road(delta)
		return
	if terrain.is_area_ready(car.global_position) and horizon.is_ready_at(car.global_position):
		_finish_loading()
	elif _load_time > LOAD_TIMEOUT:
		# Watchdog: Loading takes unusually long. Say what is missing, and let the car go as soon as there is ground under it.
		if not _load_warned:
			_load_warned = true
			push_warning("Loading takes very long (%.0f s): terrain area %.0f %%, horizon ring ready: %s" % [_load_time,
				terrain.area_progress(car.global_position) * 100.0, str(horizon.is_ready_at(car.global_position))])
		if terrain.is_ground_ready_at(car.global_position):
			_finish_loading()


## City mode: wait for the car model before the world is shown (the car is a painted
## box until then). A timeout keeps a missing model from blocking the start.
func _update_city_loading(delta: float) -> void:
	_city_car_wait += delta
	var model := car.get_node_or_null("Model") as CarModel
	var screen := loading_screen as LoadingScreen
	if screen:
		screen.set_progress(0.9, "Loading car …")
	if model != null and model.is_loading() and _city_car_wait < CITY_CAR_TIMEOUT:
		return
	_finish_loading()


## Loading is done: hide the loading screen, release the car and (at the first start) open the garage
func _finish_loading() -> void:
	world_is_ready = true
	_load_time = 0.0
	_load_warned = false
	_restore_loading_limits()
	var screen := loading_screen as LoadingScreen
	if screen:
		screen.finish(not debug_tools.is_active())
	else:
		loading_screen.visible = false
	car.freeze = false
	_last_car_position = car.global_position
	# Test tools only start the first time (not after every jump).
	# When the game starts normally (no tests), the garage opens first.
	if not _started:
		_started = true
		debug_tools.on_world_ready(self)
		if garage and not debug_tools.is_active():
			if _menu:
				_menu.open()
			else:
				garage.open()
		if whats_new:
			whats_new.show_if_new()
		refresh_road_traffic()


## Behind the loading screen nothing else needs the CPU: build more terrain tiles at once and insert more per frame
func _boost_loading() -> void:
	terrain.max_parallel_jobs = clampi(OS.get_processor_count(), _normal_jobs, 12)
	terrain.max_uploads_per_frame = maxi(_normal_uploads, 6)


func _restore_loading_limits() -> void:
	terrain.max_parallel_jobs = _normal_jobs
	terrain.max_uploads_per_frame = _normal_uploads


## Fortschrittsbalken im Ladebildschirm: erst die Straßen rund um den Start, dann die Gelände-Kacheln am
## Auto, dann die Fernsicht (Horizont-Ring); das Automodell lädt nebenher
func _update_loading() -> void:
	var screen := loading_screen as LoadingScreen
	if screen == null:
		return
	var road := 1.0 if _car_on_road else roads.area_progress(_start_point, 1200.0)
	var ground := terrain.area_progress(car.global_position) if _car_on_road else 0.0
	var far := 1.0 if _car_on_road and horizon.is_ready_at(car.global_position) else 0.0
	var model := car.get_node_or_null("Model") as CarModel
	var status := "Planning roads …"
	if _car_on_road:
		status = "Generating terrain, trees and water …"
		if ground >= 1.0:
			status = "Calculating distant view …"
	if model and model.is_loading() and road >= 1.0:
		status = "Loading car …"
	screen.set_progress(road * 0.4 + ground * 0.45 + far * 0.15, status)


## Ist das Auto gerade weit gesprungen (Reset, Teleport) und fehlt dort noch Gelände?
## Dann kurz den Ladebildschirm zeigen, bis es da ist (sonst sähe man Löcher und den
## Horizont-Ring, und das Auto könnte durch den Boden fallen).
func _check_for_jump() -> void:
	if _city_mode:
		return  # the city has no terrain tiles to wait for
	var here := car.global_position
	var jumped := here.distance_to(_last_car_position) > 50.0
	_last_car_position = here
	if not jumped:
		return
	if terrain.is_area_ready(here) and horizon.is_ready_at(here):
		return
	world_is_ready = false
	_car_on_road = true
	_load_time = 0.0
	_boost_loading()
	car.freeze = true
	loading_screen.visible = true


## Weiter Sprung (z. B. Teleport im Test): wie beim Start den Ladebildschirm zeigen und
## warten, bis Straßen und Gelände an der neuen Stelle da sind
func jump_to(point: Vector2) -> void:
	world_is_ready = false
	_car_on_road = false
	_place_timer = 0.0
	_load_time = 0.0
	_boost_loading()
	_start_point = point
	car.freeze = true
	car.teleport(find_start(point, _start_heading), true)
	loading_screen.visible = true


## Setzt das Auto auf die nächste Straße, sobald die Straßen in der Nähe berechnet sind
func _place_car_on_road(delta: float) -> void:
	_place_timer += delta
	if not roads.is_area_ready(_start_point, 1200.0):
		return
	var forward := Vector3(sin(deg_to_rad(_start_heading)), 0.0, cos(deg_to_rad(_start_heading)))
	var result := roads.nearest_road_transform(Vector3(_start_point.x, 0.0, _start_point.y), forward,
		debug_tools.on_highway)
	if result["found"]:
		car.teleport(result["transform"], true)
		_car_on_road = true
	elif _place_timer > 15.0:
		# Notfall: weit und breit keine Straße, dann eben im Gelände starten
		push_warning("No road found nearby, the car starts on open terrain.")
		_car_on_road = true


## Geländehöhe an einer Stelle (ohne Straßen)
func ground_height(x: float, z: float) -> float:
	var lakes: Array = world_gen.lakes_near(Rect2(x - 1.0, z - 1.0, 2.0, 2.0))
	return world_gen.terrain_height(x, z, lakes)


## Sucht in der Nähe eine flache, trockene Stelle für das Auto
func find_start(near: Vector2, heading_degrees: float) -> Transform3D:
	var best := near
	var best_score := INF
	for iz in range(-8, 9):
		for ix in range(-8, 9):
			var p := near + Vector2(ix, iz) * 40.0
			var lakes: Array = world_gen.lakes_near(Rect2(p.x - 1.0, p.y - 1.0, 2.0, 2.0))
			if world_gen.water_level_at(p.x, p.y, lakes) > WorldGen.NO_WATER:
				continue
			var h := world_gen.terrain_height(p.x, p.y, lakes)
			var bumpiness := absf(world_gen.terrain_height(p.x + 4.0, p.y, lakes) - h) \
				+ absf(world_gen.terrain_height(p.x, p.y + 4.0, lakes) - h)
			var score := bumpiness * 10.0 + p.distance_to(near) * 0.01
			if score < best_score:
				best_score = score
				best = p
	var start_position := Vector3(best.x, ground_height(best.x, best.y) + 1.2, best.y)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(heading_degrees)), start_position)
