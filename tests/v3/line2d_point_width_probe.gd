extends SceneTree

const REPORT_PATH = "res://v3/artifacts/line2d-point-width-probe.json"

var viewport = null
var line = null


func _init():
	call_deferred("_run")


func _run():
	viewport = Viewport.new()
	viewport.name = "Line2DPointWidthProbeViewport"
	viewport.size = Vector2(256, 256)
	viewport.transparent_bg = true
	viewport.own_world_2d = true
	viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	line = Line2D.new()
	line.name = "Line2DPointWidthProbe"
	line.width = 10.0
	line.default_color = Color(1.0, 1.0, 1.0, 1.0)
	line.antialiased = false
	for point in [Vector2(24, 128), Vector2(92, 128), Vector2(164, 128), Vector2(232, 128)]:
		line.add_point(point)
	viewport.add_child(line)

	var report = {"engine_version": Engine.get_version_info(), "class": "Line2D", "global_width": line.width}
	report["default_points_global_width_profile"] = yield(_capture_profile(false), "completed")
	var super_initialized = Line2D.new()
	super_initialized.set_super(true)
	super_initialized.clear_points()
	super_initialized.add_point(Vector2.ZERO)
	super_initialized.add_point(Vector2(10, 0))
	super_initialized.set_point_width(0, 0.25)
	super_initialized.set_point_width(1, 0.75)
	report["super_before_add_then_set_get"] = [super_initialized.get_point_width(0), super_initialized.get_point_width(1)]
	super_initialized.free()
	var requested_values = [0.0, 0.5, 5.0, 10.0]
	for point_index in range(requested_values.size()):
		line.set_point_width(point_index, requested_values[point_index])
	var getter_values = []
	for point_index in range(line.get_point_count()):
		getter_values.append(line.get_point_width(point_index))
	report["individual_setter_values"] = requested_values
	report["individual_getter_values"] = getter_values
	report["individual_profile_measurement"] = yield(_capture_profile(), "completed")

	line.width = 10.0
	_set_uniform_point_width(5.0)
	report["global10_point_width5"] = yield(_capture_profile(), "completed")
	line.width = 20.0
	report["global20_point_width5"] = yield(_capture_profile(), "completed")
	_set_uniform_point_width(10.0)
	line.width = 10.0
	report["global10_point_width10"] = yield(_capture_profile(), "completed")

	line.width = 10.0
	_set_uniform_point_width(5.0)
	line.set("super", false)
	report["super_false_point_width5"] = yield(_capture_profile(), "completed")
	line.set("super", true)
	report["super_true_point_width5"] = yield(_capture_profile(), "completed")
	var width_curve = Curve.new()
	width_curve.add_point(Vector2(0.0, 0.5))
	width_curve.add_point(Vector2(1.0, 0.5))
	width_curve.bake()
	line.width_curve = width_curve
	report["curve_property_assignment_matches"] = line.get_curve() == width_curve
	line.set_curve(null)
	report["width_curve_sample"] = {
		"point_count": width_curve.get_point_count(),
		"point0": str(width_curve.get_point_position(0)),
		"point1": str(width_curve.get_point_position(1)),
		"value_0": str(width_curve.interpolate(0.0)),
		"value_0_5": str(width_curve.interpolate(0.5)),
		"value_1": str(width_curve.interpolate(1.0)),
		"line_curve_is_null_before_native_setter": line.get_curve() == null
	}
	line.width_curve = width_curve
	line.set_curve(width_curve)
	report["line_curve_after_setter"] = str(line.get_curve())
	report["width_curve_constant_0_5"] = yield(_capture_profile(), "completed")
	_set_uniform_point_width(10.0)
	report["width_curve_constant_0_5_point_width10"] = yield(_capture_profile(), "completed")
	line.width_curve = null

	var copied = Line2D.new()
	for point in line.points:
		copied.add_point(point)
	for point_index in range(copied.get_point_count()):
		copied.set_point_width(point_index, 0.25)
	copied.points = line.points
	var copied_point_widths = []
	for point_index in range(copied.get_point_count()):
		copied_point_widths.append(copied.get_point_width(point_index))
	var source_point_widths = _read_point_widths()
	report["copied_points_width"] = copied.width
	report["copied_width_curve_is_null"] = copied.width_curve == null
	report["copied_points_point_widths"] = copied_point_widths
	report["copied_points_source_point_widths"] = source_point_widths
	copied.free()
	line.set_curve(null)
	line.clear_points()
	line.set("super", false)
	for point in [Vector2(24, 128), Vector2(92, 128), Vector2(164, 128), Vector2(232, 128)]:
		line.add_point(point)
	width_curve.clear_points()
	width_curve.add_point(Vector2(0.0, 0.5))
	width_curve.add_point(Vector2(1.0, 0.5))
	width_curve.bake()
	line.set_curve(width_curve)
	report["curve_only_line_curve_matches"] = line.get_curve() == width_curve
	report["width_curve_constant_0_5_without_point_width_writes"] = yield(_capture_profile(false), "completed")
	line.set_curve(null)
	width_curve.clear_points()
	width_curve.add_point(Vector2(0.0, 1.0))
	width_curve.add_point(Vector2(0.5, 0.0))
	width_curve.add_point(Vector2(1.0, 1.0))
	width_curve.bake()
	line.set_curve(width_curve)
	report["width_curve_taper_samples"] = [width_curve.interpolate(0.0), width_curve.interpolate(0.5), width_curve.interpolate(1.0)]
	report["width_curve_taper_without_point_width_writes"] = yield(_capture_profile(false), "completed")
	line.set("super", true)
	report["width_curve_taper_without_point_width_writes_super_true"] = yield(_capture_profile(false), "completed")
	line.set_curve(null)

	var absolute_path = ProjectSettings.globalize_path(REPORT_PATH)
	var directory = Directory.new()
	directory.make_dir_recursive(absolute_path.get_base_dir())
	var file = File.new()
	var error = file.open(absolute_path, File.WRITE)
	if error == OK:
		file.store_string(JSON.print(report, "\t"))
		file.close()
	print("LINE2D_POINT_WIDTH_PROBE=" + JSON.print(report))
	line = null
	viewport.queue_free()
	viewport = null
	quit(0 if error == OK else 1)


