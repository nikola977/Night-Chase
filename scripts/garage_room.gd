extends Node3D
## Werkstatt um das Auto, solange die Garage offen ist: eine alte Reifenwerkstatt
## in Rot und Grau (Vorbild: Nicks Fotos).
##  - Boden: Betonplatten mit Fugen, rote Farbkante an den Wänden, Bodenabläufe, Ölfleck
##  - Wände: heller, rissiger Beton (prozedurale Textur), Kabelkanäle
##  - Decke: Holzdielen mit drei Balken, vier Leuchtstoffröhren
##  - hinten: lange rote Werkbank mit Schubladen, drei Lochwände mit Werkzeug, Poster
##  - rechts: rotes Reifenregal, Montagegerät, Fässer, Reifen an der Wand
##  - links: rotes Regal mit Kannen und Schläuchen, Kran, Palette, Tür mit Fenster
##  - vorne (+Z): geschlossenes Rolltor (kein Glas mehr)
## Alles aus Kisten, Zylindern und Tori gebaut, Texturen prozedural erzeugt – keine
## Bilddateien, also keine Lizenzfragen. Dieselbe Werkstatt gilt für ALLE Garagen:
## sie wird bei jedem Öffnen gebaut und beim Schließen wieder entfernt.

const WIDTH: float = 18.0
const DEPTH: float = 18.0
const HEIGHT: float = 4.2
## Wandstärke
const WALL: float = 0.3
## Der Boden liegt so viel über dem Grund unter der Werkstatt (m). Der Grund (Straße,
## Gelände) und die Parkplatz-Linien (3 cm über der Platte) liegen sonst genau in einer
## Ebene mit den Bodenplatten und flackern beim Fahren und Drehen der Kamera.
const FLOOR_LIFT: float = 0.04
## Rot der Werkstatt: Schränke, Regale, Kran, Rahmen
const RED: Color = Color(0.66, 0.11, 0.11)


## Baut die Werkstatt. center = Mitte des Autos, floor_y = Höhe des Bodens (Räder),
## yaw = Blickrichtung des Autos: die Halle dreht sich mit, sonst steht das Auto quer
## auf der Hebebühne (die Halle war immer an der Weltachse ausgerichtet)
static func build(center: Vector3, floor_y: float, yaw: float = 0.0) -> Node3D:
	var room := Node3D.new()
	room.name = "GarageRoom"
	room.position = Vector3(center.x, floor_y + FLOOR_LIFT, center.z)
	room.rotation.y = yaw

	# --- Materialien -----------------------------------------------------------
	var wall_material := _concrete(Color(0.93, 0.92, 0.88), 0.92, 11, Vector3(2.4, 1.6, 1.0))
	var slab_materials: Array[Material] = [
		_concrete(Color(0.53, 0.53, 0.53), 0.78, 3, Vector3.ONE),
		_concrete(Color(0.48, 0.48, 0.485), 0.78, 7, Vector3.ONE),
		_concrete(Color(0.57, 0.565, 0.56), 0.78, 13, Vector3.ONE),
	]
	var wood := _concrete(Color(0.68, 0.54, 0.39), 0.78, 21, Vector3(9.0, 1.0, 1.0))
	var beam := _material(Color(0.42, 0.31, 0.21), 0.85)
	var red := _material(RED, 0.4, Color(0, 0, 0), 0.2)
	var red_dark := _material(Color(0.38, 0.06, 0.06), 0.55)
	var steel := _material(Color(0.17, 0.18, 0.2), 0.35, Color(0, 0, 0), 0.65)
	var steel_light := _material(Color(0.6, 0.62, 0.65), 0.3, Color(0, 0, 0), 0.85)
	var dark := _material(Color(0.07, 0.07, 0.08), 0.85)
	var rubber := _material(Color(0.045, 0.045, 0.05), 0.92)
	var blue := _material(Color(0.11, 0.28, 0.52), 0.55)
	var board := _material(Color(0.96, 0.95, 0.92), 0.85)
	board.albedo_texture = _dot_texture()
	board.uv1_scale = Vector3(2.0, 1.2, 1.0)
	var lamp_material := _material(Color(1.0, 0.98, 0.93), 0.4, Color(1.0, 0.95, 0.85))
	lamp_material.emission_energy_multiplier = 2.6

	_floor(room, slab_materials, red_dark, steel, dark)
	_walls(room, wall_material, dark, steel)
	_ceiling(room, wood, beam, dark, lamp_material, steel)
	_lighting(room)
	_tool_wall(room, red, red_dark, steel, steel_light, dark, board, blue, wood, lamp_material)
	_tire_corner(room, red, red_dark, steel, steel_light, rubber, blue)
	_left_corner(room, red, red_dark, steel, steel_light, dark, blue, wood)
	_gate(room, steel, dark)
	_front_details(room, red, red_dark, steel, steel_light, rubber, blue, dark)
	return room


