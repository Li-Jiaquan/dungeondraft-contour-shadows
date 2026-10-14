extends Reference

var script_class = "reference"

const MAX_OUTPUT_DIMENSION = 1024
const MAX_SWEEP_STEPS = 1024
const MAX_SWEEP_WORK = 250000

class AlphaMask:
	extends Reference
	var width = 0
	var height = 0
	# Array is reference-backed in Godot 3, so the large max-union mask can be
	# mutated in place without PoolByteArray copy-on-write surprises.
	var bytes = []

	func create(mask_width: int, mask_height: int):
		width = mask_width
		height = mask_height
		bytes.resize(width * height)
		for i in range(bytes.size()):
			bytes[i] = 0

	func merge_translated(source_alpha: PoolByteArray, source_width: int, source_height: int, shift: Vector2):
		for y in range(source_height):
			var row = y * source_width
			for x in range(source_width):
				var alpha_value = int(source_alpha[row + x])
				if alpha_value == 0:
					continue
				var target_x = float(x) + shift.x
				var target_y = float(y) + shift.y
				var x0 = int(floor(target_x))
				var y0 = int(floor(target_y))
				var tx = target_x - float(x0)
				var ty = target_y - float(y0)
				var tx_is_zero = abs(tx) < 0.000001
				var ty_is_zero = abs(ty) < 0.000001
				if tx_is_zero and ty_is_zero:
					if x0 >= 0 and y0 >= 0 and x0 < width and y0 < height:
						var integer_index = y0 * width + x0
						if alpha_value > int(bytes[integer_index]):
							bytes[integer_index] = alpha_value
					continue
				if tx_is_zero:
					var vertical00 = int(round(float(alpha_value) * (1.0 - ty)))
					var vertical01 = int(round(float(alpha_value) * ty))
					if vertical00 > 0 and x0 >= 0 and y0 >= 0 and x0 < width and y0 < height:
						var vertical_index00 = y0 * width + x0
						if vertical00 > int(bytes[vertical_index00]):
							bytes[vertical_index00] = vertical00
					if vertical01 > 0 and x0 >= 0 and y0 + 1 >= 0 and x0 < width and y0 + 1 < height:
						var vertical_index01 = (y0 + 1) * width + x0
						if vertical01 > int(bytes[vertical_index01]):
							bytes[vertical_index01] = vertical01
					continue
				if ty_is_zero:
					var horizontal00 = int(round(float(alpha_value) * (1.0 - tx)))
					var horizontal10 = int(round(float(alpha_value) * tx))
					if horizontal00 > 0 and x0 >= 0 and y0 >= 0 and x0 < width and y0 < height:
						var horizontal_index00 = y0 * width + x0
						if horizontal00 > int(bytes[horizontal_index00]):
							bytes[horizontal_index00] = horizontal00
					if horizontal10 > 0 and x0 + 1 >= 0 and y0 >= 0 and x0 + 1 < width and y0 < height:
						var horizontal_index10 = y0 * width + x0 + 1
						if horizontal10 > int(bytes[horizontal_index10]):
							bytes[horizontal_index10] = horizontal10
					continue
				var value00 = int(round(float(alpha_value) * (1.0 - tx) * (1.0 - ty)))
				var value10 = int(round(float(alpha_value) * tx * (1.0 - ty)))
				var value01 = int(round(float(alpha_value) * (1.0 - tx) * ty))
				var value11 = int(round(float(alpha_value) * tx * ty))
				if value00 > 0 and x0 >= 0 and y0 >= 0 and x0 < width and y0 < height:
					var index00 = y0 * width + x0
					if value00 > int(bytes[index00]):
						bytes[index00] = value00
				if value10 > 0 and x0 + 1 >= 0 and y0 >= 0 and x0 + 1 < width and y0 < height:
					var index10 = y0 * width + x0 + 1
					if value10 > int(bytes[index10]):
						bytes[index10] = value10
				if value01 > 0 and x0 >= 0 and y0 + 1 >= 0 and x0 < width and y0 + 1 < height:
					var index01 = (y0 + 1) * width + x0
					if value01 > int(bytes[index01]):
						bytes[index01] = value01
				if value11 > 0 and x0 + 1 >= 0 and y0 + 1 >= 0 and x0 + 1 < width and y0 + 1 < height:
					var index11 = (y0 + 1) * width + x0 + 1
					if value11 > int(bytes[index11]):
						bytes[index11] = value11

	func get_bytes() -> Array:
		return bytes


func start():
	pass


