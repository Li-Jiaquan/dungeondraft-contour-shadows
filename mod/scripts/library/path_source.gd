extends Reference

var script_class = "reference"

const DEFAULT_MAX_DIMENSION = 2048
const MAX_CAPTURE_DIMENSION = 4096
const EDGE_PADDING = 2.0
const MIN_DETERMINANT = 0.000001
const SIGNATURE_VERSION = "path-visual-v3"


func start():
	pass


func is_pathway(node) -> bool:
	if node == null or not is_instance_valid(node) or not (node is Line2D):
		return false
	if not node.has_method("Save") or not node.has_method("SetEditPoints") or not node.has_method("Smooth"):
		return false
	var has_smoothness = _has_property(node, "Smoothness") or node.has_method("get_Smoothness")
	var has_edit_points = _has_property(node, "EditPoints") or node.has_method("get_EditPoints")
	return has_smoothness and has_edit_points


func visual_signature(source) -> String:
	if not is_pathway(source):
		return "missing-pathway"
	var fields = [SIGNATURE_VERSION]
	var saved = source.call("Save", false)
	if typeof(saved) != TYPE_DICTIONARY:
		saved = {}
	# Pathway's C# properties are not advertised through get_property_list() in
	# the shipped Dungeondraft build. Save(false) provides their persisted state
	# in a small dictionary; keep only fields that can change the visible line.
	for saved_name in ["edit_points", "smoothness", "fade_in", "fade_out", "grow", "shrink"]:
		if saved.has(saved_name):
			fields.append(saved_name + "=" + _signature_value(saved[saved_name]))
	for property_name in [
		"points",
		"width",
		"width_curve",
		"default_color",
		"super",
		"gradient",
		"texture",
		"texture_mode",
		"joint_mode",
		"begin_cap_mode",
		"end_cap_mode",
		"sharp_limit",
		"round_precision",
		"antialiased",
		"loop",
		"normalize_uv",
		"material",
		"use_parent_material"
	]:
		if _has_property(source, property_name):
			fields.append(property_name + "=" + _signature_value(source.get(property_name)))
	return PoolStringArray(fields).join("|")


func capture(pathway, lifetime_owner: Node, max_dimension: int = DEFAULT_MAX_DIMENSION, set_2d_viewport_usage: bool = false):
	return _capture_async(pathway, lifetime_owner, max_dimension, true, set_2d_viewport_usage)


func capture_line(line: Line2D, lifetime_owner: Node, max_dimension: int = DEFAULT_MAX_DIMENSION, set_2d_viewport_usage: bool = false):
	return _capture_async(line, lifetime_owner, max_dimension, false, set_2d_viewport_usage)


