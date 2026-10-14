extends SceneTree

class GetterOnlyPathway:
	extends Line2D
	var _edit_points = PoolVector2Array()
	var _smoothness = 1.0
	var _fade_in = false
	var _fade_out = false
	var _grow = false
	var _shrink = false

	func get_EditPoints():
		return _edit_points

	func get_Smoothness():
		return _smoothness

	func get_FadeIn():
		return _fade_in

	func get_FadeOut():
		return _fade_out

	func get_Grow():
		return _grow

	func get_Shrink():
		return _shrink

	func Save(_copy = false):
		return {
			"edit_points": str(_edit_points),
			"smoothness": _smoothness,
			"fade_in": _fade_in,
			"fade_out": _fade_out,
			"grow": _grow,
			"shrink": _shrink
		}

	func SetEditPoints(points):
		_edit_points = points

	func Smooth():
		points = _edit_points

	func set_transition_values(fade_in, fade_out, grow, shrink):
		_fade_in = bool(fade_in)
		_fade_out = bool(fade_out)
		_grow = bool(grow)
		_shrink = bool(shrink)
		UpdateGradient()

	func UpdateGradient():
		if gradient == null:
			return
		var start_alpha = 0.0 if _fade_in else 1.0
		var end_alpha = 0.0 if _fade_out else 1.0
		gradient.set_color(0, Color(1, 1, 1, start_alpha))
		gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, end_alpha))

var failures = []
var lines = []
var path_source = null

func _init():
	path_source = load("res://v3/path_test_source.gd").new()
	if path_source == null:
		_fail("staged path source script loads")
		_finish()
		return
	call_deferred("_run")

