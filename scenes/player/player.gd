extends CharacterBody3D

const ParkourJuice = preload("res://scenes/parkour/parkour_juice.gd")
const AnchorPull = preload("res://scenes/parkour/anchor_pull.gd")
const AirControl = preload("res://scenes/parkour/air_control.gd")
var parkour_juice

# Retained for authored courses and validation tools; this controller is parkour only.
@export var parkour_mode := true
@export var use_momentum_pull := false
@export var vertical_look_enabled := false
@export_range(20.0, 120.0, 1.0) var pull_acceleration := 72.0
@export_range(0.9, 1.0, 0.01) var pull_tangent_retention := 1.0
@export_range(0.5, 1.5, 0.05) var pull_upward_scale := 1.1
@export_range(0.5, 3.0, 0.1) var pull_arrival_distance := 1.8
@export_range(0.5, 5.0, 0.1) var pull_max_duration := 2.8
@export_range(0.0, 48.0, 1.0) var pull_air_acceleration := 24.0
@export_range(0.0, 360.0, 10.0) var pull_air_turn_speed := 120.0
@export var surf_mode := false
@export_range(0.0, 0.5, 0.01) var surf_drag := 0.03
@export var parkour_air_acceleration := 32.0
@export_range(0.0, 480.0, 10.0) var parkour_air_turn_speed := 240.0
@export var parkour_air_braking := 56.0
@export var parkour_air_drag := 0.12
@export var parkour_ground_momentum_drag := 0.65
@export var parkour_ground_coast_drag := 2.0
@export var parkour_speed_limit := 32.0
@export var hook_blocked_timeout := 0.18
@export var anchor_reuse_delay := 0.45
@export var hook_exit_speed: float = 26.0
@export_range(0.0, 1.0, 0.05) var hook_exit_vertical_fraction: float = 0.4
@export_range(0.5, 1.0, 0.05) var hook_capsule_scale: float = 0.75
@export_group("Jump Assistance")
@export_range(0.0, 0.25, 0.01) var coyote_time := 0.12
@export_range(0.0, 0.25, 0.01) var jump_buffer_time := 0.14
@export_group("Presentation")
@export_range(0.0, 24.0, 0.5) var camera_fov_boost := 14.0
@export_range(0.0, 12.0, 0.5) var camera_roll_limit_degrees := 7.0

const MAX_SPEED = 8.0
const ACCEL = 14.0
const FRICTION = 14.0
const JUMP_SPEED = 5.5
const MOUSE_SENS = 0.002
const MAX_LOOK_PITCH := deg_to_rad(80.0)
const FLOOR_SNAP_LENGTH: float = 0.35
const HOOK_SPEED: float = 38.0
const HOOK_ARRIVE_DIST: float = 1.2
const HOOK_SLIDE_DURATION: float = 0.5

@onready var camera: Camera3D = $Camera3D
@onready var grapple = $Grapple
@onready var hud = $Hud
@onready var _body_collision: CollisionShape3D = $CollisionShape3D

var _full_capsule: CapsuleShape3D
var _flight_capsule: CapsuleShape3D
var _full_capsule_position: Vector3
var _capsule_reduced: bool = false
var _hook_blocked_time := 0.0
var _hook_previous_position := Vector3.ZERO
var _pull_has_approached := false
var _recent_anchor: Node3D
var _anchor_cooldown := 0.0
var input_dir = Vector3.ZERO
var gameplay_active = false
var is_hooking: bool = false
var _hook_target: Node3D = null
var _hook_launch_direction: Vector3 = Vector3.ZERO
var _hook_slide_timer: float = 0.0
# The neutral camera transform keeps presentation effects out of target acquisition.
var _camera_base_pos: Vector3
var _base_fov: float = 75.0
var camera_tilt: float = 0.0
var _gravity: float = 9.8
var _pull_solver = AnchorPull.new()
var _air_control = AirControl.new()
var _pull_input_sources: Dictionary = {}
var _jump_buffer_left := 0.0
var _coyote_time_left := 0.0
var _jump_ground_consumed := false
var _jump_left_floor := false
var _jump_event_handled := false
var _contact_traversal_areas: Dictionary = {}