# ---------------------------------------------------------------------------
# Boden: Betonplatten, rote Farbkante, Hebebühnen-Platte mit Warnstreifen
# ---------------------------------------------------------------------------
static func _floor(parent: Node3D, slabs: Array[Material], red: Material, steel: Material,
		dark: Material) -> void:
	# Dunkle Fuge unter den Platten (scheint in den 3,5 cm breiten Ritzen durch)
	_box(parent, Vector3(WIDTH, 0.3, DEPTH), Vector3(0.0, -0.16, 0.0),
		_material(Color(0.09, 0.09, 0.095), 0.9))
	var count := 8
	var tile := WIDTH / float(count)
	for ix in count:
		for iz in count:
			var material: Material = slabs[(ix * 2 + iz) % slabs.size()]
			var x := -WIDTH * 0.5 + tile * (float(ix) + 0.5)
			var z := -DEPTH * 0.5 + tile * (float(iz) + 0.5)
			_box(parent, Vector3(tile - 0.035, 0.06, tile - 0.035), Vector3(x, -0.03, z), material)
	# Rote Farbkante wie im Vorbild, rundherum 60 cm von der Wand
	var edge := 0.62
	_box(parent, Vector3(WIDTH - edge * 2.0, 0.012, 0.12),
		Vector3(0.0, 0.006, -DEPTH * 0.5 + edge), red)
	_box(parent, Vector3(WIDTH - edge * 2.0, 0.012, 0.12),
		Vector3(0.0, 0.006, DEPTH * 0.5 - edge), red)
	_box(parent, Vector3(0.12, 0.012, DEPTH - edge * 2.0),
		Vector3(-WIDTH * 0.5 + edge, 0.006, 0.0), red)
	_box(parent, Vector3(0.12, 0.012, DEPTH - edge * 2.0),
		Vector3(WIDTH * 0.5 - edge, 0.006, 0.0), red)
	# Hebebühne: Stahlplatte bündig im Boden, rundum gelb-schwarze Warnstreifen.
	# Längs unter dem Auto (das Auto steht in Z der Halle und ist rund 4,6 m lang),
	# nicht quer: sonst ragt es vorn und hinten über die Platte hinaus
	var plate_length := 5.4
	var plate_width := 3.4
	var plate := _box(parent, Vector3(plate_width, 0.012, plate_length), Vector3.ZERO, steel)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hazard := _material(Color(1.0, 1.0, 1.0), 0.7)
	hazard.albedo_texture = _stripe_texture()
	hazard.uv1_scale = Vector3(6.0, 1.0, 1.0)
	# Lange Streifen links und rechts, kurze Streifen vorn und hinten
	for x in [-1.87, 1.87]:
		_box(parent, Vector3(0.22, 0.012, plate_length + 0.44), Vector3(x, 0.0, 0.0), hazard)
	for z in [-2.81, 2.81]:
		_box(parent, Vector3(plate_width + 0.04, 0.012, 0.22), Vector3(0.0, 0.0, z), hazard)
	# Bodenabläufe mit Schlitzen
	for position in [Vector3(-4.2, 0.006, 4.6), Vector3(3.6, 0.006, -3.2)]:
		_box(parent, Vector3(0.6, 0.02, 0.6), position,
			_material(Color(0.28, 0.29, 0.3), 0.6, Color(0, 0, 0), 0.5))
		for i in 3:
			_box(parent, Vector3(0.5, 0.008, 0.03), position + Vector3(0.0, 0.012, -0.12 + i * 0.12), dark)
	# Ölfleck (glänzend, wie im Vorbild)
	var stain := _cylinder(parent, 1.05, 0.006, Vector3(3.7, 0.004, 4.3),
		_material(Color(0.035, 0.035, 0.04), 0.12, Color(0, 0, 0), 0.3))
	stain.scale = Vector3(1.0, 1.0, 0.7)
	_cylinder(parent, 0.45, 0.006, Vector3(4.4, 0.004, 3.6),
		_material(Color(0.04, 0.04, 0.045), 0.15, Color(0, 0, 0), 0.3))


