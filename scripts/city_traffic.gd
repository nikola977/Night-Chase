class_name CityTraffic
extends Node3D
## GTA-style AI traffic for the "City Block" map.
##
## The city has no road network like the endless world, so this node carries its own
## hand-measured street grid (H_ROADS / V_ROADS, taken from the road surface of the
## model). The streets cross in a grid: every crossing becomes a graph node, every stretch
## between two crossings an edge. Cars drive kinematically along the edges (right-hand
## side of the road), pick a new edge at each crossing (straight on is favoured) and keep
## a distance to the car in front. They slow down for corners and stop when the player —
## on foot or in a car — is in their way.
##
## The cars are real models from the downloads (assets/models/npc/): the Scion xD, the
## Suzuki SX4, the Pontiac G8 and the whole TrafficRider pack (BMW, VW, Ford, trucks …).
## Each model is measured once, scaled to a sensible length, centred and dropped onto the
## ground, then copied per car (the meshes are shared). No model file at all falls back to
## the box cars that the endless world's Traffic builds.
##
## While the player is on foot, pressing the interact key next to a car steals it.

## Horizontal streets: [z, x_from, x_to] (world metres, measured from the model)
const H_ROADS: Array = [
	[-215.5, -294.0, 8.0], [-179.5, -294.0, 6.0], [-143.5, -294.0, 26.0],
	[-125.5, -384.0, 8.0], [-107.5, -384.0, 80.0], [-71.5, -384.0, 80.0],
	[-35.5, -294.0, 6.0], [-0.5, -294.0, 6.0],
]
## Vertical streets: [x, z_from, z_to]
const V_ROADS: Array = [
	[-287.0, -222.5, 7.5], [-251.0, -222.5, 7.5], [-215.0, -222.5, 7.5], [-143.0, -222.5, 7.5],
	[-107.0, -222.5, 7.5], [-71.0, -222.5, 7.5], [-53.0, -222.5, -28.5], [1.0, -222.5, 7.5],
]

