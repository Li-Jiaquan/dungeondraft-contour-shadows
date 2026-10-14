extends SceneTree

const RENDERER_PATH = "res://.staged/shadow_renderer_v3.gd"
const ARTIFACT_DIR = "res://v3/artifacts"

var report = {"engine": "Godot 3.4.2 Mono", "driver": "unknown", "tests": [], "benchmarks": []}
var failures = []


func _init():
	call_deferred("_run")


func _run():
	report["driver"] = OS.get_environment("GPU_PROBE_DRIVER")
	var current_script = load(RENDERER_PATH)
	_expect(current_script != null, "GPU renderer script parses")
	if current_script == null:
		_finish()
		return
	var renderer = current_script.new()
	_test_async_failure_is_awaitable(renderer)
	var unload_result = yield(_test_owner_unload_cleanup(renderer), "completed")
	_expect(unload_result, "owner removal cancels the active GPU render and releases its stage")
	var delete_result = yield(_test_owner_delete_cleanup(renderer), "completed")
	_expect(delete_result, "deleting the GPU render owner cancels and clears its stage")
	var horizontal = yield(renderer.render_async(_solid_alpha(1, 1, 0.4), Vector2(12.0, 0.0), 0.0, "sweep", 0.01, 64, get_root()), "completed")
	_expect_ok(horizontal, "1x1 .4 horizontal sweep")
	if _result_ok(horizontal):
		var worst_error = 0.0
		for x in range(13):
			var alpha = _world_alpha(horizontal, Vector2(float(x), 0.0))
			worst_error = max(worst_error, abs(alpha - 0.4))
			_expect(abs(alpha - 0.4) < 0.06, "alpha .4 plateau at x=%d is %.3f" % [x, alpha])
		report["horizontal_plateau_worst_error"] = worst_error
		report["horizontal_backend"] = horizontal.get("backend", "missing")
		report["horizontal_elapsed_ms"] = horizontal.get("elapsed_ms", -1.0)
		_save_image(horizontal["image"], "gpu-alpha04-horizontal.png")

	var diagonal = yield(renderer.render_async(_solid_alpha(5, 5, 1.0), Vector2(13.25, 8.5), 0.0, "sweep", 0.01, 64, get_root()), "completed")
	_expect_ok(diagonal, "fractional diagonal sweep")
	if _result_ok(diagonal):
		var min_interior_alpha = 1.0
		for step_index in range(1, 20):
			var t = float(step_index) / 20.0
			var point = Vector2(2.0, 2.0) + Vector2(13.25, 8.5) * t
			var alpha = _world_alpha(diagonal, point)
			min_interior_alpha = min(min_interior_alpha, alpha)
			_expect(alpha > 0.72, "fractional diagonal interior connected at t=%.2f (%.3f)" % [t, alpha])
		report["diagonal_min_interior_alpha"] = min_interior_alpha
		report["diagonal_backend"] = diagonal.get("backend", "missing")
		report["diagonal_render_passes"] = diagonal.get("render_passes", -1)
		_save_image(diagonal["image"], "gpu-fractional-diagonal.png")

	var blur0 = yield(renderer.render_async(_solid_alpha(16, 12, 1.0), Vector2(28.0, 6.0), 0.0, "sweep", 0.01, 128, get_root()), "completed")
	var blur025 = yield(renderer.render_async(_solid_alpha(16, 12, 1.0), Vector2(28.0, 6.0), 0.25, "sweep", 0.01, 128, get_root()), "completed")
	var blur8 = yield(renderer.render_async(_solid_alpha(16, 12, 1.0), Vector2(28.0, 6.0), 8.0, "sweep", 0.01, 128, get_root()), "completed")
	_expect_ok(blur0, "blur zero render")
	_expect_ok(blur025, "fractional low blur render")
	_expect_ok(blur8, "blur 8 render")
	if _result_ok(blur0) and _result_ok(blur025) and _result_ok(blur8):
		var edge0 = _edge_alpha(blur0)
		var edge025 = _edge_alpha(blur025)
		var edge8 = _edge_alpha(blur8)
		report["blur_edge_samples"] = [edge0, edge025, edge8]
		_expect(abs(edge025 - edge0) < 0.15, "low blur changes the edge gradually")
		_expect(edge8 < edge0, "blur 8 produces a softer edge than blur zero")
		_save_image(blur0["image"], "gpu-blur-0.png")
		_save_image(blur025["image"], "gpu-blur-025.png")
		_save_image(blur8["image"], "gpu-blur-8.png")

	var broad_source = _solid_alpha(192, 192, 1.0)
	var offset_blur0 = yield(renderer.render_async(broad_source, Vector2.ZERO, 0.0, "offset", 0.01, 512, get_root()), "completed")
	var offset_blur025 = yield(renderer.render_async(broad_source, Vector2.ZERO, 0.25, "offset", 0.01, 512, get_root()), "completed")
	var offset_blur8 = yield(renderer.render_async(broad_source, Vector2.ZERO, 8.0, "offset", 0.01, 512, get_root()), "completed")
	var offset_blur32 = yield(renderer.render_async(broad_source, Vector2.ZERO, 32.0, "offset", 0.01, 512, get_root()), "completed")
	_expect_ok(offset_blur0, "wide contour blur zero")
	_expect_ok(offset_blur025, "wide contour blur 0.25")
	_expect_ok(offset_blur8, "wide contour blur 8")
	_expect_ok(offset_blur32, "wide contour blur 32")
	if _result_ok(offset_blur0) and _result_ok(offset_blur025) and _result_ok(offset_blur8) and _result_ok(offset_blur32):
		var profile_counts = [
			_count_row_alpha(offset_blur0, 0.02),
			_count_row_alpha(offset_blur025, 0.02),
			_count_row_alpha(offset_blur8, 0.02),
			_count_row_alpha(offset_blur32, 0.02)
		]
		report["blur_profile_support_pixels_above_002"] = profile_counts
		_expect(profile_counts[3] > profile_counts[2] and profile_counts[2] > profile_counts[0], "blur support widens continuously through radius 32")
		_expect(_wide_blur_profile_is_monotone(offset_blur32), "blur 32 edge profile has no visible stripes")
		_expect(_world_alpha(offset_blur32, Vector2(96.0, 96.0)) > 0.90, "blur 32 preserves the opaque interior plateau")
		_save_comparison_canvas([offset_blur0, offset_blur025, offset_blur8, offset_blur32], "gpu-comparison-order-0-025-8-32.png")

	for size in [128, 512]:
		var fixture = _solid_alpha(size, size, 1.0)
		var legacy_script = load("res://v3/renderer_legacy.gd")
		var legacy = legacy_script.new()
		var warmup_result = yield(renderer.render_async(fixture, Vector2(32.0, -20.0), 8.0, "sweep", 0.01, 512, get_root()), "completed")
		_expect_ok(warmup_result, "GPU benchmark %dx%d warmup" % [size, size])
		var gpu_samples = []
		var legacy_samples = []
		var gpu_result = warmup_result
		var cpu_result = {}
		for _repeat_index in range(3):
			var gpu_start = OS.get_ticks_usec()
			gpu_result = yield(renderer.render_async(fixture, Vector2(32.0, -20.0), 8.0, "sweep", 0.01, 512, get_root()), "completed")
			gpu_samples.append(float(OS.get_ticks_usec() - gpu_start) / 1000.0)
			var cpu_start = OS.get_ticks_usec()
			cpu_result = legacy.render(fixture, Vector2(32.0, -20.0), 8.0, "sweep", 0.01, 512)
			legacy_samples.append(float(OS.get_ticks_usec() - cpu_start) / 1000.0)
		var gpu_median = _median_ms(gpu_samples)
		var cpu_median = _median_ms(legacy_samples)
		_expect_ok(gpu_result, "GPU benchmark %dx%d" % [size, size])
		var benchmark = {
			"fixture": "opaque_%d" % size,
			"gpu_samples_ms": gpu_samples,
			"gpu_median_ms": gpu_median,
			"gpu_backend": gpu_result.get("backend", "error"),
			"gpu_render_passes": gpu_result.get("render_passes", 0),
			"gpu_pixel_scale": gpu_result.get("pixel_scale", 0.0),
			"legacy_samples_ms": legacy_samples,
			"legacy_median_ms": cpu_median,
			"cpu_pixel_scale": cpu_result.get("pixel_scale", 0.0),
			"speedup_vs_legacy_median": cpu_median / max(gpu_median, 0.001)
		}
		report["benchmarks"].append(benchmark)
		print("GPU_BENCHMARK=" + JSON.print(benchmark))

	_finish()