# ---------------------------------------------------------------------------
# Wände (vier Stück, damit die Halle geschlossen ist) und Kabelkanäle
# ---------------------------------------------------------------------------
static func _walls(parent: Node3D, wall: Material, dark: Material, steel: Material) -> void:
	var half := WIDTH * 0.5
	var deep := DEPTH * 0.5
	_box(parent, Vector3(WIDTH, HEIGHT, WALL), Vector3(0.0, HEIGHT * 0.5, -deep + WALL * 0.5), wall)
	_box(parent, Vector3(WALL, HEIGHT, DEPTH), Vector3(-half + WALL * 0.5, HEIGHT * 0.5, 0.0), wall)
	_box(parent, Vector3(WALL, HEIGHT, DEPTH), Vector3(half - WALL * 0.5, HEIGHT * 0.5, 0.0), wall)
	_box(parent, Vector3(WIDTH, HEIGHT, WALL), Vector3(0.0, HEIGHT * 0.5, deep - WALL * 0.5), wall)
	# Kabelkanal waagerecht an der Rückwand und drei senkrechte Leitungen
	var back := -deep + WALL
	_box(parent, Vector3(WIDTH - 1.0, 0.05, 0.05), Vector3(0.0, HEIGHT - 0.4, back + 0.04), dark)
	for x in [-7.9, 4.6, 7.4]:
		_box(parent, Vector3(0.05, HEIGHT - 0.4, 0.05), Vector3(x, (HEIGHT - 0.4) * 0.5, back + 0.04), dark)
	# Zwei Verteilerdosen an der Rückwand
	for x in [-7.9, 4.6]:
		_box(parent, Vector3(0.2, 0.28, 0.09), Vector3(x, 2.6, back + 0.06), dark)
		_box(parent, Vector3(0.1, 0.06, 0.03), Vector3(x, 2.6, back + 0.12), steel)
	# Steckdosenleiste über der Werkbank
	_box(parent, Vector3(1.4, 0.09, 0.05), Vector3(-6.9, 1.5, back + 0.04), dark)


# ---------------------------------------------------------------------------
# Decke: Holzdielen, drei Balken, vier Leuchtstoffröhren
# ---------------------------------------------------------------------------
static func _ceiling(parent: Node3D, wood: Material, beam: Material, dark: Material,
		lamp: Material, steel: Material) -> void:
	_box(parent, Vector3(WIDTH, 0.24, DEPTH), Vector3(0.0, HEIGHT + 0.12, 0.0), wood)
	# Fugen der Dielen (alle 90 cm quer)
	var planks := 20
	for i in planks + 1:
		var x := -WIDTH * 0.5 + WIDTH * float(i) / float(planks)
		_box(parent, Vector3(0.02, 0.006, DEPTH), Vector3(x, HEIGHT - 0.004, 0.0), dark)
	# Drei Holzbalken quer unter der Decke
	for z in [-4.6, 0.0, 4.6]:
		_box(parent, Vector3(WIDTH, 0.26, 0.28), Vector3(0.0, HEIGHT - 0.13, z), beam)
	# Leuchtstoffröhren: Gehäuse, leuchtende Röhre, zwei Aufhänger
	for spot in [Vector2(-4.6, -5.4), Vector2(2.2, -5.4), Vector2(-4.6, 3.2), Vector2(2.2, 3.2)]:
		var pos := Vector3(spot.x, HEIGHT - 0.34, spot.y)
		_box(parent, Vector3(2.7, 0.16, 0.34), pos, steel)
		_box(parent, Vector3(2.5, 0.05, 0.14), pos + Vector3(0.0, -0.1, 0.0), lamp)
		for dx in [-1.0, 1.0]:
			_box(parent, Vector3(0.04, 0.3, 0.04), pos + Vector3(dx, 0.2, 0.0), steel)


# ---------------------------------------------------------------------------
# Licht: vier warme Strahler unter den Röhren, Fülllicht, zwei weiche Lichter
# ---------------------------------------------------------------------------
static func _lighting(parent: Node3D) -> void:
	for spot in [Vector2(-4.6, -5.4), Vector2(2.2, -5.4), Vector2(-4.6, 3.2), Vector2(2.2, 3.2)]:
		var light := SpotLight3D.new()
		light.position = Vector3(spot.x, HEIGHT - 0.55, spot.y)
		light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		light.light_color = Color(1.0, 0.95, 0.86)
		light.light_energy = 5.2
		light.spot_range = 12.0
		light.spot_angle = 58.0
		light.shadow_enabled = false
		parent.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 3.2, 0.0)
	fill.light_color = Color(1.0, 0.97, 0.92)
	fill.light_energy = 1.25
	fill.omni_range = 18.0
	fill.shadow_enabled = false
	parent.add_child(fill)
	var back_fill := OmniLight3D.new()
	back_fill.position = Vector3(-1.0, 2.6, -6.8)
	back_fill.light_color = Color(1.0, 0.96, 0.9)
	back_fill.light_energy = 0.45
	back_fill.omni_range = 10.0
	back_fill.shadow_enabled = false
	parent.add_child(back_fill)


