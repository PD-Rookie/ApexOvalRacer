extends Control
## Mobile touch overlay.
##
## The controls are drawn with Control primitives, while invisible
## TouchScreenButtons provide the actual multi-touch input. The buttons feed the
## same InputMap actions as the keyboard, and the engine releases each action as
## soon as its finger is lifted:
##   steer_left, steer_right, accelerate, brake, handbrake, nitrous.
##
## The whole steering bar is touchable and is split into a left and right half.
## Brake and reverse share one button: holding BRK/R at a stop reverses, and
## releasing it returns to drive.

const ACTIONS: Array[StringName] = [
	&"steer_left", &"steer_right", &"accelerate", &"brake", &"handbrake",
	&"nitrous",
]

var _overlay_enabled := false
var _controls_enabled := false
var _car: Node = null
var _reverse_active := false

var _toggle_button: Button
var _touch_buttons: Array[TouchScreenButton] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("touch_hud")

	_build_toggle()
	_build_touch_buttons()
	_overlay_enabled = _should_auto_enable()
	_toggle_button.visible = not _should_auto_enable()
	_update_toggle_text()
	resized.connect(_layout_touch_buttons)
	_layout_touch_buttons()
	queue_redraw()


func _process(_delta: float) -> void:
	if _car == null:
		_car = get_tree().get_first_node_in_group("player_car")
	var now_reverse := _car != null and bool(_car.reverse_gear)
	if now_reverse != _reverse_active:
		_reverse_active = now_reverse
		queue_redraw()


func _build_toggle() -> void:
	_toggle_button = Button.new()
	_toggle_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toggle_button.offset_left = -78
	_toggle_button.offset_top = 14
	_toggle_button.offset_right = 78
	_toggle_button.offset_bottom = 50
	_toggle_button.focus_mode = Control.FOCUS_NONE
	_toggle_button.add_theme_font_size_override("font_size", 17)
	_toggle_button.pressed.connect(_on_toggle_pressed)
	add_child(_toggle_button)


func _build_touch_buttons() -> void:
	for _i in ACTIONS.size():
		var button := TouchScreenButton.new()
		button.passby_press = false
		button.shape_visible = false
		add_child(button)
		_touch_buttons.append(button)


func _should_auto_enable() -> bool:
	return (
		OS.has_feature("mobile")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
		or DisplayServer.is_touchscreen_available()
	)


func _update_toggle_text() -> void:
	if _toggle_button != null:
		_toggle_button.text = "TOUCH: ON" if _overlay_enabled else "TOUCH: OFF"


func _on_toggle_pressed() -> void:
	_overlay_enabled = not _overlay_enabled
	_release_all()
	_update_toggle_text()
	_update_touch_buttons()
	queue_redraw()


## Called by the race manager during the countdown and after the finish.
func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	if not enabled:
		_release_all()
	_update_touch_buttons()
	queue_redraw()


## Called by the HUD so touch controls cannot remain held while paused.
func set_paused(paused: bool) -> void:
	visible = not paused
	if paused:
		_release_all()
	_update_touch_buttons()
	queue_redraw()


func cancel_inputs() -> void:
	_release_all()


func _button_layout() -> Array[Dictionary]:
	var w := size.x
	var h := size.y
	var base := clampf(minf(w, h) * 0.08, 42.0, 88.0)
	var left_center := Vector2(w * 0.14, h * 0.82)
	var right_center := Vector2(w * 0.30, h * 0.82)
	var bar_center := (left_center + right_center) * 0.5
	var half_width := (right_center.x - left_center.x) * 0.5 + base
	return [
		{
			"action": &"steer_left",
			"pos": left_center,
			"hit_pos": Vector2(bar_center.x - half_width * 0.5, bar_center.y),
			"hit_size": Vector2(half_width, base * 2.0),
			"radius": base,
			"label": "",
		},
		{
			"action": &"steer_right",
			"pos": right_center,
			"hit_pos": Vector2(bar_center.x + half_width * 0.5, bar_center.y),
			"hit_size": Vector2(half_width, base * 2.0),
			"radius": base,
			"label": "",
		},
		{"action": &"accelerate", "pos": Vector2(w * 0.91, h * 0.78), "radius": base * 1.1, "label": "GAS"},
		{"action": &"brake", "pos": Vector2(w * 0.79, h * 0.87), "radius": base * 0.92, "label": "BRK/R"},
		{"action": &"handbrake", "pos": Vector2(w * 0.63, h * 0.88), "radius": base * 0.74, "label": "DRIFT"},
		{"action": &"nitrous", "pos": Vector2(w * 0.78, h * 0.62), "radius": base * 0.66, "label": "NOS"},
	]


