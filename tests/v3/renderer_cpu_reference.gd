extends Reference

var script_class = "reference"

const MAX_OUTPUT_DIMENSION = 1024
const SUPERSAMPLE = 2
# Work is counted in internal raster samples touched by the directional sweep.
# The cap is independent of sweep length; long sweeps use a sliding maximum.
const MAX_RENDER_WORK = 8388608



func start():
	pass


func get_work_limit() -> int:
	return MAX_RENDER_WORK


func render(source: Image, displacement: Vector2, blur_radius: float = 8.0, mode: String = "sweep", alpha_cutoff: float = 0.02, max_size: int = 384) -> Dictionary:
	if source == null or source.is_empty():
		return _failure("Source image is empty.")
	if mode != "offset" and mode != "sweep":
		return _failure("Mode must be 'offset' or 'sweep'.")
	if max_size < 1:
		return _failure("max_size must be at least 1.")
	if abs(displacement.x) > 10000000.0 or abs(displacement.y) > 10000000.0:
		return _failure("Displacement exceeds the safe image-coordinate limit.")
	if blur_radius < 0.0 or blur_radius > 10000000.0:
		return _failure("blur_radius must be between 0 and 10000000.")

	var original_width = source.get_width()
	var original_height = source.get_height()
	if original_width < 1 or original_height < 1:
		return _failure("Source image has invalid dimensions.")

	# Work on a private image copy. Texture and host-owned Image resources stay untouched.
	var rgba_image = source.duplicate()
	if rgba_image.is_compressed():
		var decompress_error = rgba_image.decompress()
		if decompress_error != OK:
			return _failure("Could not decompress source image (error %d)." % decompress_error)
	if rgba_image.get_format() != Image.FORMAT_RGBA8:
		rgba_image.convert(Image.FORMAT_RGBA8)
	if rgba_image.is_compressed() or rgba_image.get_format() != Image.FORMAT_RGBA8:
		return _failure("Source image could not be converted to RGBA8.")

	# Crop only fully transparent outer padding. This keeps sparse, padded textures
	# detailed and restores the crop origin in the returned Sprite-local offset.
	var source_origin = Vector2.ZERO
	var used_rect: Rect2 = rgba_image.get_used_rect()
	if used_rect.size.x <= 0.0 or used_rect.size.y <= 0.0:
		var transparent_image = _make_rgba_image(1, 1, PoolByteArray())
		return {
			"ok": true,
			"image": transparent_image,
			"offset": Vector2.ZERO,
			"pixel_scale": 1.0,
			"source_size": Vector2(original_width, original_height)
		}
	source_origin = used_rect.position
	if used_rect.position.x != 0.0 or used_rect.position.y != 0.0 or used_rect.size.x != float(original_width) or used_rect.size.y != float(original_height):
		rgba_image = rgba_image.get_rect(used_rect)
		if rgba_image == null or rgba_image.is_empty():
			return _failure("Could not crop transparent source-image padding.")
	var source_width = rgba_image.get_width()
	var source_height = rgba_image.get_height()

	var output_limit = min(max_size, MAX_OUTPUT_DIMENSION)
	var scale = 1.0
	var scaled_width = 1
	var scaled_height = 1
	var scaled_displacement = Vector2.ZERO
	var scaled_blur = 0.0
	var blur_padding = 0
	var left = 0
	var top = 0
	var right = 0
	var bottom = 0
	var output_width = 1
	var output_height = 1
	var estimated_work = 1

	# Fit the output and the linear-time directional raster work. Sweep length no
	# longer multiplies every source pixel; only the output surface and scan rows
	# contribute to the work estimate.
	for iteration in range(24):
		scaled_width = max(1, int(ceil(float(source_width) / scale)))
		scaled_height = max(1, int(ceil(float(source_height) / scale)))
		scaled_displacement = displacement / scale
		scaled_blur = blur_radius / scale
		blur_padding = int(ceil(scaled_blur * 3.0))
		var bounds_min_x = scaled_displacement.x if mode == "offset" else min(0.0, scaled_displacement.x)
		var bounds_min_y = scaled_displacement.y if mode == "offset" else min(0.0, scaled_displacement.y)
		var bounds_max_x = scaled_displacement.x if mode == "offset" else max(0.0, scaled_displacement.x)
		var bounds_max_y = scaled_displacement.y if mode == "offset" else max(0.0, scaled_displacement.y)
		left = int(floor(bounds_min_x)) - blur_padding
		top = int(floor(bounds_min_y)) - blur_padding
		right = int(ceil(bounds_max_x + scaled_width)) + blur_padding
		bottom = int(ceil(bounds_max_y + scaled_height)) + blur_padding
		output_width = max(1, right - left)
		output_height = max(1, bottom - top)
		var dimension_ratio = max(float(output_width), float(output_height)) / float(output_limit)
		estimated_work = _estimate_work(scaled_width, scaled_height, scaled_displacement, output_width, output_height, mode)
		var work_ratio = float(estimated_work) / float(MAX_RENDER_WORK)
		if dimension_ratio <= 1.0 and work_ratio <= 1.0:
			break
		var dimension_scale = dimension_ratio * 1.002 if dimension_ratio > 1.0 else 1.0
		var work_scale = sqrt(work_ratio) * 1.01 if work_ratio > 1.0 else 1.0
		scale *= max(dimension_scale, work_scale)

	# Recalculate after the bounded solve and enforce exact final bounds.
	scaled_width = max(1, int(ceil(float(source_width) / scale)))
	scaled_height = max(1, int(ceil(float(source_height) / scale)))
	scaled_displacement = displacement / scale
	scaled_blur = blur_radius / scale
	blur_padding = int(ceil(scaled_blur * 3.0))
	var final_bounds_min_x = scaled_displacement.x if mode == "offset" else min(0.0, scaled_displacement.x)
	var final_bounds_min_y = scaled_displacement.y if mode == "offset" else min(0.0, scaled_displacement.y)
	var final_bounds_max_x = scaled_displacement.x if mode == "offset" else max(0.0, scaled_displacement.x)
	var final_bounds_max_y = scaled_displacement.y if mode == "offset" else max(0.0, scaled_displacement.y)
	left = int(floor(final_bounds_min_x)) - blur_padding
	top = int(floor(final_bounds_min_y)) - blur_padding
	right = int(ceil(final_bounds_max_x + scaled_width)) + blur_padding
	bottom = int(ceil(final_bounds_max_y + scaled_height)) + blur_padding
	output_width = max(1, right - left)
	output_height = max(1, bottom - top)
	if output_width > output_limit or output_height > output_limit:
		return _failure("Could not fit the output inside max_size safely.")
	estimated_work = _estimate_work(scaled_width, scaled_height, scaled_displacement, output_width, output_height, mode)
	if estimated_work > MAX_RENDER_WORK * 1.05:
		return _failure("Render exceeded the bounded sample budget.")

	var internal_width = output_width * SUPERSAMPLE
	var internal_height = output_height * SUPERSAMPLE
	var internal_source_width = scaled_width * SUPERSAMPLE
	var internal_source_height = scaled_height * SUPERSAMPLE
	if internal_width < 1 or internal_height < 1 or internal_source_width < 1 or internal_source_height < 1:
		return _failure("Render dimensions are invalid.")

	# Lanczos coverage resampling retains thin alpha details as fractional coverage
	# instead of expanding every coarse source pixel into an opaque square.
	var coverage_image = rgba_image.duplicate()
	coverage_image.resize(internal_source_width, internal_source_height, Image.INTERPOLATE_LANCZOS)
	if coverage_image.get_width() != internal_source_width or coverage_image.get_height() != internal_source_height:
		return _failure("Could not resample the source coverage image.")
	var rgba_data = coverage_image.get_data()
	if rgba_data.size() < internal_source_width * internal_source_height * 4:
		return _failure("Resampled source data is incomplete.")
	var source_alpha = PoolByteArray()
	source_alpha.resize(internal_source_width * internal_source_height)
	var alpha_threshold = int(ceil(clamp(alpha_cutoff, 0.0, 1.0) * 255.0))
	var has_visible_alpha = false
	for i in range(source_alpha.size()):
		var alpha_value = int(clamp(round(float(rgba_data[i * 4 + 3])), 0.0, 255.0))
		if alpha_value < alpha_threshold:
			alpha_value = 0
		else:
			has_visible_alpha = true
		source_alpha[i] = alpha_value

	if not has_visible_alpha:
		var empty_image = _make_rgba_image(1, 1, PoolByteArray())
		return {
			"ok": true,
			"image": empty_image,
			"offset": source_origin,
			"pixel_scale": scale,
			"source_size": Vector2(original_width, original_height)
		}

	var output_alpha = PoolByteArray()
	if mode == "sweep":
		output_alpha = _render_sweep(source_alpha, internal_source_width, internal_source_height, scaled_displacement, left, top, output_width, output_height)
	else:
		output_alpha = _render_offset(source_alpha, internal_source_width, internal_source_height, scaled_displacement, left, top, output_width, output_height)

	var internal_blur = scaled_blur * float(SUPERSAMPLE)
	if internal_blur > 0.0001:
		var blur_data = PoolRealArray()
		blur_data.resize(output_alpha.size())
		for i in range(output_alpha.size()):
			blur_data[i] = float(output_alpha[i])
		for pass_index in range(3):
			blur_data = _fractional_box_blur_horizontal(blur_data, internal_width, internal_height, internal_blur)
			blur_data = _fractional_box_blur_vertical(blur_data, internal_width, internal_height, internal_blur)
		for i in range(output_alpha.size()):
			output_alpha[i] = int(clamp(round(blur_data[i]), 0.0, 255.0))

	var output_image = _make_rgba_image(internal_width, internal_height, output_alpha)
	# Downsampling the supersampled coverage gives blur-zero output a clean edge too.
	output_image.resize(output_width, output_height, Image.INTERPOLATE_LANCZOS)
	return {
		"ok": true,
		"image": output_image,
		"offset": source_origin + Vector2(float(left) * scale, float(top) * scale),
		"pixel_scale": scale,
		"source_size": Vector2(original_width, original_height),
		"work_samples": estimated_work
	}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _estimate_work(source_width: int, source_height: int, displacement: Vector2, output_width: int, output_height: int, mode: String) -> int:
	var output_samples = float(output_width * output_height * SUPERSAMPLE * SUPERSAMPLE)
	if mode == "offset":
		return int(ceil(output_samples))
	var use_x_axis = abs(displacement.x) >= abs(displacement.y)
	var dominant = abs(displacement.x) if use_x_axis else abs(displacement.y)
	var minor = abs(displacement.y) if use_x_axis else abs(displacement.x)
	var slope = minor / dominant if dominant > 0.000001 else 0.0
	var dominant_source = float(source_width if use_x_axis else source_height) * float(SUPERSAMPLE)
	var minor_source = float(source_height if use_x_axis else source_width) * float(SUPERSAMPLE)
	var sheared_rows = int(ceil(minor_source + slope * dominant_source)) + 3
	var output_u = float(output_width if use_x_axis else output_height) * float(SUPERSAMPLE)
	var input_u = output_u + ceil(dominant * float(SUPERSAMPLE)) + 3.0
	var sweep_samples = float(sheared_rows) * (output_u + input_u)
	return int(ceil(output_samples + sweep_samples))