# ---------------------------------------------------------------------------
# Rückwand: rote Werkbank, drei Lochwände voll Werkzeug, Poster
# ---------------------------------------------------------------------------
static func _tool_wall(parent: Node3D, red: Material, red_dark: Material, steel: Material,
		steel_light: Material, dark: Material, board: Material, blue: Material,
		wood: Material, lamp: Material) -> void:
	var wall_z := -DEPTH * 0.5 + WALL
	var span := 9.6
	var center_x := -0.9
	var front_z := wall_z + 0.66
	# Werkbank: roter Korpus, dunkler Sockel, Stahlplatte
	_box(parent, Vector3(span, 0.82, 0.6), Vector3(center_x, 0.5, wall_z + 0.33), red)
	_box(parent, Vector3(span, 0.1, 0.58), Vector3(center_x, 0.05, wall_z + 0.32), dark)
	_box(parent, Vector3(span + 0.1, 0.09, 0.72), Vector3(center_x, 0.96, wall_z + 0.34), steel)
	# Schubladen: fünf Fächer mit dunklen Trennern und hellen Griffen
	var bay := span / 5.0
	for i in 6:
		var x := center_x - span * 0.5 + bay * float(i)
		_box(parent, Vector3(0.05, 0.82, 0.62), Vector3(x, 0.5, wall_z + 0.34), dark)
	for i in 5:
		var x := center_x - span * 0.5 + bay * (float(i) + 0.5)
		for y in [0.34, 0.62]:
			_box(parent, Vector3(bay - 0.32, 0.05, 0.05), Vector3(x, y, front_z + 0.01), steel_light)
	# Werkzeug auf der Platte: Wasserwaage, Baupläne, Schraubenschlüssel, Kannen
	_box(parent, Vector3(1.15, 0.1, 0.14), Vector3(-4.4, 1.03, wall_z + 0.4), red)
	_box(parent, Vector3(0.66, 0.012, 0.5), Vector3(-1.5, 1.01, wall_z + 0.45), blue)
	_box(parent, Vector3(0.5, 0.012, 0.36), Vector3(-1.15, 1.015, wall_z + 0.3), blue)
	for i in 3:
		_box(parent, Vector3(0.34, 0.025, 0.06), Vector3(0.9 + i * 0.42, 1.02, wall_z + 0.42), steel_light)
	_box(parent, Vector3(0.5, 0.03, 0.06), Vector3(2.9, 1.02, wall_z + 0.5), steel_light)
	_box(parent, Vector3(0.3, 0.36, 0.22), Vector3(-2.7, 1.15, wall_z + 0.35), red_dark)
	_box(parent, Vector3(0.34, 0.26, 0.3), Vector3(-5.6, 1.1, wall_z + 0.4), wood)
	# Drei Lochwände mit Muster (Löcher als Textur)
	for i in 3:
		var panel := _box(parent, Vector3(2.15, 1.35, 0.05),
			Vector3(-4.9 + float(i) * 2.5, 2.4, wall_z + 0.09), board)
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lochwand 1: rote Wasserwaage, zwei Spachtel, Kreppband, Holzschalen, Winkel
	var b1 := -4.9
	_box(parent, Vector3(1.55, 0.15, 0.05), Vector3(b1, 2.92, wall_z + 0.13), red)
	var green := _material(Color(0.6, 0.85, 0.35), 0.35)
	for dx in [-0.45, 0.0, 0.45]:
		_box(parent, Vector3(0.1, 0.06, 0.02), Vector3(b1 + dx, 2.92, wall_z + 0.16), green)
	for dx in [-0.42, -0.16]:
		_box(parent, Vector3(0.17, 0.3, 0.03), Vector3(b1 + dx, 2.3, wall_z + 0.13), dark)
		_box(parent, Vector3(0.06, 0.2, 0.03), Vector3(b1 + dx, 2.56, wall_z + 0.13), red)
	_cylinder(parent, 0.11, 0.06, Vector3(b1 - 0.72, 2.36, wall_z + 0.14), blue, 90.0, Vector3.RIGHT)
	_box(parent, Vector3(0.34, 0.12, 0.14), Vector3(b1 - 0.66, 2.02, wall_z + 0.14), wood)
	_box(parent, Vector3(0.3, 0.1, 0.12), Vector3(b1 - 0.34, 2.02, wall_z + 0.14), wood)
	_box(parent, Vector3(0.05, 0.55, 0.03), Vector3(b1 + 0.4, 2.18, wall_z + 0.13), wood)
	_box(parent, Vector3(0.42, 0.05, 0.03), Vector3(b1 + 0.22, 1.94, wall_z + 0.13), wood)
	# Lochwand 2: zwei Spachtel, Schraubenschlüssel-Halter
	var b2 := -2.4
	for dx in [-0.5, -0.2]:
		_box(parent, Vector3(0.18, 0.32, 0.03), Vector3(b2 + dx, 2.3, wall_z + 0.13), dark)
		_box(parent, Vector3(0.06, 0.22, 0.03), Vector3(b2 + dx, 2.57, wall_z + 0.13), red)
	_box(parent, Vector3(0.06, 0.72, 0.03), Vector3(b2 + 0.55, 2.4, wall_z + 0.13), dark)
	for i in 4:
		_box(parent, Vector3(0.4, 0.045, 0.03),
			Vector3(b2 + 0.55, 2.7 - float(i) * 0.18, wall_z + 0.14), steel_light)
	_cylinder(parent, 0.1, 0.06, Vector3(b2 - 0.72, 2.5, wall_z + 0.14), red_dark, 90.0, Vector3.RIGHT)
	# Lochwand 3: Hämmer, Bürste, Pinsel, kleine Schalen
	var b3 := 0.1
	for dx in [-0.55, -0.1]:
		_box(parent, Vector3(0.05, 0.42, 0.03), Vector3(b3 + dx, 2.3, wall_z + 0.13), wood)
		_box(parent, Vector3(0.24, 0.08, 0.06), Vector3(b3 + dx, 2.52, wall_z + 0.14), dark)
	_box(parent, Vector3(0.05, 0.36, 0.03), Vector3(b3 + 0.3, 2.28, wall_z + 0.13), wood)
	_box(parent, Vector3(0.1, 0.16, 0.06), Vector3(b3 + 0.3, 2.06, wall_z + 0.14), red_dark)
	_cylinder(parent, 0.11, 0.06, Vector3(b3 + 0.62, 2.5, wall_z + 0.14), blue, 90.0, Vector3.RIGHT)
	_box(parent, Vector3(0.46, 0.12, 0.14), Vector3(b3 + 0.55, 2.0, wall_z + 0.14), wood)
	# Poster links und rechts der Lochwände
	_poster(parent, Vector3(-7.6, 2.55, wall_z + 0.09), Vector2(0.85, 1.15),
		Color(0.72, 0.18, 0.14), "РУКОМ", "НЕ ТОРГУЙСЯ", Color(0.95, 0.9, 0.8))
	_poster(parent, Vector3(5.4, 2.5, wall_z + 0.09), Vector2(0.8, 1.1),
		Color(0.85, 0.8, 0.66), "CLASSIC", "AUTO REPAIR", Color(0.3, 0.12, 0.1))
	# Zwei lange Arbeitsleuchten über der Werkbank (wie im Vorbild)
	for x in [-4.4, 1.6]:
		_box(parent, Vector3(2.4, 0.16, 0.3), Vector3(x, 3.35, wall_z + 0.32), _material(Color(0.8, 0.8, 0.78), 0.4))
		_box(parent, Vector3(2.2, 0.05, 0.12), Vector3(x, 3.25, wall_z + 0.32), lamp)
		_box(parent, Vector3(0.05, 0.5, 0.05), Vector3(x - 0.9, 3.65, wall_z + 0.16), dark)


