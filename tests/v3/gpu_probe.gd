extends SceneTree

const WIDTH = 8
const HEIGHT = 4
const ARTIFACT_PATH = "res://v3/artifacts/gpu_probe_%s.json"

var viewports = []
var report = {"frames": [], "driver": "unknown"}


func _init():
	call_deferred("_run")


func _run():
	var requested_driver = OS.get_environment("GPU_PROBE_DRIVER")
	report["driver"] = requested_driver
	var v_flip = OS.get_environment("GPU_PROBE_V_FLIP") == "1"
	report["render_target_v_flip"] = v_flip
	report["engine"] = Engine.get_version_info().get("string", "unknown")
	var image = Image.new()
	image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	image.lock()
	image.set_pixel(2, 1, Color(1.0, 1.0, 1.0, 0.4))
	image.set_pixel(5, 2, Color(1.0, 1.0, 1.0, 0.8))
	image.unlock()
	var source_texture = ImageTexture.new()
	source_texture.create_from_image(image, 0)
	var tiny_coverage = Image.new()
	tiny_coverage.create(1, 1, false, Image.FORMAT_RGBA8)
	tiny_coverage.fill(Color(1.0, 1.0, 1.0, 0.4))
	var resized_coverage = tiny_coverage.duplicate()
	resized_coverage.resize(2, 2, Image.INTERPOLATE_LANCZOS)
	var padded_coverage = Image.new()
	padded_coverage.create(4, 4, false, Image.FORMAT_RGBA8)
	padded_coverage.fill(Color(1.0, 1.0, 1.0, 0.0))
	padded_coverage.blit_rect(resized_coverage, Rect2(Vector2.ZERO, Vector2(2, 2)), Vector2.ONE)
	var padded_texture = ImageTexture.new()
	padded_texture.create_from_image(padded_coverage, Texture.FLAG_FILTER)

	var passthrough = _make_viewport("pass_source", source_texture, "", v_flip)
	var horizontal = _make_viewport("pass_horizontal", passthrough.get_texture(), "horizontal", v_flip)
	var vertical = _make_viewport("pass_vertical", horizontal.get_texture(), "vertical", v_flip)
	var mapped_seed = _make_viewport("mapped_seed", padded_texture, "", v_flip, 26, 2, _mapped_seed_shader())
	mapped_seed.get_child(0).material.set_shader_param("source_size", Vector2(4, 4))
	mapped_seed.get_child(0).material.set_shader_param("target_size", Vector2(26, 2))
	mapped_seed.get_child(0).material.set_shader_param("source_offset_px", Vector2(1, 1))
	viewports = [passthrough, horizontal, vertical, mapped_seed]
	var flag_methods = []
	for method_data in vertical.get_texture().get_method_list():
		if str(method_data.get("name", "")).find("flag") >= 0:
			flag_methods.append(method_data.get("name", ""))
	report["viewport_texture_flag_methods"] = flag_methods
	var flag_properties = []
	for property_data in vertical.get_texture().get_property_list():
		if str(property_data.get("name", "")).find("flag") >= 0:
			flag_properties.append(property_data.get("name", ""))
	report["viewport_texture_flag_properties"] = flag_properties
	for viewport in viewports:
		viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS

	for frame_index in range(1, 6):
		yield(self, "idle_frame")
		var snapshot = {
			"frame": frame_index,
			"source": _read_alpha(passthrough),
			"horizontal": _read_alpha(horizontal),
			"vertical": _read_alpha(vertical),
			"mapped_seed": _read_alpha_sized(mapped_seed, 26, 2)
		}
		report["frames"].append(snapshot)

	var last = report["frames"][report["frames"].size() - 1]
	var vertical_grid = last["vertical"]
	var sum = 0.0
	var nonzero = 0
	for value in vertical_grid:
		if value > 0.02:
			sum += value
			nonzero += 1
	report["final_nonzero_pixels"] = nonzero
	report["final_alpha_sum"] = sum
	report["expected_alpha_sum"] = 10.8
	var ready_frame_index = -1
	for frame_offset in range(report["frames"].size()):
		if _frame_is_ready(report["frames"][frame_offset]):
			ready_frame_index = frame_offset + 1
			break
	report["ready_frame_index"] = ready_frame_index
	report["ready_by_second_frame"] = ready_frame_index > 0 and ready_frame_index <= 2
	report["stable_after_warmup"] = last["vertical"] == report["frames"][1]["vertical"]
	report["mapped_seed_first_pixels"] = [last["mapped_seed"][0], last["mapped_seed"][1], last["mapped_seed"][26], last["mapped_seed"][27]]
	var result_path = ARTIFACT_PATH % requested_driver.to_lower()
	var file = File.new()
	var open_error = file.open(result_path, File.WRITE)
	if open_error == OK:
		file.store_string(JSON.print(report, "\t"))
		file.close()
	print("GPU_PROBE_JSON=" + JSON.print(report))
	quit(0 if report["ready_by_second_frame"] and report["stable_after_warmup"] else 1)


