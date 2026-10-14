extends SceneTree

const CURRENT_PATH = "res://.staged/shadow_renderer_v3.gd"
const PRODUCTION_PATH = "res://.staged/shadow_renderer_prod.gd"
const LEGACY_PATH = "res://v3/renderer_legacy.gd"
const ARTIFACT_DIR = "res://v3/artifacts"

var failures = []
var report = {"engine": "Godot 3.4.2 Mono / GLES2", "tests": [], "benchmarks": [], "comparisons": []}


func _init():
	call_deferred("_run")


func _run():
	var artifact_directory = Directory.new()
	artifact_directory.make_dir_recursive(ProjectSettings.globalize_path(ARTIFACT_DIR))
	var current_script = load(CURRENT_PATH)
	var production_script = load(PRODUCTION_PATH)
	var legacy_script = load(LEGACY_PATH)
	_expect(current_script != null, "high-quality CPU reference script parses")
	_expect(production_script != null, "production renderer script parses")
	_expect(legacy_script != null, "legacy reference renderer script parses")
	if current_script == null or production_script == null or legacy_script == null:
		_finish()
		return

	report["primary_renderer"] = "High-quality CPU reference; production synchronous API is checked separately as bounded fallback."
	var current = current_script.new()
	var production = production_script.new()
	var legacy = legacy_script.new()
	_expect(current.has_method("get_work_limit") and int(current.get_work_limit()) > 0, "current renderer exposes a positive sample-work limit")
	_test_horizontal_plateau(current)
	_test_fractional_diagonal_coverage(current)
	_test_low_blur_continuity(current)
	_test_downsample_coverage(current)
	_test_production_sync_fallback(production)
	_compare_case(current, legacy, "moderate-diagonal", _make_fixture(26, 20, 1), Vector2(8.25, -4.5), 0.0, 512)
	_compare_case(current, legacy, "long-diagonal", _make_fixture(48, 40, 2), Vector2(110.4, 72.8), 0.25, 512)
	_compare_case(current, legacy, "long-horizontal-soft", _make_fixture(40, 28, 3), Vector2(-180.0, 0.0), 3.5, 512)
	var full_benchmark = OS.get_environment("CONTOUR_SHADOWS_FULL_BENCHMARK") == "1"
	_benchmark_pair(current, legacy, "opaque_128", _make_opaque(128, 128), Vector2(32, -20), 8.0, 512)
	_benchmark_pair(current, legacy, "opaque_512", _make_opaque(512, 512), Vector2(32, -20), 8.0, 512)
	if full_benchmark:
		_benchmark_pair(current, legacy, "opaque_2048", _make_opaque(2048, 2048), Vector2(32, -20), 8.0, 512)
	else:
		report["benchmark_note"] = "Set CONTOUR_SHADOWS_FULL_BENCHMARK=1 to include the expensive 2048x2048 pair."
	_finish()


func _test_production_sync_fallback(production):
	var source = _make_solid_alpha(1, 1, 0.4)
	var result = production.render(source, Vector2(12.0, 0.0), 0.0, "sweep", 0.01, 64)
	_expect_ok(result, "production synchronous CPU fallback returns an image")
	if not _result_ok(result):
		return
	_expect(result.get("backend", "") == "cpu_fallback", "synchronous render identifies its CPU fallback backend")
	_expect(float(result.get("elapsed_ms", -1.0)) >= 0.0, "synchronous fallback reports elapsed_ms")
	_expect(result.has("diagnostic"), "synchronous fallback exposes its downsampling diagnostic")
	var worst_error = 0.0
	for x in range(13):
		worst_error = max(worst_error, abs(_world_alpha(result, Vector2(float(x), 0.0)) - 0.4))
	_expect(worst_error < 0.035, "synchronous CPU fallback preserves a translucent horizontal plateau")


