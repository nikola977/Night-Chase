class_name CityMap
extends Node3D
## Second map: the "City block" (Sketchfab FBX, see docs/track.md).
##
const Parking := preload("res://scripts/city_parking.gd")

## Was eine Fläche auf der Karte ist (siehe _map_style)
enum MapStyle { SKIP, GROUND, PROP, BUILDING }

## Wo der Editor die Veränderungen an den Stadtobjekten speichert (Position,
## Rotation, Skalierung, gelöscht). Liegt neben layout.json in user://editor.
const CITY_LAYOUT_PATH := "user://editor/city_layout.json"

## Farben des Kartenbildes: derselbe dunkle Kartenstil wie in der endlosen Welt
## (MapView.BACKGROUND, MapTiles), nur mit Straßen und Dächern statt Gelände
const MAP_BACKGROUND := Color("#111721")
const MAP_STREET := Color("#4A566B")
const MAP_PROP := Color("#1B2A26")
const MAP_LOW := Color("#2A3342")
const MAP_HIGH := Color("#96A3B8")
const MAP_LOT := Color("#3A4557")
const MAP_PAINT := Color("#93A0B4")
const MAP_STALL := Color("#4B5769")
## Kantenlänge der Bodentextur, die für die Karte ausgewertet wird (die Straßenmarkierungen
## stecken in der Textur, nicht in den Flächen)
const MAP_TEXTURE_SIZE: int = 512
## Helligkeit von Asphalt auf der Karte und wie stark helle Stellen (Markierungen) leuchten.
## Die Straßentextur ist sehr hell (Betonplatten, weiße Linien); die Kurve dunkelt sie so
## weit ab, dass die Straßenmarkierungen auf dunklem Asphalt liegen wie auf der Karte der
## endlosen Welt.
const MAP_ASPHALT_TONE: float = 0.15
const MAP_ASPHALT_GAIN: float = 0.32
const MAP_ASPHALT_CURVE: float = 1.25

## The node lives in main.tscn but does nothing until game.gd calls build().
## Then it welds the 1325 meshes of the model into one surface per material
## (1325 draw calls become 22), builds a single trimesh for the physics from
## the same surfaces and puts invisible walls around the island.

@export_group("Data")
## The FBX in the project (Godot imports it on the first start)
@export_file("*.fbx") var city_file: String = "res://assets/tracks/city/city.fbx"

@export_group("Start")
## Spot on the road (right lane of the east-west street)
@export var spawn_point: Vector3 = Vector3(-250.0, 1.0, -68.3)
## Direction of the car in degrees (0 = +Z, 90 = +X)
@export var spawn_heading: float = 90.0

@export_group("Map")
## Pixels per metre of the map picture that the big map (M) shows. The picture is drawn
## from the merged city meshes, so it has the same detail as the city itself.
@export var map_pixels_per_meter: float = 5.0

@export_group("Physics")
## Invisible walls at the edge: the map is an island, without them the car falls into the void
@export var boundary_walls: bool = true
## Parking lots on the empty ground between the blocks (see CityParking)
@export var parking: bool = true
## Lamp posts and traffic light poles are cut out of the merged city and put in as
## their own nodes, so they can fall over when the car hits them (scripts/falling_pole.gd)
@export var falling_poles: bool = true
## The pavement is 20 cm higher than the road. The car body sits only 3 cm above
## the road, so its collision box hits the kerb edge and stops. Low ground is
## therefore squashed towards the road instead of being snapped onto it: the
## pavement keeps 3 cm, small enough to drive over, but no two surfaces end up in
## the same plane (surfaces in one plane flicker, because the depth buffer cannot
## decide which one is in front).
@export var flatten_ground: bool = true
## Everything below this height counts as ground (road, pavement, kerbs)
@export var ground_below: float = 0.5
## Height of the road (lower ground stays here, nothing is moved below it)
@export var ground_level: float = 0.0
## Height the raised ground keeps after squashing (the step over a kerb). The car
## body sits 3 cm above the road, so anything higher catches on the kerb.
@export var kerb_step: float = 0.02
## How much of the original height difference survives (0.15 → 20 cm become 3 cm)
@export var kerb_squash: float = 0.15
## Small vertical faces right at ground level are dropped from the physics
@export var ignore_kerb_faces: bool = true
## Height up to which a vertical face counts as a kerb
@export var kerb_height: float = 0.35

## Emitted when the map picture is finished (it is drawn in a background thread, so the
## loading screen does not have to wait for it)
signal map_ready(texture: Texture2D, bounds: Rect2)