func _test_async_failure_is_awaitable(renderer):
	var invalid = yield(renderer.render_async(_solid_alpha(1, 1, 1.0), Vector2.ZERO, 0.0, "offset", 0.01, 64, null), "completed")
	_expect(typeof(invalid) == TYPE_DICTIONARY and not bool(invalid.get("ok", true)), "invalid async request still resolves with a failure dictionary")
	if typeof(invalid) == TYPE_DICTIONARY:
		_expect(invalid.get("backend", "") == "gpu_viewport" and invalid.has("elapsed_ms"), "async validation failure reports backend and elapsed_ms")
	report["invalid_async_result"] = invalid


func _test_owner_unload_cleanup(renderer):
	var owner = Node.new()
	owner.name = "GpuRenderOwnerUnloadTest"
	get_root().add_child(owner)
	var pending = renderer.render_async(_solid_alpha(48, 32, 1.0), Vector2(96.5, -24.25), 0.25, "sweep", 0.01, 256, owner)
	# Let the async renderer pass its initial await and allocate the stage, then
	# let one render frame start before removing the owner from the active tree.
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var stage_was_created = false
	for child in owner.get_children():
		if child is Node and child.name == "ContourShadowGpuRender":
			stage_was_created = true
	get_root().remove_child(owner)
	var result = yield(pending, "completed")
	yield(self, "idle_frame")
	var stage_children_after_cleanup = owner.get_child_count()
	var owner_cancelled = typeof(result) == TYPE_DICTIONARY and not bool(result.get("ok", true)) and str(result.get("error", "")).find("left the tree") >= 0
	var released = stage_children_after_cleanup == 0
	owner.free()
	report["owner_unload"] = {
		"stage_created_before_removal": stage_was_created,
		"result": result,
		"stage_children_after_cleanup": stage_children_after_cleanup,
		"cancelled": owner_cancelled,
		"released": released
	}
	_expect(stage_was_created, "owner unload test removes an owner after GPU resources are attached")
	_expect(owner_cancelled, "owner leaving the SceneTree cancels in-flight GPU readback")
	_expect(released, "owner unload releases all GPU stage children")
	return stage_was_created and owner_cancelled and released


