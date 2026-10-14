extends SceneTree

const HOST_PATH = "res://.staged/eraser-gpu-controller/contour_shadows.gd"
const MASK_PATH = "res://.staged/eraser-gpu-controller/shadow_mask.gd"
const REPORT_PATH = "res://v3/artifacts/eraser-gpu-controller-report.json"

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
	var CurrentMapFile = "res://eraser-gpu-controller-fixture.dungeondraft_map"

	func get_CurrentMapFile():
		return CurrentMapFile

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

class MockWorld:
	extends Reference
	var Title = "GPU eraser controller"
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

class MockGlobal:
	extends Reference
	var Root = "res://.staged/eraser-gpu-controller/"
	var World = null
	var WorldUI = null
	var Editor = null
	var ModMapData = {}

class DeferredGpuMask:
	extends Reference
	var delegate = null
	var calls = []
	var outputs = []
	var active_count = 0
	var completed_count = 0

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

	func render_gpu_stroke_async(visible_image, stroke_template, local_points, pixel_to_local, owner_node):
		active_count += 1
		var call_index = calls.size()
		calls.append({
			"baseline_id": int(visible_image.get_instance_id()),
			"point_count": local_points.size(),
			"points": local_points.duplicate(true),
			"completed_before": completed_count,
			"owner_id": int(owner_node.get_instance_id()) if is_instance_valid(owner_node) else -1
		})
		# Keep the coroutine pending across two rendered idle frames so tests can
		# append points, cancel jobs, and enqueue later strokes while it is active.
		yield(Engine.get_main_loop(), "idle_frame")
		yield(Engine.get_main_loop(), "idle_frame")
		var stroke = stroke_template.duplicate(true)
		stroke["points"] = local_points.duplicate(true)
		var image = delegate.call("apply", visible_image, [stroke], pixel_to_local)
		outputs.append({"call_index": call_index, "image_id": int(image.get_instance_id())})
		completed_count += 1
		active_count -= 1
		return {
			"ok": true,
			"image": image,
			"backend": "fake_gpu",
			"elapsed_ms": 1.0,
			"cpu_composite_frames": 0
		}

var failures = []
var assertions = []
var host = null
var mask = null
var fixture = {}


func _init():
	call_deferred("_run")


func _run():
	var host_script = load(HOST_PATH)
	var mask_script = load(MASK_PATH)
	_expect(host_script != null, "staged host parses")
	_expect(mask_script != null, "staged shadow mask parses")
	if host_script == null or mask_script == null:
		_finish()
		return
	host = host_script.new()
	mask = DeferredGpuMask.new()
	mask.delegate = mask_script.new()
	host._shadow_mask = mask
	fixture = _make_fixture(2201)
	get_root().add_child(fixture.level)
	var preview_operation = _test_preview_coalescing_and_fixed_baseline()
	if preview_operation is GDScriptFunctionState:
		preview_operation = yield(preview_operation, "completed")
	_reset_fixture()
	var undo_operation = _test_undo_during_inflight_preview()
	if undo_operation is GDScriptFunctionState:
		undo_operation = yield(undo_operation, "completed")
	_reset_fixture()
	var fifo_operation = _test_same_source_gpu_fifo()
	if fifo_operation is GDScriptFunctionState:
		fifo_operation = yield(fifo_operation, "completed")
	host.Global = null
	host = null
	fixture.level.queue_free()
	yield(self, "idle_frame")
	_finish()


func _make_fixture(node_id: int) -> Dictionary:
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
	host.Global = global
	host._eraser_level_id = int(level.ID)
	host._eraser_map_file = editor.CurrentMapFile
	host._map_recipe_writable = true
	host.eraser_radius = 80.0
	host.eraser_hardness = 0.7

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

	var shadow_image = _solid_image(192, 192, Color(0.2, 0.4, 0.8, 0.82))
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

	host._shadow_render_cache[str(node_id)] = {
		"image": shadow_image.duplicate(),
		"visible_image": shadow_image.duplicate(),
		"pixel_to_local": Transform2D(),
		"kind": "prop",
		"visible_used_rect": Rect2(Vector2.ZERO, Vector2(192, 192)),
		"source_transform": prop.global_transform,
		"texture": shadow_texture
	}
	host._enabled_node_ids[str(node_id)] = true
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
		"shadow_sprite": shadow_sprite,
		"shadow_texture": shadow_texture,
		"shadow_image": shadow_image,
		"node_id": node_id
	}


func _test_preview_coalescing_and_fixed_baseline():
	var key = str(fixture.node_id)
	var cache = host._shadow_render_cache[key]
	var baseline = cache.image.duplicate()
	var baseline_id = int(cache.visible_image.get_instance_id())
	host.call("_apply_eraser_segment", Vector2(20, 96), Vector2(58, 96))
	host.call("_process_eraser_jobs")
	_expect(host._eraser_gpu_inflight and mask.calls.size() == 1, "large stroke launches one deferred GPU preview")
	_expect(mask.calls[0].point_count == 2 and mask.calls[0].baseline_id == baseline_id, "first GPU preview snapshots the initial two points and original baseline")
	host.call("_apply_eraser_segment", Vector2(58, 96), Vector2(96, 112))
	host.call("_apply_eraser_segment", Vector2(96, 112), Vector2(150, 96))
	host.call("_finish_eraser_stroke", true, false)
	host.call("_process_eraser_jobs")
	_expect(mask.calls.size() == 1, "new motion coalesces while the first GPU snapshot is in flight")
	var drain_operation = _drain_gpu(40)
	var drain = drain_operation
	if drain_operation is GDScriptFunctionState:
		drain = yield(drain_operation, "completed")
	cache = host._shadow_render_cache[key]
	var expected = mask.delegate.apply(baseline, host._erasures[key], Transform2D())
	_expect(bool(drain.drained), "coalesced GPU previews drain the closed gesture")
	_expect(mask.calls.size() == 2 and mask.calls[1].point_count == 4, "only the newest full point snapshot is rendered after the first preview")
	_expect(mask.calls[0].baseline_id == baseline_id and mask.calls[1].baseline_id == baseline_id, "successive previews always start from the same stroke baseline")
	_expect(_images_equal(expected, cache.visible_image), "coalesced previews produce the exact single-stroke replay without soft-edge accumulation")
	_expect(mask.active_count == 0 and mask.completed_count == 2, "both deferred GPU callbacks return and release their active count")


