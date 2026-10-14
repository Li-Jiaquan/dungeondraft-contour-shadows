extends SceneTree

const TOLERANCE = 0.035

class MockProp:
	extends Node2D
	var _sprite_node = null

	func get_Sprite():
		return _sprite_node

	func _get(property):
		if str(property) == "Sprite":
			return _sprite_node
		return null

class MockSelectableProp:
	extends MockProp
	var select_calls = []
	var visually_selected = false

	func Select(value):
		select_calls.append(bool(value))
		visually_selected = bool(value)

class MockPathway:
	extends Line2D
	var Smoothness = 1.0
	var EditPoints = PoolVector2Array()
	var _fade_in = false
	var _fade_out = false
	var _grow = false
	var _shrink = false

	func Save(_copy = false):
		return {"fade_in": _fade_in, "fade_out": _fade_out, "grow": _grow, "shrink": _shrink, "smoothness": Smoothness}
	func get_FadeIn():
		return _fade_in
	func get_FadeOut():
		return _fade_out
	func get_Grow():
		return _grow
	func get_Shrink():
		return _shrink

	func SetEditPoints(points):
		EditPoints = points

	func Smooth():
		pass

class MockSelectTool:
	extends Reference
	var _selected = []
	var deselect_all_ex_calls = 0

	func get_Selected():
		return _selected

	func DeselectAllEx():
		# Deliberately leave the getter stale so the host's clear latch is tested.
		deselect_all_ex_calls += 1

class MockEditor:
	extends Reference
	var Tools = {}
	var ActiveToolName = "SelectTool"
	var CurrentMapFile = "res://mock-map.dungeondraft_map"
	var Toolset = null
	var on_select_tool_calls = []
	var tool_script = null

	func get_CurrentMapFile():
		return CurrentMapFile

	func OnSelectTool(tool_name):
		on_select_tool_calls.append(str(tool_name))
		if tool_script != null:
			tool_script.on_tool_disable(ActiveToolName)
		ActiveToolName = str(tool_name)
		if tool_script != null:
			tool_script.on_tool_enable(ActiveToolName)

class MockUiControl:
	extends Node
	signal pressed
	signal value_changed(value)
	signal item_selected(value)
	signal toggled(value)
	var value = 0.0
	var pressed_value = false
	var pressed = false

	func press():
		emit_signal("pressed")

	func select(index):
		value = int(index)

class MockToolPanel:
	extends Node
	var Tool = null
	var Align = null
	var buttons = {}

	func _init():
		Tool = Node.new()
		Tool.name = "MockRegisteredTool"
		Align = VBoxContainer.new()
		Align.name = "MockAlign"
		add_child(Tool)
		add_child(Align)

	func BeginSection(_collapsed):
		pass

	func EndSection():
		pass

	func CreateLabel(_text):
		return null

	func CreateSlider(_label, initial, _minimum, _maximum, _step, _integer):
		var control = _control()
		control.value = initial
		return control

	func CreateLabeledDropdownMenu(_label, _title, _items, _selected):
		return _control()

	func CreateColorPalette(_id, _compact, _color, _swatches, _a, _b):
		return _control()

	func CreateSeparator():
		pass

	func CreateButton(label, _icon):
		var control = _control()
		buttons[str(label)] = control
		return control

	func CreateCheckButton(_label, _icon, initial):
		var control = _control()
		control.pressed_value = initial
		control.pressed = initial
		return control

	func CreateNote(_text):
		pass

	func _control():
		var control = MockUiControl.new()
		Align.add_child(control)
		return control

class MockToolset:
	extends Reference
	var panel = null

	func CreateModTool(_controller, _category, _tool_id, _display_name, _icon):
		panel = MockToolPanel.new()
		return panel

	func press_button(label):
		if panel != null and panel.buttons.has(str(label)):
			panel.buttons[str(label)].press()

class MockGlobal:
	extends Reference
	var Root = "res://.staged/"
	var World = null
	var WorldUI = null
	var Editor = null
	var ModMapData = {}

class CountingRenderer:
	extends Reference
	var delegate = null
	var calls = 0
	func render(image, displacement, blur, mode, cutoff, limit):
		calls += 1
		return delegate.render(image, displacement, blur, mode, cutoff, limit)
	func get_work_limit():
		return delegate.get_work_limit()

class MockWorld:
	extends Reference
	var Title = "Mock Map"
	var current_level = null
	var levels = []

	func GetCurrentLevel():
		return current_level

	func GetNodeByID(node_id):
		for level in levels:
			for container in [level.Objects, level.Pathways]:
				if container == null:
					continue
				for node in container.get_children():
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

var failures = []
var report_lines = []
var renderer = null
var geometry = null
var path_source = null
var shadow_mask = null
var mock_hosts = []
var mock_levels = []
var mock_ui_panels = []

func _init():
	call_deferred("_run")

func _run():
	var renderer_script = load("res://.staged/shadow_renderer.gd")
	var geometry_script = load("res://.staged/shadow_geometry.gd")
	var path_source_script = load("res://.staged/path_source.gd")
	var shadow_mask_script = load("res://.staged/shadow_mask.gd")
	_expect(renderer_script != null, "renderer GDScript parses")
	_expect(geometry_script != null, "geometry GDScript parses")
	_expect(path_source_script != null, "Pathway source adapter GDScript parses")
	_expect(shadow_mask_script != null, "shadow mask eraser GDScript parses")
	if renderer_script == null or geometry_script == null or path_source_script == null or shadow_mask_script == null:
		_finish()
		return
	renderer = renderer_script.new()
	geometry = geometry_script.new()
	path_source = path_source_script.new()
	shadow_mask = shadow_mask_script.new()

	_test_manifest_and_host()
	_test_shadow_mask_erasures()
	yield(_test_pathway_alpha_capture(), "completed")
	_test_empty_and_hole()
	_test_alpha_gradient()
	_test_zero_and_negative_displacement()
	_test_blur_expansion()
	_test_sweep_uses_maximum_alpha()
	_test_sweep_step_limit()
	_test_large_image_limit()
	_test_downsample_preserves_alpha_details()
	_test_transform_vectors()
	_test_sprite_frame_region_flip_and_rect()
	_test_host_selection_and_lifecycle()
	_test_host_v2_adjustment_and_recipe()
	yield(_test_host_pathway_and_erasures(), "completed")
	_test_host_eraser_activation()
	yield(_test_host_incremental_eraser_jobs(), "completed")
	_test_host_parameter_coalescing()
	yield(_test_host_async_cancellation(), "completed")
	_test_host_selection_workflow()
	yield(_test_host_responsive_action_buttons(), "completed")
	_test_host_visual_signature()
	_finish()

func _test_manifest_and_host():
	var manifest_file = File.new()
	var manifest_error = manifest_file.open("res://.staged/contour_shadows.ddmod", File.READ)
	_expect(manifest_error == OK, "mod manifest is present")
	if manifest_error == OK:
		var parsed = JSON.parse(manifest_file.get_as_text())
		_expect(parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY, "mod manifest is valid JSON")
	manifest_file.close()
	var host_script = load("res://.staged/contour_shadows.gd")
	_expect(host_script != null, "host GDScript loads and compiles")

func _test_shadow_mask_erasures():
	var source = _image(11, 7)
	for y in range(7):
		for x in range(11):
			_set_pixel(source, x, y, Color(0.2, 0.4, 0.8, 0.6))
	var erase_path = {
		"points": [[2.5, 3.5], [8.5, 3.5]],
		"radius": 1.2
	}
	var source_alpha_before = _read_pixel(source, 5, 3).a
	var erased = shadow_mask.apply(source, [erase_path], Transform2D())
	_expect(erased != null and erased != source and erased.get_width() == source.get_width() and erased.get_height() == source.get_height(), "eraser returns a separate same-size image")
	if erased != null and not erased.is_empty():
		_expect(_read_pixel(erased, 5, 3).a == 0.0, "a multi-point stroke erases pixels along its line segment")
		_expect(_read_pixel(erased, 2, 2).a == 0.0 and _read_pixel(erased, 8, 4).a == 0.0, "stroke ends have round brush caps")
		_expect(abs(_read_pixel(erased, 5, 1).a - 0.6) <= TOLERANCE, "pixels outside the brush keep their alpha")
		var erased_rgb = _read_pixel(erased, 5, 3)
		_expect(abs(erased_rgb.r - 0.2) <= TOLERANCE and abs(erased_rgb.g - 0.4) <= TOLERANCE and abs(erased_rgb.b - 0.8) <= TOLERANCE, "eraser changes alpha only")
	_expect(abs(_read_pixel(source, 5, 3).a - source_alpha_before) <= TOLERANCE and abs(source_alpha_before - 0.6) <= TOLERANCE, "eraser leaves the source image unchanged")

	var transformed = _image(8, 4)
	transformed.lock()
	transformed.fill(Color(1, 1, 1, 1))
	transformed.unlock()
	var pixel_to_local = Transform2D(Vector2(2, 0), Vector2(0, 1), Vector2(10, 20))
	var translated_stroke = {"points": [[15, 21.5]], "radius": 0.6}
	var transformed_result = shadow_mask.apply(transformed, [translated_stroke], pixel_to_local)
	_expect(_read_pixel(transformed_result, 2, 1).a == 0.0 and _read_pixel(transformed_result, 5, 1).a > 0.9, "pixel-to-local scale and translation map strokes back to the intended image pixel")

	var ellipse_source = _image(10, 8)
	ellipse_source.lock()
	ellipse_source.fill(Color(1, 1, 1, 1))
	ellipse_source.unlock()
	var ellipse_stroke = {
		"points": [[4.5, 3.5]],
		"radius": 1.0,
		"radius_basis": [[2.0, 0.0], [0.0, 0.5]]
	}
	var ellipse_result = shadow_mask.apply(ellipse_source, [ellipse_stroke], Transform2D())
	_expect(_read_pixel(ellipse_result, 6, 3).a == 0.0 and _read_pixel(ellipse_result, 4, 4).a > 0.9, "radius basis preserves a nonuniform brush footprint")

	var hit_source = _image(12, 8)
	_set_pixel(hit_source, 6, 3, Color(0.2, 0.4, 0.8, 0.75))
	var source_data_before = hit_source.get_data()
	var crossing_stroke = {"points": [[2.5, 3.5], [10.5, 3.5]], "radius": 0.4}
	_expect(shadow_mask.intersects(hit_source, crossing_stroke, Transform2D()), "capsule hit-test detects an opaque mark between two brush endpoints outside the shadow")
	_expect(not shadow_mask.intersects(hit_source, {"points": [[2.5, 6.5]], "radius": 0.4}, Transform2D()), "single-point brush hit-test ignores transparent nearby pixels")
	_expect(hit_source.get_data() == source_data_before, "capsule hit-test leaves its source image unchanged")
	var translated_hit = _image(8, 4)
	_set_pixel(translated_hit, 2, 1, Color(1, 1, 1, 1))
	var hit_transform = Transform2D(Vector2(2, 0), Vector2(0, 1), Vector2(10, 20))
	_expect(shadow_mask.intersects(translated_hit, {"points": [[15, 21.5]], "radius": 0.45}, hit_transform), "capsule hit-test maps source-local coordinates through pixel scale and offset")
	var basis_hit = _image(10, 8)
	_set_pixel(basis_hit, 6, 3, Color(1, 1, 1, 1))
	var ellipse_hit = {
		"points": [[5.5, 3.5]], "radius": 1.0,
		"radius_basis": [[2.0, 0.0], [0.0, 0.5]]
	}
	_expect(shadow_mask.intersects(basis_hit, ellipse_hit, Transform2D()), "capsule hit-test maps horizontal nonuniform radius basis")
	var vertical_only = _image(10, 8)
	_set_pixel(vertical_only, 5, 4, Color(1, 1, 1, 1))
	_expect(not shadow_mask.intersects(vertical_only, ellipse_hit, Transform2D()), "capsule hit-test respects the narrower vertical radius basis")

