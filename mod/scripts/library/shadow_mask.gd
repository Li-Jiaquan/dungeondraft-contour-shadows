extends Reference

var script_class = "reference"

const MIN_DETERMINANT = 0.000001
const MAX_STROKE_COORDINATE = 10000000.0
const MAX_INFLUENCE_PIXELS = 512 * 512
const GPU_SEGMENTS_PER_PASS = 16

var _incremental_gpu_shader_cache = {}
var _incremental_gpu_dummy_texture = null

func start():
	pass


func render_gpu_stroke_async(stroke_start_visible_image: Image, stroke_template: Dictionary, local_points: Array, pixel_to_local: Transform2D, owner_node: Node) -> Dictionary:
	var started_usec = OS.get_ticks_usec()
	# Always yield once, including validation failures, so callers can uniformly
	# await this method without special-casing a synchronous Dictionary result.
	var startup_loop = Engine.get_main_loop()
	if startup_loop != null and startup_loop.has_signal("idle_frame"):
		yield(startup_loop, "idle_frame")
	if stroke_start_visible_image == null or stroke_start_visible_image.is_empty():
		return _gpu_stroke_failure("Visible image is empty.", started_usec)
	if typeof(stroke_template) != TYPE_DICTIONARY:
		return _gpu_stroke_failure("Stroke template must be a Dictionary.", started_usec)
	var radius = float(stroke_template.get("radius", 0.0))
	if not (radius > 0.0) or radius > MAX_STROKE_COORDINATE:
		return _gpu_stroke_failure("Stroke radius is invalid.", started_usec)
	var local_to_pixel = _inverse_or_null(pixel_to_local)
	if local_to_pixel == null:
		return _gpu_stroke_failure("Pixel-to-local transform is not invertible.", started_usec)
	var points = _read_points(local_points)
	if points.empty():
		return _gpu_stroke_failure("Stroke has no valid points.", started_usec)
	if owner_node == null or not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
		return _gpu_stroke_failure("GPU stroke requires an owner node inside the active SceneTree.", started_usec)
	var scene_tree = owner_node.get_tree()
	if scene_tree == null:
		return _gpu_stroke_failure("GPU stroke could not find the owner's SceneTree.", started_usec)

	var working = stroke_start_visible_image
	if working.is_compressed() or working.get_format() != Image.FORMAT_RGBA8:
		working = stroke_start_visible_image.duplicate()
		if working == null or working.is_empty():
			return _gpu_stroke_failure("Visible image could not be copied.", started_usec)
		if working.is_compressed() and working.decompress() != OK:
			return _gpu_stroke_failure("Visible image could not be decompressed.", started_usec)
		if working.get_format() != Image.FORMAT_RGBA8:
			working.convert(Image.FORMAT_RGBA8)
		if working.is_compressed() or working.get_format() != Image.FORMAT_RGBA8:
			return _gpu_stroke_failure("Visible image could not be converted to RGBA8.", started_usec)
	var width = working.get_width()
	var height = working.get_height()
	if width <= 0 or height <= 0:
		return _gpu_stroke_failure("Visible image has invalid dimensions.", started_usec)

	var brush_to_local = _read_radius_basis(stroke_template)
	if not _is_invertible(brush_to_local):
		brush_to_local = Transform2D()
	var local_to_brush = brush_to_local.affine_inverse()
	var pixel_to_brush = local_to_brush * pixel_to_local
	var brush_points = []
	for local_point in points:
		brush_points.append(local_to_brush.xform(local_point))
	var hardness = _stroke_hardness(stroke_template)
	var source_texture = ImageTexture.new()
	source_texture.create_from_image(working, 0)
	if source_texture == null or source_texture.get_width() != width or source_texture.get_height() != height:
		return _gpu_stroke_failure("Could not create a GPU texture for the visible image.", started_usec)
	# Keep source colour independent from alpha. Some GLES2 canvas texture paths
	# premultiply sampled RGBA channels; RGB8 prevents source alpha from tinting RGB.
	var rgb_image = working.duplicate()
	if rgb_image == null or rgb_image.is_empty():
		return _gpu_stroke_failure("Could not copy an RGB-only GPU source image.", started_usec)
	rgb_image.convert(Image.FORMAT_RGB8)
	if rgb_image.is_compressed() or rgb_image.get_format() != Image.FORMAT_RGB8:
		return _gpu_stroke_failure("Could not prepare an RGB-only GPU source image.", started_usec)
	var source_rgb_texture = ImageTexture.new()
	source_rgb_texture.create_from_image(rgb_image, 0)
	rgb_image = null
	if source_rgb_texture == null or source_rgb_texture.get_width() != width or source_rgb_texture.get_height() != height:
		return _gpu_stroke_failure("Could not create an RGB-only GPU texture.", started_usec)
	var dummy_texture = _get_incremental_gpu_dummy_texture()
	if dummy_texture == null:
		return _gpu_stroke_failure("Could not create the GPU coverage placeholder texture.", started_usec)

	var stage_root = Node.new()
	stage_root.name = "ContourShadowGpuStroke"
	stage_root.pause_mode = Node.PAUSE_MODE_PROCESS
	owner_node.add_child(stage_root)
	var gpu_viewports = []
	var previous_viewport = null
	var batch_start = 0
	var coverage_pass_count = 0
	while batch_start < brush_points.size():
		if coverage_pass_count >= 64:
			previous_viewport = null
			source_texture = null
			source_rgb_texture = null
			dummy_texture = null
			working = null
			gpu_viewports.clear()
			yield(_release_incremental_gpu_stage(scene_tree, stage_root), "completed")
			return _gpu_stroke_failure("GPU stroke exceeds the 1024-point / 64-pass safety limit.", started_usec)
		var batch_end = min(brush_points.size() - 1, batch_start + GPU_SEGMENTS_PER_PASS)
		var batch_count = batch_end - batch_start + 1
		var point_uniforms = PoolVector2Array()
		for batch_index in range(batch_count):
			point_uniforms.append(brush_points[batch_start + batch_index])
		while point_uniforms.size() < GPU_SEGMENTS_PER_PASS + 1:
			point_uniforms.append(Vector2.ZERO)
		var coverage_viewport = _make_incremental_gpu_viewport(
			stage_root,
			"stroke_coverage_%02d" % gpu_viewports.size(),
			width,
			height,
			_gpu_stroke_coverage_shader()
		)
		gpu_viewports.append(coverage_viewport)
		coverage_pass_count += 1
		var coverage_material = coverage_viewport.get_child(0).material
		coverage_material.set_shader_param("target_size", Vector2(width, height))
		coverage_material.set_shader_param("pixel_to_brush_x", Vector3(pixel_to_brush.x.x, pixel_to_brush.y.x, pixel_to_brush.origin.x))
		coverage_material.set_shader_param("pixel_to_brush_y", Vector3(pixel_to_brush.x.y, pixel_to_brush.y.y, pixel_to_brush.origin.y))
		for point_index in range(point_uniforms.size()):
			coverage_material.set_shader_param("point_%02d" % point_index, point_uniforms[point_index])
		coverage_material.set_shader_param("point_count", batch_count)
		coverage_material.set_shader_param("radius", radius)
		coverage_material.set_shader_param("hardness", hardness)
		coverage_material.set_shader_param("has_previous", 1 if previous_viewport != null else 0)
		coverage_material.set_shader_param("source_tex", previous_viewport.get_texture() if previous_viewport != null else dummy_texture)
		previous_viewport = coverage_viewport
		if batch_end >= brush_points.size() - 1:
			break
		batch_start = batch_end

	var composite_viewport = _make_incremental_gpu_viewport(stage_root, "stroke_composite", width, height, _gpu_stroke_composite_shader())
	gpu_viewports.append(composite_viewport)
	var composite_material = composite_viewport.get_child(0).material
	composite_material.set_shader_param("source_tex", source_texture)
	composite_material.set_shader_param("source_rgb_tex", source_rgb_texture)
	composite_material.set_shader_param("influence_tex", previous_viewport.get_texture())

	for gpu_viewport in gpu_viewports:
		gpu_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	# As with the contour renderer, Godot 3.4 needs two frames for a dynamically
	# created viewport dependency chain to render before its texture can be read.
	for frame_index in range(2):
		yield(scene_tree, "idle_frame")
		if not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
			previous_viewport = null
			composite_viewport = null
			source_texture = null
			source_rgb_texture = null
			dummy_texture = null
			working = null
			gpu_viewports.clear()
			yield(_release_incremental_gpu_stage(scene_tree, stage_root), "completed")
			return _gpu_stroke_failure("Stroke owner left the tree before GPU readback completed.", started_usec)

	var final_texture = composite_viewport.get_texture()
	var output_image = final_texture.get_data()
	var render_pass_count = gpu_viewports.size()
	if output_image == null or output_image.is_empty():
		final_texture = null
		output_image = null
		previous_viewport = null
		composite_viewport = null
		source_texture = null
		source_rgb_texture = null
		dummy_texture = null
		working = null
		gpu_viewports.clear()
		yield(_release_incremental_gpu_stage(scene_tree, stage_root), "completed")
		return _gpu_stroke_failure("GPU stroke readback returned no image.", started_usec)
	if output_image.is_compressed():
		var decompress_error = output_image.decompress()
		if decompress_error != OK:
			final_texture = null
			output_image = null
			previous_viewport = null
			composite_viewport = null
			source_texture = null
			source_rgb_texture = null
			dummy_texture = null
			working = null
			gpu_viewports.clear()
			yield(_release_incremental_gpu_stage(scene_tree, stage_root), "completed")
			return _gpu_stroke_failure("Could not decompress GPU stroke output (error %d)." % decompress_error, started_usec)
	if output_image.get_format() != Image.FORMAT_RGBA8:
		output_image.convert(Image.FORMAT_RGBA8)
	if output_image.get_width() != width or output_image.get_height() != height:
		final_texture = null
		output_image = null
		previous_viewport = null
		composite_viewport = null
		source_texture = null
		source_rgb_texture = null
		dummy_texture = null
		working = null
		gpu_viewports.clear()
		yield(_release_incremental_gpu_stage(scene_tree, stage_root), "completed")
		return _gpu_stroke_failure("GPU stroke dimensions do not match the source image.", started_usec)
	var baseline_image_for_restore = working

	final_texture = null
	previous_viewport = null
	composite_viewport = null
	source_texture = null
	source_rgb_texture = null
	dummy_texture = null
	working = null
	gpu_viewports.clear()
	yield(_release_incremental_gpu_stage(scene_tree, stage_root), "completed")
	if not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
		return _gpu_stroke_failure("Stroke owner left the tree before GPU resources were released.", started_usec)
	var video_driver = _gpu_video_driver_name()
	var backend = "gpu_viewport"
	var cpu_composite_frames = 0
	var cpu_composite_usec = 0
	var cpu_composite_max_slice_usec = 0
	if video_driver.to_upper().find("GLES2") >= 0:
		var baseline_data = baseline_image_for_restore.get_data()
		var rendered_data = output_image.get_data()
		var pixel_count = width * height
		if baseline_data.size() < pixel_count * 4 or rendered_data.size() < pixel_count * 4:
			return _gpu_stroke_failure("GLES2 alpha composition pixel data is incomplete.", started_usec)
		var pixel_index = 0
		while pixel_index < pixel_count:
			if not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
				return _gpu_stroke_failure("Stroke owner left the tree during GLES2 alpha composition.", started_usec)
			var slice_started_usec = OS.get_ticks_usec()
			var slice_pixels = 0
			var next_slice_time_check = 256
			while pixel_index < pixel_count and slice_pixels < 65536:
				var alpha_index = pixel_index * 4 + 3
				baseline_data[alpha_index] = rendered_data[alpha_index]
				pixel_index += 1
				slice_pixels += 1
				if slice_pixels >= next_slice_time_check:
					if OS.get_ticks_usec() - slice_started_usec >= 6000:
						break
					next_slice_time_check += 256
			var slice_usec = OS.get_ticks_usec() - slice_started_usec
			cpu_composite_usec += slice_usec
			cpu_composite_max_slice_usec = max(cpu_composite_max_slice_usec, slice_usec)
			cpu_composite_frames += 1
			if pixel_index < pixel_count:
				yield(scene_tree, "idle_frame")
		var restored_image = Image.new()
		restored_image.create_from_data(width, height, false, Image.FORMAT_RGBA8, baseline_data)
		if restored_image.is_empty() or restored_image.get_size() != output_image.get_size():
			return _gpu_stroke_failure("Could not create the GLES2-composited image.", started_usec)
		output_image = restored_image
		backend = "gpu_coverage_cpu_composite"
		if not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
			return _gpu_stroke_failure("Stroke owner left the tree during GLES2 alpha composition.", started_usec)
	return {
		"ok": true,
		"image": output_image,
		"backend": backend,
		"video_driver": video_driver,
		"elapsed_ms": _gpu_stroke_elapsed_ms(started_usec),
		"cpu_composite_frames": cpu_composite_frames,
		"cpu_composite_usec": cpu_composite_usec,
		"cpu_composite_max_slice_usec": cpu_composite_max_slice_usec,
		"render_passes": render_pass_count
	}


