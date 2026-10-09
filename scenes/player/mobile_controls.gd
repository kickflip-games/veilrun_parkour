extends Control

signal dash_requested
signal pull_pressed
signal pull_released
signal jump_requested
signal pause_requested

const DEADZONE := 0.15
const TURN_SPEED := 2.8 # Radians per second at full stick deflection.

var enabled := false
var movement := Vector2.ZERO
var turn := 0.0
var pitch := 0.0
var look_caption := "TURN"
var pull_active := false
var _move_finger := -1
var _look_finger := -1
var _pull_finger := -1
var _move_offset := Vector2.ZERO
var _look_offset := Vector2.ZERO
var _radius := 72.0
var _move_center := Vector2.ZERO
var _look_center := Vector2.ZERO
var _dash_center := Vector2.ZERO
var _jump_center := Vector2.ZERO
var _pause_center := Vector2.ZERO
var _mouse_emulation := true
var extra_touch_buttons: Array[Button] = []

static func is_mobile_web() -> bool:
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if not OS.has_feature("web"):
		return false
	# iPadOS can report a desktop Mac user agent.
	return bool(JavaScriptBridge.eval("/Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)"))

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 30
	_mouse_emulation = Input.emulate_mouse_from_touch
	enabled = is_mobile_web() or OS.get_cmdline_user_args().has("--mobile-controls")
	resized.connect(_layout_controls)
	get_viewport().get_window().focus_exited.connect(reset_touches)
	_layout_controls()
	hide()

func _exit_tree() -> void:
	if enabled:
		Input.emulate_mouse_from_touch = _mouse_emulation

func set_active(active: bool) -> void:
	active = active and enabled
	if visible == active:
		return
	visible = active
	reset_touches()
	# Keep menu taps working without treating joystick touches as grapples.
	Input.emulate_mouse_from_touch = false if active else _mouse_emulation

func reset_touches() -> void:
	if _pull_finger != -1:
		_pull_finger = -1
		pull_released.emit()
	_move_finger = -1
	_look_finger = -1
	_move_offset = Vector2.ZERO
	_look_offset = Vector2.ZERO
	movement = Vector2.ZERO
	turn = 0.0
	pitch = 0.0
	queue_redraw()

func set_pull_active(active: bool) -> void:
	if pull_active != active:
		pull_active = active
		queue_redraw()

func _layout_controls() -> void:
	reset_touches()
	_radius = clampf(minf(size.x, size.y) * 0.12, 42.0, 78.0)
	var margin := _radius * 0.5
	_move_center = Vector2(_radius + margin, size.y - _radius - margin)
	_look_center = Vector2(size.x - _radius - margin, _move_center.y)
	_dash_center = _look_center - Vector2(0.0, _radius * 2.3)
	_jump_center = _dash_center - Vector2(_radius * 1.6, 0.0)
	_pause_center = Vector2(size.x - _radius, _radius * 1.8)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		# Trial retry buttons share this touch router because joystick input
		# consumes touches before Godot's usual GUI/mouse emulation path.
		if event.pressed and not event.canceled:
			for button in extra_touch_buttons:
				if is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(event.position):
					button.pressed.emit()
					get_viewport().set_input_as_handled()
					return
		if not event.pressed or event.canceled:
			_release_finger(event.index)
		elif event.position.distance_to(_pause_center) <= _radius * 0.5:
			pause_requested.emit()
		elif event.position.distance_to(_dash_center) <= _radius * 0.65:
			if _pull_finger == -1:
				_pull_finger = event.index
				pull_pressed.emit()
		elif event.position.distance_to(_jump_center) <= _radius * 0.65:
			jump_requested.emit()
		elif _move_finger == -1 and event.position.distance_to(_move_center) <= _radius * 1.35:
			_move_finger = event.index
			_update_stick(event.index, event.position)
		elif _look_finger == -1 and event.position.distance_to(_look_center) <= _radius * 1.35:
			_look_finger = event.index
			_update_stick(event.index, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_update_stick(event.index, event.position)
		get_viewport().set_input_as_handled()

func _release_finger(index: int) -> void:
	if index == _pull_finger:
		_pull_finger = -1
		pull_released.emit()
	if index == _move_finger:
		_move_finger = -1
		_move_offset = Vector2.ZERO
		movement = Vector2.ZERO
	if index == _look_finger:
		_look_finger = -1
		_look_offset = Vector2.ZERO
		turn = 0.0
		pitch = 0.0
	queue_redraw()

func _update_stick(index: int, point: Vector2) -> void:
	if index == _move_finger:
		_move_offset = ((point - _move_center) / _radius).limit_length()
		movement = _apply_deadzone(_move_offset)
	if index == _look_finger:
		_look_offset = ((point - _look_center) / _radius).limit_length()
		turn = _apply_deadzone(Vector2(_look_offset.x, 0.0)).x
		pitch = _apply_deadzone(Vector2(0.0, _look_offset.y)).y
	queue_redraw()

func _apply_deadzone(value: Vector2) -> Vector2:
	var magnitude := value.length()
	if magnitude <= DEADZONE:
		return Vector2.ZERO
	return value.normalized() * ((magnitude - DEADZONE) / (1.0 - DEADZONE))

func _draw() -> void:
	_draw_stick(_move_center, _move_offset, "MOVE")
	_draw_stick(_look_center, _look_offset, look_caption)
	_draw_button(_dash_center, _radius * 0.65, "PULL", Color(0.75, 0.14, 0.1, 0.75) if pull_active else Color(0.7, 0.04, 0.06, 0.55))
	_draw_button(_jump_center, _radius * 0.65, "JUMP", Color(0.05, 0.05, 0.05, 0.5))
	_draw_button(_pause_center, _radius * 0.5, "II", Color(0.05, 0.05, 0.05, 0.5))

func _draw_stick(center: Vector2, offset: Vector2, caption: String) -> void:
	draw_circle(center, _radius, Color(0.0, 0.0, 0.0, 0.3))
	draw_arc(center, _radius, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.45), 2.0, true)
	draw_circle(center + offset * _radius * 0.65, _radius * 0.38, Color(1.0, 1.0, 1.0, 0.3))
	_draw_caption(center + Vector2(0.0, _radius * 0.65), caption)

func _draw_button(center: Vector2, radius: float, caption: String, fill: Color) -> void:
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.7), 2.0, true)
	_draw_caption(center + Vector2(0.0, 6.0), caption, radius * 1.65)

func _draw_caption(point: Vector2, caption: String, maximum_width: float = 0.0) -> void:
	var font := ThemeDB.fallback_font
	var font_size := int(clampf(_radius * 0.24, 12.0, 19.0))
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	while maximum_width > 0.0 and width > maximum_width and font_size > 9:
		font_size -= 1
		width = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, point - Vector2(width * 0.5, 0.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