# ---------------------------------------------------------------------------
# Rechts: rotes Reifenregal, Montagegerät, Fässer, Reifen an der Wand
# ---------------------------------------------------------------------------
static func _tire_corner(parent: Node3D, red: Material, red_dark: Material, steel: Material,
		steel_light: Material, rubber: Material, blue: Material) -> void:
	var wall_x := WIDTH * 0.5 - WALL
	var z := -4.2
	# Rahmen aus roten Vierkantrohren
	for dz in [-2.05, 2.05]:
		_box(parent, Vector3(0.1, 2.9, 0.1), Vector3(wall_x - 0.5, 1.45, z + dz), red)
	# Drei Böden mit je drei liegenden Reifen
	for i in 3:
		var y := 0.5 + float(i) * 0.85
		_box(parent, Vector3(0.9, 0.07, 4.2), Vector3(wall_x - 0.5, y, z), steel)
		for j in 3:
			var tz := z - 1.35 + float(j) * 1.25
			var tx := wall_x - 0.48
			_cylinder(parent, 0.36, 0.32, Vector3(tx, y + 0.42, tz), rubber, 90.0, Vector3(0, 0, 1))
			_cylinder(parent, 0.21, 0.34, Vector3(tx, y + 0.42, tz), steel_light, 90.0, Vector3(0, 0, 1))
	# Reifen an die Wand gelehnt
	var leaning := _cylinder(parent, 0.34, 0.24, Vector3(wall_x - 0.55, 0.36, 2.9), rubber,
		90.0, Vector3(0, 0, 1))
	leaning.basis = Basis(Vector3(1, 0, 0), deg_to_rad(-12.0)) * leaning.basis
	# Montagegerät: roter Sockel, Säule, Arm, Reifen auf dem Teller
	var base := Vector3(6.4, 0.0, 5.4)
	_cylinder(parent, 0.55, 0.3, base + Vector3(0, 0.15, 0), red)
	_box(parent, Vector3(0.22, 1.3, 0.22), base + Vector3(-0.2, 0.75, 0.0), red)
	_box(parent, Vector3(0.95, 0.14, 0.16), base + Vector3(-0.15, 1.42, 0.0), red)
	_cylinder(parent, 0.32, 0.24, base + Vector3(-0.15, 0.8, 0.0), rubber, 90.0, Vector3(0, 0, 1))
	_cylinder(parent, 0.18, 0.26, base + Vector3(-0.15, 0.8, 0.0), steel_light, 90.0, Vector3(0, 0, 1))
	# Blaue Fässer in der Ecke
	for dz in [-7.9, -7.0]:
		_cylinder(parent, 0.32, 0.9, Vector3(7.7, 0.45, dz), blue)
		_cylinder(parent, 0.33, 0.06, Vector3(7.7, 0.72, dz), steel)
	# Feuerlöscher und Werkzeugwagen
	_cylinder(parent, 0.13, 0.55, Vector3(wall_x - 0.5, 0.28, 6.9), red_dark)
	_box(parent, Vector3(0.6, 1.1, 0.8), Vector3(4.9, 0.55, -7.9), red)
	for i in 3:
		_box(parent, Vector3(0.5, 0.04, 0.05), Vector3(4.9, 0.3 + float(i) * 0.28, -7.48), steel_light)


