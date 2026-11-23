extends Node
const CARS: Array = [
	{"id": "giulietta", "name": "Alfa Romeo Giulietta Quadrifoglio Verde", "brand": "Alfa Romeo", "year": 2011, "folder": "2011-alfa-romeo-giulietta-quadrifoglio-verde", "ps": 235, "drive": "Front-wheel drive", "engine": "1,75 l Vierzylinder, Turbo (1750 TBi)"},
	{"id": "mx5", "name": "Mazda MX-5 Miata (Pandem)", "brand": "Mazda", "year": 2015, "folder": "2015-pandem-mazda-mx5-miata", "ps": 250, "drive": "Rear-wheel drive", "engine": "2,0 l Vierzylinder (Skyactiv, Pandem)"},
	{"id": "wrx", "name": "Subaru WRX STI (Kuhl Racing)", "brand": "Subaru", "year": 2018, "folder": "2018-kuhl-racing-gt-subaru-wrx-sti", "ps": 350, "drive": "All-wheel drive", "engine": "2,5 l Boxer-Vierzylinder, Turbo (EJ257)"},
	{"id": "urus", "name": "Lamborghini Urus Performante", "brand": "Lamborghini", "year": 2023, "folder": "2023-lamborghini-urus-performante", "ps": 666, "drive": "All-wheel drive", "engine": "4,0 l V8, Biturbo"},
	{"id": "caprice", "name": "Chevrolet Caprice Police", "brand": "Chevrolet", "year": 1994, "folder": "chevrolet-caprice-police-car-94-free-asset", "ps": 260, "drive": "Rear-wheel drive", "engine": "5,7 l V8 (LT1)"},
	{"id": "challenger", "name": "Dodge Challenger SRT Hellcat", "brand": "Dodge", "year": 2015, "folder": "dodge-challenger-srt-hellcat", "ps": 717, "drive": "Rear-wheel drive", "engine": "6,2 l V8 Kompressor (Hellcat)"},
	{"id": "corvette", "name": "Chevrolet Corvette Carbon 65", "brand": "Chevrolet", "year": 2018, "folder": "free-chevrolet-corvette-carbon-65-edition-18", "ps": 650, "drive": "Rear-wheel drive", "engine": "6,2 l V8 Kompressor (LT4)"},
	{"id": "svj", "name": "Lamborghini Aventador SVJ", "brand": "Lamborghini", "year": 2019, "folder": "lamborghini-aventador-svj-mansory-twin-turbo-pbr", "ps": 770, "drive": "All-wheel drive", "engine": "6,5 l V12"},
	{"id": "gt3rs", "name": "Porsche 911 GT3 RS (Weissach)", "brand": "Porsche", "year": 2019, "folder": "porsche-911-gt3-rs-weissach", "ps": 520, "drive": "Rear-wheel drive", "engine": "4,0 l Boxer-Sechszylinder (9A1)"},
	{"id": "supra", "name": "Toyota Supra (A80)", "brand": "Toyota", "year": 1994, "folder": "toyota-supra", "ps": 330, "drive": "Rear-wheel drive", "engine": "3,0 l Reihensechszylinder, Biturbo (2JZ-GTE)"},
]
const WHEEL_WORDS: Array = ["wheel", "rim", "tyre", "tire", "reifen", "felge", "pneu", "llanta",
	"rueda", "janta", "cerch", "whl"]
const SKIP_WORDS: Array = ["steer", "cockpit", "interior", "cluster", "warning", "sensor", "tpms", "int"]

func _ready() -> void:
	var report: Array = []
	for entry in CARS:
		report.append(_make(entry))
	var f = File.new()
	var err = f.open("user://screenshots/profile_report.txt", File.WRITE)
	if err == OK:
		f.store_string(report.join("\n"))
		f.close()
	print("done")

