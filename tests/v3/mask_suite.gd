extends SceneTree

const MASK_PATH = "res://.staged/shadow_mask.gd"

var failures = []
var lines = []
var mask = null

func _init():
	var mask_script = load(MASK_PATH)
	if mask_script == null:
		_fail("staged shadow mask script loads")
		_finish()
		return
	mask = mask_script.new()
	call_deferred("_run")

func _run():
	_test_soft_edge()
	_test_radius_and_hardness()
	_test_same_stroke_max_influence()
	_test_source_and_rgb_immutability()
	_test_nonuniform_transform()
	_test_legacy_hard_edge()
	_test_hardness_validation()
	_finish()

func _test_soft_edge():
	var source = _solid_image(11, 5, Color(1, 1, 1, 1))
	var stroke = {"points": [[5.5, 2.5]], "radius": 4.0, "hardness": 0.5}
	var result = mask.apply(source, [stroke], Transform2D())
	var center_alpha = _alpha(result, 5, 2)
	var ring_alpha = _alpha(result, 8, 2)
	var edge_alpha = _alpha(result, 9, 2)
	_expect(center_alpha == 0.0, "soft brush clears its hardness core completely")
	_expect(ring_alpha > 0.35 and ring_alpha < 0.65, "soft brush preserves a smooth intermediate alpha in the outer ring")
	_expect(edge_alpha > 0.98, "soft brush keeps original alpha at the radius boundary")
	_expect(mask.intersects(source, stroke, Transform2D()), "soft stroke still intersects opaque source pixels")

func _test_radius_and_hardness():
	var source = _solid_image(15, 5, Color(1, 1, 1, 1))
	var center = [7.5, 2.5]
	var small = mask.apply(source, [{"points": [center], "radius": 2.0, "hardness": 1.0}], Transform2D())
	var large = mask.apply(source, [{"points": [center], "radius": 4.0, "hardness": 1.0}], Transform2D())
	_expect(_alpha(small, 10, 2) > 0.98 and _alpha(large, 10, 2) == 0.0, "brush radius changes the cleared area")
	var soft = mask.apply(source, [{"points": [center], "radius": 4.0, "hardness": 0.5}], Transform2D())
	var hard = mask.apply(source, [{"points": [center], "radius": 4.0, "hardness": 0.9}], Transform2D())
	_expect(_alpha(soft, 10, 2) > 0.35 and _alpha(soft, 10, 2) < 0.65 and _alpha(hard, 10, 2) == 0.0, "higher hardness expands the fully cleared core")

func _test_same_stroke_max_influence():
	var source = _solid_image(13, 7, Color(1, 1, 1, 1))
	var one_segment = {"points": [[1.5, 3.5], [10.5, 3.5]], "radius": 2.5, "hardness": 0.4}
	var duplicate_segment = {"points": [[1.5, 3.5], [10.5, 3.5], [1.5, 3.5], [10.5, 3.5]], "radius": 2.5, "hardness": 0.4}
	var once = mask.apply(source, [one_segment], Transform2D())
	var repeated = mask.apply(source, [duplicate_segment], Transform2D())
	_expect(_images_equal(once, repeated), "duplicate and reversing segments use the maximum same-stroke influence")
	var separate_strokes = mask.apply(source, [one_segment, one_segment], Transform2D())
	_expect(_alpha(separate_strokes, 6, 5) <= _alpha(once, 6, 5), "separate strokes accumulate independently")

func _test_source_and_rgb_immutability():
	var original_color = Color(0.2, 0.4, 0.6, 0.8)
	var source = _solid_image(9, 5, original_color)
	var before = source.get_data()
	var result = mask.apply(source, [{"points": [[4.5, 2.5]], "radius": 2.0, "hardness": 1.0}], Transform2D())
	source.lock()
	var source_center = source.get_pixel(4, 2)
	source.unlock()
	result.lock()
	var output_center = result.get_pixel(4, 2)
	var output_edge = result.get_pixel(6, 2)
	result.unlock()
	_expect(source.get_data() == before and is_equal_approx(source_center.a, original_color.a), "applying erasure leaves the original Image unchanged")
	_expect(output_center.a == 0.0 and is_equal_approx(output_center.r, source_center.r) and is_equal_approx(output_center.g, source_center.g) and is_equal_approx(output_center.b, source_center.b), "erasure changes only alpha and leaves RGB intact")
	_expect(output_edge.a == 0.0, "hardness one retains the legacy inclusive radius edge")