func _test_owner_delete_cleanup(renderer):
	var owner = Node.new()
	owner.name = "GpuRenderOwnerDeleteTest"
	get_root().add_child(owner)
	var pending = renderer.render_async(_solid_alpha(48, 32, 1.0), Vector2(-90.25, 38.5), 0.25, "sweep", 0.01, 256, owner)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var stage_was_created = false
	for child in owner.get_children():
		if child is Node and child.name == "ContourShadowGpuRender":
			stage_was_created = true
	owner.free()
	var result = yield(pending, "completed")
	yield(self, "idle_frame")
	var stage_after_delete = get_root().find_node("ContourShadowGpuRender", true, false)
	var owner_cancelled = typeof(result) == TYPE_DICTIONARY and not bool(result.get("ok", true)) and str(result.get("error", "")).find("left the tree") >= 0
	var released = stage_after_delete == null
	report["owner_delete"] = {
		"stage_created_before_delete": stage_was_created,
		"result": result,
		"stage_found_after_delete": stage_after_delete != null,
		"cancelled": owner_cancelled,
		"released": released
	}
	_expect(stage_was_created, "owner delete test frees an owner after GPU resources are attached")
	_expect(owner_cancelled, "deleted owner cancels in-flight GPU readback")
	_expect(released, "deleted owner leaves no GPU stage in the SceneTree")
	return stage_was_created and owner_cancelled and released


func _solid_alpha(width, height, alpha):
	var image = Image.new()
	image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, alpha))
	return image


func _world_alpha(result, point):
	var image = result["image"]
	var scale = float(result.get("pixel_scale", 1.0))
	var image_point = (point - result["offset"]) / scale
	var x = int(floor(image_point.x))
	var y = int(floor(image_point.y))
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return 0.0
	image.lock()
	var alpha = image.get_pixel(x, y).a
	image.unlock()
	return alpha


func _edge_alpha(result):
	var image = result["image"]
	var best = 1.0
	image.lock()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var alpha = image.get_pixel(x, y).a
			if alpha > 0.08 and alpha < 0.92:
				best = min(best, alpha)
	image.unlock()
	return best


func _count_row_alpha(result, threshold):
	var image = result["image"]
	var row_y = int(image.get_height() / 2)
	var count = 0
	image.lock()
	for x in range(image.get_width()):
		if image.get_pixel(x, row_y).a > threshold:
			count += 1
	image.unlock()
	return count


