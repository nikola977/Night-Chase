extends SceneTree

func _init() -> void:
	var scene := load("res://assets/tracks/city/city.fbx") as PackedScene
	if scene == null:
		print("NO SCENE")
		quit()
		return
	var root := scene.instantiate()
	_dump(root, 0)
	quit()

func _dump(node: Node, depth: int) -> void:
	var info := ""
	if node is Node3D:
		var n3 := node as Node3D
		info = " pos=%s" % str(n3.position.snapped(Vector3(0.01, 0.01, 0.01)))
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var a := mi.get_aabb()
			info += " tri=%d size=%s" % [_tris(mi.mesh), str(a.size.snapped(Vector3(0.1, 0.1, 0.1)))]
		else:
			info += " NOMESH"
	print("%s%s [%s] children=%d%s" % ["  ".repeat(depth), node.name, node.get_class(),
		node.get_child_count(), info])
	if depth < 2:
		for c in node.get_children():
			_dump(c, depth + 1)

func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if typeof(idx) == TYPE_PACKED_INT32_ARRAY and not (idx as PackedInt32Array).is_empty():
			n += (idx as PackedInt32Array).size() / 3
		else:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n