func _capture_async(line, lifetime_owner: Node, max_dimension: int, require_pathway: bool, set_2d_viewport_usage: bool):
	# Yield before validation too, so every failure result has the same awaitable
	# shape as a successful capture.
	yield(VisualServer, "frame_post_draw")
	var validation_error = ""
	if require_pathway and not is_pathway(line):
		validation_error = "Source is not a Dungeondraft Pathway."
	elif line == null or not is_instance_valid(line):
		validation_error = "Line source is no longer available."
	elif lifetime_owner == null or not is_instance_valid(lifetime_owner) or not lifetime_owner.is_inside_tree():
		validation_error = "Capture owner must be inside the scene tree."
	elif max_dimension < 1:
		validation_error = "max_dimension must be at least 1."
	elif line.points.size() < 2:
		validation_error = "Line source needs at least two rendered points."
	if not validation_error.empty():
		return _failure(validation_error)

	var content_rect: Rect2 = _get_line_local_rect(line)
	if content_rect.size.x <= 0.0 or content_rect.size.y <= 0.0:
		return _failure("Line source has empty rendered bounds.")

	var capture_origin = Vector2(
		floor(content_rect.position.x) - EDGE_PADDING,
		floor(content_rect.position.y) - EDGE_PADDING
	)
	var capture_end = Vector2(
		ceil(content_rect.position.x + content_rect.size.x) + EDGE_PADDING,
		ceil(content_rect.position.y + content_rect.size.y) + EDGE_PADDING
	)
	var capture_size = capture_end - capture_origin
	if capture_size.x <= 0.0 or capture_size.y <= 0.0:
		return _failure("Line source bounds are invalid.")

	var output_limit = min(max_dimension, MAX_CAPTURE_DIMENSION)
	var raster_scale = min(1.0, float(output_limit) / max(capture_size.x, capture_size.y))
	var image_width = max(1, int(ceil(capture_size.x * raster_scale)))
	var image_height = max(1, int(ceil(capture_size.y * raster_scale)))
	# Protect against a one-pixel overflow from float rounding at the dimension cap.
	if image_width > output_limit or image_height > output_limit:
		raster_scale *= float(output_limit) / float(max(image_width, image_height))
		image_width = max(1, int(ceil(capture_size.x * raster_scale)))
		image_height = max(1, int(ceil(capture_size.y * raster_scale)))
	if image_width > output_limit or image_height > output_limit:
		return _failure("Line source could not fit within the capture limit.")

	var viewport = Viewport.new()
	viewport.name = "ContourShadowPathCapture"
	viewport.size = Vector2(image_width, image_height)
	if set_2d_viewport_usage:
		viewport.usage = Viewport.USAGE_2D
	viewport.own_world_2d = true
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = Viewport.UPDATE_ONCE

	var draw_copy = _copy_line_visual(line)
	draw_copy.position = -capture_origin * raster_scale
	draw_copy.scale = Vector2.ONE * raster_scale
	viewport.add_child(draw_copy)
	lifetime_owner.add_child(viewport)

	# A frame boundary is required before ViewportTexture.get_data() contains the
	# newly submitted Line2D. The temporary viewport is parented to the host so
	# unloading the mod also releases an outstanding capture.
	yield(VisualServer, "frame_post_draw")
	if not is_instance_valid(viewport):
		return _failure("Capture owner was removed before the viewport rendered.")
	if not is_instance_valid(line) or not line.is_inside_tree():
		viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
		viewport.queue_free()
		yield(VisualServer, "frame_post_draw")
		return _failure("Line source was removed before the viewport rendered.")

	var viewport_texture = viewport.get_texture()
	var image = viewport_texture.get_data()
	viewport_texture = null
	viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
	viewport.queue_free()
	# queue_free() is deferred. Wait until its scene-tree deletion has been
	# processed before returning the captured Image, so callers can immediately
	# release the source owner (for example when a floor changes) without racing
	# the temporary viewport's render-target teardown.
	yield(VisualServer, "frame_post_draw")
	if image == null or image.is_empty():
		return _failure("The Pathway viewport produced no image.")
	if image.is_compressed():
		var decompress_error = image.decompress()
		if decompress_error != OK:
			return _failure("Could not decompress the Pathway viewport image (error %d)." % decompress_error)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	if image.is_compressed() or image.get_format() != Image.FORMAT_RGBA8:
		return _failure("The Pathway viewport image could not be converted to RGBA8.")

	# Godot 3's ViewportTexture readback has a bottom-left origin. Restore the
	# top-left image convention used by Image.get_pixel and the renderer.
	image.flip_y()
	var pixel_scale = 1.0 / raster_scale
	var rect = Rect2(capture_origin, Vector2(image_width, image_height) * pixel_scale)
	var pixel_to_local = Transform2D(
		Vector2(pixel_scale, 0.0),
		Vector2(0.0, pixel_scale),
		capture_origin
	)
	return {
		"ok": true,
		"image": image,
		"rect": rect,
		"path_rect": content_rect,
		"pixel_scale": pixel_scale,
		"pixel_to_local": pixel_to_local,
		"kind": "path"
	}


