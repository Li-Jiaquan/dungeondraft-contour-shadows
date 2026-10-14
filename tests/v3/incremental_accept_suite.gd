extends SceneTree

const HOST_PATH = "res://.staged/incremental-accept/contour_shadows.gd"
const MASK_PATH = "res://.staged/incremental-accept/shadow_mask.gd"
const DRIVER_PATH = "res://.staged/incremental-accept/integration_driver.gd"
const REPORT_PATH = "res://v3/artifacts/incremental-accept-report.json"

class MockProp:
	extends Node2D
	var _sprite_node = null

	func get_Sprite():
		return _sprite_node

class MockSelectTool:
	extends Reference
	var _selected = []

	func get_Selected():
		return _selected

class MockEditor:
	extends Reference
	var Tools = {}
	var ActiveToolName = "SelectTool"
	var CurrentMapFile = "res://incremental-acceptance-fixture.dungeondraft_map"

	func get_CurrentMapFile():
		return CurrentMapFile

class MockWorld:
	extends Reference
	var Title = "Incremental Acceptance"
	var current_level = null
	var levels = []

	func GetCurrentLevel():
		return current_level

	func GetNodeByID(node_id):
		for level in levels:
			for node in level.Objects.get_children():
				if node.has_meta("node_id") and int(node.get_meta("node_id")) == int(node_id):
					return node
			for node in level.Pathways.get_children():
				if node.has_meta("node_id") and int(node.get_meta("node_id")) == int(node_id):
					return node
		return null

class MockLevel:
	extends Node2D
	var ID = 0
	var Objects = null
	var Pathways = null

	func _init():
		Objects = Node2D.new()
		Objects.name = "Objects"
		add_child(Objects)
		Pathways = Node2D.new()
		Pathways.name = "Pathways"
		add_child(Pathways)

class MockGlobal:
	extends Reference
	var Root = "res://.staged/"
	var World = null
	var WorldUI = null
	var Editor = null
	var ModMapData = {}

class CpuIncrementalMask:
	extends Reference
	var delegate = null

	func apply(image, strokes, pixel_to_local):
		return delegate.call("apply", image, strokes, pixel_to_local)

	func intersects(image, stroke, pixel_to_local):
		return delegate.call("intersects", image, stroke, pixel_to_local)

	func begin_incremental(image, stroke_template, pixel_to_local):
		return delegate.call("begin_incremental", image, stroke_template, pixel_to_local)

	func enqueue_incremental(state, local_points):
		return delegate.call("enqueue_incremental", state, local_points)

	func advance_incremental(state, max_pixels, max_usec):
		return delegate.call("advance_incremental", state, max_pixels, max_usec)

var failures = []
var assertions = []
var host = null
var mask = null
var fixture = {}
var stage_file = null


func _init():
	stage_file = File.new()
	if stage_file.open("res://v3/artifacts/incremental-accept.stages.log", File.WRITE) == OK:
		stage_file.store_line("suite_init")
		stage_file.flush()
	call_deferred("_run")


func _run():
	_stage("load_scripts")
	var host_script = load(HOST_PATH)
	var mask_script = load(MASK_PATH)
	var driver_script = load(DRIVER_PATH)
	_expect(host_script != null, "incremental acceptance host parses")
	_expect(mask_script != null, "incremental mask parses")
	_expect(driver_script != null, "native route/performance driver parses")
	if host_script == null or mask_script == null or driver_script == null:
		_finish()
		return
	mask = CpuIncrementalMask.new()
	mask.delegate = mask_script.new()
	host = host_script.new()
	_stage("make_fixture")
	fixture = _make_fixture(host, 256, 256, 1401)
	_stage("add_level")
	get_root().add_child(fixture.level)
	_stage("live_stroke_begin")
	var live_stroke_operation = _test_open_stroke_extensions()
	if live_stroke_operation is GDScriptFunctionState:
		yield(live_stroke_operation, "completed")
	_reset_fixture_erasures()
	_stage("fifo_begin")
	var fifo_operation = _test_fifo_drain_matches_full_replay()
	if fifo_operation is GDScriptFunctionState:
		yield(fifo_operation, "completed")
	_stage("undo_begin")
	_test_undo_cancels_pending_work()
	_stage("restore_begin")
	_test_restore_cancels_pending_work()
	_stage("stale_begin")
	_test_transform_staleness_cancels_jobs()
	_stage("cleanup")
	host.Global = null
	host = null
	fixture.level.queue_free()
	yield(VisualServer, "frame_post_draw")
	_finish()


