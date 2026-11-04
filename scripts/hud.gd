extends CanvasLayer
## Race HUD built in code (no theme/scene assets required).
##
## Shows a digital speedometer, gear, nitrous meter, lap counter, live lap
## timer, saved best lap, the 3-2-1-GO countdown, a pause menu and a finish
## summary with a Restart button.

const ACCENT := Color(1.0, 0.82, 0.28)
const COOL := Color(0.55, 0.88, 1.0)
const GOOD := Color(0.45, 1.0, 0.55)

var _car: Node = null
var _lap_manager: Node = null
var _touch_hud: Node = null

var _lap_label: Label
var _time_label: Label
var _best_label: Label
var _speed_label: Label
var _gear_label: Label
var _nitrous_label: Label
var _nitrous_bar: ProgressBar
var _countdown_label: Label
var _pause_button: Button
var _pause_root: Control
var _finish_root: CenterContainer
var _result_label: Label
var _restart_button: Button
var _leaderboard_rows: Array = []

var _paused := false
var _leaderboard_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

	_car = get_tree().get_first_node_in_group("player_car")
	_lap_manager = get_tree().get_first_node_in_group("race_manager")
	_touch_hud = get_tree().get_first_node_in_group("touch_hud")

	if _lap_manager != null:
		if _lap_manager.has_signal("countdown_changed"):
			_lap_manager.countdown_changed.connect(_on_countdown_changed)
		if _lap_manager.has_signal("lap_completed"):
			_lap_manager.lap_completed.connect(_on_lap_completed)
		if _lap_manager.has_signal("race_finished"):
			_lap_manager.race_finished.connect(_on_race_finished)
		if _lap_manager.has_signal("race_started"):
			_lap_manager.race_started.connect(_on_race_started)
		_best_label.text = "BEST  " + _format_time(float(_lap_manager.best_lap))


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if _lap_manager != null and _lap_manager.is_finished:
			return
		_set_paused(not _paused)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _car == null:
		_car = get_tree().get_first_node_in_group("player_car")
	if _car != null:
		if _speed_label != null:
			var speed: float = _car.current_speed_kmh
			_speed_label.text = str(int(round(speed)))
		if _gear_label != null:
			_gear_label.text = "GEAR  R" if bool(_car.reverse_gear) else "GEAR  D"
		if _nitrous_bar != null:
			_nitrous_bar.value = clampf(float(_car.nitrous_amount) * 100.0, 0.0, 100.0)
		if _nitrous_label != null:
			var nitro_color := ACCENT if bool(_car.nitrous_active) else COOL
			_nitrous_label.add_theme_color_override("font_color", nitro_color)

	if _lap_manager == null:
		return

	if _lap_label != null:
		var total: int = int(_lap_manager.total_laps)
		var lap: int = clampi(int(_lap_manager.current_lap), 1, total)
		_lap_label.text = "LAP  %d / %d" % [lap, total]
	if _time_label != null:
		_time_label.text = "TIME  " + _format_time(float(_lap_manager.get_current_lap_time()))
	if _best_label != null:
		_best_label.text = "BEST  " + _format_time(float(_lap_manager.best_lap))

	_update_leaderboard(delta)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Top-left telemetry ---------------------------------------------------
	var stats_panel := PanelContainer.new()
	stats_panel.position = Vector2(20, 16)
	stats_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.05, 0.08, 0.62)))
	root.add_child(stats_panel)

	var stats_margin := MarginContainer.new()
	stats_margin.add_theme_constant_override("margin_left", 18)
	stats_margin.add_theme_constant_override("margin_top", 12)
	stats_margin.add_theme_constant_override("margin_right", 22)
	stats_margin.add_theme_constant_override("margin_bottom", 12)
	stats_panel.add_child(stats_margin)

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 1)
	stats_margin.add_child(stats)

	_lap_label = _make_label("LAP  1 / 3", 28, ACCENT)
	_time_label = _make_label("TIME  00:00.000", 26, Color(0.95, 0.97, 1.0))
	_best_label = _make_label("BEST  --:--.---", 21, COOL)
	stats.add_child(_lap_label)
	stats.add_child(_time_label)
	stats.add_child(_best_label)

	# --- Pause button ---------------------------------------------------------
	_pause_button = Button.new()
	_pause_button.text = "PAUSE"
	_pause_button.position = Vector2(20, 150)
	_pause_button.size = Vector2(130, 44)
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.add_theme_font_size_override("font_size", 18)
	_pause_button.pressed.connect(_toggle_pause)
	root.add_child(_pause_button)

	# --- Top-right digital speedometer ---------------------------------------
	var speed_panel := PanelContainer.new()
	speed_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	speed_panel.offset_left = -272
	speed_panel.offset_top = 16
	speed_panel.offset_right = -20
	speed_panel.offset_bottom = 214
	speed_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.05, 0.08, 0.62)))
	root.add_child(speed_panel)

	var speed_margin := MarginContainer.new()
	speed_margin.add_theme_constant_override("margin_left", 18)
	speed_margin.add_theme_constant_override("margin_top", 6)
	speed_margin.add_theme_constant_override("margin_right", 22)
	speed_margin.add_theme_constant_override("margin_bottom", 8)
	speed_panel.add_child(speed_margin)

	var speed_box := VBoxContainer.new()
	speed_box.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_box.add_theme_constant_override("separation", -8)
	speed_margin.add_child(speed_box)

	_speed_label = _make_label("0", 66, Color(0.97, 0.99, 1.0))
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_box.add_child(_speed_label)

	var unit := _make_label("KM/H", 20, COOL)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_box.add_child(unit)

	_gear_label = _make_label("GEAR  D", 20, Color(0.95, 0.97, 1.0))
	_gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_box.add_child(_gear_label)

	_nitrous_label = _make_label("NITROUS", 15, COOL)
	_nitrous_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_box.add_child(_nitrous_label)

	_nitrous_bar = ProgressBar.new()
	_nitrous_bar.custom_minimum_size = Vector2(0, 12)
	_nitrous_bar.max_value = 100.0
	_nitrous_bar.value = 100.0
	_nitrous_bar.show_percentage = false
	_nitrous_bar.add_theme_stylebox_override("background", _bar_style(Color(0.08, 0.11, 0.16, 0.95)))
	_nitrous_bar.add_theme_stylebox_override("fill", _bar_style(Color(0.16, 0.78, 1.0)))
	speed_box.add_child(_nitrous_bar)

	# --- Leaderboard ----------------------------------------------------------
	var leaderboard_panel := PanelContainer.new()
	leaderboard_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	leaderboard_panel.offset_left = -272
	leaderboard_panel.offset_top = 226
	leaderboard_panel.offset_right = -20
	leaderboard_panel.offset_bottom = 438
	leaderboard_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.05, 0.08, 0.62)))
	root.add_child(leaderboard_panel)

	var leaderboard_margin := MarginContainer.new()
	leaderboard_margin.add_theme_constant_override("margin_left", 16)
	leaderboard_margin.add_theme_constant_override("margin_top", 8)
	leaderboard_margin.add_theme_constant_override("margin_right", 16)
	leaderboard_margin.add_theme_constant_override("margin_bottom", 10)
	leaderboard_panel.add_child(leaderboard_margin)

	var leaderboard_box := VBoxContainer.new()
	leaderboard_box.add_theme_constant_override("separation", 3)
	leaderboard_margin.add_child(leaderboard_box)

	var leaderboard_title := _make_label("STANDINGS", 17, ACCENT)
	leaderboard_box.add_child(leaderboard_title)

	for i in 5:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.visible = false
		leaderboard_box.add_child(row)

		var position_label := _make_label("", 17, Color(0.93, 0.96, 1.0))
		position_label.custom_minimum_size = Vector2(28, 0)
		row.add_child(position_label)

		var name_label := _make_label("", 17, Color(0.93, 0.96, 1.0))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var lap_label := _make_label("", 17, Color(0.93, 0.96, 1.0))
		lap_label.custom_minimum_size = Vector2(46, 0)
		lap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(lap_label)

		_leaderboard_rows.append({
			"row": row,
			"position": position_label,
			"name": name_label,
			"lap": lap_label,
		})

	# --- Countdown ------------------------------------------------------------
	_countdown_label = _make_label("", 160, Color(1.0, 1.0, 1.0))
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.visible = false
	root.add_child(_countdown_label)

	# --- Pause menu -----------------------------------------------------------
	_pause_root = Control.new()
	_pause_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_root.visible = false
	root.add_child(_pause_root)

	var pause_shade := ColorRect.new()
	pause_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_shade.color = Color(0.0, 0.0, 0.0, 0.62)
	pause_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_root.add_child(pause_shade)

	var pause_center := CenterContainer.new()
	pause_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_root.add_child(pause_center)

	var pause_panel := PanelContainer.new()
	pause_panel.custom_minimum_size = Vector2(520, 400)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.06, 0.1, 0.97), 20, 2))
	pause_center.add_child(pause_panel)

	var pause_margin := MarginContainer.new()
	pause_margin.add_theme_constant_override("margin_left", 38)
	pause_margin.add_theme_constant_override("margin_top", 30)
	pause_margin.add_theme_constant_override("margin_right", 38)
	pause_margin.add_theme_constant_override("margin_bottom", 30)
	pause_panel.add_child(pause_margin)

	var pause_box := VBoxContainer.new()
	pause_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_box.add_theme_constant_override("separation", 16)
	pause_margin.add_child(pause_box)

	var pause_title := _make_label("PAUSED", 46, ACCENT)
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(pause_title)

	var pause_hint := _make_label("Race timer is paused", 20, Color(0.85, 0.9, 1.0))
	pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(pause_hint)

	var resume_button := _make_button("RESUME", 26)
	resume_button.pressed.connect(_on_resume_pressed)
	pause_box.add_child(resume_button)

	var pause_reset := _make_button("RESET CAR", 24)
	pause_reset.pressed.connect(_on_pause_reset_pressed)
	pause_box.add_child(pause_reset)

	var pause_restart := _make_button("RESTART RACE", 24)
	pause_restart.pressed.connect(_on_restart_pressed)
	pause_box.add_child(pause_restart)

	# --- Finish summary -------------------------------------------------------
	_finish_root = CenterContainer.new()
	_finish_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_finish_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finish_root.visible = false
	root.add_child(_finish_root)

	var finish_panel := PanelContainer.new()
	finish_panel.custom_minimum_size = Vector2(600, 380)
	finish_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	finish_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.06, 0.1, 0.96), 20, 2))
	_finish_root.add_child(finish_panel)

	var finish_margin := MarginContainer.new()
	finish_margin.add_theme_constant_override("margin_left", 38)
	finish_margin.add_theme_constant_override("margin_top", 32)
	finish_margin.add_theme_constant_override("margin_right", 38)
	finish_margin.add_theme_constant_override("margin_bottom", 32)
	finish_panel.add_child(finish_margin)

	var finish_box := VBoxContainer.new()
	finish_box.alignment = BoxContainer.ALIGNMENT_CENTER
	finish_box.add_theme_constant_override("separation", 18)
	finish_margin.add_child(finish_box)

	var title := _make_label("RACE COMPLETE", 44, ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	finish_box.add_child(title)

	_result_label = _make_label("", 25, Color(0.92, 0.95, 1.0))
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	finish_box.add_child(_result_label)

	_restart_button = Button.new()
	_restart_button.text = "RESTART RACE"
	_restart_button.custom_minimum_size = Vector2(280, 68)
	_restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_restart_button.focus_mode = Control.FOCUS_NONE
	_restart_button.add_theme_font_size_override("font_size", 26)
	_restart_button.pressed.connect(_on_restart_pressed)
	finish_box.add_child(_restart_button)


func _update_leaderboard(delta: float) -> void:
	_leaderboard_timer -= delta
	if _leaderboard_timer > 0.0:
		return
	_leaderboard_timer = 0.15
	if _lap_manager == null or not _lap_manager.has_method("get_standings"):
		return

	var standings: Array = _lap_manager.get_standings()
	for i in _leaderboard_rows.size():
		var labels: Dictionary = _leaderboard_rows[i]
		var row: HBoxContainer = labels["row"]
		if i >= standings.size():
			row.visible = false
			continue

		row.visible = true
		var entry: Dictionary = standings[i]
		var position_label: Label = labels["position"]
		var name_label: Label = labels["name"]
		var lap_label: Label = labels["lap"]
		position_label.text = str(entry["position"])
		name_label.text = String(entry["name"])
		lap_label.text = "FIN" if bool(entry["finished"]) else "L%d" % int(entry["lap"])
		var color := ACCENT if bool(entry["is_player"]) else Color(0.93, 0.96, 1.0)
		position_label.add_theme_color_override("font_color", color)
		name_label.add_theme_color_override("font_color", color)
		lap_label.add_theme_color_override("font_color", color)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", maxi(2, int(font_size * 0.12)))
	return label


func _make_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300, 64)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _panel_style(color: Color, radius: int = 14, border: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	if border > 0:
		style.border_width_left = border
		style.border_width_top = border
		style.border_width_right = border
		style.border_width_bottom = border
		style.border_color = Color(1.0, 1.0, 1.0, 0.12)
	return style


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "--:--.---"
	var total_ms := int(round(seconds * 1000.0))
	var minutes := int(total_ms / 60000.0)
	var remaining := total_ms % 60000
	var secs := int(remaining / 1000.0)
	var millis := remaining % 1000
	return "%02d:%02d.%03d" % [minutes, secs, millis]


func _on_countdown_changed(text: String) -> void:
	_countdown_label.visible = text != ""
	_countdown_label.text = text
	var color := Color(1.0, 1.0, 1.0)
	if text == "GO!":
		color = GOOD
	elif text != "":
		color = ACCENT
	_countdown_label.add_theme_color_override("font_color", color)


func _on_race_started() -> void:
	_countdown_label.visible = true


func _on_lap_completed(_lap_number: int, lap_time: float, best: float) -> void:
	_best_label.text = "BEST  " + _format_time(best)
	_time_label.text = "TIME  " + _format_time(lap_time)


func _on_race_finished(total_time: float, best: float) -> void:
	_countdown_label.visible = false
	_pause_button.visible = false
	var position := 1
	var field_size := 1
	if _lap_manager != null and _lap_manager.has_method("get_player_finish_position"):
		position = int(_lap_manager.get_player_finish_position())
	if _lap_manager != null and _lap_manager.has_method("get_standings"):
		field_size = maxi(_lap_manager.get_standings().size(), 1)
	var laps_text := "LAPS      %d" % int(_lap_manager.total_laps)
	_result_label.text = "POSITION  P%d / %d\nTOTAL     %s\nBEST LAP  %s\n%s" % [
		position,
		field_size,
		_format_time(total_time),
		_format_time(best),
		laps_text,
	]
	_leaderboard_timer = 0.0
	_update_leaderboard(0.0)
	_finish_root.visible = true


func _toggle_pause() -> void:
	if _lap_manager != null and _lap_manager.is_finished:
		return
	_set_paused(not _paused)


func _set_paused(paused: bool) -> void:
	_paused = paused
	get_tree().paused = paused
	_pause_root.visible = paused
	_pause_button.text = "RESUME" if paused else "PAUSE"
	if _touch_hud == null:
		_touch_hud = get_tree().get_first_node_in_group("touch_hud")
	if _touch_hud != null and _touch_hud.has_method("set_paused"):
		_touch_hud.set_paused(paused)


func _on_resume_pressed() -> void:
	_set_paused(false)


func _on_pause_reset_pressed() -> void:
	_on_reset_pressed()
	_set_paused(false)


func _on_reset_pressed() -> void:
	if _car == null:
		_car = get_tree().get_first_node_in_group("player_car")
	if _car != null and _car.has_method("reset_vehicle"):
		_car.reset_vehicle()


func _on_restart_pressed() -> void:
	_set_paused(false)
	get_tree().reload_current_scene()
