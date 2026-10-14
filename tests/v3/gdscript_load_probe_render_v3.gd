extends SceneTree

func _init():
	call_deferred("_run")

func _run():
	var loaded = load("res://v3/mask_incremental_drag_benchmark.gd")
	var file = File.new()
	if file.open("res://v3/artifacts/gdscript-load-probe-render-v3.txt", File.WRITE) == OK:
		file.store_string("loaded=" + str(loaded != null))
		file.close()
	quit(0 if loaded != null else 1)
