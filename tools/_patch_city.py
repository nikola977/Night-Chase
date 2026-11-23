import io

p = "scripts/city_map.gd"
s = io.open(p, encoding="utf-8", newline="").read().replace("\r\n", "\n")


def cut(src, start_marker, end_marker, new):
    i = src.index(start_marker)
    j = src.index(end_marker, i)
    return src[:i] + new + src[j:]


# constants
old = "## Was eine Fl\u00e4che auf der Karte ist (siehe _map_style)\nenum MapStyle { SKIP, GROUND, PROP, BUILDING }"
new = old + '''

## Wo der Editor die Ver\u00e4nderungen an den Stadtobjekten speichert (Position,
## Rotation, Skalierung, gel\u00f6scht). Liegt neben layout.json in user://editor.
const CITY_LAYOUT_PATH := "user://editor/city_layout.json"'''
assert old in s
s = s.replace(old, new, 1)

# build body
build = '''\tvar started := Time.get_ticks_msec()
\t_objects = Node3D.new()
\t_objects.name = "CityObjects"
\tadd_child(_objects)
\t_surfaces = Node3D.new()
\t_surfaces.name = "Parking"
\tadd_child(_surfaces)
\tvar source := scene.instantiate()
\tvar poles: Array = []
\tvar triangles := 0
\tvar flattened := 0
\tvar glowing := 0
\tvar draw_meshes := 0
\tvar index := 0
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
\t\tdraw_meshes += int(holder.get_meta("draw_meshes", 0))
\tsource.free()
\tif boxes.is_empty():
\t\tpush_error("No meshes in %s" % city_file)
\t\treturn
\tbounds = boxes[0]
\tfor box in boxes:
\t\tbounds = bounds.merge(box)
\t# Vom Editor verschobene, skalierte oder gel\u00f6schte Objekte wiederherstellen
\t_apply_city_layout()
\tprint("City: %d editable objects (%d draw meshes, %d triangles), %.0f ms, bounds %s, %d ground vertices squashed, %d glowing" % [
\t\t_objects.get_child_count(), draw_meshes, triangles, Time.get_ticks_msec() - started,
\t\tbounds, flattened, glowing])
\tif parking:
\t\tParking.build(_surfaces)
\tif not poles.is_empty():
\t\t_spawn_poles(poles)
\t_build_collision()
\tif boundary_walls:
\t\t_build_walls()
\t_build_map_async()'''
s = cut(s, "\tvar started := Time.get_ticks_msec()", "\n\n## Squash low ground", build)

# flatten with y offset
flatten = '''## Squash low ground towards the road: the kerb stays a small step instead of a
## wall, but pavement and road keep different heights (no flickering surfaces).
## `y_offset` is the height of the object the vertices belong to.
func _flatten(arrays: Array, y_offset: float = 0.0) -> int:
\tvar verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
\tvar changed := 0
\tfor i in verts.size():
\t\tvar y := verts[i].y + y_offset
\t\tif y > -0.2 and y < ground_below:
\t\t\tvar squash := minf(kerb_step, maxf(0.0, y - ground_level) * kerb_squash)
\t\t\tvar target := ground_level + squash
\t\t\tif absf(y - target) > 0.0001:
\t\t\t\tverts[i].y = target - y_offset
\t\t\t\tchanged += 1
\tarrays[Mesh.ARRAY_VERTEX] = verts
\treturn changed'''
s = cut(s, "## Squash low ground towards the road", "\n\n## Copy of the imported material", flatten)