func get_work_limit() -> int:
	return MAX_SWEEP_WORK


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

	# Remove only fully transparent outer padding. This keeps sparse, padded textures
	# detailed and avoids scanning huge blank areas; the returned offset restores the
	# cropped image to the original Sprite-local pixel coordinates.
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

	var source_data = rgba_image.get_data()
	if source_data.size() < source_width * source_height * 4:
		return _failure("Source image data is incomplete.")

	var output_limit = min(max_size, MAX_OUTPUT_DIMENSION)
	var scale = 1.0
	var scaled_width = 1
	var scaled_height = 1
	var scaled_displacement = Vector2.ZERO
	var scaled_blur = 0.0
	var box_radius = 0
	var blur_padding = 0
	var left = 0
	var top = 0
	var right = 0
	var bottom = 0
	var output_width = 1
	var output_height = 1
	var sweep_steps = 1

	# Solve the raster scale before allocating anything. Sweep work is capped as well as
	# the final dimensions so a huge object and a long extension cannot stall the editor.
	for iteration in range(16):
		scaled_width = max(1, int(ceil(float(source_width) / scale)))
		scaled_height = max(1, int(ceil(float(source_height) / scale)))
		scaled_displacement = displacement / scale
		scaled_blur = blur_radius / scale
		box_radius = _box_radius(scaled_blur)
		blur_padding = box_radius * 3
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
		if mode == "sweep":
			sweep_steps = _get_sweep_steps(scaled_displacement)
		else:
			sweep_steps = 1

		var dimension_ratio = max(float(output_width), float(output_height)) / float(output_limit)
		var estimated_work = float(scaled_width) * float(scaled_height) * float(sweep_steps + 1)
		var work_ratio = estimated_work / float(MAX_SWEEP_WORK)
		if dimension_ratio <= 1.0 and (mode != "sweep" or work_ratio <= 1.0):
			break
		var dimension_scale = dimension_ratio * 1.002 if dimension_ratio > 1.0 else 1.0
		var work_scale = pow(work_ratio, 0.34) * 1.01 if mode == "sweep" and work_ratio > 1.0 else 1.0
		scale *= max(dimension_scale, work_scale)

	# Recalculate after the bounded solve, including an exact final-size guard.
	scaled_width = max(1, int(ceil(float(source_width) / scale)))
	scaled_height = max(1, int(ceil(float(source_height) / scale)))
	scaled_displacement = displacement / scale
	scaled_blur = blur_radius / scale
	box_radius = _box_radius(scaled_blur)
	blur_padding = box_radius * 3
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
	if mode == "sweep":
		sweep_steps = _get_sweep_steps(scaled_displacement)
	else:
		sweep_steps = 1
	if float(scaled_width) * float(scaled_height) * float(sweep_steps + 1) > float(MAX_SWEEP_WORK) * 1.1:
		return _failure("Sweep exceeded the bounded sampling budget.")

	var source_alpha = PoolByteArray()
	source_alpha.resize(scaled_width * scaled_height)
	var alpha_threshold = int(ceil(clamp(alpha_cutoff, 0.0, 1.0) * 255.0))
	var has_visible_alpha = false
	for y in range(scaled_height):
		for x in range(scaled_width):
			var alpha_value = 0
			if scale <= 1.000001:
				var source_x = clamp((float(x) + 0.5) * scale - 0.5, 0.0, float(source_width - 1))
				var source_y = clamp((float(y) + 0.5) * scale - 0.5, 0.0, float(source_height - 1))
				alpha_value = _sample_alpha(source_data, source_width, source_height, source_x, source_y)
			else:
				alpha_value = _max_alpha_in_region(source_data, source_width, source_height, x, y, scale)
			if alpha_value < alpha_threshold:
				alpha_value = 0
			else:
				has_visible_alpha = true
			source_alpha[y * scaled_width + x] = alpha_value

	if not has_visible_alpha:
		var empty_image = _make_rgba_image(1, 1, PoolByteArray())
		return {
			"ok": true,
			"image": empty_image,
			"offset": source_origin,
			"pixel_scale": scale,
			"source_size": Vector2(original_width, original_height)
		}

	var output_mask = AlphaMask.new()
	output_mask.create(output_width, output_height)

	if mode == "sweep":
		for step in range(sweep_steps + 1):
			var t = float(step) / float(sweep_steps)
			var shift = scaled_displacement * t
			output_mask.merge_translated(source_alpha, scaled_width, scaled_height, shift - Vector2(left, top))
	else:
		output_mask.merge_translated(source_alpha, scaled_width, scaled_height, scaled_displacement - Vector2(left, top))

	var merged_alpha: Array = output_mask.get_bytes()
	var output_alpha = PoolByteArray()
	output_alpha.resize(merged_alpha.size())
	for i in range(merged_alpha.size()):
		output_alpha[i] = int(merged_alpha[i])

	if box_radius > 0:
		# Keep intermediate blur values in float storage. Quantizing each pass to
		# RGBA8 would progressively darken small, valid silhouettes.
		var blur_data = PoolRealArray()
		blur_data.resize(output_alpha.size())
		for i in range(output_alpha.size()):
			blur_data[i] = float(output_alpha[i])
		for pass_index in range(3):
			blur_data = _box_blur_horizontal_real(blur_data, output_width, output_height, box_radius)
			blur_data = _box_blur_vertical_real(blur_data, output_width, output_height, box_radius)
		output_alpha = PoolByteArray()
		output_alpha.resize(blur_data.size())
		for i in range(blur_data.size()):
			output_alpha[i] = int(clamp(round(blur_data[i]), 0.0, 255.0))

	var output_image = _make_rgba_image(output_width, output_height, output_alpha)
	return {
		"ok": true,
		"image": output_image,
		"offset": source_origin + Vector2(float(left) * scale, float(top) * scale),
		"pixel_scale": scale,
		"source_size": Vector2(original_width, original_height)
	}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _box_radius(blur: float) -> int:
	if blur <= 0.0:
		return 0
	return max(0, int(floor(blur + 0.5)))


