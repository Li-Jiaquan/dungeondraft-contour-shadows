extends SceneTree

const MASK_PATH = "res://.staged/shadow_mask_gpu_stroke_v3.gd"
const ARTIFACT_PATH = "res://v3/artifacts/mask-gpu-stroke-report.json"

var mask = null
var failures = []
var tests = []
var report = {"engine": "Godot 3.4.2 Mono", "driver": "unknown"}


func _init():
	call_deferred("_run")


func _run():
	report["driver"] = OS.get_environment("GPU_PROBE_DRIVER")
	var mask_script = load(MASK_PATH)
	_expect(mask_script != null, "GPU stroke mask script parses")
	if mask_script == null:
		_finish()
		return
	mask = mask_script.new()
	report["active_video_driver"] = mask._gpu_video_driver_name()
	var small_ok = yield(_test_transformed_fractional_polyline(), "completed")
	if not small_ok:
		_finish()
		return
	var long_ok = yield(_test_long_polyline_batches(), "completed")
	if not long_ok:
		_finish()
		return
	var pass_cap_ok = yield(_test_pass_cap_releases_stage(), "completed")
	_expect(pass_cap_ok, "over-limit paths fail cleanly and release all GPU stages")
	var wide = yield(_test_wide_drag_benchmark_and_equivalence(), "completed")
	var owner_ok = yield(_test_owner_unload_cleanup(), "completed")
	_expect(owner_ok, "owner removal cancels the GPU stroke and releases its stage")
	_finish()


func _test_transformed_fractional_polyline():
	var source = _solid_image(72, 54, Color(0.2, 0.55, 0.83, 0.76))
	# Include transparent holes and translucent source texels to confirm the GPU
	# pass only changes alpha and composites against the stroke-start image.
	source.lock()
	for y in range(20, 25):
		for x in range(28, 35):
			source.set_pixel(x, y, Color(0.2, 0.55, 0.83, 0.0))
	for y in range(31, 34):
		for x in range(10, 15):
			source.set_pixel(x, y, Color(0.2, 0.55, 0.83, 0.4))
	source.unlock()
	var original_source_data = source.get_data()
	var pixel_to_local = Transform2D(Vector2(1.2, 0.17), Vector2(-0.22, 0.91), Vector2(2.5, -1.75))
	var stroke = {
		"points": [[3.25, 8.5], [18.75, 12.25], [27.0, 8.0]],
		"radius": 7.2,
		"hardness": 0.43,
		"radius_basis": [[1.1, 0.12], [-0.08, 0.92]]
	}
	var expected = mask.apply(source, [stroke], pixel_to_local)
	var result = yield(mask.render_gpu_stroke_async(source, stroke, stroke["points"], pixel_to_local, get_root()), "completed")
	_expect(bool(result.get("ok", false)), "transformed fractional GPU stroke succeeds: %s" % result.get("error", ""))
	if not bool(result.get("ok", false)):
		return false
	var comparison = _compare_images(expected, result["image"])
	_expect(_same_bytes(original_source_data, source.get_data()), "GPU stroke leaves the baseline source image unchanged")
	_expect(comparison["rgb_error_pixels_over_1"] == 0, "GPU stroke preserves source RGB within one byte")
	_expect(comparison["alpha_error_pixels_over_1"] == 0, "GPU soft-edge alpha agrees with CPU within one byte")
	_expect(str(result.get("backend", "")).find("gpu_") == 0 and result.has("elapsed_ms"), "GPU stroke reports backend and elapsed_ms")
	if str(report.get("active_video_driver", "")).to_upper().find("GLES2") >= 0:
		_expect(result.get("backend", "") == "gpu_coverage_cpu_composite" and int(result.get("cpu_composite_frames", 0)) > 0, "GLES2 alpha composition yields across bounded frame slices")
	else:
		_expect(result.get("backend", "") == "gpu_viewport" and int(result.get("cpu_composite_frames", -1)) == 0, "GLES3 completes RGB and alpha composition on the GPU")
	report["transformed_fractional"] = {
		"result": result,
		"max_alpha_error_bytes": comparison["max_alpha_error_bytes"],
		"alpha_error_pixels_over_1": comparison["alpha_error_pixels_over_1"],
		"rgb_error_pixels_over_1": comparison["rgb_error_pixels_over_1"],
		"max_rgb_error_bytes": comparison["max_rgb_error_bytes"],
		"first_expected_rgba": comparison["first_expected_rgba"],
		"first_actual_rgba": comparison["first_actual_rgba"]
	}
	return comparison["alpha_error_pixels_over_1"] == 0 and comparison["rgb_error_pixels_over_1"] == 0