func _test_pathway_alpha_capture():
	var owner = Node2D.new()
	owner.name = "PathCaptureTestOwner"
	owner.position = Vector2(31, -14)
	owner.modulate = Color(1.0, 1.0, 1.0, 0.25)
	owner.visible = false
	get_root().add_child(owner)
	var line = MockPathway.new()
	line.name = "PathwayAlphaFixture"
	line.width = 4.0
	line.points = PoolVector2Array([Vector2(6, 2), Vector2(6, 12)])
	line.EditPoints = line.points
	line.default_color = Color(0.8, 0.4, 0.2, 0.6)
	var alpha_gradient = Gradient.new()
	alpha_gradient.set_color(0, Color(0.8, 0.4, 0.2, 0.0))
	alpha_gradient.set_color(1, Color(0.8, 0.4, 0.2, 0.6))
	line.gradient = alpha_gradient
	line.modulate = Color(1.0, 1.0, 1.0, 0.5)
	line.antialiased = false
	owner.add_child(line)
	_expect(path_source.is_pathway(line) and not path_source.is_pathway(Line2D.new()), "Pathway recognition requires the Line2D API shape")
	var capture = yield(path_source.capture(line, owner, 64), "completed")
	_expect(capture.get("ok", false), "native Pathway capture returns an image")
	if capture.get("ok", false):
		_expect(capture.image.get_format() == Image.FORMAT_RGBA8 and capture.kind == "path", "path capture reports RGBA8 output and path kind")
		_expect(capture.rect.has_point(Vector2(7, 5)) and _near_vec(capture.pixel_to_local.xform(Vector2(0.5, 0.5)), capture.rect.position + Vector2(capture.pixel_scale * 0.5, capture.pixel_scale * 0.5)), "path capture reports a pixel-boundary-to-local transform")
		var solid_end_alpha = _sample_capture_alpha(capture, Vector2(6, 11))
		var outside_alpha = _sample_capture_alpha(capture, Vector2(12, 6))
		_expect(solid_end_alpha > 0.48 and solid_end_alpha < 0.72, "captured path pixels preserve intrinsic alpha without baking hidden ancestor/source modulation (got %.3f)" % solid_end_alpha)
		_expect(outside_alpha < 0.02, "transparent capture background stays transparent")
		var transparent_upper_alpha = _sample_capture_alpha(capture, Vector2(6, 2.5))
		var opaque_lower_alpha = _sample_capture_alpha(capture, Vector2(6, 11.5))
		_expect(transparent_upper_alpha < 0.10 and opaque_lower_alpha > 0.48, "vertical alpha gradient stays top-transparent/bottom-solid after readback and local-coordinate mapping")
	var invalid_capture = yield(path_source.capture_line(Line2D.new(), owner, 64), "completed")
	_expect(not invalid_capture.get("ok", true) and str(invalid_capture.get("error", "")).find("two rendered points") >= 0, "invalid path capture reports its missing-point error")
	var repeated_captures = 0
	for _capture_index in range(3):
		var repeated = yield(path_source.capture_line(line, owner, 64), "completed")
		if repeated.get("ok", false) and repeated.get("image", null) is Image:
			repeated_captures += 1
	_expect(repeated_captures == 3, "repeated Pathway captures finish cleanly after temporary Viewport cleanup")
	# capture_line waits for its temporary Viewport teardown before returning. Freeing
	# the fixture owner here stresses that boundary without a deferred extra frame.
	owner.free()

func _sample_capture_alpha(capture : Dictionary, local_position : Vector2) -> float:
	var image : Image = capture.image
	var pixel_position = capture.pixel_to_local.affine_inverse().xform(local_position)
	var x = int(floor(pixel_position.x))
	var y = int(floor(pixel_position.y))
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return 0.0
	return _read_pixel(image, x, y).a

func _test_empty_and_hole():
	var empty = _image(3, 3)
	var empty_result = _render(empty, Vector2.ZERO, 0.0, "sweep", 0.01, 32)
	_expect_ok(empty_result, "fully transparent source")
	if _result_image(empty_result) != null:
		_expect(_alpha_sum(empty_result.image) == 0.0, "transparent source remains transparent")
		_expect(empty_result.source_size == Vector2(3, 3), "fully transparent output preserves the original source size")

	var filtered = _image(5, 5)
	_set_pixel(filtered, 2, 3, Color(1, 1, 1, 0.005))
	var filtered_result = _render(filtered, Vector2.ZERO, 0.0, "offset", 0.02, 32)
	_expect_ok(filtered_result, "source entirely below the alpha cutoff")
	if _result_image(filtered_result) != null:
		_expect(filtered_result.source_size == Vector2(5, 5), "cutoff-filtered output preserves the original source size")
		_expect(filtered_result.offset == Vector2(2, 3), "cutoff-filtered output retains the cropped source origin")

	var ring = _image(5, 5)
	for y in range(5):
		for x in range(5):
			if x == 0 or y == 0 or x == 4 or y == 4:
				_set_pixel(ring, x, y, Color(1, 1, 1, 1))
	var ring_result = _render(ring, Vector2.ZERO, 0.0, "offset", 0.01, 32)
	_expect_ok(ring_result, "alpha silhouette with a hole")
	if _result_image(ring_result) != null:
		_expect(_sample_alpha(ring_result, Vector2(0, 0)) > 0.9, "opaque contour survives rendering")
		_expect(_sample_alpha(ring_result, Vector2(2, 2)) < 0.02, "transparent hole stays open")

func _test_alpha_gradient():
	var source = _image(4, 1)
	_set_pixel(source, 0, 0, Color(1, 1, 1, 0.0))
	_set_pixel(source, 1, 0, Color(1, 1, 1, 0.25))
	_set_pixel(source, 2, 0, Color(1, 1, 1, 0.5))
	_set_pixel(source, 3, 0, Color(1, 1, 1, 1.0))
	var result = _render(source, Vector2.ZERO, 0.0, "offset", 0.01, 32)
	_expect_ok(result, "gradient alpha source")
	if _result_image(result) != null:
		_expect(abs(_sample_alpha(result, Vector2(1, 0)) - 0.25) <= TOLERANCE, "low gradient alpha is preserved")
		_expect(abs(_sample_alpha(result, Vector2(2, 0)) - 0.5) <= TOLERANCE, "mid gradient alpha is preserved")
		_expect(abs(_sample_alpha(result, Vector2(3, 0)) - 1.0) <= TOLERANCE, "full alpha is preserved")
		_expect(abs(_read_pixel(source, 3, 0).a - 1.0) <= TOLERANCE, "render does not mutate its source Image")

func _test_zero_and_negative_displacement():
	var source = _image(4, 3)
	_set_pixel(source, 2, 1, Color(1, 1, 1, 1))
	var zero_result = _render(source, Vector2.ZERO, 0.0, "sweep", 0.01, 32)
	_expect_ok(zero_result, "zero displacement")
	if _result_image(zero_result) != null:
		_expect(_sample_alpha(zero_result, Vector2(2, 1)) > 0.9, "zero displacement preserves the source silhouette")

	var negative = Vector2(-3, 2)
	var negative_result = _render(source, negative, 0.0, "offset", 0.01, 32)
	_expect_ok(negative_result, "negative displacement")
	if _result_image(negative_result) != null:
		_expect(_sample_alpha(negative_result, Vector2(2, 1) + negative) > 0.9, "negative offset lands at the requested location")
		_expect(negative_result.offset.x <= -1.0, "negative offset expands output to the left")

func _test_blur_expansion():
	var source = _image(15, 15)
	source.lock()
	source.fill(Color(1, 1, 1, 1))
	source.unlock()
	var displacement = Vector2(-4, 3)
	var result = _render(source, displacement, 2.0, "offset", 0.01, 64)
	_expect_ok(result, "blurred negative offset")
	if _result_image(result) != null:
		_expect(_sample_alpha(result, Vector2(7, 7) + displacement) > 0.9, "expanded blurred shadow retains its opaque interior")
		var softened_edge = _sample_alpha(result, Vector2(0, 7) + displacement)
		_expect(softened_edge > 0.0 and softened_edge < 0.9, "blur softens the silhouette edge")
		_expect(result.offset.x < -4.0, "blur padding extends beyond the negative shadow edge")
		_expect(result.image.get_width() >= source.get_width() + 12, "blur padding increases output width")

func _test_sweep_uses_maximum_alpha():
	var source = _image(1, 1)
	_set_pixel(source, 0, 0, Color(1, 1, 1, 0.4))
	var displacement = Vector2(6, 0)
	var result = _render(source, displacement, 0.0, "sweep", 0.01, 32)
	_expect_ok(result, "continuous sweep")
	if _result_image(result) != null:
		for x in range(7):
			var alpha = _sample_alpha(result, Vector2(x, 0))
			_expect(abs(alpha - 0.4) <= TOLERANCE, "sweep uses maximum alpha without dark overlap at x=%d (got %.3f)" % [x, alpha])

func _test_sweep_step_limit():
	_expect(renderer.has_method("get_work_limit") and renderer.get_work_limit() > 0, "renderer exposes a positive bounded work limit")
	var source = _image(1, 1)
	_set_pixel(source, 0, 0, Color(1, 1, 1, 1))
	var result = _render(source, Vector2(1000000, 0), 0.0, "sweep", 0.01, 1024)
	_expect_ok(result, "extreme sweep displacement")
	if _result_image(result) != null:
		_expect(result.image.get_width() <= 1024 and result.image.get_height() <= 1024, "sweep step cap also respects the output dimension cap")

func _test_large_image_limit():
	var source = _image(2048, 1024)
	source.lock()
	source.fill(Color(1, 1, 1, 1))
	source.unlock()
	var result = _render(source, Vector2(256, -128), 32.0, "sweep", 0.01, 64)
	_expect_ok(result, "large source with a small cache limit")
	if _result_image(result) != null:
		_expect(result.image.get_width() <= 64 and result.image.get_height() <= 64, "rendered cache stays within max_size")
		_expect(result.pixel_scale >= 1.0, "large source reports a usable source-pixel scale")
	var invalid_limit = _render(_image(1, 1), Vector2.ZERO, 0.0, "offset", 0.01, 0)
	_expect(not invalid_limit.get("ok", false), "zero max_size is rejected")

func _test_downsample_preserves_alpha_details():
	var sparse = _image(8, 8)
	_set_pixel(sparse, 1, 1, Color(1, 1, 1, 0.6))
	_set_pixel(sparse, 7, 7, Color(1, 1, 1, 1.0))
	var sparse_result = _render(sparse, Vector2.ZERO, 0.0, "offset", 0.01, 4)
	_expect_ok(sparse_result, "downsampled sparse alpha source")
	if _result_image(sparse_result) != null:
		_expect(sparse_result.pixel_scale > 1.0, "cache limit triggers area downsampling")
		_expect(sparse_result.offset == Vector2(1, 1), "cropped raster offset restores its original Sprite-local origin")
		_expect(abs(_sample_alpha(sparse_result, Vector2(1, 1)) - 0.6) <= TOLERANCE, "area downsampling retains a small translucent mark at its source coordinate")

	var ring = _image(8, 8)
	ring.lock()
	ring.fill(Color(1, 1, 1, 1))
	ring.unlock()
	for y in range(3, 7):
		for x in range(3, 7):
			_set_pixel(ring, x, y, Color(1, 1, 1, 0))
	var ring_result = _render(ring, Vector2.ZERO, 0.0, "offset", 0.01, 4)
	_expect_ok(ring_result, "downsampled silhouette with a hole")
	if _result_image(ring_result) != null:
		_expect(_sample_alpha(ring_result, Vector2(4, 4)) < 0.02, "area downsampling keeps a sufficiently large transparent hole open")

