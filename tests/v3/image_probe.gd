extends SceneTree
func _init():
	var image = Image.new()
	image.create(24, 24, false, Image.FORMAT_RGBA8)
	print("PROBE_NEW_EMPTY=", image.empty(), " type=", typeof(image.empty()))
	var image_copy = image.duplicate()
	print("PROBE_COPY_EMPTY=", image_copy.empty(), " type=", typeof(image_copy.empty()), " size=", image_copy.get_size())
	var typed_image: Image = image_copy
	print("PROBE_TYPED_EMPTY=", typed_image.empty(), " type=", typeof(typed_image.empty()))
	print("PROBE_HAS_EMPTY=", image.has_method("empty"), " is_empty=", image.has_method("is_empty"))
	print("PROBE_IS_EMPTY=", image.is_empty())
	for method in image_copy.get_method_list():
		if "empty" in method.name:
			print("PROBE_EMPTY_METHOD=", method)
	quit()