func _test_undo_during_inflight_preview():
	var key = str(fixture.node_id)
	var cache = host._shadow_render_cache[key]
	var baseline = cache.image.duplicate()
	var texture_id = int(cache.texture.get_instance_id())
	host.call("_apply_eraser_segment", Vector2(20, 96), Vector2(58, 96))
	host.call("_finish_eraser_stroke", true, false)
	host.call("_process_eraser_jobs")
	_expect(host._eraser_gpu_inflight and host._eraser_pending_jobs.has(key), "undo fixture has a live GPU callback and queued job")
	var undo_result = host.call("undo_last_erase")
	cache = host._shadow_render_cache[key]
	_expect(undo_result.get("ok", false) and int(undo_result.get("restored", 0)) == 1, "undo removes the stroke while its GPU callback is pending")
	_expect(host._eraser_pending_jobs.empty() and host._eraser_gpu_inflight, "undo cancels the job but keeps the global GPU slot occupied until the coroutine returns")
	_expect(_images_equal(baseline, cache.visible_image) and int(cache.texture.get_instance_id()) == texture_id, "undo restores the baseline through the existing ImageTexture")
	var wait_operation = _wait_for_gpu_callback(12)
	if wait_operation is GDScriptFunctionState:
		wait_operation = yield(wait_operation, "completed")
	cache = host._shadow_render_cache[key]
	_expect(not host._eraser_gpu_inflight and mask.active_count == 0, "cancelled GPU callback releases its global slot when it returns")
	_expect(_images_equal(baseline, cache.visible_image) and int(cache.texture.get_instance_id()) == texture_id, "stale GPU result cannot overwrite the post-undo baseline")
	_expect(not host._erasures.has(key), "undo leaves no serialized erasure stroke behind")


func _test_same_source_gpu_fifo():
	var key = str(fixture.node_id)
	var baseline = host._shadow_render_cache[key].image.duplicate()
	host.call("_apply_eraser_segment", Vector2(20, 64), Vector2(62, 64))
	host.call("_finish_eraser_stroke", true, false)
	host.call("_apply_eraser_segment", Vector2(26, 136), Vector2(68, 136))
	host.call("_finish_eraser_stroke", true, false)
	var queue = host._eraser_pending_jobs.get(key, [])
	_expect(queue.size() == 2 and int(queue[0].stroke_index) == 0 and int(queue[1].stroke_index) == 1, "two rapid wide strokes queue in per-source recipe order")
	var drain_operation = _drain_gpu(60)
	var drain = drain_operation
	if drain_operation is GDScriptFunctionState:
		drain = yield(drain_operation, "completed")
	var cache = host._shadow_render_cache[key]
	var expected = mask.delegate.apply(baseline, host._erasures[key], Transform2D())
	_expect(bool(drain.drained) and mask.calls.size() == 2, "same-source FIFO renders both closed strokes")
	if mask.calls.size() >= 2 and mask.outputs.size() >= 1:
		_expect(mask.calls[1].completed_before >= 1, "the second GPU stroke starts only after the first callback completes")
		_expect(mask.calls[1].baseline_id == mask.outputs[0].image_id, "the second stroke starts from the first stroke's final visible image")
	_expect(_images_equal(expected, cache.visible_image), "GPU FIFO result matches full multi-stroke replay exactly")


func _drain_gpu(max_frames: int) -> Dictionary:
	var report = {"drained": false, "frames": 0}
	while report.frames < max_frames:
		host.call("_process_eraser_jobs")
		report.frames += 1
		if host._eraser_pending_jobs.empty() and not host._eraser_gpu_inflight:
			report.drained = true
			return report
		yield(self, "idle_frame")
	return report


func _wait_for_gpu_callback(max_frames: int) -> Dictionary:
	var report = {"returned": false, "frames": 0}
	while report.frames < max_frames and host._eraser_gpu_inflight:
		report.frames += 1
		yield(self, "idle_frame")
		host.call("_process_eraser_jobs")
	report.returned = not host._eraser_gpu_inflight
	return report


func _reset_fixture():
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
	cache.texture.set_data(cache.visible_image)
	mask.calls.clear()
	mask.outputs.clear()
	mask.active_count = 0
	mask.completed_count = 0
	host._eraser_last_backend = "none"
	host._last_error = ""


func _solid_image(width: int, height: int, color: Color) -> Image:
	var image = Image.new()
	image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _images_equal(first: Image, second: Image) -> bool:
	if first == null or second == null or first.is_empty() or second.is_empty() or first.get_size() != second.get_size():
		return false
	return first.get_data() == second.get_data()


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
	print("ERASER_GPU_CONTROLLER_REPORT=" + JSON.print(report))
	quit(0 if failures.empty() else 1)