func _render_offset(source_alpha: PoolByteArray, source_width: int, source_height: int, displacement: Vector2, left: int, top: int, output_width: int, output_height: int) -> PoolByteArray:
	var width = output_width * SUPERSAMPLE
	var height = output_height * SUPERSAMPLE
	var shift = displacement * float(SUPERSAMPLE)
	var origin_x = left * SUPERSAMPLE
	var origin_y = top * SUPERSAMPLE
	var output = PoolByteArray()
	output.resize(width * height)
	for y in range(height):
		var source_y = float(origin_y + y) - shift.y
		for x in range(width):
			var source_x = float(origin_x + x) - shift.x
			var value = _sample_alpha(source_alpha, source_width, source_height, source_x, source_y)
			output[y * width + x] = int(clamp(round(value), 0.0, 255.0))
	return output


func _render_sweep(source_alpha: PoolByteArray, source_width: int, source_height: int, displacement: Vector2, left: int, top: int, output_width: int, output_height: int) -> PoolByteArray:
	var use_x_axis = abs(displacement.x) >= abs(displacement.y)
	var dominant_value = displacement.x if use_x_axis else displacement.y
	var minor_value = displacement.y if use_x_axis else displacement.x
	var direction_sign = -1.0 if dominant_value < 0.0 else 1.0
	var dominant = abs(dominant_value) * float(SUPERSAMPLE)
	var slope = minor_value / dominant_value if abs(dominant_value) > 0.000001 else 0.0
	var width = output_width * SUPERSAMPLE
	var height = output_height * SUPERSAMPLE
	var x_origin = left * SUPERSAMPLE
	var y_origin = top * SUPERSAMPLE
	var x_last = x_origin + width - 1
	var y_last = y_origin + height - 1
	var output_u_min = 0
	var output_u_max = 0
	if use_x_axis:
		output_u_min = int(floor(min(direction_sign * float(x_origin), direction_sign * float(x_last))))
		output_u_max = int(ceil(max(direction_sign * float(x_origin), direction_sign * float(x_last))))
	else:
		output_u_min = int(floor(min(direction_sign * float(y_origin), direction_sign * float(y_last))))
		output_u_max = int(ceil(max(direction_sign * float(y_origin), direction_sign * float(y_last))))
	var output_u_count = output_u_max - output_u_min + 1

	# The source alpha is sampled once onto a shear-aligned grid. The shadow
	# displacement becomes horizontal there, so each row can use a sliding max.
	var source_u_count = source_width if use_x_axis else source_height
	var source_v_count = source_height if use_x_axis else source_width
	var source_v_span = float(source_v_count - 1) + abs(slope) * float(source_u_count - 1)
	var source_v_min = int(floor(min(0.0, -slope * float(source_u_count - 1)))) - 1
	var source_v_max = int(ceil(max(float(source_v_count - 1), float(source_v_count - 1) - slope * float(source_u_count - 1)))) + 1
	if source_v_max < source_v_min:
		source_v_min = 0
		source_v_max = source_v_count - 1
	var sweep_height = source_v_max - source_v_min + 1
	var max_alpha = PoolByteArray()
	max_alpha.resize(output_u_count * sweep_height)
	var input_u_min = output_u_min - int(ceil(dominant)) - 1
	var input_u_count = output_u_max - input_u_min + 1
	var queue_capacity = max(1, input_u_count)
	var input_values = PoolByteArray()
	input_values.resize(input_u_count)
	var deque = PoolIntArray()
	deque.resize(queue_capacity)

	for v_row in range(sweep_height):
		var v = float(source_v_min + v_row)
		for input_offset in range(input_u_count):
			var u = float(input_u_min + input_offset)
			var source_point = _inverse_shear(u, v, direction_sign, slope, use_x_axis)
			var value = _sample_alpha(source_alpha, source_width, source_height, source_point.x, source_point.y)
			input_values[input_offset] = int(clamp(round(value), 0.0, 255.0))

		var head = 0
		var tail = 0
		var next_add = input_u_min
		for u_offset in range(output_u_count):
			var u_index = output_u_min + u_offset
			while next_add <= u_index:
				var value_index = next_add - input_u_min
				var new_value = int(input_values[value_index])
				while tail > head:
					var back_u = deque[(tail - 1) % queue_capacity]
					var back_value = int(input_values[int(back_u) - input_u_min])
					if back_value <= new_value:
						tail -= 1
					else:
						break
				deque[tail % queue_capacity] = next_add
				tail += 1
				next_add += 1
			var start_position = float(u_index) - dominant
			var first_in_range = int(ceil(start_position - 0.000001))
			while head < tail and int(deque[head % queue_capacity]) < first_in_range:
				head += 1
			var maximum = 0.0
			if head < tail:
				var front_u = int(deque[head % queue_capacity])
				maximum = float(input_values[front_u - input_u_min])
			maximum = max(maximum, _sample_row(input_values, input_u_min, start_position))
			var target_index = v_row * output_u_count + u_offset
			max_alpha[target_index] = int(clamp(round(maximum), 0.0, 255.0))

	var output = PoolByteArray()
	output.resize(width * height)
	for y in range(height):
		var global_y = y_origin + y
		for x in range(width):
			var global_x = x_origin + x
			var target_u = direction_sign * float(global_x if use_x_axis else global_y)
			var target_v = float(global_y) - slope * float(global_x) if use_x_axis else float(global_x) - slope * float(global_y)
			var u_offset = int(round(target_u)) - output_u_min
			var alpha_value = _sample_sweep_plane(max_alpha, output_u_count, sweep_height, u_offset, target_v - float(source_v_min))
			output[y * width + x] = int(clamp(round(alpha_value), 0.0, 255.0))
	return output