func _layout_touch_buttons() -> void:
	var layout := _button_layout()
	for i in mini(layout.size(), _touch_buttons.size()):
		var data := layout[i]
		var button := _touch_buttons[i]
		button.action = data["action"]
		if i < 2:
			var rect := RectangleShape2D.new()
			rect.size = data["hit_size"]
			button.shape = rect
			button.position = data["hit_pos"]
		else:
			var circle := CircleShape2D.new()
			circle.radius = float(data["radius"]) * 1.22
			button.shape = circle
			button.position = data["pos"]
	_update_touch_buttons()
	queue_redraw()


func _update_touch_buttons() -> void:
	var enabled := _overlay_enabled and _controls_enabled
	for button in _touch_buttons:
		button.visible = enabled


func _draw() -> void:
	if not _overlay_enabled:
		return

	var layout := _button_layout()
	var font := ThemeDB.fallback_font
	_draw_steering(layout[0], layout[1], font)
	for i in range(2, layout.size()):
		_draw_circle_button(layout[i], font)


func _draw_steering(left: Dictionary, right: Dictionary, font: Font) -> void:
	var left_center: Vector2 = left["pos"]
	var right_center: Vector2 = right["pos"]
	var radius: float = left["radius"]
	var left_held := Input.is_action_pressed(&"steer_left")
	var right_held := Input.is_action_pressed(&"steer_right")

	var fill := Color(0.04, 0.07, 0.11, 0.4)
	if not _controls_enabled:
		fill = Color(0.04, 0.07, 0.11, 0.22)

	var bar := Rect2(
		Vector2(left_center.x - radius, left_center.y - radius),
		Vector2(right_center.x - left_center.x + radius * 2.0, radius * 2.0)
	)
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(radius))
	draw_style_box(style, bar)

	var highlight := Color(1.0, 1.0, 1.0, 0.2)
	if left_held:
		draw_circle(left_center, radius * 0.94, highlight)
	if right_held:
		draw_circle(right_center, radius * 0.94, highlight)

	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	outline.set_border_width_all(3)
	outline.border_color = Color(1.0, 1.0, 1.0, 0.8)
	outline.set_corner_radius_all(int(radius))
	draw_style_box(outline, bar)

	var middle := (left_center + right_center) * 0.5
	draw_line(
		Vector2(middle.x, middle.y - radius),
		Vector2(middle.x, middle.y + radius),
		Color(1.0, 1.0, 1.0, 0.16),
		2.0,
		true
	)
	_draw_text(font, "<", left_center, int(radius * 0.8))
	_draw_text(font, ">", right_center, int(radius * 0.8))


func _draw_circle_button(button: Dictionary, font: Font) -> void:
	var center: Vector2 = button["pos"]
	var radius: float = button["radius"]
	var action: StringName = button["action"]
	var label: String = button["label"]
	var held := Input.is_action_pressed(action)

	var fill := Color(1.0, 1.0, 1.0, 0.28) if held else Color(0.04, 0.07, 0.11, 0.4)
	if not _controls_enabled:
		fill = Color(0.04, 0.07, 0.11, 0.22)
	if action == &"brake" and _reverse_active:
		label = "REV"
		fill = Color(1.0, 0.56, 0.18, 0.5) if held else Color(1.0, 0.56, 0.18, 0.28)

	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.82), 3.0, true)
	_draw_text(font, label, center, int(radius * (0.42 if label.length() > 3 else 0.55)))


func _draw_text(font: Font, text: String, center: Vector2, font_size: int) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var position := center + Vector2(-text_size.x * 0.5, text_size.y * 0.34)
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 0.95))


func _release_all() -> void:
	for action in ACTIONS:
		Input.action_release(action)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _exit_tree() -> void:
	_release_all()