func _run():
	var owner = Node2D.new()
	owner.name = "PathSourceV3Suite"
	get_root().add_child(owner)
	var source = _fixture_pathway()
	owner.add_child(source)
	_expect(path_source.is_pathway(source), "Pathway recognition accepts getter-only C# style transition properties")
	var ordinary_line = Line2D.new()
	_expect(not path_source.is_pathway(ordinary_line), "ordinary Line2D is not mistaken for a Dungeondraft Pathway")
	ordinary_line.free()

	var base_signature = path_source.visual_signature(source)
	_expect(path_source._read_taper_widths(source).empty(), "native point-width getters stay gated off for an un-tapered mock Pathway")
	source.set_transition_values(true, false, false, false)
	var fade_in_signature = path_source.visual_signature(source)
	_expect(base_signature != fade_in_signature, "visual signature includes transition values returned by Save(false)")
	var before_capture = yield(path_source.capture(source, owner, 128), "completed")
	_expect(before_capture.get("ok", false), "transition fixture captures through the Pathway API")
	var before_alpha = _alpha_sum(before_capture.get("image", null)) if before_capture.get("ok", false) else 0.0

	source.set_transition_values(true, true, false, false)
	var fade_out_signature = path_source.visual_signature(source)
	var after_capture = yield(path_source.capture(source, owner, 128), "completed")
	var after_alpha = _alpha_sum(after_capture.get("image", null)) if after_capture.get("ok", false) else 0.0
	var default_usage_capture = yield(path_source.capture(source, owner, 128, false), "completed")
	var explicit_level_count = _alpha_level_count(after_capture.get("image", null)) if after_capture.get("ok", false) else 0
	var default_level_count = _alpha_level_count(default_usage_capture.get("image", null)) if default_usage_capture.get("ok", false) else 0
	_expect(fade_in_signature != fade_out_signature, "enter and exit transition states produce different follow signatures")
	_expect(after_capture.get("ok", false) and abs(after_alpha - before_alpha) > 0.1, "changing the exit transition changes captured alpha")
	_expect(default_usage_capture.get("ok", false), "capture succeeds when the Viewport usage is left at its engine default")
	lines.append("INFO: viewport usage alpha levels explicit_2d=%d default=%d" % [explicit_level_count, default_level_count])
	var precision_line = Line2D.new()
	precision_line.name = "AlphaPrecisionPath"
	precision_line.points = PoolVector2Array([Vector2(2, 18), Vector2(30, 18)])
	precision_line.width = 8.0
	precision_line.default_color = Color(1, 1, 1, 0.4)
	precision_line.antialiased = false
	owner.add_child(precision_line)
	var explicit_precision = yield(path_source.capture_line(precision_line, owner, 128, true), "completed")
	var default_precision = yield(path_source.capture_line(precision_line, owner, 128), "completed")
	var explicit_precision_alpha = _sample_capture_alpha(explicit_precision, Vector2(16, 18))
	var default_precision_alpha = _sample_capture_alpha(default_precision, Vector2(16, 18))
	lines.append("INFO: alpha_0_4 viewport explicit_2d=%.6f default=%.6f" % [explicit_precision_alpha, default_precision_alpha])
	_expect(default_precision.get("ok", false) and abs(default_precision_alpha - 0.4) <= 0.01, "engine-default 2D capture preserves the sampled 0.4 path alpha")
	precision_line.queue_free()

	var copied = path_source._copy_line_visual(source)
	var source_gradient_alpha = source.gradient.get_color(0).a
	_expect(copied.gradient != source.gradient and copied.width_curve != source.width_curve, "capture copy owns independent Gradient and Curve resources")
	if OS.get_environment("CONTOUR_PATH_SHADER_TEST") == "1":
		var material_probe = _fixture_pathway()
		material_probe.material = _fixture_shader_material()
		var material_copy = path_source._copy_line_visual(material_probe)
		_expect(material_copy.material != material_probe.material, "capture copy owns an independent ShaderMaterial resource")
		var same_material_signature = path_source.visual_signature(material_probe)
		material_probe.material.set_shader_param("gain", 0.4)
		_expect(is_equal_approx(float(material_copy.material.get_shader_param("gain")), 1.0), "editing a live shader uniform does not change a capture snapshot")
		var material_signature_after = path_source.visual_signature(material_probe)
		material_probe.material.set_shader_param("gain", 0.7)
		material_signature_after = path_source.visual_signature(material_probe)
		_expect(same_material_signature != material_signature_after, "visual signature detects in-place ShaderMaterial uniform edits")
		material_copy.free()
		material_probe.free()
	else:
		lines.append("SKIP: ShaderMaterial capture is GLES3-only because this engine's GLES2 offscreen shader backend emits invalid-program errors")
	var tapered_probe = _fixture_pathway()
	tapered_probe.clear_points()
	tapered_probe.add_point(Vector2(2, 8))
	tapered_probe.add_point(Vector2(18, 8))
	tapered_probe.call("set_point_width", 0, 0.25)
	tapered_probe.call("set_point_width", 1, 10.0)
	tapered_probe.width = 69.0
	tapered_probe.joint_mode = Line2D.LINE_JOINT_BEVEL
	tapered_probe.set_transition_values(false, false, true, false)
	tapered_probe.set_meta("path_suite_taper_widths_initialized", true)
	var tapered_copy = path_source._copy_line_visual(tapered_probe)
	var tapered_widths = []
	for index in range(int(tapered_copy.call("get_point_count"))):
		tapered_widths.append(float(tapered_copy.call("get_point_width", index)))
	var tapered_bounds = path_source._get_line_local_rect(tapered_probe)
	_expect(tapered_widths.size() == 2 and is_equal_approx(float(tapered_widths[0]), 0.25) and is_equal_approx(float(tapered_widths[1]), 10.0), "smoothed-path capture clone copies initialized absolute per-point widths")
	_expect(is_equal_approx(tapered_bounds.size.y, 10.0), "tapered bounds use absolute point width instead of multiplying by global width")
	tapered_copy.free()
	tapered_probe.free()
	if path_source._has_property(source, "super") and path_source._has_property(copied, "super"):
		var original_super = bool(source.get("super"))
		var before_super_signature = path_source.visual_signature(source)
		_expect(bool(copied.get("super")) == original_super, "native Line2D super flag is copied into the isolated capture")
		source.set("super", not original_super)
		_expect(before_super_signature != path_source.visual_signature(source), "visual signature detects native Line2D super flag changes")
		_expect(bool(copied.get("super")) == original_super, "changing the live Line2D super flag leaves an existing capture snapshot unchanged")
		source.set("super", original_super)
	source.gradient.set_color(0, Color(1, 1, 1, 0.23))
	source.width_curve.set_point_value(1, 1.7)
	_expect(is_equal_approx(copied.gradient.get_color(0).a, source_gradient_alpha), "editing the live transition Gradient does not change a capture snapshot")
	_expect(is_equal_approx(copied.width_curve.get_point_position(1).y, 1.0), "editing the live width Curve does not change a capture snapshot")

	var same_resource_signature = path_source.visual_signature(source)
	source.gradient.set_color(0, Color(1, 1, 1, 0.31))
	_expect(same_resource_signature != path_source.visual_signature(source), "visual signature detects in-place Gradient edits without a new resource id")
	same_resource_signature = path_source.visual_signature(source)
	source.width_curve.set_point_value(1, 1.9)
	var curve_signature_after = path_source.visual_signature(source)
	_expect(same_resource_signature != curve_signature_after, "visual signature detects in-place Curve edits without a new resource id")
	var independent_copy = copied
	independent_copy.material = null
	independent_copy.gradient.set_color(0, Color(1, 1, 1, 1))
	independent_copy.gradient.set_color(1, Color(1, 1, 1, 1))
	owner.add_child(independent_copy)
	var copy_capture = yield(path_source.capture_line(independent_copy, owner, 128), "completed")
	_expect(copy_capture.get("ok", false) and _alpha_sum(copy_capture.get("image", null)) > 0.0, "independent visual clone remains renderable by the native Line2D capture path")
	owner.queue_free()
	yield(VisualServer, "frame_post_draw")
	_finish()

