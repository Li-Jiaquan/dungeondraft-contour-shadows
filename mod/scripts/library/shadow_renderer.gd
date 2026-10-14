extends Reference

var script_class = "reference"

const MAX_OUTPUT_DIMENSION = 1024
const SUPERSAMPLE = 2
# Synchronous fallback budget only. GPU work is reported separately as the sum
# of raster samples processed by each planned viewport pass.
const CPU_FALLBACK_WORK_LIMIT = 250000

var _gpu_shader_cache = {}
var _cpu_fallback_script = null


func start():
	pass


func get_work_limit() -> int:
	return CPU_FALLBACK_WORK_LIMIT


func render(source: Image, displacement: Vector2, blur_radius: float = 8.0, mode: String = "sweep", alpha_cutoff: float = 0.02, max_size: int = 384) -> Dictionary:
	var started_usec = OS.get_ticks_usec()
	var fallback_script = _get_cpu_fallback_script()
	if fallback_script == null:
		return _failure("Synchronous CPU fallback script could not be loaded.")
	var fallback = fallback_script.new().render(source, displacement, blur_radius, mode, alpha_cutoff, min(max_size, 384))
	if typeof(fallback) == TYPE_DICTIONARY and bool(fallback.get("ok", false)):
		fallback["backend"] = "cpu_fallback"
		fallback["elapsed_ms"] = _elapsed_ms(started_usec)
		fallback["diagnostic"] = "Synchronous CPU fallback capped at 384 pixels; pixel_scale reports any downsampling."
	return fallback


func _get_cpu_fallback_script():
	if _cpu_fallback_script != null:
		return _cpu_fallback_script
	var script = get_script()
	if script == null or script.resource_path == "":
		return null
	var fallback_path = script.resource_path.get_base_dir().plus_file("shadow_renderer_cpu_fallback.gd")
	_cpu_fallback_script = ResourceLoader.load(fallback_path, "", true)
	return _cpu_fallback_script


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _estimate_gpu_work(internal_width: int, internal_height: int, output_width: int, output_height: int, displacement: Vector2, scaled_blur: float, mode: String) -> Dictionary:
	# Match render_async's pass schedule exactly: one seed, geometric-doubling
	# max passes, an optional native-size downsample, then two blur passes.
	var internal_area = internal_width * internal_height
	var samples = internal_area
	var passes = 1
	if mode == "sweep":
		var displacement_internal = displacement * float(SUPERSAMPLE)
		var total_length = displacement_internal.length()
		var reach = 0.0
		while reach < total_length - 0.00001:
			var step_length = min(1.0, total_length) if reach <= 0.00001 else min(reach, total_length - reach)
			reach += step_length
			samples += internal_area
			passes += 1
	var downsampled = output_width > 1 and output_height > 1
	if downsampled:
		samples += output_width * output_height
		passes += 1
	var blur_width = output_width if downsampled else internal_width
	var blur_height = output_height if downsampled else internal_height
	var output_blur = scaled_blur if downsampled else scaled_blur * float(SUPERSAMPLE)
	if output_blur > 0.0001:
		samples += 2 * blur_width * blur_height
		passes += 2
	return {"work_samples": samples, "render_passes": passes}


func _make_rgba_image(width: int, height: int, alpha: PoolByteArray) -> Image:
	var pixel_count = width * height
	var rgba = PoolByteArray()
	rgba.resize(pixel_count * 4)
	for i in range(pixel_count):
		var base = i * 4
		rgba[base] = 255
		rgba[base + 1] = 255
		rgba[base + 2] = 255
		rgba[base + 3] = int(alpha[i]) if alpha.size() > i else 0
	var image = Image.new()
	image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)
	return image