## Whole map, used for the walls
var bounds: AABB = AABB()
## Top-down picture of the city and the world rectangle it shows (x/z), for the big map
var map_texture: ImageTexture
var map_bounds := Rect2()

## Die Parkplätze (eigene Meshes mit eigener Kollision)
var _surfaces: Node3D
## Alle Stadtobjekte (eine Node3D-Gruppe pro Haus/Block/Straße aus dem FBX)
var _objects: Node3D
## Alle gezeichneten Meshes der Stadt (für das Kartenbild)
var _merged: Array[MeshInstance3D] = []
## Material-Kopien pro Materialname, damit nicht jedes Haus neue Materialien anlegt
var _material_cache: Dictionary = {}
var _car: VehicleBody3D

## Background job for the map picture: the task id, the data it works on, the result
var _map_task: int = -1
var _map_job: Dictionary = {}
var _map_image: Image
var _map_mutex := Mutex.new()


func build(car: VehicleBody3D) -> void:
	_car = car
	if not ResourceLoader.exists(city_file):
		push_error("City file missing: %s" % city_file)
		return
	var scene := load(city_file) as PackedScene
	if scene == null:
		push_error("City file is not a scene: %s" % city_file)
		return
	var started := Time.get_ticks_msec()
	_objects = Node3D.new()
	_objects.name = "CityObjects"
	add_child(_objects)
	_surfaces = Node3D.new()
	_surfaces.name = "Parking"
	add_child(_surfaces)
	var source := scene.instantiate()
	var poles: Array = []
	var triangles := 0
	var flattened := 0
	var glowing := 0
	var draw_meshes := 0
	var index := 0
	var boxes: Array[AABB] = []
	for child in source.get_children():
		var holder := _build_object(child, index, poles, boxes)
		index += 1
		if holder == null:
			continue
		_objects.add_child(holder)
		triangles += int(holder.get_meta("triangles", 0))
		flattened += int(holder.get_meta("flattened", 0))
		glowing += int(holder.get_meta("glowing", 0))
		draw_meshes += int(holder.get_meta("draw_meshes", 0))
	source.free()
	if boxes.is_empty():
		push_error("No meshes in %s" % city_file)
		return
	bounds = boxes[0]
	for box in boxes:
		bounds = bounds.merge(box)
	# Vom Editor verschobene, skalierte oder gelöschte Objekte wiederherstellen
	_apply_city_layout()
	print("City: %d editable objects (%d draw meshes, %d triangles), %.0f ms, bounds %s, %d ground vertices squashed, %d glowing" % [
		_objects.get_child_count(), draw_meshes, triangles, Time.get_ticks_msec() - started,
		bounds, flattened, glowing])
	if parking:
		Parking.build(_surfaces)
	if not poles.is_empty():
		_spawn_poles(poles)
	_build_collision()
	if boundary_walls:
		_build_walls()
	_build_map_async()

## Squash low ground towards the road: the kerb stays a small step instead of a
## wall, but pavement and road keep different heights (no flickering surfaces).
## `y_offset` is the height of the object the vertices belong to.
func _flatten(arrays: Array, y_offset: float = 0.0) -> int:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var changed := 0
	for i in verts.size():
		var y := verts[i].y + y_offset
		if y > -0.2 and y < ground_below:
			var squash := minf(kerb_step, maxf(0.0, y - ground_level) * kerb_squash)
			var target := ground_level + squash
			if absf(y - target) > 0.0001:
				verts[i].y = target - y_offset
				changed += 1
	arrays[Mesh.ARRAY_VERTEX] = verts
	return changed

## Copy of the imported material with the settings the city needs: the light
## materials (neon signs, lit windows) glow, everything else stays matte
func _city_material(material: StandardMaterial3D, key: String) -> StandardMaterial3D:
	if material == null:
		return null
	if _material_cache.has(key):
		return _material_cache[key]
	var copy := material.duplicate() as StandardMaterial3D
	copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if key.to_lower().contains("glow"):
		# The GLOW surfaces are the lit signs and windows of the model. Low energy and
		# the texture as emission keep them coloured at night instead of white blobs.
		copy.emission_enabled = true
		copy.emission = Color.WHITE
		copy.emission_texture = copy.albedo_texture
		copy.emission_energy_multiplier = 0.22
	_material_cache[key] = copy
	return copy


