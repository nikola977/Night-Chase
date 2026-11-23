extends Node3D
## Temporary: measures the full AABB of each downloaded NPC car model (clean transforms).

func _ready() -> void:
	var paths := [
		"res://assets/models/npc/2009-scion-xd/source/FINALXd.glb",
		"res://assets/models/npc/2010-suzuki-sx4-sportback/source/sx4FINAL.glb",
		"res://assets/models/npc/pontiac-g8-gxp-2009/source/Pontiac_G8_GXP_2009_FM7_Sketchfab.glb",
		"res://assets/models/npc/traffic-rider-npc-vehicles/source/trafficrider2.fbx",
	]
	var out := ""
	for p in paths:
		out += "==== %s ====\n" % p
		var s := load(p) as PackedScene
		if s == null:
			out += "LOADED=null\n\n"
			continue
		var inst: Node = s.instantiate()
		var box := _aabb(inst, Transform3D.IDENTITY)
		out += "FULL size=%s center=%s\n" % [str(box.size), str(box.get_center())]
		if inst.get_child_count() > 1:
			for child in inst.get_children():
				if not (child is MeshInstance3D):
					continue
				var cb := _aabb(child, inst.transform)
				out += "  %-26s size=%s off=%s\n" % [child.name, str(cb.size), str(cb.get_center())]
		elif inst.get_child_count() == 1 and inst.get_child(0).get_child_count() > 1:
			out += "  (children of %s)\n" % inst.get_child(0).name
			for gc in inst.get_child(0).get_children():
				if not (gc is MeshInstance3D):
					continue
				var gb := _aabb(gc, inst.transform * (inst.get_child(0) as Node3D).transform)
				out += "    %-28s size=%s\n" % [gc.name, str(gb.size)]
		inst.free()
		out += "\n"
	var f := FileAccess.open("res://screenshots/npc_probe.txt", FileAccess.WRITE)
	if f:
		f.store_string(out)
		f.close()

func _aabb(node: Node, xf: Transform3D) -> AABB:
	var here := xf
	if node is Node3D:
		here = xf * (node as Node3D).transform
	var box := AABB()
	var first := true
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		var b: AABB = mi.mesh.get_aabb()
		for x in [b.position.x, b.end.x]:
			for y in [b.position.y, b.end.y]:
				for z in [b.position.z, b.end.z]:
					var pt: Vector3 = here * Vector3(x, y, z)
					if first:
						box = AABB(pt, Vector3.ZERO)
						first = false
					else:
						box = box.expand(pt)
	for child in node.get_children():
		var cb := _aabb(child, here)
		if cb.size.length() > 0.0:
			if first:
				box = cb
				first = false
			else:
				box = box.merge(cb)
	return box