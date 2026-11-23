extends SceneTree
## Diagnostic for the city map: prints the material settings, looks for ground
## surfaces that overlap each other (they flicker when they lie at the same
## height) and saves a top-down picture of the whole island.
##
##   Godot_v4.7.2-stable_win64.exe --path . -s res://tools/city_probe.gd

const CITY := "res://assets/tracks/city/city.fbx"
const CELL := 1.0

var _main: Node
var _frames := 0
var _saved := false
var _camera: Camera3D
## Height of every horizontal face, in centimetres (before any flattening)
var _heights := {}
## 4 m cells with something standing on them (walls, roofs, props)
var _blocked := {}
const FREE_CELL := 4.0


func _initialize() -> void:
	_dump_materials()
	var mode = load("res://scripts/city_mode.gd")
	mode.enabled = true
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _saved:
		return false
	if _frames < 10 or not _main.world_is_ready:
		return false
	if _camera == null:
		_setup_camera()
		return false
	if _frames % 10 != 0:
		return false
	_save_overview()
	return false


func _setup_camera() -> void:
	var city := _main.get_node_or_null("CityMap")
	if city == null:
		print("PROBE: no CityMap node")
		return
	var hud := _main.get_node_or_null("HUD")
	if hud:
		hud.visible = false
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var box: AABB = city.bounds
	var center := box.get_center()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = maxf(box.size.x, box.size.z) * 1.02
	_camera.near = 1.0
	_camera.far = 2000.0
	_main.add_child(_camera)
	_camera.global_position = Vector3(center.x, center.y + 600.0, center.z)
	_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_camera.make_current()
	print("PROBE: overview camera at %s, size %.0f, bounds %s" % [_camera.global_position, _camera.size, box])


func _save_overview() -> void:
	_saved = true
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		print("PROBE: no image")
		quit()
		return
	image.save_png("res://screenshots/city_overview.png")
	print("PROBE: overview saved")
	quit()


## ------------------------------------------------------------------ materials


func _dump_materials() -> void:
	var scene := load(CITY) as PackedScene
	if scene == null:
		print("PROBE: cannot load %s" % CITY)
		return
	var source := scene.instantiate()
	var stats := {}
	var keys: Array[String] = []
	var grid := {}
	print("PROBE: walking %s" % CITY)
	_walk(source, Transform3D.IDENTITY, stats, keys, grid)
	print("PROBE: walked, %d materials, %d ground cells" % [keys.size(), grid.size()])
	source.free()

	print("\n==== MATERIALS ====")
	for i in keys.size():
		var key := keys[i]
		var s: Dictionary = stats[key]
		var mat: Material = s["material"]
		var line := "%2d %-28s tris %5d  area %9.1f m2  ground %8.1f m2" % [i, key, s["tris"], s["area"], s["ground"]]
		if mat is StandardMaterial3D:
			var std := mat as StandardMaterial3D
			var tex := std.albedo_texture
			line += "\n     albedo=%s color=%s rough=%.2f metal=%.2f cull=%d transp=%d vcol=%s filter=%d normal=%s" % [
				tex.resource_path.get_file() if tex != null else "<none>", std.albedo_color, std.roughness,
				std.metallic, std.cull_mode, std.transparency, str(std.vertex_color_use_as_albedo),
				std.texture_filter, str(std.normal_enabled)]
		elif mat is ShaderMaterial:
			line += "\n     shader=%s" % (mat as ShaderMaterial).shader.resource_path
		else:
			line += "\n     %s" % str(mat)
		print(line)

	print("\n==== GROUND HEIGHTS (cm: vertex count) ====")
	var heights: Array = _heights.keys()
	heights.sort()
	for h in heights:
		print("  %3d cm : %5d" % [h, _heights[h]])

	print("\n==== FREE SPACE (4 m cells without buildings, at least 24 m wide) ====")
	_free_space()

	print("\n==== OVERLAPPING GROUND (same 1 m cell, several materials) ====")
	var pairs := {}
	for cell in grid:
		var mask: int = grid[cell]
		if mask == 0 or (mask & (mask - 1)) == 0:
			continue
		for i in keys.size():
			if mask & (1 << i) == 0:
				continue
			for j in range(i + 1, keys.size()):
				if mask & (1 << j) == 0:
					continue
				var pair := "%s  +  %s" % [keys[i], keys[j]]
				pairs[pair] = float(pairs.get(pair, 0.0)) + CELL * CELL
	var sorted_pairs: Array = pairs.keys()
	sorted_pairs.sort_custom(func(a, b): return pairs[a] > pairs[b])
	for k in mini(sorted_pairs.size(), 25):
		print("%9.0f m2  %s" % [pairs[sorted_pairs[k]], sorted_pairs[k]])
	if sorted_pairs.is_empty():
		print("none")