func _test_transform_vectors():
	var right = geometry.angle_vector(0.0, 10.0)
	var down = geometry.angle_vector(90.0, 10.0)
	_expect(_near_vec(right, Vector2(10, 0)), "0 degrees points right")
	_expect(_near_vec(down, Vector2(0, 10)), "90 degrees points down")

	var transform = Transform2D()
	transform.x = Vector2(0, -2)
	transform.y = Vector2(-3, 0)
	transform.origin = Vector2(80, -30)
	var local_vector = Vector2(4, -5)
	var world_vector = transform.xform(local_vector) - transform.origin
	var recovered = geometry.world_to_local_vector(transform, world_vector)
	_expect(_near_vec(recovered, local_vector), "inverse basis handles rotation, nonuniform scale, and mirror without translation")

func _test_sprite_frame_region_flip_and_rect():
	var pixels = _image(4, 2)
	for y in range(2):
		if y == 0:
			_set_pixel(pixels, 0, y, Color(1, 0, 0, 1))
			_set_pixel(pixels, 1, y, Color(0, 1, 0, 1))
			_set_pixel(pixels, 2, y, Color(0, 0, 1, 1))
			_set_pixel(pixels, 3, y, Color(1, 1, 0, 1))
		else:
			_set_pixel(pixels, 0, y, Color(0, 1, 1, 1))
			_set_pixel(pixels, 1, y, Color(1, 0, 1, 1))
			_set_pixel(pixels, 2, y, Color(1, 1, 1, 1))
			_set_pixel(pixels, 3, y, Color(0, 0, 0, 1))
	var texture = ImageTexture.new()
	texture.create_from_image(pixels)

	var frame_sprite = Sprite.new()
	frame_sprite.texture = texture
	frame_sprite.hframes = 2
	frame_sprite.vframes = 1
	frame_sprite.frame = 1
	frame_sprite.centered = false
	frame_sprite.offset = Vector2(3, -2)
	var frame_result = geometry.extract_sprite_image(frame_sprite)
	_expect(_result_ok(frame_result), "frame extraction succeeds")
	if _result_ok(frame_result):
		_expect(frame_result.image.get_width() == 2 and frame_result.image.get_height() == 2, "selected Sprite frame is cropped")
		_expect(_near_color(_read_pixel(frame_result.image, 0, 0), Color(0, 0, 1, 1)), "frame index selects the right Sprite frame")
		_expect(_near_vec(frame_result.rect.position, Vector2(3, -2)), "uncentered Sprite rect includes its offset")

	var region_sprite = Sprite.new()
	region_sprite.texture = texture
	region_sprite.region_enabled = true
	region_sprite.region_rect = Rect2(0, 0, 2, 2)
	region_sprite.flip_h = true
	region_sprite.flip_v = true
	region_sprite.centered = false
	region_sprite.offset = Vector2(7, 4)
	var region_result = geometry.extract_sprite_image(region_sprite)
	_expect(_result_ok(region_result), "region extraction succeeds")
	if _result_ok(region_result):
		_expect(region_result.image.get_width() == 2 and region_result.image.get_height() == 2, "Sprite region is cropped")
		_expect(_near_color(_read_pixel(region_result.image, 0, 0), Color(1, 0, 1, 1)), "horizontal and vertical flips are applied to extracted pixels")
		_expect(_near_vec(region_result.rect.position, Vector2(7, 4)), "region draw rect includes Sprite offset")

	var atlas = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(2, 0, 2, 2)
	var atlas_sprite = Sprite.new()
	atlas_sprite.texture = atlas
	atlas_sprite.centered = true
	atlas_sprite.offset = Vector2(1, 2)
	var atlas_result = geometry.extract_sprite_image(atlas_sprite)
	_expect(_result_ok(atlas_result), "AtlasTexture extraction succeeds")
	if _result_ok(atlas_result):
		_expect(atlas_result.image.get_width() == 2 and atlas_result.image.get_height() == 2, "AtlasTexture region is unpacked")
		_expect(_near_color(_read_pixel(atlas_result.image, 0, 0), Color(0, 0, 1, 1)), "AtlasTexture samples its atlas region")
		_expect(_near_vec(atlas_result.rect.position, Vector2(0, 1)), "centered AtlasTexture rect includes Sprite offset")
	frame_sprite.free()
	region_sprite.free()
	atlas_sprite.free()

func _test_host_selection_and_lifecycle():
	var host_script = load("res://.staged/contour_shadows.gd")
	if host_script == null:
		_expect(false, "host regression script is available")
		return

	var empty_fixture = _mock_host_fixture(host_script)
	empty_fixture["global"].Editor.ActiveToolName = "contour_shadows"
	var empty_result = empty_fixture.host.GenerateSelected()
	_expect(not empty_result.get("ok", true), "GenerateSelected reports a notice when nothing is selected")
	_expect(str(empty_result.get("notice", "")).find("请先用选择工具") >= 0 and empty_fixture.host._last_error == "", "empty selection remains an actionable notice, not a script error")
	_expect(empty_fixture.host._last_selection_type_code == TYPE_ARRAY and empty_fixture.host._last_selection_type == "Array", "selection inspection recognizes the native Array return type")

	var selected_fixture = _mock_host_fixture(host_script)
	var selected_prop = _mock_prop(selected_fixture.level, 0)
	selected_fixture.select_tool._selected = [selected_prop]
	_expect(not _has_property(selected_fixture.select_tool, "Selected") and selected_fixture.select_tool.has_method("get_Selected") and typeof(selected_fixture.select_tool.call("get_Selected")) == TYPE_ARRAY, "SelectTool.Selected mock matches the native getter and Array contract")
	_expect(not _has_property(selected_prop, "Sprite") and selected_prop.has_method("get_Sprite") and selected_prop.get("Sprite") == selected_prop._sprite_node, "Prop fixture models a C# Sprite getter absent from get_property_list")
	var selected_result = selected_fixture.host.GenerateSelected()
	_expect(selected_result.get("ok", false) and int(selected_result.get("queued", 0)) == 1, "GenerateSelected queues a selected Prop with node_id zero")
	_expect(selected_fixture.host._stable_node_id(selected_prop) == 0, "node_id zero is a valid stable object id")
	var selected_diagnostics = selected_fixture.host.GetDiagnostics()
	_expect(selected_diagnostics.get("selected_type", "") == "Array" and int(selected_diagnostics.get("selected_count", -1)) == 1 and int(selected_diagnostics.get("selected_prop_count", -1)) == 1 and selected_diagnostics.get("selected_source", "") == "live", "diagnostics report the live selection shape and Prop count")
	selected_fixture.host._renderer = renderer
	var renderer_diagnostics = selected_fixture.host.GetDiagnostics()
	_expect(int(renderer_diagnostics.get("renderer_work_limit", -1)) == renderer.get_work_limit(), "host diagnostics expose the actual renderer work limit")
	selected_fixture.host.on_color_change("contour_shadows_color", Color(0.45, 0.25, 0.15, 1.0))
	_expect(_near_color(selected_fixture.host.shadow_color, Color(0.45, 0.25, 0.15, 1.0)), "ColorPalette callback accepts an id and Color value")
	selected_fixture.host.on_color_change(Color(0.2, 0.4, 0.65, 1.0))
	_expect(_near_color(selected_fixture.host.shadow_color, Color(0.2, 0.4, 0.65, 1.0)), "ColorPalette callback also accepts a direct Color value")

	var snapshot_fixture = _mock_host_fixture(host_script)
	var snapshot_prop = _mock_prop(snapshot_fixture.level, 25)
	snapshot_fixture.select_tool._selected = [snapshot_prop]
	snapshot_fixture["global"].Editor.ActiveToolName = "SelectTool"
	snapshot_fixture.host._capture_selection_snapshot()
	snapshot_fixture["global"].Editor.ActiveToolName = "contour_shadows"
	snapshot_fixture.select_tool._selected = []
	var snapshot_result = snapshot_fixture.host.GenerateSelected()
	_expect(snapshot_result.get("ok", false) and int(snapshot_result.get("queued", 0)) == 1 and snapshot_fixture.host._last_selection_source == "snapshot", "GenerateSelected uses the captured selection after switching away from SelectTool")
	var snapshot_diagnostics = snapshot_fixture.host.GetDiagnostics()
	_expect(snapshot_diagnostics.get("selected_source", "") == "snapshot" and int(snapshot_diagnostics.get("selected_prop_count", 0)) == 1, "diagnostics identify the captured selection fallback")

	var floor_snapshot_fixture = _mock_host_fixture(host_script)
	var old_floor_prop = _mock_prop(floor_snapshot_fixture.level, 26)
	floor_snapshot_fixture.select_tool._selected = [old_floor_prop]
	floor_snapshot_fixture.host._capture_selection_snapshot()
	var new_floor = MockLevel.new()
	new_floor.ID = 1
	mock_levels.append(new_floor)
	floor_snapshot_fixture["global"].World.levels.append(new_floor)
	floor_snapshot_fixture["global"].World.current_level = new_floor
	floor_snapshot_fixture["global"].Editor.ActiveToolName = "contour_shadows"
	floor_snapshot_fixture.select_tool._selected = []
	var stale_floor_result = floor_snapshot_fixture.host.GenerateSelected()
	_expect(not stale_floor_result.get("ok", true) and floor_snapshot_fixture.host._selection_snapshot_node_ids.empty(), "selection snapshot is discarded after changing floors")

	var excluded_fixture = _mock_host_fixture(host_script)
	var excluded_prop = _mock_prop(excluded_fixture.level, 22)
	excluded_fixture.host._excluded_node_ids["22"] = true
	excluded_fixture.select_tool._selected = [excluded_prop]
	var excluded_result = excluded_fixture.host.GenerateSelected()
	_expect(excluded_result.get("ok", false) and int(excluded_result.get("queued", -1)) == 0 and int(excluded_result.get("skipped", 0)) == 1, "GenerateSelected skips a selected Prop already excluded")

	var other_level_fixture = _mock_host_fixture(host_script)
	var other_level = MockLevel.new()
	other_level.ID = 1
	mock_levels.append(other_level)
	var other_level_prop = _mock_prop(other_level, 23)
	other_level_fixture.select_tool._selected = [other_level_prop]
	var other_level_result = other_level_fixture.host.GenerateSelected()
	_expect(not other_level_result.get("ok", true), "GenerateSelected ignores a Prop outside the current level")

	var internal_fixture = _mock_host_fixture(host_script)
	var internal_node = Node2D.new()
	internal_node.set_meta("node_id", 24)
	internal_node.set_meta("contour_shadows_owner", "contour_shadows")
	internal_node.add_child(Sprite.new())
	internal_fixture.level.Objects.add_child(internal_node)
	internal_fixture.select_tool._selected = [internal_node]
	var internal_result = internal_fixture.host.GenerateSelected()
	_expect(not internal_result.get("ok", true), "GenerateSelected ignores an internal shadow node")

	var lifecycle = _mock_host_fixture(host_script)
	var lifecycle_prop = _mock_prop(lifecycle.level, 0)
	var source_sprite = lifecycle_prop.get("Sprite")
	var rendered_image = _image(3, 3)
	var render_transform = Transform2D()
	var render_settings = lifecycle.host.get_effective_settings(0)
	lifecycle.host._update_shadow_node(lifecycle_prop, source_sprite, rendered_image, render_transform, 0, render_settings, "prop")
	var first_wrapper = lifecycle.host._find_shadow(lifecycle_prop)
	lifecycle.host._update_shadow_node(lifecycle_prop, source_sprite, rendered_image, render_transform, 0, render_settings, "prop")
	var second_wrapper = lifecycle.host._find_shadow(lifecycle_prop)
	_expect(first_wrapper != null and first_wrapper == second_wrapper, "refresh reuses the existing plugin wrapper")
	var owned_wrappers = 0
	for child in lifecycle_prop.get_children():
		if child.has_meta("contour_shadows_owner") and str(child.get_meta("contour_shadows_owner")) == "contour_shadows":
			owned_wrappers += 1
	_expect(owned_wrappers == 1 and second_wrapper.get_child_count() == 1, "refresh does not accumulate plugin shadow nodes")

	var unrelated = Node2D.new()
	unrelated.name = "UnrelatedChild"
	lifecycle_prop.add_child(unrelated)
	lifecycle.select_tool._selected = [lifecycle_prop]
	var excluded_op = lifecycle.host.ExcludeSelected()
	_expect(excluded_op.get("ok", false) and int(excluded_op.get("excluded", 0)) == 1, "exclude-selected records node_id zero")
	_expect(lifecycle.host._find_shadow(lifecycle_prop) == null and unrelated.get_parent() == lifecycle_prop, "excluding removes only the owned wrapper")
	var restored_op = lifecycle.host.RestoreSelected()
	_expect(restored_op.get("ok", false) and int(restored_op.get("restored", 0)) == 1 and int(restored_op.get("queued", 0)) == 1, "restore-selected clears exclusion and queues regeneration")

	var recipe_host = lifecycle.host
	recipe_host._enabled_node_ids["0"] = true
	recipe_host._excluded_node_ids["31"] = true
	var recipe_saved = recipe_host._save_map_recipe()
	var reopened_host = host_script.new()
	mock_hosts.append(reopened_host)
	reopened_host.Global = lifecycle["global"]
	reopened_host._refresh_map_context()
	var recipe_loaded = reopened_host._enabled_node_ids.has("0") and reopened_host._excluded_node_ids.has("31")
	_expect(recipe_saved and recipe_loaded, "map recipe saves and loads through ModMapData")
	_expect(reopened_host._generation_queue.size() == 1 and int(reopened_host._generation_queue[0].node_id) == 0, "reopened recipe queues the enabled Prop by node_id zero")

	lifecycle.host._update_shadow_node(lifecycle_prop, source_sprite, rendered_image, render_transform, 0, render_settings, "prop")
	var cleared = lifecycle.host.ClearShadows()
	var cleared_again = lifecycle.host.ClearShadows()
	_expect(cleared.get("ok", false) and int(cleared.get("removed", 0)) == 1, "clear removes the generated shadow on the current level")
	_expect(cleared_again.get("ok", false) and int(cleared_again.get("removed", -1)) == 0, "repeated clear is idempotent")
	_expect(unrelated.get_parent() == lifecycle_prop, "clear leaves unrelated Prop children intact")