## The TrafficRider pack: one FBX holding every vehicle as its own child node
const FBX_PACK := "res://assets/models/npc/traffic-rider-npc-vehicles/source/trafficrider2.fbx"
const FBX_SCALE := 0.70
## Every car the AI drives: name/brand/year, the model file and (for the FBX) the node,
## the scale to bring it to a sensible size, and how often it appears (weight).
const NPC_MODELS: Array = [
	{"name": "Scion xD", "brand": "Scion", "year": 2009,
		"path": "res://assets/models/npc/2009-scion-xd/source/FINALXd.glb", "node": "", "scale": 1.0, "weight": 3.0},
	{"name": "Suzuki SX4 Sportback", "brand": "Suzuki", "year": 2010,
		"path": "res://assets/models/npc/2010-suzuki-sx4-sportback/source/sx4FINAL.glb", "node": "", "scale": 0.234, "weight": 3.0},
	{"name": "Pontiac G8 GXP", "brand": "Pontiac", "year": 2009,
		"path": "res://assets/models/npc/pontiac-g8-gxp-2009/source/Pontiac_G8_GXP_2009_FM7_Sketchfab.glb", "node": "", "scale": 1.0, "weight": 1.0},
	{"name": "BMW 4 Series", "brand": "BMW", "year": 2015, "path": FBX_PACK, "node": "AI_Bmw4_High", "scale": FBX_SCALE, "weight": 3.0},
	{"name": "Chevrolet Van", "brand": "Chevrolet", "year": 2008, "path": FBX_PACK, "node": "AI_Chevy_High", "scale": FBX_SCALE, "weight": 1.5},
	{"name": "Renault Clio", "brand": "Renault", "year": 2013, "path": FBX_PACK, "node": "AI_Clio_High", "scale": FBX_SCALE, "weight": 3.0},
	{"name": "Chevrolet Cruze", "brand": "Chevrolet", "year": 2012, "path": FBX_PACK, "node": "AI_Cruze_High", "scale": FBX_SCALE, "weight": 3.0},
	{"name": "Ford E-150", "brand": "Ford", "year": 2005, "path": FBX_PACK, "node": "AI_Ford_E150_High", "scale": FBX_SCALE, "weight": 1.5},
	{"name": "Ford Excursion", "brand": "Ford", "year": 2004, "path": FBX_PACK, "node": "AI_Ford_Excursion_High", "scale": FBX_SCALE, "weight": 1.5},
	{"name": "Ford F-150", "brand": "Ford", "year": 2010, "path": FBX_PACK, "node": "AI_Ford_F150_High", "scale": FBX_SCALE, "weight": 1.5},
	{"name": "Ford Transit", "brand": "Ford", "year": 2012, "path": FBX_PACK, "node": "AI_Ford_Transit_High", "scale": FBX_SCALE, "weight": 1.5},
	{"name": "Land Rover Freelander", "brand": "Land Rover", "year": 2007, "path": FBX_PACK, "node": "AI_Freelander_High", "scale": FBX_SCALE, "weight": 2.0},
	{"name": "VW Golf 7", "brand": "Volkswagen", "year": 2014, "path": FBX_PACK, "node": "AI_Golf7_High", "scale": FBX_SCALE, "weight": 3.0},
	{"name": "Kia Cee'd", "brand": "Kia", "year": 2012, "path": FBX_PACK, "node": "AI_Kia_Ceed_High", "scale": FBX_SCALE, "weight": 3.0},
	{"name": "Nissan Maxity", "brand": "Nissan", "year": 2010, "path": FBX_PACK, "node": "AI_Maxity_High", "scale": FBX_SCALE, "weight": 1.0},
	{"name": "Mazda 2", "brand": "Mazda", "year": 2011, "path": FBX_PACK, "node": "AI_Mazda2_High", "scale": FBX_SCALE, "weight": 3.0},
	{"name": "Mazda 3", "brand": "Mazda", "year": 2012, "path": FBX_PACK, "node": "AI_Mazda3_High", "scale": FBX_SCALE, "weight": 3.0},
	{"name": "Mercedes-Benz Sprinter", "brand": "Mercedes-Benz", "year": 2011, "path": FBX_PACK, "node": "AI_Mb_Sprinter_High", "scale": FBX_SCALE, "weight": 1.5},
	{"name": "Mercedes-Benz Unimog", "brand": "Mercedes-Benz", "year": 2000, "path": FBX_PACK, "node": "AI_Mb_Unimog_High", "scale": FBX_SCALE, "weight": 1.0},
	{"name": "Nissan Atlas", "brand": "Nissan", "year": 2010, "path": FBX_PACK, "node": "AI_Nissan_Atlas_High", "scale": FBX_SCALE, "weight": 1.0},
	{"name": "Nissan Atleon", "brand": "Nissan", "year": 2008, "path": FBX_PACK, "node": "AI_Nissan_Atleon_High", "scale": FBX_SCALE, "weight": 1.0},
	{"name": "Scania", "brand": "Scania", "year": 2013, "path": FBX_PACK, "node": "AI_Scania_High", "scale": FBX_SCALE, "weight": 1.0},
	{"name": "Škoda Octavia", "brand": "Škoda", "year": 2013, "path": FBX_PACK, "node": "AI_Skoda_Octavia_High", "scale": FBX_SCALE, "weight": 3.0},
	{"name": "TIR Truck", "brand": "Truck", "year": 2010, "path": FBX_PACK, "node": "AI_Tir_High", "scale": FBX_SCALE, "weight": 1.0},
	{"name": "Box Truck", "brand": "Truck", "year": 2010, "path": FBX_PACK, "node": "AI_Truck1_High", "scale": FBX_SCALE, "weight": 1.0},
	{"name": "VW Amarok", "brand": "Volkswagen", "year": 2012, "path": FBX_PACK, "node": "AI_Vw_Amorak_High", "scale": FBX_SCALE, "weight": 2.0},
]

## How many cars roam the city
const COUNT: int = 16
## Side of the lane (metres right of the street centre) and driving/turn speed (m/s)
const LANE: float = 2.8
const CRUISE_MIN: float = 7.0
const CRUISE_MAX: float = 12.5
const CORNER_SPEED: float = 4.5
const ACCEL: float = 6.0
const BRAKE: float = 10.0
## Cars appear at least this far from the player and are recycled when farther than that
const SPAWN_MIN: float = 55.0
const RECYCLE: float = 260.0
## Distance up to which an AI car gets a solid body
const BODY_DISTANCE: float = 55.0
## How close the player must be on foot to steal a car (below OnFoot.ENTER_DISTANCE)
const STEAL_DISTANCE: float = 3.5
## The city (and the player's car) live on physics layer 1
const OBSTACLE_LAYER: int = 1
## Road ends closer than this belong to the same junction (metres)
const MERGE_DISTANCE: float = 1.6