func _is_debug_fly_active() -> bool:
	var debug_fly_camera := get_node_or_null("/root/DebugFlyCamera")
	return debug_fly_camera != null and debug_fly_camera.has_method("is_active") and debug_fly_camera.is_active()

func _ready() -> void:
	_full_capsule = _body_collision.shape.duplicate() as CapsuleShape3D
	_flight_capsule = _full_capsule.duplicate() as CapsuleShape3D
	_flight_capsule.radius *= hook_capsule_scale
	_flight_capsule.height *= hook_capsule_scale
	_full_capsule_position = _body_collision.position
	_body_collision.shape = _full_capsule
	add_to_group("player")
	# Anchors are query targets, never obstacles to the player's capsule.
	set_collision_mask_value(2, false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	floor_snap_length = FLOOR_SNAP_LENGTH
	if surf_mode:
		floor_stop_on_slope = false
		floor_constant_speed = false
		floor_block_on_wall = false
	_camera_base_pos = camera.position
	_base_fov = camera.fov
	hud.start_game_requested.connect(_on_start_game_requested)
	parkour_juice = ParkourJuice.new()
	parkour_juice.name = "ParkourJuice"
	add_child(parkour_juice)
	parkour_juice.configure(self)
	get_viewport().get_window().focus_exited.connect(reset_movement_input)

func _process(delta: float) -> void:
	if gameplay_active and not get_tree().paused and not _is_debug_fly_active():
		rotate_y(-hud.mobile_controls.turn * hud.mobile_controls.TURN_SPEED * delta)
		if vertical_look_enabled:
			camera.rotation.x = clampf(camera.rotation.x - hud.mobile_controls.pitch * hud.mobile_controls.TURN_SPEED * delta, -MAX_LOOK_PITCH, MAX_LOOK_PITCH)
	if is_instance_valid(parkour_juice):
		parkour_juice.update_effects(delta)

func _on_start_game_requested() -> void:
	if gameplay_active:
		return
	gameplay_active = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if hud.mobile_controls.enabled else Input.MOUSE_MODE_CAPTURED)
	GameManager.register_player(self)

func _input(event: InputEvent) -> void:
	if not gameplay_active or get_tree().paused or _is_debug_fly_active():
		return
	if hud.mobile_controls.enabled and (event is InputEventMouseMotion or event is InputEventMouseButton):
		return
	# Releases cannot be swallowed by a HUD control crossed while holding.
	if event.is_action_released("grapple"):
		release_pull(_pull_event_source(event))
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * MOUSE_SENS, -MAX_LOOK_PITCH, MAX_LOOK_PITCH) if vertical_look_enabled else 0.0
	if event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if not gameplay_active or get_tree().paused or _is_debug_fly_active():
		return
	if hud.mobile_controls.enabled and event is InputEventMouseButton:
		return
	# Only fresh unhandled presses acquire; release is dispatched in the same
	# event, so even a short tap between physics frames cannot leave a latch.
	if event.is_action_pressed("grapple"):
		press_pull(_pull_event_source(event))
		get_viewport().set_input_as_handled()
	elif event.is_action_released("grapple"):
		release_pull(_pull_event_source(event))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jump_or_dash") and not event.is_echo():
		_jump_event_handled = true
		request_jump()
		get_viewport().set_input_as_handled()

func _pull_event_source(event: InputEvent) -> StringName:
	return StringName("mouse_%d" % event.button_index) if event is InputEventMouseButton else &"keyboard"