## Ein Stadtobjekt (eine Gruppe aus dem FBX: ein Haus, ein Block, eine Straße).
## Die Meshes der Gruppe werden pro Material zusammengefasst, damit das Objekt nur
## wenige Draw-Calls hat, aber als Ganzes verschoben, gedreht, skaliert und gelöscht
## werden kann. Jedes Objekt bekommt seine eigene Kollision.
func _build_object(child: Node, index: int, poles: Array, boxes: Array[AABB]) -> Node3D:
	var holder := Node3D.new()
	var clean := String(child.name).validate_node_name()
	holder.name = clean if clean != "" else "Object%d" % index
	holder.set_meta("city_object", true)
	holder.set_meta("city_id", "o%04d" % index)
	holder.set_meta("city_label", String(child.name))
	if child is Node3D:
		holder.transform = (child as Node3D).transform
	var tools: Dictionary = {}
	var order: Array[String] = []
	var materials: Dictionary = {}
	var world := holder.transform
	if child is MeshInstance3D:
		_collect_mesh(child as MeshInstance3D, Transform3D.IDENTITY, world, tools, order, materials, poles, boxes)
	for grandchild in child.get_children():
		_collect_part(grandchild, Transform3D.IDENTITY, world, tools, order, materials, poles, boxes)
	var triangles := 0
	var flattened := 0
	var glowing := 0
	for key in order:
		var arrays: Array = (tools[key] as SurfaceTool).commit_to_arrays()
		if arrays.is_empty():
			continue
		if flatten_ground:
			flattened += _flatten(arrays, holder.position.y)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var lit := _city_material(materials.get(key) as StandardMaterial3D, key)
		if key.to_lower().contains("glow"):
			glowing += 1
		mesh.surface_set_material(0, lit)
		var instance := MeshInstance3D.new()
		instance.name = key.validate_node_name()
		instance.mesh = mesh
		holder.add_child(instance)
		_merged.append(instance)
		triangles += _surface_triangles(mesh)
	# Leere Gruppen (nur Marker im FBX) sind keine Objekte
	if triangles == 0:
		holder.free()
		return null
	holder.set_meta("triangles", triangles)
	holder.set_meta("flattened", flattened)
	holder.set_meta("glowing", glowing)
	holder.set_meta("draw_meshes", holder.get_child_count())
	_add_holder_collision(holder)
	return holder


## Sammelt alle Meshes unter `node` (Transform relativ zum Objekt) in SurfaceTools
## pro Material. `holder_xf` ist der Transform des ganzen Objekts und wird nur für
## Weltkoordinaten (Lampen, Bounds) gebraucht.
func _collect_part(node: Node, local: Transform3D, holder_xf: Transform3D, tools: Dictionary,
		order: Array[String], materials: Dictionary, poles: Array, boxes: Array[AABB]) -> void:
	var here := local
	if node is Node3D:
		here = local * (node as Node3D).transform
	if node is MeshInstance3D:
		_collect_mesh(node as MeshInstance3D, here, holder_xf, tools, order, materials, poles, boxes)
	for c in node.get_children():
		_collect_part(c, here, holder_xf, tools, order, materials, poles, boxes)


## Ein einzelnes Mesh in die Material-SurfaceTools des Objekts legen
func _collect_mesh(instance: MeshInstance3D, xf: Transform3D, holder_xf: Transform3D,
		tools: Dictionary, order: Array[String], materials: Dictionary, poles: Array,
		boxes: Array[AABB]) -> void:
	var mesh: Mesh = instance.mesh
	if mesh == null:
		return
	var world := holder_xf * xf
	boxes.append(world * mesh.get_aabb())
	var pole: Dictionary = _pole_of(mesh, world) if falling_poles else {}
	if not pole.is_empty():
		poles.append(pole)
		return
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		var key: String = material.resource_name if material != null else "<no material>"
		if not tools.has(key):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			if material != null:
				tool.set_material(material)
			tools[key] = tool
			materials[key] = material
			order.append(key)
		(tools[key] as SurfaceTool).append_from(mesh, surface, xf)


func _surface_triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if typeof(indices) == TYPE_PACKED_INT32_ARRAY and not (indices as PackedInt32Array).is_empty():
			count += (indices as PackedInt32Array).size() / 3
		else:
			count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return count


## Eigene Kollision pro Stadtobjekt: die Dreiecke des Objekts, mit flachem Boden
## (Kerb faces wie bisher weggelassen). So verschwindet die Kollision mit dem Objekt,
## wenn es gelöscht wird, und wandert mit, wenn es verschoben wird.
func _add_holder_collision(holder: Node3D) -> void:
	var xf := holder.transform
	var inverse := xf.affine_inverse()
	var faces := PackedVector3Array()
	var skipped := 0
	for child in holder.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var source := instance.mesh.get_faces()
		for i in range(0, source.size(), 3):
			var a := xf * source[i]
			var b := xf * source[i + 1]
			var c := xf * source[i + 2]
			if ignore_kerb_faces and _is_kerb(a, b, c):
				skipped += 1
				continue
			for point in [a, b, c]:
				faces.append(inverse * _physics_point(point))
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.set_meta("city_object_collision", true)
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	holder.add_child(body)