# Async production path. Each viewport pass propagates the alpha maximum over a
# doubled directional interval. Only the last viewport is read back to the CPU.
func render_async(source: Image, displacement: Vector2, blur_radius: float = 8.0, mode: String = "sweep", alpha_cutoff: float = 0.02, max_size: int = 384, owner_node: Node = null) -> Dictionary:
	var started_usec = OS.get_ticks_usec()
	# Keep the method awaitable even for validation failures before a Viewport can
	# be created. The host can always yield(render_async(...), "completed").
	var startup_loop = Engine.get_main_loop()
	if startup_loop != null and startup_loop.has_signal("idle_frame"):
		yield(startup_loop, "idle_frame")
	if source == null or source.is_empty():
		return _gpu_failure("Source image is empty.", started_usec)
	if mode != "offset" and mode != "sweep":
		return _gpu_failure("Mode must be 'offset' or 'sweep'.", started_usec)
	if max_size < 1:
		return _gpu_failure("max_size must be at least 1.", started_usec)
	if abs(displacement.x) > 10000000.0 or abs(displacement.y) > 10000000.0:
		return _gpu_failure("Displacement exceeds the safe image-coordinate limit.", started_usec)
	if blur_radius < 0.0 or blur_radius > 10000000.0:
		return _gpu_failure("blur_radius must be between 0 and 10000000.", started_usec)
	if owner_node == null or not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
		return _gpu_failure("GPU render requires an owner node inside the active SceneTree.", started_usec)
	var scene_tree = owner_node.get_tree()
	if scene_tree == null:
		return _gpu_failure("GPU render could not find the owner's SceneTree.", started_usec)

	var plan = _make_gpu_plan(source, displacement, blur_radius, mode, alpha_cutoff, max_size)
	if not bool(plan.get("ok", false)):
		return _gpu_failure(str(plan.get("error", "Could not prepare the render.")), started_usec)
	if bool(plan.get("empty", false)):
		var empty_result = {
			"ok": true,
			"image": _make_rgba_image(1, 1, PoolByteArray()),
			"offset": plan["source_origin"],
			"pixel_scale": plan["scale"],
			"source_size": plan["source_size"],
			"work_samples": 0,
			"backend": "gpu_viewport",
			"elapsed_ms": _elapsed_ms(started_usec),
			"render_passes": 0,
			"estimated_render_passes": 0
		}
		return empty_result

	var stage_root = Node.new()
	stage_root.name = "ContourShadowGpuRender"
	stage_root.pause_mode = Node.PAUSE_MODE_PROCESS
	owner_node.add_child(stage_root)
	var source_viewport = _make_gpu_viewport(stage_root, "coverage", plan["internal_width"], plan["internal_height"], plan["source_texture"], _gpu_seed_shader())
	var gpu_passes = [source_viewport]
	var source_material = source_viewport.get_child(0).material
	source_material.set_shader_param("target_size", Vector2(plan["internal_width"], plan["internal_height"]))
	source_material.set_shader_param("source_size", Vector2(plan["padded_source_width"], plan["padded_source_height"]))
	source_material.set_shader_param("source_offset_px", plan["source_offset_px"])
	source_material.set_shader_param("alpha_cutoff", plan["alpha_cutoff"])
	var current_viewport = source_viewport
	var render_passes = 1

	if mode == "sweep":
		var displacement_internal = plan["scaled_displacement"] * float(SUPERSAMPLE)
		var reach = 0.0
		var total_length = displacement_internal.length()
		var direction = displacement_internal.normalized() if total_length > 0.000001 else Vector2.ZERO
		while reach < total_length - 0.00001:
			var step_length = min(1.0, total_length) if reach <= 0.00001 else min(reach, total_length - reach)
			var step_vector = direction * step_length
			var step_uv = Vector2(step_vector.x / float(plan["internal_width"]), step_vector.y / float(plan["internal_height"]))
			current_viewport = _make_gpu_viewport(stage_root, "sweep_%02d" % render_passes, plan["internal_width"], plan["internal_height"], current_viewport.get_texture(), _gpu_max_shader())
			gpu_passes.append(current_viewport)
			current_viewport.get_child(0).material.set_shader_param("step_uv", step_uv)
			render_passes += 1
			reach += step_length
			if render_passes > 32:
				current_viewport = null
				source_viewport = null
				plan["source_texture"] = null
				source_material = null
				yield(_release_gpu_stage(scene_tree, stage_root), "completed")
				return _gpu_failure("GPU sweep exceeded its bounded pass count.", started_usec)

	var gpu_downsampled = false
	if plan["output_width"] > 1 and plan["output_height"] > 1:
		current_viewport = _make_gpu_viewport(stage_root, "coverage_downsample", plan["output_width"], plan["output_height"], current_viewport.get_texture(), _gpu_resample_shader())
		gpu_passes.append(current_viewport)
		current_viewport.get_child(0).material.set_shader_param("target_size", Vector2(plan["output_width"], plan["output_height"]))
		render_passes += 1
		gpu_downsampled = true
	var blur_surface_width = plan["output_width"] if gpu_downsampled else plan["internal_width"]
	var blur_surface_height = plan["output_height"] if gpu_downsampled else plan["internal_height"]
	var output_blur = plan["scaled_blur"] if gpu_downsampled else plan["scaled_blur"] * float(SUPERSAMPLE)
	if output_blur > 0.0001:
		var horizontal_step = Vector2(1.0 / float(blur_surface_width), 0.0)
		current_viewport = _make_gpu_viewport(stage_root, "blur_horizontal", blur_surface_width, blur_surface_height, current_viewport.get_texture(), _gpu_blur_shader())
		gpu_passes.append(current_viewport)
		current_viewport.get_child(0).material.set_shader_param("sample_step_uv", horizontal_step)
		current_viewport.get_child(0).material.set_shader_param("sigma", output_blur)
		render_passes += 1
		var vertical_step = Vector2(0.0, 1.0 / float(blur_surface_height))
		current_viewport = _make_gpu_viewport(stage_root, "blur_vertical", blur_surface_width, blur_surface_height, current_viewport.get_texture(), _gpu_blur_shader())
		gpu_passes.append(current_viewport)
		current_viewport.get_child(0).material.set_shader_param("sample_step_uv", vertical_step)
		current_viewport.get_child(0).material.set_shader_param("sigma", output_blur)
		render_passes += 1

	for gpu_viewport in gpu_passes:
		gpu_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS

	# In Godot 3.4 the first frame after dynamic Viewport creation is blank. The
	# second frame carries the full ordered dependency chain on GLES2 and GLES3.
	for frame_index in range(2):
		yield(scene_tree, "idle_frame")
		if not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
			current_viewport = null
			source_viewport = null
			plan["source_texture"] = null
			source_material = null
			yield(_release_gpu_stage(scene_tree, stage_root), "completed")
			return _gpu_failure("Render owner left the tree before GPU readback completed.", started_usec)
	var final_texture = current_viewport.get_texture()
	var readback = final_texture.get_data()
	if readback == null or readback.is_empty():
		final_texture = null
		readback = null
		current_viewport = null
		source_viewport = null
		plan["source_texture"] = null
		source_material = null
		yield(_release_gpu_stage(scene_tree, stage_root), "completed")
		return _gpu_failure("GPU Viewport readback returned no image.", started_usec)
	if readback.is_compressed():
		var decompress_error = readback.decompress()
		if decompress_error != OK:
			final_texture = null
			readback = null
			current_viewport = null
			source_viewport = null
			plan["source_texture"] = null
			source_material = null
			yield(_release_gpu_stage(scene_tree, stage_root), "completed")
			return _gpu_failure("Could not decompress the GPU result (error %d)." % decompress_error, started_usec)
	if readback.get_format() != Image.FORMAT_RGBA8:
		readback.convert(Image.FORMAT_RGBA8)
	if not gpu_downsampled:
		readback.resize(plan["output_width"], plan["output_height"], Image.INTERPOLATE_LANCZOS)
	var has_output_alpha = readback.get_used_rect().size.x > 0.0 and readback.get_used_rect().size.y > 0.0
	var output_image = readback
	final_texture = null
	readback = null
	current_viewport = null
	source_viewport = null
	plan["source_texture"] = null
	source_material = null
	yield(_release_gpu_stage(scene_tree, stage_root), "completed")
	if not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
		return _gpu_failure("Render owner left the tree before GPU resources were released.", started_usec)

	# A zero-alpha frame while the preprocessed input is visible indicates that
	# this host could not execute the embedded shaders. Keep the CPU renderer as an
	# explicit functional fallback and expose it in diagnostics.
	if not has_output_alpha and bool(plan["has_visible_alpha"]):
		var fallback = render(source, displacement, blur_radius, mode, alpha_cutoff, max_size)
		fallback["backend"] = "cpu_fallback"
		fallback["elapsed_ms"] = _elapsed_ms(started_usec)
		fallback["render_passes"] = render_passes
		fallback["diagnostic"] = "GPU returned an empty frame; synchronous CPU fallback was used."
		return fallback

	return {
		"ok": true,
		"image": output_image,
		"offset": plan["source_origin"] + Vector2(float(plan["left"]) * plan["scale"], float(plan["top"]) * plan["scale"]),
		"pixel_scale": plan["scale"],
		"source_size": plan["source_size"],
		"work_samples": plan["work_samples"],
		"backend": "gpu_viewport",
		"elapsed_ms": _elapsed_ms(started_usec),
		"render_passes": render_passes,
		"estimated_render_passes": plan["estimated_render_passes"],
		"render_frames_waited": 2
	}