func _get_incremental_gpu_dummy_texture():
	if _incremental_gpu_dummy_texture != null and is_instance_valid(_incremental_gpu_dummy_texture):
		return _incremental_gpu_dummy_texture
	var image = Image.new()
	image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var texture = ImageTexture.new()
	texture.create_from_image(image, 0)
	_incremental_gpu_dummy_texture = texture
	return texture


func _make_incremental_gpu_viewport(parent: Node, viewport_name: String, width: int, height: int, shader_code: String) -> Viewport:
	var viewport = Viewport.new()
	viewport.name = viewport_name
	viewport.size = Vector2(width, height)
	viewport.own_world_2d = true
	viewport.transparent_bg = true
	viewport.render_target_v_flip = true
	viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
	parent.add_child(viewport)
	var rect = ColorRect.new()
	rect.name = "ShaderPass"
	rect.rect_size = Vector2(width, height)
	var shader = _incremental_gpu_shader_cache.get(shader_code, null)
	if shader == null:
		shader = Shader.new()
		shader.code = shader_code
		_incremental_gpu_shader_cache[shader_code] = shader
	var material = ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	viewport.add_child(rect)
	return viewport


func _gpu_stroke_coverage_shader() -> String:
	var shader_code = """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D source_tex;
uniform vec2 target_size;
uniform vec3 pixel_to_brush_x;
uniform vec3 pixel_to_brush_y;
uniform int point_count;
uniform int has_previous;
uniform float radius;
uniform float hardness;
float point_influence(vec2 pixel, vec2 point) {
	float distance_to_path = length(pixel - point);
	if (distance_to_path > radius) {
		return 0.0;
	}
	float inner_radius = radius * hardness;
	if (distance_to_path <= inner_radius || inner_radius >= radius) {
		return 1.0;
	}
	float t = clamp((distance_to_path - inner_radius) / (radius - inner_radius), 0.0, 1.0);
	float smooth_value = t * t * (3.0 - 2.0 * t);
	return 1.0 - smooth_value;
}
float segment_influence(vec2 pixel, vec2 start_point, vec2 end_point) {
	vec2 segment = end_point - start_point;
	float length_squared = dot(segment, segment);
	float ratio = 0.0;
	if (length_squared > 0.000001) {
		ratio = clamp(dot(pixel - start_point, segment) / length_squared, 0.0, 1.0);
	}
	return point_influence(pixel, start_point + segment * ratio);
}
void fragment() {
	vec2 pixel = UV * target_size;
	vec3 pixel_h = vec3(pixel, 1.0);
	vec2 brush_pixel = vec2(dot(pixel_to_brush_x, pixel_h), dot(pixel_to_brush_y, pixel_h));
	float influence = 0.0;
	if (has_previous != 0) {
		influence = texture(source_tex, UV).a;
	}
	COLOR = vec4(1.0, 1.0, 1.0, influence);
}
"""
	var point_uniforms = ""
	for point_index in range(GPU_SEGMENTS_PER_PASS + 1):
		point_uniforms += "uniform vec2 point_%02d;\n" % point_index
	var declarations_position = shader_code.find("float point_influence(vec2 pixel, vec2 point) {")
	if declarations_position >= 0:
		shader_code = shader_code.substr(0, declarations_position) + point_uniforms + shader_code.substr(declarations_position)
	var fragment_start = shader_code.find("void fragment() {")
	if fragment_start < 0:
		return shader_code
	var insertion_point = shader_code.find("\tCOLOR = vec4(1.0, 1.0, 1.0, influence);", fragment_start)
	if insertion_point < 0:
		return shader_code
	var point_operations = "\tif (point_count == 1) {\n\t\tinfluence = max(influence, point_influence(brush_pixel, point_00));\n\t}\n"
	for segment_index in range(GPU_SEGMENTS_PER_PASS):
		var start_name = "point_%02d" % segment_index
		var end_name = "point_%02d" % (segment_index + 1)
		point_operations += "\tif (point_count > %d && influence < 0.999999) { influence = max(influence, segment_influence(brush_pixel, %s, %s)); }\n" % [segment_index + 1, start_name, end_name]
	shader_code = shader_code.substr(0, insertion_point) + point_operations + shader_code.substr(insertion_point)
	return shader_code