func press_pull(source: StringName = &"touch") -> void:
	if not gameplay_active or get_tree().paused or _is_debug_fly_active() or _pull_input_sources.has(source):
		return
	var already_held := not _pull_input_sources.is_empty()
	_pull_input_sources[source] = true
	# An automatic release consumes this hold. There is no polling/reacquisition
	# until all held buttons have been lifted and the player presses again.
	if not already_held and not is_hooking:
		grapple.request_hook()

func release_pull(source: StringName = &"touch") -> void:
	if not _pull_input_sources.has(source):
		return
	_pull_input_sources.erase(source)
	if _pull_input_sources.is_empty() and is_hooking:
		_release_hook()

func reset_movement_input() -> void:
	for area in _contact_traversal_areas.values():
		if is_instance_valid(area):
			area.reset_contact_state(self)
	_contact_traversal_areas.clear()
	_pull_input_sources.clear()
	_jump_buffer_left = 0.0
	_coyote_time_left = 0.0
	_jump_ground_consumed = false
	_jump_left_floor = false
	_jump_event_handled = false
	Input.action_release("grapple")
	Input.action_release("jump_or_dash")
	if is_hooking:
		_release_hook()

func request_hook() -> void:
	# Programmatic compatibility for authored route probes. Desktop and touch
	# use press_pull/release_pull, so their controls never toggle.
	if not gameplay_active or get_tree().paused or _is_debug_fly_active():
		return
	if is_hooking:
		_release_hook()
	else:
		grapple.request_hook()

func _release_hook() -> void:
	_end_hook(false)
	_hook_slide_timer = HOOK_SLIDE_DURATION
	if is_instance_valid(parkour_juice):
		parkour_juice.grapple_release()

func request_dash() -> void:
	# Legacy programmatic alias; the touch router dispatches a held pull now.
	request_hook()

func get_aim_basis() -> Basis:
	# Presentation roll, landing dip and speed FOV never change target selection.
	var basis := global_basis.orthonormalized()
	return basis * Basis(Vector3.RIGHT, camera.rotation.x) if vertical_look_enabled else basis

func reset_pull_state() -> void:
	_pull_solver.reset()
	_pull_has_approached = false

func get_pull_debug() -> Dictionary:
	return {"active": is_hooking and use_momentum_pull, "elapsed": _pull_solver.elapsed,
		"force": _pull_solver.last_force, "velocity": velocity, "speed": velocity.length()}

func _physics_process(delta: float) -> void:
	if is_instance_valid(parkour_juice):
		parkour_juice.begin_physics_step()
	_anchor_cooldown = maxf(0.0, _anchor_cooldown - delta)
	_update_jump_assistance(delta)
	if _capsule_reduced and not is_hooking:
		_try_restore_capsule()
	if is_hooking:
		_jump_event_handled = false
		_handle_hook_movement(delta)
		_apply_contact_traversal(delta)
		move_and_slide()
		if is_instance_valid(parkour_juice):
			parkour_juice.finish_physics_step()
		return
	if gameplay_active:
		handle_input()
		_try_buffered_jump()
		handle_movement(delta)
		_apply_gravity(delta)
	else:
		var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
		horizontal_velocity *= exp(-FRICTION * delta)
		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.z
		_apply_gravity(delta)
	_apply_contact_traversal(delta)
	velocity = velocity.limit_length(parkour_speed_limit)
	move_and_slide()
	# Consume a landing buffer on the collision tick itself. Waiting for the
	# next floor poll would lose valid late buffers at lower physics rates.
	if gameplay_active:
		_refresh_jump_ground_contact()
		_try_buffered_jump()
	if _hook_slide_timer > 0.0:
		for i in get_slide_collision_count():
			var normal_y: float = get_slide_collision(i).get_normal().y
			# Collision has already removed motion into the obstacle. Keep the
			# remaining tangent so glancing contacts do not erase forward travel.
			if normal_y < 0.7 and not (surf_mode and normal_y > 0.05):
				_hook_slide_timer = 0.0
				break
	if is_instance_valid(parkour_juice):
		parkour_juice.finish_physics_step()