builders = '''## Ein Stadtobjekt (eine Gruppe aus dem FBX: ein Haus, ein Block, eine Stra\u00dfe).
## Die Meshes der Gruppe werden pro Material zusammengefasst, damit das Objekt nur
## wenige Draw-Calls hat, aber als Ganzes verschoben, gedreht, skaliert und gel\u00f6scht
## werden kann. Jedes Objekt bekommt seine eigene Kollision.
func _build_object(child: Node, index: int, poles: Array, boxes: Array[AABB]) -> Node3D:
\tvar holder := Node3D.new()
\tvar clean := String(child.name).validate_node_name()
\tholder.name = clean if clean != "" else "Object%d" % index
\tholder.set_meta("city_object", true)
\tholder.set_meta("city_id", "o%04d" % index)
\tholder.set_meta("city_label", String(child.name))
\tif child is Node3D:
\t\tholder.transform = (child as Node3D).transform
\tvar tools: Dictionary = {}
\tvar order: Array[String] = []
\tvar materials: Dictionary = {}
\tvar world := holder.transform
\tif child is MeshInstance3D:
\t\t_collect_part(child, Transform3D.IDENTITY, world, tools, order, materials, poles, boxes)
\tfor grandchild in child.get_children():
\t\t_collect_part(grandchild, Transform3D.IDENTITY, world, tools, order, materials, poles, boxes)
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
\treturn holder


## Sammelt alle Meshes unter `node` (Transform relativ zum Objekt) in SurfaceTools
## pro Material. `holder_xf` ist der Transform des ganzen Objekts und wird nur f\u00fcr
## Weltkoordinaten (Lampen, Bounds) gebraucht.
func _collect_part(node: Node, local: Transform3D, holder_xf: Transform3D, tools: Dictionary,
\t\torder: Array[String], materials: Dictionary, poles: Array, boxes: Array[AABB]) -> void:
\tvar here := local
\tif node is Node3D:
\t\there = local * (node as Node3D).transform
\tif node is MeshInstance3D:
\t\tvar instance := node as MeshInstance3D
\t\tvar mesh: Mesh = instance.mesh
\t\tif mesh != null:
\t\t\tvar world := holder_xf * here
\t\t\tboxes.append(world * mesh.get_aabb())
\t\t\tvar pole: Dictionary = _pole_of(mesh, world) if falling_poles else {}
\t\t\tif pole.is_empty():
\t\t\t\tfor surface in mesh.get_surface_count():
\t\t\t\t\tvar material := mesh.surface_get_material(surface)
\t\t\t\t\tvar key: String = material.resource_name if material != null else "<no material>"
\t\t\t\t\tif not tools.has(key):
\t\t\t\t\t\tvar tool := SurfaceTool.new()
\t\t\t\t\t\ttool.begin(Mesh.PRIMITIVE_TRIANGLES)
\t\t\t\t\t\tif material != null:
\t\t\t\t\t\t\ttool.set_material(material)
\t\t\t\t\t\ttools[key] = tool
\t\t\t\t\t\tmaterials[key] = material
\t\t\t\t\t\torder.append(key)
\t\t\t\t\t(tools[key] as SurfaceTool).append_from(mesh, surface, here)
\t\t\telse:
\t\t\t\tpoles.append(pole)
\tfor c in node.get_children():
\t\t_collect_part(c, here, holder_xf, tools, order, materials, poles, boxes)


func _surface_triangles(mesh: Mesh) -> int:
\tvar count := 0
\tfor surface in mesh.get_surface_count():
\t\tvar arrays := mesh.surface_get_arrays(surface)
\t\tvar indices: Variant = arrays[Mesh.ARRAY_INDEX]
\t\tif typeof(indices) == TYPE_PACKED_INT32_ARRAY and not (indices as PackedInt32Array).is_empty():
\t\t\tcount += (indices as PackedInt32Array).size() / 3
\t\telse:
\t\t\tcount += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
\treturn count


## Eigene Kollision pro Stadtobjekt: die Dreiecke des Objekts, mit flachem Boden
## (Kerb faces wie bisher weggelassen). So verschwindet die Kollision mit dem Objekt,
## wenn es gel\u00f6scht wird, und wandert mit, wenn es verschoben wird.
func _add_holder_collision(holder: Node3D) -> void:
\tvar xf := holder.transform
\tvar inverse := xf.affine_inverse()
\tvar faces := PackedVector3Array()
\tvar skipped := 0
\tfor child in holder.get_children():
\t\tvar instance := child as MeshInstance3D
\t\tif instance == null or instance.mesh == null:
\t\t\tcontinue
\t\tvar source := instance.mesh.get_faces()
\t\tfor i in range(0, source.size(), 3):
\t\t\tvar a := xf * source[i]
\t\t\tvar b := xf * source[i + 1]
\t\t\tvar c := xf * source[i + 2]
\t\t\tif ignore_kerb_faces and _is_kerb(a, b, c):
\t\t\t\tskipped += 1
\t\t\t\tcontinue
\t\t\tfor point in [a, b, c]:
\t\t\t\tfaces.append(inverse * _physics_point(point))
\tif faces.is_empty():
\t\treturn
\tvar body := StaticBody3D.new()
\tbody.name = "Collision"
\tbody.set_meta("city_object_collision", true)
\tvar shape := CollisionShape3D.new()
\tvar concave := ConcavePolygonShape3D.new()
\tconcave.set_faces(faces)
\tshape.shape = concave
\tbody.add_child(shape)
\tholder.add_child(body)'''
s = cut(s, "## Merge every mesh with its world transform into one surface per material", "\n\n## A lamp post:", builders)

