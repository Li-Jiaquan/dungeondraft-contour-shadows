extends SceneTree

const MASK_PATH = "res://.staged/shadow_mask_incremental.gd"
const ARTIFACT_PATH = "res://v3/artifacts/mask-incremental-report.json"

var mask = null
var failures = []
var test_lines = []
var metrics = {}


func _init():
	call_deferred("_run")


func _run():
	var mask_script = load(MASK_PATH)
	_expect(mask_script != null, "incremental mask parses")
	if mask_script == null:
		_finish()
		return
	mask = mask_script.new()
	_test_transformed_polyline_matches_apply()
	_test_hard_edge_and_duplicate_segments()
	_test_separate_strokes_accumulate_from_prior_visible_image()
	_test_batches_do_not_link_across_calls()
	_test_safe_collinear_queue_merge()
	_test_pixel_budget_cursor_and_dirty_rect()
	_finish()


func _test_transformed_polyline_matches_apply():
	var source = _solid_image(32, 22, Color(0.2, 0.4, 0.8, 0.75))
	var source_before = source.get_data()
	var pixel_to_local = Transform2D(Vector2(1.3, 0.2), Vector2(-0.25, 0.9), Vector2(2.0, -1.5))
	var stroke = {
		"points": [[3.5, 9.5], [11.5, 9.5], [17.5, 12.5], [26.5, 7.5]],
		"radius": 3.25,
		"hardness": 0.45,
		"radius_basis": [[1.4, 0.1], [0.2, 0.85]]
	}
	var expected = mask.apply(source, [stroke], pixel_to_local)
	var state = mask.begin_incremental(source, stroke, pixel_to_local)
	_expect(bool(state.get("ok", false)), "transformed stroke state initializes")
	if not bool(state.get("ok", false)):
		return
	_enqueue_polyline(state, stroke["points"])
	var result = _drain(state, 47, 100000)
	_expect(bool(result.get("ok", false)) and not bool(result.get("pending", true)), "transformed polyline drains in bounded chunks")
	_expect(_images_equal(expected, state["image"]), "incremental transformed soft stroke is byte-equal to apply")
	_expect(_rgb_equal(source, state["image"]), "incremental transformed stroke leaves RGB unchanged")
	_expect(source.get_data() == source_before, "incremental application does not mutate its input image")


func _test_hard_edge_and_duplicate_segments():
	var source = _solid_image(26, 14, Color(0.6, 0.3, 0.1, 0.8))
	var points = [[2.5, 7.5], [12.5, 7.5], [2.5, 7.5], [12.5, 7.5]]
	var stroke = {"points": points, "radius": 2.5, "hardness": 1.0}
	var expected = mask.apply(source, [stroke], Transform2D())
	var state = mask.begin_incremental(source, stroke, Transform2D())
	_enqueue_polyline(state, points)
	_drain(state, 29, 100000)
	_expect(_images_equal(expected, state["image"]), "duplicate/reversing hard segments use the same max influence as apply")


func _test_separate_strokes_accumulate_from_prior_visible_image():
	var source = _solid_image(30, 20, Color(0.15, 0.55, 0.35, 0.9))
	var first = {"points": [[4.5, 7.5], [22.5, 7.5]], "radius": 4.0, "hardness": 0.35}
	var second = {"points": [[14.5, 3.5], [14.5, 16.5]], "radius": 3.5, "hardness": 0.7}
	var expected = mask.apply(source, [first, second], Transform2D())
	var first_state = mask.begin_incremental(source, first, Transform2D())
	_enqueue_polyline(first_state, first["points"])
	_drain(first_state, 53, 100000)
	var second_state = mask.begin_incremental(first_state["image"], second, Transform2D())
	_enqueue_polyline(second_state, second["points"])
	_drain(second_state, 53, 100000)
	_expect(_images_equal(expected, second_state["image"]), "later incremental strokes multiply with earlier completed strokes exactly")
	_expect(_rgb_equal(source, second_state["image"]), "separate-stroke accumulation preserves RGB")


func _test_batches_do_not_link_across_calls():
	var source = _solid_image(22, 11, Color(1.0, 1.0, 1.0, 1.0))
	var template = {"radius": 0.75, "hardness": 1.0}
	var state = mask.begin_incremental(source, template, Transform2D())
	mask.enqueue_incremental(state, [[2.5, 5.5], [4.5, 5.5]])
	mask.enqueue_incremental(state, [[17.5, 5.5]])
	_drain(state, 17, 100000)
	_expect(_alpha(state["image"], 10, 5) > 0.98, "separate batches leave the gap intact without an implicit connector")
	_expect(_alpha(state["image"], 3, 5) < 0.02 and _alpha(state["image"], 17, 5) < 0.02, "each queued segment and point still erase their local coverage")


func _test_safe_collinear_queue_merge():
	var source = _solid_image(48, 28, Color(1.0, 1.0, 1.0, 0.8))
	var template = {"radius": 3.0, "hardness": 0.6}
	var state = mask.begin_incremental(source, template, Transform2D())
	mask.enqueue_incremental(state, [[8.5, 12.5], [18.5, 12.5]])
	mask.enqueue_incremental(state, [[18.5, 12.5], [28.5, 12.5]])
	_expect(state["segments"].size() == 1, "untouched adjacent collinear segments coalesce into one raster scan")
	var expected = mask.apply(source, [{"points": [[8.5, 12.5], [18.5, 12.5], [28.5, 12.5]], "radius": 3.0, "hardness": 0.6}], Transform2D())
	_drain(state, 37, 100000)
	_expect(_images_equal(expected, state["image"]), "collinear queue coalescing preserves the exact capsule result")
	var curved_state = mask.begin_incremental(source, template, Transform2D())
	mask.enqueue_incremental(curved_state, [[8.5, 12.5], [18.5, 12.5]])
	mask.enqueue_incremental(curved_state, [[18.5, 12.5], [28.5, 18.5]])
	_expect(curved_state["segments"].size() == 2, "curved queued segments are never shortcut together")
	var partial_state = mask.begin_incremental(source, template, Transform2D())
	mask.enqueue_incremental(partial_state, [[8.5, 12.5], [18.5, 12.5]])
	mask.advance_incremental(partial_state, 1, 100000)
	mask.enqueue_incremental(partial_state, [[18.5, 12.5], [28.5, 12.5]])
	_expect(partial_state["segments"].size() == 2, "a partially rasterized segment is never merged or rewound")