func _copy_line_visual(source: Line2D) -> Line2D:
	var copy = Line2D.new()
	# Pathway.Smooth() stores Grow/Shrink tapers in Line2D's private absolute
	# per-point widths array. Read it only from an actual tapered Pathway: the
	# engine's getter crashes if that array has not first been initialized.
	var taper_widths = _read_taper_widths(source)
	var visual_properties = [
		"super",
		"points",
		"closed",
		"width",
		"width_curve",
		"default_color",
		"gradient",
		"texture",
		"texture_mode",
		"joint_mode",
		"begin_cap_mode",
		"end_cap_mode",
		"sharp_limit",
		"round_precision",
		"antialiased",
		"loop",
		"normalize_uv",
		"material",
		"use_parent_material"
	]
	for property_name in visual_properties:
		if property_name == "points":
			continue
		if _has_property(source, property_name) and _has_property(copy, property_name):
			var value = source.get(property_name)
			if property_name in ["width_curve", "gradient", "material"] and value is Resource:
				# Pathway.UpdateGradient() and Line2D rendering both consume mutable
				# resources. Keep the capture snapshot independent from the live path.
				value = value.duplicate(true)
			copy.set(property_name, value)
	if taper_widths.size() == source.points.size() and copy.has_method("clear_points") and copy.has_method("add_point") and copy.has_method("set_point_width"):
		# A points-property assignment does not initialize Line2D's hidden width
		# storage. add_point() establishes the point slots; then write every
		# absolute pixel width copied from the smoothed Pathway.
		copy.call("clear_points")
		for point in source.points:
			copy.call("add_point", point)
		for index in range(taper_widths.size()):
			copy.call("set_point_width", index, float(taper_widths[index]))
	else:
		copy.points = source.points

	# Sample the path's intrinsic alpha. The real source node remains the
	# shadow's parent, so its own opacity and any hidden/compare-layer alpha are
	# applied exactly once when the shadow is drawn.
	copy.visible = true
	copy.self_modulate = Color(1, 1, 1, 1)
	copy.modulate = Color(1, 1, 1, 1)
	return copy


func _get_line_local_rect(line: Line2D) -> Rect2:
	var points: PoolVector2Array = line.points
	if points.empty():
		return Rect2()
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point in points:
		minimum.x = min(minimum.x, point.x)
		minimum.y = min(minimum.y, point.y)
		maximum.x = max(maximum.x, point.x)
		maximum.y = max(maximum.y, point.y)

	var half_width = _get_line_half_width(line)
	var joint_padding_scale = 1.0
	if int(line.joint_mode) == Line2D.LINE_JOINT_SHARP and _has_property(line, "sharp_limit"):
		# Godot 3.4 LineBuilder compares the outer-corner distance against
		# half_width * width_curve_scale * sharp_limit, then falls back to a
		# bevel. This gives us a real upper bound for sharp joins instead of an
		# arbitrary fixed multiplier that wastes pixels on broad paths.
		joint_padding_scale = max(1.0, abs(float(line.get("sharp_limit"))))
	var padding = max(1.0, half_width * joint_padding_scale)
	return Rect2(minimum - Vector2.ONE * padding, maximum - minimum + Vector2.ONE * padding * 2.0)


func _get_width_curve_max_scale(line: Line2D) -> float:
	var maximum_scale = 1.0
	var curve = line.width_curve
	if curve == null or not is_instance_valid(curve):
		return maximum_scale
	if _has_property(curve, "max_value"):
		maximum_scale = max(maximum_scale, abs(float(curve.get("max_value"))))
	if curve.has_method("get_baked_points"):
		for baked_point in curve.get_baked_points():
			maximum_scale = max(maximum_scale, abs(baked_point.y))
	if curve.has_method("get_point_count") and curve.has_method("get_point_position"):
		for index in range(int(curve.get_point_count())):
			var curve_point: Vector2 = curve.get_point_position(index)
			maximum_scale = max(maximum_scale, abs(curve_point.y))
	return maximum_scale


func _get_line_half_width(line: Line2D) -> float:
	var widths = _read_taper_widths(line)
	if widths.size() > 0:
		var max_width = 0.0
		for width in widths:
			max_width = max(max_width, abs(float(width)))
		return max_width * 0.5
	return abs(float(line.width)) * _get_width_curve_max_scale(line) * 0.5


func _read_taper_widths(line: Line2D) -> Array:
	var widths = []
	if not _has_taper_width_storage(line):
		return widths
	var point_count = min(int(line.call("get_point_count")), line.points.size())
	for index in range(point_count):
		widths.append(float(line.call("get_point_width", index)))
	return widths