func _make_gpu_plan(source: Image, displacement: Vector2, blur_radius: float, mode: String, alpha_cutoff: float, max_size: int) -> Dictionary:
	var original_width = source.get_width()
	var original_height = source.get_height()
	if original_width < 1 or original_height < 1:
		return {"ok": false, "error": "Source image has invalid dimensions."}
	var rgba_image = source.duplicate()
	if rgba_image.is_compressed():
		var decompress_error = rgba_image.decompress()
		if decompress_error != OK:
			return {"ok": false, "error": "Could not decompress source image (error %d)." % decompress_error}
	if rgba_image.get_format() != Image.FORMAT_RGBA8:
		rgba_image.convert(Image.FORMAT_RGBA8)
	if rgba_image.is_compressed() or rgba_image.get_format() != Image.FORMAT_RGBA8:
		return {"ok": false, "error": "Source image could not be converted to RGBA8."}
	var source_origin = Vector2.ZERO
	var used_rect = rgba_image.get_used_rect()
	if used_rect.size.x <= 0.0 or used_rect.size.y <= 0.0:
		return {"ok": true, "empty": true, "source_origin": Vector2.ZERO, "scale": 1.0, "source_size": Vector2(original_width, original_height)}
	source_origin = used_rect.position
	if used_rect.position.x != 0.0 or used_rect.position.y != 0.0 or used_rect.size.x != float(original_width) or used_rect.size.y != float(original_height):
		rgba_image = rgba_image.get_rect(used_rect)
		if rgba_image == null or rgba_image.is_empty():
			return {"ok": false, "error": "Could not crop transparent source-image padding."}
	var source_width = rgba_image.get_width()
	var source_height = rgba_image.get_height()
	var output_limit = min(max_size, MAX_OUTPUT_DIMENSION)
	var scale = 1.0
	var dimensions = {}
	for _iteration in range(24):
		dimensions = _gpu_dimensions(source_width, source_height, displacement, blur_radius, mode, scale)
		var dimension_ratio = max(float(dimensions["output_width"]), float(dimensions["output_height"])) / float(output_limit)
		if dimension_ratio <= 1.0:
			break
		scale *= dimension_ratio * 1.002
	dimensions = _gpu_dimensions(source_width, source_height, displacement, blur_radius, mode, scale)
	if dimensions["output_width"] > output_limit or dimensions["output_height"] > output_limit:
		return {"ok": false, "error": "Could not fit the output inside max_size safely."}
	var output_width = int(dimensions["output_width"])
	var output_height = int(dimensions["output_height"])
	var internal_width = output_width * SUPERSAMPLE
	var internal_height = output_height * SUPERSAMPLE
	var internal_source_width = max(1, int(ceil(float(source_width) / scale))) * SUPERSAMPLE
	var internal_source_height = max(1, int(ceil(float(source_height) / scale))) * SUPERSAMPLE
	var coverage_image = rgba_image.duplicate()
	coverage_image.resize(internal_source_width, internal_source_height, Image.INTERPOLATE_LANCZOS)
	var coverage_bytes = coverage_image.get_data()
	if coverage_bytes.size() < internal_source_width * internal_source_height * 4:
		return {"ok": false, "error": "Resampled source coverage is incomplete."}
	var alpha_threshold = int(ceil(clamp(alpha_cutoff, 0.0, 1.0) * 255.0))
	var has_visible_alpha = false
	for byte_index in range(3, coverage_bytes.size(), 4):
		if int(coverage_bytes[byte_index]) >= alpha_threshold:
			has_visible_alpha = true
			break
	if not has_visible_alpha:
		return {"ok": true, "empty": true, "source_origin": source_origin, "scale": scale, "source_size": Vector2(original_width, original_height)}
	var padded_width = internal_source_width + 2
	var padded_height = internal_source_height + 2
	var padded_image = Image.new()
	padded_image.create(padded_width, padded_height, false, Image.FORMAT_RGBA8)
	padded_image.fill(Color(1.0, 1.0, 1.0, 0.0))
	padded_image.blit_rect(coverage_image, Rect2(Vector2.ZERO, Vector2(internal_source_width, internal_source_height)), Vector2.ONE)
	var source_texture = ImageTexture.new()
	source_texture.create_from_image(padded_image, Texture.FLAG_FILTER)
	var source_offset_px = Vector2(float(dimensions["left"] * SUPERSAMPLE), float(dimensions["top"] * SUPERSAMPLE))
	if mode == "offset":
		source_offset_px -= dimensions["scaled_displacement"] * float(SUPERSAMPLE)
	source_offset_px += Vector2.ONE
	var work_estimate = _estimate_gpu_work(internal_width, internal_height, output_width, output_height, dimensions["scaled_displacement"], dimensions["scaled_blur"], mode)
	return {
		"ok": true,
		"empty": false,
		"source_texture": source_texture,
		"source_origin": source_origin,
		"source_size": Vector2(original_width, original_height),
		"scale": scale,
		"left": dimensions["left"],
		"top": dimensions["top"],
		"output_width": output_width,
		"output_height": output_height,
		"internal_width": internal_width,
		"internal_height": internal_height,
		"padded_source_width": padded_width,
		"padded_source_height": padded_height,
		"source_offset_px": source_offset_px,
		"scaled_displacement": dimensions["scaled_displacement"],
		"scaled_blur": dimensions["scaled_blur"],
		"alpha_cutoff": float(alpha_threshold) / 255.0,
		"has_visible_alpha": has_visible_alpha,
		# work_samples counts shader raster samples (one pixel per pass), not CPU
		# preprocessing or readback work. This is independent of source sparsity.
		"work_samples": work_estimate["work_samples"],
		"estimated_render_passes": work_estimate["render_passes"]
	}