## A lamp post: tall and thin, standing on the ground. The bottom edge decides, because
## the lamp itself sits at the end of an arm that makes the whole mesh 2 m wide.
## Empty = no post (a house, a fence, a sign).
func _pole_of(mesh: Mesh, xform: Transform3D) -> Dictionary:
	var box: AABB = xform * mesh.get_aabb()
	if box.position.y > 1.5 or box.size.y < 8.0 or box.size.y > 16.0:
		return {}
	if maxf(box.size.x, box.size.z) > 3.6:
		return {}
	var low := box.position.y + 0.15
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for point in mesh.get_faces():
		var p := xform * point
		if p.y > low:
			continue
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	if min_x == INF:
		return {}
	var radius := maxf(max_x - min_x, max_z - min_z) * 0.5
	if radius > 0.5:
		return {}
	return {
		"mesh": mesh,
		"xform": xform,
		"base": Vector3((min_x + max_x) * 0.5, box.position.y, (min_z + max_z) * 0.5),
		"radius": maxf(radius, 0.07),
		"height": box.size.y,
	}


## One node per post: the model mesh hangs below a pivot at its foot point, so the whole
## post can tip over
func _spawn_poles(poles: Array) -> void:
	for i in poles.size():
		var pole: Dictionary = poles[i]
		var base: Vector3 = pole["base"]
		var xform: Transform3D = pole["xform"]
		var visual := MeshInstance3D.new()
		visual.mesh = pole["mesh"]
		# Das Mesh so verschieben, dass der Fußpunkt genau im Ursprung des Knotens liegt
		visual.transform = Transform3D(xform.basis, xform.origin - base)
		var post := FallingPole.new()
		post.name = "Pole%d" % (i + 1)
		post.add_child(visual)
		post.setup(base, pole["height"], pole["radius"], _car)
		add_child(post)
	print("City: %d poles that fall over" % poles.size())


## One trimesh for the whole map (31 050 triangles). The map is small enough that
## a separate physics file like the old track needed is not worth it.
func _build_collision() -> void:
	var faces := PackedVector3Array()
	var skipped := 0
	for child in _surfaces.get_children():
		var instance := child as MeshInstance3D
		if instance.has_meta("skip_physics"):
			continue
		var mesh: ArrayMesh = instance.mesh
		var source := mesh.get_faces()
		# The parking lots are built 8 cm high with a slope; they keep that height in the
		# physics, so the car drives up the slope instead of sinking into the asphalt
		var keep := instance.has_meta("keep_physics_height")
		for i in range(0, source.size(), 3):
			if ignore_kerb_faces and _is_kerb(source[i], source[i + 1], source[i + 2]):
				skipped += 1
				continue
			for corner in 3:
				faces.append(source[i + corner] if keep else _physics_point(source[i + corner]))
	var body := StaticBody3D.new()
	body.name = "CityCollision"
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	add_child(body)
	print("City: parking physics with %d triangles (%d kerb faces left out)" % [faces.size() / 3, skipped])


## The car's collision box sits a few millimetres above the road, so even the small
## visible kerb would stop it. The physics therefore gets one flat ground (the road
## level): the car drives onto the pavement, and its wheels sink 2 cm into it — which
## cannot be seen, while the drawing keeps the kerb that makes the streets look right.
func _physics_point(point: Vector3) -> Vector3:
	if flatten_ground and point.y > ground_level + 0.0001 and point.y < ground_below:
		return Vector3(point.x, ground_level, point.z)
	return point