func _test_host_v2_adjustment_and_recipe():
	var host_script = load("res://.staged/contour_shadows.gd")
	if host_script == null:
		_expect(false, "v2 adjustment host script is available")
		return

	var fixture = _mock_host_fixture(host_script)
	var first = _mock_prop(fixture.level, 701)
	var second = _mock_prop(fixture.level, 702)
	_set_sprite_image(first.get("Sprite"), 8, 6, Color(1, 1, 1, 0.8))
	_set_sprite_image(second.get("Sprite"), 8, 6, Color(1, 1, 1, 0.8))
	fixture.host._renderer = renderer
	fixture.host._geometry = geometry
	fixture.host._shadow_mask = shadow_mask
	var toolset = MockToolset.new()
	fixture["global"].Editor.Toolset = toolset
	fixture.host._create_tool_panel()
	mock_ui_panels.append(toolset.panel)
	_expect(toolset.panel.buttons.has("单独调整") and toolset.panel.buttons.has("全局调整"), "separate and global adjustment controls are distinct buttons")

	fixture.select_tool._selected = [first]
	toolset.press_button("单独调整")
	_expect(fixture.host.adjustment_mode == "individual", "individual button switches to per-source adjustment mode")
	var global_before = fixture.host._parameter_settings_dictionary().duplicate(true)
	var applied = fixture.host.apply_to_selected_settings({"distance": 88.0})
	var first_override = fixture.host._overrides.get("701", {})
	var first_effective = fixture.host.get_effective_settings(701)
	var override_is_complete = first_override.size() == 6
	for setting_key in ["angle", "distance", "blur_radius", "opacity", "mode", "color"]:
		override_is_complete = override_is_complete and first_override.has(setting_key)
	_expect(applied.get("ok", false) and int(applied.get("modified", 0)) == 1, "individual adjustments apply to the selected source")
	_expect(override_is_complete, "first individual override snapshots all six effective parameters")
	_expect(abs(float(first_effective.distance) - 88.0) < TOLERANCE and abs(float(first_effective.angle) - float(global_before.angle)) < TOLERANCE and abs(float(fixture.host.distance) - float(global_before.distance)) < TOLERANCE, "individual field edit changes only the selected effective value, not global defaults")
	_expect(abs(float(fixture.host._distance_slider.value) - 88.0) < TOLERANCE, "individual controls synchronize to the selected override")
	var first_generated = fixture.host._generate_prop(first, 701)
	var first_wrapper = fixture.host._find_shadow(first)
	var first_shadow_sprite = first_wrapper.get_child(0) if first_wrapper != null and first_wrapper.get_child_count() > 0 else null
	var first_shadow_texture = first_shadow_sprite.texture if first_shadow_sprite != null else null
	_expect(first_generated.get("ok", false) and first_shadow_texture != null, "individual Prop shadow generates before a global refresh")

	fixture.host._generation_queue.clear()
	fixture.host._pending_node_ids.clear()
	fixture.host._enabled_node_ids["701"] = true
	fixture.host._enabled_node_ids["702"] = true
	toolset.press_button("全局调整")
	_expect(fixture.host.adjustment_mode == "global", "global button switches back to map-wide defaults")
	var global_result = fixture.host.apply_global_settings({"angle": 132.0, "opacity": 0.65})
	var selected_effective_after_global = fixture.host.get_effective_settings(701)
	var inherited_effective = fixture.host.get_effective_settings(702)
	_expect(global_result.get("ok", false) and int(global_result.queued) == 1 and int(global_result.refreshed_candidate_count) == 1 and int(global_result.skipped_overrides) == 1, "global refresh queues only the enabled non-override source and reports skipped overrides")
	_expect(fixture.host._generation_queue.size() == 1 and int(fixture.host._generation_queue[0].node_id) == 702, "global refresh leaves the overridden source out of the work queue")
	_expect(abs(float(selected_effective_after_global.angle) - float(global_before.angle)) < TOLERANCE and abs(float(selected_effective_after_global.opacity) - float(global_before.opacity)) < TOLERANCE and abs(float(selected_effective_after_global.distance) - 88.0) < TOLERANCE, "global changes to angle and opacity do not alter any snapshotted individual parameters")
	_expect(abs(float(inherited_effective.angle) - 132.0) < TOLERANCE and abs(float(inherited_effective.opacity) - 0.65) < TOLERANCE and abs(float(inherited_effective.distance) - float(global_before.distance)) < TOLERANCE, "non-overridden source inherits changed global fields")
	fixture.host._process_generation_queue()
	_expect(first_shadow_sprite != null and first_shadow_sprite.texture == first_shadow_texture, "global refresh preserves the independent source shadow texture")
	fixture.select_tool._selected = [second]
	fixture.host.set_adjustment_mode("individual")
	_expect(abs(float(fixture.host._distance_slider.value) - float(global_before.distance)) < TOLERANCE and abs(float(fixture.host._angle_slider.value) - 132.0) < TOLERANCE, "switching selected sources synchronizes controls to each source's effective settings")
	fixture.select_tool._selected = [first]
	var restored = fixture.host.use_global_settings_for_selected()
	var restored_effective = fixture.host.get_effective_settings(701)
	_expect(restored.get("ok", false) and int(restored.restored) == 1 and not fixture.host._overrides.has("701"), "use-global removes the selected override")
	_expect(abs(float(restored_effective.angle) - 132.0) < TOLERANCE and abs(float(restored_effective.opacity) - 0.65) < TOLERANCE and abs(float(restored_effective.distance) - float(global_before.distance)) < TOLERANCE, "restored source follows global defaults for every parameter")
	_expect(abs(float(fixture.host._angle_slider.value) - 132.0) < TOLERANCE and abs(float(fixture.host._distance_slider.value) - float(global_before.distance)) < TOLERANCE, "use-global synchronizes the controls with map defaults")

	var migration = _mock_host_fixture(host_script)
	var excluded_prop = _mock_prop(migration.level, 811)
	var enabled_pathway = _mock_pathway(migration.level, 812)
	migration.host._path_source = path_source
	migration["global"].ModMapData["contour_shadows"] = {
		"version": 1,
		"settings": {"angle": 123.0, "distance": 19.0, "follow": true, "preview": false},
		"enabled_node_ids": [812],
		"excluded_node_ids": [811],
		"future_field": {"keep": true}
	}
	migration.host._refresh_map_context()
	var migrated_recipe = migration["global"].ModMapData["contour_shadows"]
	_expect(int(migrated_recipe.get("version", 0)) == 2 and typeof(migrated_recipe.get("overrides", null)) == TYPE_DICTIONARY and migrated_recipe.get("overrides", {}).empty() and typeof(migrated_recipe.get("erasures", null)) == TYPE_DICTIONARY and migrated_recipe.get("erasures", {}).empty(), "v1 recipe migrates to v2 with empty override and erasure collections (" + JSON.print(migrated_recipe) + ")")
	_expect(migrated_recipe.get("enabled_node_ids", []) == [812] and migrated_recipe.get("excluded_node_ids", []) == [811] and migrated_recipe.get("future_field", {}).get("keep", false), "v1 migration preserves object/path IDs and unknown future fields")
	_expect(abs(float(migrated_recipe.settings.get("angle", 0.0)) - 123.0) < TOLERANCE and abs(float(migrated_recipe.settings.get("distance", 0.0)) - 19.0) < TOLERANCE and bool(migrated_recipe.settings.get("follow", false)) and not bool(migrated_recipe.settings.get("preview", true)), "v1 migration retains global projection settings")
	_expect(migration.host._generation_queue.size() == 1 and migration.host._generation_queue[0].source == enabled_pathway, "v1-enabled Pathway queues for restoration after migration")

	var roundtrip = _mock_host_fixture(host_script)
	var roundtrip_prop = _mock_prop(roundtrip.level, 821)
	var persisted_stroke = {"points": [[1.25, 2.75], [4.5, 3.5]], "radius": 3.0, "hardness": 0.33, "radius_basis": [[2.0, 0.0], [0.0, 0.5]]}
	roundtrip["global"].ModMapData["contour_shadows"] = {
		"version": 2,
		"settings": {"angle": 40.0, "distance": 14.0, "blur_radius": 4.0, "opacity": 0.7, "mode": "offset", "color": "34303a", "follow": true, "preview": true},
		"enabled_node_ids": [821], "excluded_node_ids": [],
		"overrides": {"821": {"distance": 77.0}},
		"erasures": {"821": [persisted_stroke]},
		"future_field": "roundtrip"
	}
	roundtrip.host._refresh_map_context()
	var loaded_effective = roundtrip.host.get_effective_settings(821)
	roundtrip_prop.position = Vector2(120, -45)
	roundtrip_prop.rotation = 0.6
	roundtrip.host._save_map_recipe()
	var roundtrip_recipe = roundtrip["global"].ModMapData["contour_shadows"]
	var serialized_recipe = JSON.parse(JSON.print(roundtrip_recipe))
	_expect(serialized_recipe.error == OK and int(roundtrip_recipe.get("version", 0)) == 2, "v2 recipe with overrides and erasures remains JSON serializable")
	_expect(abs(float(loaded_effective.distance) - 77.0) < TOLERANCE and roundtrip_recipe.overrides["821"].size() == 6, "partial v2 override loads as a full six-parameter snapshot")
	_expect(JSON.print(roundtrip_recipe.erasures.get("821", [])) == JSON.print([persisted_stroke]) and roundtrip_recipe.get("future_field", "") == "roundtrip", "v2 erasure points and unknown fields roundtrip unchanged after source movement (" + JSON.print(roundtrip_recipe.erasures.get("821", [])) + ")")
	_expect(roundtrip.host._generation_queue.size() == 1 and int(roundtrip.host._generation_queue[0].node_id) == 821, "v2 enabled Prop queues for restoration")