func _gpu_dimensions(source_width: int, source_height: int, displacement: Vector2, blur_radius: float, mode: String, scale: float) -> Dictionary:
	var scaled_width = max(1, int(ceil(float(source_width) / scale)))
	var scaled_height = max(1, int(ceil(float(source_height) / scale)))
	var scaled_displacement = displacement / scale
	var scaled_blur = blur_radius / scale
	var blur_padding = int(ceil(scaled_blur * 3.0))
	var bounds_min_x = scaled_displacement.x if mode == "offset" else min(0.0, scaled_displacement.x)
	var bounds_min_y = scaled_displacement.y if mode == "offset" else min(0.0, scaled_displacement.y)
	var bounds_max_x = scaled_displacement.x if mode == "offset" else max(0.0, scaled_displacement.x)
	var bounds_max_y = scaled_displacement.y if mode == "offset" else max(0.0, scaled_displacement.y)
	var left = int(floor(bounds_min_x)) - blur_padding
	var top = int(floor(bounds_min_y)) - blur_padding
	var right = int(ceil(bounds_max_x + scaled_width)) + blur_padding
	var bottom = int(ceil(bounds_max_y + scaled_height)) + blur_padding
	return {
		"left": left,
		"top": top,
		"output_width": max(1, right - left),
		"output_height": max(1, bottom - top),
		"scaled_displacement": scaled_displacement,
		"scaled_blur": scaled_blur
	}