## One AI car: the visual node, the edge it is on (a -> b, t in 0..1) and its state
class NpcCar:
	var node: Node3D
	var body: AnimatableBody3D
	var a: int = 0
	var b: int = 1
	var t: float = 0.0
	var seg_len: float = 1.0
	var road: int = 0
	var speed: float = 0.0
	var cruise: float = 9.0
	var length: float = 4.5
	var width: float = 1.85
	var height: float = 1.45
	## Distance of the lane centre from the street centre (metres)
	var lane: float = 2.8
	var braking: bool = false

## The player's car (for distance keeping and collisions)
var car: Car
## The on-foot controller (to see where the player stands while walking)
var on_foot: Node

## Street graph: node positions (x, z) and per node the list of [neighbour, road_id, length]
var _nodes: Array[Vector2] = []
## Height of every node (the city is flat, the player's own roads are not)
var _heights: PackedFloat32Array = []
var _adj: Array = []
var _cars: Array[NpcCar] = []
## Prepared car models: {node, length, width, height, weight} (node is a template to copy)
var _templates: Array[Dictionary] = []
## Fallback box builder (the endless world's Traffic) when no model is present
var _helper: Traffic
## Instantiated model files (path -> scene root). The TrafficRider pack holds 20 vehicles in
## one FBX: instantiating it once per car cost half a minute of loading time.
var _packs: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _active: bool = false
var _spawn_timer: float = 0.0
## How many cars may drive on the current graph
var _car_limit: int = COUNT


func build() -> void:
	var started := Time.get_ticks_msec()
	_rng.seed = 20260214
	_car_limit = COUNT
	_build_templates()
	_make_graph()
	for i in COUNT:
		_spawn_one(true)
	_active = true
	print("CityTraffic: %d nodes, %d models, %d cars (%.0f ms)" % [_nodes.size(),
		_templates.size(), _cars.size(), Time.get_ticks_msec() - started])


## Build the graph from the player's own roads (the editor's @road pieces) instead of
## the city grid. Road ends that meet become one junction, so cars follow the road.
func build_on_roads(segments: Array) -> bool:
	_nodes.clear()
	_heights.clear()
	_adj.clear()
	_active = false
	for npc in _cars.duplicate():
		_remove(npc)
	var edges := 0
	for entry: Dictionary in segments:
		var a: Vector3 = entry.get("a", Vector3.ZERO)
		var b: Vector3 = entry.get("b", Vector3.ZERO)
		if a.distance_to(b) < 1.0:
			continue
		var ia := _node_for(a)
		var ib := _node_for(b)
		if ia == ib:
			continue
		var width := float(entry.get("width", 9.0))
		_connect(ia, ib, edges, clampf(width * 0.3, 1.2, 3.2))
		edges += 1
	if edges == 0 or _nodes.size() < 2:
		return false
	if _templates.is_empty():
		_build_templates()
	_rng.seed = 20260214
	_car_limit = clampi(edges, 1, COUNT)
	for i in _car_limit:
		_spawn_one(true)
	# A short road right next to the player: allow the cars to appear anyway
	if _cars.is_empty():
		_spawn_one(false)
	_active = true
	print("RoadTraffic: %d roads, %d junctions, %d cars" % [edges, _nodes.size(), _cars.size()])
	return true


## Node for a point, or the node that is already there when two road ends meet
func _node_for(point: Vector3) -> int:
	var flat := Vector2(point.x, point.z)
	for i in _nodes.size():
		if _nodes[i].distance_to(flat) <= MERGE_DISTANCE:
			return i
	_nodes.append(flat)
	_heights.append(point.y)
	_adj.append([])
	return _nodes.size() - 1


func _exit_tree() -> void:
	if _helper:
		_helper.free()
		_helper = null


# ---------------------------------------------------------------------------
# Car models
# ---------------------------------------------------------------------------

