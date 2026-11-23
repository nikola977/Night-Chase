extends SceneTree
## Einmalig: zeigt Aufbau, Knochen und Größe des importierten Zeichens.
## Godot --headless --path . -s res://tools/character_probe.gd

const PATH := "res://assets/models/character_cyberpunk/scene.gltf"


func _initialize() -> void:
	var packed := load(PATH) as PackedScene
	if packed == null:
		print("Konnte ", PATH, " nicht laden")
		quit()
		return
	var root := packed.instantiate()
	print("== Wurzel: ", root.name, " (", root.get_class(), ")")
	_dump(root, 0)
	var skeleton := _find_skeleton(root)
	if skeleton:
		print("== Knochen: ", skeleton.get_bone_count())
		for i in skeleton.get_bone_count():
			print("  ", i, "  ", skeleton.get_bone_name(i), "   Eltern: ", skeleton.get_bone_parent(i))
	var aabb := _world_aabb(root)
	print("== AABB: Position ", aabb.position, "  Größe ", aabb.size)
	for anim in _find_animations(root):
		print("== Animation: ", anim.name, "  Länge ", anim.length)
	root.free()
	quit()


func _dump(node: Node, depth: int) -> void:
	var text := "  ".repeat(depth) + node.name + "  [" + node.get_class() + "]"
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh:
			text += "  Oberflächen: %d  AABB: %s" % [mesh.get_surface_count(), mesh.get_aabb()]
			var mat := (node as MeshInstance3D).get_active_material(0)
			if mat:
				text += "  Material: " + mat.resource_name
	print(text)
	for child in node.get_children():
		_dump(child, depth + 1)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _find_animations(node: Node) -> Array[AnimationPlayer]:
	var list: Array[AnimationPlayer] = []
	if node is AnimationPlayer:
		list.append(node)
	for child in node.get_children():
		list.append_array(_find_animations(child))
	return list


func _world_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		var box := instance.global_transform * instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