func _release_incremental_gpu_stage(scene_tree: SceneTree, stage_root: Node) -> bool:
	if is_instance_valid(stage_root):
		for child in stage_root.get_children():
			if child is Viewport:
				child.render_target_update_mode = Viewport.UPDATE_DISABLED
				if child.get_child_count() > 0:
					var pass_node = child.get_child(0)
					if pass_node.material is ShaderMaterial:
						var material = pass_node.material
						material.set_shader_param("source_tex", null)
						material.set_shader_param("source_rgb_tex", null)
						material.set_shader_param("influence_tex", null)
		stage_root.queue_free()
	if VisualServer.has_signal("frame_post_draw"):
		yield(VisualServer, "frame_post_draw")
	else:
		yield(scene_tree, "idle_frame")
	return true


func _gpu_stroke_composite_shader() -> String:
	return """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D source_tex;
uniform sampler2D source_rgb_tex;
uniform sampler2D influence_tex;
void fragment() {
	vec4 source_color = texture(source_tex, UV);
	vec3 source_rgb = texture(source_rgb_tex, UV).rgb;
	float influence = texture(influence_tex, UV).a;
	COLOR = vec4(source_rgb, source_color.a * (1.0 - influence));
}
"""


func _gpu_video_driver_name() -> String:
	if not OS.has_method("get_current_video_driver") or not OS.has_method("get_video_driver_name"):
		return ""
	var driver_index = OS.call("get_current_video_driver")
	return str(OS.call("get_video_driver_name", driver_index))