## The big map (M) needs something to show, and the city has no road network. So the
## city is drawn from above in the same dark style as the map of the endless world
## (MapTiles/MapView): dark ground, streets in grey, the roofs shaded by height, the
## parking lots outlined. Drawn once, so it does not depend on time of day or weather.
## The picture is 2790 x 1170 pixels and takes about 3.5 s in GDScript, so the surfaces
## are only collected here; the pixels are filled in a background thread while the game
## is already running (see _draw_map and _process).
func _build_map_async() -> void:
	if _surfaces == null or _surfaces.get_child_count() == 0:
		return
	var area := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	if area.size.x < 1.0 or area.size.y < 1.0:
		return
	var scale := maxf(0.5, map_pixels_per_meter)
	var job := {
		"area": area,
		"scale": scale,
		"width": maxi(8, roundi(area.size.x * scale)),
		"height": maxi(8, roundi(area.size.y * scale)),
		"surfaces": [],
		"started": Time.get_ticks_msec(),
	}
	var textures: Dictionary = {}
	var draw_meshes: Array[Node] = []
	for mesh_instance in _merged:
		draw_meshes.append(mesh_instance)
	for child in _surfaces.get_children():
		draw_meshes.append(child)
	for child in draw_meshes:
		var mesh: Mesh = (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		var style := _map_style(child.name)
		if style == MapStyle.SKIP:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var faces: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if faces.is_empty():
			continue
		var uvs := PackedVector2Array()
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			uvs = arrays[Mesh.ARRAY_TEX_UV]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		if not indices.is_empty():
			# Flächen und UVs in Dreiecksreihenfolge bringen (die Netze der Stadt haben keine
			# Indizes, aber sicher ist sicher)
			var ordered := PackedVector3Array()
			var ordered_uvs := PackedVector2Array()
			ordered.resize(indices.size())
			ordered_uvs.resize(indices.size())
			for i in indices.size():
				ordered[i] = faces[indices[i]]
				if indices[i] < uvs.size():
					ordered_uvs[i] = uvs[indices[i]]
			faces = ordered
			uvs = ordered_uvs
		# Die Straßen tragen ihre Markierungen in der Textur: daraus werden auf der Karte
		# helle Linien auf dunklem Asphalt, wie die Straßen der endlosen Welt
		var ground: Dictionary = {}
		var material := mesh.surface_get_material(0) as StandardMaterial3D
		if style == MapStyle.GROUND and not uvs.is_empty() and material != null \
				and material.albedo_texture != null:
			var key := material.albedo_texture.get_instance_id()
			if not textures.has(key):
				textures[key] = _map_texture_data(material.albedo_texture)
			ground = (textures[key] as Dictionary).duplicate()
			ground["scale"] = Vector2(material.uv1_scale.x, material.uv1_scale.y)
		job["surfaces"].append({"style": style, "faces": faces, "uvs": uvs, "ground": ground})
	_map_job = job
	# Poll in _process even while the game is paused (the big map pauses the tree)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_map_task = WorkerThreadPool.add_task(_draw_map.bind(job), false, "City map")


## Runs in a background thread: only the collected data, no scene tree
func _draw_map(job: Dictionary) -> void:
	var width: int = job["width"]
	var height: int = job["height"]
	var area: Rect2 = job["area"]
	var scale: float = job["scale"]
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	image.fill(MAP_BACKGROUND)
	var data := image.get_data()
	# Höchste Fläche pro Bildpunkt: die Karte wird von oben gezeichnet, und wo zwei
	# Flächen übereinander liegen (Dach über Straße), gewinnt die höhere
	var top := PackedFloat32Array()
	top.resize(width * height)
	top.fill(-1000.0)
	for surface: Dictionary in job["surfaces"]:
		var faces: PackedVector3Array = surface["faces"]
		var uvs: PackedVector2Array = surface["uvs"]
		var style: int = surface["style"]
		var ground: Dictionary = surface["ground"]
		for i in range(0, faces.size(), 3):
			_map_face(data, top, width, height, faces, uvs, i, area, scale, style, ground)
	_map_mutex.lock()
	_map_image = Image.create_from_data(width, height, false, Image.FORMAT_RGB8, data)
	_map_mutex.unlock()


## Main thread: take the finished picture, draw the parking lots on it and hand it to
## the big map
func _process(_delta: float) -> void:
	if _map_task < 0:
		return
	if not WorkerThreadPool.is_task_completed(_map_task):
		return
	WorkerThreadPool.wait_for_task_completion(_map_task)
	_map_task = -1
	_map_mutex.lock()
	var image: Image = _map_image
	_map_image = null
	_map_mutex.unlock()
	if image == null or _map_job.is_empty():
		return
	var area: Rect2 = _map_job["area"]
	_draw_lots(image, area, float(_map_job["scale"]))
	image.generate_mipmaps()
	map_texture = ImageTexture.create_from_image(image)
	map_bounds = area
	print("City: map picture %d x %d px in %d ms (drawn in the background) for %s" % [
		int(_map_job["width"]), int(_map_job["height"]),
		Time.get_ticks_msec() - int(_map_job["started"]), area])
	map_ready.emit(map_texture, map_bounds)


## Which colour a surface gets on the map: lit windows and signs (the GLOW materials)
## show nothing from above, the streets and the parking lots are ground, trees and
## props stay dark, everything else is a building
func _map_style(key: String) -> int:
	var name := key.to_lower()
	if name.contains("glow"):
		return MapStyle.SKIP
	if name == "roadsground" or name.begins_with("parking"):
		return MapStyle.GROUND
	if name.begins_with("cityprops") or name.begins_with("elise") or name.begins_with("tire"):
		return MapStyle.PROP
	return MapStyle.BUILDING


## One triangle of the city seen from above: every picture point inside it gets filled,
## but only where nothing higher is already drawn. The edges are stepped forward instead
## of recomputed for every point, otherwise the streets would take seconds.
func _map_face(data: PackedByteArray, top: PackedFloat32Array, width: int, height: int,
		faces: PackedVector3Array, uvs: PackedVector2Array, index: int, area: Rect2,
		scale: float, style: int, ground: Dictionary) -> int:
	var a := faces[index]
	var b := faces[index + 1]
	var c := faces[index + 2]
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000001:
		return 0
	normal = normal.normalized()
	# Wände und Unterseiten zeigen von oben nichts
	if absf(normal.y) < 0.2:
		return 0
	var ax := (a.x - area.position.x) * scale
	var az := (a.z - area.position.y) * scale
	var bx := (b.x - area.position.x) * scale
	var bz := (b.z - area.position.y) * scale
	var cx := (c.x - area.position.x) * scale
	var cz := (c.z - area.position.y) * scale
	var x0 := maxi(0, floori(minf(ax, minf(bx, cx))))
	var x1 := mini(width - 1, ceili(maxf(ax, maxf(bx, cx))))
	var z0 := maxi(0, floori(minf(az, minf(bz, cz))))
	var z1 := mini(height - 1, ceili(maxf(az, maxf(bz, cz))))
	# Die Fläche der Kantenfunktion bei Punkt A: daraus kommen die Gewichte der Ecken
	var total := (cx - bx) * (az - bz) - (cz - bz) * (ax - bx)
	if absf(total) < 0.0001 or x0 > x1 or z0 > z1:
		return 0
	var inverse := 1.0 / total
	var positive := total > 0.0
	# Licht von Nordwesten wie auf der Geländekarte
	var lit := clampf(1.0 - (normal.x + normal.z) * 0.4, 0.8, 1.2)
	var color := _map_color(style, maxf(a.y, maxf(b.y, c.y))) * lit
	var red := roundi(clampf(color.r, 0.0, 1.0) * 255.0)
	var green := roundi(clampf(color.g, 0.0, 1.0) * 255.0)
	var blue := roundi(clampf(color.b, 0.0, 1.0) * 255.0)
	var textured := ground.has("lum")
	var lum := PackedFloat32Array()
	var lut := PackedByteArray()
	var lum_width := 1
	var lum_height := 1
	var uv_scale := Vector2.ONE
	var ua := Vector2.ZERO
	var ub := Vector2.ZERO
	var uc := Vector2.ZERO
	if textured:
		lum = ground["lum"]
		lut = ground["lut"]
		lum_width = ground["width"]
		lum_height = ground["height"]
		uv_scale = ground["scale"]
		ua = uvs[index]
		ub = uvs[index + 1]
		uc = uvs[index + 2]
	# Schrittweite der Kantenfunktionen pro Bildpunkt nach rechts
	var step0 := bz - cz
	var step1 := cz - az
	var step2 := az - bz
	var filled := 0
	for py in range(z0, z1 + 1):
		var pz := py + 0.5
		var row := py * width
		var left := x0 + 0.5
		var w0 := (cx - bx) * (pz - bz) - (cz - bz) * (left - bx)
		var w1 := (ax - cx) * (pz - cz) - (az - cz) * (left - cx)
		var w2 := (bx - ax) * (pz - az) - (bz - az) * (left - ax)
		for px in range(x0, x1 + 1):
			var inside := (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) if positive \
				else (w0 <= 0.0 and w1 <= 0.0 and w2 <= 0.0)
			if inside:
				var slot := row + px
				var h := (w0 * a.y + w1 * b.y + w2 * c.y) * inverse
				if h > top[slot]:
					top[slot] = h
					var offset := slot * 3
					if textured:
						var u := (w0 * ua.x + w1 * ub.x + w2 * uc.x) * inverse * uv_scale.x
						var v := (w0 * ua.y + w1 * ub.y + w2 * uc.y) * inverse * uv_scale.y
						u -= floorf(u)
						v -= floorf(v)
						var level := mini(int(lum[mini(int(v * lum_height), lum_height - 1) * lum_width
							+ mini(int(u * lum_width), lum_width - 1)] * 31.0), 31)
						var entry := level * 3
						data[offset] = lut[entry]
						data[offset + 1] = lut[entry + 1]
						data[offset + 2] = lut[entry + 2]
					else:
						data[offset] = red
						data[offset + 1] = green
						data[offset + 2] = blue
					filled += 1
			w0 += step0
			w1 += step1
			w2 += step2
	return filled


## Helligkeit der Bodentextur als kleine Tabelle und die Farbstufen der Karte dafür:
## Asphalt bleibt dunkel, die hellen Straßenmarkierungen werden zu hellen Linien
func _map_texture_data(texture: Texture2D) -> Dictionary:
	var image := texture.get_image()
	if image == null:
		return {}
	image = image.duplicate() as Image
	# Die importierten Texturen liegen komprimiert im Speicher
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGB8)
	var width := mini(image.get_width(), MAP_TEXTURE_SIZE)
	var height := mini(image.get_height(), MAP_TEXTURE_SIZE)
	if width != image.get_width() or height != image.get_height():
		image.resize(width, height, Image.INTERPOLATE_BILINEAR)
	var bytes := image.get_data()
	var lum := PackedFloat32Array()
	lum.resize(width * height)
	for i in lum.size():
		lum[i] = (bytes[i * 3] * 0.3 + bytes[i * 3 + 1] * 0.59 + bytes[i * 3 + 2] * 0.11) / 255.0
	var lut := PackedByteArray()
	lut.resize(32 * 3)
	for level in 32:
		var tone := clampf(MAP_ASPHALT_TONE + pow(level / 31.0, MAP_ASPHALT_CURVE) * MAP_ASPHALT_GAIN,
			0.0, 1.0)
		lut[level * 3] = roundi(tone * 0.92 * 255.0)
		lut[level * 3 + 1] = roundi(tone * 0.98 * 255.0)
		lut[level * 3 + 2] = roundi(minf(tone * 1.12, 1.0) * 255.0)
	return {"lum": lum, "width": width, "height": height, "lut": lut, "scale": Vector2.ONE}