func _make(entry) -> String:
	var profile = CarProfile.new()
	profile.id = entry.id
	profile.display_name = entry.name
	profile.brand = entry.brand
	profile.year = entry.year
	profile.subtitle = "%s · %d" % [entry.brand, entry.year]
	profile.model_folder = entry.folder
	profile.power_ps = entry.ps
	profile.drive_text = entry.drive
	profile.engine_text = entry.engine
	profile.paint_colors = [Color(0.75, 0.08, 0.09), Color(0.86, 0.87, 0.86), Color(0.02, 0.05, 0.12), Color(0.62, 0.64, 0.66), Color(0.92, 0.55, 0.02), Color(0.03, 0.32, 0.6)]
	var path = CarModel.model_path(profile)
	if path == "":
		return entry.id + ": NO MODEL FOUND (" + entry.folder + ")"
	var scene = load(path) as PackedScene
	if scene == null:
		return entry.id + ": LOAD FAILED " + path
	var inst = scene.instantiate()
	add_child(inst)
	var meshes = _meshes(inst)
	var wheels = []
	for mi in meshes:
		if _has_word(mi):
			wheels.append(mi)
	var full = _box(meshes)
	var radius = _wheel_radius(wheels)
	var names = []
	for mi in wheels:
		names.append(mi.name)
	var filtered_names = []
	var reliable = _filter_wheels(wheels, full.size, filtered_names)
	var wbox = _box(wheels)
	var scale = 1.0
	var wheelbase = 0.0
	var track = 0.0
	var notes = ""
	if reliable:
		var wheel_d = radius * 2.0
		var wb_model = maxf(full.size.z - wheel_d, full.size.z * 0.5)
		scale = 1.0 if (wb_model > 1.2 and wb_model < 4.5) else 2.7 / maxf(wb_model, 0.01)
		wheelbase = wb_model * scale
		track = maxf(wbox.size.x - wheel_d * 0.55, wbox.size.x * 0.55) * scale
		profile.wheel_parts = PackedStringArray(filtered_names)
		notes = "wheels_ok"
	else:
		scale = 4.6 / maxf(full.size.z, 0.01)
		wheelbase = 2.7
		track = 1.6
		radius = 0.33 / maxf(scale, 0.001)
		notes = "NO/WIDE WHEELS"
	# Always set wheel_parts if we have at least 2 wheels (minimum for a car)
	if wheels.size() >= 2:
		profile.wheel_parts = PackedStringArray(names)
	var wheelbase_real = clampf(wheelbase, 2.3, 3.1)
	var track_real = clampf(track, 1.4, 1.75)
	var radius_real = clampf(radius * scale, 0.28, 0.40)
	profile.wheelbase = wheelbase_real
	profile.track_front = track_real
	profile.track_rear = track_real
	profile.wheel_radius = radius_real
	var length = maxf(full.size.z * scale, wheelbase_real * 1.35)
	var width = clampf(full.size.x * scale, track_real + 0.12, 2.3)
	var height = clampf(full.size.y * scale, 1.15, 2.0)
	profile.body_size = Vector3(width * 0.96, height * 0.55, length * 0.98)
	profile.body_center = Vector3(0.0, height * 0.27, 0.0)
	profile.cabin_size = Vector3(width * 0.7, height * 0.42, length * 0.5)
	profile.cabin_center = Vector3(0.0, height * 0.74, -length * 0.04)
	inst.queue_free()
	var result = "%s | scale=%.3f wheelbase=%.2f track=%.2f radius=%.2f size=%.2f x %.2f x %.2f | %s | wheels=[%s]" % [entry.id, scale, profile.wheelbase, profile.track_front, profile.wheel_radius, profile.body_size.x, height, profile.body_size.z, notes, ", ".join(names)]
	ResourceSaver.save(profile, "res://cars/" + entry.id + ".tres")
	return result

func _box(meshes)
	var box = AABB()
	var first = true
	for var mi in meshes:
		var piece = mi.global_transform * mi.get_aabb()
		box = piece if first else box.merge(piece)
		first = false
	return box
}

func _wheel_radius(wheels) -> float:
	var halves = []
	for var mi in wheels:
		halves.append((mi.global_transform * mi.get_aabb()).size.y * 0.5)
	if halves.size() == 0:
		return 0.0
	halves.sort()
	return halves[halves.size() / 2]

func _filter_wheels(wheels: Array[MeshInstance3D], full_size: Vector3, out_names: Array[String]) -> bool:
	if wheels.is_empty():
		return false
	var dims: Array[float] = []
	for var i in range(wheels.size()):
		var mi := wheels[i]
		var aabb := mi.global_transform * mi.get_aabb()
		dims.append(maxf(aabb.size.x, aabb.size.z))
	var kept: Array[MeshInstance3D] = []
	for var idx in range(dims.size()):
		var ratio := dims[idx] / maxf(full_size.x, full_size.z)
		if ratio < 0.30:
			kept.append(wheels[idx])
		else:
			break
	if kept.is_empty():
		return false
	out_names.clear()
	for var mi in kept:
		out_names.append(String(mi.name))
	return true

func _meshes(node) {
	var result = Array[MeshInstance3D]()
	var stack = Array[Node]()
	stack.push_back(node)
	while stack.size() > 0:
		var current = stack.pop_back()
		if current is MeshInstance3D and current.mesh:
			result.append(current)
		stack.append_array(current.get_children())
	return result
}

func _has_word(mi: MeshInstance3D) -> bool:
	var tokens = _tokens(String(mi.name))
	for var s in mi.mesh.get_surface_count():
		var mat = mi.mesh.surface_get_material(s)
		if mat:
			tokens.append_array(_tokens(mat.resource_name))
	for var t in tokens:
		if t in SKIP_WORDS:
			return false
	for var t in tokens:
		for var root in WHEEL_WORDS:
			if t == root or t.begins_with(root):
				return true
	return false

func _tokens(text: String) -> PackedStringArray:
	var out = PackedStringArray()
	var current = ""
	for var ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			current += ch
		elif current != "":
			out.append(current)
			current = ""
	if current != "":
		out.append(current)
	return out