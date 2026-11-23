class_name CityParking
extends RefCounted
## Parking lots on the empty ground of the city map, where there are no buildings.
##
## The lots are built into the merged city surfaces (CityMap), so they get the same
## physics as the map. The slab lies 8 cm above the ground with a 1.2 m slope around
## it, so the car drives on and off without a bump. White lines mark the stalls.

## Asphalt from the project (the endless world's roads use the same texture)
const ASPHALT_TEXTURE := "res://assets/textures/asphalt_02/asphalt_02_diff_1k.jpg"
## Height of the slab above the ground (m). Two surfaces 2 cm apart flicker on the flat
## ground of the map as soon as you look at them from further away; 8 cm is far enough
## apart for the depth buffer, and the slope below keeps the car from bumping.
const SURFACE := 0.08
## Width of the slope around the slab (m)
const SLOPE := 1.2
## Height of the painted lines above the slab; 4 mm flickered against the asphalt
const PAINT := 0.03
## Parking stall: width, depth (m) and line width (m)
const STALL := Vector2(2.7, 5.0)
const LINE := 0.12
## Driving lane between two rows of stalls (m)
const AISLE := 6.0
## One metre of texture per this many metres (asphalt tiles every 8 m)
const TILE := 8.0

## Where the lots go: centre (x, z) and size (width x, depth), all in map metres.
## The spots come from the free-space scan in tools/city_probe.gd: the large empty
## fields west and east of the blocks and the empty block in the middle.
const LOTS: Array[Dictionary] = [
	{"center": Vector2(-334.0, -164.0), "size": Vector2(92.0, 80.0)},
	{"center": Vector2(112.0, -58.0), "size": Vector2(88.0, 84.0)},
	{"center": Vector2(-88.0, -98.0), "size": Vector2(46.0, 26.0)},
]


## Adds one mesh per lot to `parent` (called by CityMap before the collision is built)
static func build(parent: Node3D) -> void:
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_texture = load(ASPHALT_TEXTURE)
	asphalt.roughness = 0.85
	asphalt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.86, 0.86, 0.84)
	paint.roughness = 0.55
	for i in LOTS.size():
		var lot: Dictionary = LOTS[i]
		var slab := MeshInstance3D.new()
		slab.name = "Parking%d" % (i + 1)
		slab.mesh = _slab_mesh(lot["center"], lot["size"], asphalt)
		# The slab keeps its height in the physics too, so the car drives up the slope
		slab.set_meta("keep_physics_height", true)
		parent.add_child(slab)
		# The paint lies 3 cm above the asphalt (closer flickers) but is no obstacle
		var lines := MeshInstance3D.new()
		lines.name = "Parking%dLines" % (i + 1)
		lines.mesh = _paint_mesh(lot["center"], lot["size"], paint)
		lines.set_meta("skip_physics", true)
		parent.add_child(lines)


## Top of the slab (inside the slope) in map metres. The slab, the paint and the map
## picture all measure from this rectangle, so the slope only has to be right once.
static func top_rect(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - size * 0.5 + Vector2(SLOPE, SLOPE), size - Vector2(SLOPE, SLOPE) * 2.0)


static func _slab_mesh(center: Vector2, size: Vector2, asphalt: Material) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var low_x := center.x - half.x
	var high_x := center.x + half.x
	var low_z := center.y - half.y
	var high_z := center.y + half.y
	# Slab with a slope all around, so the wheels can drive on without a bump
	var top := top_rect(center, size)
	var top_x0 := top.position.x
	var top_x1 := top.end.x
	var top_z0 := top.position.y
	var top_z1 := top.end.y
	_quad(tool, Vector3(top_x0, SURFACE, top_z0), Vector3(top_x1, SURFACE, top_z0),
		Vector3(top_x1, SURFACE, top_z1), Vector3(top_x0, SURFACE, top_z1))
	_quad(tool, Vector3(low_x, 0.0, low_z), Vector3(high_x, 0.0, low_z),
		Vector3(top_x1, SURFACE, top_z0), Vector3(top_x0, SURFACE, top_z0))
	_quad(tool, Vector3(high_x, 0.0, low_z), Vector3(high_x, 0.0, high_z),
		Vector3(top_x1, SURFACE, top_z1), Vector3(top_x1, SURFACE, top_z0))
	_quad(tool, Vector3(high_x, 0.0, high_z), Vector3(low_x, 0.0, high_z),
		Vector3(top_x0, SURFACE, top_z1), Vector3(top_x1, SURFACE, top_z1))
	_quad(tool, Vector3(low_x, 0.0, high_z), Vector3(low_x, 0.0, low_z),
		Vector3(top_x0, SURFACE, top_z0), Vector3(top_x0, SURFACE, top_z1))
	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, asphalt)
	return mesh


static func _paint_mesh(center: Vector2, size: Vector2, paint: Material) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := top_rect(center, size)
	# Rows of stalls with an aisle between them, as many as fit into the lot
	var row_z := top.position.y + 0.5
	while row_z + STALL.y <= top.end.y - 0.5:
		_stalls(tool, top.position.x + 0.5, top.end.x - 0.5, row_z)
		row_z += STALL.y + AISLE
	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, paint)
	return mesh


## A row of stalls from `low_x` to `high_x` at `start_z`, all lines running towards +Z
static func _stalls(tool: SurfaceTool, low_x: float, high_x: float, start_z: float) -> void:
	var usable := high_x - low_x - 1.0
	var count := int(usable / STALL.x)
	if count < 2:
		return
	var width := count * STALL.x
	var first := (low_x + high_x) * 0.5 - width * 0.5
	var y := SURFACE + PAINT
	for i in count + 1:
		var x := first + i * STALL.x
		_paint(tool, x, start_z, x + LINE, start_z + STALL.y, y)
	# Line at the end of the row
	var end_z := start_z + STALL.y
	_paint(tool, first, end_z, first + width, end_z + LINE, y)


## A flat paint stripe on the slab
static func _paint(tool: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	var a := Vector3(minf(x0, x1), y, minf(z0, z1))
	var b := Vector3(maxf(x0, x1), y, minf(z0, z1))
	var c := Vector3(maxf(x0, x1), y, maxf(z0, z1))
	var d := Vector3(minf(x0, x1), y, maxf(z0, z1))
	_quad(tool, a, b, c, d)


## A quad facing up (the material has no back faces to show, so the winding matters)
static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	tool.set_normal(Vector3.UP)
	for point in [a, b, c, a, c, d]:
		tool.set_uv(Vector2(point.x, point.z) / TILE)
		tool.add_vertex(point)