func _gpu_stroke_failure(message: String, started_usec: int) -> Dictionary:
	return {"ok": false, "error": message, "backend": "gpu_viewport", "elapsed_ms": _gpu_stroke_elapsed_ms(started_usec)}


func _gpu_stroke_elapsed_ms(started_usec: int) -> float:
	return float(OS.get_ticks_usec() - started_usec) / 1000.0


func begin_incremental(visible_image: Image, stroke_template: Dictionary, pixel_to_local: Transform2D) -> Dictionary:
	if visible_image == null or visible_image.is_empty():
		return _incremental_failure("Visible image is empty.")
	if typeof(stroke_template) != TYPE_DICTIONARY:
		return _incremental_failure("Stroke template must be a Dictionary.")
	var radius = float(stroke_template.get("radius", 0.0))
	if not (radius > 0.0) or radius > MAX_STROKE_COORDINATE:
		return _incremental_failure("Stroke radius is invalid.")
	var local_to_pixel = _inverse_or_null(pixel_to_local)
	if local_to_pixel == null:
		return _incremental_failure("Pixel-to-local transform is not invertible.")

	var working = visible_image.duplicate()
	if working == null or working.is_empty():
		return _incremental_failure("Visible image could not be copied.")
	if working.is_compressed() and working.decompress() != OK:
		return _incremental_failure("Visible image could not be decompressed.")
	if working.get_format() != Image.FORMAT_RGBA8:
		working.convert(Image.FORMAT_RGBA8)
	if working.is_compressed() or working.get_format() != Image.FORMAT_RGBA8:
		return _incremental_failure("Visible image could not be converted to RGBA8.")
	var width = working.get_width()
	var height = working.get_height()
	if width <= 0 or height <= 0:
		return _incremental_failure("Visible image has invalid dimensions.")
	var baseline_data = working.get_data()
	if baseline_data.size() < width * height * 4:
		return _incremental_failure("Visible image pixel data is incomplete.")

	var brush_to_local = _read_radius_basis(stroke_template)
	if not _is_invertible(brush_to_local):
		brush_to_local = Transform2D()
	var local_to_brush = brush_to_local.affine_inverse()
	var pixel_to_brush = local_to_brush * pixel_to_local
	var brush_to_pixel = local_to_pixel * brush_to_local
	var extent_x = radius * sqrt(brush_to_pixel.x.x * brush_to_pixel.x.x + brush_to_pixel.y.x * brush_to_pixel.y.x)
	var extent_y = radius * sqrt(brush_to_pixel.x.y * brush_to_pixel.x.y + brush_to_pixel.y.y * brush_to_pixel.y.y)
	var influence_image = Image.new()
	influence_image.create(width, height, false, Image.FORMAT_L8)
	influence_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	var influence_data = influence_image.get_data()
	influence_image = null
	if influence_data.size() < width * height:
		return _incremental_failure("Could not allocate the stroke influence buffer.")

	var hardness = _stroke_hardness(stroke_template)
	return {
		"ok": true,
		"image": working,
		"width": width,
		"height": height,
		"baseline_data": baseline_data,
		"output_data": baseline_data,
		"influence_data": influence_data,
		"segments": [],
		"segment_head": 0,
		"cursor_x": 0,
		"cursor_y": 0,
		"local_to_pixel": local_to_pixel,
		"local_to_brush": local_to_brush,
		"pixel_to_brush": pixel_to_brush,
		"radius": radius,
		"radius_squared": radius * radius,
		"inner_radius": radius * hardness,
		"inner_radius_squared": radius * hardness * radius * hardness,
		"soft_band_width": radius * (1.0 - hardness),
		"hardness": hardness,
		"soft_edge": hardness < 1.0,
		"extent_x": extent_x,
		"extent_y": extent_y,
		"segments_enqueued": 0,
		"total_processed_pixels": 0,
		"total_influence_updates": 0,
		"total_touched_pixels": 0
	}