func _fixture_pathway():
	var pathway = GetterOnlyPathway.new()
	pathway.name = "GetterOnlyPathway"
	pathway.points = PoolVector2Array([Vector2(2, 8), Vector2(18, 8)])
	pathway.SetEditPoints(pathway.points)
	pathway.width = 6.0
	pathway.antialiased = false
	var alpha_gradient = Gradient.new()
	alpha_gradient.set_color(0, Color(1, 1, 1, 1))
	alpha_gradient.set_color(1, Color(1, 1, 1, 1))
	pathway.gradient = alpha_gradient
	var width_curve = Curve.new()
	width_curve.max_value = 3.0
	width_curve.add_point(Vector2(0, 1))
	width_curve.add_point(Vector2(1, 1))
	pathway.width_curve = width_curve
	_disconnect_native_line_curve_callback(width_curve, pathway)
	return pathway

func _fixture_shader_material() -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = "shader_type canvas_item; uniform float gain = 1.0; void fragment() { COLOR = vec4(1.0, 1.0, 1.0, COLOR.a * gain); }"
	var material = ShaderMaterial.new()
	material.shader = shader
	return material

func _disconnect_native_line_curve_callback(curve: Curve, line: Line2D):
	# This Dungeondraft test engine exposes a C++ Line2D callback through a
	# GDScript mock, but the callback is not callable on that mock. Disconnect
	# only that fixture connection before mutating the Curve; production nodes
	# retain their native connection and the signature test still sees the edit.
	for connection in curve.get_signal_connection_list("changed"):
		if connection.get("target", null) == line and str(connection.get("method", "")) == "_curve_changed":
			curve.disconnect("changed", line, "_curve_changed")

func _alpha_sum(image):
	if not (image is Image) or image.is_empty():
		return 0.0
	image.lock()
	var result = 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			result += image.get_pixel(x, y).a
	image.unlock()
	return result

func _alpha_level_count(image):
	if not (image is Image) or image.is_empty():
		return 0
	var levels = {}
	image.lock()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var alpha = image.get_pixel(x, y).a
			levels[str(int(round(alpha * 255.0)))] = true
	image.unlock()
	return levels.size()

func _sample_capture_alpha(capture, local_point):
	if not capture.get("ok", false):
		return -1.0
	var image = capture.get("image", null)
	if not (image is Image) or image.is_empty():
		return -1.0
	var pixel_to_local = capture.get("pixel_to_local", Transform2D())
	var pixel = pixel_to_local.affine_inverse().xform(local_point)
	var x = int(floor(pixel.x))
	var y = int(floor(pixel.y))
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return -1.0
	image.lock()
	var alpha = image.get_pixel(x, y).a
	image.unlock()
	return alpha

func _expect(condition, message):
	if condition:
		lines.append("PASS: " + message)
		print("PASS: " + message)
	else:
		_fail(message)

func _fail(message):
	failures.append(message)
	lines.append("FAIL: " + message)
	printerr("FAIL: " + message)

func _finish():
	var report = File.new()
	if report.open("res://.staged/path-suite-report.txt", File.WRITE) == OK:
		for line in lines:
			report.store_line(line)
		report.store_line("FAILURE_COUNT: %d" % failures.size())
		report.store_line("RESULT: %s" % ("PASS" if failures.empty() else "FAIL"))
		report.close()
	if failures.empty():
		print("RESULT: PASS")
		quit(0)
	else:
		printerr("RESULT: FAIL (%d failures)" % failures.size())
		quit(1)