## Load every model once, normalise it (scale, centre, floor) and remember it.
func _build_templates() -> void:
	var seen := {}
	for entry: Dictionary in NPC_MODELS:
		var path: String = entry["path"]
		var node_name: String = entry["node"]
		var key := path + "|" + node_name
		if seen.has(key):
			continue
		seen[key] = true
		var template := _make_template(path, node_name, float(entry["scale"]))
		if template.is_empty():
			push_warning("CityTraffic: model not available: %s %s" % [path, node_name])
			continue
		template["name"] = entry["name"]
		template["brand"] = entry["brand"]
		template["year"] = entry["year"]
		template["weight"] = float(entry["weight"])
		_templates.append(template)
		print("CityTraffic: %s  L=%.2f W=%.2f H=%.2f" % [entry["name"],
			template["length"], template["width"], template["height"]])
	# The copies share their meshes with the packs, so the packs can be released
	for pack: Node in _packs.values():
		pack.free()
	_packs.clear()


## Instantiate a model file once and keep it for every car that uses it
func _pack(path: String) -> Node:
	var inst: Node = _packs.get(path)
	if inst == null:
		var scene := load(path) as PackedScene
		if scene == null:
			return null
		inst = scene.instantiate()
		_packs[path] = inst
	return inst


## One normalised car model: scaled, centred on X/Z, floor at y = 0, nose along +Z.
func _make_template(path: String, node_name: String, scale: float) -> Dictionary:
	var inst := _pack(path)
	if inst == null:
		return {}
	var source: Node3D = null
	if node_name == "":
		source = inst.duplicate() as Node3D
	else:
		var found := inst.get_node_or_null(node_name)
		if found == null or not (found is Node3D):
			var kids := []
			for c in inst.get_children():
				kids.append(str(c.name))
			push_warning("CityTraffic: node '%s' not in %s (has %s)" % [node_name, path, str(kids)])
			return {}
		# Only this vehicle is copied out of the pack (not the whole pack onto every car)
		source = (found as Node3D).duplicate() as Node3D
		source.transform = _relative_transform(found as Node3D, inst)
	var pivot := Node3D.new()
	var scaled := Node3D.new()
	scaled.scale = Vector3(scale, scale, scale)
	pivot.add_child(scaled)
	scaled.add_child(source)
	var box := _aabb(pivot, Transform3D.IDENTITY)
	if box.size.length() < 0.01:
		pivot.free()
		return {}
	scaled.position = Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y,
		-(box.position.z + box.size.z * 0.5))
	# Godot's FBX import turns "use vertex colours as albedo" on, but the meshes have no
	# vertex colours, so every car renders black. Turn it off so the textures show.
	_fix_materials(pivot)
	return {
		"node": pivot,
		"length": maxf(box.size.z, 0.5),
		"width": maxf(box.size.x, 0.5),
		"height": maxf(box.size.y, 0.3),
	}


## Transform of a node relative to one of its ancestors
func _relative_transform(node: Node3D, ancestor: Node) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var walk: Node = node
	while walk != null and walk != ancestor:
		if walk is Node3D:
			transform = (walk as Node3D).transform * transform
		walk = walk.get_parent()
	return transform


func _aabb(node: Node, xf: Transform3D) -> AABB:
	var here := xf
	if node is Node3D:
		here = xf * (node as Node3D).transform
	var box := AABB()
	var first := true
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		var b: AABB = mi.mesh.get_aabb()
		for x in [b.position.x, b.end.x]:
			for y in [b.position.y, b.end.y]:
				for z in [b.position.z, b.end.z]:
					var pt: Vector3 = here * Vector3(x, y, z)
					if first:
						box = AABB(pt, Vector3.ZERO)
						first = false
					else:
						box = box.expand(pt)
	for child in node.get_children():
		var cb := _aabb(child, here)
		if cb.size.length() > 0.0:
			box = cb if first else box.merge(cb)
			first = false
	return box


