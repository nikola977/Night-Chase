extends Node3D
## Temporary diagnostic: 4 m street / building occupancy grid of the city.

const X0 := -386.0
const Z0 := -224.5
const C := 4.0

var _road := {}
var _pav := {}
var _blocked := {}
var _bounds := AABB()
var _first := true

func _ready() -> void:
	var path := "res://assets/tracks/city/city.fbx"
	for attempt in 300:
		var s := load(path) as PackedScene
		if s == null:
			OS.delay_msec(20)
			continue
		var inst := s.instantiate()
		_road.clear(); _pav.clear(); _blocked.clear(); _first = true
		_walk(inst, Transform3D.IDENTITY)
		if _road.size() > 0:
			_write_result()
			return
		inst.free()
		OS.delay_msec(20)
	_write("FAILED after 300 attempts")

func _walk(node: Node, xf: Transform3D) -> void:
	var here := xf
	if node is Node3D:
		here = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for sm in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(sm)
			if arr.size() == 0:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var count := idx.size() if idx.size() > 0 else verts.size()
			var road_surface := _is_road(mesh.surface_get_material(sm))
			for t in range(0, count, 3):
				var ia := idx[t] if idx.size() > 0 else t
				var ib := idx[t + 1] if idx.size() > 0 else t + 1
				var ic := idx[t + 2] if idx.size() > 0 else t + 2
				var a: Vector3 = here * verts[ia]
				var b: Vector3 = here * verts[ib]
				var c: Vector3 = here * verts[ic]
				var box := AABB(a, Vector3.ZERO).expand(b).expand(c)
				if _first:
					_bounds = box
					_first = false
				else:
					_bounds = _bounds.merge(box)
				var lo := minf(a.y, minf(b.y, c.y))
				var hi := maxf(a.y, maxf(b.y, c.y))
				var n := (b - a).cross(c - a)
				var flat_face := n.length_squared() > 1e-9 and absf(n.normalized().y) >= 0.85
				var gx0 := int(floor((minf(a.x, minf(b.x, c.x)) - X0) / C))
				var gx1 := int(floor((maxf(a.x, maxf(b.x, c.x)) - X0) / C))
				var gz0 := int(floor((minf(a.z, minf(b.z, c.z)) - Z0) / C))
				var gz1 := int(floor((maxf(a.z, maxf(b.z, c.z)) - Z0) / C))
				if gx1 - gx0 > 60 or gz1 - gz0 > 60:
					continue
				if hi > 0.5:
					for gz in range(gz0, gz1 + 1):
						for gx in range(gx0, gx1 + 1):
							_blocked[gz * 1000 + gx] = true
				if road_surface and flat_face and lo <= 0.5:
					for corner: Vector3 in [a, b, c]:
						var cx := int(floor((corner.x - X0) / C))
						var cz := int(floor((corner.z - Z0) / C))
						var kk := cz * 1000 + cx
						if lo <= 0.10:
							_road[kk] = true
						else:
							_pav[kk] = true
	for ch in node.get_children():
		_walk(ch, here)

func _is_road(mat: Material) -> bool:
	if mat == null:
		return false
	if mat.resource_name == "RoadsGround":
		return true
	var std := mat as StandardMaterial3D
	return std != null and std.albedo_texture != null \
		and std.albedo_texture.resource_path.contains("Roads_Grounds")

func _write_result() -> void:
	var out := "bounds=%s\n" % str(_bounds)
	out += "road_cells=%d pav_cells=%d blocked=%d\n" % [_road.size(), _pav.size(), _blocked.size()]
	out += "legend: '#'=road(y<=10cm) 'x'=pavement 'B'=building/prop ' '=nothing\n"
	for zz in range(59):
		var line := ""
		for xx in range(140):
			var kk := zz * 1000 + xx
			if _blocked.has(kk):
				line += "B"
			elif _road.has(kk):
				line += "#"
			elif _pav.has(kk):
				line += "x"
			else:
				line += " "
		out += "R%02d|%s\n" % [zz, line]
	out += "x: col0=-386 +4m; z: row0=-224.5 +4m\n"
	_write(out)

func _write(text: String) -> void:
	var f := FileAccess.open("res://screenshots/city_grid.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()