## Farbe einer Fläche: Straßen hell, Bäume dunkel, Dächer nach Höhe (wie die Berge der
## endlosen Welt heller werden)
func _map_color(style: int, peak: float) -> Color:
	match style:
		MapStyle.GROUND:
			return MAP_STREET
		MapStyle.PROP:
			return MAP_PROP
		_:
			return MAP_LOW.lerp(MAP_HIGH, smoothstep(2.0, 24.0, peak))


## Parkplätze: dunkle Fläche, heller Rand und die Trennlinien der Stellplätze
func _draw_lots(image: Image, area: Rect2, scale: float) -> void:
	for lot: Dictionary in Parking.LOTS:
		var top := Parking.top_rect(lot["center"], lot["size"])
		var rect := Rect2i(roundi((top.position.x - area.position.x) * scale),
			roundi((top.position.y - area.position.y) * scale),
			maxi(2, roundi(top.size.x * scale)), maxi(2, roundi(top.size.y * scale)))
		rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if rect.size.x < 2 or rect.size.y < 2:
			continue
		image.fill_rect(rect, MAP_LOT)
		# Rand in vier Streifen (Image.fill_rect kann nur gefüllt zeichnen)
		var edge := maxi(1, roundi(scale * 0.25))
		image.fill_rect(Rect2i(rect.position, Vector2i(rect.size.x, edge)), MAP_PAINT)
		image.fill_rect(Rect2i(rect.position + Vector2i(0, rect.size.y - edge),
			Vector2i(rect.size.x, edge)), MAP_PAINT)
		image.fill_rect(Rect2i(rect.position, Vector2i(edge, rect.size.y)), MAP_PAINT)
		image.fill_rect(Rect2i(rect.position + Vector2i(rect.size.x - edge, 0),
			Vector2i(edge, rect.size.y)), MAP_PAINT)
		# Stellplätze: Reihen mit einer Fahrgasse dazwischen, so wie CityParking sie baut
		var step := maxi(3, roundi(Parking.STALL.x * scale))
		var row_z := top.position.y + 0.5
		while row_z + Parking.STALL.y <= top.end.y - 0.5:
			var z0 := maxi(rect.position.y + edge, roundi((row_z - area.position.y) * scale))
			var z1 := mini(rect.end.y - edge,
				roundi((row_z + Parking.STALL.y - area.position.y) * scale))
			if z1 - z0 > 1:
				var x := rect.position.x + edge
				while x < rect.end.x - edge - 1:
					image.fill_rect(Rect2i(x, z0, 1, z1 - z0), MAP_STALL)
					x += step
				image.fill_rect(Rect2i(rect.position.x + edge, z1 - 1,
					rect.size.x - edge * 2, 1), MAP_STALL)
			row_z += Parking.STALL.y + Parking.AISLE