func _test_horizontal_plateau(renderer):
	var source = _make_solid_alpha(1, 1, 0.4)
	var result = renderer.render(source, Vector2(12.0, 0.0), 0.0, "sweep", 0.01, 64)
	_expect_ok(result, "1x1 translucent horizontal sweep renders")
	if not _result_ok(result):
		return
	var worst = 0.0
	for x in range(13):
		var value = _world_alpha(result, Vector2(float(x), 0.0))
		worst = max(worst, abs(value - 0.4))
		_expect(abs(value - 0.4) < 0.035, "horizontal sweep keeps a flat %.2f plateau at x=%d (%.3f)" % [0.4, x, value])
	report["horizontal_plateau_worst_abs_error"] = worst


func _test_fractional_diagonal_coverage(renderer):
	var source = _make_opaque(5, 5)
	var result = renderer.render(source, Vector2(13.25, 8.5), 0.0, "sweep", 0.01, 64)
	_expect_ok(result, "fractional diagonal sweep renders")
	if not _result_ok(result):
		return
	var missing_interior = 0
	for step in range(1, 20):
		var t = float(step) / 20.0
		var point = Vector2(2.0, 2.0) + Vector2(13.25, 8.5) * t
		if _world_alpha(result, point) < 0.82:
			missing_interior += 1
	_expect(missing_interior == 0, "fractional diagonal sweep keeps its interior connected without dark gaps")
	var boundary_coverage = false
	var output_data = result.image.get_data()
	for y in range(result.image.get_height()):
		for x in range(result.image.get_width()):
			var a = float(output_data[(y * result.image.get_width() + x) * 4 + 3]) / 255.0
			if a > 0.04 and a < 0.96:
				boundary_coverage = true
				break
		if boundary_coverage:
			break
	_expect(boundary_coverage, "blur-zero diagonal sweep still has antialiased boundary coverage")


func _test_low_blur_continuity(renderer):
	var source = _make_opaque(9, 9)
	var radii = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.75, 1.0]
	var alpha_sums = []
	var edge_samples = []
	var scales = []
	for radius in radii:
		var result = renderer.render(source, Vector2(0.0, 0.0), radius, "offset", 0.01, 96)
		_expect_ok(result, "blur radius %.2f renders" % radius)
		if not _result_ok(result):
			return
		alpha_sums.append(_alpha_sum(result.image))
		edge_samples.append(_world_alpha(result, Vector2(-0.25, 4.0)))
		scales.append(float(result.get("pixel_scale", -1.0)))
	for i in range(1, alpha_sums.size()):
		var relative_change = abs(float(alpha_sums[i]) - float(alpha_sums[i - 1])) / max(1.0, float(alpha_sums[i - 1]))
		_expect(relative_change < 0.06, "blur coverage changes smoothly from %.2f to %.2f (%.3f)" % [radii[i - 1], radii[i], relative_change])
		_expect(abs(float(edge_samples[i]) - float(edge_samples[i - 1])) < 0.12, "edge alpha changes gradually from %.2f to %.2f" % [radii[i - 1], radii[i]])
		_expect(abs(float(scales[i]) - float(scales[i - 1])) < 0.0001, "low blur radius does not force a raster-scale jump")
	report["low_blur"] = {"radii": radii, "alpha_sums": alpha_sums, "edge_samples": edge_samples, "pixel_scales": scales}


func _test_downsample_coverage(renderer):
	var source = Image.new()
	source.create(8, 8, false, Image.FORMAT_RGBA8)
	source.fill(Color(1, 1, 1, 0))
	source.lock()
	source.set_pixel(1, 1, Color(1, 1, 1, 0.6))
	source.set_pixel(7, 7, Color(1, 1, 1, 1.0))
	source.unlock()
	var result = renderer.render(source, Vector2.ZERO, 0.0, "offset", 0.01, 4)
	_expect_ok(result, "downsampled thin alpha details render")
	if not _result_ok(result):
		return
	var detail = _world_alpha(result, Vector2(1.0, 1.0))
	_expect(detail > 0.02, "downsampling retains a translucent one-pixel detail as nonzero coverage")
	_expect(float(result.get("pixel_scale", 0.0)) > 1.0, "output-size cap activates coverage resampling")
	report["downsample_detail_alpha"] = detail