func _make_gpu_viewport(parent: Node, viewport_name: String, width: int, height: int, source_texture: Texture, shader_code: String) -> Viewport:
	var viewport = Viewport.new()
	viewport.name = viewport_name
	viewport.size = Vector2(width, height)
	viewport.own_world_2d = true
	viewport.transparent_bg = true
	viewport.render_target_v_flip = true
	viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS
	# Finish binding the ColorRect and uniforms before the viewport renders once.
	viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
	parent.add_child(viewport)
	var rect = ColorRect.new()
	rect.name = "ShaderPass"
	rect.rect_size = Vector2(width, height)
	var cache_key = shader_code
	var shader = _gpu_shader_cache.get(cache_key, null)
	if shader == null:
		shader = Shader.new()
		shader.code = shader_code
		_gpu_shader_cache[cache_key] = shader
	var material = ShaderMaterial.new()
	material.shader = shader
	if source_texture != null:
		if source_texture.has_method("set_flags"):
			source_texture.set_flags(Texture.FLAG_FILTER)
		material.set_shader_param("source_tex", source_texture)
	rect.material = material
	viewport.add_child(rect)
	return viewport


func _gpu_seed_shader() -> String:
	return """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D source_tex;
uniform vec2 target_size;
uniform vec2 source_size;
uniform vec2 source_offset_px;
uniform float alpha_cutoff;
void fragment() {
	vec2 source_uv = (UV * target_size + source_offset_px) / source_size;
	float alpha = 0.0;
	if (source_uv.x >= 0.0 && source_uv.y >= 0.0 && source_uv.x <= 1.0 && source_uv.y <= 1.0) {
		alpha = texture(source_tex, source_uv).a;
	}
	if (alpha < alpha_cutoff) {
		alpha = 0.0;
	}
	COLOR = vec4(1.0, 1.0, 1.0, alpha);
}
"""