func enqueue_incremental(state: Dictionary, local_points: Array):
	if not bool(state.get("ok", false)):
		return
	var points = _read_points(local_points)
	if points.empty() or points.size() > 2:
		return
	var segment = _make_incremental_segment(state, points)
	if not bool(segment.get("ok", false)):
		return
	var segments: Array = state["segments"]
	if segments.empty():
		state["segment_head"] = 0
		state["cursor_x"] = segment["left"]
		state["cursor_y"] = segment["top"]
	else:
		var tail_index = segments.size() - 1
		var head_index = int(state["segment_head"])
		var tail: Dictionary = segments[tail_index]
		var tail_unstarted = tail_index > head_index or (int(state["cursor_x"]) == int(tail["left"]) and int(state["cursor_y"]) == int(tail["top"]))
		if tail_unstarted and _can_merge_incremental_segments(tail, segment):
			segments[tail_index] = _merge_incremental_segments(tail, segment, state)
			state["segments"] = segments
			state["segments_enqueued"] = int(state.get("segments_enqueued", 0)) + 1
			return
	segments.append(segment)
	state["segments"] = segments
	state["segments_enqueued"] = int(state.get("segments_enqueued", 0)) + 1


func _make_incremental_segment(state: Dictionary, points: Array) -> Dictionary:
	var local_to_pixel = state["local_to_pixel"]
	var local_to_brush = state["local_to_brush"]
	var image_a = local_to_pixel.xform(points[0])
	var image_b = local_to_pixel.xform(points[1]) if points.size() > 1 else image_a
	var brush_a = local_to_brush.xform(points[0])
	var brush_b = local_to_brush.xform(points[1]) if points.size() > 1 else brush_a
	var width = int(state["width"])
	var height = int(state["height"])
	var extent_x = float(state["extent_x"])
	var extent_y = float(state["extent_y"])
	var left = max(0, int(floor(min(image_a.x, image_b.x) - extent_x - 0.5)))
	var top = max(0, int(floor(min(image_a.y, image_b.y) - extent_y - 0.5)))
	var right = min(width - 1, int(ceil(max(image_a.x, image_b.x) + extent_x - 0.5)))
	var bottom = min(height - 1, int(ceil(max(image_a.y, image_b.y) + extent_y - 0.5)))
	if right < left or bottom < top:
		return {"ok": false}
	var brush_delta = brush_b - brush_a
	var delta_x = brush_delta.x
	var delta_y = brush_delta.y
	return {
		"ok": true,
		"image_a": image_a,
		"image_b": image_b,
		"brush_a": brush_a,
		"brush_b": brush_b,
		"delta_x": delta_x,
		"delta_y": delta_y,
		"length_squared": brush_delta.length_squared(),
		"left": left,
		"top": top,
		"right": right,
		"bottom": bottom
	}


func _can_merge_incremental_segments(first: Dictionary, second: Dictionary) -> bool:
	var first_dx = float(first["delta_x"])
	var first_dy = float(first["delta_y"])
	var second_dx = float(second["delta_x"])
	var second_dy = float(second["delta_y"])
	var first_length_squared = float(first["length_squared"])
	var second_length_squared = float(second["length_squared"])
	var first_end: Vector2 = first["brush_b"]
	var second_start: Vector2 = second["brush_a"]
	if first_end.distance_squared_to(second_start) > 0.00000001:
		return false
	if first_length_squared <= 0.000001 or second_length_squared <= 0.000001:
		return true
	var cross = first_dx * second_dy - first_dy * second_dx
	var collinear_limit = 0.00001 * sqrt(first_length_squared * second_length_squared)
	var forward_dot = first_dx * second_dx + first_dy * second_dy
	return abs(cross) <= collinear_limit and forward_dot > 0.0


func _merge_incremental_segments(first: Dictionary, second: Dictionary, state: Dictionary) -> Dictionary:
	var result = first.duplicate()
	var first_start: Vector2 = first["brush_a"]
	var second_end: Vector2 = second["brush_b"]
	if float(first["length_squared"]) <= 0.000001:
		result["delta_x"] = second_end.x - first_start.x
		result["delta_y"] = second_end.y - first_start.y
	elif float(second["length_squared"]) <= 0.000001:
		# A point at the previous endpoint is already part of that capsule.
		return result
	else:
		result["delta_x"] = second_end.x - first_start.x
		result["delta_y"] = second_end.y - first_start.y
	result["brush_b"] = second_end
	var merged_delta: Vector2 = second_end - first_start
	result["length_squared"] = merged_delta.length_squared()
	result["image_b"] = second["image_b"]
	var image_a: Vector2 = first["image_a"]
	var image_b: Vector2 = second["image_b"]
	var extent_x = float(state["extent_x"])
	var extent_y = float(state["extent_y"])
	var width = int(state["width"])
	var height = int(state["height"])
	result["left"] = max(0, int(floor(min(image_a.x, image_b.x) - extent_x - 0.5)))
	result["top"] = max(0, int(floor(min(image_a.y, image_b.y) - extent_y - 0.5)))
	result["right"] = min(width - 1, int(ceil(max(image_a.x, image_b.x) + extent_x - 0.5)))
	result["bottom"] = min(height - 1, int(ceil(max(image_a.y, image_b.y) + extent_y - 0.5)))
	return result