func _test_long_polyline_batches():
	var source = _solid_image(96, 72, Color(0.42, 0.28, 0.67, 0.83))
	var points = []
	for point_index in range(70):
		var ratio = float(point_index) / 69.0
		points.append([10.2 + 76.0 * ratio, 36.0 + 12.0 * sin(ratio * PI * 3.0)])
	var stroke = {"points": points, "radius": 5.6, "hardness": 0.61}
	var expected = mask.apply(source, [stroke], Transform2D())
	var result = yield(mask.render_gpu_stroke_async(source, stroke, points, Transform2D(), get_root()), "completed")
	_expect(bool(result.get("ok", false)), "multi-pass long GPU stroke succeeds: %s" % result.get("error", ""))
	if not bool(result.get("ok", false)):
		return false
	var comparison = _compare_images(expected, result["image"])
	_expect(int(result.get("render_passes", 0)) >= 4, "long GPU stroke batches path segments across coverage passes")
	_expect(comparison["alpha_error_pixels_over_1"] == 0, "long stroke max-mask ping-pong preserves CPU alpha within one byte")
	_expect(comparison["rgb_error_pixels_over_1"] == 0, "long GPU stroke preserves RGB within one byte")
	report["long_polyline"] = {
		"point_count": points.size(),
		"result": result,
		"max_alpha_error_bytes": comparison["max_alpha_error_bytes"],
		"alpha_error_pixels_over_1": comparison["alpha_error_pixels_over_1"],
		"rgb_error_pixels_over_1": comparison["rgb_error_pixels_over_1"],
		"max_rgb_error_bytes": comparison["max_rgb_error_bytes"]
	}
	return comparison["alpha_error_pixels_over_1"] == 0 and comparison["rgb_error_pixels_over_1"] == 0


func _test_wide_drag_benchmark_and_equivalence():
	var source = _solid_image(512, 512, Color(0.73, 0.44, 0.24, 0.8))
	var points = []
	for point_index in range(32):
		var ratio = float(point_index) / 31.0
		points.append([102.4 + 307.2 * ratio, 256.0 + 12.8 * sin(ratio * PI * 4.0)])
	var stroke = {"points": points, "radius": 256.0, "hardness": 0.7}
	var gpu_result = yield(mask.render_gpu_stroke_async(source, stroke, points, Transform2D(), get_root()), "completed")
	_expect(bool(gpu_result.get("ok", false)), "512px radius-256 GPU drag succeeds: %s" % gpu_result.get("error", ""))
	if not bool(gpu_result.get("ok", false)):
		return false
	var cpu_started = OS.get_ticks_usec()
	var expected = mask.apply(source, [stroke], Transform2D())
	var cpu_elapsed_ms = float(OS.get_ticks_usec() - cpu_started) / 1000.0
	var comparison = _compare_images(expected, gpu_result["image"])
	_expect(comparison["rgb_error_pixels_over_1"] == 0, "wide GPU stroke preserves RGB within one byte")
	_expect(comparison["alpha_error_pixels_over_1"] == 0, "wide GPU stroke agrees with CPU within one alpha byte")
	report["wide_radius_256"] = {
		"size": [512, 512],
		"point_count": points.size(),
		"radius": 256.0,
		"gpu_result": gpu_result,
		"cpu_composite_max_slice_usec": int(gpu_result.get("cpu_composite_max_slice_usec", 0)),
		"cpu_reference_elapsed_ms": cpu_elapsed_ms,
		"max_alpha_error_bytes": comparison["max_alpha_error_bytes"],
		"alpha_error_pixels_over_1": comparison["alpha_error_pixels_over_1"],
		"rgb_error_pixels_over_1": comparison["rgb_error_pixels_over_1"],
		"max_rgb_error_bytes": comparison["max_rgb_error_bytes"]
	}
	if str(report.get("active_video_driver", "")).to_upper().find("GLES2") >= 0:
		_expect(int(gpu_result.get("cpu_composite_max_slice_usec", 0)) <= 7000, "GLES2 CPU alpha-composition slices stay within the 6 ms target plus timer-check granularity")
	return comparison["alpha_error_pixels_over_1"] == 0 and comparison["rgb_error_pixels_over_1"] == 0