# city layout API
layout = '''## Vom Editor gespeicherte Ver\u00e4nderungen (Position, Rotation, Skalierung, gel\u00f6scht)
func _apply_city_layout() -> void:
\tif not FileAccess.file_exists(CITY_LAYOUT_PATH):
\t\treturn
\tvar file := FileAccess.open(CITY_LAYOUT_PATH, FileAccess.READ)
\tif file == null:
\t\treturn
\tvar text := file.get_as_text()
\tfile.close()
\tvar data: Variant = JSON.parse_string(text)
\tif typeof(data) != TYPE_DICTIONARY:
\t\tpush_warning("city_layout.json ist nicht in Ordnung.")
\t\treturn
\tfor entry in data.get("objects", []):
\t\tif typeof(entry) != TYPE_DICTIONARY:
\t\t\tcontinue
\t\tvar node := _city_object_by_id(str(entry.get("id", "")))
\t\tif node == null:
\t\t\tcontinue
\t\tvar pos: Array = entry.get("pos", [])
\t\tif pos.size() == 3:
\t\t\tnode.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
\t\tvar rot: Array = entry.get("rot", [])
\t\tif rot.size() == 3:
\t\t\tnode.rotation = Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])),
\t\t\t\tdeg_to_rad(float(rot[2])))
\t\tvar scale := clampf(float(entry.get("scale", 1.0)), 0.02, 200.0)
\t\tnode.scale = Vector3.ONE * scale
\t\tif bool(entry.get("deleted", false)):
\t\t\t_set_city_deleted(node, true)


## Speichert alle Stadtobjekte (der Editor ruft das nach jeder \u00c4nderung auf)
func city_save_layout() -> void:
\tif _objects == null:
\t\treturn
\tDirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://editor"))
\tvar objects: Array = []
\tfor child in _objects.get_children():
\t\tvar node := child as Node3D
\t\tif node == null or not node.has_meta("city_object"):
\t\t\tcontinue
\t\tobjects.append({
\t\t\t"id": str(node.get_meta("city_id", "")),
\t\t\t"name": str(node.get_meta("city_label", node.name)),
\t\t\t"pos": [node.position.x, node.position.y, node.position.z],
\t\t\t"rot": [rad_to_deg(node.rotation.x), rad_to_deg(node.rotation.y), rad_to_deg(node.rotation.z)],
\t\t\t"scale": node.scale.x,
\t\t\t"deleted": not node.visible,
\t\t})
\tvar file := FileAccess.open(CITY_LAYOUT_PATH, FileAccess.WRITE)
\tif file == null:
\t\tpush_warning("Kann die Stadt nicht speichern: " + CITY_LAYOUT_PATH)
\t\treturn
\tfile.store_string(JSON.stringify({"version": 1, "objects": objects}, "  "))
\tfile.close()


## L\u00f6scht ein Stadtobjekt (ausblenden, Kollision aus, in city_layout.json merken)
func city_delete(node: Node3D) -> void:
\tif node == null or not is_instance_valid(node):
\t\treturn
\t_set_city_deleted(node, true)
\tcity_save_layout()


func _set_city_deleted(node: Node3D, deleted: bool) -> void:
\tnode.visible = not deleted
\tfor child in node.get_children():
\t\tvar body := child as StaticBody3D
\t\tif body != null:
\t\t\tbody.collision_layer = 0 if deleted else 1
\t\t\tbody.collision_mask = 0 if deleted else 1


func _city_object_by_id(id: String) -> Node3D:
\tif _objects == null or id == "":
\t\treturn null
\tfor child in _objects.get_children():
\t\tvar node := child as Node3D
\t\tif node != null and str(node.get_meta("city_id", "")) == id:
\t\t\treturn node
\treturn null


## Name des Objekts f\u00fcr den Editor (z. B. "Filler_Housing")
func city_label(node: Node3D) -> String:
\tif node == null or not is_instance_valid(node):
\t\treturn ""
\treturn str(node.get_meta("city_label", node.name))


## Start transform of the car'''
s = s.replace("## Start transform of the car", layout, 1)

