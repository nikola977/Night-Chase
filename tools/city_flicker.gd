extends SceneTree
## Measures flicker in the city map: the car stands still, so every change in the
## middle of the picture between two frames is temporal noise (z-fighting,
## shadow acne, shimmering). Prints a second average and saves an amplified
## difference picture of the worst pair.
##
##   Godot_v4.7.2-stable_win64.exe --path . -s res://tools/city_flicker.gd

const FRAMES := 40
## Crop in fractions of the window, so the HUD and the sky are left out
const CROP := Rect2(0.06, 0.26, 0.70, 0.48)
const STEP := 2

var _main: Node
var _frames := 0
var _settle := 0
var _prev: Image
var _pairs := 0
var _sum := 0.0
var _sum_peak := 0.0
var _worst := -1.0
var _worst_image: Image


func _initialize() -> void:
	var mode = load("res://scripts/city_mode.gd")
	mode.enabled = true
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 10 or not _main.world_is_ready:
		return false
	_settle += 1
	if _settle < 30:
		return false
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		return false
	if _prev == null:
		_prev = image
		return false
	var diff := _compare(_prev, image)
	_pairs += 1
	_sum += diff["mean"]
	_sum_peak += diff["peak"]
	if diff["mean"] > _worst:
		_worst = diff["mean"]
		_worst_image = diff["image"]
	_prev = image
	if _pairs < FRAMES:
		return false
	print("\nFLICKER: %d pairs, mean change %.3f / 255, %.1f %% pixels changed > 8, peak %.3f" % [
		_pairs, _sum / _pairs, _sum_peak / _pairs * 100.0, _worst])
	if _worst_image != null:
		_worst_image.save_png("res://screenshots/city_flicker_diff.png")
		print("FLICKER: worst pair written to screenshots/city_flicker_diff.png")
	quit()
	return true


func _compare(a: Image, b: Image) -> Dictionary:
	var size := Vector2i(a.get_width(), a.get_height())
	var origin := Vector2i(int(CROP.position.x * size.x), int(CROP.position.y * size.y))
	var rect := Rect2i(origin, Vector2i(int(CROP.size.x * size.x), int(CROP.size.y * size.y)))
	var total := 0.0
	var count := 0
	var changed := 0
	var out := Image.create(rect.size.x, rect.size.y, false, Image.FORMAT_RGB8)
	for y in range(0, rect.size.y, STEP):
		for x in range(0, rect.size.x, STEP):
			var pa := a.get_pixel(rect.position.x + x, rect.position.y + y)
			var pb := b.get_pixel(rect.position.x + x, rect.position.y + y)
			var d := (absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)) / 3.0
			total += d
			count += 1
			if d > 8.0 / 255.0:
				changed += 1
			var lit := clampf(d * 12.0, 0.0, 1.0)
			out.set_pixel(x, y, Color(lit, lit * 0.4, lit * 0.2))
	return {"mean": total / maxf(count, 1) * 255.0, "peak": float(changed) / maxf(count, 1),
		"image": out}
