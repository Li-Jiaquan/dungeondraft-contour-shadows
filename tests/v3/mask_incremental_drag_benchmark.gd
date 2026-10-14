extends SceneTree

const MASK_PATH = "res://.staged/shadow_mask_incremental.gd"
const ARTIFACT_PATH = "res://v3/artifacts/mask-incremental-drag-benchmark-render-v3.json"
const PIXEL_BUDGET = 4096
const TIME_BUDGET_USEC = 6000

var report = {"engine": "Godot 3.4.2 Mono", "driver": "GLES2", "fixtures": [], "failures": []}


func _init():
	call_deferred("_run")


func _run():
	var mask_script = load(MASK_PATH)
	if mask_script == null:
		report["failures"].append("staged shadow_mask.gd did not parse")
		_finish()
		return
	var mask = mask_script.new()
	for side in [256, 512]:
		var source = _solid_image(side, Color(0.8, 0.55, 0.3, 0.8))
		var prior_strokes = _stroke_set(side, 8, 8, 22.0)
		var active = _curved_stroke(side, 32, 22.0)
		var visible_before = mask.apply(source, prior_strokes, Transform2D())
		var fixture = _benchmark_drag(mask, source, visible_before, prior_strokes, active, "radius22_%d" % side)
		report["fixtures"].append(fixture)
		print("MASK_INCREMENTAL_DRAG=" + JSON.print(fixture))
		var wide_active = _curved_stroke(side, 32, 256.0)
		var wide = _benchmark_incremental_only(mask, visible_before, wide_active, "radius256_%d" % side)
		report["fixtures"].append(wide)
		print("MASK_INCREMENTAL_WIDE=" + JSON.print(wide))
	_finish()


func _benchmark_drag(mask, source: Image, visible_before: Image, prior_strokes: Array, active: Dictionary, fixture_name: String) -> Dictionary:
	var started = OS.get_ticks_usec()
	var replay_times = []
	var replay_final = Image.new()
	for point_count in range(1, active["points"].size() + 1):
		var replay_strokes = prior_strokes.duplicate()
		replay_strokes.append({
			"points": _prefix(active["points"], point_count),
			"radius": active["radius"],
			"hardness": active["hardness"]
		})
		var replay_started = OS.get_ticks_usec()
		replay_final = mask.apply(source, replay_strokes, Transform2D())
		replay_times.append(OS.get_ticks_usec() - replay_started)
	var replay_total_usec = OS.get_ticks_usec() - started

	var incremental = _drain_incremental(mask, visible_before, active)
	var final_expected = mask.apply(source, _append_stroke(prior_strokes, active), Transform2D())
	var incremental_matches = _images_equal(final_expected, incremental["state"]["image"])
	var replay_matches = _images_equal(final_expected, replay_final)
	if not incremental_matches or not replay_matches:
		report["failures"].append("%s output differs from synchronous apply" % fixture_name)
	var replay_sorted = replay_times.duplicate()
	replay_sorted.sort()
	var replay_per_update = []
	for elapsed in replay_times:
		replay_per_update.append(float(elapsed) / 1000.0)
	var result = {
		"fixture": fixture_name,
		"size": [source.get_width(), source.get_height()],
		"prior_stroke_count": prior_strokes.size(),
		"active_point_count": active["points"].size(),
		"radius": active["radius"],
		"replay_total_ms": float(replay_total_usec) / 1000.0,
		"replay_median_update_ms": float(replay_sorted[replay_sorted.size() / 2]) / 1000.0,
		"replay_update_ms": replay_per_update,
		"incremental_total_ms": incremental["total_ms"],
		"incremental_frames": incremental["frames"],
		"incremental_frames_after_release": incremental["frames_after_release"],
		"incremental_max_advance_ms": float(incremental["max_advance_usec"]) / 1000.0,
		"incremental_p95_advance_ms": float(incremental["p95_advance_usec"]) / 1000.0,
		"incremental_total_processed_pixels": incremental["total_processed_pixels"],
		"incremental_total_touched_pixels": incremental["state"]["total_touched_pixels"],
		"incremental_matches_apply": incremental_matches,
		"replay_matches_apply": replay_matches
	}
	return result


func _benchmark_incremental_only(mask, visible_before: Image, active: Dictionary, fixture_name: String) -> Dictionary:
	var incremental = _drain_incremental(mask, visible_before, active)
	return {
		"fixture": fixture_name,
		"size": [visible_before.get_width(), visible_before.get_height()],
		"active_point_count": active["points"].size(),
		"radius": active["radius"],
		"incremental_total_ms": incremental["total_ms"],
		"incremental_frames": incremental["frames"],
		"incremental_frames_after_release": incremental["frames_after_release"],
		"incremental_max_advance_ms": float(incremental["max_advance_usec"]) / 1000.0,
		"incremental_p95_advance_ms": float(incremental["p95_advance_usec"]) / 1000.0,
		"incremental_total_processed_pixels": incremental["total_processed_pixels"],
		"incremental_total_touched_pixels": incremental["state"]["total_touched_pixels"],
		"pending_after_drain": incremental["pending"]
	}