func advance_incremental(state: Dictionary, max_pixels: int = 4096, max_usec: int = 6000) -> Dictionary:
	var started_usec = OS.get_ticks_usec()
	if not bool(state.get("ok", false)):
		return {"ok": false, "changed": false, "pending": false, "processed_pixels": 0, "touched_pixels": 0, "dirty_rect": Rect2(), "image": null, "elapsed_usec": 0}
	var pixel_budget = max(1, max_pixels)
	var time_budget = max(1, max_usec)
	var width = int(state["width"])
	var height = int(state["height"])
	var baseline_data: PoolByteArray = state["baseline_data"]
	var output_data: PoolByteArray = state["output_data"]
	var influence_data: PoolByteArray = state["influence_data"]
	var segments: Array = state["segments"]
	var segment_head = int(state["segment_head"])
	var cursor_x = int(state["cursor_x"])
	var cursor_y = int(state["cursor_y"])
	var pixel_to_brush = state["pixel_to_brush"]
	var radius = float(state["radius"])
	var radius_squared = float(state["radius_squared"])
	var inner_radius = float(state["inner_radius"])
	var inner_radius_squared = float(state["inner_radius_squared"])
	var soft_band_width = float(state["soft_band_width"])
	var hardness = float(state["hardness"])
	var soft_edge = bool(state["soft_edge"])
	var processed_pixels = 0
	var influence_updates = 0
	var touched_pixels = 0
	var changed = false
	var dirty_left = width
	var dirty_top = height
	var dirty_right = -1
	var dirty_bottom = -1
	var next_time_check = 64
	var time_budget_exhausted = false
	while segment_head < segments.size() and processed_pixels < pixel_budget and not time_budget_exhausted:
		var segment: Dictionary = segments[segment_head]
		var segment_left = int(segment["left"])
		var segment_top = int(segment["top"])
		var segment_right = int(segment["right"])
		var segment_bottom = int(segment["bottom"])
		var brush_a: Vector2 = segment["brush_a"]
		var brush_b: Vector2 = segment["brush_b"]
		var brush_delta: Vector2 = brush_b - brush_a
		var length_squared = float(segment["length_squared"])
		while cursor_y <= segment_bottom and processed_pixels < pixel_budget:
			var x = cursor_x
			var y = cursor_y
			var mask_index = y * width + x
			var alpha_index = mask_index * 4 + 3
			var base_alpha = int(baseline_data[alpha_index])
			var old_weight = int(influence_data[mask_index])
			var current_alpha = int(output_data[alpha_index])
			# Once this pixel is fully erased, or its visible alpha has rounded to
			# zero, later same-stroke influence cannot change the rendered result.
			if base_alpha > 0 and old_weight < 255 and current_alpha > 0:
				var brush_point = pixel_to_brush.xform(Vector2(float(x) + 0.5, float(y) + 0.5))
				var closest_point = brush_a
				if length_squared > 0.000001:
					var ratio = clamp((brush_point - brush_a).dot(brush_delta) / length_squared, 0.0, 1.0)
					closest_point = brush_a + brush_delta * ratio
				var distance_squared = brush_point.distance_squared_to(closest_point)
				if distance_squared <= radius_squared:
					var erase_weight = _erase_weight(sqrt(distance_squared), radius, hardness)
					var weight_byte = int(round(erase_weight * 255.0))
					if weight_byte > old_weight:
						influence_data[mask_index] = weight_byte
						influence_updates += 1
						var new_alpha = int(round(float(base_alpha) * (1.0 - float(weight_byte) / 255.0)))
						if new_alpha != int(output_data[alpha_index]):
							output_data[alpha_index] = new_alpha
							touched_pixels += 1
							changed = true
							dirty_left = min(dirty_left, x)
							dirty_top = min(dirty_top, y)
							dirty_right = max(dirty_right, x)
							dirty_bottom = max(dirty_bottom, y)
			processed_pixels += 1
			if cursor_x < segment_right:
				cursor_x += 1
			else:
				cursor_x = segment_left
				cursor_y += 1
			if processed_pixels >= next_time_check:
				if OS.get_ticks_usec() - started_usec >= time_budget:
					time_budget_exhausted = true
					break
				next_time_check += 64
		if cursor_y > segment_bottom:
			segment_head += 1
			if segment_head < segments.size():
				var next_segment: Dictionary = segments[segment_head]
				cursor_x = int(next_segment["left"])
				cursor_y = int(next_segment["top"])
			else:
				segments = []
				segment_head = 0
				cursor_x = 0
				cursor_y = 0
				break
	state["output_data"] = output_data
	state["influence_data"] = influence_data
	state["segments"] = segments
	state["segment_head"] = segment_head
	state["cursor_x"] = cursor_x
	state["cursor_y"] = cursor_y
	state["total_processed_pixels"] = int(state["total_processed_pixels"]) + processed_pixels
	state["total_influence_updates"] = int(state["total_influence_updates"]) + influence_updates
	state["total_touched_pixels"] = int(state["total_touched_pixels"]) + touched_pixels
	var output_image: Image = state["image"]
	if changed:
		output_image = Image.new()
		output_image.create_from_data(width, height, false, Image.FORMAT_RGBA8, output_data)
		state["image"] = output_image
	var dirty_rect = Rect2()
	if changed:
		dirty_rect = Rect2(Vector2(dirty_left, dirty_top), Vector2(dirty_right - dirty_left + 1, dirty_bottom - dirty_top + 1))
	var elapsed_usec = OS.get_ticks_usec() - started_usec
	return {
		"ok": true,
		"changed": changed,
		"pending": segment_head < segments.size(),
		"processed_pixels": processed_pixels,
		"influence_updates": influence_updates,
		"touched_pixels": touched_pixels,
		"total_processed_pixels": state["total_processed_pixels"],
		"total_touched_pixels": state["total_touched_pixels"],
		"dirty_rect": dirty_rect,
		"image": output_image,
		"elapsed_usec": elapsed_usec
	}


