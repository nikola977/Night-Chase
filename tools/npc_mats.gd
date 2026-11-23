extends Node3D
## Temporary: dumps the materials of the downloaded NPC car models.

var _out := ""

func _ready() -> void:
	_dump_model("res://assets/models/npc/2009-scion-xd/source/FINALXd.glb", "")
	_dump_model("res://assets/models/npc/traffic-rider-npc-vehicles/source/trafficrider2.fbx", "AI_Bmw4_High")
	_dump_model("res://assets/models/npc/traffic-rider-npc-vehicles/source/trafficrider2.fbx", "AI_Golf7_High")
	_dump_model("res://assets/models/npc/traffic-rider-npc-vehicles/source/trafficrider2.fbx", "AI_Scania_High")
	var f := FileAccess.open("res://screenshots/npc_mats.txt", FileAccess.WRITE)
	if f:
		f.store_string(_out)
		f.close()

func _dump_model(path: String, node_name: String) -> void:
	_out += "==== %s %s ====\n" % [path.get_file(), node_name]
	var scene := load(path) as PackedScene
	if scene == null:
		_out += "null\n\n"
		return
	var inst: Node = scene.instantiate()
	var root: Node = inst if node_name == "" else inst.get_node_or_null(node_name)
	if root == null:
		_out += "node missing\n\n"
		inst.free()
		return
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh: Mesh = (n as MeshInstance3D).mesh
			_out += "  mesh '%s' surfaces=%d\n" % [n.name, mesh.get_surface_count()]
			for s in mesh.get_surface_count():
				_out += "    [%d] %s\n" % [s, _mat_info(mesh.surface_get_material(s))]
		for c in n.get_children():
			stack.append(c)
	inst.free()
	_out += "\n"

func _mat_info(mat: Material) -> String:
	if mat == null:
		return "<null material>"
	var cls := mat.get_class()
	if mat is StandardMaterial3D:
		var std := mat as StandardMaterial3D
		var tex := ""
		if std.albedo_texture != null:
			tex = std.albedo_texture.resource_path
		return "%s '%s' color=%s tex='%s' vcol=%s" % [cls, mat.resource_name, std.albedo_color, tex,
			str(std.vertex_color_use_as_albedo)]
	return "%s '%s'" % [cls, mat.resource_name]