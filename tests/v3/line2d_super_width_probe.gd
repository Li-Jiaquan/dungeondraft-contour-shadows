extends SceneTree

const REPORT_PATH = "res://v3/artifacts/line2d-super-width-probe.json"


func _init():
	call_deferred("_run")


func _run():
	var line = Line2D.new()
	line.width = 10.0
	var default_super = bool(line.get_super())
	line.set_super(true)
	var super_before_points = bool(line.get_super())
	line.clear_points()
	line.add_point(Vector2(16, 32))
	line.add_point(Vector2(48, 32))
	var report = {
		"engine_version": Engine.get_version_info(),
		"default_super": default_super,
		"super_before_points": super_before_points,
		"global_width": line.width,
		"point_count_after_add": line.get_point_count(),
		"default_point_widths_after_super_then_add": [line.get_point_width(0), line.get_point_width(1)]
	}
	print("LINE2D_SUPER_WIDTH_PROBE=" + JSON.print(report))
	var absolute_path = ProjectSettings.globalize_path(REPORT_PATH)
	var directory = Directory.new()
	directory.make_dir_recursive(absolute_path.get_base_dir())
	var file = File.new()
	var error = file.open(absolute_path, File.WRITE)
	if error == OK:
		file.store_string(JSON.print(report, "\t"))
		file.close()
	line.free()
	quit(0 if error == OK else 1)