func _has_taper_width_storage(line: Line2D) -> bool:
	# Save(false) exposes the transition flags while the native width array is
	# private. Smooth() initializes that array for a real C# Pathway with Grow or
	# Shrink enabled. GDScript mocks can advertise the same Save() fields without
	# having initialized the native array, so production reads are CSharpScript-only.
	if not is_pathway(line) or not line.has_method("get_point_width") or not line.has_method("set_point_width") or not line.has_method("get_point_count"):
		return false
	var saved = line.call("Save", false)
	if typeof(saved) != TYPE_DICTIONARY or line.points.size() < 2:
		return false
	if not (bool(saved.get("grow", false)) or bool(saved.get("shrink", false))):
		return false
	var attached_script = line.get_script()
	if attached_script is Script and attached_script.get_class() == "CSharpScript":
		return true
	return false


func _signature_value(value) -> String:
	if value == null:
		return "null"
	if value is Gradient:
		var gradient_fields = [str(value.colors), str(value.offsets)]
		for property_name in ["interpolation_mode", "color_space"]:
			if _has_property(value, property_name):
				gradient_fields.append(property_name + "=" + str(value.get(property_name)))
		return "Gradient(" + PoolStringArray(gradient_fields).join(";") + ")"
	if value is Curve:
		var curve_fields = []
		for property_name in ["min_value", "max_value", "min_domain", "max_domain", "bake_resolution"]:
			if _has_property(value, property_name):
				curve_fields.append(property_name + "=" + str(value.get(property_name)))
		if value.has_method("get_point_count") and value.has_method("get_point_position"):
			for index in range(int(value.get_point_count())):
				var point_fields = ["p" + str(index) + "=" + str(value.get_point_position(index))]
				if value.has_method("get_point_left_tangent"):
					point_fields.append("left=" + str(value.get_point_left_tangent(index)))
				if value.has_method("get_point_right_tangent"):
					point_fields.append("right=" + str(value.get_point_right_tangent(index)))
				if value.has_method("get_point_left_mode"):
					point_fields.append("left_mode=" + str(value.get_point_left_mode(index)))
				if value.has_method("get_point_right_mode"):
					point_fields.append("right_mode=" + str(value.get_point_right_mode(index)))
				curve_fields.append(PoolStringArray(point_fields).join(","))
		if value.has_method("get_baked_points"):
			curve_fields.append("baked=" + str(value.get_baked_points()))
		return "Curve(" + PoolStringArray(curve_fields).join(";") + ")"
	if value is ShaderMaterial:
		var material_fields = [_resource_identity(value)]
		var shader = value.shader
		if shader != null:
			material_fields.append("shader=" + str(shader.code))
			for parameter_name in _shader_uniform_names(shader):
				material_fields.append(parameter_name + "=" + _signature_value(value.get_shader_param(parameter_name)))
		return "ShaderMaterial(" + PoolStringArray(material_fields).join(";") + ")"
	if value is Resource:
		return _resource_identity(value)
	return str(value)


func _resource_identity(resource: Resource) -> String:
	var fields = [str(resource.get_class()), str(resource.resource_path), str(resource.get_instance_id())]
	if resource is Texture and resource.has_method("get_size"):
		fields.append("size=" + str(resource.get_size()))
	return PoolStringArray(fields).join(":")


func _shader_uniform_names(shader: Shader) -> Array:
	var names = []
	if shader.has_method("get_param_list"):
		for parameter in shader.call("get_param_list"):
			var parameter_name = str(parameter.get("name", ""))
			if not parameter_name.empty() and not names.has(parameter_name):
				names.append(parameter_name)
	if not names.empty():
		return names
	# Godot 3.4's custom Dungeondraft build does not expose get_param_list() on
	# Shader. Parse simple uniform declarations so edits to live shader parameters
	# still invalidate follow generation on that engine version.
	var expression = RegEx.new()
	if expression.compile("(?m)\\buniform\\s+[A-Za-z_][A-Za-z0-9_]*\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*(?:\\[[^\\]]+\\])?\\s*(?::[^;]*)?(?:=[^;]*)?;") != OK:
		return names
	for match_result in expression.search_all(shader.code):
		var parameter_name = match_result.get_string(1)
		if not names.has(parameter_name):
			names.append(parameter_name)
	return names


func _has_property(object, property_name: String) -> bool:
	if object == null or not is_instance_valid(object):
		return false
	for property_info in object.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true
	return false


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