func _inverse_shear(u: float, v: float, direction_sign: float, slope: float, use_x_axis: bool) -> Vector2:
	if use_x_axis:
		var x = direction_sign * u
		return Vector2(x, v + slope * x)
	var y = direction_sign * u
	return Vector2(v + slope * y, y)


func _sample_row(values: PoolByteArray, origin: int, position: float) -> float:
	var floor_position = int(floor(position))
	var fraction = position - float(floor_position)
	var first_index = floor_position - origin
	var second_index = first_index + 1
	var first_value = float(values[first_index]) if first_index >= 0 and first_index < values.size() else 0.0
	var second_value = float(values[second_index]) if second_index >= 0 and second_index < values.size() else 0.0
	return first_value * (1.0 - fraction) + second_value * fraction


func _sample_sweep_plane(data: PoolByteArray, width: int, height: int, x: int, y: float) -> float:
	if x < 0 or x >= width:
		return 0.0
	var y0 = int(floor(y))
	var fraction = y - float(y0)
	var a = float(data[y0 * width + x]) if y0 >= 0 and y0 < height else 0.0
	var b = float(data[(y0 + 1) * width + x]) if y0 + 1 >= 0 and y0 + 1 < height else 0.0
	return a * (1.0 - fraction) + b * fraction


func _sample_alpha(data: PoolByteArray, width: int, height: int, x: float, y: float) -> float:
	var x0 = int(floor(x))
	var y0 = int(floor(y))
	var tx = x - float(x0)
	var ty = y - float(y0)
	var a00 = float(_alpha_at(data, width, height, x0, y0))
	var a10 = float(_alpha_at(data, width, height, x0 + 1, y0))
	var a01 = float(_alpha_at(data, width, height, x0, y0 + 1))
	var a11 = float(_alpha_at(data, width, height, x0 + 1, y0 + 1))
	var upper = a00 * (1.0 - tx) + a10 * tx
	var lower = a01 * (1.0 - tx) + a11 * tx
	return upper * (1.0 - ty) + lower * ty


