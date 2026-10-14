extends Reference

var script_class = "reference"

const MAX_ATLAS_DEPTH = 8

func start():
	pass


func world_to_local_vector(transform: Transform2D, world_vector: Vector2) -> Vector2:
	var x_axis = transform.x
	var y_axis = transform.y
	var determinant = x_axis.x * y_axis.y - y_axis.x * x_axis.y
	if abs(determinant) < 0.000001:
		return Vector2.ZERO
	return Vector2(
		(world_vector.x * y_axis.y - y_axis.x * world_vector.y) / determinant,
		(x_axis.x * world_vector.y - x_axis.y * world_vector.x) / determinant
	)


func angle_vector(degrees: float, distance: float) -> Vector2:
	var radians = degrees * PI / 180.0
	return Vector2(cos(radians), sin(radians)) * distance


func extract_sprite_image(sprite) -> Dictionary:
	if sprite == null:
		return _failure("Sprite is null.")
	if not sprite.has_method("get"):
		return _failure("Object does not expose Sprite properties.")

	var texture = sprite.get("texture")
	if texture == null:
		return _failure("Sprite has no texture.")
	var texture_result = _extract_texture_image(texture, 0)
	if not texture_result.get("ok", false):
		return texture_result
	var texture_image = texture_result["image"]
	if texture_image == null or texture_image.is_empty():
		return _failure("Sprite texture has no readable image data.")

	var hframes = max(1, int(sprite.get("hframes")))
	var vframes = max(1, int(sprite.get("vframes")))
	var frame = max(0, int(sprite.get("frame")))
	var region_enabled = bool(sprite.get("region_enabled"))
	var base_rect = Rect2(Vector2.ZERO, Vector2(texture.get_width(), texture.get_height()))
	if region_enabled:
		base_rect = sprite.get("region_rect")
		if base_rect.size.x <= 0.0 or base_rect.size.y <= 0.0:
			return _failure("Sprite region has zero width or height.")

	var frame_size = base_rect.size / Vector2(float(hframes), float(vframes))
	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return _failure("Sprite frame has zero width or height.")
	var frame_column = frame % hframes
	var frame_row = int(floor(float(frame) / float(hframes)))
	var source_rect = Rect2(
		base_rect.position + Vector2(float(frame_column), float(frame_row)) * frame_size,
		frame_size
	)
	var output_size = Vector2(max(1, int(ceil(frame_size.x))), max(1, int(ceil(frame_size.y))))
	var image = _crop_image_padded(texture_image, source_rect, output_size)
	if image == null or image.is_empty():
		return _failure("Sprite frame could not be cropped from its texture.")

	if bool(sprite.get("flip_h")):
		image.flip_x()
	if bool(sprite.get("flip_v")):
		image.flip_y()

	var draw_position = sprite.get("offset")
	if bool(sprite.get("centered")):
		draw_position -= frame_size / 2.0
	var rect = Rect2(draw_position, frame_size)
	if sprite.has_method("get_rect"):
		var native_rect = sprite.get_rect()
		if native_rect.size.x > 0.0 and native_rect.size.y > 0.0:
			rect = native_rect
	return {"ok": true, "image": image, "rect": rect}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _extract_texture_image(texture, depth: int) -> Dictionary:
	if texture == null:
		return _failure("Texture is null.")
	if depth > MAX_ATLAS_DEPTH:
		return _failure("AtlasTexture nesting is too deep.")

	if texture is AtlasTexture:
		var atlas_texture = texture.get("atlas")
		if atlas_texture == null:
			return _failure("AtlasTexture has no atlas.")
		var atlas_result = _extract_texture_image(atlas_texture, depth + 1)
		if not atlas_result.get("ok", false):
			return atlas_result
		var atlas_image = atlas_result["image"]
		var raw_region: Rect2 = texture.get("region")
		var region_size = raw_region.size
		if region_size.x == 0.0:
			region_size.x = atlas_texture.get_width()
		if region_size.y == 0.0:
			region_size.y = atlas_texture.get_height()
		var region = Rect2(raw_region.position, region_size)
		if region.size.x <= 0.0 or region.size.y <= 0.0:
			return _failure("AtlasTexture region has invalid dimensions.")
		var margin = texture.get("margin")
		var logical_width = max(1, int(texture.get_width()))
		var logical_height = max(1, int(texture.get_height()))
		var logical_image = Image.new()
		logical_image.create(logical_width, logical_height, false, Image.FORMAT_RGBA8)
		logical_image.fill(Color(0, 0, 0, 0))
		_blit_region_padded(atlas_image, region, logical_image, margin.position)
		return {"ok": true, "image": logical_image}

	if not texture.has_method("get_data"):
		return _failure("Texture type does not expose readable image data.")
	var image = texture.get_data()
	if image == null or image.is_empty():
		return _failure("Texture returned no image data.")
	var rgba_image = image.duplicate()
	if rgba_image.is_compressed():
		var decompress_error = rgba_image.decompress()
		if decompress_error != OK:
			return _failure("Could not decompress texture image (error %d)." % decompress_error)
	if rgba_image.get_format() != Image.FORMAT_RGBA8:
		rgba_image.convert(Image.FORMAT_RGBA8)
	if rgba_image.is_compressed() or rgba_image.get_format() != Image.FORMAT_RGBA8:
		return _failure("Texture image could not be converted to RGBA8.")
	var texture_width = max(1, int(texture.get_width()))
	var texture_height = max(1, int(texture.get_height()))
	if rgba_image.get_width() != texture_width or rgba_image.get_height() != texture_height:
		rgba_image.resize(texture_width, texture_height, Image.INTERPOLATE_BILINEAR)
	return {"ok": true, "image": rgba_image}


func _crop_image_padded(source: Image, source_rect: Rect2, output_size: Vector2) -> Image:
	var width = max(1, int(output_size.x))
	var height = max(1, int(output_size.y))
	var output = Image.new()
	output.create(width, height, false, Image.FORMAT_RGBA8)
	output.fill(Color(0, 0, 0, 0))
	_blit_region_padded(source, source_rect, output, Vector2.ZERO)
	return output


func _blit_region_padded(source: Image, source_rect: Rect2, destination: Image, destination_position: Vector2):
	if source == null or source.is_empty() or source_rect.size.x <= 0.0 or source_rect.size.y <= 0.0:
		return
	var source_left = int(floor(source_rect.position.x))
	var source_top = int(floor(source_rect.position.y))
	var source_right = int(ceil(source_rect.position.x + source_rect.size.x))
	var source_bottom = int(ceil(source_rect.position.y + source_rect.size.y))
	var clipped_left = max(0, source_left)
	var clipped_top = max(0, source_top)
	var clipped_right = min(source.get_width(), source_right)
	var clipped_bottom = min(source.get_height(), source_bottom)
	if clipped_right <= clipped_left or clipped_bottom <= clipped_top:
		return
	var clipped_rect = Rect2(
		Vector2(clipped_left, clipped_top),
		Vector2(clipped_right - clipped_left, clipped_bottom - clipped_top)
	)
	var crop = source.get_rect(clipped_rect)
	if crop == null or crop.is_empty():
		return
	var destination_x = int(round(destination_position.x + float(clipped_left) - source_rect.position.x))
	var destination_y = int(round(destination_position.y + float(clipped_top) - source_rect.position.y))
	destination.blit_rect(crop, Rect2(Vector2.ZERO, Vector2(crop.get_width(), crop.get_height())), Vector2(destination_x, destination_y))
