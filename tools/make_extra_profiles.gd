extends Node
## Misst die aus .blend exportierten .glb-Modelle (tools/blend_export.py) und schreibt je Auto
## ein Profil nach cars/<id>.tres: Radstand, Spur, Radradius, Karosserie- und Kabinenbox aus den
## echten Maßen, damit das Auto in der Garage fahrbar ist. Vorhandene Profile bleiben unberührt.

const EXTRA: Array = [
	{"id": "centenario", "name": "Lamborghini Centenario LP 770-4", "brand": "Lamborghini", "year": 2016,
		"folder": "lamborghini-centenario-lp-770-interior-sdc", "ps": 770, "drive": "All-wheel drive",
		"engine": "6,5 l V12", "cyl": 12},
	{"id": "centenario_roadster", "name": "Lamborghini Centenario Roadster", "brand": "Lamborghini", "year": 2017,
		"folder": "lamborghini-centenario-roadster-sdc", "ps": 770, "drive": "All-wheel drive",
		"engine": "6,5 l V12", "cyl": 12},
	{"id": "aventador", "name": "Lamborghini Aventador LP 700-4", "brand": "Lamborghini", "year": 2011,
		"folder": "free-lamborghini-aventador-lp-700-4", "ps": 700, "drive": "All-wheel drive",
		"engine": "6,5 l V12", "cyl": 12},
	{"id": "gt3", "name": "Porsche 911 GT3", "brand": "Porsche", "year": 2021,
		"folder": "porsche-911-gt3", "ps": 510, "drive": "Rear-wheel drive",
		"engine": "4,0 l Boxer-Sechszylinder (9A1)", "cyl": 6},
]

const WHEEL_WORDS: Array[String] = ["wheel", "rim", "tyre", "tire", "reifen", "felge", "pneu", "llanta",
	"rueda", "janta", "cerch", "whl"]
const SKIP_WORDS: Array[String] = ["steer", "cockpit", "interior", "cluster", "warning", "sensor", "tpms", "int"]
const PAINTS: Array[Color] = [Color(0.75, 0.08, 0.09), Color(0.86, 0.87, 0.86), Color(0.02, 0.05, 0.12),
	Color(0.62, 0.64, 0.66), Color(0.92, 0.55, 0.02), Color(0.03, 0.32, 0.6)]


func _ready() -> void:
	for entry: Dictionary in EXTRA:
		print("PROFILE ", _make(entry))
	print("done")
	get_tree().quit()


