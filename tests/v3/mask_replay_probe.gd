extends SceneTree

const MASK_PATH = "res://.staged/shadow_mask_replay_probe.gd"
const ARTIFACT_PATH = "res://v3/artifacts/mask-replay-probe.json"
var report = {"engine": "Godot 3.4.2 Mono", "driver": "GLES2", "fixtures": []}
var failures = []


func _init():
	call_deferred("_run")


func _run():
	var mask_script = load(MASK_PATH)
	if mask_script == null:
		failures.append("staged shadow_mask.gd did not parse")
		_finish()
		return
	var mask = mask_script.new()
	for side in [256, 512]:
		var source = Image.new()
		source.create(side, side, false, Image.FORMAT_RGBA8)
		source.fill(Color(1.0, 1.0, 1.0, 0.8))
		var cases = [
			{"name": "one_stroke_2_points_%d" % side, "strokes": [_stroke(side, 2, side * 0.5, 22.0)]},
			{"name": "one_stroke_32_points_%d" % side, "strokes": [_stroke(side, 32, side * 0.5, 22.0)]},
			{"name": "eight_strokes_8_points_%d" % side, "strokes": _stroke_set(side, 8, 8, 22.0)}
		]
		for fixture in cases:
			var samples = []
			for repeat_index in range(3):
				var started = OS.get_ticks_usec()
				var output = mask.apply(source, fixture["strokes"], Transform2D())
				samples.append(float(OS.get_ticks_usec() - started) / 1000.0)
				if output == null or output.is_empty() or output.get_size() != source.get_size():
					failures.append("%s produced no valid image" % fixture["name"])
			var sorted_samples = samples.duplicate()
			sorted_samples.sort()
			var item = {"fixture": fixture["name"], "size": [side, side], "stroke_count": fixture["strokes"].size(), "point_counts": _point_counts(fixture["strokes"]), "samples_ms": samples, "median_ms": sorted_samples[1]}
			report["fixtures"].append(item)
			print("MASK_REPLAY=" + JSON.print(item))
	_finish()


func _stroke(side: int, point_count: int, center_y: float, radius: float) -> Dictionary:
	var points = []
	for point_index in range(point_count):
		var ratio = float(point_index) / float(max(1, point_count - 1))
		points.append([float(side) * (0.2 + 0.6 * ratio), center_y])
	return {"points": points, "radius": radius, "hardness": 0.7}


func _stroke_set(side: int, stroke_count: int, point_count: int, radius: float) -> Array:
	var strokes = []
	for stroke_index in range(stroke_count):
		var center_y = float(side) * (0.15 + 0.7 * float(stroke_index) / float(max(1, stroke_count - 1)))
		strokes.append(_stroke(side, point_count, center_y, radius))
	return strokes


func _point_counts(strokes: Array) -> Array:
	var counts = []
	for stroke in strokes:
		counts.append(stroke["points"].size())
	return counts


func _finish():
	report["result"] = "FAIL" if not failures.empty() else "PASS"
	report["failures"] = failures
	var file = File.new()
	if file.open(ARTIFACT_PATH, File.WRITE) == OK:
		file.store_string(JSON.print(report, "\t"))
		file.close()
	print("MASK_REPLAY_REPORT=" + JSON.print(report))
	quit(1 if not failures.empty() else 0)
