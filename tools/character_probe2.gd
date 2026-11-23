extends SceneTree
## Einmalig: zeigt die Ruhe-Lage der Knochen (Armature-Raum) des Zeichens.
## Godot --headless --path . -s res://tools/character_probe2.gd

const PATH := "res://assets/models/character_cyberpunk/scene.gltf"
const NAMES: Array[String] = [
	"hips_00", "spine1_01", "spine3_03", "neck_04", "head_05",
	"l eye_06", "r eye_07",
	"l shoulder_027", "l arm_028", "l forearm_029", "l hand_030",
	"r shoulder_08", "r arm_09", "r forearm_010", "r hand_011",
	"l leg_047", "l knee_048", "l foot_049", "l toes_050",
	"r leg_051", "r knee_052", "r foot_053", "r toes_054",
]


func _initialize() -> void:
	var packed := load(PATH) as PackedScene
	if packed == null:
		print("Konnte nicht laden")
		quit()
		return
	var root := packed.instantiate()
	var skeleton := _find_skeleton(root)
	print("Skelett-Skalierung: ", skeleton.scale)
	for bone in NAMES:
		var index := skeleton.find_bone(bone)
		if index < 0:
			print(bone, " fehlt")
			continue
		var rest := skeleton.get_bone_global_rest(index)
		var parent := skeleton.get_bone_parent(index)
		print("%-14s idx=%2d  pos=%s  vorne(Y-Achse)=%s  Eltern=%s" % [
			bone, index,
			_s(rest.origin),
			_s(rest.basis.y.normalized()),
			skeleton.get_bone_name(parent) if parent >= 0 else "-",
		])
	# Gelenk-Längen für die Sitzhaltung
	_joint(skeleton, "l leg_047", "l knee_048")
	_joint(skeleton, "l knee_048", "l foot_049")
	_joint(skeleton, "r leg_051", "r knee_052")
	_joint(skeleton, "r knee_052", "r foot_053")
	_joint(skeleton, "l arm_028", "l forearm_029")
	_joint(skeleton, "l forearm_029", "l hand_030")
	_joint(skeleton, "r arm_09", "r forearm_010")
	_joint(skeleton, "r forearm_010", "r hand_011")
	_joint(skeleton, "hips_00", "neck_04")
	# Materialliste und Mesh-Namen (zum Ausblenden von Kopf, Kapuze usw.)
	var player := _find_player(root)
	if player:
		print("Animationen: ", player.get_animation_list())
	root.free()
	quit()


func _joint(skeleton: Skeleton3D, a: String, b: String) -> void:
	var ia := skeleton.find_bone(a)
	var ib := skeleton.find_bone(b)
	var pa := skeleton.get_bone_global_rest(ia).origin
	var pb := skeleton.get_bone_global_rest(ib).origin
	print("Länge %s -> %s: %.2f cm  Richtung %s" % [a, b, pa.distance_to(pb), _s((pb - pa).normalized())])


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null


func _s(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