# ---------------------------------------------------------------------------
# Links: Regal mit Kannen und Schläuchen, Kran, Palette, Tür mit Fenster
# ---------------------------------------------------------------------------
static func _left_corner(parent: Node3D, red: Material, red_dark: Material, steel: Material,
		steel_light: Material, dark: Material, blue: Material, wood: Material) -> void:
	var wall_x := -WIDTH * 0.5 + WALL
	# Regal: vier rote Böden, zwei sichtbare Pfosten
	var shelf_z := -2.6
	for y in [0.35, 1.05, 1.75, 2.45]:
		_box(parent, Vector3(0.72, 0.08, 2.9), Vector3(wall_x + 0.4, y, shelf_z), red)
	for dz in [-1.4, 1.4]:
		_box(parent, Vector3(0.08, 2.75, 0.08), Vector3(wall_x + 0.74, 1.38, shelf_z + dz), red)
	# Kannen, blaue Schlauchrollen, Pappkartons
	for dz in [-0.5, 0.5]:
		_box(parent, Vector3(0.34, 0.46, 0.26), Vector3(wall_x + 0.36, 1.35, shelf_z + dz), red)
		_box(parent, Vector3(0.1, 0.1, 0.12), Vector3(wall_x + 0.36, 1.62, shelf_z + dz), dark)
	for dz in [-0.9, 0.0, 0.9]:
		_torus(parent, 0.2, 0.09, Vector3(wall_x + 0.34, 2.6, shelf_z + dz), blue, 90.0)
	_box(parent, Vector3(0.5, 0.36, 0.5), Vector3(wall_x + 0.36, 2.15, shelf_z - 0.6), wood)
	# Kran (Motorheber): Grundrahmen, Säule, Ausleger mit Kette
	var hoist := Vector3(-7.0, 0.0, 2.4)
	_box(parent, Vector3(0.95, 0.14, 1.7), hoist + Vector3(0.0, 0.07, 0.0), red_dark)
	for dz in [-0.7, 0.7]:
		var wheel := _cylinder(parent, 0.12, 0.1, hoist + Vector3(0.25, 0.12, dz), dark, 90.0,
			Vector3(0, 0, 1))
		wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cylinder(parent, 0.09, 2.1, hoist + Vector3(-0.1, 1.05, 0.0), red)
	var boom := _box(parent, Vector3(1.8, 0.13, 0.15), hoist + Vector3(0.65, 2.0, 0.0), red)
	boom.rotation_degrees = Vector3(0.0, 0.0, -8.0)
	_cylinder(parent, 0.02, 1.0, hoist + Vector3(1.4, 1.45, 0.0), steel)
	_box(parent, Vector3(0.12, 0.12, 0.12), hoist + Vector3(1.4, 0.92, 0.0), steel_light)
	# Palette mit Holzplanken
	for i in 5:
		_box(parent, Vector3(1.2, 0.05, 0.16), Vector3(-7.9, 0.17, 4.6 + float(i) * 0.21), wood)
	for dz in [4.55, 5.35]:
		_box(parent, Vector3(1.2, 0.14, 0.14), Vector3(-7.9, 0.07, dz), wood)
	# Tür mit Fenster an der linken Wand, vorne
	var door_z := 6.9
	_box(parent, Vector3(0.06, 2.25, 1.2), Vector3(wall_x + 0.05, 1.12, door_z),
		_material(Color(0.56, 0.58, 0.56), 0.55, Color(0, 0, 0), 0.2))
	for dz in [-0.66, 0.66]:
		_box(parent, Vector3(0.07, 2.36, 0.12), Vector3(wall_x + 0.06, 1.18, door_z + dz),
			_material(Color(0.4, 0.41, 0.4), 0.6))
	_box(parent, Vector3(0.07, 0.12, 1.44), Vector3(wall_x + 0.06, 2.3, door_z),
		_material(Color(0.4, 0.41, 0.4), 0.6))
	_box(parent, Vector3(0.03, 0.6, 0.5), Vector3(wall_x + 0.09, 1.62, door_z),
		_material(Color(0.16, 0.2, 0.24), 0.12, Color(0, 0, 0), 0.6))
	_box(parent, Vector3(0.07, 0.05, 0.16), Vector3(wall_x + 0.1, 1.02, door_z + 0.42), steel_light)
	# Zwei Poster neben der Tür
	_poster(parent, Vector3(wall_x + 0.1, 2.2, 4.6), Vector2(0.7, 0.95),
		Color(0.8, 0.42, 0.2), "HARD WORK", "HAPPY WORK", Color(0.2, 0.15, 0.12), 90.0)