func _incremental_failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func apply(source_image: Image, strokes: Array, pixel_to_local: Transform2D) -> Image:
	if source_image == null:
		return Image.new()

	# All conversion and pixel writes happen on a private image copy. Stroke
	# definitions remain JSON-friendly arrays of local-space point pairs.
	var working = source_image.duplicate()
	if working == null or working.is_empty():
		return working
	if working.is_compressed():
		if working.decompress() != OK:
			return working
	if working.get_format() != Image.FORMAT_RGBA8:
		working.convert(Image.FORMAT_RGBA8)
	if working.is_compressed() or working.get_format() != Image.FORMAT_RGBA8:
		return working
	if strokes.empty():
		return working

	var local_to_pixel = _inverse_or_null(pixel_to_local)
	if local_to_pixel == null:
		return working
	var width = working.get_width()
	var height = working.get_height()
	var pixels = working.get_data()
	if width <= 0 or height <= 0 or pixels.size() < width * height * 4:
		return working

	for stroke in strokes:
		if typeof(stroke) != TYPE_DICTIONARY:
			continue
		var radius = float(stroke.get("radius", 0.0))
		if not (radius > 0.0) or radius > MAX_STROKE_COORDINATE:
			continue
		var hardness = _stroke_hardness(stroke)
		var local_points = _read_points(stroke.get("points", []))
		if local_points.empty():
			continue

		var brush_to_local = _read_radius_basis(stroke)
		if not _is_invertible(brush_to_local):
			brush_to_local = Transform2D()
		var local_to_brush = brush_to_local.affine_inverse()
		var pixel_to_brush = local_to_brush * pixel_to_local
		var brush_to_pixel = local_to_pixel * brush_to_local
		var extent_x = radius * sqrt(brush_to_pixel.x.x * brush_to_pixel.x.x + brush_to_pixel.y.x * brush_to_pixel.y.x)
		var extent_y = radius * sqrt(brush_to_pixel.x.y * brush_to_pixel.x.y + brush_to_pixel.y.y * brush_to_pixel.y.y)
		var brush_points = []
		var image_points = []
		for local_point in local_points:
			brush_points.append(local_to_brush.xform(local_point))
			image_points.append(local_to_pixel.xform(local_point))

		var segment_count = max(1, brush_points.size() - 1)
		var segments = []
		var minimum_x = INF
		var minimum_y = INF
		var maximum_x = -INF
		var maximum_y = -INF
		for segment_index in range(segment_count):
			var point_a = brush_points[segment_index]
			var point_b = brush_points[segment_index + 1] if brush_points.size() > 1 else point_a
			var image_a = image_points[segment_index]
			var image_b = image_points[segment_index + 1] if image_points.size() > 1 else image_a
			segments.append({"a": point_a, "b": point_b, "image_a": image_a, "image_b": image_b})
			minimum_x = min(minimum_x, min(image_a.x, image_b.x) - extent_x)
			minimum_y = min(minimum_y, min(image_a.y, image_b.y) - extent_y)
			maximum_x = max(maximum_x, max(image_a.x, image_b.x) + extent_x)
			maximum_y = max(maximum_y, max(image_a.y, image_b.y) + extent_y)
		var bounds_left = max(0, int(floor(minimum_x - 0.5)))
		var bounds_top = max(0, int(floor(minimum_y - 0.5)))
		var bounds_right = min(width - 1, int(ceil(maximum_x - 0.5)))
		var bounds_bottom = min(height - 1, int(ceil(maximum_y - 0.5)))
		if bounds_right < bounds_left or bounds_bottom < bounds_top:
			continue

		# Store the strongest influence from this entire stroke before touching
		# alpha. Crossing/duplicate segments therefore do not erase repeatedly.
		var bounds_width = bounds_right - bounds_left + 1
		var tile_width = min(bounds_width, MAX_INFLUENCE_PIXELS)
		var tile_height = max(1, int(floor(float(MAX_INFLUENCE_PIXELS) / float(tile_width))))
		for tile_left in range(bounds_left, bounds_right + 1, tile_width):
			var active_tile_width = min(tile_width, bounds_right - tile_left + 1)
			for tile_top in range(bounds_top, bounds_bottom + 1, tile_height):
				var active_tile_height = min(tile_height, bounds_bottom - tile_top + 1)
				var influence = PoolByteArray()
				influence.resize(active_tile_width * active_tile_height)
				# Godot 3 PoolByteArray.resize() leaves new bytes undefined.
				# Zero them so untouched pixels cannot inherit stale brush weight.
				for zero_index in range(influence.size()):
					influence[zero_index] = 0
				for segment in segments:
					var image_a = segment.image_a
					var image_b = segment.image_b
					var left = max(tile_left, int(floor(min(image_a.x, image_b.x) - extent_x - 0.5)))
					var top = max(tile_top, int(floor(min(image_a.y, image_b.y) - extent_y - 0.5)))
					var right = min(tile_left + active_tile_width - 1, int(ceil(max(image_a.x, image_b.x) + extent_x - 0.5)))
					var bottom = min(tile_top + active_tile_height - 1, int(ceil(max(image_a.y, image_b.y) + extent_y - 0.5)))
					if right < left or bottom < top:
						continue
					for y in range(top, bottom + 1):
						for x in range(left, right + 1):
							var pixel_index = (y * width + x) * 4 + 3
							if int(pixels[pixel_index]) == 0:
								continue
							var brush_point = pixel_to_brush.xform(Vector2(float(x) + 0.5, float(y) + 0.5))
							var distance_squared = _distance_squared_to_segment(brush_point, segment.a, segment.b)
							var erase_weight = _erase_weight(sqrt(distance_squared), radius, hardness)
							if erase_weight <= 0.0:
								continue
							var influence_index = (y - tile_top) * active_tile_width + (x - tile_left)
							influence[influence_index] = max(int(influence[influence_index]), int(round(erase_weight * 255.0)))
				for y in range(tile_top, tile_top + active_tile_height):
					for x in range(tile_left, tile_left + active_tile_width):
						var influence_index = (y - tile_top) * active_tile_width + (x - tile_left)
						var weight = float(influence[influence_index]) / 255.0
						if weight <= 0.0:
							continue
						var alpha_index = (y * width + x) * 4 + 3
						pixels[alpha_index] = int(round(float(pixels[alpha_index]) * (1.0 - weight)))

	var output = Image.new()
	output.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)
	return output