func _make(entry: Dictionary) -> String:
	var profile := CarProfile.new()
	profile.id = entry["id"]
	profile.display_name = entry["name"]
	profile.brand = entry["brand"]
	profile.year = entry["year"]
	profile.subtitle = "%s · %d" % [entry["brand"], entry["year"]]
	profile.model_folder = entry["folder"]
	profile.power_ps = entry["ps"]
	profile.drive_text = entry["drive"]
	profile.engine_text = entry["engine"]
	profile.cylinders = entry["cyl"]
	profile.paint_colors = PAINTS.duplicate()
	profile.credit = "Sketchfab model, license see assets/models/%s" % entry["folder"]

	var path := CarModel.model_path(profile)
	if path == "":
		return "%s: NO MODEL (%s)" % [entry["id"], entry["folder"]]
	var scene := load(path) as PackedScene
	if scene == null:
		return "%s: LOAD FAILED %s" % [entry["id"], path]
	var inst := scene.instantiate()
	add_child(inst)

	var meshes := _meshes(inst)
	if meshes.is_empty():
		inst.queue_free()
		return "%s: NO MESHES" % entry["id"]
	# Manche Download-Szenen enthalten Teile weit weg vom Auto (z. B. ein Motor 7 m daneben).
	# Nur was um das größte Mesh herum liegt, gehört zum Auto – sonst wird das Auto zu groß.
	var core := _core_box(meshes)
	var near: Array[MeshInstance3D] = []
	for mi in meshes:
		if core.has_point(mi.global_position) or core.intersects(mi.global_transform * mi.get_aabb()):
			near.append(mi)
	meshes = near
	var full := _box(meshes)
	if full.size.x <= 0.0 or full.size.z <= 0.0:
		inst.queue_free()
		return "%s: EMPTY BOUNDS" % entry["id"]
	# Längsachse: exportierte Modelle stehen mal längs Z, mal längs X
	var sideways := full.size.x > full.size.z * 1.15
	var length_model := full.size.x if sideways else full.size.z
	if sideways:
		profile.model_rotation_deg = 90.0

	var wheels: Array[MeshInstance3D] = []
	for mi in meshes:
		if _is_wheel(mi):
			wheels.append(mi)
	var names: Array[String] = []
	for mi in wheels:
		names.append(String(mi.name))
	var radius_model := _wheel_radius(wheels)
	var notes := "wheels_ok"
	var scale := 1.0
	var wheelbase := 0.0
	var track := 0.0
	var reliable := wheels.size() >= 4 and radius_model > 0.0
	if reliable:
		var wheel_d := radius_model * 2.0
		var wb_model := maxf(length_model - wheel_d, length_model * 0.5)
		scale = 1.0 if (wb_model > 1.2 and wb_model < 4.5) else 2.7 / maxf(wb_model, 0.01)
		wheelbase = wb_model * scale
		var wbox := _box(wheels)
		var width_model := wbox.size.z if sideways else wbox.size.x
		track = maxf(width_model - wheel_d * 0.55, width_model * 0.55) * scale
		profile.wheel_parts = PackedStringArray(names)
	else:
		scale = 4.6 / maxf(length_model, 0.01)
		wheelbase = 2.7
		track = 1.6
		radius_model = 0.33 / maxf(scale, 0.001)
		notes = "NO/WIDE WHEELS"
		if not names.is_empty():
			profile.wheel_parts = PackedStringArray(names)

	profile.wheelbase = clampf(wheelbase, 2.3, 3.2)
	profile.track_front = clampf(track, 1.4, 1.78)
	profile.track_rear = profile.track_front
	profile.wheel_radius = clampf(radius_model * scale, 0.28, 0.40)
	var length := maxf(length_model * scale, profile.wheelbase * 1.35)
	var width := clampf((full.size.z if sideways else full.size.x) * scale,
		profile.track_front + 0.12, 2.35)
	var height := clampf(full.size.y * scale, 1.05, 2.0)
	profile.body_size = Vector3(width * 0.96, height * 0.55, length * 0.98)
	profile.body_center = Vector3(0.0, height * 0.27, 0.0)
	profile.cabin_size = Vector3(width * 0.7, height * 0.42, length * 0.5)
	profile.cabin_center = Vector3(0.0, height * 0.74, -length * 0.04)

	inst.queue_free()
	var error := ResourceSaver.save(profile, "res://cars/%s.tres" % entry["id"])
	return "%s | save=%d | scale=%.3f wheelbase=%.2f track=%.2f radius=%.2f size=%.2f x %.2f x %.2f | rot=%d | %s | wheels=%d" % [
		entry["id"], error, scale, profile.wheelbase, profile.track_front, profile.wheel_radius,
		width, height, length, roundi(profile.model_rotation_deg), notes, wheels.size()]


## Box des größten Meshes, um 60 % gewachsen: alles darum ist das Auto
func _core_box(meshes: Array[MeshInstance3D]) -> AABB:
	var best := AABB()
	var best_volume := 0.0
	for mi in meshes:
		var piece: AABB = mi.global_transform * mi.get_aabb()
		var volume: float = piece.size.x * piece.size.y * piece.size.z
		if volume > best_volume:
			best_volume = volume
			best = piece
	if best_volume <= 0.0:
		return _box(meshes)
	best = best.grow(best.size.length() * 0.6)
	return best


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and (current as MeshInstance3D).mesh != null:
			result.append(current)
		stack.append_array(current.get_children())
	return result


func _box(meshes: Array) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in meshes:
		var piece: AABB = mi.global_transform * mi.get_aabb()
		box = piece if first else box.merge(piece)
		first = false
	return box


func _wheel_radius(wheels: Array) -> float:
	var halves: Array[float] = []
	for mi: MeshInstance3D in wheels:
		halves.append((mi.global_transform * mi.get_aabb()).size.y * 0.5)
	if halves.is_empty():
		return 0.0
	halves.sort()
	return halves[halves.size() / 2]


func _is_wheel(mi: MeshInstance3D) -> bool:
	var tokens := _tokens(String(mi.name))
	if mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var material := mi.mesh.surface_get_material(s)
			if material != null:
				tokens.append_array(_tokens(material.resource_name))
	for token in tokens:
		if token in SKIP_WORDS:
			return false
	for token in tokens:
		for root in WHEEL_WORDS:
			if token == root or token.begins_with(root):
				return true
	return false


func _tokens(text: String) -> Array[String]:
	var out: Array[String] = []
	var current := ""
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			current += ch
		elif current != "":
			out.append(current)
			current = ""
	if current != "":
		out.append(current)
	return out