# ---------------------------------------------------------------------------
# Vorne: geschlossenes Rolltor mit Rahmen, Schwelle und Kasten
# ---------------------------------------------------------------------------
static func _gate(parent: Node3D, steel: Material, dark: Material) -> void:
	var front := DEPTH * 0.5 - WALL
	var width := 5.6
	var height := 3.75
	for x in [-width * 0.5 - 0.1, width * 0.5 + 0.1]:
		_box(parent, Vector3(0.2, height, 0.18), Vector3(x, height * 0.5, front - 0.09), dark)
	_box(parent, Vector3(width + 0.4, 0.26, 0.2), Vector3(0.0, height + 0.13, front - 0.1), dark)
	# Lamellen, abwechselnd zwei Grautöne
	var shade_a := _material(Color(0.4, 0.42, 0.43), 0.45, Color(0, 0, 0), 0.5)
	var shade_b := _material(Color(0.34, 0.36, 0.37), 0.45, Color(0, 0, 0), 0.5)
	var slats := 15
	var slat_height := height / float(slats)
	for i in slats:
		var y := height - (float(i) + 0.5) * slat_height
		_box(parent, Vector3(width, slat_height - 0.02, 0.06), Vector3(0.0, y, front - 0.04),
			shade_a if i % 2 == 0 else shade_b)
	# Kasten für die Wickelwelle, Schwelle aus Stahl
	_box(parent, Vector3(width + 0.5, 0.45, 0.36), Vector3(0.0, height + 0.4, front - 0.18), dark)
	_box(parent, Vector3(width + 0.4, 0.06, 0.5), Vector3(0.0, 0.01, front - 0.2), steel)


# ---------------------------------------------------------------------------
# Vorne an der Wand: Hängeschrank, Werkzeugwagen, Wagenheber, Reifenstapel, Schlauchrolle
# ---------------------------------------------------------------------------
static func _front_details(parent: Node3D, red: Material, red_dark: Material, steel: Material,
		steel_light: Material, rubber: Material, blue: Material, dark: Material) -> void:
	var front := DEPTH * 0.5 - WALL
	# Hängeschrank links neben dem Tor
	_box(parent, Vector3(1.9, 0.9, 0.4), Vector3(-4.3, 2.55, front - 0.21), red)
	_box(parent, Vector3(0.03, 0.82, 0.03), Vector3(-4.3, 2.55, front - 0.41), dark)
	for dx in [-0.45, 0.45]:
		_box(parent, Vector3(0.04, 0.5, 0.04), Vector3(-4.3 + dx, 2.55, front - 0.43), steel_light)
	# Werkzeugwagen auf Rollen
	var cart := Vector3(-4.6, 0.0, 6.4)
	_box(parent, Vector3(0.72, 1.05, 1.0), cart + Vector3(0.0, 0.6, 0.0), red)
	_box(parent, Vector3(0.76, 0.07, 1.04), cart + Vector3(0.0, 1.13, 0.0), steel)
	for i in 3:
		_box(parent, Vector3(0.5, 0.04, 0.05), cart + Vector3(0.0, 0.35 + float(i) * 0.28, 0.52),
			steel_light)
	for dx in [-0.28, 0.28]:
		for dz in [-0.4, 0.4]:
			_cylinder(parent, 0.06, 0.1, cart + Vector3(dx, 0.06, dz), dark, 90.0, Vector3(0, 0, 1))
	# Wagenheber
	var jack := Vector3(-6.4, 0.0, 6.8)
	_box(parent, Vector3(0.42, 0.12, 0.9), jack + Vector3(0.0, 0.06, 0.0), red_dark)
	var arm := _box(parent, Vector3(0.16, 0.12, 0.95), jack + Vector3(0.0, 0.22, 0.1), red)
	arm.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
	_cylinder(parent, 0.03, 1.1, jack + Vector3(0.0, 0.45, -0.75), steel, 90.0, Vector3.RIGHT)
	# Reifenstapel rechts
	for i in 4:
		_cylinder(parent, 0.34, 0.24, Vector3(6.9, 0.12 + float(i) * 0.25, 6.4), rubber)
		_cylinder(parent, 0.2, 0.26, Vector3(6.9, 0.12 + float(i) * 0.25, 6.4), steel_light)
	# Schlauchrolle an der Wand
	_torus(parent, 0.28, 0.1, Vector3(4.9, 2.4, front - 0.22), blue, 90.0)
	_box(parent, Vector3(0.12, 0.12, 0.14), Vector3(4.9, 2.4, front - 0.12), steel)