func _set_uniform_point_width(value: float):
	for point_index in range(line.get_point_count()):
		line.set_point_width(point_index, value)


func _capture_profile(include_point_widths: bool = true) -> Dictionary:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var texture = viewport.get_texture()
	var image = texture.get_data() if texture != null else null
	if image == null or image.is_empty():
		return {"ok": false, "reason": "viewport readback was empty"}
	var center_x = 128
	var count_above_half = 0
	var support_top = -1
	var support_bottom = -1
	var alpha_sum = 0.0
	var maximum_alpha = 0.0
	image.lock()
	for y in range(image.get_height()):
		var alpha = image.get_pixel(center_x, y).a
		alpha_sum += alpha
		maximum_alpha = max(maximum_alpha, alpha)
		if alpha > 0.5:
			count_above_half += 1
			if support_top < 0:
				support_top = y
			support_bottom = y
	image.unlock()
	var profile = {
		"ok": true,
		"global_width": line.width,
		"super": bool(line.get("super")),
		"pixels_alpha_above_0_5": count_above_half,
		"alpha_support_y": [support_top, support_bottom],
		"alpha_sum_on_center_column": alpha_sum,
		"max_alpha": maximum_alpha
	}
	if include_point_widths:
		profile["point_widths"] = _read_point_widths()
	return profile


func _read_point_widths() -> Array:
	var widths = []
	for point_index in range(line.get_point_count()):
		widths.append(line.get_point_width(point_index))
	return widths