# map build from all draw meshes
old = '''\tvar textures: Dictionary = {}
\tfor child in _surfaces.get_children():
\t\tvar mesh: Mesh = (child as MeshInstance3D).mesh'''
new = '''\tvar textures: Dictionary = {}
\tvar draw_meshes: Array[Node] = []
\tdraw_meshes.append_array(_merged)
\tdraw_meshes.append_array(_surfaces.get_children())
\tfor child in draw_meshes:
\t\tvar mesh: Mesh = (child as MeshInstance3D).mesh'''
assert old in s
s = s.replace(old, new, 1)

old = '\tprint("City: physics with %d triangles (%d kerb faces left out)" % [faces.size() / 3, skipped])'
new = '\tprint("City: parking physics with %d triangles (%d kerb faces left out)" % [faces.size() / 3, skipped])'
assert old in s
s = s.replace(old, new, 1)

old = '''## The merged surfaces, one MeshInstance3D per material
var _surfaces: Node3D
var _car: VehicleBody3D'''
new = '''## Die Parkpl\u00e4tze (eigene Meshes mit eigener Kollision)
var _surfaces: Node3D
## Alle Stadtobjekte (eine Node3D-Gruppe pro Haus/Block/Stra\u00dfe aus dem FBX)
var _objects: Node3D
## Alle gezeichneten Meshes der Stadt (f\u00fcr das Kartenbild)
var _merged: Array[MeshInstance3D] = []
## Material-Kopien pro Materialname, damit nicht jedes Haus neue Materialien anlegt
var _material_cache: Dictionary = {}
var _car: VehicleBody3D'''
assert old in s
s = s.replace(old, new, 1)

old = '''\tvar copy := material.duplicate() as StandardMaterial3D
\tcopy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC'''
new = '''\tif _material_cache.has(key):
\t\treturn _material_cache[key]
\tvar copy := material.duplicate() as StandardMaterial3D
\tcopy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC'''
assert old in s
s = s.replace(old, new, 1)

old = '''\t\tcopy.emission_energy_multiplier = 0.22
\treturn copy'''
new = '''\t\tcopy.emission_energy_multiplier = 0.22
\t_material_cache[key] = copy
\treturn copy'''
assert old in s
s = s.replace(old, new, 1)

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("city_map.gd patched, lines:", s.count("\n"))
