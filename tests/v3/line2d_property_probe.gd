extends SceneTree

const REPORT_PATH = "res://v3/artifacts/line2d-native-probe.json"


func _init():
	call_deferred("_run")


func _run():
	var line = Line2D.new()
	var native_properties = _native_property_rows(line)
	var native_property_names = []
	for property in native_properties:
		native_property_names.append(str(property.get("name", "")))
	var queried_properties = {}
	for property_name in ["grow", "shrink", "transition", "uv", "loop", "normalize_uv", "begin_cap_mode", "end_cap_mode", "texture_mode"]:
		queried_properties[property_name] = native_property_names.has(property_name)
	var report = {
		"engine_version": Engine.get_version_info(),
		"class": "Line2D",
		"native_properties": native_properties,
		"native_methods": _native_method_rows(line),
		"queried_native_property_presence": queried_properties,
		"line_instance_property_names": _instance_property_names(line)
	}
	var absolute_path = ProjectSettings.globalize_path(REPORT_PATH)
	var directory = Directory.new()
	directory.make_dir_recursive(absolute_path.get_base_dir())
	var file = File.new()
	var error = file.open(absolute_path, File.WRITE)
	if error == OK:
		file.store_string(JSON.print(report, "\t"))
		file.close()
	print("LINE2D_NATIVE_PROBE=" + JSON.print(report))
	line.free()
	quit(0 if error == OK else 1)


func _native_property_rows(line: Line2D) -> Array:
	var rows = []
	for property in ClassDB.class_get_property_list("Line2D", true):
		var property_name = str(property.get("name", ""))
		rows.append({
			"name": property_name,
			"type": int(property.get("type", TYPE_NIL)),
			"type_name": _variant_type_name(int(property.get("type", TYPE_NIL))),
			"hint": int(property.get("hint", PROPERTY_HINT_NONE)),
			"hint_string": str(property.get("hint_string", "")),
			"usage": int(property.get("usage", 0)),
			"default_value": str(line.get(property_name))
		})
	return rows


func _variant_type_name(type_id: int) -> String:
	var names = {
		TYPE_NIL: "NIL",
		TYPE_BOOL: "BOOL",
		TYPE_INT: "INT",
		TYPE_REAL: "REAL",
		TYPE_STRING: "STRING",
		TYPE_VECTOR2: "VECTOR2",
		TYPE_RECT2: "RECT2",
		TYPE_VECTOR3: "VECTOR3",
		TYPE_TRANSFORM2D: "TRANSFORM2D",
		TYPE_PLANE: "PLANE",
		TYPE_QUAT: "QUAT",
		TYPE_AABB: "AABB",
		TYPE_BASIS: "BASIS",
		TYPE_TRANSFORM: "TRANSFORM",
		TYPE_COLOR: "COLOR",
		TYPE_NODE_PATH: "NODE_PATH",
		TYPE_RID: "RID",
		TYPE_OBJECT: "OBJECT",
		TYPE_DICTIONARY: "DICTIONARY",
		TYPE_ARRAY: "ARRAY",
		TYPE_RAW_ARRAY: "POOL_BYTE_ARRAY",
		TYPE_INT_ARRAY: "POOL_INT_ARRAY",
		TYPE_REAL_ARRAY: "POOL_REAL_ARRAY",
		TYPE_STRING_ARRAY: "POOL_STRING_ARRAY",
		TYPE_VECTOR2_ARRAY: "POOL_VECTOR2_ARRAY",
		TYPE_VECTOR3_ARRAY: "POOL_VECTOR3_ARRAY",
		TYPE_COLOR_ARRAY: "POOL_COLOR_ARRAY"
	}
	return str(names.get(type_id, "UNKNOWN"))


func _native_method_rows(line: Line2D) -> Array:
	var rows = []
	var class_methods = ClassDB.class_get_method_list("Line2D", true)
	var instance_methods = line.get_method_list()
	for method in class_methods:
		var row = {"name": str(method.get("name", ""))}
		for instance_method in instance_methods:
			if str(instance_method.get("name", "")) == row["name"]:
				row["instance_metadata"] = str(instance_method)
				break
		rows.append(row)
	return rows


func _instance_property_names(line: Line2D) -> Array:
	var names = []
	for property in line.get_property_list():
		names.append(str(property.get("name", "")))
	return names
