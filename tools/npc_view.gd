extends Node3D
## Temporary: shows one FBX vehicle twice (original vs. vertex colours off) to find why it is black.

func _ready() -> void:
	var scene := load("res://assets/models/npc/traffic-rider-npc-vehicles/source/trafficrider2.fbx") as PackedScene
	var inst: Node = scene.instantiate()
	var car: Node3D = inst.get_node("AI_Golf7_High")
	car.transform = inst.transform * car.transform
	inst.remove_child(car)
	inst.free()
	# Report vertex colours and texture info
	var mi := car as MeshInstance3D
	var arr := mi.mesh.surface_get_arrays(0)
	var has_color := arr[Mesh.ARRAY_COLOR] != null and (arr[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0
	var first_color := "none"
	if has_color:
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		first_color = str(cols[0])
	var std := mi.mesh.surface_get_material(0) as StandardMaterial3D
	var tex_size := Vector2i.ZERO
	if std != null and std.albedo_texture != null:
		tex_size = std.albedo_texture.get_size()
	print("VCOL present=%s first=%s  tex_size=%s  vcol_flag=%s" % [str(has_color), first_color,
		str(tex_size), str(std.vertex_color_use_as_albedo)])
	set_meta("done", true)
	_add(car, Vector3(-3, 0, 0), false)
	var car2 := car.duplicate() as Node3D
	_add(car2, Vector3(3, 0, 0), true)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.4, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.5, 8)
	cam.rotation_degrees = Vector3(-12, 0, 0)
	cam.fov = 45
	cam.current = true
	add_child(cam)

func _add(node: Node3D, offset: Vector3, fix: bool) -> void:
	var holder := Node3D.new()
	var scaled := Node3D.new()
	scaled.scale = Vector3(0.7, 0.7, 0.7)
	holder.add_child(scaled)
	scaled.add_child(node)
	var box := _aabb(holder)
	scaled.position = Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y, -(box.position.z + box.size.z * 0.5))
	holder.position = offset
	if fix:
		_fix(node)
	add_child(holder)

func _fix(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh: Mesh = (n as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s) as StandardMaterial3D
				if mat:
					var cp := mat.duplicate() as StandardMaterial3D
					cp.vertex_color_use_as_albedo = false
					(n as MeshInstance3D).set_surface_override_material(s, cp)
		for c in n.get_children():
			stack.append(c)

func _aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [[node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var n: Node = pair[0]
		var t: Transform3D = pair[1]
		if n is Node3D:
			t = t * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var b: AABB = (n as MeshInstance3D).mesh.get_aabb()
			for x in [b.position.x, b.end.x]:
				for y in [b.position.y, b.end.y]:
					for z in [b.position.z, b.end.z]:
						var pt: Vector3 = t * Vector3(x, y, z)
						if first:
							box = AABB(pt, Vector3.ZERO)
							first = false
						else:
							box = box.expand(pt)
		for c in n.get_children():
			stack.append([c, t])
	return box