func _test_nonuniform_transform():
	var source = _solid_image(15, 11, Color(1, 1, 1, 1))
	var stroke = {
		"points": [[7.5, 5.5]],
		"radius": 2.0,
		"hardness": 1.0,
		"radius_basis": [[2.0, 0.0], [0.0, 1.0]]
	}
	var result = mask.apply(source, [stroke], Transform2D())
	_expect(_alpha(result, 10, 5) == 0.0 and _alpha(result, 12, 5) > 0.98, "nonuniform source transform keeps radius circular in brush space")
	_expect(_alpha(result, 7, 8) > 0.98, "nonuniform transform applies the shorter vertical ellipse extent")

func _test_legacy_hard_edge():
	var source = _solid_image(9, 5, Color(1, 1, 1, 1))
	var legacy = {"points": [[4.5, 2.5]], "radius": 2.0}
	var explicit_hard = {"points": [[4.5, 2.5]], "radius": 2.0, "hardness": 1.0}
	var legacy_result = mask.apply(source, [legacy], Transform2D())
	var explicit_result = mask.apply(source, [explicit_hard], Transform2D())
	_expect(_images_equal(legacy_result, explicit_result), "strokes without hardness preserve the previous hard-edge behavior")
	_expect(_alpha(legacy_result, 6, 2) == 0.0 and _alpha(legacy_result, 7, 2) > 0.98, "legacy hard brush clears through its radius and preserves the outside")

func _test_hardness_validation():
	var source = _solid_image(13, 5, Color(1, 1, 1, 1))
	var point = [6.5, 2.5]
	var hard = mask.apply(source, [{"points": [point], "radius": 4.0, "hardness": 1.0}], Transform2D())
	var invalid_values = ["0.25", null, {"value": 0.25}, NAN]
	for invalid_value in invalid_values:
		var invalid_result = mask.apply(source, [{"points": [point], "radius": 4.0, "hardness": invalid_value}], Transform2D())
		_expect(_images_equal(invalid_result, hard), "invalid hardness %s safely falls back to legacy hard edge" % str(invalid_value))

	var clamped_zero = mask.apply(source, [{"points": [point], "radius": 4.0, "hardness": 0.0}], Transform2D())
	var below_zero = mask.apply(source, [{"points": [point], "radius": 4.0, "hardness": -3.0}], Transform2D())
	_expect(_images_equal(clamped_zero, below_zero), "numeric hardness below zero clamps to zero")
	var above_one = mask.apply(source, [{"points": [point], "radius": 4.0, "hardness": 3.0}], Transform2D())
	_expect(_images_equal(hard, above_one), "numeric hardness above one clamps to one")

func _solid_image(width, height, color):
	var image = Image.new()
	image.create(width, height, false, Image.FORMAT_RGBA8)
	image.lock()
	for y in range(height):
		for x in range(width):
			image.set_pixel(x, y, color)
	image.unlock()
	return image

func _alpha(image, x, y):
	if image == null or image.is_empty():
		return -1.0
	image.lock()
	var value = image.get_pixel(x, y).a
	image.unlock()
	return value

func _images_equal(first, second):
	if first == null or second == null or first.get_size() != second.get_size():
		return false
	var first_data = first.get_data()
	var second_data = second.get_data()
	if first_data.size() != second_data.size():
		return false
	for index in range(first_data.size()):
		if first_data[index] != second_data[index]:
			return false
	return true

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
	if report.open("res://.staged/mask-suite-report.txt", File.WRITE) == OK:
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
