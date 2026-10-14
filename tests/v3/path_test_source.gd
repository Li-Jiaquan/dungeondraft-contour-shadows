extends "res://.staged/path_source.gd"

# Test-only override for a Line2D fixture whose per-point width storage was
# initialized explicitly by set_point_width(). Production path_source.gd keeps
# native reads restricted to real CSharpScript Pathways.
func _has_taper_width_storage(line: Line2D) -> bool:
	if line != null and is_instance_valid(line) and line.has_meta("path_suite_taper_widths_initialized"):
		return bool(line.get_meta("path_suite_taper_widths_initialized"))
	return ._has_taper_width_storage(line)