func _test_host_pathway_and_erasures():
	yield(self, "idle_frame")
	var host_script = load("res://.staged/contour_shadows.gd")
	if host_script == null:
		_expect(false, "Pathway and erasure host script is available")
		return

	var selection = _mock_host_fixture(host_script)
	selection.host._path_source = path_source
	var pathway = _mock_pathway(selection.level, 901)
	var prop = _mock_prop(selection.level, 902)
	selection.select_tool._selected = [pathway]
	var selected_path = selection.host.GenerateSelected()
	var diagnostics = selection.host.get_diagnostics()
	_expect(selected_path.get("ok", false) and int(selected_path.queued) == 1 and selection.host._generation_queue[0].source == pathway, "GenerateSelected recognizes and queues a Pathway source")
	_expect(int(diagnostics.pathways) == 1 and int(diagnostics.sources) == 2 and int(diagnostics.selected_path_count) == 1, "diagnostics distinguish Pathways from Props and report total sources")
	selection.host._generation_queue.clear()
	selection.host._pending_node_ids.clear()
	var all_sources = selection.host.GenerateCurrentLevel()
	var queued_path = false
	var queued_prop = false
	for item in selection.host._generation_queue:
		queued_path = queued_path or item.source == pathway
		queued_prop = queued_prop or item.source == prop
	_expect(all_sources.get("ok", false) and int(all_sources.queued) == 2 and queued_path and queued_prop, "current-level generation queues both Pathway and Prop sources")
	var clear_pending = selection.host.ClearShadows()
	_expect(clear_pending.get("ok", false) and selection.host._generation_queue.empty() and selection.host._pending_node_ids.empty(), "clear cancels the queued Pathway and Prop jobs")
	selection.select_tool._selected = [pathway]
	selection.host.GenerateSelected()
	var excluded_path = selection.host.ExcludeSelected()
	_expect(excluded_path.get("ok", false) and int(excluded_path.excluded) == 1 and selection.host._generation_queue.empty() and not selection.host._pending_node_ids.has("901"), "excluding a selected Pathway cancels its queued capture")

	var fixture = _mock_host_fixture(host_script)
	var eraser_prop = _mock_prop(fixture.level, 911)
	var source_sprite = eraser_prop.get("Sprite")
	_set_sprite_image(source_sprite, 12, 8, Color(1, 1, 1, 0.8))
	source_sprite.centered = false
	source_sprite.offset = Vector2(2, -3)
	var sprite_transform = Transform2D(Vector2(1.2, 0.15), Vector2(-0.2, 0.9), Vector2(3, 5))
	source_sprite.transform = sprite_transform
	fixture.host._renderer = renderer
	fixture.host._geometry = geometry
	fixture.host._shadow_mask = shadow_mask
	fixture.host.shadow_mode = "offset"
	fixture.host.distance = 0.0
	fixture.host.blur_radius = 0.0
	var generated = fixture.host._generate_prop(eraser_prop, 911)
	var extracted = geometry.extract_sprite_image(source_sprite)
	var expected_pixel_to_local = source_sprite.transform * Transform2D(Vector2(1, 0), Vector2(0, 1), extracted.rect.position)
	var cache = fixture.host._shadow_render_cache.get("911", {})
	var generated_transform = cache.get("pixel_to_local", Transform2D())
	var generated_determinant = generated_transform.x.x * generated_transform.y.y - generated_transform.x.y * generated_transform.y.x
	_expect(generated.get("ok", false) and abs(generated_determinant) > 0.5, "Prop extraction keeps a nondegenerate pixel-to-source transform")
	_expect(_near_vec(generated_transform.x, expected_pixel_to_local.x) and _near_vec(generated_transform.y, expected_pixel_to_local.y) and _near_vec(generated_transform.origin, expected_pixel_to_local.origin), "Prop pixel-to-local transform preserves Sprite basis and extracted rect origin")
	var probe_pixel = Vector2(6.5, 4.5)
	var probe_local = generated_transform.xform(probe_pixel)
	var original_source_data = source_sprite.texture.get_data().get_data()
	var erase = fixture.host.add_erase_stroke(911, [[probe_local.x, probe_local.y]], 1.1, [[1, 0], [0, 1]])
	var strokes_before_refresh = fixture.host._erasures.get("911", []).duplicate(true)
	cache = fixture.host._shadow_render_cache.get("911", {})
	var erased_image = cache.get("visible_image", null)
	var visible_before = _sample_image_alpha_at_local(erased_image, cache.get("pixel_to_local", Transform2D()), probe_local)
	_expect(erase.get("ok", false) and erase.get("recorded", false) and strokes_before_refresh.size() == 1, "local eraser records a JSON-friendly source-local stroke")
	_expect(visible_before < 0.02 and abs(_read_pixel(source_sprite.texture.get_data(), 6, 4).a - 0.8) < TOLERANCE and source_sprite.texture.get_data().get_data() == original_source_data, "eraser clears only the generated shadow alpha and never edits the source texture")
	var undone = fixture.host.undo_last_erase()
	cache = fixture.host._shadow_render_cache.get("911", {})
	var visible_after_undo = _sample_image_alpha_at_local(cache.get("visible_image", null), cache.get("pixel_to_local", Transform2D()), probe_local)
	_expect(undone.get("ok", false) and int(undone.restored) == 1 and visible_after_undo > 0.1, "undo restores the last valid local erasure")
	fixture.host.add_erase_stroke(911, [[probe_local.x, probe_local.y]], 1.1, [[1, 0], [0, 1]])
	var serialized_before_refresh = JSON.print(fixture.host._erasures.get("911", []))
	eraser_prop.position = Vector2(80, -35)
	eraser_prop.rotation = 0.55
	fixture.host.blur_radius = 2.0
	var refreshed = fixture.host._generate_prop(eraser_prop, 911)
	cache = fixture.host._shadow_render_cache.get("911", {})
	var visible_after_refresh = _sample_image_alpha_at_local(cache.get("visible_image", null), cache.get("pixel_to_local", Transform2D()), probe_local)
	_expect(refreshed.get("ok", false) and JSON.print(fixture.host._erasures.get("911", [])) == serialized_before_refresh, "refresh after parameter and object-transform changes retains the original local-coordinate stroke")
	_expect(visible_after_refresh < 0.02 and source_sprite.texture.get_data().get_data() == original_source_data, "refresh re-applies the same eraser to a newly rendered shadow without touching source pixels")
	fixture.select_tool._selected = [eraser_prop]
	var restored_erasures = fixture.host.restore_selected_erasures()
	cache = fixture.host._shadow_render_cache.get("911", {})
	var visible_after_restore = _sample_image_alpha_at_local(cache.get("visible_image", null), cache.get("pixel_to_local", Transform2D()), probe_local)
	_expect(restored_erasures.get("ok", false) and int(restored_erasures.restored) == 1 and not fixture.host._erasures.has("911") and visible_after_restore > 0.1, "restore-selected erasures removes strokes and restores the refreshed shadow pixels (result=%s, alpha=%.3f, erasures=%s)" % [JSON.print(restored_erasures), visible_after_restore, JSON.print(fixture.host._erasures)])

	var gesture_fixture = _mock_host_fixture(host_script)
	get_root().add_child(gesture_fixture.level)
	var gesture_prop = _mock_prop(gesture_fixture.level, 912)
	_set_sprite_image(gesture_prop.get("Sprite"), 21, 21, Color(1, 1, 1, 0.8))
	gesture_fixture.host._renderer = renderer
	gesture_fixture.host._geometry = geometry
	gesture_fixture.host._shadow_mask = shadow_mask
	gesture_fixture.host.shadow_mode = "offset"
	gesture_fixture.host.distance = 0.0
	gesture_fixture.host.blur_radius = 0.0
	gesture_fixture.host.eraser_radius = 1.0
	gesture_fixture.host._generate_prop(gesture_prop, 912)
	var gesture_cache = gesture_fixture.host._shadow_render_cache.get("912", {})
	var sparse_shadow = _image(21, 21)
	_set_pixel(sparse_shadow, 2, 2, Color(1, 1, 1, 0.75))
	_set_pixel(sparse_shadow, 10, 2, Color(1, 1, 1, 0.75))
	_set_pixel(sparse_shadow, 18, 2, Color(1, 1, 1, 0.75))
	gesture_cache["image"] = sparse_shadow
	gesture_cache["visible_image"] = sparse_shadow
	gesture_cache["pixel_to_local"] = Transform2D()
	gesture_fixture.host._shadow_render_cache["912"] = gesture_cache
	gesture_fixture.select_tool._selected = [gesture_prop]
	gesture_fixture.host._on_eraser_toggled(true)
	var u_start = Vector2(2.5, 2.5)
	var u_bottom_left = Vector2(2.5, 18.5)
	var u_bottom_right = Vector2(18.5, 18.5)
	var u_end = Vector2(18.5, 2.5)
	gesture_fixture.host._apply_eraser_segment(gesture_prop.to_global(u_start), gesture_prop.to_global(u_bottom_left))
	gesture_fixture.host._apply_eraser_segment(gesture_prop.to_global(u_bottom_left), gesture_prop.to_global(u_bottom_right))
	gesture_fixture.host._apply_eraser_segment(gesture_prop.to_global(u_bottom_right), gesture_prop.to_global(u_end))
	gesture_fixture.host._finish_eraser_stroke(true)
	var gesture_frames = 0
	while not gesture_fixture.host._eraser_pending_jobs.empty() and gesture_frames < 100:
		gesture_fixture.host._process_eraser_jobs()
		yield(self, "idle_frame")
		gesture_frames += 1
	gesture_cache = gesture_fixture.host._shadow_render_cache.get("912", {})
	var u_visible = gesture_cache.get("visible_image", null)
	var stored_gesture = gesture_fixture.host._erasures.get("912", [])
	var stored_points = stored_gesture[0].get("points", []) if not stored_gesture.empty() else []
	_expect(stored_points.size() == 4 and _near_vec(Vector2(float(stored_points[1][0]), float(stored_points[1][1])), u_bottom_left) and _near_vec(Vector2(float(stored_points[2][0]), float(stored_points[2][1])), u_bottom_right), "U-shaped eraser gesture retains intermediate points while crossing a transparent gap (points=%s)" % JSON.print(stored_points))
	var u_start_alpha = _read_pixel(u_visible, 2, 2).a if u_visible is Image else -1.0
	var u_middle_alpha = _read_pixel(u_visible, 10, 2).a if u_visible is Image else -1.0
	var u_end_alpha = _read_pixel(u_visible, 18, 2).a if u_visible is Image else -1.0
	_expect(u_start_alpha == 0.0 and u_end_alpha == 0.0 and abs(u_middle_alpha - 0.75) <= TOLERANCE, "U-shaped gesture erases both touched ends without drawing a shortcut across untouched middle alpha (alpha=%.3f/%.3f/%.3f; erasures=%s; pending=%s)" % [u_start_alpha, u_middle_alpha, u_end_alpha, JSON.print(stored_gesture), JSON.print(gesture_fixture.host._eraser_stroke_by_node_id)])
	gesture_fixture.host._on_eraser_toggled(false)