func intersects(source_image: Image, stroke: Dictionary, pixel_to_local: Transform2D) -> bool:
	if source_image == null or source_image.is_empty():
		return false
	var radius = float(stroke.get("radius", 0.0))
	if not (radius > 0.0) or radius > MAX_STROKE_COORDINATE:
		return false
	var hardness = _stroke_hardness(stroke)
	var local_points = _read_points(stroke.get("points", []))
	if local_points.empty():
		return false
	var local_to_pixel = _inverse_or_null(pixel_to_local)
	if local_to_pixel == null:
		return false

	var readable_image = source_image
	if readable_image.is_compressed() or readable_image.get_format() != Image.FORMAT_RGBA8:
		readable_image = source_image.duplicate()
		if readable_image == null or readable_image.is_empty():
			return false
		if readable_image.is_compressed() and readable_image.decompress() != OK:
			return false
		if readable_image.get_format() != Image.FORMAT_RGBA8:
			readable_image.convert(Image.FORMAT_RGBA8)
		if readable_image.is_compressed() or readable_image.get_format() != Image.FORMAT_RGBA8:
			return false

	var width = readable_image.get_width()
	var height = readable_image.get_height()
	var pixels = readable_image.get_data()
	if width <= 0 or height <= 0 or pixels.size() < width * height * 4:
		return false

	var brush_to_local = _read_radius_basis(stroke)
	if not _is_invertible(brush_to_local):
		brush_to_local = Transform2D()
	var local_to_brush = brush_to_local.affine_inverse()
	var pixel_to_brush = local_to_brush * pixel_to_local
	var brush_to_pixel = local_to_pixel * brush_to_local
	var extent_x = radius * sqrt(brush_to_pixel.x.x * brush_to_pixel.x.x + brush_to_pixel.y.x * brush_to_pixel.y.x)
	var extent_y = radius * sqrt(brush_to_pixel.x.y * brush_to_pixel.x.y + brush_to_pixel.y.y * brush_to_pixel.y.y)
	var brush_points = []
	var image_points = []
	for local_point in local_points:
		brush_points.append(local_to_brush.xform(local_point))
		image_points.append(local_to_pixel.xform(local_point))

	var segment_count = max(1, brush_points.size() - 1)
	for segment_index in range(segment_count):
		var point_a = brush_points[segment_index]
		var point_b = brush_points[segment_index + 1] if brush_points.size() > 1 else point_a
		var image_a = image_points[segment_index]
		var image_b = image_points[segment_index + 1] if image_points.size() > 1 else image_a
		var left = max(0, int(floor(min(image_a.x, image_b.x) - extent_x - 0.5)))
		var top = max(0, int(floor(min(image_a.y, image_b.y) - extent_y - 0.5)))
		var right = min(width - 1, int(ceil(max(image_a.x, image_b.x) + extent_x - 0.5)))
		var bottom = min(height - 1, int(ceil(max(image_a.y, image_b.y) + extent_y - 0.5)))
		if right < left or bottom < top:
			continue
		for y in range(top, bottom + 1):
			for x in range(left, right + 1):
				var alpha_index = (y * width + x) * 4 + 3
				if int(pixels[alpha_index]) == 0:
					continue
				var brush_point = pixel_to_brush.xform(Vector2(float(x) + 0.5, float(y) + 0.5))
				var distance_squared = _distance_squared_to_segment(brush_point, point_a, point_b)
				if _erase_weight(sqrt(distance_squared), radius, hardness) > 0.0:
					return true
	return false


func _read_points(raw_points) -> Array:
	var result = []
	if typeof(raw_points) != TYPE_ARRAY:
		return result
	for raw_point in raw_points:
		var point = _read_vector(raw_point)
		if point == null:
			continue
		if not (point.x == point.x) or not (point.y == point.y):
			continue
		if abs(point.x) > MAX_STROKE_COORDINATE or abs(point.y) > MAX_STROKE_COORDINATE:
			continue
		result.append(point)
	return result


func _read_vector(value):
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return null


func _read_radius_basis(stroke: Dictionary) -> Transform2D:
	var raw_basis = stroke.get("radius_basis", null)
	if typeof(raw_basis) != TYPE_ARRAY or raw_basis.size() < 2:
		return Transform2D()
	var x_axis = _read_vector(raw_basis[0])
	var y_axis = _read_vector(raw_basis[1])
	if x_axis == null or y_axis == null:
		return Transform2D()
	return Transform2D(x_axis, y_axis, Vector2.ZERO)


func _inverse_or_null(transform: Transform2D):
	if not _is_invertible(transform):
		return null
	return transform.affine_inverse()


func _is_invertible(transform: Transform2D) -> bool:
	var determinant = transform.x.x * transform.y.y - transform.x.y * transform.y.x
	return abs(determinant) >= MIN_DETERMINANT


func _distance_squared_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment = end - start
	var length_squared = segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_squared_to(start)
	var ratio = clamp((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_squared_to(start + segment * ratio)


func _erase_weight(distance: float, radius: float, hardness: float) -> float:
	if distance > radius:
		return 0.0
	var inner_radius = radius * clamp(hardness, 0.0, 1.0)
	if distance <= inner_radius or inner_radius >= radius:
		return 1.0
	var t = clamp((distance - inner_radius) / (radius - inner_radius), 0.0, 1.0)
	var smooth = t * t * (3.0 - 2.0 * t)
	return 1.0 - smooth


func _stroke_hardness(stroke: Dictionary) -> float:
	if not stroke.has("hardness"):
		return 1.0
	var raw_value = stroke.get("hardness")
	if typeof(raw_value) != TYPE_INT and typeof(raw_value) != TYPE_REAL:
		return 1.0
	var hardness = float(raw_value)
	if not (hardness == hardness):
		return 1.0
	return clamp(hardness, 0.0, 1.0)