func _gpu_max_shader() -> String:
	return """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D source_tex;
uniform vec2 step_uv;
float alpha_at(vec2 at_uv) {
	if (at_uv.x < 0.0 || at_uv.y < 0.0 || at_uv.x > 1.0 || at_uv.y > 1.0) {
		return 0.0;
	}
	return texture(source_tex, at_uv).a;
}
void fragment() {
	float alpha = max(alpha_at(UV), alpha_at(UV - step_uv));
	COLOR = vec4(1.0, 1.0, 1.0, alpha);
}
"""


func _gpu_blur_shader() -> String:
	return """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D source_tex;
uniform vec2 sample_step_uv;
uniform float sigma;
float alpha_at(vec2 at_uv) {
	if (at_uv.x < 0.0 || at_uv.y < 0.0 || at_uv.x > 1.0 || at_uv.y > 1.0) {
		return 0.0;
	}
	return texture(source_tex, at_uv).a;
}
void fragment() {
	float radius = min(ceil(3.0 * sigma), 192.0);
	float center_weight = 1.0;
	float alpha_total = alpha_at(UV) * center_weight;
	float weight_total = center_weight;
	for (int pair_index = 1; pair_index <= 96; pair_index++) {
		float first_distance = float(pair_index * 2 - 1);
		if (first_distance > radius) {
			break;
		}
		float second_distance = first_distance + 1.0;
		float first_weight = exp(-0.5 * first_distance * first_distance / (sigma * sigma));
		float second_weight = 0.0;
		if (second_distance <= radius) {
			second_weight = exp(-0.5 * second_distance * second_distance / (sigma * sigma));
		}
		float pair_weight = first_weight + second_weight;
		float pair_offset = first_distance + second_weight / max(pair_weight, 0.000001);
		alpha_total += (alpha_at(UV + sample_step_uv * pair_offset) + alpha_at(UV - sample_step_uv * pair_offset)) * pair_weight;
		weight_total += 2.0 * pair_weight;
	}
	float alpha = alpha_total / max(weight_total, 0.0001);
	COLOR = vec4(1.0, 1.0, 1.0, alpha);
}
"""


func _gpu_resample_shader() -> String:
	return """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D source_tex;
uniform vec2 target_size;
void fragment() {
	vec2 target_uv = FRAGCOORD.xy / target_size;
	float alpha = texture(source_tex, target_uv).a;
	COLOR = vec4(1.0, 1.0, 1.0, alpha);
}
"""


func _gpu_failure(message: String, started_usec: int) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"backend": "gpu_viewport",
		"elapsed_ms": _elapsed_ms(started_usec)
	}


func _elapsed_ms(started_usec: int) -> float:
	return float(OS.get_ticks_usec() - started_usec) / 1000.0


func _release_gpu_stage(scene_tree: SceneTree, stage_root: Node) -> bool:
	if is_instance_valid(stage_root):
		for child in stage_root.get_children():
			if child is Viewport:
				child.render_target_update_mode = Viewport.UPDATE_DISABLED
		stage_root.queue_free()
	if VisualServer.has_signal("frame_post_draw"):
		yield(VisualServer, "frame_post_draw")
	else:
		yield(scene_tree, "idle_frame")
	return true
