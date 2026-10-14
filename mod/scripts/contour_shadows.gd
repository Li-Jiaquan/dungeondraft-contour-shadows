var script_class = "tool"

const TOOL_ID = "contour_shadows"
const DISPLAY_NAME = "轮廓投影"
const SETTINGS_PATH = "user://contour_shadows/settings.json"
const MAP_DATA_KEY = "contour_shadows"
const RECIPE_VERSION = 2
const SHADOW_META = "contour_shadows_owner"
const SELECTION_MARK_META = "contour_shadows_selection_marked"
const SHADOW_NODE_NAME = "__ContourShadows"
const FOLLOW_INTERVAL = 0.2
const FOLLOW_SCAN_BUDGET = 2
const GENERATION_BUDGET_PER_FRAME = 1
const MAX_RENDER_SIZE = 512
const MAX_EXTRACTION_CACHE_ITEMS = 32
const MAX_EXTRACTION_CACHE_BYTES = 67108864
const ALPHA_CUTOFF = 0.02
const ERASER_DEFAULT_RADIUS = 12.0
const PARAMETER_REFRESH_DEBOUNCE_SECONDS = 0.18
const ERASER_FRAME_PIXEL_BUDGET = 4096
const ERASER_FRAME_TIME_BUDGET_USEC = 6000
const ERASER_GPU_FOOTPRINT_THRESHOLD_PIXELS = 16384

var angle_degrees = 45.0
var distance = 32.0
var blur_radius = 8.0
var opacity = 0.30
var shadow_mode = "sweep"
var shadow_color = Color(0.08, 0.08, 0.09, 1.0)
var follow_enabled = false
var preview_enabled = true
var adjustment_mode = "global"
var eraser_enabled = false
var eraser_radius = ERASER_DEFAULT_RADIUS
var eraser_hardness = 0.7

var _tool_panel = null
var _status_label = null
var _selection_label = null
var _angle_slider = null
var _distance_slider = null
var _blur_slider = null
var _opacity_slider = null
var _angle_value_label = null
var _distance_value_label = null
var _blur_value_label = null
var _opacity_value_label = null
var _offset_mode_button = null
var _sweep_mode_button = null
var _color_palette = null
var _color_label = null
var _follow_button = null
var _preview_button = null
var _individual_adjust_button = null
var _global_adjust_button = null
var _use_global_button = null
var _eraser_button = null
var _eraser_radius_slider = null
var _eraser_hardness_slider = null
var _eraser_hardness_value_label = null
var _erase_undo_button = null
var _restore_erasures_button = null
var _scope_label = null
var _advanced_toggle = null
var _advanced_container = null
var _selection_action_row = null
var _selection_action_row_vertical = true
var _selection_action_button_a = null
var _selection_action_button_b = null
var _selection_action_view_a = null
var _selection_action_view_b = null
var _eraser_radius_value_label = null
var _last_action_layout_width = -1.0

var _renderer = null
var _geometry = null
var _path_source = null
var _shadow_mask = null
var _enabled_node_ids = {}
var _excluded_node_ids = {}
var _overrides = {}
var _erasures = {}
var _recipe_extra_fields = {}
var _recipe_extra_settings = {}
var _generation_queue = []
var _pending_node_ids = {}
var _generated_fingerprints = {}
var _extraction_cache = {}
var _extraction_cache_bytes = 0
var _extraction_cache_clock = 0
var _world_instance_id = -1
var _map_recipe_writable = true
var _settings_dirty = false
var _settings_save_delay = 0.0
var _parameter_refresh_pending = false
var _parameter_refresh_delay = 0.0
var _parameter_refresh_global = false
var _parameter_refresh_node_ids = {}
var _parameter_refresh_event_count = 0
var _parameter_refresh_batch_count = 0
var _follow_delay = 0.0
var _follow_cursor = 0
var _last_operation = "尚未生成"
var _last_error = ""
var _last_notice = ""
var _last_selection_type = "unknown"
var _last_selection_type_code = TYPE_NIL
var _last_selection_count = 0
var _last_selected_prop_count = 0
var _last_selected_path_count = 0
var _last_selection_source = "none"
var _selection_snapshot_node_ids = []
var _selection_snapshot_world_id = -1
var _selection_snapshot_level_id = -1
var _selection_snapshot_map_file = ""
var _selection_record_cleared = false
var _selection_highlight_node_ids = {}
var _last_generated = 0
var _last_removed = 0
var _last_skipped = 0
var _queue_completion_label = ""
var _syncing_controls = false
var _selection_parameter_key = ""
var _generation_in_progress = false
var _generation_epoch = 0
var _generation_job_counter = 0
var _active_generation_token = -1
var _active_generation_level_id = -1
var _active_generation_node_key = ""
var _generation_batch_total = 0
var _generation_batch_done = 0
var _render_count_total = 0
var _last_render_msec = 0.0
var _total_render_msec = 0.0
var _last_render_backend = "none"
var _eraser_drawing = false
var _eraser_window_was_focused = true
var _eraser_last_world_position = Vector2.ZERO
var _eraser_level_id = -1
var _eraser_selection_key = ""
var _eraser_world_id = -1
var _eraser_map_file = ""
var _eraser_stroke_by_node_id = {}
var _eraser_gesture_node_ids = []
var _eraser_pending_jobs = {}
var _eraser_job_order = []
var _eraser_job_cursor = 0
var _eraser_job_counter = 0
var _eraser_processed_pixels_total = 0
var _eraser_texture_upload_count = 0
var _eraser_last_frame_processed_pixels = 0
var _eraser_last_frame_usec = 0
var _eraser_last_frame_uploads = 0
var _eraser_last_frame_upload_usec = 0
var _eraser_total_upload_usec = 0
var _eraser_gpu_inflight = false
var _eraser_gpu_token_counter = 0
var _eraser_gpu_active_token = -1
var _eraser_gpu_wait_state = null
var _eraser_last_backend = "none"
var _eraser_gpu_render_count = 0
var _eraser_gpu_total_render_msec = 0.0
var _eraser_gpu_last_render_msec = 0.0
var _eraser_gpu_last_backend = "none"
var _eraser_gpu_last_cpu_composite_frames = 0
var _erase_undo_stack = []
var _shadow_render_cache = {}
var _world_ui_cursor_saved = {}


func start():
	_load_global_settings()
	_cleanup_stale_selection_marks()
	var mod_root = str(Global.Root)
	if not mod_root.ends_with("/"):
		mod_root += "/"
	var renderer_script = ResourceLoader.load(mod_root + "scripts/library/shadow_renderer.gd", "", true)
	var geometry_script = ResourceLoader.load(mod_root + "scripts/library/shadow_geometry.gd", "", true)
	var path_source_script = ResourceLoader.load(mod_root + "scripts/library/path_source.gd", "", true)
	var shadow_mask_script = ResourceLoader.load(mod_root + "scripts/library/shadow_mask.gd", "", true)
	if renderer_script != null:
		_renderer = renderer_script.new()
	if geometry_script != null:
		_geometry = geometry_script.new()
	if path_source_script != null:
		_path_source = path_source_script.new()
	if shadow_mask_script != null:
		_shadow_mask = shadow_mask_script.new()
	if _renderer == null or _geometry == null or _path_source == null or _shadow_mask == null:
		_last_error = "投影功能未能启动，请重新打开地图或检查插件安装。"
		push_error("[contour-shadows] " + _last_error)
	_create_tool_panel()
	print("[contour-shadows] ready; auto-generation is disabled")


func update(delta : float):
	_refresh_map_context()
	_capture_selection_snapshot()
	_sync_selection_highlights()
	_update_selection_label()
	_update_independent_controls()
	_update_multiselect_label()
	_update_eraser_lifecycle()
	_process_eraser_jobs()
	_update_responsive_action_layout()
	if _settings_dirty:
		_settings_save_delay -= delta
		if _settings_save_delay <= 0.0:
			_save_global_settings()
	_process_parameter_refresh(delta)
	if not _generation_queue.empty() and not _generation_in_progress:
		_process_generation_queue()
	if follow_enabled and _generation_queue.empty() and not _generation_in_progress and not _parameter_refresh_pending and _eraser_pending_jobs.empty():
		_follow_delay -= delta
		if _follow_delay <= 0.0:
			_follow_delay = FOLLOW_INTERVAL
			_scan_generated_for_changes()
	_update_status()


func _create_tool_panel():
	var icon_path = Global.Root + "icons/contour_shadows.png"
	_tool_panel = Global.Editor.Toolset.CreateModTool(self, "Effects", TOOL_ID, DISPLAY_NAME, icon_path)
	for property in _tool_panel.get_property_list():
		if str(property.get("name", "")) == "Tool":
			var registered_tool = _tool_panel.get("Tool")
			_attach_controller_meta(registered_tool)
			break
	if Global.Editor.Tools.has(TOOL_ID):
		_attach_controller_meta(Global.Editor.Tools[TOOL_ID])
	_tool_panel.BeginSection(false)

	var target_card = _create_ui_card("目标与生成")
	_selection_label = _new_ui_label("已记录 0 个物件 · 0 条路径", target_card)
	_status_label = _new_ui_label("就绪", target_card)
	_selection_action_row = VBoxContainer.new()
	_selection_action_row.add_constant_override("separation", 4)
	target_card.add_child(_selection_action_row)
	_selection_action_button_a = _create_panel_button("选择对象")
	_selection_action_button_a.connect("pressed", self, "begin_selection_mode")
	_selection_action_button_b = _create_panel_button("生成选中对象")
	_selection_action_button_b.connect("pressed", self, "generate_selected")
	_selection_action_view_a = _reparent_ui_control(_selection_action_button_a, _selection_action_row)
	_selection_action_view_b = _reparent_ui_control(_selection_action_button_b, _selection_action_row)
	var current_button = _create_panel_button("生成当前层", true)
	current_button.connect("pressed", self, "generate_current_level")
	_reparent_ui_control(current_button, target_card)

	var parameter_card = _create_ui_card("投影参数")
	var adjustment_row = HBoxContainer.new()
	adjustment_row.add_constant_override("separation", 4)
	parameter_card.add_child(adjustment_row)
	_global_adjust_button = _create_panel_button("全局调整")
	_global_adjust_button.connect("pressed", self, "set_adjustment_mode", ["global"])
	_individual_adjust_button = _create_panel_button("单独调整")
	_individual_adjust_button.connect("pressed", self, "set_adjustment_mode", ["individual"])
	_reparent_ui_control(_global_adjust_button, adjustment_row)
	_reparent_ui_control(_individual_adjust_button, adjustment_row)
	_scope_label = _new_ui_label("作用范围：全局默认", parameter_card)
	_use_global_button = _create_panel_button("恢复为全局参数", true)
	_use_global_button.connect("pressed", self, "use_global_settings_for_selected")
	_reparent_ui_control(_use_global_button, parameter_card)

	var angle_row = _create_ui_slider_row(parameter_card, "方向 °")
	_angle_value_label = angle_row.get_node("Label")
	_angle_slider = _tool_panel.CreateSlider("", angle_degrees, 0.0, 359.0, 1.0, false)
	_reparent_ui_slider(_angle_slider, angle_row)
	var distance_row = _create_ui_slider_row(parameter_card, "距离 px")
	_distance_value_label = distance_row.get_node("Label")
	_distance_slider = _tool_panel.CreateSlider("", distance, 0.0, 256.0, 1.0, false)
	_reparent_ui_slider(_distance_slider, distance_row)
	var blur_row = _create_ui_slider_row(parameter_card, "柔化 px")
	_blur_value_label = blur_row.get_node("Label")
	_blur_slider = _tool_panel.CreateSlider("", blur_radius, 0.0, 64.0, 0.5, false)
	_reparent_ui_slider(_blur_slider, blur_row)
	var opacity_row = _create_ui_slider_row(parameter_card, "不透明度 %")
	_opacity_value_label = opacity_row.get_node("Label")
	_opacity_slider = _tool_panel.CreateSlider("", opacity * 100.0, 0.0, 100.0, 1.0, false)
	_reparent_ui_slider(_opacity_slider, opacity_row)
	_new_ui_label("投影模式", parameter_card)
	var mode_row = HBoxContainer.new()
	mode_row.add_constant_override("separation", 4)
	mode_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parameter_card.add_child(mode_row)
	_offset_mode_button = _create_panel_button("短投影")
	_sweep_mode_button = _create_panel_button("连续延展")
	_offset_mode_button.connect("pressed", self, "_on_mode_choice_pressed", ["offset"])
	_sweep_mode_button.connect("pressed", self, "_on_mode_choice_pressed", ["sweep"])
	_reparent_ui_control(_offset_mode_button, mode_row)
	_reparent_ui_control(_sweep_mode_button, mode_row)
	_color_palette = _tool_panel.CreateColorPalette("contour_shadows_color", false, shadow_color.to_html(false), ["141519", "202127", "34303a", "51463e", "4c3b34"], false, false)
	_reparent_ui_control(_color_palette, parameter_card)
	_color_label = _new_ui_label("颜色 · #" + shadow_color.to_html(false), parameter_card)

	var eraser_card = _create_ui_card("局部擦除")
	_eraser_button = _tool_panel.CreateCheckButton("启用阴影橡皮擦", "", false)
	_eraser_button.connect("toggled", self, "_on_eraser_toggled")
	_reparent_ui_control(_eraser_button, eraser_card)
	var diameter_row = _create_ui_slider_row(eraser_card, "直径 px")
	_eraser_radius_value_label = diameter_row.get_node("Label")
	_eraser_radius_slider = _tool_panel.CreateSlider("", eraser_radius * 2.0, 2.0, 512.0, 2.0, false)
	_eraser_radius_slider.connect("value_changed", self, "_on_eraser_radius_changed")
	_reparent_ui_slider(_eraser_radius_slider, diameter_row)
	var hardness_row = _create_ui_slider_row(eraser_card, "硬度 %")
	_eraser_hardness_value_label = hardness_row.get_node("Label")
	_eraser_hardness_slider = _tool_panel.CreateSlider("", eraser_hardness * 100.0, 0.0, 100.0, 1.0, false)
	_eraser_hardness_slider.connect("value_changed", self, "_on_eraser_hardness_changed")
	_reparent_ui_slider(_eraser_hardness_slider, hardness_row)
	_new_ui_label("硬度越低边缘越柔；100% 为硬边。", eraser_card)
	var erase_actions = VBoxContainer.new()
	erase_actions.add_constant_override("separation", 4)
	eraser_card.add_child(erase_actions)
	_erase_undo_button = _create_panel_button("撤销上一笔")
	_erase_undo_button.connect("pressed", self, "undo_last_erase")
	_restore_erasures_button = _create_panel_button("恢复选中擦除")
	_restore_erasures_button.connect("pressed", self, "restore_selected_erasures")
	_reparent_ui_control(_erase_undo_button, erase_actions)
	_reparent_ui_control(_restore_erasures_button, erase_actions)

	var advanced_card = _create_ui_card("高级维护")
	_advanced_toggle = _tool_panel.CreateCheckButton("显示高级维护选项", "", false)
	_advanced_toggle.connect("toggled", self, "_on_advanced_toggled")
	_reparent_ui_control(_advanced_toggle, advanced_card)
	_advanced_container = VBoxContainer.new()
	_advanced_container.add_constant_override("separation", 4)
	_advanced_container.visible = false
	advanced_card.add_child(_advanced_container)
	_preview_button = _tool_panel.CreateCheckButton("显示投影预览", "", preview_enabled)
	_preview_button.connect("toggled", self, "_on_preview_toggled")
	_follow_button = _tool_panel.CreateCheckButton("跟随已生成对象", "", follow_enabled)
	_follow_button.connect("toggled", self, "_on_follow_toggled")
	_reparent_ui_control(_preview_button, _advanced_container)
	_reparent_ui_control(_follow_button, _advanced_container)
	var clear_selection_button = _create_panel_button("清除选择记录", true)
	clear_selection_button.connect("pressed", self, "clear_selection_record")
	var exclude_button = _create_panel_button("排除选中目标", true)
	exclude_button.connect("pressed", self, "exclude_selected")
	var restore_button = _create_panel_button("恢复选中目标", true)
	restore_button.connect("pressed", self, "restore_selected")
	_reparent_ui_control(clear_selection_button, _advanced_container)
	_reparent_ui_control(exclude_button, _advanced_container)
	_reparent_ui_control(restore_button, _advanced_container)
	_advanced_container.add_child(HSeparator.new())
	var clean_button = _create_panel_button("清理本层投影", true)
	clean_button.connect("pressed", self, "clear_shadows")
	_reparent_ui_control(clean_button, _advanced_container)
	_tool_panel.EndSection()

	_angle_slider.connect("value_changed", self, "_on_angle_changed")
	_distance_slider.connect("value_changed", self, "_on_distance_changed")
	_blur_slider.connect("value_changed", self, "_on_blur_changed")
	_opacity_slider.connect("value_changed", self, "_on_opacity_changed")
	_update_responsive_action_layout(true)
	_sync_controls()


func _create_ui_card(title : String) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.09, 0.20)
	style.border_color = Color(0.45, 0.45, 0.47, 0.16)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	panel.add_stylebox_override("panel", style)
	var margin = MarginContainer.new()
	margin.add_constant_override("margin_left", 7)
	margin.add_constant_override("margin_top", 3)
	margin.add_constant_override("margin_right", 7)
	margin.add_constant_override("margin_bottom", 3)
	panel.add_child(margin)
	var content = VBoxContainer.new()
	content.add_constant_override("separation", 2)
	margin.add_child(content)
	_tool_panel.Align.add_child(panel)
	_new_ui_label(title, content)
	return content


