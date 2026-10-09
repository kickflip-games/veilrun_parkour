extends Node3D

const TOGGLE_ACTION := "debug_fly_camera_toggle"

const MOVE_FORWARD := "debug_fly_move_forward"
const MOVE_BACKWARD := "debug_fly_move_backward"
const MOVE_LEFT := "debug_fly_move_left"
const MOVE_RIGHT := "debug_fly_move_right"
const MOVE_UP := "debug_fly_move_up"
const MOVE_DOWN := "debug_fly_move_down"
const MOVE_FAST := "debug_fly_move_fast"
const MOVE_SLOW := "debug_fly_move_slow"

@export var move_speed: float = 9.0
@export var fast_multiplier: float = 3.0
@export var slow_multiplier: float = 0.35
@export var acceleration: float = 14.0
@export var mouse_sensitivity: float = 0.0022
@export var invert_y: bool = false

var _active := false
var _velocity := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _previous_camera: Camera3D
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE

@onready var _pivot: Node3D = Node3D.new()
@onready var _camera: Camera3D = Camera3D.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_actions()

	add_child(_pivot)
	_pivot.add_child(_camera)
	_camera.current = false

	set_process_input(true)
	set_physics_process(true)
	set_process_unhandled_input(true)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		toggle()
		get_viewport().set_input_as_handled()
		return

	if not _active:
		return

	if event.is_action_pressed("ui_cancel"):
		_disable()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * mouse_sensitivity
		var pitch_delta: float = event.relative.y * mouse_sensitivity
		_pitch += pitch_delta if invert_y else -pitch_delta
		_pitch = clampf(_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
		_apply_rotation()


func _physics_process(delta: float) -> void:
	if not _active:
		_velocity = Vector3.ZERO
		return

	var direction := Vector3.ZERO
	var camera_basis := _camera.global_transform.basis

	if Input.is_action_pressed(MOVE_FORWARD):
		direction -= camera_basis.z
	if Input.is_action_pressed(MOVE_BACKWARD):
		direction += camera_basis.z
	if Input.is_action_pressed(MOVE_LEFT):
		direction -= camera_basis.x
	if Input.is_action_pressed(MOVE_RIGHT):
		direction += camera_basis.x
	if Input.is_action_pressed(MOVE_UP):
		direction += camera_basis.y
	if Input.is_action_pressed(MOVE_DOWN):
		direction -= camera_basis.y

	direction = direction.normalized()

	var speed := move_speed
	if Input.is_action_pressed(MOVE_FAST):
		speed *= fast_multiplier
	elif Input.is_action_pressed(MOVE_SLOW):
		speed *= slow_multiplier

	var target_velocity := direction * speed
	_velocity = _velocity.lerp(target_velocity, acceleration * delta)

	global_position += _velocity * delta


func toggle() -> void:
	if _active:
		_disable()
	else:
		_enable()


func is_active() -> bool:
	return _active


func _enable() -> void:
	if _active:
		return

	var current_camera := get_viewport().get_camera_3d()
	if current_camera != null:
		_previous_camera = current_camera
		global_transform = current_camera.global_transform
	else:
		_previous_camera = null

	_previous_mouse_mode = Input.get_mouse_mode()
	_extract_rotation_from_transform()
	_apply_rotation()
	_camera.current = true
	_active = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _disable() -> void:
	if not _active:
		return

	_active = false
	_velocity = Vector3.ZERO

	if is_instance_valid(_previous_camera):
		_previous_camera.current = true
	_previous_camera = null
	_camera.current = false
	Input.set_mouse_mode(_previous_mouse_mode)


func _apply_rotation() -> void:
	rotation = Vector3.ZERO
	_pivot.rotation = Vector3(0.0, _yaw, 0.0)
	_camera.rotation = Vector3(_pitch, 0.0, 0.0)


func _extract_rotation_from_transform() -> void:
	var transform_basis := global_transform.basis.orthonormalized()
	_yaw = atan2(-transform_basis.z.x, -transform_basis.z.z)
	var flat_forward := Vector2(-transform_basis.z.x, -transform_basis.z.z).length()
	_pitch = atan2(transform_basis.z.y, flat_forward)


func _ensure_actions() -> void:
	_ensure_key_action(TOGGLE_ACTION, KEY_F4)
	_ensure_key_action(MOVE_FORWARD, KEY_W)
	_ensure_key_action(MOVE_BACKWARD, KEY_S)
	_ensure_key_action(MOVE_LEFT, KEY_A)
	_ensure_key_action(MOVE_RIGHT, KEY_D)
	_ensure_key_action(MOVE_UP, KEY_E)
	_ensure_key_action(MOVE_DOWN, KEY_Q)
	_ensure_key_action(MOVE_FAST, KEY_SHIFT)
	_ensure_key_action(MOVE_SLOW, KEY_CTRL)


func _ensure_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	var already_has_key := false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			already_has_key = true
			break

	if not already_has_key:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = keycode
		InputMap.action_add_event(action, key_event)
