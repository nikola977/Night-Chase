extends Node
## Prüft, was die Garage aus cars/ liest: Marke, Modell vorhanden, Räder erkannt.
## Aufruf: godot --headless --path . scenes/_checkcars.tscn


func _ready() -> void:
	var brands := {}
	for file in ResourceLoader.list_directory("res://cars"):
		if file.get_extension().to_lower() != "tres":
			continue
		var profile := load("res://cars/" + file) as CarProfile
		if profile == null:
			print("BROKEN ", file)
			continue
		if not brands.has(profile.brand):
			brands[profile.brand] = []
		(brands[profile.brand] as Array).append(profile)
	for brand: String in brands:
		var list: Array = brands[brand]
		list.sort_custom(func(a: CarProfile, b: CarProfile) -> bool: return a.year < b.year)
		print("BRAND %s (%d)" % [brand, list.size()])
		for p: CarProfile in list:
			print("   %-18s %-38s model=%-5s wheels=%d  %.2f x %.2f x %.2f m" % [
				p.id, p.display_name, str(CarModel.is_available(p)), p.wheel_parts.size(),
				p.body_size.x, p.body_size.y, p.body_size.z])
	print("done")
	get_tree().quit()