func _compare_case(current, legacy, label: String, source: Image, displacement: Vector2, blur: float, max_size: int):
	var old_result = legacy.render(source, displacement, blur, "sweep", 0.01, max_size)
	var new_result = current.render(source, displacement, blur, "sweep", 0.01, max_size)
	_expect_ok(old_result, "%s legacy reference renders" % label)
	_expect_ok(new_result, "%s current renderer renders" % label)
	if not _result_ok(old_result) or not _result_ok(new_result):
		return
	var metrics = _compare_images(old_result, new_result)
	metrics["label"] = label
	metrics["legacy_pixel_scale"] = float(old_result.get("pixel_scale", -1.0))
	metrics["current_pixel_scale"] = float(new_result.get("pixel_scale", -1.0))
	metrics["legacy_size"] = [old_result.image.get_width(), old_result.image.get_height()]
	metrics["current_size"] = [new_result.image.get_width(), new_result.image.get_height()]
	metrics["displacement"] = [displacement.x, displacement.y]
	metrics["blur_radius"] = blur
	metrics["work_samples"] = int(new_result.get("work_samples", -1))
	report["comparisons"].append(metrics)
	_save_comparison_png(label, old_result, new_result, metrics)
	print("V3_COMPARE=" + JSON.print(metrics))


func _benchmark_pair(current, legacy, label: String, source: Image, displacement: Vector2, blur: float, max_size: int):
	var timing = {"label": label, "source_size": [source.get_width(), source.get_height()], "displacement": [displacement.x, displacement.y], "blur_radius": blur, "max_size": max_size}
	var current_result = current.render(source, displacement, blur, "sweep", 0.02, max_size)
	var legacy_result = legacy.render(source, displacement, blur, "sweep", 0.02, max_size)
	_expect_ok(current_result, "%s current benchmark renders" % label)
	_expect_ok(legacy_result, "%s legacy benchmark renders" % label)
	if not _result_ok(current_result) or not _result_ok(legacy_result):
		return
	# Warm both implementations before collecting a median from three synchronous runs.
	for _warmup in range(1):
		current.render(source, displacement, blur, "sweep", 0.02, max_size)
		legacy.render(source, displacement, blur, "sweep", 0.02, max_size)
	var current_times = []
	var legacy_times = []
	var repeat_count = 2 if OS.get_environment("CONTOUR_SHADOWS_FULL_BENCHMARK") == "1" else 1
	for _repeat in range(repeat_count):
		var started = OS.get_ticks_msec()
		current_result = current.render(source, displacement, blur, "sweep", 0.02, max_size)
		current_times.append(OS.get_ticks_msec() - started)
		started = OS.get_ticks_msec()
		legacy_result = legacy.render(source, displacement, blur, "sweep", 0.02, max_size)
		legacy_times.append(OS.get_ticks_msec() - started)
	timing["current_runs_ms"] = current_times
	timing["legacy_runs_ms"] = legacy_times
	timing["current_median_ms"] = _median(current_times)
	timing["legacy_median_ms"] = _median(legacy_times)
	timing["speedup_vs_legacy"] = float(timing["legacy_median_ms"]) / max(1.0, float(timing["current_median_ms"]))
	timing["current_pixel_scale"] = float(current_result.get("pixel_scale", -1.0))
	timing["legacy_pixel_scale"] = float(legacy_result.get("pixel_scale", -1.0))
	timing["current_output"] = [current_result.image.get_width(), current_result.image.get_height()]
	timing["legacy_output"] = [legacy_result.image.get_width(), legacy_result.image.get_height()]
	timing["current_work_samples"] = int(current_result.get("work_samples", -1))
	timing["current_output_alpha_sum"] = _alpha_sum(current_result.image)
	timing["legacy_output_alpha_sum"] = _alpha_sum(legacy_result.image)
	report["benchmarks"].append(timing)
	print("V3_BENCH=" + JSON.print(timing))