func start_grapple(target: Node3D) -> void:
	if not gameplay_active or get_tree().paused or _is_debug_fly_active():
		return
	if is_hooking or not is_instance_valid(target) or not target.is_in_group("grapple_anchors") or not target.has_method("is_grapple_available"):
		return
	if not target.is_grapple_available():
		return
	if target == _recent_anchor and _anchor_cooldown > 0.0:
		return
	_recent_anchor = target
	_anchor_cooldown = anchor_reuse_delay
	_hook_blocked_time = 0.0
	_hook_previous_position = global_position
	reset_pull_state()
	_pull_solver.acceleration = pull_acceleration
	_pull_solver.speed_limit = parkour_speed_limit
	_pull_solver.tangent_retention = pull_tangent_retention
	_pull_solver.upward_scale = pull_upward_scale
	_pull_solver.air_acceleration = pull_air_acceleration
	_pull_solver.air_turn_speed = pull_air_turn_speed
	_pull_solver.air_braking = parkour_air_braking
	_body_collision.shape = _flight_capsule
	# Keep the feet fixed while shrinking the capsule for flight.
	_body_collision.position = _full_capsule_position - Vector3.UP * ((_full_capsule.height - _flight_capsule.height) * 0.5)
	_capsule_reduced = true
	is_hooking = true
	_hook_target = target
	_hook_launch_direction = global_position.direction_to(target.global_position)
	if is_instance_valid(parkour_juice):
		parkour_juice.grapple_start()

func _handle_hook_movement(delta: float) -> void:
	if not is_instance_valid(_hook_target) or not _hook_target.is_grapple_available():
		_end_hook(false)
		return
	var to_target: Vector3 = _hook_target.global_position - global_position
	var motion := global_position - _hook_previous_position
	if use_momentum_pull and _finish_pull_pass(to_target, motion):
		return
	var traveled := motion.length()
	var stalled: bool
	if use_momentum_pull:
		# A wall can project a fast pull into useful tangential travel. Only
		# actual lost motion/progress counts as blocked, independent of tick rate.
		var progress := _hook_previous_position.distance_to(_hook_target.global_position) - to_target.length()
		stalled = traveled < 0.5 * delta or (is_on_wall() and progress < 0.5 * delta)
	else:
		stalled = is_on_wall() or traveled < 0.02
	if stalled:
		_hook_blocked_time += delta
	else:
		_hook_blocked_time = 0.0
	_hook_previous_position = global_position
	if _hook_blocked_time >= hook_blocked_timeout:
		_end_hook(not use_momentum_pull)
		if use_momentum_pull:
			_hook_slide_timer = HOOK_SLIDE_DURATION
		return
	if use_momentum_pull:
		if _pull_solver.elapsed >= pull_max_duration:
			_end_hook(false)
			_hook_slide_timer = HOOK_SLIDE_DURATION
			return
		input_dir = _read_move_input()
		velocity = _pull_solver.step(velocity, to_target, input_dir, _gravity, delta)
		return
	# Stop before overshooting a small target at low frame rates, without teleporting.
	var arrival_distance := maxf(HOOK_ARRIVE_DIST, HOOK_SPEED * delta)
	if to_target.length() < arrival_distance:
		_on_hook_impact()
		return
	velocity = to_target.normalized() * HOOK_SPEED