func _median_ms(samples):
	var ordered = samples.duplicate()
	ordered.sort()
	if ordered.empty():
		return -1.0
	var middle = int(ordered.size() / 2)
	if ordered.size() % 2 == 1:
		return float(ordered[middle])
	return (float(ordered[middle - 1]) + float(ordered[middle])) * 0.5


func _wide_blur_profile_is_monotone(result):
	var image = result["image"]
	var row_y = int(image.get_height() / 2)
	var center_x = int(image.get_width() / 2)
	var previous = 0.0
	var monotone = true
	image.lock()
	for x in range(center_x + 1):
		var alpha = image.get_pixel(x, row_y).a
		if alpha + 0.025 < previous:
			monotone = false
			break
		previous = alpha
	image.unlock()
	return monotone


func _save_comparison_canvas(results, file_name):
	var panel_size = 240
	var panel_inset = 24
	var canvas = Image.new()
	canvas.create(panel_size * results.size(), panel_size, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(1.0, 1.0, 1.0, 1.0))
	for panel_index in range(results.size()):
		var source = results[panel_index]["image"]
		var factor = min(float(panel_size - panel_inset * 2) / float(source.get_width()), float(panel_size - panel_inset * 2) / float(source.get_height()))
		var preview_width = max(1, int(round(float(source.get_width()) * factor)))
		var preview_height = max(1, int(round(float(source.get_height()) * factor)))
		var resized = source.duplicate()
		resized.resize(preview_width, preview_height, Image.INTERPOLATE_LANCZOS)
		var preview = Image.new()
		preview.create(preview_width, preview_height, false, Image.FORMAT_RGBA8)
		resized.lock()
		preview.lock()
		for y in range(preview_height):
			for x in range(preview_width):
				var intensity = 1.0 - resized.get_pixel(x, y).a
				preview.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
		resized.unlock()
		preview.unlock()
		canvas.blit_rect(preview, Rect2(Vector2.ZERO, Vector2(preview_width, preview_height)), Vector2(panel_index * panel_size + (panel_size - preview_width) / 2, (panel_size - preview_height) / 2))
	var absolute_dir = ProjectSettings.globalize_path(ARTIFACT_DIR)
	var directory = Directory.new()
	directory.make_dir_recursive(absolute_dir)
	canvas.save_png(absolute_dir.plus_file(file_name))


func _save_image(image, file_name):
	var absolute_dir = ProjectSettings.globalize_path(ARTIFACT_DIR)
	var directory = Directory.new()
	directory.make_dir_recursive(absolute_dir)
	image.save_png(absolute_dir.plus_file(file_name))


func _result_ok(result):
	return typeof(result) == TYPE_DICTIONARY and bool(result.get("ok", false)) and result.get("image", null) != null


func _expect_ok(result, name):
	_expect(_result_ok(result), "%s succeeds (%s)" % [name, str(result.get("error", "no error")) if typeof(result) == TYPE_DICTIONARY else "non-dictionary result"])
	if _result_ok(result):
		_expect(result.has("backend") and result.has("elapsed_ms"), "%s reports backend and elapsed_ms" % name)
		_expect(float(result["elapsed_ms"]) >= 0.0, "%s elapsed_ms is nonnegative" % name)
	report["tests"].append({"name": name, "ok": _result_ok(result), "backend": result.get("backend", "missing") if typeof(result) == TYPE_DICTIONARY else "missing", "elapsed_ms": result.get("elapsed_ms", -1.0) if typeof(result) == TYPE_DICTIONARY else -1.0})


func _expect(condition, message):
	var status = "PASS" if condition else "FAIL"
	print("%s: %s" % [status, message])
	if not condition:
		failures.append(message)


func _finish():
	report["failures"] = failures
	report["result"] = "PASS" if failures.empty() else "FAIL"
	var absolute_dir = ProjectSettings.globalize_path(ARTIFACT_DIR)
	var directory = Directory.new()
	directory.make_dir_recursive(absolute_dir)
	var file = File.new()
	file.open(absolute_dir.plus_file("gpu-render-report-%s.json" % OS.get_environment("GPU_PROBE_DRIVER").to_lower()), File.WRITE)
	file.store_string(JSON.print(report, "\t"))
	file.close()
	print("GPU_RENDER_REPORT=" + JSON.print(report))
	quit(0 if failures.empty() else 1)