func _test_pixel_budget_cursor_and_dirty_rect():
	var source = _solid_image(64, 64, Color(1.0, 1.0, 1.0, 0.8))
	var template = {"radius": 256.0, "hardness": 1.0}
	var state = mask.begin_incremental(source, template, Transform2D())
	mask.enqueue_incremental(state, [[32.0, 32.0]])
	var first = mask.advance_incremental(state, 127, 100000)
	_expect(first.get("processed_pixels", 0) == 127 and first.get("pending", false), "advance stops at the requested pixel budget and retains its cursor")
	_expect(first.get("changed", false) and first.get("dirty_rect", Rect2()).size.x > 0, "changed advance reports a dirty rectangle")
	var calls = 1
	var largest_chunk = int(first.get("processed_pixels", 0))
	var result = first
	while bool(result.get("pending", false)) and calls < 100:
		result = mask.advance_incremental(state, 127, 100000)
		largest_chunk = max(largest_chunk, int(result.get("processed_pixels", 0)))
		calls += 1
	_expect(not result.get("pending", true) and calls > 1, "radius-256 single point eventually completes across frames")
	_expect(largest_chunk <= 127 and int(result.get("total_processed_pixels", 0)) == 64 * 64, "large brush obeys per-call cap while covering every candidate pixel")
	_expect(_alpha(state["image"], 32, 32) == 0.0, "bounded large-brush raster reaches its center")
	var full_size_source = _solid_image(512, 512, Color(1.0, 1.0, 1.0, 0.8))
	var timed_state = mask.begin_incremental(full_size_source, template, Transform2D())
	mask.enqueue_incremental(timed_state, [[256.0, 256.0]])
	var time_limited = mask.advance_incremental(timed_state, 512 * 512, 1)
	_expect(int(time_limited.get("processed_pixels", 512 * 512)) <= 64 and bool(time_limited.get("pending", false)), "one-microsecond budget stops the scan before the larger pixel cap")
	metrics["one_microsecond_budget"] = {
		"processed_pixels": time_limited.get("processed_pixels", -1),
		"elapsed_usec": time_limited.get("elapsed_usec", -1),
		"pending": time_limited.get("pending", false)
	}
	print("MASK_INCREMENTAL_TIME_BUDGET=" + JSON.print({"processed_pixels": time_limited.get("processed_pixels", -1), "elapsed_usec": time_limited.get("elapsed_usec", -1), "pending": time_limited.get("pending", false)}))


func _enqueue_polyline(state: Dictionary, points: Array):
	if points.size() == 1:
		mask.enqueue_incremental(state, [points[0]])
		return
	for point_index in range(points.size() - 1):
		mask.enqueue_incremental(state, [points[point_index], points[point_index + 1]])


func _drain(state: Dictionary, max_pixels: int, max_usec: int) -> Dictionary:
	var result = {"ok": true, "pending": true}
	var calls = 0
	while bool(result.get("pending", false)) and calls < 20000:
		result = mask.advance_incremental(state, max_pixels, max_usec)
		_expect(int(result.get("processed_pixels", 0)) <= max_pixels, "advance stays within its pixel budget")
		calls += 1
	_expect(calls < 20000, "incremental work queue terminates")
	return result


func _solid_image(width: int, height: int, color: Color) -> Image:
	var image = Image.new()
	image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _alpha(image: Image, x: int, y: int) -> float:
	image.lock()
	var value = image.get_pixel(x, y).a
	image.unlock()
	return value


func _images_equal(first: Image, second: Image) -> bool:
	if first == null or second == null or first.get_size() != second.get_size():
		return false
	var first_data = first.get_data()
	var second_data = second.get_data()
	if first_data.size() != second_data.size():
		return false
	for byte_index in range(first_data.size()):
		if first_data[byte_index] != second_data[byte_index]:
			print("MASK_INCREMENTAL_BYTE_MISMATCH=%d expected=%d actual=%d" % [byte_index, int(first_data[byte_index]), int(second_data[byte_index])])
			return false
	return true


func _rgb_equal(first: Image, second: Image) -> bool:
	if first.get_size() != second.get_size():
		return false
	var first_data = first.get_data()
	var second_data = second.get_data()
	for byte_index in range(first_data.size()):
		if byte_index % 4 != 3 and first_data[byte_index] != second_data[byte_index]:
			return false
	return true


func _expect(condition: bool, message: String):
	var line = ("PASS: " if condition else "FAIL: ") + message
	print(line)
	test_lines.append(line)
	if not condition:
		failures.append(message)


func _finish():
	var report = {"result": "PASS" if failures.empty() else "FAIL", "failures": failures, "tests": test_lines, "metrics": metrics}
	var file = File.new()
	if file.open(ARTIFACT_PATH, File.WRITE) == OK:
		file.store_string(JSON.print(report, "\t"))
		file.close()
	print("MASK_INCREMENTAL_REPORT=" + JSON.print(report))
	quit(0 if failures.empty() else 1)