func _finish_pull_pass(to_target: Vector3, motion: Vector3) -> bool:
	var arrival_squared := pull_arrival_distance * pull_arrival_distance
	if to_target.length_squared() < arrival_squared:
		_on_hook_impact()
		return true
	var travel_squared := motion.length_squared()
	if travel_squared < 0.000001:
		return false
	var previous_offset := to_target + motion
	var approach := previous_offset.dot(motion)
	# Test actual travel, not a predicted velocity that could cross a wall.
	# Colliding slide paths can bend; their endpoint chord is not an arrival path.
	if get_slide_collision_count() == 0:
		var closest := previous_offset - motion * clampf(approach / travel_squared, 0.0, 1.0)
		if closest.length_squared() < arrival_squared:
			_on_hook_impact()
			return true
	if approach > 0.0:
		_pull_has_approached = true
	# Initial momentum away from a new ring must first be allowed to turn in.
	# After approaching, a missed ring releases instead of attracting us backward.
	if _pull_has_approached and to_target.dot(motion) < -0.0001:
		_release_hook()
		return true
	return false

func _on_hook_impact() -> void:
	var target := _hook_target
	var impact_pos := target.global_position
	_end_hook(false)
	SoundManager.play_sfx(SoundManager.SFX_GRAPPLE_ARRIVAL)
	if not use_momentum_pull:
		var travel_direction := velocity.normalized() if not velocity.is_zero_approx() else _hook_launch_direction
		var exit_direction := Vector3(travel_direction.x, travel_direction.y * hook_exit_vertical_fraction, travel_direction.z).normalized()
		velocity = exit_direction * hook_exit_speed
	target.on_grapple_arrival()
	if is_instance_valid(parkour_juice):
		parkour_juice.grapple_arrival(impact_pos)
	_hook_slide_timer = HOOK_SLIDE_DURATION
	velocity = velocity.limit_length(parkour_speed_limit)

func _end_hook(zero_velocity: bool = true) -> void:
	if is_instance_valid(_hook_target):
		_recent_anchor = _hook_target
		_anchor_cooldown = anchor_reuse_delay
	is_hooking = false
	_hook_target = null
	reset_pull_state()
	if zero_velocity:
		velocity = Vector3.ZERO
	else:
		velocity = velocity.limit_length(parkour_speed_limit)

func _try_restore_capsule() -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _full_capsule
	query.transform = _body_collision.global_transform
	query.transform.origin = to_global(_full_capsule_position)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.0
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return
	_body_collision.shape = _full_capsule
	_body_collision.position = _full_capsule_position
	_capsule_reduced = false

func handle_input() -> void:
	if _is_debug_fly_active():
		input_dir = Vector3.ZERO
		return
	input_dir = _read_move_input()
	if Input.is_action_just_pressed("jump_or_dash") and not _jump_event_handled:
		request_jump()
	_jump_event_handled = false

func _read_move_input() -> Vector3:
	var direction := Vector3.ZERO
	if Input.is_action_pressed("move_forwards"):
		direction.z -= 1
	if Input.is_action_pressed("move_backwards"):
		direction.z += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	var touch_move: Vector2 = hud.mobile_controls.movement
	direction += Vector3(touch_move.x, 0.0, touch_move.y)
	direction = global_transform.basis.orthonormalized() * direction.limit_length()
	direction.y = 0.0
	return direction

func request_jump() -> void:
	if not gameplay_active or get_tree().paused or is_hooking or _is_debug_fly_active():
		return
	_jump_buffer_left = maxf(jump_buffer_time, 0.000001)
	_try_buffered_jump()

func _update_jump_assistance(delta: float) -> void:
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	_coyote_time_left = maxf(0.0, _coyote_time_left - delta)
	if not gameplay_active or is_hooking or _is_debug_fly_active():
		_jump_buffer_left = 0.0
		_coyote_time_left = 0.0
		return
	_refresh_jump_ground_contact()

func _refresh_jump_ground_contact() -> void:
	if not is_on_floor():
		_jump_left_floor = true
	elif _jump_left_floor or velocity.y <= 0.0:
		_jump_ground_consumed = false
		_jump_left_floor = false
	if is_on_floor() and not _jump_ground_consumed:
		_coyote_time_left = coyote_time