func _make_fixture(controller, width: int, height: int, node_id: int) -> Dictionary:
	var level = MockLevel.new()
	var selection = MockSelectTool.new()
	var editor = MockEditor.new()
	editor.Tools = {"SelectTool": selection}
	var world = MockWorld.new()
	world.current_level = level
	world.levels = [level]
	var global = MockGlobal.new()
	global.World = world
	global.Editor = editor
	global.ModMapData = {}
	controller.Global = global
	controller._shadow_mask = mask
	controller._eraser_level_id = int(level.ID)
	controller._eraser_map_file = editor.CurrentMapFile
	controller.eraser_radius = 24.0
	controller.eraser_hardness = 0.55
	controller._map_recipe_writable = true

	var prop = MockProp.new()
	prop.set_meta("node_id", node_id)
	var source_image = _solid_image(8, 8, Color(0.3, 0.7, 0.2, 0.9))
	var source_texture = ImageTexture.new()
	source_texture.create_from_image(source_image)
	var source_sprite = Sprite.new()
	source_sprite.texture = source_texture
	prop._sprite_node = source_sprite
	prop.add_child(source_sprite)
	level.Objects.add_child(prop)

	var shadow_image = _solid_image(width, height, Color(0.2, 0.4, 0.8, 0.82))
	var shadow_texture = ImageTexture.new()
	shadow_texture.create_from_image(shadow_image)
	var wrapper = Node2D.new()
	wrapper.name = "__ContourShadows"
	wrapper.set_meta("contour_shadows_owner", "contour_shadows")
	var shadow_sprite = Sprite.new()
	shadow_sprite.centered = false
	shadow_sprite.texture = shadow_texture
	shadow_sprite.set_meta("contour_shadows_owner", "contour_shadows")
	wrapper.add_child(shadow_sprite)
	prop.add_child(wrapper)
	controller._shadow_render_cache[str(node_id)] = {
		"image": shadow_image.duplicate(),
		"visible_image": shadow_image.duplicate(),
		"pixel_to_local": Transform2D(),
		"kind": "prop",
		"visible_used_rect": Rect2(Vector2.ZERO, Vector2(width, height)),
		"source_transform": prop.global_transform,
		"texture": shadow_texture
	}
	controller._enabled_node_ids[str(node_id)] = true
	selection._selected = [prop]
	return {
		"level": level,
		"world": world,
		"global": global,
		"editor": editor,
		"selection": selection,
		"prop": prop,
		"source_sprite": source_sprite,
		"source_texture": source_texture,
		"source_image_data": source_image.get_data(),
		"shadow_sprite": shadow_sprite,
		"shadow_texture": shadow_texture,
		"shadow_image": shadow_image,
		"node_id": node_id
	}