# ---------------------------------------------------------------------------
# Poster: farbige Fläche mit zwei Textzeilen (auch gedreht für die Seitenwand)
# ---------------------------------------------------------------------------
static func _poster(parent: Node3D, position: Vector3, size: Vector2, background: Color,
		title: String, subtitle: String, text_color: Color, yaw: float = 0.0) -> void:
	var pivot := Node3D.new()
	pivot.position = position
	pivot.rotation_degrees = Vector3(0.0, yaw, 0.0)
	parent.add_child(pivot)
	_box(pivot, Vector3(size.x, size.y, 0.03), Vector3.ZERO, _material(background, 0.9))
	var label := Label3D.new()
	label.text = title + "\n" + subtitle
	label.font_size = 54
	label.pixel_size = 0.004
	label.modulate = text_color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.position = Vector3(0.0, 0.0, 0.025)
	var font := load("res://assets/fonts/Inter-ExtraBold.ttf") as Font
	if font:
		label.font = font
	pivot.add_child(label)


# ---------------------------------------------------------------------------
# Prozedurale Texturen (keine Bilddateien)
# ---------------------------------------------------------------------------
## Beton: Perlin-Rauschen als Helligkeit, Farbe kommt vom Material
static func _concrete(color: Color, roughness: float, noise_seed: int, uv: Vector3) -> StandardMaterial3D:
	var material := _material(color, roughness)
	material.albedo_texture = _noise_texture(noise_seed)
	material.uv1_scale = uv
	return material


static func _noise_texture(noise_seed: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.45
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.72, 0.72))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = ramp
	return texture


## Lochwand: weißes Blech mit dunklen Löchern im Raster
static func _dot_texture() -> ImageTexture:
	var size := 64
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	image.fill(Color(0.96, 0.95, 0.92))
	for y in size:
		for x in size:
			var dx := float(x % 16) - 8.0
			var dy := float(y % 16) - 8.0
			if dx * dx + dy * dy < 6.0:
				image.set_pixel(x, y, Color(0.24, 0.24, 0.25))
	return ImageTexture.create_from_image(image)


## Warnstreifen: gelb-schwarze Diagonalen für die Hebebühne
static func _stripe_texture() -> ImageTexture:
	var size := 64
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var stripe := int(floor(float(x + y) / 16.0)) % 2 == 0
			image.set_pixel(x, y, Color(0.95, 0.78, 0.05) if stripe else Color(0.06, 0.06, 0.06))
	return ImageTexture.create_from_image(image)


# ---------------------------------------------------------------------------
# Bausteine
# ---------------------------------------------------------------------------
static func _box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position
	parent.add_child(node)
	return node


## Zylinder, standardmäßig stehend; rotate_degrees kippt ihn (z. B. 90° für liegende Räder)
static func _cylinder(parent: Node3D, radius: float, height: float, position: Vector3,
		material: Material, rotate_degrees: float = 0.0, axis: Vector3 = Vector3.RIGHT) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position
	if rotate_degrees != 0.0:
		node.basis = Basis(axis.normalized(), deg_to_rad(rotate_degrees))
	parent.add_child(node)
	return node


## Ring (Schlauchrolle), liegt standardmäßig flach; rotate_degrees kippt ihn aufrecht
static func _torus(parent: Node3D, inner_radius: float, thickness: float, position: Vector3,
		material: Material, rotate_degrees: float = 0.0) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = inner_radius + thickness
	mesh.rings = 24
	mesh.ring_segments = 12
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position
	if rotate_degrees != 0.0:
		node.rotation_degrees = Vector3(rotate_degrees, 0.0, 0.0)
	parent.add_child(node)
	return node


static func _material(color: Color, roughness: float, emission: Color = Color(0, 0, 0),
		metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission != Color(0, 0, 0):
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.8
	return material