## Godot's FBX import enables vertex colours as albedo, but the models have none, so
## every car renders black. Give each surface a copy with the flag off so the textures show.
func _fix_materials(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh: Mesh = (n as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s) as StandardMaterial3D
				if mat != null and mat.vertex_color_use_as_albedo:
					var copy := mat.duplicate() as StandardMaterial3D
					copy.vertex_color_use_as_albedo = false
					(n as MeshInstance3D).set_surface_override_material(s, copy)
		for c in n.get_children():
			stack.append(c)


func _pick_template() -> Dictionary:
	if _templates.is_empty():
		return {}
	var total := 0.0
	for t: Dictionary in _templates:
		total += t["weight"]
	var pick := _rng.randf() * total
	for t: Dictionary in _templates:
		pick -= t["weight"]
		if pick <= 0.0:
			return t
	return _templates[_templates.size() - 1]


# ---------------------------------------------------------------------------
# Street graph
# ---------------------------------------------------------------------------

func _make_graph() -> void:
	_nodes.clear()
	_adj.clear()
	for h: Array in H_ROADS:
		for v: Array in V_ROADS:
			if v[0] >= h[1] - 0.5 and v[0] <= h[2] + 0.5 and h[0] >= v[1] - 0.5 and h[0] <= v[2] + 0.5:
				_add_node(Vector2(v[0], h[0]))
	for hi in H_ROADS.size():
		var h: Array = H_ROADS[hi]
		var line: Array[int] = []
		for i in _nodes.size():
			if absf(_nodes[i].y - h[0]) < 0.6:
				line.append(i)
		line.sort_custom(func(x: int, y: int) -> bool: return _nodes[x].x < _nodes[y].x)
		for k in range(line.size() - 1):
			_connect(line[k], line[k + 1], hi)
	for vi in V_ROADS.size():
		var v: Array = V_ROADS[vi]
		var line: Array[int] = []
		for i in _nodes.size():
			if absf(_nodes[i].x - v[0]) < 0.6:
				line.append(i)
		line.sort_custom(func(x: int, y: int) -> bool: return _nodes[x].y < _nodes[y].y)
		for k in range(line.size() - 1):
			_connect(line[k], line[k + 1], 100 + vi)


func _add_node(point: Vector2, height: float = 0.0) -> void:
	for i in _nodes.size():
		if _nodes[i].distance_to(point) < 0.5:
			return
	_nodes.append(point)
	_heights.append(height)
	_adj.append([])


func _connect(a: int, b: int, road: int, lane: float = LANE) -> void:
	if a == b:
		return
	for entry: Array in _adj[a]:
		if entry[0] == b:
			return
	var length := _nodes[a].distance_to(_nodes[b])
	_adj[a].append([b, road, length, lane])
	_adj[b].append([a, road, length, lane])


## Lane offset of an edge (4th element); the city grid uses the default
func _lane_of(edge: Array) -> float:
	return float(edge[3]) if edge.size() > 3 else LANE


func _road_between(a: int, b: int) -> Array:
	for entry: Array in _adj[a]:
		if entry[0] == b:
			return entry
	return []


func _pos(index: int) -> Vector3:
	var height := _heights[index] if index < _heights.size() else 0.0
	return Vector3(_nodes[index].x, height, _nodes[index].y)


# ---------------------------------------------------------------------------
# Spawning
# ---------------------------------------------------------------------------

func _spawn_one(far: bool) -> void:
	var player := car.global_position if car else Vector3.ZERO
	var a := 0
	var b := 0
	var found := false
	for attempt in 40:
		a = _rng.randi_range(0, _nodes.size() - 1)
		if _adj[a].is_empty():
			continue
		var entry: Array = _adj[a][_rng.randi_range(0, _adj[a].size() - 1)]
		b = entry[0]
		if a == b:
			continue
		var at := _pos(a).lerp(_pos(b), _rng.randf())
		if not far or at.distance_to(player) > SPAWN_MIN:
			found = true
			break
	if not found:
		return
	var npc := NpcCar.new()
	_setup_visual(npc)
	npc.a = a
	npc.b = b
	npc.t = _rng.randf()
	var edge := _road_between(a, b)
	npc.road = edge[1] if not edge.is_empty() else 0
	npc.lane = _lane_of(edge)
	npc.seg_len = maxf(_pos(a).distance_to(_pos(b)), 0.1)
	npc.cruise = _rng.randf_range(CRUISE_MIN, CRUISE_MAX)
	npc.speed = npc.cruise * 0.6
	add_child(npc.node)
	npc.body = AnimatableBody3D.new()
	npc.body.collision_layer = OBSTACLE_LAYER
	npc.body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(npc.width, npc.height, npc.length)
	shape.shape = box
	shape.position = Vector3(0.0, npc.height * 0.5, 0.0)
	npc.body.add_child(shape)
	npc.node.add_child(npc.body)
	_cars.append(npc)
	_place(npc)
	npc.node.reset_physics_interpolation()


## Build the visual for one car from a random model (or the box fallback)
func _setup_visual(npc: NpcCar) -> void:
	var template := _pick_template()
	npc.node = Node3D.new()
	if template.is_empty():
		_build_box_car(npc)
		return
	npc.length = template["length"]
	npc.width = template["width"]
	npc.height = template["height"]
	var visual: Node = (template["node"] as Node).duplicate()
	npc.node.add_child(visual)


## Fallback: the box cars the endless world's Traffic builds
func _build_box_car(npc: NpcCar) -> void:
	if _helper == null:
		_helper = Traffic.new()
	var types: Array = ["s3", "accord", "id_buzz", "aztek", "lc500"]
	var type: String = types[_rng.randi_range(0, types.size() - 1)]
	var info: Dictionary = Traffic.TYPES[type]
	npc.length = info["length"]
	npc.width = info["width"]
	npc.height = info["height"]
	var mesh := _helper.call("_vehicle_mesh", type) as ArrayMesh
	var surfaces: Dictionary = _helper.get("_surface_index")
	var paint_index: int = (surfaces[type] as Dictionary)["paint"]
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.set_surface_override_material(paint_index, _helper.call("_paint_material",
		Color.from_hsv(_rng.randf(), 0.4, 0.8)))
	npc.node.add_child(visual)


# ---------------------------------------------------------------------------
# Driving
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _active or car == null or car.freeze:
		return
	for npc in _cars:
		var target := npc.cruise
		if npc.t > 0.7 and _corner_ahead(npc):
			target = minf(target, CORNER_SPEED)
		var gap := _gap_ahead(npc)
		if gap < 40.0:
			target = minf(target, maxf(0.0, (gap - 2.5) * 0.55))
		# Walls, posts, parked cars, the player: stop instead of driving through them
		var obstacle := _obstacle_ahead(npc)
		if obstacle < 14.0:
			target = minf(target, maxf(0.0, (obstacle - 1.5) * 0.9))
		npc.braking = target < npc.speed - 0.5
		npc.speed = move_toward(npc.speed, target, (ACCEL if target > npc.speed else BRAKE) * delta)
		_advance(npc, delta)
		_place(npc)
		_update_body(npc)


## Metres from the front bumper to the first solid thing in the lane. A flat surface (road,
## roof, the editor's road slabs) does not count, so only walls, posts and vehicles stop a car.
func _obstacle_ahead(npc: NpcCar) -> float:
	if npc.body == null:
		return 1e9
	var forward := npc.node.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return 1e9
	forward = forward.normalized()
	var from: Vector3 = npc.node.global_position + Vector3.UP * maxf(0.5, npc.height * 0.5) \
		+ forward * npc.length * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * 14.0, OBSTACLE_LAYER)
	query.collide_with_areas = false
	query.exclude = [npc.body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 1e9
	if absf((hit["normal"] as Vector3).y) > 0.7:
		return 1e9
	return from.distance_to(hit["position"])


func _advance(npc: NpcCar, delta: float) -> void:
	npc.t += npc.speed * delta / maxf(npc.seg_len, 0.1)
	var guard := 0
	while npc.t >= 1.0 and guard < 4:
		guard += 1
		npc.t -= 1.0
		var prev := npc.a
		npc.a = npc.b
		npc.b = _choose_next(npc.a, prev, npc.road)
		var edge := _road_between(npc.a, npc.b)
		if edge.is_empty():
			npc.t = 0.0
			return
		npc.road = edge[1]
		npc.lane = _lane_of(edge)
		npc.seg_len = maxf(edge[2], 0.1)


func _choose_next(a: int, prev: int, road: int) -> int:
	var choices: Array[int] = []
	var straight := -1
	for entry: Array in _adj[a]:
		if entry[0] == prev:
			continue
		choices.append(entry[0])
		if entry[1] == road:
			straight = entry[0]
	if choices.is_empty():
		return prev
	if straight >= 0 and _rng.randf() < 0.72:
		return straight
	return choices[_rng.randi_range(0, choices.size() - 1)]


func _corner_ahead(npc: NpcCar) -> bool:
	if _adj[npc.b].is_empty():
		return false
	var in_dir := (_nodes[npc.b] - _nodes[npc.a]).normalized()
	for entry: Array in _adj[npc.b]:
		if entry[0] == npc.a:
			continue
		var out_dir := (_nodes[entry[0]] - _nodes[npc.b]).normalized()
		if absf(in_dir.dot(out_dir)) < 0.97:
			return true
	return false


## Distance to the nearest obstacle ahead in the lane (other cars and the player)
func _gap_ahead(npc: NpcCar) -> float:
	var flat := _nodes[npc.b] - _nodes[npc.a]
	if flat.length() < 0.001:
		return 1e9
	flat = flat.normalized()
	var dir := Vector3(flat.x, 0.0, flat.y)
	var right := dir.cross(Vector3.UP)
	var here := npc.node.global_position
	var best := 1e9
	for other in _cars:
		if other == npc:
			continue
		best = minf(best, _ahead_gap(other.node.global_position, here, dir, right,
			npc.length, other.length, 3.2, 45.0))
	if car:
		best = minf(best, _ahead_gap(car.global_position, here, dir, right, npc.length, 2.5, 3.6, 45.0))
	if on_foot != null and on_foot.get("is_walking") == true:
		var walker: Node3D = on_foot.get("_player")
		if walker:
			best = minf(best, _ahead_gap(walker.global_position, here, dir, right, npc.length, 0.9, 3.6, 30.0))
	return best


func _ahead_gap(target: Vector3, here: Vector3, dir: Vector3, right: Vector3,
		own_len: float, other_len: float, max_side: float, reach: float) -> float:
	var rel := target - here
	var ahead := rel.dot(dir)
	if ahead <= 0.0 or ahead > reach or absf(rel.dot(right)) > max_side:
		return 1e9
	return ahead - own_len * 0.5 - other_len * 0.5


func _place(npc: NpcCar) -> void:
	var a := _pos(npc.a)
	var b := _pos(npc.b)
	var dir := b - a
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.001:
		return
	flat = flat.normalized()
	var right := flat.cross(Vector3.UP)
	var pos := a.lerp(b, clampf(npc.t, 0.0, 1.0)) + right * npc.lane
	npc.node.global_transform = Transform3D(Basis.looking_at(-flat, Vector3.UP), pos)


func _update_body(npc: NpcCar) -> void:
	var distance := npc.node.global_position.distance_to(car.global_position)
	npc.body.collision_layer = OBSTACLE_LAYER if distance < BODY_DISTANCE else 0


# ---------------------------------------------------------------------------
# Player interaction
# ---------------------------------------------------------------------------

## Nearest AI car within reach, or null (used for the "[F] Steal" prompt).
func steal_target(player_position: Vector3) -> Node3D:
	var best := _nearest_car(player_position)
	return best.node if best != null else null


func _nearest_car(player_position: Vector3) -> NpcCar:
	var best: NpcCar = null
	var best_distance := STEAL_DISTANCE
	for npc in _cars:
		var distance := npc.node.global_position.distance_to(player_position)
		if distance < best_distance:
			best_distance = distance
			best = npc
	return best


## If the player on foot stands next to an AI car, "steal" it: the AI car disappears and
## the player's own car is placed where it stood, so pressing the key again gets in.
func try_steal(player_position: Vector3) -> bool:
	var best := _nearest_car(player_position)
	if best == null:
		return false
	var stolen := Transform3D(best.node.global_basis, best.node.global_position)
	_remove(best)
	if car:
		car.teleport(stolen, true)
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
	return true


func _remove(npc: NpcCar) -> void:
	npc.node.queue_free()
	_cars.erase(npc)


func _process(delta: float) -> void:
	if not _active or car == null:
		return
	var player := Vector2(car.global_position.x, car.global_position.z)
	for npc in _cars.duplicate():
		if _nodes[npc.a].distance_to(player) > RECYCLE:
			_remove(npc)
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and _cars.size() < _car_limit:
		_spawn_timer = 0.5
		_spawn_one(true)


## The list of AI car models (name, brand, year) for the garage/menu
static func catalog() -> Array:
	var out: Array = []
	for entry: Dictionary in NPC_MODELS:
		out.append({"name": entry["name"], "brand": entry["brand"], "year": entry["year"]})
	return out


func car_count() -> int:
	return _cars.size()