func _test_fifo_drain_matches_full_replay():
	var source_save = _source_snapshot()
	var base = fixture.shadow_image.duplicate()
	var texture_id = fixture.shadow_texture.get_instance_id()
	var gestures = [
		[Vector2(24, 38), Vector2(208, 38)],
		[Vector2(38, 214), Vector2(220, 214)],
		[Vector2(54, 64), Vector2(54, 198)],
		[Vector2(194, 60), Vector2(194, 200)],
		[Vector2(75, 85), Vector2(180, 170)],
		[Vector2(180, 85), Vector2(76, 171)]
	]
	for gesture in gestures:
		_begin_gesture(gesture[0], gesture[1])
		_close_gesture()
	var queue = host._eraser_pending_jobs.get(str(fixture.node_id), [])
	var queued_indices = []
	for job in queue:
		queued_indices.append(int(job.get("stroke_index", -1)))
	_expect(queued_indices == [0, 1, 2, 3, 4, 5], "rapid gestures queue FIFO jobs per source in stroke-history order")
	var expected = mask.apply(base, host._erasures[str(fixture.node_id)], Transform2D())
	var drain_operation = _drain_jobs(500)
	var drain = drain_operation
	if drain_operation is GDScriptFunctionState:
		drain = yield(drain_operation, "completed")
	var cache = host._shadow_render_cache[str(fixture.node_id)]
	_expect(bool(drain.get("drained", false)) and drain.frames > 1, "many queued strokes drain across bounded frame slices")
	_expect(_images_equal(expected, cache.visible_image), "many-stroke incremental output is byte-equal to full recipe replay")
	if not _images_equal(expected, cache.visible_image):
		var diff = _image_diff_report(expected, cache.visible_image)
		fixture.fifo_diff = diff
		print("FIFO_IMAGE_DIFF=" + JSON.print(diff))
	_expect(_source_snapshot() == source_save and fixture.source_texture.get_data().get_data() == fixture.source_image_data, "incremental work never changes source transform or source pixels")
	_expect(fixture.shadow_sprite.texture == fixture.shadow_texture and fixture.shadow_texture.get_instance_id() == texture_id, "drained work reuses the shadow ImageTexture instead of replacing it")
	_expect(int(drain.get("max_frame_pixels", 999999)) <= 4096, "all raster work slices obey the 4096-pixel frame budget")
	_expect(int(drain.get("max_frame_uploads", 999999)) <= 1, "a source texture is uploaded at most once per frame")
	_expect(int(drain.get("max_frame_work_usec", 999999)) <= 12000, "raster work stays within the 6 ms budget plus bounded engine overhead")
	_expect(int(drain.get("total_processed_pixels", 0)) > 4096, "large multi-stroke fixture exercises incremental work across frames")
	_expect(int(host.call("get_diagnostics").get("eraser_pending_jobs", -1)) == 0, "diagnostics report zero jobs after the queue drains")
	fixture.drain_report = drain
	fixture.expected_after_many = expected
	fixture.cache_after_many = cache
	_reset_fixture_erasures()


func _test_open_stroke_extensions():
	var key = str(fixture.node_id)
	var baseline_image = host._shadow_render_cache[key].image.duplicate()
	_begin_gesture(Vector2(30, 82), Vector2(102, 82))
	host.call("_process_eraser_jobs")
	var queue = host._eraser_pending_jobs.get(key, [])
	_expect(queue.size() == 1, "an open gesture owns one per-source incremental job after its first update")
	if queue.empty():
		return
	var first_frame_uploads = int(host.call("get_diagnostics").get("eraser_last_frame_uploads", 0))
	host.call("_apply_eraser_segment", Vector2(102, 82), Vector2(168, 132))
	var stroke = host._erasures[key][0]
	_expect(stroke.get("points", []).size() == 3 and host._eraser_pending_jobs[key].size() == 1, "new motion extends the active job without queuing a separate stroke")
	host.call("_process_eraser_jobs")
	_close_gesture()
	var drain_operation = _drain_jobs(120)
	var drain = drain_operation
	if drain_operation is GDScriptFunctionState:
		drain = yield(drain_operation, "completed")
	var expected = mask.apply(baseline_image, host._erasures.get(key, []), Transform2D())
	var cache = host._shadow_render_cache[key]
	_expect(bool(drain.get("drained", false)), "extended open-stroke work drains after release")
	_expect(_images_equal(expected, cache.visible_image), "streamed motion segments preserve full-recipe max-influence output")
	if not _images_equal(expected, cache.visible_image):
		var diff = _image_diff_report(expected, cache.visible_image)
		fixture.live_stroke_diff = diff
		print("LIVE_STROKE_IMAGE_DIFF=" + JSON.print(diff))
	_expect(first_frame_uploads <= 1 and int(drain.get("max_frame_uploads", 999999)) <= 1, "live updates upload the source texture no more than once per frame")
	_expect(int(host.call("get_diagnostics").get("eraser_gpu_render_count", 0)) == 0, "CPU acceptance does not dispatch the GPU preview path")
	fixture.live_stroke_report = drain