func _create_ui_slider_row(parent, label_text : String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var label = _new_ui_label(label_text, row)
	label.name = "Label"
	label.autowrap = false
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return row


func _reparent_ui_slider(slider, parent):
	var display_root = _reparent_ui_control(slider, parent)
	if display_root is Control:
		display_root.rect_min_size = Vector2(0.0, 32.0)
		display_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return display_root


func _create_panel_button(label : String, secondary : bool = false):
	# Panel actions use text-only buttons. Keep the Dungeondraft tool icon on the
	# toolbar registration, where it helps identification instead of consuming
	# the height of every action in the narrow side panel.
	var control = _tool_panel.CreateButton(label, "")
	_compact_panel_button_tree(control, secondary)
	return control


func _compact_panel_button_tree(node, secondary : bool = false):
	if not is_instance_valid(node):
		return
	if node is Button:
		node.icon = null
		node.rect_min_size = Vector2(node.rect_min_size.x, 32.0)
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if secondary and _ui_has_property(node, "flat"):
			node.set("flat", true)
	elif node is Control:
		node.rect_min_size = Vector2(node.rect_min_size.x, 0.0)
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for child in node.get_children():
		_compact_panel_button_tree(child, secondary)


func _ui_has_property(object, property_name : String) -> bool:
	if not is_instance_valid(object):
		return false
	for descriptor in object.get_property_list():
		if str(descriptor.get("name", "")) == property_name:
			return true
	return false


func _set_panel_button_text(control, text : String) -> bool:
	if not is_instance_valid(control):
		return false
	if _ui_has_property(control, "text"):
		control.set("text", text)
		return true
	for child in control.get_children():
		if _set_panel_button_text(child, text):
			return true
	return false


func _new_ui_label(label_text : String, parent):
	var label = Label.new()
	label.text = label_text
	label.autowrap = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _reparent_ui_control(control, parent):
	if not is_instance_valid(control) or not is_instance_valid(parent):
		return null
	var display_root = control
	var ancestor = display_root.get_parent()
	while is_instance_valid(ancestor) and ancestor != _tool_panel.Align and _tool_panel.Align.is_a_parent_of(ancestor):
		display_root = ancestor
		ancestor = display_root.get_parent()
	if display_root == parent:
		return display_root
	var current_parent = display_root.get_parent()
	if current_parent == parent:
		return display_root
	if is_instance_valid(current_parent):
		current_parent.remove_child(display_root)
	parent.add_child(display_root)
	if display_root is Control:
		display_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return display_root


func _update_responsive_action_layout(force : bool = false):
	if not is_instance_valid(_tool_panel) or not is_instance_valid(_selection_action_row):
		return
	var width = float(_tool_panel.Align.rect_size.x)
	if not force and abs(width - _last_action_layout_width) < 12.0:
		return
	_last_action_layout_width = width
	var use_horizontal = width >= 220.0
	if use_horizontal == (not _selection_action_row_vertical):
		return
	var old_row = _selection_action_row
	var replacement = HBoxContainer.new() if use_horizontal else VBoxContainer.new()
	replacement.add_constant_override("separation", 4)
	var parent = old_row.get_parent()
	var index = old_row.get_index()
	parent.remove_child(old_row)
	parent.add_child(replacement)
	parent.move_child(replacement, index)
	_move_ui_node(_selection_action_view_a, replacement)
	_move_ui_node(_selection_action_view_b, replacement)
	_selection_action_row = replacement
	_selection_action_row_vertical = not use_horizontal
	old_row.queue_free()


func _move_ui_node(node, parent):
	if not is_instance_valid(node) or not is_instance_valid(parent):
		return
	var current_parent = node.get_parent()
	if current_parent == parent:
		return
	if is_instance_valid(current_parent):
		current_parent.remove_child(node)
	parent.add_child(node)
	if node is Control:
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _attach_controller_meta(target):
	if is_instance_valid(target) and target.has_method("set_meta"):
		target.set_meta("contour_shadows_controller", self)


func _on_angle_changed(value):
	if _syncing_controls:
		return
	_on_parameter_changed("angle", clamp(float(value), 0.0, 359.0))


func _on_distance_changed(value):
	if _syncing_controls:
		return
	_on_parameter_changed("distance", clamp(float(value), 0.0, 256.0))


func _on_blur_changed(value):
	if _syncing_controls:
		return
	_on_parameter_changed("blur_radius", clamp(float(value), 0.0, 64.0))


func _on_opacity_changed(value):
	if _syncing_controls:
		return
	_on_parameter_changed("opacity", clamp(float(value) / 100.0, 0.0, 1.0))


func _on_mode_selected(index):
	if _syncing_controls:
		return
	_on_parameter_changed("mode", "offset" if int(index) == 0 else "sweep")


func _on_mode_choice_pressed(mode : String):
	if _syncing_controls:
		return
	if mode != "offset" and mode != "sweep":
		return
	_on_parameter_changed("mode", mode)


func on_color_change(id_or_value, maybe_color = null):
	# Dungeondraft's ColorPalette dispatches this named tool-script callback;
	# it is not a Godot signal on the returned HBoxContainer.
	if _syncing_controls:
		return
	var value = maybe_color if typeof(maybe_color) == TYPE_COLOR else id_or_value
	if typeof(value) == TYPE_COLOR:
		_on_parameter_changed("color", Color(value.r, value.g, value.b, 1.0))
	elif typeof(value) == TYPE_STRING:
		_on_parameter_changed("color", _parse_color(str(value), shadow_color))


func _on_parameter_changed(key : String, value):
	if adjustment_mode == "individual":
		var applied = apply_to_selected_settings({key: value}, true)
		if not applied.get("ok", false) or applied.has("notice"):
			_sync_controls()
		return
	var options = _normalize_parameter_settings({key: value})
	if options.empty():
		return
	_apply_parameters_to_globals(options)
	_mark_settings_changed()
	_sync_controls()
	if _has_appearance_parameters(options):
		_refresh_enabled_appearance_without_overrides()
	if _has_render_parameters(options):
		_schedule_global_parameter_refresh()


func _apply_parameters_to_globals(options : Dictionary):
	if options.has("angle"):
		angle_degrees = float(options.angle)
	if options.has("distance"):
		distance = float(options.distance)
	if options.has("blur_radius"):
		blur_radius = float(options.blur_radius)
	if options.has("opacity"):
		opacity = float(options.opacity)
	if options.has("mode"):
		shadow_mode = str(options.mode)
	if options.has("color"):
		shadow_color = _parse_color(str(options.color), shadow_color)
	if _color_label != null:
		_color_label.text = "阴影颜色：#" + shadow_color.to_html(false)


func set_adjustment_mode(mode : String) -> Dictionary:
	if not mode in ["global", "individual"]:
		return _operation_error("未知的参数调整模式。")
	if mode == "individual" and _selected_source_ids().empty():
		adjustment_mode = "individual"
		_selection_parameter_key = ""
		_sync_controls()
		return _operation_notice("单独调整需要先记录至少一个本层对象或路径。", "selection_missing")
	adjustment_mode = mode
	_selection_parameter_key = ""
	_sync_controls()
	_settings_dirty = true
	_settings_save_delay = 0.45
	_last_error = ""
	_last_notice = ""
	_last_operation = "已切换到%s调整。" % ("全局" if mode == "global" else "单独")
	return {"ok": true, "mode": adjustment_mode}


func apply_global_settings(options : Dictionary = {}) -> Dictionary:
	_flush_parameter_refresh()
	var normalized = _normalize_parameter_settings(options)
	if normalized.empty():
		return {"ok": true, "queued": 0, "refreshed_candidate_count": 0, "skipped_overrides": 0}
	_apply_parameters_to_globals(normalized)
	_mark_settings_changed()
	_sync_controls()
	var refresh = {"queued": 0, "candidates": 0, "overrides": 0}
	if _has_appearance_parameters(normalized):
		_refresh_enabled_appearance_without_overrides()
	if _has_render_parameters(normalized):
		refresh = _refresh_enabled_without_overrides()
	_last_operation = "全局默认已更新；已排队刷新 %d 个无独立参数的对象/路径" % int(refresh.queued) if int(refresh.queued) > 0 else "全局默认已更新"
	return {"ok": true, "queued": int(refresh.queued), "refreshed_candidate_count": int(refresh.candidates), "skipped_overrides": int(refresh.overrides)}


func apply_to_selected_settings(options : Dictionary, defer_render : bool = false) -> Dictionary:
	var level = _current_level()
	if level == null:
		return _operation_error("没有打开的地图楼层。")
	var sources = _selected_sources(level)
	if sources.empty():
		return _operation_notice("单独调整需要先记录至少一个本层对象或路径；全局默认未更改。", "selection_missing")
	var normalized = _normalize_parameter_settings(options)
	if normalized.empty():
		return {"ok": true, "modified": 0, "queued": 0}
	var modified = 0
	for source in sources:
		var node_id = _stable_node_id(source)
		if node_id < 0:
			continue
		var key = str(node_id)
		var override = _overrides.get(key, _parameter_settings_dictionary()).duplicate(true)
		for setting_key in normalized.keys():
			override[setting_key] = normalized[setting_key]
		_overrides[key] = override
		modified += 1
	var saved = _save_map_recipe()
	var queued = 0
	if _has_appearance_parameters(normalized):
		_apply_appearance_to_sources(sources)
	if _has_render_parameters(normalized):
		if defer_render:
			_schedule_selected_parameter_refresh(sources)
		else:
			_flush_parameter_refresh()
			queued = int(_enqueue_sources(sources, level, "单独调整刷新").get("queued", 0))
	_selection_parameter_key = ""
	_sync_controls()
	_last_operation = "已为 %d 个选中对象/路径设置独立参数；正在刷新" % modified if _has_render_parameters(normalized) else "已为 %d 个选中对象/路径更新外观" % modified
	return {"ok": true, "modified": modified, "queued": int(queued), "map_data_saved": saved}


func _has_appearance_parameters(options : Dictionary) -> bool:
	return options.has("color") or options.has("opacity")


func _has_render_parameters(options : Dictionary) -> bool:
	return options.has("angle") or options.has("distance") or options.has("blur_radius") or options.has("mode")


func _schedule_global_parameter_refresh():
	_parameter_refresh_pending = true
	_parameter_refresh_global = true
	_parameter_refresh_delay = PARAMETER_REFRESH_DEBOUNCE_SECONDS
	_parameter_refresh_event_count += 1
	_last_operation = "参数已更新；松开滑块后刷新投影"


func _schedule_selected_parameter_refresh(sources : Array):
	_parameter_refresh_pending = true
	_parameter_refresh_delay = PARAMETER_REFRESH_DEBOUNCE_SECONDS
	_parameter_refresh_event_count += 1
	for source in sources:
		var node_id = _stable_node_id(source)
		if node_id >= 0:
			_parameter_refresh_node_ids[str(node_id)] = true
	_last_operation = "参数已更新；松开滑块后刷新所选对象"


func _process_parameter_refresh(delta : float) -> bool:
	if not _parameter_refresh_pending:
		return false
	_parameter_refresh_delay -= max(0.0, float(delta))
	if _parameter_refresh_delay > 0.0:
		return false
	# Let the active job finish before coalesced targets are checked against the
	# pending set. Otherwise a slider change can be dropped as a duplicate of the
	# still-running source and leave that source with a stale render.
	if _generation_in_progress:
		return false
	_flush_parameter_refresh()
	return true


func _cancel_parameter_refresh():
	_parameter_refresh_pending = false
	_parameter_refresh_delay = 0.0
	_parameter_refresh_global = false
	_parameter_refresh_node_ids.clear()


func _flush_parameter_refresh() -> Dictionary:
	if not _parameter_refresh_pending:
		return {"queued": 0, "candidates": 0, "overrides": 0}
	var refresh = {"queued": 0, "candidates": 0, "overrides": 0}
	var refresh_global = _parameter_refresh_global
	var refresh_ids = _parameter_refresh_node_ids.keys()
	_cancel_parameter_refresh()
	_parameter_refresh_batch_count += 1
	if refresh_global:
		refresh = _refresh_enabled_without_overrides()
	if not refresh_ids.empty() and is_instance_valid(Global.World):
		var level = _current_level()
		if level != null:
			for node_key in refresh_ids:
				var source = Global.World.GetNodeByID(int(node_key))
				if _is_source_node(source) and _source_is_on_level(source, level) and not _excluded_node_ids.has(str(node_key)):
					refresh.candidates += 1
					if _queue_source(source, level, int(node_key), "参数调整刷新"):
						refresh.queued += 1
	if int(refresh.queued) > 0:
		_last_generated = 0
		_queue_completion_label = "参数调整刷新"
		_last_operation = "参数已合并；正在刷新 %d 个对象/路径" % int(refresh.queued)
	elif not _generation_queue.empty() or _generation_in_progress:
		_last_operation = "参数已合并；目标已在生成队列中"
	else:
		_last_operation = "参数已合并；没有需要刷新的已生成对象"
	return refresh


func _refresh_enabled_appearance_without_overrides():
	if not is_instance_valid(Global.World):
		return
	var sources = []
	for node_id in _sorted_node_ids(_enabled_node_ids):
		var key = str(int(node_id))
		if _overrides.has(key) or _excluded_node_ids.has(key):
			continue
		var source = Global.World.GetNodeByID(int(node_id))
		if _is_source_node(source):
			sources.append(source)
	_apply_appearance_to_sources(sources)


func _apply_appearance_to_sources(sources : Array):
	for source in sources:
		var node_id = _stable_node_id(source)
		if node_id < 0:
			continue
		var wrapper = _find_shadow(source)
		if wrapper == null:
			continue
		var shadow_sprite = null
		for child in wrapper.get_children():
			if child is Sprite:
				shadow_sprite = child
				break
		if shadow_sprite == null:
			continue
		var settings = get_effective_settings(node_id)
		var source_sprite = _source_sprite_for_source(source)
		var source_alpha = source_sprite.modulate.a if is_instance_valid(source_sprite) else 1.0
		var color = _parse_color(str(settings.get("color", shadow_color.to_html(false))), shadow_color)
		shadow_sprite.modulate = Color(color.r, color.g, color.b, float(settings.get("opacity", opacity)) * source_alpha)


func use_global_settings_for_selected() -> Dictionary:
	var level = _current_level()
	if level == null:
		return _operation_error("没有打开的地图楼层。")
	var sources = _selected_sources(level)
	if sources.empty():
		return _operation_notice("请先记录要恢复为全局参数的对象或路径。", "selection_missing")
	var removed = 0
	for source in sources:
		var node_id = _stable_node_id(source)
		if node_id < 0:
			continue
		var key = str(node_id)
		if _overrides.has(key):
			_overrides.erase(key)
			removed += 1
	var saved = _save_map_recipe()
	var queued = _enqueue_sources(sources, level, "使用全局参数").get("queued", 0)
	_selection_parameter_key = ""
	_sync_controls()
	_last_operation = "已移除 %d 个独立参数；正在按全局参数刷新" % removed
	return {"ok": true, "restored": removed, "queued": int(queued), "map_data_saved": saved}


func _refresh_enabled_without_overrides() -> Dictionary:
	var queued = 0
	var candidates = 0
	var override_count = 0
	if not is_instance_valid(Global.World):
		return {"queued": 0, "candidates": 0, "overrides": 0}
	for node_id in _sorted_node_ids(_enabled_node_ids):
		var key = str(int(node_id))
		if _overrides.has(key):
			override_count += 1
			continue
		if _excluded_node_ids.has(key):
			continue
		var source = Global.World.GetNodeByID(int(node_id))
		var level = _level_for_source(source) if _is_source_node(source) else null
		if level == null:
			continue
		candidates += 1
		if _queue_source(source, level, int(node_id), "全局参数刷新"):
			queued += 1
	if queued > 0:
		_last_generated = 0
		_queue_completion_label = "全局参数刷新"
	return {"queued": queued, "candidates": candidates, "overrides": override_count}


func get_effective_settings(node_id : int) -> Dictionary:
	var result = _parameter_settings_dictionary()
	var override = _overrides.get(str(int(node_id)), {})
	if typeof(override) == TYPE_DICTIONARY:
		for key in override.keys():
			result[key] = override[key]
	return result


func _selected_source_ids() -> Array:
	var level = _current_level()
	if level == null:
		return []
	var result = []
	for source in _selected_sources(level):
		var node_id = _stable_node_id(source)
		if node_id >= 0 and not result.has(node_id):
			result.append(node_id)
	result.sort()
	return result


func _update_independent_controls():
	if _scope_label == null:
		return
	if adjustment_mode != "individual":
		_scope_label.text = "作用范围：全局默认"
		return
	var selection_key = PoolStringArray(_selected_source_ids()).join(",")
	if selection_key != _selection_parameter_key:
		_selection_parameter_key = selection_key
		_sync_controls()
	if selection_key == "":
		_scope_label.text = "作用范围：单独调整 · 尚无目标；全局默认不变"
	else:
		_scope_label.text = "作用范围：单独调整 · 修改将应用到 %d 个目标" % _selected_source_ids().size()


func _update_multiselect_label():
	if adjustment_mode != "individual" or _scope_label == null:
		return
	var selected_ids = _selected_source_ids()
	if selected_ids.empty():
		return
	var varied = []
	var keys = ["angle", "distance", "blur_radius", "opacity", "mode", "color"]
	var labels = {"angle": "角度", "distance": "距离", "blur_radius": "模糊", "opacity": "不透明度", "mode": "模式", "color": "颜色"}
	var first = get_effective_settings(int(selected_ids[0]))
	for key in keys:
		var first_value = first.get(key, null)
		for index in range(1, selected_ids.size()):
			var current = get_effective_settings(int(selected_ids[index])).get(key, null)
			var different = abs(float(first_value) - float(current)) > 0.0001 if typeof(first_value) in [TYPE_INT, TYPE_REAL] and typeof(current) in [TYPE_INT, TYPE_REAL] else first_value != current
			if different:
				varied.append(labels[key])
				break
	var message = "作用范围：单独调整 · %d 个目标；显示第一个值" % selected_ids.size()
	if not varied.empty():
		message += " · 混合值：" + PoolStringArray(varied).join("、")
	_scope_label.text = message


func _on_follow_toggled(value):
	if _syncing_controls:
		return
	follow_enabled = bool(value)
	_follow_delay = 0.0
	_mark_settings_changed()


func _on_advanced_toggled(value):
	if _advanced_container != null:
		_advanced_container.visible = bool(value)


func _on_preview_toggled(value):
	if _syncing_controls:
		return
	preview_enabled = bool(value)
	_set_preview_on_all_levels(preview_enabled)
	_mark_settings_changed()


func _mark_settings_changed():
	_settings_dirty = true
	_settings_save_delay = 0.45
	if _save_map_recipe():
		_last_error = ""


func _load_global_settings():
	angle_degrees = 45.0
	distance = 32.0
	blur_radius = 8.0
	opacity = 0.30
	shadow_mode = "sweep"
	shadow_color = Color(0.08, 0.08, 0.09, 1.0)
	follow_enabled = false
	preview_enabled = true
	adjustment_mode = "global"
	eraser_radius = ERASER_DEFAULT_RADIUS
	eraser_hardness = 0.7
	var file = File.new()
	if file.open(SETTINGS_PATH, File.READ) != OK:
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	var data = parsed.result
	angle_degrees = _number_setting(data, "angle", angle_degrees, 0.0, 359.0)
	distance = _number_setting(data, "distance", distance, 0.0, 256.0)
	blur_radius = _number_setting(data, "blur_radius", blur_radius, 0.0, 64.0)
	opacity = _number_setting(data, "opacity", opacity, 0.0, 1.0)
	var loaded_mode = str(data.get("mode", shadow_mode))
	shadow_mode = loaded_mode if loaded_mode in ["offset", "sweep"] else "sweep"
	var color_text = str(data.get("color", shadow_color.to_html(false)))
	shadow_color = _parse_color(color_text, shadow_color)
	follow_enabled = bool(data.get("follow", follow_enabled))
	preview_enabled = bool(data.get("preview", preview_enabled))
	var loaded_adjustment_mode = str(data.get("adjustment_mode", adjustment_mode))
	adjustment_mode = loaded_adjustment_mode if loaded_adjustment_mode in ["global", "individual"] else "global"
	eraser_radius = _number_setting(data, "eraser_radius", eraser_radius, 1.0, 256.0)
	eraser_hardness = _number_setting(data, "eraser_hardness", eraser_hardness, 0.0, 1.0)


func _number_setting(data : Dictionary, key : String, fallback : float, minimum : float, maximum : float) -> float:
	var value = data.get(key, fallback)
	if not (typeof(value) in [TYPE_INT, TYPE_REAL]):
		return fallback
	return clamp(float(value), minimum, maximum)


func _parse_color(value : String, fallback : Color) -> Color:
	var text = value.strip_edges()
	if text == "":
		return fallback
	if not text.begins_with("#"):
		text = "#" + text
	return Color(text)


func _save_global_settings():
	var directory = Directory.new()
	if not directory.dir_exists("user://contour_shadows"):
		directory.make_dir_recursive("user://contour_shadows")
	var data = _settings_dictionary()
	data["adjustment_mode"] = adjustment_mode
	data["eraser_radius"] = eraser_radius
	data["eraser_hardness"] = eraser_hardness
	var file = File.new()
	if file.open(SETTINGS_PATH, File.WRITE) == OK:
		file.store_line(JSON.print(data, "\t"))
		file.close()
		_settings_dirty = false
	else:
		_last_error = "无法保存 user://contour_shadows/settings.json"



func _load_map_recipe():
	_enabled_node_ids.clear()
	_excluded_node_ids.clear()
	_overrides.clear()
	_erasures.clear()
	_recipe_extra_fields.clear()
	_recipe_extra_settings.clear()
	_map_recipe_writable = true
	if typeof(Global.ModMapData) != TYPE_DICTIONARY:
		return false
	if not Global.ModMapData.has(MAP_DATA_KEY):
		return false
	var saved = Global.ModMapData.get(MAP_DATA_KEY, {})
	if typeof(saved) != TYPE_DICTIONARY:
		return false
	var recipe_version = int(saved.get("version", 1))
	if recipe_version < 1 or recipe_version > RECIPE_VERSION:
		_map_recipe_writable = false
		_last_error = "地图中的轮廓投影设置版本 %d 暂不受支持；已保留原数据。" % recipe_version
		return false
	var enabled_ids = saved.get("enabled_node_ids", [])
	var excluded_ids = saved.get("excluded_node_ids", [])
	if typeof(enabled_ids) == TYPE_ARRAY:
		for value in enabled_ids:
			if typeof(value) in [TYPE_INT, TYPE_REAL] and int(value) >= 0:
				_enabled_node_ids[str(int(value))] = true
	if typeof(excluded_ids) == TYPE_ARRAY:
		for value in excluded_ids:
			if typeof(value) in [TYPE_INT, TYPE_REAL] and int(value) >= 0:
				_excluded_node_ids[str(int(value))] = true
	for key in _excluded_node_ids.keys():
		_enabled_node_ids.erase(key)
	var saved_settings = saved.get("settings", {})
	if typeof(saved_settings) == TYPE_DICTIONARY:
		_apply_settings(saved_settings)
		for setting_key in saved_settings.keys():
			if not str(setting_key) in ["angle", "distance", "blur_radius", "opacity", "mode", "color", "follow", "preview"]:
				_recipe_extra_settings[setting_key] = saved_settings[setting_key]
	if recipe_version >= 2:
		var saved_overrides = saved.get("overrides", {})
		if typeof(saved_overrides) == TYPE_DICTIONARY:
			for key in saved_overrides.keys():
				if int(key) < 0 or typeof(saved_overrides[key]) != TYPE_DICTIONARY:
					continue
				var normalized = _parameter_settings_dictionary()
				var normalized_override = _normalize_parameter_settings(saved_overrides[key])
				for setting_key in normalized_override.keys():
					normalized[setting_key] = normalized_override[setting_key]
				if not normalized.empty():
					_overrides[str(int(key))] = normalized
		var saved_erasures = saved.get("erasures", {})
		if typeof(saved_erasures) == TYPE_DICTIONARY:
			for key in saved_erasures.keys():
				if int(key) >= 0 and typeof(saved_erasures[key]) == TYPE_ARRAY and not saved_erasures[key].empty():
					_erasures[str(int(key))] = saved_erasures[key].duplicate(true)
	for field in saved.keys():
		if not str(field) in ["version", "settings", "enabled_node_ids", "excluded_node_ids", "overrides", "erasures"]:
			_recipe_extra_fields[field] = saved[field]
	if recipe_version == 1:
		# Preserve all v1 data and upgrade the schema in memory before the next save.
		Global.ModMapData[MAP_DATA_KEY] = saved.duplicate(true)
		Global.ModMapData[MAP_DATA_KEY]["version"] = RECIPE_VERSION
		Global.ModMapData[MAP_DATA_KEY]["overrides"] = {}
		Global.ModMapData[MAP_DATA_KEY]["erasures"] = {}
		_save_map_recipe()
	_sync_controls()
	return true


func _save_map_recipe() -> bool:
	if not _map_recipe_writable:
		_last_error = "地图中的轮廓投影设置版本暂不受支持；原数据已保留。"
		return false
	if typeof(Global.ModMapData) != TYPE_DICTIONARY:
		_last_error = "地图设置暂时无法保存。"
		return false
	var recipe = _recipe_extra_fields.duplicate(true)
	recipe["version"] = RECIPE_VERSION
	recipe["settings"] = _settings_dictionary()
	recipe["enabled_node_ids"] = _sorted_node_ids(_enabled_node_ids)
	recipe["excluded_node_ids"] = _sorted_node_ids(_excluded_node_ids)
	recipe["overrides"] = _serialize_overrides()
	recipe["erasures"] = _serialize_erasures()
	Global.ModMapData[MAP_DATA_KEY] = recipe
	return true


func _serialize_overrides() -> Dictionary:
	var result = {}
	for key in _overrides.keys():
		if typeof(_overrides[key]) == TYPE_DICTIONARY and not _overrides[key].empty():
			result[str(int(key))] = _overrides[key].duplicate(true)
	return result


func _serialize_erasures() -> Dictionary:
	var result = {}
	for key in _erasures.keys():
		if typeof(_erasures[key]) == TYPE_ARRAY and not _erasures[key].empty():
			result[str(int(key))] = _erasures[key].duplicate(true)
	return result


func _sorted_node_ids(source : Dictionary) -> Array:
	var result = []
	for key in source.keys():
		var parsed_id = int(key)
		if parsed_id >= 0:
			result.append(parsed_id)
	result.sort()
	return result


func _settings_dictionary() -> Dictionary:
	var settings = {
		"angle": angle_degrees,
		"distance": distance,
		"blur_radius": blur_radius,
		"opacity": opacity,
		"mode": shadow_mode,
		"color": shadow_color.to_html(false),
		"follow": follow_enabled,
		"preview": preview_enabled
	}
	for setting_key in _recipe_extra_settings.keys():
		settings[setting_key] = _recipe_extra_settings[setting_key]
	return settings


func _parameter_settings_dictionary() -> Dictionary:
	return {
		"angle": angle_degrees,
		"distance": distance,
		"blur_radius": blur_radius,
		"opacity": opacity,
		"mode": shadow_mode,
		"color": shadow_color.to_html(false)
	}


func _normalize_parameter_settings(data : Dictionary) -> Dictionary:
	var result = {}
	if data.has("angle"):
		result["angle"] = _number_setting(data, "angle", angle_degrees, 0.0, 359.0)
	if data.has("distance"):
		result["distance"] = _number_setting(data, "distance", distance, 0.0, 256.0)
	if data.has("blur_radius"):
		result["blur_radius"] = _number_setting(data, "blur_radius", blur_radius, 0.0, 64.0)
	if data.has("opacity"):
		result["opacity"] = _number_setting(data, "opacity", opacity, 0.0, 1.0)
	if data.has("mode"):
		var mode = str(data.get("mode", ""))
		if mode in ["offset", "sweep"]:
			result["mode"] = mode
	if data.has("color"):
		var color_value = data.color
		var parsed_color = color_value if typeof(color_value) == TYPE_COLOR else _parse_color(str(color_value), shadow_color)
		result["color"] = parsed_color.to_html(false)
	return result


func _apply_settings(data : Dictionary):
	angle_degrees = _number_setting(data, "angle", angle_degrees, 0.0, 359.0)
	distance = _number_setting(data, "distance", distance, 0.0, 256.0)
	blur_radius = _number_setting(data, "blur_radius", blur_radius, 0.0, 64.0)
	opacity = _number_setting(data, "opacity", opacity, 0.0, 1.0)
	var loaded_mode = str(data.get("mode", shadow_mode))
	shadow_mode = loaded_mode if loaded_mode in ["offset", "sweep"] else "sweep"
	shadow_color = _parse_color(str(data.get("color", shadow_color.to_html(false))), shadow_color)
	follow_enabled = bool(data.get("follow", follow_enabled))
	preview_enabled = bool(data.get("preview", preview_enabled))


func _refresh_map_context():
	if not is_instance_valid(Global.World):
		return
	var current_world_id = int(Global.World.get_instance_id())
	if current_world_id == _world_instance_id:
		return
	if _settings_dirty:
		_save_global_settings()
	_cancel_parameter_refresh()
	# The host has already switched its live ModMapData by the time this is
	# detected. Close the gesture without writing the old map into the new one.
	_finish_eraser_stroke(true, false)
	_cancel_all_eraser_jobs()
	eraser_enabled = false
	_eraser_level_id = -1
	_eraser_selection_key = ""
	_eraser_world_id = -1
	_eraser_map_file = ""
	_restore_world_ui_cursor()
	if not _settings_dirty:
		_last_error = ""
	_world_instance_id = current_world_id
	_generation_queue.clear()
	_pending_node_ids.clear()
	_generation_epoch += 1
	_generation_in_progress = false
	_active_generation_token = -1
	_active_generation_level_id = -1
	_active_generation_node_key = ""
	_generated_fingerprints.clear()
	_shadow_render_cache.clear()
	_erase_undo_stack.clear()
	_clear_selection_snapshot()
	_enabled_node_ids.clear()
	_excluded_node_ids.clear()
	_overrides.clear()
	_erasures.clear()
	if not _load_map_recipe():
		_load_global_settings()
		_sync_controls()
		return
	_restore_enabled_objects()


func _restore_enabled_objects():
	if not is_instance_valid(Global.World):
		return
	var restored_sources = []
	var recipe_changed = false
	for key in _enabled_node_ids.keys():
		var node_id = int(key)
		var source = Global.World.GetNodeByID(node_id)
		if not _is_source_node(source) or _excluded_node_ids.has(key):
			_enabled_node_ids.erase(key)
			recipe_changed = true
			continue
		var level = _level_for_source(source)
		if level == null:
			continue
		if _queue_source(source, level, node_id, "重开地图恢复"):
			restored_sources.append(source)
	if recipe_changed:
		_save_map_recipe()
	if not restored_sources.empty():
		_last_generated = 0
		_last_skipped = 0
		_queue_completion_label = "重开地图恢复"
		_last_operation = "重开地图：已排队恢复 %d 个轮廓投影" % restored_sources.size()
	else:
		_last_operation = "地图设置已载入；尚未生成投影"


func generate_current_level() -> Dictionary:
	var level = _current_level()
	if level == null:
		return _operation_error("没有打开的地图楼层。")
	return _enqueue_sources(_level_sources(level), level, "当前层")


func generate_selected() -> Dictionary:
	var level = _current_level()
	if level == null:
		return _operation_error("没有打开的地图楼层。")
	var sources = _selected_sources(level)
	if sources.empty():
		return _operation_notice("请先用选择工具选中本层物件或路径，再生成投影。", "selection_missing")
	return _enqueue_sources(sources, level, "选中对象")


func begin_selection_mode() -> Dictionary:
	if not is_instance_valid(Global.Editor):
		return _operation_error("当前无法打开选择工具。")
	if not Global.Editor.has_method("OnSelectTool"):
		return _operation_error("当前版本无法打开选择工具。")
	_last_error = ""
	_last_notice = "先在地图上选取本层物件，再回到轮廓投影。"
	_last_operation = "已打开选择工具；选好对象后回到轮廓投影。"
	Global.Editor.call("OnSelectTool", "SelectTool")
	return {"ok": true, "tool": "SelectTool"}


func clear_selection_record() -> Dictionary:
	_selection_record_cleared = true
	_clear_selection_snapshot()
	var select_tool = null
	if is_instance_valid(Global.Editor) and Global.Editor.Tools.has("SelectTool"):
		select_tool = Global.Editor.Tools["SelectTool"]
	var live_selection_cleared = false
	if is_instance_valid(select_tool):
		if select_tool.has_method("DeselectAllEx"):
			select_tool.call("DeselectAllEx")
			live_selection_cleared = true
		elif select_tool.has_method("DeselectAll"):
			select_tool.call("DeselectAll")
			live_selection_cleared = true
	_sync_selection_highlights()
	_last_selected_prop_count = 0
	_last_selection_source = "none"
	_last_notice = "已清除选择记录。"
	_last_error = ""
	_last_operation = "已清除选择记录。"
	return {"ok": true, "cleared": true, "live_selection_cleared": live_selection_cleared}


func exclude_selected() -> Dictionary:
	var level = _current_level()
	if level == null:
		return _operation_error("没有打开的地图楼层。")
	_finish_eraser_stroke(true)
	var count = 0
	var sources = _selected_sources(level)
	if sources.empty():
		return _operation_notice("请先用选择工具选中本层物件或路径，再执行此操作。", "selection_missing")
	for source in sources:
		var node_id = _stable_node_id(source)
		if node_id < 0:
			continue
		var key = str(node_id)
		_cancel_eraser_jobs_for_node(key)
		_excluded_node_ids[key] = true
		_enabled_node_ids.erase(key)
		_remove_shadow(source)
		_generated_fingerprints.erase(key)
		_shadow_render_cache.erase(key)
		_cancel_queued_node(key)
		count += 1
	var map_data_saved = _save_map_recipe()
	_last_operation = "已排除 %d 个选中对象" % count
	if map_data_saved:
		_last_error = ""
	return {"ok": true, "excluded": count, "map_data_saved": map_data_saved}


func restore_selected() -> Dictionary:
	var level = _current_level()
	if level == null:
		return _operation_error("没有打开的地图楼层。")
	var sources = _selected_sources(level)
	if sources.empty():
		return _operation_notice("请先用选择工具选中本层物件或路径，再执行此操作。", "selection_missing")
	var count = 0
	for source in sources:
		var node_id = _stable_node_id(source)
		if node_id < 0:
			continue
		var key = str(node_id)
		if _excluded_node_ids.has(key):
			_excluded_node_ids.erase(key)
			count += 1
	var map_data_saved = _save_map_recipe()
	var queued = _enqueue_sources(sources, level, "恢复选中对象")
	_last_operation = "已恢复 %d 个对象；正在生成选中投影" % count
	if not map_data_saved:
		_last_error = "地图设置暂时无法保存。"
	return {"ok": true, "restored": count, "queued": queued.get("queued", 0), "map_data_saved": map_data_saved}


func clear_shadows() -> Dictionary:
	var level = _current_level()
	if level == null:
		return _operation_error("没有打开的地图楼层。")
	_flush_parameter_refresh()
	_finish_eraser_stroke(true)
	var removed = 0
	for source in _level_sources(level):
		if _remove_shadow(source):
			removed += 1
		var node_id = _stable_node_id(source)
		if node_id >= 0:
			var key = str(node_id)
			_cancel_eraser_jobs_for_node(key)
			_generated_fingerprints.erase(key)
			_shadow_render_cache.erase(key)
			_enabled_node_ids.erase(key)
	_cancel_queued_level(int(level.ID))
	var map_data_saved = _save_map_recipe()
	_last_removed = removed
	_last_operation = "已清理当前层 %d 个轮廓投影" % removed
	if map_data_saved:
		_last_error = ""
	return {"ok": true, "removed": removed, "level_id": int(level.ID), "map_data_saved": map_data_saved}


func set_preview(value : bool) -> Dictionary:
	preview_enabled = bool(value)
	_set_preview_on_all_levels(preview_enabled)
	_mark_settings_changed()
	return {"ok": true, "preview": preview_enabled}


func configure(options : Dictionary) -> Dictionary:
	_flush_parameter_refresh()
	var parameter_options = _normalize_parameter_settings(options)
	_apply_parameters_to_globals(parameter_options)
	if options.has("follow"):
		follow_enabled = bool(options.follow)
	if options.has("preview"):
		preview_enabled = bool(options.preview)
		_set_preview_on_all_levels(preview_enabled)
	_mark_settings_changed()
	_sync_controls()
	if _has_appearance_parameters(parameter_options):
		_refresh_enabled_appearance_without_overrides()
	if _has_render_parameters(parameter_options):
		_refresh_enabled_without_overrides()
	return get_diagnostics()


func _enqueue_sources(sources : Array, level, label : String) -> Dictionary:
	var queued = 0
	var skipped = 0
	for source in sources:
		if not _is_source_node(source):
			skipped += 1
			continue
		var node_id = _stable_node_id(source)
		if node_id < 0:
			skipped += 1
			continue
		var key = str(node_id)
		if _excluded_node_ids.has(key):
			skipped += 1
			continue
		if _queue_source(source, level, node_id, label):
			queued += 1
	_last_skipped = skipped
	_last_generated = 0
	_last_notice = ""
	_queue_completion_label = label
	_last_operation = "%s：已排队 %d 个对象/路径" % [label, queued] if queued > 0 else "%s：没有需要生成的对象/路径" % label
	_last_error = ""
	return {"ok": true, "queued": queued, "skipped": skipped, "level_id": int(level.ID)}


func _enqueue_props(props : Array, level, label : String) -> Dictionary:
	return _enqueue_sources(props, level, label)


func _queue_source(source, level, node_id : int, label : String) -> bool:
	var key = str(node_id)
	if _pending_node_ids.has(key):
		return false
	if _generation_queue.empty() and not _generation_in_progress:
		_generation_batch_total = 0
		_generation_batch_done = 0
	_pending_node_ids[key] = true
	_generation_queue.append({
		"source": source, "prop": source, "level": level, "node_id": node_id,
		"level_id": int(level.ID), "label": label, "epoch": _generation_epoch,
		"world_id": int(Global.World.get_instance_id()) if is_instance_valid(Global.World) else -1,
		"map_file": _current_map_file()
	})
	_generation_batch_total += 1
	return true


func _queue_prop(prop, level, node_id : int, label : String) -> bool:
	return _queue_source(prop, level, node_id, label)


func _process_generation_queue():
	if _generation_in_progress or _generation_queue.empty():
		return
	var item = _generation_queue.pop_front()
	var key = str(item.node_id)
	var level = item.get("level", null)
	if not is_instance_valid(level):
		level = _level_by_id(int(item.level_id))
	var source = item.get("source", item.get("prop", null))
	if not is_instance_valid(level) or not _is_source_node(source) or not _source_is_on_level(source, level):
		_pending_node_ids.erase(key)
		_generation_batch_done += 1
		return
	if _stable_node_id(source) != int(item.node_id) or _excluded_node_ids.has(key):
		_pending_node_ids.erase(key)
		_generation_batch_done += 1
		return
	_generation_job_counter += 1
	item["job_token"] = _generation_job_counter
	item["source_signature"] = _source_signature(source)
	_active_generation_level_id = int(level.ID)
	_active_generation_node_key = key
	_generation_in_progress = true
	_active_generation_token = _generation_job_counter
	# Keep CPU-only Prop test doubles synchronous; the installed production renderer
	# always takes the async path. Path capture remains async in either case.
	if not _is_pathway_source(source) and (_renderer == null or not _renderer.has_method("render_async")):
		var cpu_result = _generate_prop(source, int(item.node_id))
		_pending_node_ids.erase(key)
		_complete_generation_item(source, int(item.node_id), cpu_result, str(item.get("label", "生成")), str(item.get("source_signature", "")))
		_clear_active_generation_job(int(item.job_token))
		return
	var result_or_state = _generate_source_async(item, level, source)
	if result_or_state is GDScriptFunctionState:
		_await_generation_job(result_or_state, item, level, source)
		return
	_finish_generation_job(item, level, source, result_or_state)


func _await_generation_job(job_state : GDScriptFunctionState, item : Dictionary, level, source):
	var result = yield(job_state, "completed")
	if typeof(result) != TYPE_DICTIONARY:
		result = {"ok": false, "error": "异步投影任务没有返回有效结果。"}
	_finish_generation_job(item, level, source, result)


func _generate_source_async(item : Dictionary, level, source):
	var node_id = int(item.node_id)
	var capture = {}
	if _is_pathway_source(source):
		var capture_or_state = _path_source.capture(source, level)
		if capture_or_state is GDScriptFunctionState:
			capture = yield(capture_or_state, "completed")
		else:
			capture = capture_or_state
		if not _is_generation_item_current(item, source, level):
			return {"ok": false, "cancelled": true}
	else:
		capture = _capture_prop_source(source)
	if typeof(capture) != TYPE_DICTIONARY:
		if is_instance_valid(source):
			_remove_shadow(source)
		return {"ok": false, "error": "源对象捕获没有返回有效结果。"}
	if not capture.get("ok", false):
		if is_instance_valid(source):
			_remove_shadow(source)
		return {"ok": false, "error": str(capture.get("error", "无法捕获投影源图像。"))}
	if not _source_signature_matches_item(item, source):
		return {"ok": false, "retry": true}
	var prepared = _prepare_render_from_capture(source, node_id, capture)
	if not prepared.get("ok", false):
		_remove_shadow(source)
		return prepared
	var started_usec = OS.get_ticks_usec()
	var rendered = null
	if _renderer.has_method("render_async"):
		var render_state = _renderer.call(
			"render_async", prepared.image, prepared.displacement, prepared.blur_radius,
			str(prepared.settings.mode), ALPHA_CUTOFF, MAX_RENDER_SIZE, source
		)
		if render_state is GDScriptFunctionState:
			rendered = yield(render_state, "completed")
		else:
			rendered = render_state
	else:
		# Test doubles and older renderer scripts retain a deterministic CPU fallback.
		rendered = _renderer.render(prepared.image, prepared.displacement, prepared.blur_radius, str(prepared.settings.mode), ALPHA_CUTOFF, MAX_RENDER_SIZE)
	var measured_msec = float(OS.get_ticks_usec() - started_usec) / 1000.0
	_last_render_msec = float(rendered.get("elapsed_ms", measured_msec)) if typeof(rendered) == TYPE_DICTIONARY else measured_msec
	_total_render_msec += _last_render_msec
	_render_count_total += 1
	_last_render_backend = str(rendered.get("backend", "cpu_sync" if not _renderer.has_method("render_async") else "gpu_async")) if typeof(rendered) == TYPE_DICTIONARY else "unknown"
	if not _is_generation_item_current(item, source, level):
		return {"ok": false, "cancelled": true}
	if not _source_signature_matches_item(item, source):
		return {"ok": false, "retry": true}
	# Color/opacity are appearance-only and deliberately do not enter the shape
	# signature, so read their latest values when the image is installed.
	return _install_render_result(source, node_id, capture, get_effective_settings(node_id), rendered)


func _finish_generation_job(item : Dictionary, level, source, result : Dictionary):
	var node_id = int(item.node_id)
	var key = str(node_id)
	var token = int(item.get("job_token", -1))
	if token != _active_generation_token:
		return
	_pending_node_ids.erase(key)
	if result.get("cancelled", false):
		_generation_batch_done += 1
		_clear_active_generation_job(token)
		return
	if result.get("retry", false) and _is_source_node(source) and is_instance_valid(level) and _source_is_on_level(source, level) and not _excluded_node_ids.has(key):
		_generation_batch_done += 1
		_clear_active_generation_job(token)
		if _queue_source(source, level, node_id, str(item.get("label", "生成"))):
			_last_operation = "目标在生成期间发生变化，已重新排队刷新"
		return
	_complete_generation_item(source, node_id, result, str(item.get("label", "生成")), str(item.get("source_signature", "")))
	_clear_active_generation_job(token)


func _clear_active_generation_job(token : int):
	if token != _active_generation_token:
		return
	_active_generation_level_id = -1
	_active_generation_node_key = ""
	_generation_in_progress = false
	_active_generation_token = -1


func _is_generation_item_current(item : Dictionary, source, level) -> bool:
	var job_token = int(item.get("job_token", -1))
	if job_token >= 0 and job_token != _active_generation_token:
		return false
	if int(item.get("epoch", -1)) != _generation_epoch:
		return false
	if not is_instance_valid(Global.World) or int(item.get("world_id", -1)) != int(Global.World.get_instance_id()):
		return false
	if str(item.get("map_file", "")) != _current_map_file():
		return false
	if not is_instance_valid(source) or not is_instance_valid(level) or not source.is_inside_tree():
		return false
	var key = str(item.get("node_id", -1))
	return _pending_node_ids.has(key) and _stable_node_id(source) == int(item.get("node_id", -1)) and _source_is_on_level(source, level)


func _source_signature_matches_item(item : Dictionary, source) -> bool:
	var expected = str(item.get("source_signature", ""))
	return expected == "" or _source_signature(source) == expected


func _generate_prop(prop, node_id : int) -> Dictionary:
	var capture = _capture_prop_source(prop)
	if not capture.get("ok", false):
		_remove_shadow(prop)
		return capture
	return _generate_source_from_capture(prop, node_id, capture)


func _capture_prop_source(prop) -> Dictionary:
	var sprite = _prop_sprite(prop)
	if not is_instance_valid(sprite) or not (sprite is Sprite) or sprite.texture == null:
		return {"ok": false, "error": "无法读取该物件的图像。"}
	var extracted = _get_cached_sprite_image(sprite)
	if typeof(extracted) != TYPE_DICTIONARY or not extracted.get("ok", false):
		return {"ok": false, "error": str(extracted.get("error", "无法读取该物件的图像。"))}
	var pixel_to_local = sprite.transform * Transform2D(Vector2(1.0, 0.0), Vector2(0.0, 1.0), extracted.rect.position)
	return {
		"ok": true,
		"image": extracted.image,
		"rect": extracted.rect,
		"pixel_scale": 1.0,
		"pixel_to_local": pixel_to_local,
		"kind": "prop",
		"source_sprite": sprite
	}


func _generate_source_from_capture(source, node_id : int, capture : Dictionary) -> Dictionary:
	var prepared = _prepare_render_from_capture(source, node_id, capture)
	if not prepared.get("ok", false):
		_remove_shadow(source)
		return prepared
	var render_started_usec = OS.get_ticks_usec()
	var rendered = _renderer.render(prepared.image, prepared.displacement, prepared.blur_radius, str(prepared.settings.mode), ALPHA_CUTOFF, MAX_RENDER_SIZE)
	_last_render_msec = float(OS.get_ticks_usec() - render_started_usec) / 1000.0
	_total_render_msec += _last_render_msec
	_render_count_total += 1
	_last_render_backend = str(rendered.get("backend", "cpu_sync")) if typeof(rendered) == TYPE_DICTIONARY else "unknown"
	return _install_render_result(source, node_id, capture, prepared.settings, rendered)


func _prepare_render_from_capture(source, node_id : int, capture : Dictionary) -> Dictionary:
	if _renderer == null or _geometry == null or _shadow_mask == null:
		return {"ok": false, "error": "投影功能暂不可用，请重新打开地图或检查插件安装。"}
	var source_image = capture.get("image", null)
	var pixel_to_local = capture.get("pixel_to_local", Transform2D())
	if not (source_image is Image) or source_image.is_empty():
		return {"ok": false, "error": "没有有效的投影源图像。"}
	var settings = get_effective_settings(node_id)
	var image_global_transform = source.global_transform * pixel_to_local
	var world_displacement = _geometry.angle_vector(float(settings.angle), float(settings.distance))
	var local_displacement = _geometry.world_to_local_vector(image_global_transform, world_displacement)
	var average_scale = (image_global_transform.x.length() + image_global_transform.y.length()) * 0.5
	var local_blur_radius = float(settings.blur_radius) / max(average_scale, 0.000001)
	return {
		"ok": true,
		"image": source_image,
		"settings": settings,
		"displacement": local_displacement,
		"blur_radius": local_blur_radius
	}


func _install_render_result(source, node_id : int, capture : Dictionary, settings : Dictionary, rendered) -> Dictionary:
	if typeof(rendered) != TYPE_DICTIONARY:
		_remove_shadow(source)
		return {"ok": false, "error": "渲染器没有返回有效结果。"}
	if not rendered.get("ok", false):
		_remove_shadow(source)
		return {"ok": false, "error": str(rendered.get("error", "轮廓渲染失败。"))}
	if not rendered.has("image") or not (rendered.image is Image):
		_remove_shadow(source)
		return {"ok": false, "error": "渲染结果中没有有效图像。"}
	if rendered.image.is_empty():
		_remove_shadow(source)
		return {"ok": false, "error": "渲染结果图像为空。"}
	var node_key = str(node_id)
	if _eraser_stroke_by_node_id.has(node_key):
		_finish_eraser_stroke(true)
	_cancel_eraser_jobs_for_node(node_key)
	var pixel_to_local = capture.get("pixel_to_local", Transform2D())
	var output_to_source = pixel_to_local * Transform2D(
		Vector2(float(rendered.get("pixel_scale", 1.0)), 0.0),
		Vector2(0.0, float(rendered.get("pixel_scale", 1.0))),
		Vector2(rendered.get("offset", Vector2.ZERO))
	)
	var strokes = _erasures.get(str(node_id), [])
	var masked_image = _shadow_mask.apply(rendered.image, strokes, output_to_source)
	if not (masked_image is Image) or masked_image.is_empty():
		masked_image = rendered.image
	var sprite = capture.get("source_sprite", null)
	_update_shadow_node(source, sprite, masked_image, output_to_source, node_id, settings, str(capture.get("kind", "prop")))
	_shadow_render_cache[str(node_id)] = {
		"image": rendered.image.duplicate(),
		"visible_image": masked_image.duplicate(),
		"pixel_to_local": output_to_source,
		"kind": str(capture.get("kind", "prop")),
		"visible_used_rect": masked_image.get_used_rect(),
		"source_transform": source.global_transform,
		"texture": _shadow_texture_for_source(source)
	}
	return {"ok": true, "node_id": node_id}


func _complete_generation_item(source, node_id : int, result : Dictionary, label : String, source_signature : String = ""):
	var key = str(node_id)
	_generation_batch_done += 1
	if result.get("ok", false):
		_generated_fingerprints[key] = source_signature if source_signature != "" else _source_signature(source)
		_enabled_node_ids[key] = true
		_last_generated += 1
		_save_map_recipe()
	else:
		_last_error = str(result.get("error", "生成失败。"))
		_last_operation = "生成失败：" + _last_error
	if _generation_queue.empty():
		var should_complete = _queue_completion_label == label or _last_operation.find("已排队") >= 0 or _last_operation.find("正在刷新") >= 0
		if should_complete:
			_last_operation = "已完成 %d/%d 个投影" % [_generation_batch_done, _generation_batch_total]
			_queue_completion_label = ""


func _get_cached_sprite_image(sprite) -> Dictionary:
	var texture = sprite.texture
	var cache_key = _sprite_extract_key(sprite, texture)
	_extraction_cache_clock += 1
	if _extraction_cache.has(cache_key):
		var cached = _extraction_cache[cache_key]
		if cached.texture == texture:
			cached.last_used = _extraction_cache_clock
			_extraction_cache[cache_key] = cached
			return {"ok": true, "image": cached.image, "rect": cached.rect}
		_remove_extraction_cache_entry(cache_key)
	var extracted = _geometry.extract_sprite_image(sprite)
	if typeof(extracted) != TYPE_DICTIONARY or not extracted.get("ok", false):
		return extracted
	var image = extracted.get("image", null)
	if not (image is Image) or image.is_empty():
		return {"ok": false, "error": "无法读取该物件的图像。"}
	var image_bytes = int(image.get_width()) * int(image.get_height()) * 4
	if image_bytes <= 0 or image_bytes > MAX_EXTRACTION_CACHE_BYTES:
		return extracted
	while _extraction_cache.size() >= MAX_EXTRACTION_CACHE_ITEMS or _extraction_cache_bytes + image_bytes > MAX_EXTRACTION_CACHE_BYTES:
		if not _evict_oldest_extraction_cache_entry():
			return extracted
	_extraction_cache[cache_key] = {
		"texture": texture,
		"image": image,
		"rect": extracted.rect,
		"bytes": image_bytes,
		"last_used": _extraction_cache_clock
	}
	_extraction_cache_bytes += image_bytes
	return extracted


func _sprite_extract_key(sprite, texture) -> String:
	return PoolStringArray([
	_texture_cache_identity(texture, 0),
		str(sprite.hframes), str(sprite.vframes), str(sprite.frame),
		str(sprite.region_enabled), str(sprite.region_rect),
		str(sprite.flip_h), str(sprite.flip_v), str(sprite.centered), str(sprite.offset)
	]).join("|")


func _texture_cache_identity(texture, depth : int) -> String:
	if not is_instance_valid(texture):
		return "null"
	var parts = [str(texture.get_instance_id()), str(texture.resource_path), str(texture.get_size())]
	if texture is AtlasTexture:
		parts.append(str(texture.region))
		parts.append(str(texture.margin))
		if depth < 8:
			parts.append(_texture_cache_identity(texture.atlas, depth + 1))
	return PoolStringArray(parts).join(":")


func _remove_extraction_cache_entry(cache_key : String):
	if not _extraction_cache.has(cache_key):
		return
	var cached = _extraction_cache[cache_key]
	_extraction_cache_bytes = max(0, _extraction_cache_bytes - int(cached.get("bytes", 0)))
	_extraction_cache.erase(cache_key)


func _evict_oldest_extraction_cache_entry() -> bool:
	if _extraction_cache.empty():
		return false
	var oldest_key = ""
	var oldest_stamp = _extraction_cache_clock + 1
	for cache_key in _extraction_cache.keys():
		var cached = _extraction_cache[cache_key]
		if int(cached.get("last_used", 0)) < oldest_stamp:
			oldest_stamp = int(cached.get("last_used", 0))
			oldest_key = str(cache_key)
	if oldest_key == "":
		return false
	_remove_extraction_cache_entry(oldest_key)
	return true


func _local_blur_radius(sprite) -> float:
	var transform = sprite.global_transform
	var average_scale = (transform.x.length() + transform.y.length()) * 0.5
	if average_scale <= 0.000001:
		return blur_radius
	return blur_radius / average_scale


func _update_shadow_node(source, source_sprite, image : Image, output_to_source : Transform2D, node_id : int, settings : Dictionary, source_kind : String):
	var wrapper = _find_shadow(source)
	if wrapper == null:
		wrapper = Node2D.new()
		wrapper.name = SHADOW_NODE_NAME
		wrapper.set_meta(SHADOW_META, TOOL_ID)
		wrapper.set_meta("source_node_id", int(node_id))
		source.add_child(wrapper)
	wrapper.transform = Transform2D()
	if source_kind == "path":
		wrapper.z_index = -1
		wrapper.z_as_relative = true
		wrapper.show_behind_parent = true
	else:
		wrapper.show_behind_parent = false
		wrapper.z_index = int(source_sprite.z_index) - 1 if is_instance_valid(source_sprite) else -1
		wrapper.z_as_relative = source_sprite.z_as_relative if is_instance_valid(source_sprite) else true
		if is_instance_valid(source_sprite) and wrapper.get_index() > source_sprite.get_index():
			source.move_child(wrapper, source_sprite.get_index())
	wrapper.visible = preview_enabled
	var shadow_sprite = null
	if wrapper.get_child_count() > 0 and wrapper.get_child(0) is Sprite:
		shadow_sprite = wrapper.get_child(0)
	else:
		for child in wrapper.get_children():
			wrapper.remove_child(child)
			child.queue_free()
		shadow_sprite = Sprite.new()
		shadow_sprite.name = "ContourShadowSprite"
		wrapper.add_child(shadow_sprite)
	var image_texture = ImageTexture.new()
	image_texture.create_from_image(image)
	shadow_sprite.texture = image_texture
	shadow_sprite.centered = false
	shadow_sprite.transform = output_to_source
	var color = _parse_color(str(settings.get("color", shadow_color.to_html(false))), shadow_color)
	var source_alpha = source_sprite.modulate.a if is_instance_valid(source_sprite) else 1.0
	shadow_sprite.modulate = Color(color.r, color.g, color.b, float(settings.opacity) * source_alpha)
	shadow_sprite.z_index = 0
	shadow_sprite.z_as_relative = true
	shadow_sprite.set_meta(SHADOW_META, TOOL_ID)
	wrapper.set_meta("source_node_id", int(node_id))
	return shadow_sprite


func _shadow_texture_for_source(source):
	var wrapper = _find_shadow(source)
	if wrapper == null:
		return null
	for child in wrapper.get_children():
		if child is Sprite:
			return child.texture
	return null


func _find_shadow(source):
	if not is_instance_valid(source):
		return null
	for child in source.get_children():
		if child.has_meta(SHADOW_META) and str(child.get_meta(SHADOW_META)) == TOOL_ID:
			return child
	return null


func _remove_shadow(source) -> bool:
	if not is_instance_valid(source):
		return false
	var node_id = _stable_node_id(source)
	if node_id >= 0:
		var node_key = str(node_id)
		if _eraser_stroke_by_node_id.has(node_key):
			_finish_eraser_stroke(true)
		_cancel_eraser_jobs_for_node(node_key)
		_shadow_render_cache.erase(node_key)
	var removed = false
	for child in source.get_children():
		if child.has_meta(SHADOW_META) and str(child.get_meta(SHADOW_META)) == TOOL_ID:
			source.remove_child(child)
			child.queue_free()
			removed = true
	return removed


func _selected_props(level) -> Array:
	return _selected_sources(level)


func _selected_sources(level) -> Array:
	var result = _read_selected_sources(level)
	if _active_tool_name() == TOOL_ID and _selection_record_cleared:
		_set_selected_counts([])
		_last_selection_source = "none"
		return []
	if not result.empty():
		return result
	if _active_tool_name() != TOOL_ID:
		return result
	if not _selection_snapshot_matches(level):
		_clear_selection_snapshot()
		return result
	for node_id in _selection_snapshot_node_ids:
		var node = Global.World.GetNodeByID(int(node_id))
		if _is_source_node(node) and _source_is_on_level(node, level):
			result.append(node)
	_set_selected_counts(result)
	_last_selection_source = "snapshot" if not result.empty() else "none"
	return result


func _read_selected_props(level) -> Array:
	return _read_selected_sources(level)


func _read_selected_sources(level) -> Array:
	var result = []
	_last_selection_type = "unavailable"
	_last_selection_type_code = TYPE_NIL
	_last_selection_count = 0
	_last_selected_prop_count = 0
	_last_selected_path_count = 0
	_last_selection_source = "none"
	if not is_instance_valid(level) or not is_instance_valid(Global.Editor):
		return result
	if not Global.Editor.Tools.has("SelectTool"):
		return result
	var select_tool = Global.Editor.Tools["SelectTool"]
	if not is_instance_valid(select_tool):
		return result
	var selected = null
	if select_tool.has_method("get_Selected"):
		selected = select_tool.call("get_Selected")
	else:
		selected = select_tool.get("Selected")
	_last_selection_type_code = typeof(selected)
	_last_selection_type = "Array" if _last_selection_type_code == TYPE_ARRAY else str(_last_selection_type_code)
	if typeof(selected) != TYPE_ARRAY:
		return result
	_last_selection_count = selected.size()
	for node in selected:
		if _is_source_node(node) and _source_is_on_level(node, level):
			result.append(node)
	_set_selected_counts(result)
	_last_selection_source = "live" if not result.empty() else "none"
	return result


func _set_selected_counts(sources : Array):
	_last_selected_prop_count = 0
	_last_selected_path_count = 0
	for source in sources:
		if _is_prop_node(source):
			_last_selected_prop_count += 1
		elif _is_pathway_source(source):
			_last_selected_path_count += 1


func _is_prop_node(node) -> bool:
	if _stable_node_id(node) < 0:
		return false
	var sprite = _prop_sprite(node)
	return is_instance_valid(sprite) and sprite is Sprite


func _is_pathway_source(node) -> bool:
	return _path_source != null and _path_source.has_method("is_pathway") and bool(_path_source.call("is_pathway", node))


func _is_source_node(node) -> bool:
	return _is_prop_node(node) or (_stable_node_id(node) >= 0 and _is_pathway_source(node))


func _source_is_on_level(source, level) -> bool:
	if not is_instance_valid(source) or not is_instance_valid(level):
		return false
	var parent = source.get_parent()
	return (is_instance_valid(level.Objects) and parent == level.Objects) or (is_instance_valid(level.Pathways) and parent == level.Pathways)


func _level_sources(level) -> Array:
	var result = _level_props(level)
	if not is_instance_valid(level) or not is_instance_valid(level.Pathways):
		return result
	for pathway in level.Pathways.get_children():
		if _stable_node_id(pathway) >= 0 and _is_pathway_source(pathway):
			result.append(pathway)
	return result


func _prop_sprite(node):
	if not is_instance_valid(node):
		return null
	if node.has_method("get_Sprite"):
		return node.call("get_Sprite")
	for property in node.get_property_list():
		if str(property.get("name", "")) == "Sprite":
			return node.get("Sprite")
	return null


func _has_property(object, property_name : String) -> bool:
	if not is_instance_valid(object):
		return false
	for property_info in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func _source_sprite_for_source(source):
	if _is_prop_node(source):
		return _prop_sprite(source)
	return null


func _active_tool_name() -> String:
	if not is_instance_valid(Global.Editor):
		return ""
	if Global.Editor.has_method("get_ActiveToolName"):
		return str(Global.Editor.call("get_ActiveToolName"))
	return str(Global.Editor.get("ActiveToolName"))


func _capture_selection_snapshot():
	if not is_instance_valid(Global.World) or not is_instance_valid(Global.Editor):
		_clear_selection_snapshot()
		return
	var active_tool = _active_tool_name()
	var level = _current_level()
	if not is_instance_valid(level):
		_clear_selection_snapshot()
		return
	if active_tool == "SelectTool":
		var selected_props = _read_selected_props(level)
		if selected_props.empty():
			_clear_selection_snapshot()
			return
		_selection_snapshot_node_ids.clear()
		for prop in selected_props:
			var node_id = _stable_node_id(prop)
			if node_id >= 0 and not _selection_snapshot_node_ids.has(node_id):
				_selection_snapshot_node_ids.append(node_id)
		_selection_snapshot_world_id = int(Global.World.get_instance_id())
		_selection_snapshot_level_id = int(level.ID)
		_selection_snapshot_map_file = _current_map_file()
		_selection_record_cleared = false
	else:
		if not _selection_snapshot_matches(level):
			_clear_selection_snapshot()


func _selection_snapshot_matches(level) -> bool:
	if not is_instance_valid(level) or not is_instance_valid(Global.World) or _selection_snapshot_node_ids.empty():
		return false
	if _selection_snapshot_world_id != int(Global.World.get_instance_id()):
		return false
	if _selection_snapshot_level_id != int(level.ID):
		return false
	var current_map_file = _current_map_file()
	if current_map_file != "":
		return _selection_snapshot_map_file == current_map_file
	return true


func _current_map_file() -> String:
	if not is_instance_valid(Global.Editor):
		return ""
	if Global.Editor.has_method("get_CurrentMapFile"):
		return str(Global.Editor.call("get_CurrentMapFile"))
	for property in Global.Editor.get_property_list():
		if str(property.get("name", "")) == "CurrentMapFile":
			return str(Global.Editor.get("CurrentMapFile"))
	return ""


func _clear_selection_snapshot():
	_selection_snapshot_node_ids.clear()
	_selection_snapshot_world_id = -1
	_selection_snapshot_level_id = -1
	_selection_snapshot_map_file = ""


func _update_selection_label():
	if _selection_label == null:
		return
	var count = _selection_snapshot_node_ids.size()
	if is_instance_valid(Global.World):
		var snapshot_sources = []
		for node_id in _selection_snapshot_node_ids:
			var source = Global.World.GetNodeByID(int(node_id))
			if _is_source_node(source) and _source_is_on_level(source, _current_level()):
				snapshot_sources.append(source)
		_set_selected_counts(snapshot_sources)
		count = snapshot_sources.size()
	if _selection_record_cleared:
		_selection_label.text = "目标：0 个 · 选择记录已清除"
	else:
		_selection_label.text = "目标：%d 个 · %d 物件 / %d 路径" % [count, _last_selected_prop_count, _last_selected_path_count]


func _sync_selection_highlights():
	var desired = {}
	var level = _current_level()
	var active_tool = _active_tool_name()
	var show_highlights = (
		is_instance_valid(Global.World)
		and is_instance_valid(level)
		and active_tool == TOOL_ID
		and not _selection_record_cleared
		and _selection_snapshot_matches(level)
	)
	if show_highlights:
		for node_id in _selection_snapshot_node_ids:
			var key = str(int(node_id))
			var prop = Global.World.GetNodeByID(int(node_id))
			if not _is_prop_node(prop) or prop.get_parent() != level.Objects:
				continue
			if prop.has_method("Select"):
				var was_marked = false
				if _selection_highlight_node_ids.has(key):
					var previous_prop = _selection_highlight_node_ids[key].get_ref()
					was_marked = is_instance_valid(previous_prop) and previous_prop == prop
				if not was_marked:
					prop.call("Select", true)
					prop.set_meta(SELECTION_MARK_META, true)
				desired[key] = weakref(prop)
	elif active_tool == "SelectTool" and not _selection_record_cleared and _selection_snapshot_matches(level):
		# Keep ownership while the real SelectTool owns the selection. If it is
		# explicitly cleared on a later frame, the cleanup below balances Select(false).
		for node_id in _selection_snapshot_node_ids:
			var key = str(int(node_id))
			if not _selection_highlight_node_ids.has(key):
				continue
			var prop = Global.World.GetNodeByID(int(node_id))
			var previous_prop = _selection_highlight_node_ids[key].get_ref()
			if is_instance_valid(prop) and prop == previous_prop and prop.get_parent() == level.Objects:
				desired[key] = weakref(prop)
	for key in _selection_highlight_node_ids.keys():
		var previous_prop = _selection_highlight_node_ids[key].get_ref()
		var desired_prop = desired[key].get_ref() if desired.has(key) else null
		if is_instance_valid(previous_prop) and previous_prop == desired_prop:
			continue
		if not is_instance_valid(previous_prop):
			continue
		var current_prop = Global.World.GetNodeByID(int(key)) if is_instance_valid(Global.World) else null
		var is_live_selected = active_tool == "SelectTool" and current_prop == previous_prop and _selection_snapshot_node_ids.has(int(key))
		if not is_live_selected:
			if previous_prop.has_method("Select"):
				previous_prop.call("Select", false)
			if previous_prop.has_meta(SELECTION_MARK_META):
				previous_prop.remove_meta(SELECTION_MARK_META)
	_selection_highlight_node_ids = desired


func _cleanup_stale_selection_marks():
	if not is_instance_valid(Global.World):
		return
	var level = _current_level()
	var selected_ids = {}
	if _active_tool_name() == "SelectTool" and is_instance_valid(level):
		for prop in _read_selected_props(level):
			selected_ids[str(_stable_node_id(prop))] = true
	for scan_level in Global.World.levels:
		if not is_instance_valid(scan_level) or not is_instance_valid(scan_level.Objects):
			continue
		for prop in _level_props(scan_level):
			if not prop.has_meta(SELECTION_MARK_META):
				continue
			var key = str(_stable_node_id(prop))
			if scan_level == level and selected_ids.has(key):
				_selection_highlight_node_ids[key] = weakref(prop)
				continue
			if prop.has_method("Select"):
				prop.call("Select", false)
			prop.remove_meta(SELECTION_MARK_META)


func _level_props(level) -> Array:
	var props = []
	if not is_instance_valid(level) or not is_instance_valid(level.Objects):
		return props
	for child in level.Objects.get_children():
		if _is_prop_node(child):
			props.append(child)
	return props


func _stable_node_id(node) -> int:
	if not is_instance_valid(node) or not node.has_meta("node_id"):
		return -1
	var value = node.get_meta("node_id")
	if typeof(value) != TYPE_INT or int(value) < 0:
		return -1
	return int(value)


func _current_level():
	if not is_instance_valid(Global.World):
		return null
	return Global.World.GetCurrentLevel()


func _scan_generated_for_changes():
	if not is_instance_valid(Global.World):
		return
	var keys = _generated_fingerprints.keys()
	if keys.empty():
		_follow_cursor = 0
		return
	for i in range(min(FOLLOW_SCAN_BUDGET, keys.size())):
		if _follow_cursor >= keys.size():
			_follow_cursor = 0
		var key = str(keys[_follow_cursor])
		_follow_cursor += 1
		var source = Global.World.GetNodeByID(int(key))
		var level = _level_for_source(source) if is_instance_valid(source) else null
		if not _is_source_node(source) or level == null:
			continue
		if _excluded_node_ids.has(key) or not _enabled_node_ids.has(key) or _find_shadow(source) == null or _eraser_stroke_by_node_id.has(key):
			continue
		var signature = _source_signature(source)
		if signature != str(_generated_fingerprints.get(key, "")) and not _pending_node_ids.has(key):
			if _queue_source(source, level, int(key), "跟随更新"):
				_last_generated = 0
				_queue_completion_label = "跟随更新"
				_last_operation = "跟随更新：已排队 1 个对象"
				break


func _source_signature(source) -> String:
	if not _is_source_node(source):
		return "missing"
	var transform = source.global_transform
	var fields = [
		str(source.get_class()), str(transform.x.x), str(transform.x.y), str(transform.y.x), str(transform.y.y),
		_settings_signature(_stable_node_id(source)),
		JSON.print(_erasures.get(str(_stable_node_id(source)), []))
	]
	var sprite = _prop_sprite(source)
	if is_instance_valid(sprite):
		var texture_id = -1
		var texture_path = ""
		var texture_size = Vector2.ZERO
		if sprite.texture != null:
			texture_id = sprite.texture.get_instance_id()
			texture_path = str(sprite.texture.resource_path)
			texture_size = sprite.texture.get_size()
		fields.append_array([
			str(texture_id), texture_path, str(texture_size.x), str(texture_size.y),
			str(sprite.hframes), str(sprite.vframes), str(sprite.frame),
			str(sprite.region_enabled), str(sprite.region_rect), str(sprite.flip_h), str(sprite.flip_v),
			str(sprite.centered), str(sprite.offset), str(sprite.modulate),
			str(sprite.transform), str(sprite.z_index), str(sprite.z_as_relative)
		])
	else:
		fields.append_array(_path_signature_fields(source))
	return PoolStringArray(fields).join("|")


func _path_signature_fields(source) -> Array:
	if _path_source != null and _path_source.has_method("visual_signature"):
		return ["path_visual=" + str(_path_source.call("visual_signature", source))]
	var fields = []
	for property_name in ["points", "width", "width_curve", "default_color", "gradient", "texture", "texture_mode", "joint_mode", "begin_cap_mode", "end_cap_mode", "sharp_limit", "round_precision", "antialiased", "loop", "normalize_uv", "FadeIn", "FadeOut", "Grow", "Shrink"]:
		if _has_property(source, property_name):
			var value = source.get(property_name)
			if value is Texture:
				value = _texture_cache_identity(value, 0)
			elif value is Resource:
				value = str(value.resource_path) + ":" + str(value.get_instance_id())
			fields.append(property_name + "=" + str(value))
	return fields


func _settings_signature(node_id : int = -1) -> String:
	var settings = _parameter_settings_dictionary() if node_id < 0 else get_effective_settings(node_id)
	return "%0.3f|%0.3f|%0.3f|%s" % [float(settings.angle), float(settings.distance), float(settings.blur_radius), str(settings.mode)]


func _set_preview_on_all_levels(value : bool):
	if not is_instance_valid(Global.World):
		return
	for level in Global.World.levels:
		if not is_instance_valid(level):
			continue
		for source in _level_sources(level):
			var wrapper = _find_shadow(source)
			if wrapper != null:
				wrapper.visible = bool(value)


func _on_eraser_toggled(value):
	if _syncing_controls:
		return
	if not bool(value):
		_disable_eraser("阴影橡皮擦已关闭。")
		return
	# Snapshot the real SelectTool selection before handing input to this mod tool.
	_capture_selection_snapshot()
	var level = _current_level()
	if level == null or not _selection_snapshot_matches(level):
		_sync_controls()
		_operation_notice("阴影橡皮擦需要先记录至少一个本层对象或路径。", "selection_missing")
		return
	var selected_sources = _selected_sources(level)
	var selected_ids = []
	for source in selected_sources:
		var node_id = _stable_node_id(source)
		if node_id >= 0 and not selected_ids.has(node_id):
			selected_ids.append(node_id)
	selected_ids.sort()
	if selected_ids.empty():
		_sync_controls()
		_operation_notice("阴影橡皮擦需要先记录至少一个本层对象或路径。", "selection_missing")
		return
	var missing_sources = []
	for source in selected_sources:
		var source_node_id = _stable_node_id(source)
		if not _eraser_source_ready(source, source_node_id):
			missing_sources.append(source)
	if not missing_sources.empty():
		var waiting_for_generation = false
		for source in missing_sources:
			if _pending_node_ids.has(str(_stable_node_id(source))):
				waiting_for_generation = true
				break
		var message = "所选对象的投影仍在生成；请等待队列完成后再启用橡皮擦。" if waiting_for_generation else "所选对象缺少可擦除的投影缓存；请先生成/刷新选中对象，再启用橡皮擦。"
		_sync_controls()
		_operation_notice(message, "eraser_shadow_not_ready")
		return
	if not is_instance_valid(Global.Editor) or not Global.Editor.has_method("OnSelectTool"):
		_sync_controls()
		_operation_error("当前版本无法接管画布输入，橡皮擦未启用。")
		return
	var expected_world_id = int(Global.World.get_instance_id()) if is_instance_valid(Global.World) else -1
	var expected_level_id = int(level.ID)
	var expected_map_file = _current_map_file()
	var expected_selection_key = PoolStringArray(selected_ids).join(",")
	# Set the expected scope before switching. OnSelectTool may synchronously run
	# lifecycle callbacks, so restore this snapshot only after the switch returns.
	_eraser_level_id = expected_level_id
	_eraser_selection_key = expected_selection_key
	_eraser_world_id = expected_world_id
	_eraser_map_file = expected_map_file
	# Selecting the already active mod tool again can call our own disable hook.
	# Keep the current input owner and only refresh the eraser's recorded scope.
	if _active_tool_name() != TOOL_ID:
		Global.Editor.call("OnSelectTool", TOOL_ID)
	if _active_tool_name() != TOOL_ID:
		_clear_eraser_scope()
		_sync_controls()
		_operation_error("无法切换到轮廓投影工具，橡皮擦未启用。")
		return
	if not _eraser_scope_matches(expected_world_id, expected_level_id, expected_map_file, expected_selection_key):
		_clear_eraser_scope()
		_sync_controls()
		_operation_notice("接管画布后地图、楼层或选择发生变化；橡皮擦未启用，请重新确认目标。", "eraser_scope_changed")
		return
	# A host lifecycle callback can clear these during OnSelectTool. Re-apply the
	# captured scope after verifying that the same world/level/selection survived.
	_eraser_level_id = expected_level_id
	_eraser_selection_key = expected_selection_key
	_eraser_world_id = expected_world_id
	_eraser_map_file = expected_map_file
	eraser_enabled = true
	_eraser_window_was_focused = _read_window_focus()
	_set_eraser_cursor()
	_last_error = ""
	_last_notice = ""
	_last_operation = "橡皮擦已启用 · 仅擦除 %d 个已记录对象/路径" % selected_ids.size()
	_sync_controls()


func _clear_eraser_scope():
	eraser_enabled = false
	_eraser_window_was_focused = _read_window_focus()
	_eraser_level_id = -1
	_eraser_selection_key = ""
	_eraser_world_id = -1
	_eraser_map_file = ""
	_restore_world_ui_cursor()


func _eraser_scope_matches(world_id : int, level_id : int, map_file : String, selection_key : String) -> bool:
	if not is_instance_valid(Global.World) or int(Global.World.get_instance_id()) != world_id:
		return false
	if _current_map_file() != map_file:
		return false
	var current_level = _current_level()
	if not is_instance_valid(current_level) or int(current_level.ID) != level_id:
		return false
	return PoolStringArray(_selected_source_ids()).join(",") == selection_key


func _eraser_source_ready(source, node_id : int) -> bool:
	if not _is_source_node(source) or _find_shadow(source) == null:
		return false
	if _pending_node_ids.has(str(node_id)):
		return false
	var cache = _shadow_render_cache.get(str(node_id), {})
	if typeof(cache) != TYPE_DICTIONARY or not cache.has("pixel_to_local"):
		return false
	var image = cache.get("visible_image", null)
	return image is Image and not image.is_empty()


func _on_eraser_radius_changed(value):
	if _syncing_controls:
		return
	var next_radius = clamp(float(value) * 0.5, 1.0, 256.0)
	if is_equal_approx(next_radius, eraser_radius):
		return
	if _eraser_drawing:
		_finish_eraser_stroke(true)
	eraser_radius = next_radius
	if eraser_enabled:
		_set_eraser_cursor()
	_settings_dirty = true
	_settings_save_delay = 0.45


func _on_eraser_hardness_changed(value):
	if _syncing_controls:
		return
	var next_hardness = clamp(float(value) / 100.0, 0.0, 1.0)
	if is_equal_approx(next_hardness, eraser_hardness):
		return
	if _eraser_drawing:
		_finish_eraser_stroke(true)
	eraser_hardness = next_hardness
	_settings_dirty = true
	_settings_save_delay = 0.45


func on_tool_enable(tool_id):
	if str(tool_id) == TOOL_ID and eraser_enabled:
		_set_eraser_cursor()


func on_tool_disable(tool_id):
	if str(tool_id) == TOOL_ID:
		_disable_eraser("工具切换，橡皮擦关闭")


func on_content_input(event):
	if not eraser_enabled or _active_tool_name() != TOOL_ID:
		return
	if _poll_eraser_focus(_read_window_focus()):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_ESCAPE:
		_disable_eraser("已结束阴影橡皮擦。")
		return
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		if event.pressed:
			if not _world_ui_inside_bounds():
				return
			_eraser_drawing = true
			_eraser_last_world_position = _get_map_mouse_position()
			_eraser_gesture_node_ids.clear()
			_eraser_stroke_by_node_id.clear()
			_apply_eraser_segment(_eraser_last_world_position, _eraser_last_world_position)
		else:
			_finish_eraser_stroke(true)
		return
	if event is InputEventMouseMotion and _eraser_drawing:
		if not _world_ui_inside_bounds():
			_finish_eraser_stroke(true)
			_eraser_drawing = false
			_last_operation = "已离开画布，笔画结束"
			return
		var current_position = _get_map_mouse_position()
		_apply_eraser_segment(_eraser_last_world_position, current_position)
		_eraser_last_world_position = current_position


func _update_eraser_lifecycle():
	if not eraser_enabled:
		return
	if _active_tool_name() != TOOL_ID:
		_disable_eraser("工具切换，橡皮擦关闭")
		return
	if _poll_eraser_focus(_read_window_focus()):
		return
	if not is_instance_valid(Global.World):
		_disable_eraser("地图切换，橡皮擦关闭", false)
		return
	if int(Global.World.get_instance_id()) != _eraser_world_id or _current_map_file() != _eraser_map_file:
		_disable_eraser("地图切换，橡皮擦关闭", false)
		return
	var level = _current_level()
	if not is_instance_valid(level):
		_disable_eraser("楼层切换，橡皮擦关闭", false)
		return
	if int(level.ID) != _eraser_level_id:
		_disable_eraser("楼层切换，橡皮擦关闭")
		return
	var selection_key = PoolStringArray(_selected_source_ids()).join(",")
	if selection_key != _eraser_selection_key:
		_finish_eraser_stroke(true)
		_eraser_selection_key = selection_key
		if selection_key == "":
			_disable_eraser("选择已清空，橡皮擦关闭")


func _read_window_focus() -> bool:
	if OS.has_method("is_window_focused"):
		return bool(OS.is_window_focused())
	return true


func _poll_eraser_focus(focused : bool) -> bool:
	if not eraser_enabled:
		_eraser_window_was_focused = focused
		return false
	var just_lost_focus = _eraser_window_was_focused and not focused
	_eraser_window_was_focused = focused
	if just_lost_focus:
		_handle_eraser_focus_lost()
	return just_lost_focus


func _handle_eraser_focus_lost():
	if not eraser_enabled or not _eraser_drawing:
		return
	_finish_eraser_stroke(true)
	_eraser_drawing = false
	_last_operation = "窗口失焦，笔画结束"


func _disable_eraser(message : String = "", persist : bool = true):
	_finish_eraser_stroke(true, persist)
	eraser_enabled = false
	_eraser_window_was_focused = _read_window_focus()
	_eraser_level_id = -1
	_eraser_selection_key = ""
	_eraser_world_id = -1
	_eraser_map_file = ""
	_restore_world_ui_cursor()
	_sync_controls()
	if message != "":
		_last_operation = message


func _set_eraser_cursor():
	if not is_instance_valid(Global.WorldUI):
		return
	if _world_ui_cursor_saved.empty():
		for property_name in ["CursorMode", "CursorRadius", "IsActionInverted"]:
			var saved = _read_world_ui_property(property_name)
			if saved.get("available", false):
				_world_ui_cursor_saved[property_name] = saved.value
	_set_world_ui_property("CursorMode", 5)
	_set_world_ui_property("CursorRadius", eraser_radius)
	_set_world_ui_property("IsActionInverted", true)


func _restore_world_ui_cursor():
	if _world_ui_cursor_saved.empty():
		return
	if is_instance_valid(Global.WorldUI):
		for property_name in _world_ui_cursor_saved.keys():
			_set_world_ui_property(str(property_name), _world_ui_cursor_saved[property_name])
	_world_ui_cursor_saved.clear()


func _read_world_ui_property(property_name : String) -> Dictionary:
	if not is_instance_valid(Global.WorldUI):
		return {"available": false}
	if _has_property(Global.WorldUI, property_name):
		return {"available": true, "value": Global.WorldUI.get(property_name)}
	for method_name in ["get_" + property_name, "Get" + property_name]:
		if Global.WorldUI.has_method(method_name):
			return {"available": true, "value": Global.WorldUI.call(method_name)}
	return {"available": false}


func _set_world_ui_property(property_name : String, value) -> bool:
	if not is_instance_valid(Global.WorldUI):
		return false
	for method_name in ["set_" + property_name, "Set" + property_name]:
		if Global.WorldUI.has_method(method_name):
			Global.WorldUI.call(method_name, value)
			return true
	if _has_property(Global.WorldUI, property_name):
		Global.WorldUI.set(property_name, value)
		return true
	return false


func _get_map_mouse_position() -> Vector2:
	if is_instance_valid(Global.WorldUI):
		if Global.WorldUI.has_method("get_MousePosition"):
			return Global.WorldUI.call("get_MousePosition")
		if _has_property(Global.WorldUI, "MousePosition"):
			return Global.WorldUI.get("MousePosition")
	if is_instance_valid(Global.World):
		return Global.World.get_global_mouse_position()
	return Vector2.ZERO


func _world_ui_inside_bounds() -> bool:
	if not is_instance_valid(Global.WorldUI):
		return false
	if Global.WorldUI.has_method("get_IsInsideBounds"):
		return bool(Global.WorldUI.call("get_IsInsideBounds"))
	if _has_property(Global.WorldUI, "IsInsideBounds"):
		return bool(Global.WorldUI.get("IsInsideBounds"))
	return true


func _world_radius_basis(source) -> Transform2D:
	if not is_instance_valid(source):
		return Transform2D()
	var inverse = source.global_transform.affine_inverse()
	return Transform2D(inverse.basis_xform(Vector2(1.0, 0.0)), inverse.basis_xform(Vector2(0.0, 1.0)), Vector2.ZERO)


func _radius_basis_from_value(value) -> Transform2D:
	if typeof(value) == TYPE_TRANSFORM2D:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		var x_axis = _vector_from_value(value[0])
		var y_axis = _vector_from_value(value[1])
		if x_axis != null and y_axis != null:
			return Transform2D(x_axis, y_axis, Vector2.ZERO)
	return Transform2D()


func _vector_from_value(value):
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return null


func _serialize_radius_basis(basis : Transform2D) -> Array:
	return [[basis.x.x, basis.x.y], [basis.y.x, basis.y.y]]


func _apply_eraser_segment(world_from : Vector2, world_to : Vector2):
	var level = _current_level()
	if level == null:
		return
	var selected_ids = _selected_source_ids()
	if selected_ids.empty():
		return
	for node_id in selected_ids:
		var key = str(int(node_id))
		var source = Global.World.GetNodeByID(int(node_id)) if is_instance_valid(Global.World) else null
		if not _is_source_node(source) or not _source_is_on_level(source, level) or _find_shadow(source) == null:
			continue
		var basis = _world_radius_basis(source)
		if abs(basis.x.x * basis.y.y - basis.x.y * basis.y.x) < 0.000001:
			continue
		var local_from = source.to_local(world_from)
		var local_to = source.to_local(world_to)
		var strokes = _erasures.get(key, [])
		if _eraser_stroke_by_node_id.has(key):
			var stroke_index = int(_eraser_stroke_by_node_id[key])
			if stroke_index >= 0 and stroke_index < strokes.size():
				var stroke = strokes[stroke_index]
				var points = stroke.get("points", [])
				if _append_eraser_point(points, local_to):
					stroke["points"] = points
					strokes[stroke_index] = stroke
					_erasures[key] = strokes
					_extend_eraser_job_footprint(key, stroke_index, local_to)
				continue
		var initial_points = []
		initial_points.append([local_from.x, local_from.y])
		if local_from.distance_squared_to(local_to) >= 0.01:
			initial_points.append([local_to.x, local_to.y])
		if not _eraser_segment_may_hit_used_rect(key, initial_points, eraser_radius, basis):
			continue
		if not _erase_stroke_intersects_shadow(key, initial_points, eraser_radius, basis):
			continue
		var stroke = {
			"points": initial_points,
			"radius": eraser_radius,
			"hardness": eraser_hardness,
			"radius_basis": _serialize_radius_basis(basis)
		}
		strokes.append(stroke)
		_erasures[key] = strokes
		_eraser_stroke_by_node_id[key] = strokes.size() - 1
		_eraser_gesture_node_ids.append(key)
		_enqueue_eraser_stroke_job(key, source, strokes.size() - 1)


func _append_eraser_point(points : Array, point : Vector2) -> bool:
	if points.empty():
		points.append([point.x, point.y])
		return true
	var previous = _vector_from_value(points[points.size() - 1])
	if previous == null or previous.distance_squared_to(point) < 0.01:
		return false
	points.append([point.x, point.y])
	return true


func _enqueue_eraser_stroke_job(node_key : String, source, stroke_index : int):
	if not is_instance_valid(source):
		return
	var cache = _shadow_render_cache.get(node_key, {})
	if typeof(cache) != TYPE_DICTIONARY or not cache.has("visible_image") or not cache.has("pixel_to_local"):
		return
	var base_image = cache.get("image", null)
	var stroke = _erasures.get(node_key, [])[stroke_index]
	var footprint_bounds = _eraser_footprint_bounds(cache, stroke.get("points", []), float(stroke.get("radius", eraser_radius)), _radius_basis_from_value(stroke.get("radius_basis", null)))
	_eraser_job_counter += 1
	var queue = _eraser_pending_jobs.get(node_key, [])
	queue.append({
		"job_id": _eraser_job_counter,
		"node_id": int(node_key),
		"source_instance_id": int(source.get_instance_id()),
		"stroke_index": stroke_index,
		"closed": false,
		"queued_point_index": 0,
		"state": null,
		"pixel_to_local": cache.pixel_to_local,
		"footprint_min": footprint_bounds.get("min", Vector2.ZERO),
		"footprint_max": footprint_bounds.get("max", Vector2.ZERO),
		"source_transform": source.global_transform,
		"world_id": int(Global.World.get_instance_id()) if is_instance_valid(Global.World) else -1,
		"map_file": _current_map_file(),
		"level_id": int(_eraser_level_id),
		"expected_visible_image_id": -1,
		"base_image_id": int(base_image.get_instance_id()) if base_image is Image else -1
	})
	_eraser_pending_jobs[node_key] = queue
	if not _eraser_job_order.has(node_key):
		_eraser_job_order.append(node_key)


func _eraser_footprint_bounds(cache : Dictionary, points : Array, radius : float, radius_basis : Transform2D) -> Dictionary:
	if not cache.has("pixel_to_local") or points.empty():
		return {"min": Vector2.ZERO, "max": Vector2.ZERO}
	var local_to_pixel = cache.pixel_to_local.affine_inverse()
	var brush_to_pixel = local_to_pixel * radius_basis
	var extent_x = radius * sqrt(brush_to_pixel.x.x * brush_to_pixel.x.x + brush_to_pixel.y.x * brush_to_pixel.y.x)
	var extent_y = radius * sqrt(brush_to_pixel.x.y * brush_to_pixel.x.y + brush_to_pixel.y.y * brush_to_pixel.y.y)
	var bounds_min = Vector2(INF, INF)
	var bounds_max = Vector2(-INF, -INF)
	for raw_point in points:
		var point = _vector_from_value(raw_point)
		if point == null:
			continue
		var pixel = local_to_pixel.xform(point)
		bounds_min.x = min(bounds_min.x, pixel.x - extent_x)
		bounds_min.y = min(bounds_min.y, pixel.y - extent_y)
		bounds_max.x = max(bounds_max.x, pixel.x + extent_x)
		bounds_max.y = max(bounds_max.y, pixel.y + extent_y)
	if bounds_min.x == INF:
		return {"min": Vector2.ZERO, "max": Vector2.ZERO}
	return {"min": bounds_min, "max": bounds_max}


func _extend_eraser_job_footprint(node_key : String, stroke_index : int, local_point : Vector2):
	var cache = _shadow_render_cache.get(node_key, {})
	var queue = _eraser_pending_jobs.get(node_key, [])
	if typeof(cache) != TYPE_DICTIONARY or not cache.has("pixel_to_local") or typeof(queue) != TYPE_ARRAY:
		return
	var strokes = _erasures.get(node_key, [])
	if stroke_index < 0 or stroke_index >= strokes.size():
		return
	var stroke = strokes[stroke_index]
	var local_to_pixel = cache.pixel_to_local.affine_inverse()
	var basis = _radius_basis_from_value(stroke.get("radius_basis", null))
	var brush_to_pixel = local_to_pixel * basis
	var radius = float(stroke.get("radius", eraser_radius))
	var extent_x = radius * sqrt(brush_to_pixel.x.x * brush_to_pixel.x.x + brush_to_pixel.y.x * brush_to_pixel.y.x)
	var extent_y = radius * sqrt(brush_to_pixel.x.y * brush_to_pixel.x.y + brush_to_pixel.y.y * brush_to_pixel.y.y)
	var pixel = local_to_pixel.xform(local_point)
	for index in range(queue.size()):
		var job = queue[index]
		if int(job.get("stroke_index", -1)) != stroke_index:
			continue
		var bounds_min = job.get("footprint_min", Vector2(pixel.x - extent_x, pixel.y - extent_y))
		var bounds_max = job.get("footprint_max", Vector2(pixel.x + extent_x, pixel.y + extent_y))
		bounds_min.x = min(bounds_min.x, pixel.x - extent_x)
		bounds_min.y = min(bounds_min.y, pixel.y - extent_y)
		bounds_max.x = max(bounds_max.x, pixel.x + extent_x)
		bounds_max.y = max(bounds_max.y, pixel.y + extent_y)
		job["footprint_min"] = bounds_min
		job["footprint_max"] = bounds_max
		queue[index] = job
		_eraser_pending_jobs[node_key] = queue
		return


func _eraser_clipped_footprint_pixels(job : Dictionary, image : Image) -> int:
	if not (image is Image) or image.is_empty():
		return 0
	var bounds_min = job.get("footprint_min", Vector2.ZERO)
	var bounds_max = job.get("footprint_max", Vector2.ZERO)
	var left = clamp(int(floor(bounds_min.x)), 0, image.get_width())
	var top = clamp(int(floor(bounds_min.y)), 0, image.get_height())
	var right = clamp(int(ceil(bounds_max.x)), 0, image.get_width())
	var bottom = clamp(int(ceil(bounds_max.y)), 0, image.get_height())
	return max(0, right - left) * max(0, bottom - top)


func _process_eraser_jobs():
	var frame_started = OS.get_ticks_usec()
	var had_jobs = not _eraser_pending_jobs.empty()
	_eraser_last_frame_processed_pixels = 0
	_eraser_last_frame_usec = 0
	_eraser_last_frame_uploads = 0
	_eraser_last_frame_upload_usec = 0
	if _shadow_mask == null or not _shadow_mask.has_method("begin_incremental") or not _shadow_mask.has_method("enqueue_incremental") or not _shadow_mask.has_method("advance_incremental"):
		return
	var keys = _eraser_job_order.duplicate()
	if keys.empty():
		return
	var start_index = posmod(_eraser_job_cursor, keys.size())
	var frame_images = {}
	var visited = 0
	for offset in range(keys.size()):
		if _eraser_last_frame_processed_pixels >= ERASER_FRAME_PIXEL_BUDGET:
			break
		if OS.get_ticks_usec() - frame_started >= ERASER_FRAME_TIME_BUDGET_USEC:
			break
		var key_index = (start_index + offset) % keys.size()
		var node_key = str(keys[key_index])
		if not _eraser_pending_jobs.has(node_key):
			continue
		var queue = _eraser_pending_jobs[node_key]
		if typeof(queue) != TYPE_ARRAY or queue.empty():
			_eraser_pending_jobs.erase(node_key)
			_eraser_job_order.erase(node_key)
			continue
		visited += 1
		var job = queue[0]
		var source = Global.World.GetNodeByID(int(node_key)) if is_instance_valid(Global.World) else null
		var cache = _shadow_render_cache.get(node_key, {})
		if not _eraser_job_is_current(job, source, cache):
			if _eraser_stroke_by_node_id.has(node_key):
				_finish_eraser_stroke(true)
			_cancel_eraser_jobs_for_node(node_key)
			continue
		var strokes = _erasures.get(node_key, [])
		var stroke_index = int(job.get("stroke_index", -1))
		if stroke_index < 0 or stroke_index >= strokes.size():
			if _eraser_stroke_by_node_id.has(node_key):
				_finish_eraser_stroke(true)
			_cancel_eraser_jobs_for_node(node_key)
			continue
		var stroke = strokes[stroke_index]
		var points = stroke.get("points", [])
		var visible_image = cache.get("visible_image", null)
		if not (visible_image is Image) or visible_image.is_empty():
			if _eraser_stroke_by_node_id.has(node_key):
				_finish_eraser_stroke(true)
			_cancel_eraser_jobs_for_node(node_key)
			continue
		var baseline = job.get("gpu_baseline", null)
		if not (baseline is Image) or baseline.is_empty():
			baseline = visible_image
			job["gpu_baseline"] = baseline
			job["gpu_baseline_image_id"] = int(baseline.get_instance_id())
			job["expected_visible_image_id"] = int(visible_image.get_instance_id())
		var mode = str(job.get("mode", "cpu"))
		var gpu_available = _shadow_mask.has_method("render_gpu_stroke_async") and not bool(job.get("gpu_failed", false))
		var footprint_pixels = _eraser_clipped_footprint_pixels(job, visible_image)
		if mode == "cpu" and gpu_available and footprint_pixels > ERASER_GPU_FOOTPRINT_THRESHOLD_PIXELS:
			mode = "gpu"
			job["mode"] = mode
			job["state"] = null
			job["queued_point_index"] = 0
			job["gpu_rendered_point_count"] = 0
		if mode == "gpu":
			var rendered_point_count = int(job.get("gpu_rendered_point_count", 0))
			if bool(job.get("gpu_inflight", false)):
				queue[0] = job
				_eraser_pending_jobs[node_key] = queue
				continue
			if _eraser_gpu_inflight:
				queue[0] = job
				_eraser_pending_jobs[node_key] = queue
				continue
			if bool(job.get("closed", false)) and rendered_point_count >= points.size():
				queue.pop_front()
				if queue.empty():
					_eraser_pending_jobs.erase(node_key)
					_eraser_job_order.erase(node_key)
				else:
					_eraser_pending_jobs[node_key] = queue
				continue
			if rendered_point_count < points.size():
				queue[0] = job
				_eraser_pending_jobs[node_key] = queue
				_start_gpu_eraser_preview(node_key, job, source, cache, stroke, points)
			else:
				queue[0] = job
				_eraser_pending_jobs[node_key] = queue
			continue
		var state = job.get("state", null)
		if state == null:
			var template = stroke.duplicate(true)
			template["points"] = []
			state = _shadow_mask.call("begin_incremental", baseline, template, cache.pixel_to_local)
			if typeof(state) != TYPE_DICTIONARY or not state.get("ok", false):
				_last_error = str(state.get("error", "无法开始增量擦除。")) if typeof(state) == TYPE_DICTIONARY else "增量擦除初始化失败。"
				_last_operation = "擦除更新失败"
				if _eraser_stroke_by_node_id.has(node_key):
					_finish_eraser_stroke(true)
				_cancel_eraser_jobs_for_node(node_key)
				continue
			job["state"] = state
			cache["visible_used_rect"] = visible_image.get_used_rect()
			_shadow_render_cache[node_key] = cache
		if not bool(job.get("gpu_failed", false)):
			_eraser_last_backend = "cpu_incremental"
		var queued_point_index = int(job.get("queued_point_index", 0))
		while queued_point_index < points.size():
			var batch = []
			if queued_point_index == 0:
				batch.append(points[0])
				if points.size() > 1:
					batch.append(points[1])
					queued_point_index = 2
				else:
					queued_point_index = 1
			else:
				batch.append(points[queued_point_index - 1])
				batch.append(points[queued_point_index])
				queued_point_index += 1
			_shadow_mask.call("enqueue_incremental", state, batch)
		job["queued_point_index"] = queued_point_index
		job["state"] = state
		var remaining_pixels = max(1, ERASER_FRAME_PIXEL_BUDGET - _eraser_last_frame_processed_pixels)
		var remaining_usec = max(1, ERASER_FRAME_TIME_BUDGET_USEC - int(OS.get_ticks_usec() - frame_started))
		var advanced = _shadow_mask.call("advance_incremental", state, remaining_pixels, remaining_usec)
		if typeof(advanced) != TYPE_DICTIONARY or not advanced.get("ok", false):
			_last_error = str(advanced.get("error", "擦除计算失败。")) if typeof(advanced) == TYPE_DICTIONARY else "擦除计算失败。"
			_last_operation = "擦除更新失败"
			if _eraser_stroke_by_node_id.has(node_key):
				_finish_eraser_stroke(true)
			_cancel_eraser_jobs_for_node(node_key)
			continue
		_eraser_last_frame_processed_pixels += int(advanced.get("processed_pixels", 0))
		_eraser_processed_pixels_total += int(advanced.get("processed_pixels", 0))
		if advanced.get("changed", false):
			var changed_image = advanced.get("image", null)
			if changed_image is Image and not changed_image.is_empty():
				frame_images[node_key] = changed_image
				job["expected_visible_image_id"] = int(changed_image.get_instance_id())
		var pending = bool(advanced.get("pending", false))
		var closed = bool(job.get("closed", false))
		var has_unqueued_points = int(job.get("queued_point_index", 0)) < points.size()
		if closed and not pending and not has_unqueued_points:
			queue.pop_front()
			if queue.empty():
				_eraser_pending_jobs.erase(node_key)
				_eraser_job_order.erase(node_key)
			else:
				_eraser_pending_jobs[node_key] = queue
		else:
			queue[0] = job
			_eraser_pending_jobs[node_key] = queue
			if closed or pending or has_unqueued_points:
				_last_operation = "正在更新擦除…"
	if not _eraser_job_order.empty():
		_eraser_job_cursor = posmod(start_index + max(1, visited), _eraser_job_order.size())
	else:
		_eraser_job_cursor = 0
	var upload_started = OS.get_ticks_usec()
	for node_key in frame_images.keys():
		var source = Global.World.GetNodeByID(int(node_key)) if is_instance_valid(Global.World) else null
		var image = frame_images[node_key]
		_upload_eraser_image(str(node_key), source, image)
	_eraser_last_frame_upload_usec = int(OS.get_ticks_usec() - upload_started)
	_eraser_total_upload_usec += _eraser_last_frame_upload_usec
	_eraser_last_frame_usec = int(OS.get_ticks_usec() - frame_started)
	if not _eraser_pending_jobs.empty() and not _eraser_drawing:
		_last_operation = "正在更新擦除…"
	elif had_jobs and _eraser_pending_jobs.empty() and _last_error == "":
		_last_operation = "擦除更新完成"


func _upload_eraser_image(node_key : String, source, image : Image) -> bool:
	if not _is_source_node(source) or not (image is Image) or image.is_empty():
		return false
	var cache = _shadow_render_cache.get(node_key, {})
	if typeof(cache) != TYPE_DICTIONARY:
		return false
	var texture = cache.get("texture", null)
	if is_instance_valid(texture) and texture is ImageTexture and texture.has_method("set_data"):
		texture.set_data(image)
	else:
		var wrapper = _find_shadow(source)
		var shadow_sprite = null
		if wrapper != null:
			for child in wrapper.get_children():
				if child is Sprite:
					shadow_sprite = child
					break
		if shadow_sprite == null:
			return false
		var replacement = ImageTexture.new()
		replacement.create_from_image(image)
		shadow_sprite.texture = replacement
		cache["texture"] = replacement
	cache["visible_image"] = image
	cache["visible_used_rect"] = image.get_used_rect()
	_shadow_render_cache[node_key] = cache
	_eraser_texture_upload_count += 1
	_eraser_last_frame_uploads += 1
	return true


func _start_gpu_eraser_preview(node_key : String, job : Dictionary, source, cache : Dictionary, stroke : Dictionary, points : Array):
	if _eraser_gpu_inflight or not _shadow_mask.has_method("render_gpu_stroke_async"):
		return
	if not _eraser_job_is_current(job, source, cache):
		return
	var token = _eraser_gpu_token_counter + 1
	_eraser_gpu_token_counter = token
	var stroke_template = stroke.duplicate(true)
	stroke_template["points"] = []
	var point_snapshot = points.duplicate(true)
	var context = {
		"token": token,
		"node_key": node_key,
		"job_id": int(job.get("job_id", -1)),
		"snapshot_point_count": point_snapshot.size(),
		"source": source,
		"stroke_template": stroke_template
	}
	job["gpu_inflight"] = true
	job["gpu_token"] = token
	job["gpu_requested_point_count"] = point_snapshot.size()
	var queue = _eraser_pending_jobs.get(node_key, [])
	if queue.empty() or int(queue[0].get("job_id", -1)) != int(job.get("job_id", -2)):
		return
	queue[0] = job
	_eraser_pending_jobs[node_key] = queue
	_eraser_gpu_inflight = true
	_eraser_gpu_active_token = token
	var request = _shadow_mask.call("render_gpu_stroke_async", job.gpu_baseline, stroke_template, point_snapshot, cache.pixel_to_local, source)
	if request is GDScriptFunctionState:
		_eraser_gpu_wait_state = _await_gpu_eraser_preview(request, context)
	elif typeof(request) == TYPE_DICTIONARY:
		_complete_gpu_eraser_preview(context, request)
	else:
		_complete_gpu_eraser_preview(context, {"ok": false, "error": "GPU 擦除没有返回有效结果。"})


func _await_gpu_eraser_preview(request : GDScriptFunctionState, context : Dictionary):
	var result = yield(request, "completed")
	_complete_gpu_eraser_preview(context, result)


func _complete_gpu_eraser_preview(context : Dictionary, result):
	var token = int(context.get("token", -1))
	if _eraser_gpu_active_token == token:
		_eraser_gpu_inflight = false
		_eraser_gpu_active_token = -1
		_eraser_gpu_wait_state = null
	var node_key = str(context.get("node_key", ""))
	var queue = _eraser_pending_jobs.get(node_key, [])
	if typeof(queue) != TYPE_ARRAY or queue.empty():
		return
	var job = queue[0]
	if int(job.get("job_id", -1)) != int(context.get("job_id", -2)) or int(job.get("gpu_token", -1)) != token:
		return
	job["gpu_inflight"] = false
	job["gpu_token"] = -1
	var source = context.get("source", null)
	var cache = _shadow_render_cache.get(node_key, {})
	if not _eraser_job_is_current(job, source, cache):
		if _eraser_stroke_by_node_id.has(node_key):
			_finish_eraser_stroke(true)
		_cancel_eraser_jobs_for_node(node_key)
		return
	var snapshot_point_count = int(context.get("snapshot_point_count", 0))
	if typeof(result) == TYPE_DICTIONARY:
		_eraser_gpu_render_count += 1
		_eraser_gpu_last_render_msec = float(result.get("elapsed_ms", 0.0))
		_eraser_gpu_total_render_msec += _eraser_gpu_last_render_msec
		_eraser_gpu_last_backend = str(result.get("backend", "unknown"))
		_eraser_gpu_last_cpu_composite_frames = int(result.get("cpu_composite_frames", 0))
	else:
		_eraser_gpu_last_backend = "invalid_result"
		_eraser_gpu_last_cpu_composite_frames = 0
	if typeof(result) == TYPE_DICTIONARY and bool(result.get("ok", false)):
		var image = result.get("image", null)
		var upload_started = OS.get_ticks_usec()
		var upload_ok = image is Image and not image.is_empty() and _upload_eraser_image(node_key, source, image)
		if upload_ok:
			var upload_usec = int(OS.get_ticks_usec() - upload_started)
			_eraser_last_frame_upload_usec = upload_usec
			_eraser_total_upload_usec += upload_usec
			_eraser_last_frame_usec = max(_eraser_last_frame_usec, upload_usec)
			job["gpu_rendered_point_count"] = snapshot_point_count
			job["expected_visible_image_id"] = int(image.get_instance_id())
			_eraser_last_backend = _eraser_gpu_last_backend
			queue[0] = job
			_eraser_pending_jobs[node_key] = queue
			var latest_points_count = 0
			var current_strokes = _erasures.get(node_key, [])
			var current_stroke_index = int(job.get("stroke_index", -1))
			if current_stroke_index >= 0 and current_stroke_index < current_strokes.size():
				latest_points_count = current_strokes[current_stroke_index].get("points", []).size()
			if not bool(job.get("closed", false)) or snapshot_point_count < latest_points_count:
				_last_operation = "正在更新擦除…"
			return
	# A failed GPU preview is replayed once from the stroke-start image by the
	# bounded CPU worker. The renderer always returns a baseline-relative image,
	# so this also safely replaces any previous GPU preview.
	var strokes = _erasures.get(node_key, [])
	var stroke_index = int(job.get("stroke_index", -1))
	if stroke_index < 0 or stroke_index >= strokes.size():
		_cancel_eraser_jobs_for_node(node_key)
		return
	var stroke = strokes[stroke_index]
	var template = stroke.duplicate(true)
	template["points"] = []
	var baseline = job.get("gpu_baseline", null)
	var state = _shadow_mask.call("begin_incremental", baseline, template, cache.pixel_to_local)
	if typeof(state) != TYPE_DICTIONARY or not bool(state.get("ok", false)):
		_last_error = str(state.get("error", "无法开始擦除兼容回退。")) if typeof(state) == TYPE_DICTIONARY else "无法开始擦除兼容回退。"
		_last_operation = "擦除更新失败"
		if _eraser_stroke_by_node_id.has(node_key):
			_finish_eraser_stroke(true)
		_cancel_eraser_jobs_for_node(node_key)
		return
	var current_points = stroke.get("points", [])
	_queue_all_incremental_eraser_points(state, current_points)
	job["mode"] = "cpu"
	job["gpu_failed"] = true
	job["gpu_rendered_point_count"] = 0
	job["queued_point_index"] = current_points.size()
	job["state"] = state
	queue[0] = job
	_eraser_pending_jobs[node_key] = queue
	_eraser_last_backend = "cpu_fallback"
	_last_error = ""
	_last_notice = "已切换到渐进式擦除兼容模式。"
	_last_operation = "正在更新擦除…"


func _queue_all_incremental_eraser_points(state : Dictionary, points : Array):
	var point_index = 0
	while point_index < points.size():
		var batch = []
		if point_index == 0:
			batch.append(points[0])
			if points.size() > 1:
				batch.append(points[1])
				point_index = 2
			else:
				point_index = 1
		else:
			batch.append(points[point_index - 1])
			batch.append(points[point_index])
			point_index += 1
		_shadow_mask.call("enqueue_incremental", state, batch)


func _eraser_job_is_current(job : Dictionary, source, cache) -> bool:
	if not is_instance_valid(Global.World) or int(job.get("world_id", -1)) != int(Global.World.get_instance_id()):
		return false
	if str(job.get("map_file", "")) != _current_map_file():
		return false
	if not _is_source_node(source) or not source.is_inside_tree() or _stable_node_id(source) != int(job.get("node_id", -1)):
		return false
	if int(source.get_instance_id()) != int(job.get("source_instance_id", -1)):
		return false
	var level = _level_by_id(int(job.get("level_id", -1)))
	if not is_instance_valid(level) or not _source_is_on_level(source, level):
		return false
	if typeof(cache) != TYPE_DICTIONARY or not cache.has("visible_image") or not cache.has("pixel_to_local"):
		return false
	var image = cache.get("visible_image", null)
	if not (image is Image) or image.is_empty():
		return false
	var base_image = cache.get("image", null)
	if not (base_image is Image) or base_image.is_empty():
		return false
	var expected_base_image_id = int(job.get("base_image_id", -1))
	if expected_base_image_id >= 0 and int(base_image.get_instance_id()) != expected_base_image_id:
		return false
	if cache.pixel_to_local != job.get("pixel_to_local", Transform2D()):
		return false
	if source.global_transform != job.get("source_transform", source.global_transform):
		return false
	if _find_shadow(source) == null:
		return false
	var expected_image_id = int(job.get("expected_visible_image_id", -1))
	if expected_image_id >= 0 and int(image.get_instance_id()) != expected_image_id:
		return false
	return true


func _eraser_segment_may_hit_used_rect(node_key : String, points : Array, radius : float, radius_basis : Transform2D) -> bool:
	var cache = _shadow_render_cache.get(node_key, {})
	if typeof(cache) != TYPE_DICTIONARY or not cache.has("pixel_to_local"):
		return false
	var image = cache.get("visible_image", null)
	if not (image is Image) or image.is_empty():
		return false
	var used_rect = cache.get("visible_used_rect", null)
	if typeof(used_rect) != TYPE_RECT2:
		used_rect = image.get_used_rect()
		cache["visible_used_rect"] = used_rect
		_shadow_render_cache[node_key] = cache
	if used_rect.size.x <= 0.0 or used_rect.size.y <= 0.0:
		return false
	var local_to_pixel = cache.pixel_to_local.affine_inverse()
	var brush_to_pixel = local_to_pixel * radius_basis
	var extent_x = radius * sqrt(brush_to_pixel.x.x * brush_to_pixel.x.x + brush_to_pixel.y.x * brush_to_pixel.y.x)
	var extent_y = radius * sqrt(brush_to_pixel.x.y * brush_to_pixel.x.y + brush_to_pixel.y.y * brush_to_pixel.y.y)
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	for raw_point in points:
		var point = _vector_from_value(raw_point)
		if point == null:
			continue
		var pixel_point = local_to_pixel.xform(point)
		min_x = min(min_x, pixel_point.x)
		min_y = min(min_y, pixel_point.y)
		max_x = max(max_x, pixel_point.x)
		max_y = max(max_y, pixel_point.y)
	if min_x == INF:
		return false
	min_x -= extent_x
	min_y -= extent_y
	max_x += extent_x
	max_y += extent_y
	return max_x >= used_rect.position.x and min_x <= used_rect.position.x + used_rect.size.x and max_y >= used_rect.position.y and min_y <= used_rect.position.y + used_rect.size.y


func _brush_intersects_shadow(node_key : String, center_local : Vector2, radius : float, radius_basis : Transform2D) -> bool:
	var cache = _shadow_render_cache.get(node_key, {})
	if typeof(cache) != TYPE_DICTIONARY or not cache.has("pixel_to_local"):
		return false
	var image = cache.get("visible_image", cache.get("image", null))
	if not (image is Image) or image.is_empty():
		return false
	var pixel_to_local = cache.pixel_to_local
	var local_to_pixel = pixel_to_local.affine_inverse()
	var center_pixel = local_to_pixel.xform(center_local)
	var brush_to_pixel = local_to_pixel * radius_basis
	var extent_x = radius * sqrt(brush_to_pixel.x.x * brush_to_pixel.x.x + brush_to_pixel.y.x * brush_to_pixel.y.x)
	var extent_y = radius * sqrt(brush_to_pixel.x.y * brush_to_pixel.x.y + brush_to_pixel.y.y * brush_to_pixel.y.y)
	var left = max(0, int(floor(center_pixel.x - extent_x - 0.5)))
	var top = max(0, int(floor(center_pixel.y - extent_y - 0.5)))
	var right = min(image.get_width() - 1, int(ceil(center_pixel.x + extent_x - 0.5)))
	var bottom = min(image.get_height() - 1, int(ceil(center_pixel.y + extent_y - 0.5)))
	if right < left or bottom < top:
		return false
	var local_to_brush = radius_basis.affine_inverse()
	image.lock()
	var hit = false
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			if image.get_pixel(x, y).a <= ALPHA_CUTOFF:
				continue
			var pixel_local = pixel_to_local.xform(Vector2(float(x) + 0.5, float(y) + 0.5))
			if local_to_brush.basis_xform(pixel_local - center_local).length_squared() <= radius * radius:
				hit = true
				break
		if hit:
			break
	image.unlock()
	return hit


func _apply_erasures_to_source(source, node_key : String) -> bool:
	if _eraser_stroke_by_node_id.has(node_key):
		_finish_eraser_stroke(true)
	_cancel_eraser_jobs_for_node(node_key)
	var cache = _shadow_render_cache.get(node_key, {})
	if typeof(cache) != TYPE_DICTIONARY or not cache.has("image") or not cache.has("pixel_to_local"):
		return false
	var image = _shadow_mask.apply(cache.image, _erasures.get(node_key, []), cache.pixel_to_local)
	if not (image is Image) or image.is_empty():
		return false
	cache["visible_image"] = image
	cache["visible_used_rect"] = image.get_used_rect()
	_shadow_render_cache[node_key] = cache
	var wrapper = _find_shadow(source)
	if wrapper == null:
		return false
	var shadow_sprite = null
	for child in wrapper.get_children():
		if child is Sprite:
			shadow_sprite = child
			break
	if shadow_sprite == null:
		return false
	var image_texture = cache.get("texture", shadow_sprite.texture)
	if image_texture == shadow_sprite.texture and is_instance_valid(image_texture) and image_texture is ImageTexture and image_texture.has_method("set_data"):
		image_texture.set_data(image)
	else:
		image_texture = ImageTexture.new()
		image_texture.create_from_image(image)
		shadow_sprite.texture = image_texture
	cache["texture"] = image_texture
	_shadow_render_cache[node_key] = cache
	return true


func add_erase_stroke(node_id : int, local_points : Array, radius_world : float, world_radius_basis, hardness : float = 1.0) -> Dictionary:
	var key = str(int(node_id))
	var source = Global.World.GetNodeByID(int(node_id)) if is_instance_valid(Global.World) else null
	if not _is_source_node(source) or _find_shadow(source) == null:
		return _operation_notice("该对象/路径当前没有可擦除的轮廓投影。", "shadow_missing")
	# Explicit API strokes synchronize earlier queued pointer work before testing
	# against the visible alpha, then use the existing deterministic full replay.
	if _eraser_stroke_by_node_id.has(key):
		_finish_eraser_stroke(true)
	_apply_erasures_to_source(source, key)
	var parsed_points = []
	for raw_point in local_points:
		var point = _vector_from_value(raw_point)
		if point != null:
			parsed_points.append(point)
	if parsed_points.empty() or radius_world <= 0.0:
		return _operation_error("擦除笔画需要有效的局部坐标点和正半径。")
	var basis = _radius_basis_from_value(world_radius_basis)
	if abs(basis.x.x * basis.y.y - basis.x.y * basis.y.x) < 0.000001:
		return _operation_error("擦除笔刷变换不可逆。")
	if not _erase_stroke_intersects_shadow(key, parsed_points, radius_world, basis):
		return {"ok": true, "recorded": false, "reason": "no_shadow_intersection"}
	var stroke = {
		"points": [],
		"radius": radius_world,
		"hardness": clamp(float(hardness), 0.0, 1.0),
		"radius_basis": _serialize_radius_basis(basis)
	}
	for point in parsed_points:
		stroke.points.append([point.x, point.y])
	var strokes = _erasures.get(key, [])
	strokes.append(stroke)
	_erasures[key] = strokes
	_erase_undo_stack.append([{"node_id": key, "stroke": stroke.duplicate(true)}])
	_apply_erasures_to_source(source, key)
	_generated_fingerprints[key] = _source_signature(source)
	_save_map_recipe()
	return {"ok": true, "recorded": true, "node_id": int(node_id), "stroke_count": strokes.size()}


func _erase_stroke_intersects_shadow(node_key : String, points : Array, radius : float, basis : Transform2D) -> bool:
	if _shadow_mask == null or not _shadow_mask.has_method("intersects"):
		return false
	var cache = _shadow_render_cache.get(node_key, {})
	if typeof(cache) != TYPE_DICTIONARY or not cache.has("pixel_to_local"):
		return false
	var image = cache.get("visible_image", null)
	if not (image is Image) or image.is_empty():
		return false
	if not _eraser_segment_may_hit_used_rect(node_key, points, radius, basis):
		return false
	var stroke = {
		"points": [],
		"radius": radius,
		"radius_basis": _serialize_radius_basis(basis)
	}
	for point in points:
		var vector = _vector_from_value(point)
		if vector != null:
			stroke.points.append([vector.x, vector.y])
	return bool(_shadow_mask.call("intersects", image, stroke, cache.pixel_to_local))


func _finish_eraser_stroke(record_undo : bool, persist : bool = true):
	if not _eraser_gesture_node_ids.empty():
		var undo_entries = []
		for key in _eraser_gesture_node_ids:
			var strokes = _erasures.get(key, [])
			var stroke_index = int(_eraser_stroke_by_node_id.get(key, -1))
			if stroke_index >= 0 and stroke_index < strokes.size():
				undo_entries.append({"node_id": key, "stroke": strokes[stroke_index].duplicate(true)})
				_mark_eraser_job_closed(str(key), stroke_index)
		if record_undo and not undo_entries.empty():
			_erase_undo_stack.append(undo_entries)
		if persist:
			for key in _eraser_gesture_node_ids:
				var source = Global.World.GetNodeByID(int(key)) if is_instance_valid(Global.World) else null
				if is_instance_valid(source):
					_generated_fingerprints[str(key)] = _source_signature(source)
		if persist:
			_save_map_recipe()
	_eraser_drawing = false
	_eraser_gesture_node_ids.clear()
	_eraser_stroke_by_node_id.clear()
	if not _eraser_pending_jobs.empty():
		_last_operation = "正在更新擦除…"


func _mark_eraser_job_closed(node_key : String, stroke_index : int):
	var queue = _eraser_pending_jobs.get(node_key, [])
	if typeof(queue) != TYPE_ARRAY:
		return
	for index in range(queue.size()):
		var job = queue[index]
		if int(job.get("stroke_index", -1)) == stroke_index:
			job["closed"] = true
			queue[index] = job
			_eraser_pending_jobs[node_key] = queue
			return


func _cancel_eraser_jobs_for_node(node_key : String):
	_eraser_pending_jobs.erase(node_key)
	_eraser_job_order.erase(node_key)
	if _eraser_job_order.empty():
		_eraser_job_cursor = 0
	else:
		_eraser_job_cursor = posmod(_eraser_job_cursor, _eraser_job_order.size())


func _cancel_all_eraser_jobs():
	_eraser_pending_jobs.clear()
	_eraser_job_order.clear()
	_eraser_job_cursor = 0


func undo_last_erase() -> Dictionary:
	_finish_eraser_stroke(true)
	if _erase_undo_stack.empty():
		return _operation_notice("当前会话没有可撤销的擦除笔画。", "undo_empty")
	var gesture = _erase_undo_stack.pop_back()
	var restored = 0
	for entry in gesture:
		var key = str(entry.node_id)
		var strokes = _erasures.get(key, [])
		if strokes.empty() or JSON.print(strokes[strokes.size() - 1]) != JSON.print(entry.stroke):
			continue
		strokes.pop_back()
		if strokes.empty():
			_erasures.erase(key)
		else:
			_erasures[key] = strokes
		var source = Global.World.GetNodeByID(int(key)) if is_instance_valid(Global.World) else null
		if is_instance_valid(source):
			_apply_erasures_to_source(source, key)
			_generated_fingerprints[key] = _source_signature(source)
		restored += 1
	_save_map_recipe()
	_last_operation = "已撤销上一笔擦除，恢复 %d 个对象/路径" % restored
	return {"ok": true, "restored": restored}


func restore_selected_erasures() -> Dictionary:
	_finish_eraser_stroke(true)
	var level = _current_level()
	if level == null:
		return _operation_error("没有打开的地图楼层。")
	var sources = _selected_sources(level)
	if sources.empty():
		return _operation_notice("请先记录要恢复阴影擦除的对象或路径。", "selection_missing")
	var restored = 0
	for source in sources:
		var key = str(_stable_node_id(source))
		if not _erasures.has(key):
			continue
		_erasures.erase(key)
		_erase_undo_stack.clear()
		_apply_erasures_to_source(source, key)
		_generated_fingerprints[key] = _source_signature(source)
		restored += 1
	var saved = _save_map_recipe()
	_last_operation = "已恢复 %d 个选中对象/路径的阴影擦除" % restored
	return {"ok": true, "restored": restored, "map_data_saved": saved}


func _cancel_queued_level(level_id : int):
	var remaining = []
	for item in _generation_queue:
		if int(item.level_id) == level_id:
			_pending_node_ids.erase(str(item.node_id))
		else:
			remaining.append(item)
	_generation_queue = remaining
	if _active_generation_level_id == level_id and _active_generation_node_key != "":
		_pending_node_ids.erase(_active_generation_node_key)
		_generation_in_progress = false
		_active_generation_token = -1
		_active_generation_level_id = -1
		_active_generation_node_key = ""


func _cancel_queued_node(node_key : String):
	var remaining = []
	for item in _generation_queue:
		if str(item.node_id) == node_key:
			_pending_node_ids.erase(node_key)
		else:
			remaining.append(item)
	_generation_queue = remaining
	if _active_generation_node_key == node_key:
		_pending_node_ids.erase(node_key)
		_generation_in_progress = false
		_active_generation_token = -1
		_active_generation_level_id = -1
		_active_generation_node_key = ""


func _level_by_id(level_id : int):
	if not is_instance_valid(Global.World):
		return null
	for level in Global.World.levels:
		if is_instance_valid(level) and int(level.ID) == level_id:
			return level
	return null


func _level_for_prop(prop):
	return _level_for_source(prop)


func _level_for_source(source):
	if not _is_source_node(source) or not is_instance_valid(Global.World):
		return null
	for level in Global.World.levels:
		if is_instance_valid(level) and _source_is_on_level(source, level):
			return level
	return null


func _update_status():
	if _status_label == null:
		return
	if _generation_in_progress or not _generation_queue.empty():
		var progress = "%d/%d" % [_generation_batch_done, _generation_batch_total]
		if _generation_in_progress and _active_generation_node_key != "":
			_status_label.text = "正在生成目标 %s · %s 完成 · 队列 %d" % [_active_generation_node_key, progress, _generation_queue.size()]
		else:
			_status_label.text = "等待生成 · %s 完成 · 队列 %d" % [progress, _generation_queue.size()]
	elif _parameter_refresh_pending:
		var target_count = _parameter_refresh_node_ids.size()
		if _parameter_refresh_global:
			target_count = max(target_count, _enabled_node_ids.size())
		_status_label.text = "等待参数稳定 · %.1f 秒后刷新 %d 个目标" % [max(0.0, _parameter_refresh_delay), target_count]
	elif _eraser_has_closed_pending_jobs():
		_status_label.text = "正在更新擦除…"
	elif _last_error != "":
		_status_label.text = "错误：" + _last_error
	else:
		_status_label.text = _last_operation


func _eraser_has_closed_pending_jobs() -> bool:
	for key in _eraser_pending_jobs.keys():
		for job in _eraser_pending_jobs[key]:
			if bool(job.get("closed", false)):
				return true
	return false


func _operation_error(message : String) -> Dictionary:
	_last_error = message
	_last_notice = ""
	_last_operation = "操作失败"
	return {"ok": false, "error": message}


func _operation_notice(message : String, reason : String) -> Dictionary:
	_last_error = ""
	_last_notice = message
	_last_operation = message
	return {"ok": false, "notice": message, "reason": reason}


func get_diagnostics() -> Dictionary:
	var level = _current_level()
	var prop_count = 0
	var pathway_count = 0
	var source_count = 0
	var current_shadow_count = 0
	var erasure_stroke_count = 0
	var eraser_pending_job_count = 0
	var eraser_queued_segment_count = 0
	var erasure_counts = {}
	if level != null:
		for source in _level_sources(level):
			source_count += 1
			if _is_pathway_source(source):
				pathway_count += 1
			else:
				prop_count += 1
			if _find_shadow(source) != null:
				current_shadow_count += 1
	for key in _erasures.keys():
		var strokes = _erasures[key]
		var count = strokes.size() if typeof(strokes) == TYPE_ARRAY else 0
		erasure_counts[str(key)] = count
		erasure_stroke_count += count
	for key in _eraser_pending_jobs.keys():
		for erase_job in _eraser_pending_jobs[key]:
			eraser_pending_job_count += 1
			var erase_stroke_index = int(erase_job.get("stroke_index", -1))
			var erase_strokes = _erasures.get(str(key), [])
			var erase_points = []
			if erase_stroke_index >= 0 and erase_stroke_index < erase_strokes.size():
				erase_points = erase_strokes[erase_stroke_index].get("points", [])
			if str(erase_job.get("mode", "cpu")) == "gpu":
				eraser_queued_segment_count += max(0, erase_points.size() - int(erase_job.get("gpu_rendered_point_count", 0)))
			else:
				eraser_queued_segment_count += max(0, erase_points.size() - int(erase_job.get("queued_point_index", 0)))
			var erase_state = erase_job.get("state", null)
			if typeof(erase_state) == TYPE_DICTIONARY:
				var erase_segments = erase_state.get("segments", [])
				eraser_queued_segment_count += max(0, erase_segments.size() - int(erase_state.get("segment_head", 0)))
	return {
		"ok": true,
		"tool_id": TOOL_ID,
		"map_title": str(Global.World.Title) if is_instance_valid(Global.World) else "",
		"map_file": _current_map_file(),
		"level_id": int(level.ID) if level != null else -1,
		"props": prop_count,
		"pathways": pathway_count,
		"sources": source_count,
		"shadows": current_shadow_count,
		"enabled": _enabled_node_ids.size(),
		"excluded": _excluded_node_ids.size(),
		"overrides": _overrides.size(),
		"override_node_ids": _sorted_node_ids(_overrides),
		"erasures": erasure_stroke_count,
		"erasure_strokes": erasure_stroke_count,
		"erasure_counts": erasure_counts,
		"erasure_node_ids": _sorted_node_ids(_erasures),
		"queued": _generation_queue.size(),
		"pending_node_ids": _sorted_node_ids(_pending_node_ids),
		"generation_in_progress": _generation_in_progress,
		"generation_batch_total": _generation_batch_total,
		"generation_batch_done": _generation_batch_done,
		"generation_epoch": _generation_epoch,
		"active_generation_token": _active_generation_token,
		"active_generation_level_id": _active_generation_level_id,
		"active_generation_node_id": int(_active_generation_node_key) if _active_generation_node_key != "" else -1,
		"extraction_cache_items": _extraction_cache.size(),
		"extraction_cache_bytes": _extraction_cache_bytes,
		"shadow_cache_items": _shadow_render_cache.size(),
		"parameter_refresh_pending": _parameter_refresh_pending,
		"parameter_refresh_delay": _parameter_refresh_delay,
		"parameter_refresh_global": _parameter_refresh_global,
		"parameter_refresh_node_ids": _sorted_node_ids(_parameter_refresh_node_ids),
		"parameter_refresh_event_count": _parameter_refresh_event_count,
		"parameter_refresh_batch_count": _parameter_refresh_batch_count,
		"render_count": _render_count_total,
		"last_render_backend": _last_render_backend,
		"last_render_msec": _last_render_msec,
		"total_render_msec": _total_render_msec,
		"active_tool": _active_tool_name(),
		"follow": follow_enabled,
		"preview": preview_enabled,
		"renderer_loaded": _renderer != null,
		"renderer_work_limit": int(_renderer.call("get_work_limit")) if _renderer != null and _renderer.has_method("get_work_limit") else -1,
		"geometry_loaded": _geometry != null,
		"path_source_loaded": _path_source != null,
		"shadow_mask_loaded": _shadow_mask != null,
		"adjustment_mode": adjustment_mode,
		"eraser_enabled": eraser_enabled,
		"eraser_drawing": _eraser_drawing,
		"eraser_radius": eraser_radius,
		"eraser_size": eraser_radius * 2.0,
		"eraser_hardness": eraser_hardness,
		"active_erase_node_ids": _eraser_gesture_node_ids.duplicate(),
		"eraser_pending_jobs": eraser_pending_job_count,
		"eraser_queued_segments": eraser_queued_segment_count,
		"eraser_processed_pixels_total": _eraser_processed_pixels_total,
		"eraser_last_frame_processed_pixels": _eraser_last_frame_processed_pixels,
		"eraser_texture_upload_count": _eraser_texture_upload_count,
		"eraser_last_frame_uploads": _eraser_last_frame_uploads,
		"eraser_last_frame_usec": _eraser_last_frame_usec,
		"eraser_last_frame_upload_usec": _eraser_last_frame_upload_usec,
		"eraser_total_upload_usec": _eraser_total_upload_usec,
		"eraser_gpu_inflight": _eraser_gpu_inflight,
		"eraser_gpu_render_count": _eraser_gpu_render_count,
		"eraser_gpu_last_render_msec": _eraser_gpu_last_render_msec,
		"eraser_gpu_total_render_msec": _eraser_gpu_total_render_msec,
		"eraser_gpu_last_backend": _eraser_gpu_last_backend,
		"eraser_gpu_last_cpu_composite_frames": _eraser_gpu_last_cpu_composite_frames,
		"eraser_last_backend": _eraser_last_backend,
		"mod_map_data_available": typeof(Global.ModMapData) == TYPE_DICTIONARY,
		"last_operation": _last_operation,
		"last_error": _last_error,
		"last_notice": _last_notice,
		"selected_type": _last_selection_type,
		"selected_type_code": _last_selection_type_code,
		"selected_count": _last_selection_count,
		"selected_prop_count": _last_selected_prop_count,
		"selected_path_count": _last_selected_path_count,
		"selected_source_count": _last_selected_prop_count + _last_selected_path_count,
		"selected_source": _last_selection_source,
		"selection_snapshot_node_ids": _selection_snapshot_node_ids.duplicate(),
		"selection_snapshot_count": _selection_snapshot_node_ids.size(),
		"selection_record_cleared": _selection_record_cleared,
		"selection_highlight_count": _selection_highlight_node_ids.size(),
		"last_generated": _last_generated,
		"last_removed": _last_removed,
		"last_skipped": _last_skipped
	}


func _sync_controls():
	if _angle_slider == null:
		return
	_syncing_controls = true
	var settings = _parameter_settings_dictionary()
	var selected_ids = _selected_source_ids() if adjustment_mode == "individual" else []
	if not selected_ids.empty():
		settings = get_effective_settings(int(selected_ids[0]))
	_angle_slider.value = float(settings.angle)
	_distance_slider.value = float(settings.distance)
	_blur_slider.value = float(settings.blur_radius)
	_opacity_slider.value = float(settings.opacity) * 100.0
	if _angle_value_label != null:
		_angle_value_label.text = "方向 °"
	if _distance_value_label != null:
		_distance_value_label.text = "距离 px"
	if _blur_value_label != null:
		_blur_value_label.text = "柔化 px"
	if _opacity_value_label != null:
		_opacity_value_label.text = "不透明度 %"
	var current_mode = str(settings.mode)
	_set_panel_button_text(_offset_mode_button, "短投影 ✓" if current_mode == "offset" else "短投影")
	_set_panel_button_text(_sweep_mode_button, "连续延展 ✓" if current_mode == "sweep" else "连续延展")
	if _color_label != null:
		var color = _parse_color(str(settings.color), shadow_color)
		_color_label.text = "颜色 · #" + color.to_html(false)
		_sync_color_palette_node(_color_palette, color)
	if _follow_button != null:
		_follow_button.pressed = follow_enabled
	if _preview_button != null:
		_preview_button.pressed = preview_enabled
	_set_panel_button_text(_global_adjust_button, "全局调整 ✓" if adjustment_mode == "global" else "全局调整")
	_set_panel_button_text(_individual_adjust_button, "单独调整 ✓" if adjustment_mode == "individual" else "单独调整")
	if _use_global_button != null:
		_use_global_button.visible = adjustment_mode == "individual"
	if _scope_label != null:
		if adjustment_mode == "global":
			_scope_label.text = "作用范围：全局默认"
		elif selected_ids.empty():
			_scope_label.text = "作用范围：单独调整 · 尚无目标；全局默认不变"
		else:
			_scope_label.text = "作用范围：单独调整 · 修改将应用到 %d 个目标" % selected_ids.size()
	if _eraser_button != null:
		_eraser_button.pressed = eraser_enabled
	if _eraser_radius_slider != null:
		_eraser_radius_slider.value = eraser_radius * 2.0
	if _eraser_radius_value_label != null:
		_eraser_radius_value_label.text = "直径 px"
	if _eraser_hardness_slider != null:
		_eraser_hardness_slider.value = eraser_hardness * 100.0
	if _eraser_hardness_value_label != null:
		_eraser_hardness_value_label.text = "硬度 %"
	_syncing_controls = false


func _sync_color_palette_node(node, color : Color) -> bool:
	if not is_instance_valid(node):
		return false
	if node is ColorPickerButton:
		node.color = color
		return true
	for child in node.get_children():
		if _sync_color_palette_node(child, color):
			return true
	return false


func GenerateCurrentLevel():
	return generate_current_level()


func GenerateSelected():
	return generate_selected()


func ClearShadows():
	return clear_shadows()


func ExcludeSelected():
	return exclude_selected()


func RestoreSelected():
	return restore_selected()


func BeginSelectionMode():
	return begin_selection_mode()


func ClearSelectionRecord():
	return clear_selection_record()


func GetDiagnostics():
	return get_diagnostics()


func Configure(options : Dictionary):
	return configure(options)


func SetPreview(value : bool):
	return set_preview(value)