## Small vertical face right at ground level = kerb
func _is_kerb(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000001:
		return false
	normal = normal.normalized()
	if absf(normal.y) > 0.3:
		return false
	var low := minf(a.y, minf(b.y, c.y))
	var high := maxf(a.y, maxf(b.y, c.y))
	return high <= 0.5 and high - low <= kerb_height and low >= -0.25


## Invisible walls at the four edges of the map
func _build_walls() -> void:
	var low := bounds.position
	var high := bounds.end
	var middle := (bounds.position + bounds.end) * 0.5
	var height := 8.0
	var thickness := 2.0
	var base := low.y + height * 0.5
	var sides := [
		[Vector3(low.x, base, middle.z), Vector3(thickness, height, high.z - low.z)],
		[Vector3(high.x, base, middle.z), Vector3(thickness, height, high.z - low.z)],
		[Vector3(middle.x, base, low.z), Vector3(high.x - low.x, height, thickness)],
		[Vector3(middle.x, base, high.z), Vector3(high.x - low.x, height, thickness)],
	]
	for side: Array in sides:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[1]
		shape.shape = box
		body.add_child(shape)
		# Position before adding: the map is built before it is in the tree in the test
		# tools, and a global transform cannot be set there
		body.position = side[0]
		add_child(body)


## Vom Editor gespeicherte Veränderungen (Position, Rotation, Skalierung, gelöscht)
func _apply_city_layout() -> void:
	if not FileAccess.file_exists(CITY_LAYOUT_PATH):
		return
	var file := FileAccess.open(CITY_LAYOUT_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("city_layout.json ist nicht in Ordnung.")
		return
	for entry in data.get("objects", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var node := _city_object_by_id(str(entry.get("id", "")))
		if node == null:
			continue
		var pos: Array = entry.get("pos", [])
		if pos.size() == 3:
			node.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		var rot: Array = entry.get("rot", [])
		if rot.size() == 3:
			node.rotation = Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])),
				deg_to_rad(float(rot[2])))
		var scale := clampf(float(entry.get("scale", 1.0)), 0.02, 200.0)
		node.scale = Vector3.ONE * scale
		if bool(entry.get("deleted", false)):
			_set_city_deleted(node, true)


