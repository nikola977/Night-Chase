extends SceneTree

func _init() -> void:
	var scene := load("res://assets/tracks/city/city.fbx") as PackedScene
	var root := scene.instantiate()
	get_root().add_child(root)
	var groups := 0
	var meshes := 0
	for child in root.get_children():
		var info := _info(child)
		if info[1] > 0:
			groups += 1
			meshes += info[1]
			print("%-28s meshes=%4d childgroups=%3d size=%s" % [String(child.name), info[1], info[2], str(info[3])])
	print("filled groups:", groups, "meshes:", meshes)
	quit()

func _info(node: Node) -> Array:
	var count := 0
	var child_groups := 0
	var box := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			count += 1
			var b: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		stack.append_array(n.get_children())
	for c in node.get_children():
		if c is Node3D and _has_mesh(c):
			child_groups += 1
	return [node, count, child_groups, box.size.snapped(Vector3(0.1, 0.1, 0.1))]

func _has_mesh(node: Node) -> bool:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			return true
		stack.append_array(n.get_children())
	return false