func _test_host_eraser_activation():
	var host_script = load("res://.staged/contour_shadows.gd")
	if host_script == null:
		_expect(false, "eraser activation host loads")
		return
	var fixture = _mock_host_fixture(host_script)
	get_root().add_child(fixture.level)
	var prop = _mock_prop(fixture.level, 921)
	_set_sprite_image(prop.get("Sprite"), 24, 24, Color(1, 1, 1, 0.8))
	fixture.host._renderer = renderer
	fixture.host._geometry = geometry
	fixture.host._shadow_mask = shadow_mask
	fixture.host.distance = 0.0
	fixture.host.blur_radius = 0.0
	var generation = fixture.host._generate_prop(prop, 921)
	_expect(generation.get("ok", false), "eraser activation fixture has generated a shadow")
	fixture.host._enabled_node_ids["921"] = true
	fixture["global"].Editor.tool_script = fixture.host
	var ready_cache = fixture.host._shadow_render_cache.get("921", {})
	_expect(fixture.host._eraser_source_ready(prop, 921), "eraser activation cache is ready (source=%s; cachetype=%s; hastransform=%s; image=%s; empty=%s; wrapper=%s; pending=%s)" % [str(fixture.host._is_source_node(prop)), str(typeof(ready_cache)), str(ready_cache.has("pixel_to_local")), str(ready_cache.get("visible_image") is Image), str(ready_cache.get("visible_image").is_empty()), str(fixture.host._find_shadow(prop)), str(fixture.host._pending_node_ids)])
	fixture.select_tool._selected = [prop]
	fixture.host.begin_selection_mode()
	var original_transform = prop.transform
	var original_data = prop.get("Sprite").texture.get_data().get_data()
	fixture.host._on_eraser_toggled(true)
	_expect(fixture["global"].Editor.ActiveToolName == "contour_shadows" and fixture["global"].Editor.on_select_tool_calls == ["SelectTool", "contour_shadows"], "eraser enable explicitly takes canvas ownership from native SelectTool (notice=%s; snapshot=%s; cache=%s)" % [fixture.host._last_notice, str(fixture.host._selection_snapshot_node_ids), str(fixture.host._shadow_render_cache.keys())])
	_expect(fixture.host.eraser_enabled and fixture.host._selection_snapshot_node_ids == [921], "eraser preserves recorded source ids while taking tool ownership")
	_expect(prop.transform == original_transform and prop.get("Sprite").texture.get_data().get_data() == original_data, "activating eraser leaves source geometry and pixels untouched")
	fixture.host._eraser_drawing = true
	fixture.host._handle_eraser_focus_lost()
	_expect(fixture.host.eraser_enabled and not fixture.host._eraser_drawing, "focus loss ends the stroke while leaving eraser mode armed")
	fixture.host._eraser_window_was_focused = true
	fixture.host._eraser_drawing = true
	fixture.host._poll_eraser_focus(false)
	_expect(not fixture.host._eraser_drawing and fixture.host.eraser_enabled, "a true-to-false window focus transition ends exactly the active stroke")
	fixture.host._eraser_drawing = true
	fixture.host._poll_eraser_focus(false)
	_expect(fixture.host._eraser_drawing, "repeated unfocused polls do not reset a newly delivered native gesture")
	fixture.host._eraser_drawing = false
	fixture.host._poll_eraser_focus(true)
	_expect(not fixture.host._eraser_drawing, "returning focus cannot resume or bridge the previous stroke")
	fixture.host._on_eraser_toggled(false)
	_expect(not fixture.host.eraser_enabled and not fixture.host._eraser_drawing, "eraser can be explicitly disabled without leaving a stroke active")
	fixture.host._on_eraser_toggled(true)
	_expect(fixture.host.eraser_enabled and fixture.host._eraser_world_id == fixture.world.get_instance_id() and fixture.host._eraser_level_id == fixture.level.ID and fixture.host._eraser_map_file == fixture["global"].Editor.CurrentMapFile, "eraser reactivation from its own tool survives native disable/enable callback ordering")
	fixture.host._on_eraser_toggled(false)
	fixture["global"].Editor.tool_script = null
	var empty_fixture = _mock_host_fixture(host_script)
	empty_fixture.host._on_eraser_toggled(true)
	_expect(not empty_fixture.host.eraser_enabled and empty_fixture["global"].Editor.on_select_tool_calls.empty(), "empty selection refuses erasing before changing the active tool")
	var missing_fixture = _mock_host_fixture(host_script)
	var missing = _mock_prop(missing_fixture.level, 922)
	missing_fixture.select_tool._selected = [missing]
	missing_fixture.host._on_eraser_toggled(true)
	_expect(not missing_fixture.host.eraser_enabled and not missing_fixture.host._last_notice.empty(), "recorded source without a ready shadow reports a useful notice instead of arming a silent eraser")

func _test_host_incremental_eraser_jobs():
	yield(self, "idle_frame")
	var fixture = _mock_host_fixture(load("res://.staged/contour_shadows.gd"))
	get_root().add_child(fixture.level)
	var prop = _mock_prop(fixture.level, 919)
	_set_sprite_image(prop.get("Sprite"), 64, 64, Color(1, 1, 1, 0.8))
	fixture.host._renderer = renderer
	fixture.host._geometry = geometry
	fixture.host._shadow_mask = shadow_mask
	fixture.host.distance = 0.0
	fixture.host.blur_radius = 0.0
	fixture.host.eraser_radius = 4.0
	fixture.host.eraser_hardness = 0.35
	fixture.host._generate_prop(prop, 919)
	fixture.host._enabled_node_ids["919"] = true
	fixture.select_tool._selected = [prop]
	fixture.host._on_eraser_toggled(true)
	var cache = fixture.host._shadow_render_cache["919"]
	var original_visible = cache.visible_image.get_data()
	var original_source = prop.get("Sprite").texture.get_data().get_data()
	var original_transform = prop.transform
	var texture_id = _shadow_sprite(prop).texture.get_instance_id()
	fixture.host._apply_eraser_segment(Vector2(-12, 0), Vector2(-3, 0))
	_expect(fixture.host._shadow_render_cache["919"].visible_image.get_data() == original_visible, "mouse segment queues incremental work without replaying or changing the image synchronously")
	fixture.host._finish_eraser_stroke(true)
	fixture.host._apply_eraser_segment(Vector2(-7, -8), Vector2(-7, 8))
	fixture.host._finish_eraser_stroke(true)
	_expect(fixture.host._erasures.get("919", []).size() == 2, "two fast gestures are recorded independently before their rendering completes")
	var expected = shadow_mask.apply(cache.image, fixture.host._erasures.get("919", []), cache.pixel_to_local)
	var frames = 0
	while not fixture.host._eraser_pending_jobs.empty() and frames < 300:
		fixture.host._process_eraser_jobs()
		yield(self, "idle_frame")
		frames += 1
	_expect(fixture.host._eraser_pending_jobs.empty(), "queued incremental gestures eventually drain")
	_expect(fixture.host._shadow_render_cache["919"].visible_image.get_data() == expected.get_data(), "per-source FIFO renders two overlapping soft gestures exactly like full recipe replay")
	_expect(_shadow_sprite(prop).texture.get_instance_id() == texture_id, "incremental erasing reuses the existing ImageTexture")
	fixture.host._apply_eraser_segment(Vector2(12, -8), Vector2(12, 8))
	fixture.host._finish_eraser_stroke(true)
	var undone = fixture.host.undo_last_erase()
	fixture.host._process_eraser_jobs()
	_expect(undone.get("restored", 0) == 1 and fixture.host._eraser_pending_jobs.empty(), "undo cancels unfinished jobs for the undone gesture")
	_expect(fixture.host._shadow_render_cache["919"].visible_image.get_data() == expected.get_data(), "cancelled incremental jobs cannot overwrite undo restoration")
	_expect(prop.transform == original_transform and prop.get("Sprite").texture.get_data().get_data() == original_source, "incremental erasing preserves source pixels and geometry")
	fixture.host._on_eraser_toggled(false)


func _shadow_sprite(source):
	var wrapper = source.get_node_or_null("__ContourShadows")
	if wrapper == null:
		return null
	for child in wrapper.get_children():
		if child is Sprite:
			return child
	return null

func _test_host_parameter_coalescing():
	var host_script = load("res://.staged/contour_shadows.gd")
	if host_script == null:
		_expect(false, "parameter coalescing host loads")
		return
	var fixture = _mock_host_fixture(host_script)
	get_root().add_child(fixture.level)
	var prop = _mock_prop(fixture.level, 923)
	_set_sprite_image(prop.get("Sprite"), 16, 16, Color(1, 1, 1, 0.8))
	var counter = CountingRenderer.new()
	counter.delegate = renderer
	fixture.host._renderer = counter
	fixture.host._geometry = geometry
	fixture.host._shadow_mask = shadow_mask
	fixture.host._generate_prop(prop, 923)
	fixture.host._enabled_node_ids["923"] = true
	fixture.host._generated_fingerprints["923"] = fixture.host._source_signature(prop)
	var original_texture = _shadow_sprite(prop).texture
	counter.calls = 0
	fixture.host._on_parameter_changed("opacity", 0.55)
	fixture.host._on_parameter_changed("color", Color(0.2, 0.3, 0.4, 1.0))
	_expect(counter.calls == 0 and fixture.host._generation_queue.empty() and _shadow_sprite(prop).texture == original_texture, "opacity and color update the existing shadow without recomputing pixels")
	_expect(abs(_shadow_sprite(prop).modulate.a - 0.55) < TOLERANCE and abs(_shadow_sprite(prop).modulate.r - 0.2) < TOLERANCE, "appearance fast path applies current color and opacity")
	_expect(fixture.host._generated_fingerprints["923"] == fixture.host._source_signature(prop), "appearance fast path does not create a follow-refresh mismatch")
	fixture.host._on_parameter_changed("angle", 12.0)
	fixture.host._on_parameter_changed("angle", 25.0)
	fixture.host._on_parameter_changed("distance", 40.0)
	fixture.host._process_parameter_refresh(0.10)
	_expect(counter.calls == 0 and fixture.host._generation_queue.empty(), "rapid shape edits wait until the debounce interval elapses")
	fixture.host._process_parameter_refresh(0.10)
	_expect(fixture.host._generation_queue.size() == 1 and counter.calls == 0, "rapid shape edits coalesce into one pending source job")
	fixture.host._process_generation_queue()
	_expect(counter.calls == 1 and fixture.host._generation_queue.empty(), "coalesced shape edits render once using the latest parameters")
	_expect(abs(fixture.host.angle_degrees - 25.0) < TOLERANCE and abs(fixture.host.distance - 40.0) < TOLERANCE, "coalescing retains the last angle and distance values")

