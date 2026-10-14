extends SceneTree

const RENDERER_PATH = "res://.staged/shadow_renderer_work_smoke.gd"
var failures = []


func _init():
	call_deferred("_run")


func _run():
	var renderer_script = load(RENDERER_PATH)
	_expect(renderer_script != null, "renderer parses")
	if renderer_script == null:
		_finish()
		return
	var renderer = renderer_script.new()
	_expect(renderer.get_work_limit() == 250000, "work-limit API remains the 250k CPU fallback budget")
	var source = Image.new()
	source.create(8, 6, false, Image.FORMAT_RGBA8)
	source.fill(Color(1.0, 1.0, 1.0, 0.4))
	var offset_result = yield(renderer.render_async(source, Vector2.ZERO, 0.0, "offset", 0.01, 64, get_root()), "completed")
	_check_work(offset_result, "offset", false)
	if bool(offset_result.get("ok", false)):
		_expect(abs(_world_alpha(offset_result, Vector2(3.0, 2.0)) - 0.4) < 0.03, "offset interior retains the translucent alpha plateau")
	var sweep_result = yield(renderer.render_async(source, Vector2(7.25, 2.5), 0.25, "sweep", 0.01, 64, get_root()), "completed")
	_check_work(sweep_result, "sweep blur", true)
	if bool(sweep_result.get("ok", false)):
		_expect(_world_alpha(sweep_result, Vector2(3.0, 2.0) + Vector2(7.25, 2.5) * 0.5) > 0.32, "fractional low-blur sweep retains connected translucent coverage")
	_finish()


func _check_work(result: Dictionary, label: String, blurred: bool):
	_expect(bool(result.get("ok", false)), "%s render completes (%s)" % [label, str(result.get("error", "no error"))])
	if not bool(result.get("ok", false)):
		return
	var width = result["image"].get_width()
	var height = result["image"].get_height()
	var internal_area = width * height * 4
	var output_area = width * height
	var passes = int(result.get("render_passes", -1))
	_expect(int(result.get("estimated_render_passes", -2)) == passes, "%s estimated pass count matches executed passes" % label)
	var expected_samples = internal_area + output_area
	if label.begins_with("sweep"):
		var max_passes = passes - (4 if blurred else 2)
		expected_samples = internal_area * (1 + max_passes) + output_area * (3 if blurred else 1)
	_expect(int(result.get("work_samples", -1)) == expected_samples, "%s raster sample count equals the pass-by-pass area sum" % label)
	_expect(result["image"].get_used_rect().size.x > 0 and result["image"].get_used_rect().size.y > 0, "%s output contains coverage" % label)
	print("RENDER_WORK_SMOKE=" + JSON.print({"case": label, "work_samples": result.get("work_samples", -1), "render_passes": passes, "estimated_render_passes": result.get("estimated_render_passes", -1), "size": [width, height]}))


func _world_alpha(result: Dictionary, point: Vector2) -> float:
	var image = result["image"]
	var image_point = (point - result["offset"]) / float(result.get("pixel_scale", 1.0))
	var x = int(floor(image_point.x))
	var y = int(floor(image_point.y))
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return 0.0
	image.lock()
	var alpha = image.get_pixel(x, y).a
	image.unlock()
	return alpha


func _expect(condition: bool, message: String):
	print("%s: %s" % ["PASS" if condition else "FAIL", message])
	if not condition:
		failures.append(message)


func _finish():
	print("RENDER_WORK_SMOKE_RESULT=" + ("PASS" if failures.empty() else "FAIL"))
	quit(0 if failures.empty() else 1)