func _compare_images(first: Dictionary, second: Dictionary) -> Dictionary:
	var first_data = first.image.get_data()
	var second_data = second.image.get_data()
	var first_scale = float(first.get("pixel_scale", 1.0))
	var second_scale = float(second.get("pixel_scale", 1.0))
	var min_x = min(float(first.offset.x), float(second.offset.x))
	var min_y = min(float(first.offset.y), float(second.offset.y))
	var max_x = max(float(first.offset.x) + float(first.image.get_width() - 1) * first_scale, float(second.offset.x) + float(second.image.get_width() - 1) * second_scale)
	var max_y = max(float(first.offset.y) + float(first.image.get_height() - 1) * first_scale, float(second.offset.y) + float(second.image.get_height() - 1) * second_scale)
	var width = max(1, int(ceil(max_x - min_x)) + 1)
	var height = max(1, int(ceil(max_y - min_y)) + 1)
	var absolute_total = 0.0
	var square_total = 0.0
	var maximum = 0.0
	var first_sum = 0.0
	var second_sum = 0.0
	var count = width * height
	for y in range(height):
		for x in range(width):
			var world = Vector2(min_x + float(x), min_y + float(y))
			var a = _world_alpha_from_data(first, first_data, world)
			var b = _world_alpha_from_data(second, second_data, world)
			var diff = abs(a - b)
			absolute_total += diff
			square_total += diff * diff
			maximum = max(maximum, diff)
			first_sum += a
			second_sum += b
	return {
		"canvas_size": [width, height],
		"mae": absolute_total / float(max(1, count)),
		"rmse": sqrt(square_total / float(max(1, count))),
		"max_abs_difference": maximum,
		"legacy_alpha_sum_on_source_grid": first_sum,
		"current_alpha_sum_on_source_grid": second_sum,
		"alpha_sum_ratio": second_sum / max(0.0001, first_sum)
	}