func _test_undo_cancels_pending_work():
	var prop = fixture.prop
	var key = str(fixture.node_id)
	var cache = host._shadow_render_cache[key]
	var base = cache.image.duplicate()
	var first = [Vector2(35, 112), Vector2(216, 112)]
	var second = [Vector2(128, 24), Vector2(128, 226)]
	_begin_gesture(first[0], first[1])
	_close_gesture()
	_begin_gesture(second[0], second[1])
	_close_gesture()
	var before_undo_jobs = int(host.call("get_diagnostics").get("eraser_pending_jobs", 0))
	var first_only_strokes = [host._erasures[key][host._erasures[key].size() - 2]]
	var first_only_expected = mask.apply(base, first_only_strokes, Transform2D())
	var undone = host.call("undo_last_erase")
	cache = host._shadow_render_cache[key]
	_expect(int(before_undo_jobs) >= 2, "undo fixture has multiple queued strokes before replay")
	_expect(undone.get("ok", false) and int(undone.get("restored", 0)) == 1, "undo removes exactly the most recent gesture while jobs are pending")
	_expect(host._eraser_pending_jobs.empty() and _images_equal(first_only_expected, cache.visible_image), "undo cancels stale queued jobs and restores precisely the preceding gesture")
	for _frame in range(3):
		host.call("_process_eraser_jobs")
	_expect(_images_equal(first_only_expected, host._shadow_render_cache[key].visible_image), "cancelled work cannot overwrite the post-undo image on later frames")
	var undone_first = host.call("undo_last_erase")
	cache = host._shadow_render_cache[key]
	_expect(undone_first.get("ok", false) and int(undone_first.get("restored", 0)) == 1 and _images_equal(base, cache.visible_image), "a second undo reaches the exact unedited baseline")


func _test_restore_cancels_pending_work():
	var key = str(fixture.node_id)
	var base = host._shadow_render_cache[key].image.duplicate()
	var source_save = _source_snapshot()
	_begin_gesture(Vector2(42, 128), Vector2(214, 128))
	_close_gesture()
	var had_pending = not host._eraser_pending_jobs.empty()
	var restored = host.call("restore_selected_erasures")
	var cache = host._shadow_render_cache[key]
	_expect(had_pending, "restore fixture begins while an incremental job is queued")
	_expect(restored.get("ok", false) and int(restored.get("restored", 0)) == 1, "restore-selected clears erasures while work is pending")
	_expect(host._eraser_pending_jobs.empty() and _images_equal(base, cache.visible_image), "restore cancels stale jobs and restores the exact base image")
	for _frame in range(3):
		host.call("_process_eraser_jobs")
	_expect(_images_equal(base, host._shadow_render_cache[key].visible_image), "cancelled restore work cannot re-erase pixels on a later frame")
	_expect(_source_snapshot() == source_save and fixture.source_texture.get_data().get_data() == fixture.source_image_data, "restore leaves the source object and source texture unchanged")


func _test_transform_staleness_cancels_jobs():
	var key = str(fixture.node_id)
	var base = host._shadow_render_cache[key].image.duplicate()
	_begin_gesture(Vector2(48, 90), Vector2(205, 90))
	_close_gesture()
	var had_pending = not host._eraser_pending_jobs.empty()
	fixture.prop.position = Vector2(11, 7)
	host.call("_process_eraser_jobs")
	_expect(had_pending, "transform-staleness fixture begins with pending incremental work")
	_expect(not host._eraser_pending_jobs.has(key), "source movement invalidates and drops its stale generation-token job")
	fixture.prop.position = Vector2.ZERO
	var saved = host._shadow_render_cache[key]
	saved["visible_image"] = base.duplicate()
	saved["source_transform"] = fixture.prop.global_transform
	host._shadow_render_cache[key] = saved


func _begin_gesture(from: Vector2, to: Vector2):
	host.call("_apply_eraser_segment", from, to)


func _close_gesture():
	host.call("_finish_eraser_stroke", true, false)


func _reset_fixture_erasures():
	host.call("_cancel_all_eraser_jobs")
	host._erasures.clear()
	host._erase_undo_stack.clear()
	host._eraser_stroke_by_node_id.clear()
	host._eraser_gesture_node_ids.clear()
	host._eraser_drawing = false
	var key = str(fixture.node_id)
	var cache = host._shadow_render_cache[key]
	cache["visible_image"] = cache.image.duplicate()
	cache["visible_used_rect"] = cache.visible_image.get_used_rect()
	host._shadow_render_cache[key] = cache
	fixture.shadow_texture.set_data(cache.visible_image)
	fixture.shadow_sprite.texture = fixture.shadow_texture
	fixture.expected_after_many = null


