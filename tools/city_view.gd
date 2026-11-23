extends Node3D
## Temporary: draws the planned traffic road lines over the city, top-down, for verification.

const H_ROADS: Array = [
	[-215.5, -294.0, 8.0], [-179.5, -294.0, 6.0], [-143.5, -294.0, 26.0],
	[-125.5, -384.0, 8.0], [-107.5, -384.0, 80.0], [-71.5, -384.0, 80.0],
	[-35.5, -294.0, 6.0], [-0.5, -294.0, 6.0],
]
const V_ROADS: Array = [
	[-287.0, -222.5, 7.5], [-251.0, -222.5, 7.5], [-215.0, -222.5, 7.5], [-143.0, -222.5, 7.5],
	[-107.0, -222.5, 7.5], [-71.0, -222.5, 7.5], [-53.0, -222.5, -28.5], [1.0, -222.5, 7.5],
]

func _ready() -> void:
	var path := "res://assets/tracks/city/city.fbx"
	var src: Node = null
	for attempt in 300:
		var s := load(path) as PackedScene
		if s == null:
			OS.delay_msec(20)
			continue
		var inst := s.instantiate()
		if _has_road(inst):
			src = inst
			break
		inst.free()
		OS.delay_msec(20)
	if src == null:
		return
	add_child(src)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.12, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.3
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -30, 0)
	add_child(sun)
	_draw_network()
	var center := Vector3((-386.0 + 172.0) * 0.5, 0.0, (-224.5 + 9.5) * 0.5)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 330.0
	cam.near = 1.0
	cam.far = 2000.0
	cam.position = Vector3(center.x, 300.0, center.z)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.current = true
	add_child(cam)

func _draw_network() -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1, 0.1, 0.1)
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.1, 1, 0.3)
	green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for h: Array in H_ROADS:
		_bar(Vector3(h[1], 1.2, h[0]), Vector3(h[2], 1.2, h[0]), red)
	for v: Array in V_ROADS:
		_bar(Vector3(v[0], 1.2, v[1]), Vector3(v[0], 1.2, v[2]), red)
	for h: Array in H_ROADS:
		for v: Array in V_ROADS:
			if v[0] >= h[1] - 0.01 and v[0] <= h[2] + 0.01 and h[0] >= v[1] - 0.01 and h[0] <= v[2] + 0.01:
				var m := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(7, 0.3, 7)
				m.mesh = bm
				m.material_override = green
				m.position = Vector3(v[0], 1.4, h[0])
				add_child(m)

func _bar(a: Vector3, b: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(maxf(0.9, absf(b.x - a.x)), 0.2, maxf(0.9, absf(b.z - a.z)))
	m.mesh = bm
	m.material_override = mat
	m.position = (a + b) * 0.5
	add_child(m)

func _has_road(n: Node) -> bool:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var std := mesh.surface_get_material(s) as StandardMaterial3D
			if std != null and std.albedo_texture != null \
					and std.albedo_texture.resource_path.contains("Roads_Grounds"):
				return true
	for ch in n.get_children():
		if _has_road(ch):
			return true
	return false