func _drain_incremental(mask, visible_before: Image, active: Dictionary) -> Dictionary:
	var started = OS.get_ticks_usec()
	var state = mask.begin_incremental(visible_before, {"radius": active["radius"], "hardness": active["hardness"]}, Transform2D())
	if not bool(state.get("ok", false)):
		report["failures"].append("begin_incremental failed: %s" % state.get("error", "unknown"))
		return {"state": state, "frames": 0, "frames_after_release": 0, "max_advance_usec": 0, "p95_advance_usec": 0, "total_processed_pixels": 0, "total_ms": 0.0, "pending": false}
	var frame_times = []
	var total_processed = 0
	var point_count = active["points"].size()
	var release_frame_count = 0
	var result = {"ok": true, "pending": false}
	for point_index in range(point_count):
		var points = active["points"]
		if point_index == 0:
			mask.enqueue_incremental(state, [points[point_index]])
		else:
			mask.enqueue_incremental(state, [points[point_index - 1], points[point_index]])
		result = mask.advance_incremental(state, PIXEL_BUDGET, TIME_BUDGET_USEC)
		frame_times.append(int(result.get("elapsed_usec", 0)))
		total_processed += int(result.get("processed_pixels", 0))
		if point_index == point_count - 1:
			release_frame_count = frame_times.size()
		if frame_times.size() > 100000:
			report["failures"].append("incremental frame loop exceeded safety limit")
			break
	while bool(result.get("pending", false)) and frame_times.size() < 100000:
		result = mask.advance_incremental(state, PIXEL_BUDGET, TIME_BUDGET_USEC)
		frame_times.append(int(result.get("elapsed_usec", 0)))
		total_processed += int(result.get("processed_pixels", 0))
	if bool(result.get("pending", false)):
		report["failures"].append("incremental drain did not complete")
	var frame_times_sorted = frame_times.duplicate()
	frame_times_sorted.sort()
	var maximum = frame_times_sorted[frame_times_sorted.size() - 1] if not frame_times_sorted.empty() else 0
	var p95_index = int(ceil(float(frame_times_sorted.size()) * 0.95)) - 1
	var p95 = frame_times_sorted[clamp(p95_index, 0, frame_times_sorted.size() - 1)] if not frame_times_sorted.empty() else 0
	return {
		"state": state,
		"frames": frame_times.size(),
		"frames_after_release": max(0, frame_times.size() - release_frame_count),
		"max_advance_usec": maximum,
		"p95_advance_usec": p95,
		"total_processed_pixels": total_processed,
		"total_ms": float(OS.get_ticks_usec() - started) / 1000.0,
		"pending": bool(result.get("pending", false))
	}


func _solid_image(side: int, color: Color) -> Image:
	var image = Image.new()
	image.create(side, side, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _stroke_set(side: int, stroke_count: int, point_count: int, radius: float) -> Array:
	var strokes = []
	for stroke_index in range(stroke_count):
		var y = float(side) * (0.12 + 0.76 * float(stroke_index) / float(max(1, stroke_count - 1)))
		var points = []
		for point_index in range(point_count):
			var ratio = float(point_index) / float(max(1, point_count - 1))
			points.append([float(side) * (0.12 + 0.76 * ratio), y])
		strokes.append({"points": points, "radius": radius, "hardness": 0.7})
	return strokes


func _curved_stroke(side: int, point_count: int, radius: float) -> Dictionary:
	var points = []
	for point_index in range(point_count):
		var ratio = float(point_index) / float(max(1, point_count - 1))
		var x = float(side) * (0.2 + 0.6 * ratio)
		var y = float(side) * (0.5 + 0.025 * sin(ratio * PI * 4.0))
		points.append([x, y])
	return {"points": points, "radius": radius, "hardness": 0.7}


func _prefix(points: Array, count: int) -> Array:
	var result = []
	for index in range(count):
		result.append(points[index])
	return result


func _append_stroke(strokes: Array, stroke: Dictionary) -> Array:
	var result = strokes.duplicate()
	result.append(stroke)
	return result


func _images_equal(first: Image, second: Image) -> bool:
	if first == null or second == null or first.get_size() != second.get_size():
		return false
	return first.get_data() == second.get_data()


func _finish():
	report["result"] = "FAIL" if not report["failures"].empty() else "PASS"
	var file = File.new()
	if file.open(ARTIFACT_PATH, File.WRITE) == OK:
		file.store_string(JSON.print(report, "\t"))
		file.close()
	print("MASK_INCREMENTAL_DRAG_REPORT=" + JSON.print(report))
	quit(1 if not report["failures"].empty() else 0)
