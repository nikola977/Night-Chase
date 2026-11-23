extends SceneTree
## Zeichnet nur das Kartenbild der Stadt (Taste M) und speichert es als PNG,
## damit man es ohne Spielstart ansehen kann.
## Aufruf: Godot --headless --path . -s res://tools/city_map_test.gd

const OUT := "res://screenshots/city_map.png"


func _initialize() -> void:
	var city := CityMap.new()
	root.add_child(city)
	var started := Time.get_ticks_msec()
	city.build(null)
	print("Bau: %d ms" % (Time.get_ticks_msec() - started))
	for child in city.get_node("Surfaces").get_children():
		var mesh: Mesh = child.mesh
		var faces := mesh.get_faces()
		var low := INF
		var high := -INF
		for point in faces:
			low = minf(low, point.y)
			high = maxf(high, point.y)
		var material := mesh.surface_get_material(0)
		var texture: Texture2D = material.albedo_texture if material != null else null
		print("%-26s %5d tris  y %6.2f .. %6.2f  %s" % [child.name, faces.size() / 3, low, high,
			texture.resource_path.get_file() if texture != null else "-"])
	var image: Image = city.map_texture.get_image()
	image.save_png(OUT)
	print("Karte: %s (%d x %d)" % [OUT, image.get_width(), image.get_height()])
	quit()