## Speichert alle Stadtobjekte (der Editor ruft das nach jeder Änderung auf)
func city_save_layout() -> void:
	if _objects == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://editor"))
	var objects: Array = []
	for child in _objects.get_children():
		var node := child as Node3D
		if node == null or not node.has_meta("city_object"):
			continue
		objects.append({
			"id": str(node.get_meta("city_id", "")),
			"name": str(node.get_meta("city_label", node.name)),
			"pos": [node.position.x, node.position.y, node.position.z],
			"rot": [rad_to_deg(node.rotation.x), rad_to_deg(node.rotation.y), rad_to_deg(node.rotation.z)],
			"scale": node.scale.x,
			"deleted": not node.visible,
		})
	var file := FileAccess.open(CITY_LAYOUT_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Kann die Stadt nicht speichern: " + CITY_LAYOUT_PATH)
		return
	file.store_string(JSON.stringify({"version": 1, "objects": objects}, "  "))
	file.close()


## Löscht ein Stadtobjekt (ausblenden, Kollision aus, in city_layout.json merken)
func city_delete(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	_set_city_deleted(node, true)
	city_save_layout()


func _set_city_deleted(node: Node3D, deleted: bool) -> void:
	node.visible = not deleted
	for child in node.get_children():
		var body := child as StaticBody3D
		if body != null:
			body.collision_layer = 0 if deleted else 1
			body.collision_mask = 0 if deleted else 1


func _city_object_by_id(id: String) -> Node3D:
	if _objects == null or id == "":
		return null
	for child in _objects.get_children():
		var node := child as Node3D
		if node != null and str(node.get_meta("city_id", "")) == id:
			return node
	return null


## Name des Objekts für den Editor (z. B. "Filler_Housing")
func city_label(node: Node3D) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	return str(node.get_meta("city_label", node.name))


## Start transform of the car
func start_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(spawn_heading)), spawn_point)


## Reset key (R): the main scene's CarReset needs roads, the city has none
func _unhandled_input(event: InputEvent) -> void:
	if _car == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_R:
			_car.teleport(start_transform(), true)
			_car.linear_velocity = Vector3.ZERO
			_car.angular_velocity = Vector3.ZERO
