extends Node
## Setzt für die neuen Autos die echten Werksmaße (Länge, Breite, Höhe, Radstand, Spur,
## Radradius). Die Messung aus dem Modell taugt dort nicht, weil die Sketchfab-Szenen
## Bauteile weit weg vom Auto enthalten. Werte in Metern.

const REAL: Array = [
	{"id": "centenario", "wheelbase": 2.70, "track": 1.668, "radius": 0.35,
		"body": Vector3(1.98, 0.63, 4.90), "body_center": Vector3(0.0, 0.31, 0.0),
		"cabin": Vector3(1.44, 0.48, 2.30), "cabin_center": Vector3(0.0, 0.86, -0.18)},
	{"id": "centenario_roadster", "wheelbase": 2.70, "track": 1.668, "radius": 0.35,
		"body": Vector3(1.98, 0.63, 4.90), "body_center": Vector3(0.0, 0.31, 0.0),
		"cabin": Vector3(1.44, 0.48, 2.30), "cabin_center": Vector3(0.0, 0.86, -0.18)},
	{"id": "aventador", "wheelbase": 2.70, "track": 1.668, "radius": 0.35,
		"body": Vector3(1.95, 0.625, 4.76), "body_center": Vector3(0.0, 0.31, 0.0),
		"cabin": Vector3(1.42, 0.48, 2.25), "cabin_center": Vector3(0.0, 0.86, -0.18)},
	{"id": "gt3", "wheelbase": 2.457, "track": 1.553, "radius": 0.34,
		"body": Vector3(1.80, 0.70, 4.55), "body_center": Vector3(0.0, 0.35, 0.0),
		"cabin": Vector3(1.30, 0.54, 2.30), "cabin_center": Vector3(0.0, 0.95, -0.18)},
]


func _ready() -> void:
	for entry: Dictionary in REAL:
		var path := "res://cars/%s.tres" % entry["id"]
		var profile := load(path) as CarProfile
		if profile == null:
			print("MISSING ", path)
			continue
		profile.wheelbase = entry["wheelbase"]
		profile.track_front = entry["track"]
		profile.track_rear = entry["track"]
		profile.wheel_radius = entry["radius"]
		profile.body_size = entry["body"]
		profile.body_center = entry["body_center"]
		profile.cabin_size = entry["cabin"]
		profile.cabin_center = entry["cabin_center"]
		print("FIXED %s save=%d" % [entry["id"], ResourceSaver.save(profile, path)])
	print("done")
	get_tree().quit()