func _alpha_at(data: PoolByteArray, width: int, height: int, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	return int(data[y * width + x])


func _fractional_box_blur_horizontal(source: PoolRealArray, width: int, height: int, radius: float) -> PoolRealArray:
	var output = PoolRealArray()
	output.resize(source.size())
	var radius0 = int(floor(radius))
	var radius1 = radius0 + 1
	var fraction = radius - float(radius0)
	var divisor0 = float(radius0 * 2 + 1)
	var divisor1 = float(radius1 * 2 + 1)
	for y in range(height):
		var row = y * width
		var total0 = 0.0
		var total1 = 0.0
		for k in range(-radius0, radius0 + 1):
			if k >= 0 and k < width:
				total0 += source[row + k]
		for k in range(-radius1, radius1 + 1):
			if k >= 0 and k < width:
				total1 += source[row + k]
		for x in range(width):
			var average0 = total0 / divisor0
			var average1 = total1 / divisor1
			output[row + x] = average0 * (1.0 - fraction) + average1 * fraction
			var add0 = x + radius0 + 1
			var remove0 = x - radius0
			var add1 = x + radius1 + 1
			var remove1 = x - radius1
			if add0 < width:
				total0 += source[row + add0]
			if remove0 >= 0:
				total0 -= source[row + remove0]
			if add1 < width:
				total1 += source[row + add1]
			if remove1 >= 0:
				total1 -= source[row + remove1]
	return output


func _fractional_box_blur_vertical(source: PoolRealArray, width: int, height: int, radius: float) -> PoolRealArray:
	var output = PoolRealArray()
	output.resize(source.size())
	var radius0 = int(floor(radius))
	var radius1 = radius0 + 1
	var fraction = radius - float(radius0)
	var divisor0 = float(radius0 * 2 + 1)
	var divisor1 = float(radius1 * 2 + 1)
	for x in range(width):
		var total0 = 0.0
		var total1 = 0.0
		for k in range(-radius0, radius0 + 1):
			if k >= 0 and k < height:
				total0 += source[k * width + x]
		for k in range(-radius1, radius1 + 1):
			if k >= 0 and k < height:
				total1 += source[k * width + x]
		for y in range(height):
			var average0 = total0 / divisor0
			var average1 = total1 / divisor1
			output[y * width + x] = average0 * (1.0 - fraction) + average1 * fraction
			var add0 = y + radius0 + 1
			var remove0 = y - radius0
			var add1 = y + radius1 + 1
			var remove1 = y - radius1
			if add0 < height:
				total0 += source[add0 * width + x]
			if remove0 >= 0:
				total0 -= source[remove0 * width + x]
			if add1 < height:
				total1 += source[add1 * width + x]
			if remove1 >= 0:
				total1 -= source[remove1 * width + x]
	return output


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