func _test_host_async_cancellation():
	var host_script = load("res://.staged/contour_shadows.gd")
	if host_script == null:
		_expect(false, "async cancellation host script is available")
		return

	var clear_case = _mock_host_fixture(host_script)
	var clear_path = _mock_pathway(clear_case.level, 1001)
	var clear_started = _start_pending_path_generation(clear_case, clear_path)
	var clear_result = clear_case.host.ClearShadows()
	yield(_wait_render_frames(3), "completed")
	_expect(clear_started.get("ok", false) and clear_result.get("ok", false) and _find_host_shadow(clear_path) == null, "clear during asynchronous Pathway capture cannot recreate the removed shadow")
	_expect(clear_case.host._generation_queue.empty() and clear_case.host._pending_node_ids.empty() and not clear_case.host._generation_in_progress, "clear during capture releases its queue, pending id and active token")

	var exclude_case = _mock_host_fixture(host_script)
	var exclude_path = _mock_pathway(exclude_case.level, 1002)
	var exclude_started = _start_pending_path_generation(exclude_case, exclude_path)
	var exclude_result = exclude_case.host.ExcludeSelected()
	yield(_wait_render_frames(3), "completed")
	_expect(exclude_started.get("ok", false) and exclude_result.get("ok", false) and exclude_case.host._excluded_node_ids.has("1002") and _find_host_shadow(exclude_path) == null, "excluding during asynchronous Pathway capture cannot restore or regenerate the source")
	_expect(exclude_case.host._pending_node_ids.empty() and not exclude_case.host._generation_in_progress, "exclude during capture clears pending state")

	var delete_case = _mock_host_fixture(host_script)
	var delete_path = _mock_pathway(delete_case.level, 1003)
	var delete_started = _start_pending_path_generation(delete_case, delete_path)
	delete_path.free()
	yield(_wait_render_frames(3), "completed")
	_expect(delete_started.get("ok", false) and not delete_case.host._pending_node_ids.has("1003") and not delete_case.host._generation_in_progress, "deleting a Pathway during capture releases its stale pending id and job")
	_expect(delete_case.host._generation_queue.empty() and not delete_case["global"].ModMapData.get("contour_shadows", {}).get("enabled_node_ids", []).has(1003), "deleted Pathway is not added to the map recipe by a stale callback")

	var reload_case = _mock_host_fixture(host_script)
	var reload_path = _mock_pathway(reload_case.level, 1004)
	var reload_started = _start_pending_path_generation(reload_case, reload_path)
	var replacement_level = MockLevel.new()
	replacement_level.ID = 1
	get_root().add_child(replacement_level)
	mock_levels.append(replacement_level)
	var replacement_world = MockWorld.new()
	replacement_world.current_level = replacement_level
	replacement_world.levels = [replacement_level]
	reload_case["global"].World = replacement_world
	reload_case["global"].ModMapData = {"contour_shadows": {"version": 2, "settings": {}, "enabled_node_ids": [], "excluded_node_ids": [], "overrides": {}, "erasures": {}}}
	reload_case.host._refresh_map_context()
	yield(_wait_render_frames(3), "completed")
	_expect(reload_started.get("ok", false) and not reload_case.host._pending_node_ids.has("1004") and not reload_case.host._generation_in_progress, "map/world reload invalidates a Pathway capture from the previous world")
	_expect(reload_case["global"].ModMapData["contour_shadows"].get("enabled_node_ids", []).empty() and _find_host_shadow(reload_path) == null, "stale pre-reload Pathway callback cannot write its old node id or shadow into the new recipe")

	var map_case = _mock_host_fixture(host_script)
	var map_path = _mock_pathway(map_case.level, 1005)
	var map_started = _start_pending_path_generation(map_case, map_path)
	map_case["global"].Editor.CurrentMapFile = "res://replacement-map.dungeondraft_map"
	map_case["global"].ModMapData["contour_shadows"] = {"version": 2, "settings": {}, "enabled_node_ids": [], "excluded_node_ids": [], "overrides": {}, "erasures": {}}
	map_case.host._refresh_map_context()
	yield(_wait_render_frames(3), "completed")
	_expect(map_started.get("ok", false) and _find_host_shadow(map_path) == null, "map-file change invalidates a pending Pathway capture")
	_expect(map_case["global"].ModMapData["contour_shadows"].get("enabled_node_ids", []).empty() and not map_case.host._pending_node_ids.has("1005") and not map_case.host._generation_in_progress, "stale callback cannot write the previous map's Pathway id into a replacement recipe")

func _start_pending_path_generation(fixture : Dictionary, pathway):
	fixture.host._path_source = path_source
	if not fixture.level.is_inside_tree():
		get_root().add_child(fixture.level)
	fixture.select_tool._selected = [pathway]
	var result = fixture.host.GenerateSelected()
	fixture.host._process_generation_queue()
	return result

func _find_host_shadow(source):
	if not is_instance_valid(source):
		return null
	for child in source.get_children():
		if child.has_meta("contour_shadows_owner") and str(child.get_meta("contour_shadows_owner")) == "contour_shadows":
			return child
	return null

func _wait_render_frames(count : int):
	for _frame in range(count):
		yield(VisualServer, "frame_post_draw")

func _test_host_selection_workflow():
	var host_script = load("res://.staged/contour_shadows.gd")
	if host_script == null:
		_expect(false, "selection workflow host script is available")
		return

	var fixture = _mock_host_fixture(host_script)
	var toolset = MockToolset.new()
	fixture["global"].Editor.Toolset = toolset
	fixture.host._create_tool_panel()
	mock_ui_panels.append(toolset.panel)
	toolset.press_button("选择对象")
	_expect(fixture["global"].Editor.on_select_tool_calls == ["SelectTool"] and fixture["global"].Editor.ActiveToolName == "SelectTool", "selection button dispatches BeginSelectionMode to OnSelectTool(SelectTool)")

	var prop = _mock_selectable_prop(fixture.level, 41)
	var sprite = prop.get("Sprite")
	sprite.hframes = 2
	sprite.vframes = 1
	sprite.frame = 1
	sprite.region_enabled = true
	sprite.region_rect = Rect2(1, 0, 2, 2)
	sprite.flip_h = true
	sprite.flip_v = true
	sprite.centered = false
	sprite.offset = Vector2(5, -3)
	var source_transform = Transform2D()
	source_transform.x = Vector2(0, -1.5)
	source_transform.y = Vector2(-0.75, 0)
	source_transform.origin = Vector2(8, 13)
	sprite.transform = source_transform
	sprite.z_index = 4
	sprite.z_as_relative = false
	sprite.modulate = Color(0.8, 0.7, 0.6, 0.55)
	var sprite_state = {
		"texture": sprite.texture,
		"hframes": sprite.hframes,
		"vframes": sprite.vframes,
		"frame": sprite.frame,
		"region_enabled": sprite.region_enabled,
		"region_rect": sprite.region_rect,
		"flip_h": sprite.flip_h,
		"flip_v": sprite.flip_v,
		"centered": sprite.centered,
		"offset": sprite.offset,
		"transform": sprite.transform,
		"z_index": sprite.z_index,
		"z_as_relative": sprite.z_as_relative,
		"modulate": sprite.modulate
	}
	fixture["global"].ModMapData["contour_shadows"] = {
		"version": 1,
		"enabled_node_ids": [41],
		"excluded_node_ids": [],
		"settings": {"angle": 45.0}
	}
	var recipe_before = JSON.print(fixture["global"].ModMapData)
	fixture.select_tool._selected = [prop]
	fixture.host._capture_selection_snapshot()
	_expect(fixture.host._selection_snapshot_node_ids == [41], "getter-only SelectTool selection records the stable Prop id")
	fixture["global"].Editor.ActiveToolName = "EffectsIntermediate"
	fixture.host._capture_selection_snapshot()
	_expect(fixture.host._selection_snapshot_node_ids == [41], "selection snapshot survives an intermediate tool switch")
	fixture["global"].Editor.ActiveToolName = "contour_shadows"
	fixture.select_tool._selected = []
	fixture.host._capture_selection_snapshot()
	fixture.host._sync_selection_highlights()
	_expect(prop.visually_selected and prop.select_calls == [true], "plugin tool applies the Prop visual selection API after the live getter clears")
	_expect(int(fixture.host.GetDiagnostics().get("selection_highlight_count", -1)) == 1, "diagnostics count the active visual selection marks")
	_expect(prop.get_child_count() == 1 and prop.get_child(0) == sprite, "visual selection creates no temporary Sprite child that could enter map serialization")
	_expect(sprite.texture == sprite_state.texture and sprite.hframes == sprite_state.hframes and sprite.vframes == sprite_state.vframes and sprite.frame == sprite_state.frame and sprite.region_enabled == sprite_state.region_enabled and sprite.region_rect == sprite_state.region_rect and sprite.flip_h == sprite_state.flip_h and sprite.flip_v == sprite_state.flip_v and sprite.centered == sprite_state.centered and sprite.offset == sprite_state.offset and sprite.transform == sprite_state.transform and sprite.z_index == sprite_state.z_index and sprite.z_as_relative == sprite_state.z_as_relative and sprite.modulate == sprite_state.modulate, "visual selection leaves every source Sprite rendering property unchanged")
	_expect(JSON.print(fixture["global"].ModMapData) == recipe_before, "visual selection does not alter the saved map recipe")

	fixture.select_tool._selected = [prop]
	fixture["global"].Editor.ActiveToolName = "SelectTool"
	fixture.host._capture_selection_snapshot()
	fixture.host._sync_selection_highlights()
	_expect(prop.visually_selected and prop.select_calls == [true], "returning to SelectTool preserves its still-live visual selection")
	fixture.select_tool._selected = []
	fixture.host._capture_selection_snapshot()
	fixture.host._sync_selection_highlights()
	_expect(fixture.host._selection_snapshot_node_ids.empty(), "returning to SelectTool with an empty selection clears the snapshot")
	_expect(not prop.visually_selected and prop.select_calls == [true, false], "empty SelectTool selection removes the plugin visual selection")
	_expect(int(fixture.host.GetDiagnostics().get("selection_highlight_count", -1)) == 0, "diagnostics stop counting marks after SelectTool clears selection")

	fixture.select_tool._selected = [prop]
	fixture.host._capture_selection_snapshot()
	fixture["global"].Editor.ActiveToolName = "contour_shadows"
	fixture.select_tool._selected = []
	fixture.host._capture_selection_snapshot()
	fixture.host._sync_selection_highlights()
	fixture.select_tool._selected = [prop]
	toolset.press_button("清除选择记录")
	_expect(fixture.select_tool.deselect_all_ex_calls == 1, "clear-selection button dispatches DeselectAllEx")
	_expect(fixture.host._selection_snapshot_node_ids.empty() and fixture.host._selection_record_cleared and not prop.visually_selected, "clearing the record removes the snapshot and visual selection")
	var stale_selection_result = fixture.host.GenerateSelected()
	_expect(not stale_selection_result.get("ok", true) and fixture.host._generation_queue.empty(), "clear latch blocks a stale live getter from queuing selected Props")
	_expect(prop.get_child_count() == 1 and JSON.print(fixture["global"].ModMapData) == recipe_before, "selection clearing preserves the source Sprite and recipe data")

	var live_reload_fixture = _mock_host_fixture(host_script)
	var live_reload_prop = _mock_selectable_prop(live_reload_fixture.level, 44)
	live_reload_fixture.select_tool._selected = [live_reload_prop]
	live_reload_fixture.host._capture_selection_snapshot()
	live_reload_fixture["global"].Editor.ActiveToolName = "contour_shadows"
	live_reload_fixture.select_tool._selected = []
	live_reload_fixture.host._sync_selection_highlights()
	live_reload_fixture["global"].Editor.ActiveToolName = "SelectTool"
	live_reload_fixture.select_tool._selected = [live_reload_prop]
	live_reload_fixture.host.Global = null
	var live_reload_toolset = MockToolset.new()
	live_reload_fixture["global"].Editor.Toolset = live_reload_toolset
	var live_reload_host = host_script.new()
	mock_hosts.append(live_reload_host)
	live_reload_host.Global = live_reload_fixture["global"]
	live_reload_host.start()
	mock_ui_panels.append(live_reload_toolset.panel)
	_expect(live_reload_prop.visually_selected and live_reload_prop.has_meta("contour_shadows_selection_marked"), "host reload adopts a marked Prop that is still live-selected")
	live_reload_host._capture_selection_snapshot()
	live_reload_host._sync_selection_highlights()
	_expect(live_reload_prop.visually_selected, "host reload does not clear a live SelectTool visual selection")
	live_reload_fixture.select_tool._selected = []
	live_reload_host._capture_selection_snapshot()
	live_reload_host._sync_selection_highlights()
	_expect(not live_reload_prop.visually_selected and not live_reload_prop.has_meta("contour_shadows_selection_marked"), "reloaded host clears its adopted mark after the live selection becomes empty")

	var orphan_fixture = _mock_host_fixture(host_script)
	var orphan_prop = _mock_selectable_prop(orphan_fixture.level, 45)
	orphan_fixture.select_tool._selected = [orphan_prop]
	orphan_fixture.host._capture_selection_snapshot()
	orphan_fixture["global"].Editor.ActiveToolName = "contour_shadows"
	orphan_fixture.select_tool._selected = []
	orphan_fixture.host._sync_selection_highlights()
	orphan_fixture["global"].Editor.ActiveToolName = "EffectsIntermediate"
	orphan_fixture.host.Global = null
	var orphan_toolset = MockToolset.new()
	orphan_fixture["global"].Editor.Toolset = orphan_toolset
	var replacement_host = host_script.new()
	mock_hosts.append(replacement_host)
	replacement_host.Global = orphan_fixture["global"]
	replacement_host.start()
	mock_ui_panels.append(orphan_toolset.panel)
	_expect(not orphan_prop.visually_selected and not orphan_prop.has_meta("contour_shadows_selection_marked"), "host start removes an orphaned visual selection marker from the previous instance")

	var map_fixture = _mock_host_fixture(host_script)
	var map_prop = _mock_selectable_prop(map_fixture.level, 42)
	map_fixture.select_tool._selected = [map_prop]
	map_fixture.host._capture_selection_snapshot()
	map_fixture["global"].Editor.ActiveToolName = "contour_shadows"
	map_fixture.select_tool._selected = []
	map_fixture.host._sync_selection_highlights()
	map_fixture["global"].Editor.CurrentMapFile = "res://replacement-map.dungeondraft_map"
	map_fixture["global"].Editor.ActiveToolName = "EffectsIntermediate"
	map_fixture.host._capture_selection_snapshot()
	map_fixture.host._sync_selection_highlights()
	_expect(map_fixture.host._selection_snapshot_node_ids.empty() and not map_prop.visually_selected, "changing maps clears the snapshot and visual selection")

	var floor_fixture = _mock_host_fixture(host_script)
	var old_floor_prop = _mock_selectable_prop(floor_fixture.level, 43)
	floor_fixture.select_tool._selected = [old_floor_prop]
	floor_fixture.host._capture_selection_snapshot()
	floor_fixture["global"].Editor.ActiveToolName = "contour_shadows"
	floor_fixture.select_tool._selected = []
	floor_fixture.host._sync_selection_highlights()
	var new_floor = MockLevel.new()
	new_floor.ID = 1
	mock_levels.append(new_floor)
	floor_fixture["global"].World.levels.append(new_floor)
	floor_fixture["global"].World.current_level = new_floor
	floor_fixture.host._capture_selection_snapshot()
	floor_fixture.host._sync_selection_highlights()
	_expect(floor_fixture.host._selection_snapshot_node_ids.empty() and not old_floor_prop.visually_selected, "changing floors clears the snapshot and visual selection")