func _frame_is_ready(frame_data):
	var source_values = frame_data["source"]
	var horizontal = frame_data["horizontal"]
	var vertical = frame_data["vertical"]
	return (
		abs(source_values[_index(2, 1)] - 0.4) < 0.08
		and abs(source_values[_index(5, 2)] - 0.8) < 0.08
		and abs(horizontal[_index(1, 1)] - 0.4) < 0.08
		and abs(horizontal[_index(3, 1)] - 0.4) < 0.08
		and abs(vertical[_index(2, 0)] - 0.4) < 0.08
		and abs(vertical[_index(2, 2)] - 0.4) < 0.08
		and vertical[_index(0, 0)] < 0.02
		and vertical[_index(7, 3)] < 0.02
	)


func _index(x, y):
	return y * WIDTH + x


func _make_viewport(node_name, input_texture, pass_kind, v_flip, width = WIDTH, height = HEIGHT, shader_override = ""):
	var viewport = Viewport.new()
	viewport.name = node_name
	viewport.size = Vector2(width, height)
	viewport.own_world_2d = true
	viewport.transparent_bg = true
	viewport.render_target_v_flip = v_flip
	viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS
	get_root().add_child(viewport)
	var rect = ColorRect.new()
	rect.rect_size = Vector2(width, height)
	var material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = shader_override if shader_override != "" else _shader_code(pass_kind)
	material.shader = shader
	material.set_shader_param("source_tex", input_texture)
	material.set_shader_param("texel_size", Vector2(1.0 / width, 1.0 / height))
	rect.material = material
	viewport.add_child(rect)
	return viewport


func _shader_code(pass_kind):
	var radius_expr = "vec2(0.0, 0.0)"
	if pass_kind == "horizontal":
		radius_expr = "vec2(texel_size.x, 0.0)"
	elif pass_kind == "vertical":
		radius_expr = "vec2(0.0, texel_size.y)"
	return """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D source_tex;
uniform vec2 texel_size;
void fragment() {
    vec2 radius = %s;
    float a = texture(source_tex, UV).a;
    if (radius.x > 0.0) {
        a = max(a, texture(source_tex, UV - radius).a);
        a = max(a, texture(source_tex, UV + radius).a);
    }
    if (radius.y > 0.0) {
        a = max(a, texture(source_tex, UV - radius).a);
        a = max(a, texture(source_tex, UV + radius).a);
    }
    COLOR = vec4(1.0, 1.0, 1.0, a);
}
""" % radius_expr


func _read_alpha(viewport):
	return _read_alpha_sized(viewport, WIDTH, HEIGHT)


func _read_alpha_sized(viewport, width, height):
	var texture = viewport.get_texture()
	var image = texture.get_data()
	var values = []
	if image == null:
		for _i in range(width * height):
			values.append(0.0)
		return values
	image.lock()
	for y in range(height):
		for x in range(width):
			values.append(image.get_pixel(x, y).a)
	image.unlock()
	return values


func _mapped_seed_shader():
	return """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D source_tex;
uniform vec2 source_size;
uniform vec2 target_size;
uniform vec2 source_offset_px;
void fragment() {
    vec2 source_uv = (UV * target_size + source_offset_px) / source_size;
    float alpha = 0.0;
    if (source_uv.x >= 0.0 && source_uv.y >= 0.0 && source_uv.x <= 1.0 && source_uv.y <= 1.0) {
        alpha = texture(source_tex, source_uv).a;
    }
    COLOR = vec4(1.0, 1.0, 1.0, alpha);
}
"""