func _drain_jobs(max_frames: int) -> Dictionary:
	var report = {
		"drained": false,
		"frames": 0,
		"max_frame_pixels": 0,
		"max_frame_uploads": 0,
		"max_frame_work_usec": 0,
		"total_processed_pixels_before": int(host.get("_eraser_processed_pixels_total"))
	}
	while report.frames < max_frames and not host._eraser_pending_jobs.empty():
		host.call("_process_eraser_jobs")
		var diagnostics = host.call("get_diagnostics")
		report.frames += 1
		report.max_frame_pixels = max(int(report.max_frame_pixels), int(diagnostics.get("eraser_last_frame_processed_pixels", 0)))
		report.max_frame_uploads = max(int(report.max_frame_uploads), int(diagnostics.get("eraser_last_frame_uploads", 0)))
		var raster_usec = int(diagnostics.get("eraser_last_frame_usec", 0)) - int(diagnostics.get("eraser_last_frame_upload_usec", 0))
		report.max_frame_work_usec = max(int(report.max_frame_work_usec), raster_usec)
		yield(self, "idle_frame")
	report.drained = host._eraser_pending_jobs.empty()
	report.pending_after = int(host.call("get_diagnostics").get("eraser_pending_jobs", -1))
	report.total_processed_pixels = int(host.get("_eraser_processed_pixels_total")) - int(report.total_processed_pixels_before)
	return report


func _source_snapshot() -> String:
	return str(fixture.prop.global_transform) + "|" + str(fixture.prop.transform) + "|" + str(fixture.source_sprite.transform) + "|" + str(fixture.source_texture.get_size())


func _solid_image(width: int, height: int, color: Color) -> Image:
	var image = Image.new()
	image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _images_equal(first: Image, second: Image) -> bool:
	if first == null or second == null or first.is_empty() or second.is_empty() or first.get_size() != second.get_size():
		return false
	return first.get_data() == second.get_data()


func _image_diff_report(expected: Image, actual: Image) -> Dictionary:
	var expected_data = expected.get_data()
	var actual_data = actual.get_data()
	var result = {"byte_diff_count": 0, "alpha_diff_pixels": 0, "rgb_diff_pixels": 0, "first_differences": []}
	var pixel_seen = {}
	for byte_index in range(min(expected_data.size(), actual_data.size())):
		if expected_data[byte_index] == actual_data[byte_index]:
			continue
		result.byte_diff_count = int(result.byte_diff_count) + 1
		var pixel_index = int(byte_index / 4)
		var channel = byte_index % 4
		if not pixel_seen.has(pixel_index):
			pixel_seen[pixel_index] = true
			var pixel_x = pixel_index % expected.get_width()
			var pixel_y = int(pixel_index / expected.get_width())
			var base = pixel_index * 4
			if expected_data[base + 3] != actual_data[base + 3]:
				result.alpha_diff_pixels = int(result.alpha_diff_pixels) + 1
			else:
				result.rgb_diff_pixels = int(result.rgb_diff_pixels) + 1
			if result.first_differences.size() < 12:
				result.first_differences.append({"x": pixel_x, "y": pixel_y, "expected_rgba": [expected_data[base], expected_data[base + 1], expected_data[base + 2], expected_data[base + 3]], "actual_rgba": [actual_data[base], actual_data[base + 1], actual_data[base + 2], actual_data[base + 3]], "different_channel": channel})
	return result


func _expect(condition: bool, message: String):
	var line = ("PASS: " if condition else "FAIL: ") + message
	assertions.append(line)
	print(line)
	if not condition:
		failures.append(message)


func _finish():
	var report = {"result": "PASS" if failures.empty() else "FAIL", "failures": failures, "assertions": assertions}
	var file = File.new()
	if file.open(REPORT_PATH, File.WRITE) == OK:
		file.store_string(JSON.print(report, "\t"))
		file.close()
	print("INCREMENTAL_ACCEPT_REPORT=" + JSON.print(report))
	quit(0 if failures.empty() else 1)


func _stage(label: String):
	print("INCREMENTAL_STAGE=" + label)
	if stage_file != null and stage_file.is_open():
		stage_file.store_line(label)
		stage_file.flush()