func _test_host_responsive_action_buttons():
	yield(self, "idle_frame")
	var host_script = load("res://.staged/contour_shadows.gd")
	var fixture = _mock_host_fixture(host_script)
	var toolset = MockToolset.new()
	fixture["global"].Editor.Toolset = toolset
	fixture.host._create_tool_panel()
	mock_ui_panels.append(toolset.panel)
	for width in [232.0, 180.0, 232.0]:
		var old_row = fixture.host._selection_action_row
		toolset.panel.Align.rect_size.x = width
		fixture.host._update_responsive_action_layout(true)
		yield(self, "idle_frame")
		yield(self, "idle_frame")
		var row = fixture.host._selection_action_row
		var first = fixture.host._selection_action_view_a
		var second = fixture.host._selection_action_view_b
		var context = " at panel width %d" % int(width)
		_expect(not is_instance_valid(old_row), "responsive layout releases the replaced row" + context)
		_expect(is_instance_valid(row) and row.visible, "responsive layout keeps its replacement visible" + context)
		_expect(is_instance_valid(first) and is_instance_valid(second), "responsive layout preserves both target action buttons after deferred deletion" + context)
		if is_instance_valid(first) and is_instance_valid(second):
			_expect(first.get_parent() == row and second.get_parent() == row, "responsive layout reparents both target action buttons" + context)
	toolset.press_button("选择对象")
	_expect(fixture["global"].Editor.ActiveToolName == "SelectTool", "selection action still dispatches after repeated panel resizing")


func _test_host_visual_signature():
	var host_script = load("res://.staged/contour_shadows.gd")
	if host_script == null:
		_expect(false, "host visual-signature script is available")
		return
	var fixture = _mock_host_fixture(host_script)
	get_root().add_child(fixture.level)
	var prop = _mock_prop(fixture.level, 32)
	var sprite = prop.get("Sprite")
	var original_signature = fixture.host._source_signature(prop)
	prop.position = Vector2(31, -17)
	prop.force_update_transform()
	_expect(fixture.host._source_signature(prop) == original_signature, "Prop translation alone does not invalidate shadow pixels")
	prop.position = Vector2.ZERO
	prop.force_update_transform()
	sprite.rotation = 0.2
	sprite.force_update_transform()
	_expect(fixture.host._source_signature(prop) != original_signature, "Sprite rotation invalidates the shadow signature")
	sprite.rotation = 0.0
	sprite.force_update_transform()
	sprite.scale = Vector2(1.25, 0.8)
	sprite.force_update_transform()
	_expect(fixture.host._source_signature(prop) != original_signature, "Sprite scale invalidates the shadow signature")
	sprite.scale = Vector2.ONE
	sprite.z_index = 1
	_expect(fixture.host._source_signature(prop) != original_signature, "Sprite z_index invalidates the shadow signature")
	sprite.z_index = 0
	sprite.z_as_relative = false
	_expect(fixture.host._source_signature(prop) != original_signature, "Sprite z_as_relative invalidates the shadow signature")
	fixture.host._path_source = path_source
	var pathway = _mock_pathway(fixture.level, 9231)
	var transition_signature = fixture.host._source_signature(pathway)
	pathway._grow = true
	_expect(fixture.host._source_signature(pathway) != transition_signature, "getter-only Pathway entrance taper invalidates the shadow signature")
	transition_signature = fixture.host._source_signature(pathway)
	pathway._shrink = true
	_expect(fixture.host._source_signature(pathway) != transition_signature, "getter-only Pathway exit taper invalidates the shadow signature")
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.2))
	pathway.gradient = gradient
	transition_signature = fixture.host._source_signature(pathway)
	gradient.set_color(0, Color(1, 1, 1, 0.7))
	_expect(fixture.host._source_signature(pathway) != transition_signature, "in-place path Gradient alpha changes invalidate the shadow signature")
	var curve = Curve.new()
	curve.add_point(Vector2(0, 0.2))
	curve.add_point(Vector2(1, 1))
	pathway.width_curve = curve
	transition_signature = fixture.host._source_signature(pathway)
	# The custom engine's Line2D connects this internal callback without exposing
	# it through the script subclass. This test changes the signature data only.
	if curve.is_connected("changed", pathway, "_curve_changed"):
		curve.disconnect("changed", pathway, "_curve_changed")
	curve.set_point_value(0, 0.5)
	_expect(fixture.host._source_signature(pathway) != transition_signature, "in-place path Curve width changes invalidate the shadow signature")

func _mock_host_fixture(host_script):
	var select_tool = MockSelectTool.new()
	var editor = MockEditor.new()
	editor.Tools = {"SelectTool": select_tool}
	var level = MockLevel.new()
	level.ID = 0
	mock_levels.append(level)
	var world = MockWorld.new()
	world.current_level = level
	world.levels = [level]
	var global = MockGlobal.new()
	global.World = world
	global.Editor = editor
	global.ModMapData = {}
	var host = host_script.new()
	mock_hosts.append(host)
	host.Global = global
	return {"host": host, "global": global, "world": world, "level": level, "select_tool": select_tool}

func _mock_prop(level, node_id):
	var prop = MockProp.new()
	prop.set_meta("node_id", int(node_id))
	var sprite = Sprite.new()
	var texture = ImageTexture.new()
	texture.create_from_image(_image(3, 3))
	sprite.texture = texture
	prop._sprite_node = sprite
	prop.add_child(sprite)
	level.Objects.add_child(prop)
	return prop

func _mock_selectable_prop(level, node_id):
	var prop = MockSelectableProp.new()
	prop.set_meta("node_id", int(node_id))
	var sprite = Sprite.new()
	var texture = ImageTexture.new()
	texture.create_from_image(_image(4, 2))
	sprite.texture = texture
	prop._sprite_node = sprite
	prop.add_child(sprite)
	level.Objects.add_child(prop)
	return prop

func _set_sprite_image(sprite : Sprite, width : int, height : int, color : Color):
	var image = _image(width, height)
	image.fill(color)
	var texture = ImageTexture.new()
	texture.create_from_image(image)
	sprite.texture = texture

func _sample_image_alpha_at_local(image, pixel_to_local : Transform2D, local_position : Vector2) -> float:
	if not (image is Image) or image.is_empty():
		return 0.0
	var pixel_position = pixel_to_local.affine_inverse().xform(local_position)
	var x = int(floor(pixel_position.x))
	var y = int(floor(pixel_position.y))
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return 0.0
	return _read_pixel(image, x, y).a

func _mock_pathway(level, node_id):
	var pathway = MockPathway.new()
	pathway.set_meta("node_id", int(node_id))
	pathway.points = PoolVector2Array([Vector2(1, 2), Vector2(7, 2)])
	pathway.EditPoints = pathway.points
	pathway.width = 2.0
	level.Pathways.add_child(pathway)
	return pathway

func _has_property(object, property_name):
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false

func _render(source, displacement, blur, mode, cutoff, max_size):
	return renderer.render(source, displacement, blur, mode, cutoff, max_size)

func _image(width, height):
	var image = Image.new()
	image.create(width, height, false, Image.FORMAT_RGBA8)
	image.lock()
	image.fill(Color(1, 1, 1, 0))
	image.unlock()
	return image

func _expect_ok(result, label):
	_expect(typeof(result) == TYPE_DICTIONARY and result.get("ok", false), "%s returns ok" % label)

func _result_ok(result):
	return typeof(result) == TYPE_DICTIONARY and result.get("ok", false) and result.has("image") and result.image != null

func _result_image(result):
	if _result_ok(result):
		return result.image
	return null

func _sample_alpha(result, source_position):
	var image = result.image
	var scale = float(result.get("pixel_scale", 1.0))
	if scale <= 0.0:
		return 0.0
	var origin = result.get("offset", Vector2.ZERO)
	var x = int(round((source_position.x - origin.x) / scale))
	var y = int(round((source_position.y - origin.y) / scale))
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return 0.0
	image.lock()
	var alpha = image.get_pixel(x, y).a
	image.unlock()
	return alpha

func _alpha_sum(image):
	image.lock()
	var sum = 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			sum += image.get_pixel(x, y).a
	image.unlock()
	return sum

func _near_vec(actual, expected):
	return abs(actual.x - expected.x) < TOLERANCE and abs(actual.y - expected.y) < TOLERANCE

func _near_color(actual, expected):
	return abs(actual.r - expected.r) < TOLERANCE and abs(actual.g - expected.g) < TOLERANCE and abs(actual.b - expected.b) < TOLERANCE and abs(actual.a - expected.a) < TOLERANCE

func _set_pixel(image, x, y, color):
	image.lock()
	image.set_pixel(x, y, color)
	image.unlock()

func _read_pixel(image, x, y):
	image.lock()
	var color = image.get_pixel(x, y)
	image.unlock()
	return color

func _expect(condition, message):
	if condition:
		report_lines.append("PASS: " + message)
		print("PASS: " + message)
	else:
		failures.append(message)
		report_lines.append("FAIL: " + message)
		printerr("FAIL: " + message)

func _finish():
	_cleanup_mocks()
	var report = File.new()
	if report.open("res://.staged/report.txt", File.WRITE) == OK:
		for line in report_lines:
			report.store_line(line)
		report.store_line("FAILURE_COUNT: %d" % failures.size())
		if failures.empty():
			report.store_line("RESULT: PASS")
		else:
			report.store_line("RESULT: FAIL (%d failures)" % failures.size())
		report.close()
	if failures.empty():
		print("RESULT: PASS")
		quit(0)
	else:
		printerr("RESULT: FAIL (%d failures)" % failures.size())
		quit(1)

func _cleanup_mocks():
	# Host instances hold the fixture Global graph; clear that edge first so
	# all mock References and their Node fixtures can be released before exit.
	for host in mock_hosts:
		if is_instance_valid(host):
			host.Global = null
	mock_hosts.clear()
	for level in mock_levels:
		if is_instance_valid(level):
			level.free()
	mock_levels.clear()
	for panel in mock_ui_panels:
		if is_instance_valid(panel):
			panel.free()
	mock_ui_panels.clear()
	renderer = null
	geometry = null