func _test_pass_cap_releases_stage():
	var owner = Node.new()
	owner.name = "GpuStrokePassLimitTest"
	get_root().add_child(owner)
	var source = _solid_image(8, 8, Color(0.8, 0.3, 0.6, 0.9))
	var points = []
	for point_index in range(1026):
		points.append([float(point_index) * 0.001, 4.0])
	var stroke = {"radius": 1.0, "hardness": 0.5}
	var pending = mask.render_gpu_stroke_async(source, stroke, points, Transform2D(), owner)
	var result = yield(pending, "completed")
	yield(self, "idle_frame")
	var released = owner.get_child_count() == 0
	owner.queue_free()
	var limited = not bool(result.get("ok", true)) and str(result.get("error", "")).find("1024-point / 64-pass") >= 0
	report["pass_limit"] = {"result": result, "released": released, "limited": limited}
	return released and limited


func _test_owner_unload_cleanup():
	var owner = Node.new()
	owner.name = "GpuStrokeOwnerUnloadTest"
	get_root().add_child(owner)
	var source = _solid_image(32, 32, Color(1.0, 1.0, 1.0, 1.0))
	var stroke = {"points": [[4.5, 15.5], [27.5, 15.5]], "radius": 6.0, "hardness": 0.5}
	var pending = mask.render_gpu_stroke_async(source, stroke, stroke["points"], Transform2D(), owner)
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var stage_created = owner.get_child_count() > 0
	get_root().remove_child(owner)
	var result = yield(pending, "completed")
	yield(self, "idle_frame")
	var released = owner.get_child_count() == 0
	owner.free()
	var cancelled = not bool(result.get("ok", true)) and str(result.get("error", "")).find("left the tree") >= 0
	report["owner_unload"] = {"stage_created": stage_created, "result": result, "released": released, "cancelled": cancelled}
	return stage_created and released and cancelled


func _solid_image(width: int, height: int, color: Color) -> Image:
	var image = Image.new()
	image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _compare_images(expected: Image, actual: Image) -> Dictionary:
	var result = {"max_alpha_error_bytes": 0, "alpha_error_pixels_over_1": 0, "rgb_error_pixels_over_1": 0, "max_rgb_error_bytes": 0, "first_expected_rgba": [], "first_actual_rgba": []}
	if expected == null or actual == null or expected.get_size() != actual.get_size():
		result["alpha_error_pixels_over_1"] = 1
		result["rgb_error_pixels_over_1"] = 1
		return result
	var expected_data = expected.get_data()
	var actual_data = actual.get_data()
	for channel in range(4):
		result["first_expected_rgba"].append(int(expected_data[channel]))
		result["first_actual_rgba"].append(int(actual_data[channel]))
	for pixel_index in range(expected.get_width() * expected.get_height()):
		var byte_index = pixel_index * 4
		var max_rgb_error = 0
		for channel in range(3):
			max_rgb_error = max(max_rgb_error, abs(int(expected_data[byte_index + channel]) - int(actual_data[byte_index + channel])))
		result["max_rgb_error_bytes"] = max(int(result["max_rgb_error_bytes"]), max_rgb_error)
		if max_rgb_error > 1:
			result["rgb_error_pixels_over_1"] += 1
		var alpha_error = abs(int(expected_data[byte_index + 3]) - int(actual_data[byte_index + 3]))
		result["max_alpha_error_bytes"] = max(int(result["max_alpha_error_bytes"]), alpha_error)
		if alpha_error > 1:
			result["alpha_error_pixels_over_1"] += 1
	return result


func _same_bytes(first: PoolByteArray, second: PoolByteArray) -> bool:
	if first.size() != second.size():
		return false
	for byte_index in range(first.size()):
		if int(first[byte_index]) != int(second[byte_index]):
			return false
	return true


func _expect(condition: bool, message: String):
	var line = ("PASS: " if condition else "FAIL: ") + message
	tests.append(line)
	if not condition:
		failures.append(message)
	print(line)


func _finish():
	report["result"] = "FAIL" if not failures.empty() else "PASS"
	report["failures"] = failures
	report["tests"] = tests
	var file = File.new()
	if file.open(ARTIFACT_PATH, File.WRITE) == OK:
		file.store_string(JSON.print(report, "\t"))
		file.close()
	print("MASK_GPU_STROKE_REPORT=" + JSON.print(report))
	quit(1 if not failures.empty() else 0)