## Cells that are free of geometry between 0.5 m and 8 m: empty ground to build on
func _free_space() -> void:
	var cells := {}
	var min_x := 0
	var max_x := 0
	var min_z := 0
	var max_z := 0
	var first := true
	for cell in _blocked:
		var c: Vector2i = cell
		if first:
			min_x = c.x
			max_x = c.x
			min_z = c.y
			max_z = c.y
			first = false
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.y)
		max_z = maxi(max_z, c.y)
	# Blocked cells came only from geometry above ground; every other cell inside
	# the map that has ground is free
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			if not _blocked.has(Vector2i(x, z)):
				cells[Vector2i(x, z)] = true
	print("  free cells: %d of %d" % [cells.size(), (max_x - min_x + 1) * (max_z - min_z + 1)])
	# Largest free rectangle per row height (classic histogram method), keep the biggest ones
	var best: Array = []
	var heights := {}
	for z in range(min_z, max_z + 1):
		for x in range(min_x, max_x + 1):
			heights[x] = int(heights.get(x, 0)) + 1 if cells.has(Vector2i(x, z)) else 0
		var stack: Array = []
		for x in range(min_x, max_x + 2):
			var h := int(heights.get(x, 0))
			while not stack.is_empty() and int(heights.get(stack[-1], 0)) > h:
				var top: int = stack.pop_back()
				var left: int = stack[-1] if not stack.is_empty() else min_x - 1
				var width := x - left - 1
				var height := int(heights.get(top, 0))
				if width >= 4 and height >= 4:
					best.append({"area": width * height, "x": left + 1, "z": z - height + 1,
						"w": width, "h": height})
			stack.append(x)
	best.sort_custom(func(a, b): return a["area"] > b["area"])
	var shown := 0
	var used: Array = []
	for b in best:
		var rect := Rect2i(b["x"], b["z"], b["w"], b["h"])
		var clash := false
		for other in used:
			if rect.intersects(other):
				clash = true
				break
		if clash:
			continue
		used.append(rect)
		print("  %3d x %3d m  at world x %7.1f .. %7.1f  z %7.1f .. %7.1f" % [rect.size.x, rect.size.y,
			rect.position.x * FREE_CELL, rect.end.x * FREE_CELL, rect.position.y * FREE_CELL, rect.end.y * FREE_CELL])
		shown += 1
		if shown >= 12:
			break


func _walk(node: Node, xform: Transform3D, stats: Dictionary, keys: Array[String], grid: Dictionary) -> void:
	var here := xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		var mesh: Mesh = instance.mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface)
				var key: String = material.resource_name if material != null else "<no material>"
				if key == "":
					key = "<unnamed %d>" % keys.size()
				if not stats.has(key):
					stats[key] = {"material": material, "tris": 0, "area": 0.0, "ground": 0.0}
					keys.append(key)
				var s: Dictionary = stats[key]
				var faces := mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array
				var indices: PackedInt32Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
				var count := indices.size() if indices.size() > 0 else faces.size()
				for t in range(0, count, 3):
					var ia := indices[t] if indices.size() > 0 else t
					var ib := indices[t + 1] if indices.size() > 0 else t + 1
					var ic := indices[t + 2] if indices.size() > 0 else t + 2
					var a := here * faces[ia]
					var b := here * faces[ib]
					var c := here * faces[ic]
					var area := (b - a).cross(c - a).length() * 0.5
					s["tris"] = int(s["tris"]) + 1
					s["area"] = float(s["area"]) + area
					var normal := (b - a).cross(c - a)
					if normal.length_squared() < 0.000001:
						continue
					var low := minf(a.y, minf(b.y, c.y))
					var high := maxf(a.y, maxf(b.y, c.y))
					if high > 0.5:
						_mark_blocked(a, b, c)
					normal = normal.normalized()
					if absf(normal.y) >= 0.85 and low > -0.6 and high < 0.7:
						for corner in [a, b, c]:
							var cm := roundi(corner.y * 100.0)
							_heights[cm] = int(_heights.get(cm, 0)) + 1
					if absf(normal.y) < 0.85 or high > 0.6 or low < -0.6:
						continue
					s["ground"] = float(s["ground"]) + area
					_mark(grid, key, keys, a, b, c)
	for child in node.get_children():
		_walk(child, here, stats, keys, grid)


## Marks the 4 m cells a solid triangle stands on (walls, roofs, props)
func _mark_blocked(a: Vector3, b: Vector3, c: Vector3) -> void:
	var low := minf(a.y, minf(b.y, c.y))
	var high := maxf(a.y, maxf(b.y, c.y))
	if high < 0.5 or low > 8.0:
		return
	var min_x := floori(minf(a.x, minf(b.x, c.x)) / FREE_CELL)
	var max_x := floori(maxf(a.x, maxf(b.x, c.x)) / FREE_CELL)
	var min_z := floori(minf(a.z, minf(b.z, c.z)) / FREE_CELL)
	var max_z := floori(maxf(a.z, maxf(b.z, c.z)) / FREE_CELL)
	if max_x - min_x > 40 or max_z - min_z > 40:
		return
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			_blocked[Vector2i(x, z)] = true


## Rasterizes the footprint of a ground triangle into 1 m cells (bitmask per cell)
func _mark(grid: Dictionary, key: String, keys: Array[String], a: Vector3, b: Vector3, c: Vector3) -> void:
	var index := keys.find(key)
	if index < 0 or index > 62:
		return
	var bit := 1 << index
	var min_x := floori(minf(a.x, minf(b.x, c.x)) / CELL)
	var max_x := floori(maxf(a.x, maxf(b.x, c.x)) / CELL)
	var min_z := floori(minf(a.z, minf(b.z, c.z)) / CELL)
	var max_z := floori(maxf(a.z, maxf(b.z, c.z)) / CELL)
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var cell := Vector2i(x, z)
			grid[cell] = int(grid.get(cell, 0)) | bit