func _try_buffered_jump() -> void:
	if _jump_buffer_left <= 0.0 or _jump_ground_consumed or (not is_on_floor() and _coyote_time_left <= 0.0):
		return
	_jump_buffer_left = 0.0
	_coyote_time_left = 0.0
	_jump_ground_consumed = true
	_jump_left_floor = false
	_hook_slide_timer = 0.0
	# Keep horizontal momentum and any stronger upward launch from a roof bank.
	velocity.y = maxf(velocity.y, JUMP_SPEED)
	if is_instance_valid(parkour_juice):
		parkour_juice.jump()

func handle_movement(delta: float) -> void:
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var exit_grace := _hook_slide_timer > 0.0
	_hook_slide_timer = maxf(0.0, _hook_slide_timer - delta)
	if surf_mode and is_on_floor():
		# Authored banks retain their collision-projected surf acceleration.
		horizontal_velocity *= exp(-surf_drag * delta)
		if input_dir != Vector3.ZERO:
			var desired := input_dir.normalized()
			var add_speed := maxf(0.0, MAX_SPEED - horizontal_velocity.dot(desired))
			horizontal_velocity += desired * minf(add_speed, 12.0 * input_dir.length() * delta)
		horizontal_velocity = horizontal_velocity.limit_length(parkour_speed_limit)
	elif not is_on_floor() or exit_grace or horizontal_velocity.length() > MAX_SPEED + 0.1:
		var drag := surf_drag if surf_mode else parkour_air_drag
		if is_on_floor() and not exit_grace:
			drag = parkour_ground_momentum_drag if input_dir != Vector3.ZERO else parkour_ground_coast_drag
		horizontal_velocity *= exp(-drag * delta)
		_air_control.acceleration = parkour_air_acceleration
		_air_control.turn_degrees_per_second = parkour_air_turn_speed
		_air_control.braking = parkour_air_braking
		# Steering stays horizontal and cannot consume the jump/climb component.
		var speed_budget := sqrt(maxf(0.0, parkour_speed_limit * parkour_speed_limit - velocity.y * velocity.y))
		horizontal_velocity = _air_control.step(horizontal_velocity, input_dir, MAX_SPEED, speed_budget, delta)
	elif input_dir != Vector3.ZERO:
		var target_velocity: Vector3 = input_dir * MAX_SPEED
		horizontal_velocity = horizontal_velocity.lerp(target_velocity, 1.0 - exp(-ACCEL * delta))
	else:
		horizontal_velocity *= exp(-FRICTION * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

func _apply_gravity(delta: float) -> void:
	if surf_mode:
		# Continuous gravity lets swept collision project motion down the banks.
		if is_on_floor() and velocity.y <= 0.0:
			velocity += Vector3.DOWN.slide(get_floor_normal()) * _gravity * delta
		velocity.y -= _gravity * delta
		return
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta

func register_contact_traversal(area: Area3D) -> void:
	if is_instance_valid(area) and area.is_in_group("contact_traversal"):
		_contact_traversal_areas[area.get_instance_id()] = area

func unregister_contact_traversal(area: Area3D) -> void:
	_contact_traversal_areas.erase(area.get_instance_id())

func _apply_contact_traversal(delta: float) -> void:
	if not gameplay_active or get_tree().paused or _is_debug_fly_active():
		return
	for id in _contact_traversal_areas.keys():
		var area = _contact_traversal_areas[id]
		if not is_instance_valid(area) or not area.has_live_contact(self):
			_contact_traversal_areas.erase(id)
			continue
		velocity = area.step_velocity(self,velocity,delta)

func apply_spring_launch(launch_velocity: Vector3) -> void:
	if not gameplay_active:
		return
	_end_hook(false)
	velocity = launch_velocity.limit_length(parkour_speed_limit)
	_hook_slide_timer = HOOK_SLIDE_DURATION
	grapple._clear_pending()
	if is_instance_valid(parkour_juice):
		parkour_juice.spring_launch()
