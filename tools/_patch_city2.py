import io

p = "scripts/city_map.gd"
s = io.open(p, encoding="utf-8", newline="").read().replace("\r\n", "\n")

old = '''\tvar index := 0
\tvar boxes: Array[AABB] = []
\tfor child in source.get_children():
\t\tvar holder := _build_object(child, index, poles, boxes)
\t\tindex += 1
\t\tif holder == null:
\t\t\tcontinue
\t\t_objects.add_child(holder)
\t\ttriangles += int(holder.get_meta("triangles", 0))
\t\tflattened += int(holder.get_meta("flattened", 0))
\t\tglowing += int(holder.get_meta("glowing", 0))
\t\tdraw_meshes += int(holder.get_meta("draw_meshes", 0))'''
new = '''\tvar index := 0
\tvar boxes: Array[AABB] = []
\tfor child in source.get_children():
\t\tfor holder: Node3D in _build_objects(child, index, poles, boxes):
\t\t\t_objects.add_child(holder)
\t\t\ttriangles += int(holder.get_meta("triangles", 0))
\t\t\tflattened += int(holder.get_meta("flattened", 0))
\t\t\tglowing += int(holder.get_meta("glowing", 0))
\t\t\tdraw_meshes += int(holder.get_meta("draw_meshes", 0))
\t\tindex += 1'''
assert old in s
s = s.replace(old, new, 1)

start = "## Ein Stadtobjekt (eine Gruppe aus dem FBX: ein Haus, ein Block, eine Stra\u00dfe)."
end = "\n\n## Sammelt alle Meshes unter `node`"
new_block = '''## Zerlegt eine Gruppe aus dem FBX in einzeln bearbeitbare Objekte. Gruppen, die
## mehrere Geb\u00e4ude enthalten (z. B. Filler_Housing mit sechs H\u00e4usern), werden in
## ihre Untergruppen aufgeteilt; einfache Gruppen bleiben ein Objekt.
func _build_objects(child: Node, index: int, poles: Array, boxes: Array[AABB]) -> Array[Node3D]:
\tvar out: Array[Node3D] = []
\tvar id := "%04d" % index
\tvar world := Transform3D.IDENTITY
\tif child is Node3D:
\t\tworld = (child as Node3D).transform
\tvar parts: Array[Node] = []
\tif child is Node3D:
\t\tfor c in child.get_children():
\t\t\tif _has_mesh(c):
\t\t\t\tparts.append(c)
\tif parts.size() < 2:
\t\tvar single := _holder_for(child, world, id, String(child.name), poles, boxes)
\t\tif single != null:
\t\t\tout.append(single)
\t\treturn out
\t# Mehrere Untergruppen: jede wird ein eigenes Objekt, direkte Meshes der Gruppe
\t# (ohne die Untergruppen) bilden ein weiteres Objekt
\tvar parent_holder := _holder_for(child, world, id, String(child.name), poles, boxes, parts)
\tif parent_holder != null:
\t\tout.append(parent_holder)
\tvar sub := 0
\tfor part in parts:
\t\tvar part_xf: Transform3D = world * (part as Node3D).transform
\t\tvar label := "%s \u203a %s" % [String(child.name), String(part.name)]
\t\tvar holder := _holder_for(part, part_xf, "%s.%02d" % [id, sub], label, poles, boxes)
\t\tsub += 1
\t\tif holder != null:
\t\t\tout.append(holder)
\treturn out


func _has_mesh(node: Node) -> bool:
\tvar stack: Array[Node] = [node]
\twhile not stack.is_empty():
\t\tvar current: Node = stack.pop_back()
\t\tvar instance := current as MeshInstance3D
\t\tif instance != null and instance.mesh != null:
\t\t\treturn true
\t\tstack.append_array(current.get_children())
\treturn false


## Baut ein Objekt aus `node`: Meshes pro Material zusammengefasst, eigene Kollision.
## `skip` sind Knoten, die zu anderen Objekten geh\u00f6ren und nicht mitgenommen werden.
func _holder_for(node: Node, xf: Transform3D, id: String, label: String, poles: Array,
\t\tboxes: Array[AABB], skip: Array[Node] = []) -> Node3D:
\tvar holder := Node3D.new()
\tvar clean := String(node.name).validate_node_name()
\tholder.name = clean if clean != "" else "Object"
\tholder.set_meta("city_object", true)
\tholder.set_meta("city_id", id)
\tholder.set_meta("city_label", label)
\tholder.transform = xf
\tvar tools: Dictionary = {}
\tvar order: Array[String] = []
\tvar materials: Dictionary = {}
\tif node is MeshInstance3D:
\t\t_collect_mesh(node as MeshInstance3D, Transform3D.IDENTITY, xf, tools, order, materials,
\t\t\tpoles, boxes)
\telse:
\t\tfor c in node.get_children():
\t\t\tif c in skip:
\t\t\t\tcontinue
\t\t\t_collect_part(c, Transform3D.IDENTITY, xf, tools, order, materials, poles, boxes)
\tvar triangles := 0
\tvar flattened := 0
\tvar glowing := 0
\tfor key in order:
\t\tvar arrays: Array = (tools[key] as SurfaceTool).commit_to_arrays()
\t\tif arrays.is_empty():
\t\t\tcontinue
\t\tif flatten_ground:
\t\t\tflattened += _flatten(arrays, holder.position.y)
\t\tvar mesh := ArrayMesh.new()
\t\tmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
\t\tvar lit := _city_material(materials.get(key) as StandardMaterial3D, key)
\t\tif key.to_lower().contains("glow"):
\t\t\tglowing += 1
\t\tmesh.surface_set_material(0, lit)
\t\tvar instance := MeshInstance3D.new()
\t\tinstance.name = key.validate_node_name()
\t\tinstance.mesh = mesh
\t\tholder.add_child(instance)
\t\t_merged.append(instance)
\t\ttriangles += _surface_triangles(mesh)
\t# Leere Gruppen (nur Marker im FBX) sind keine Objekte
\tif triangles == 0:
\t\tholder.free()
\t\treturn null
\tholder.set_meta("triangles", triangles)
\tholder.set_meta("flattened", flattened)
\tholder.set_meta("glowing", glowing)
\tholder.set_meta("draw_meshes", holder.get_child_count())
\t_add_holder_collision(holder)
\treturn holder'''
s = s[:s.index(start)] + new_block + s[s.index(end):]

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("split patch applied, lines:", s.count("\n"))
