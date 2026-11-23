extends Node3D
## Temporary: baut alle neuen Garage-Autos wie in der Garage auf (CarModel mit Vorschau-Rädern),
## macht ein Übersichtsbild und schreibt einen Bericht, welches Modell gültige Transforms hat.

const IDS: Array = ["giulietta", "mx5", "wrx", "urus", "caprice", "challenger", "corvette", "svj", "gt3rs", "supra"]

var _holders: Array[Node3D] = []


func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.5, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.7
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 40)
	plane.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.32, 0.35)
	plane.material_override = mat
	plane.position = Vector3(14, 0, 4)
	add_child(plane)
	for i in IDS.size():
		var holder := Node3D.new()
		holder.position = Vector3((i % 5) * 7.0, 0.0, (i / 5) * 9.0)
		add_child(holder)
		_holders.append(holder)
		var model := CarModel.new()
		holder.add_child(model)
		model.show_profile(load("res://cars/%s.tres" % IDS[i]))
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(14.0, 26.0, 30.0)
	cam.look_at(Vector3(14.0, 0.5, 4.0), Vector3.UP)
	cam.fov = 55.0
	cam.current = true
	await get_tree().create_timer(14.0).timeout
	_dump()


func _dump() -> void:
	var lines: Array[String] = []
	for i in IDS.size():
		var model := _holders[i].get_child(0) as CarModel
		var pivot := model.get_node_or_null("ModelPivot") as Node3D
		var meshes := 0
		var non_finite := 0
		var stack: Array = [model]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				meshes += 1
				if not (n as MeshInstance3D).global_transform.origin.is_finite():
					non_finite += 1
			stack.append_array(n.get_children())
		var pv := "none"
		if pivot:
			pv = "scale=%.3f pos=%s fin=%s" % [pivot.transform.basis.get_scale().x,
				str(pivot.transform.origin), str(pivot.transform.origin.is_finite())]
		lines.append("%s: meshes=%d non_finite=%d pivot=%s measured=%s" % [
			IDS[i], meshes, non_finite, pv, str(model.measured)])
	var file := FileAccess.open("res://screenshots/car_check.txt", FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()