func _save_comparison_png(label: String, first: Dictionary, second: Dictionary, metrics: Dictionary):
	var first_data = first.image.get_data()
	var second_data = second.image.get_data()
	var canvas = metrics["canvas_size"]
	var width = int(canvas[0])
	var height = int(canvas[1])
	var image = Image.new()
	image.create(width * 3, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.lock()
	var min_x = min(float(first.offset.x), float(second.offset.x))
	var min_y = min(float(first.offset.y), float(second.offset.y))
	for y in range(height):
		for x in range(width):
			var world = Vector2(min_x + float(x), min_y + float(y))
			var a = _world_alpha_from_data(first, first_data, world)
			var b = _world_alpha_from_data(second, second_data, world)
			var difference = abs(a - b)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
			image.set_pixel(width + x, y, Color(1.0, 1.0, 1.0, b))
			image.set_pixel(width * 2 + x, y, Color(1.0, 0.08, 0.0, clamp(difference * 2.0, 0.0, 1.0)))
	image.unlock()
	image.save_png(ARTIFACT_DIR + "/comparison-" + label + ".png")


func _world_alpha(result: Dictionary, position: Vector2) -> float:
	return _world_alpha_from_data(result, result.image.get_data(), position)


func _world_alpha_from_data(result: Dictionary, data: PoolByteArray, position: Vector2) -> float:
	var scale = float(result.get("pixel_scale", 1.0))
	if scale <= 0.0:
		return 0.0
	var local_x = (position.x - float(result.offset.x)) / scale
	var local_y = (position.y - float(result.offset.y)) / scale
	var x0 = int(floor(local_x))
	var y0 = int(floor(local_y))
	var tx = local_x - float(x0)
	var ty = local_y - float(y0)
	var width = result.image.get_width()
	var height = result.image.get_height()
	var a00 = _result_alpha_at(data, width, height, x0, y0)
	var a10 = _result_alpha_at(data, width, height, x0 + 1, y0)
	var a01 = _result_alpha_at(data, width, height, x0, y0 + 1)
	var a11 = _result_alpha_at(data, width, height, x0 + 1, y0 + 1)
	var upper = a00 * (1.0 - tx) + a10 * tx
	var lower = a01 * (1.0 - tx) + a11 * tx
	return upper * (1.0 - ty) + lower * ty


func _result_alpha_at(data: PoolByteArray, width: int, height: int, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0.0
	return float(data[(y * width + x) * 4 + 3]) / 255.0


func _make_fixture(width: int, height: int, style: int) -> Image:
	var rgba = PoolByteArray()
	rgba.resize(width * height * 4)
	for i in range(width * height):
		rgba[i * 4] = 255
		rgba[i * 4 + 1] = 255
		rgba[i * 4 + 2] = 255
		rgba[i * 4 + 3] = 0
	for y in range(height):
		for x in range(width):
			var nx = (float(x) - float(width) * 0.48) / max(1.0, float(width) * 0.43)
			var ny = (float(y) - float(height) * 0.5) / max(1.0, float(height) * 0.42)
			var inside = nx * nx + ny * ny < 1.0
			if style == 1:
				inside = inside and not (x > int(width * 0.38) and x < int(width * 0.63) and y > int(height * 0.42) and y < int(height * 0.7))
			elif style == 2:
				inside = inside or (x > int(width * 0.55) and x < int(width * 0.9) and y > int(height * 0.35) and y < int(height * 0.62))
			elif style == 3:
				inside = inside and not (x > int(width * 0.35) and x < int(width * 0.6) and y > int(height * 0.32) and y < int(height * 0.8))
			if inside:
				var alpha = 175 + int((x * 17 + y * 23) % 81)
				rgba[(y * width + x) * 4 + 3] = alpha
	var image = Image.new()
	image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)
	return image


func _make_opaque(width: int, height: int) -> Image:
	var image = Image.new()
	image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))
	return image


func _make_solid_alpha(width: int, height: int, alpha: float) -> Image:
	var image = Image.new()
	image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, alpha))
	return image


func _alpha_sum(image: Image) -> float:
	var data = image.get_data()
	var total = 0.0
	for i in range(image.get_width() * image.get_height()):
		total += float(data[i * 4 + 3]) / 255.0
	return total


func _median(values: Array) -> int:
	var ordered = values.duplicate()
	ordered.sort()
	return int(ordered[int(ordered.size() / 2)])


func _result_ok(result) -> bool:
	return typeof(result) == TYPE_DICTIONARY and bool(result.get("ok", false)) and result.has("image") and result.image != null


func _expect_ok(result, label: String):
	_expect(_result_ok(result), "%s returns an image" % label)


func _expect(condition: bool, label: String):
	var item = {"ok": condition, "label": label}
	report["tests"].append(item)
	if not condition:
		failures.append(label)
		printerr("FAIL: " + label)
	else:
		print("PASS: " + label)


func _finish():
	var directory = Directory.new()
	directory.make_dir_recursive(ProjectSettings.globalize_path(ARTIFACT_DIR))
	report["failure_count"] = failures.size()
	report["result"] = "PASS" if failures.empty() else "FAIL"
	report["failures"] = failures
	var file = File.new()
	var path = ARTIFACT_DIR + "/benchmark.json"
	if file.open(path, File.WRITE) == OK:
		file.store_string(JSON.print(report, "\t"))
		file.close()
	else:
		printerr("Could not write renderer v3 benchmark JSON")
	print("V3_REPORT=" + JSON.print(report))
	quit(0 if failures.empty() else 1)