func _get_sweep_steps(displacement: Vector2) -> int:
	var distance = displacement.length()
	if distance <= 0.0001:
		return 1
	return max(1, min(MAX_SWEEP_STEPS, int(ceil(distance * 2.0))))


func _sample_alpha(data: PoolByteArray, width: int, height: int, x: float, y: float) -> int:
	var x0 = int(floor(x))
	var y0 = int(floor(y))
	var tx = x - float(x0)
	var ty = y - float(y0)
	var a00 = _alpha_at(data, width, height, x0, y0)
	var a10 = _alpha_at(data, width, height, x0 + 1, y0)
	var a01 = _alpha_at(data, width, height, x0, y0 + 1)
	var a11 = _alpha_at(data, width, height, x0 + 1, y0 + 1)
	var upper = float(a00) * (1.0 - tx) + float(a10) * tx
	var lower = float(a01) * (1.0 - tx) + float(a11) * tx
	return int(round(upper * (1.0 - ty) + lower * ty))


func _max_alpha_in_region(data: PoolByteArray, width: int, height: int, output_x: int, output_y: int, scale: float) -> int:
	var left = max(0, int(floor(float(output_x) * scale)))
	var top = max(0, int(floor(float(output_y) * scale)))
	var right = min(width, int(ceil(float(output_x + 1) * scale)))
	var bottom = min(height, int(ceil(float(output_y + 1) * scale)))
	var maximum_alpha = 0
	for y in range(top, bottom):
		for x in range(left, right):
			maximum_alpha = max(maximum_alpha, int(data[(y * width + x) * 4 + 3]))
			if maximum_alpha >= 255:
				return 255
	return maximum_alpha


func _alpha_at(data: PoolByteArray, width: int, height: int, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	return int(data[(y * width + x) * 4 + 3])


func _box_blur_horizontal_real(source: PoolRealArray, width: int, height: int, radius: int) -> PoolRealArray:
	var output = PoolRealArray()
	output.resize(source.size())
	var divisor = radius * 2 + 1
	for y in range(height):
		var row = y * width
		var total = 0.0
		for k in range(-radius, radius + 1):
			if k >= 0 and k < width:
				total += source[row + k]
		for x in range(width):
			output[row + x] = total / float(divisor)
			var add_x = x + radius + 1
			var remove_x = x - radius
			if add_x < width:
				total += source[row + add_x]
			if remove_x >= 0:
				total -= source[row + remove_x]
	return output


func _box_blur_vertical_real(source: PoolRealArray, width: int, height: int, radius: int) -> PoolRealArray:
	var output = PoolRealArray()
	output.resize(source.size())
	var divisor = radius * 2 + 1
	for x in range(width):
		var total = 0.0
		for k in range(-radius, radius + 1):
			if k >= 0 and k < height:
				total += source[k * width + x]
		for y in range(height):
			output[y * width + x] = total / float(divisor)
			var add_y = y + radius + 1
			var remove_y = y - radius
			if add_y < height:
				total += source[add_y * width + x]
			if remove_y >= 0:
				total -= source[remove_y * width + x]
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
