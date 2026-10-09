extends SceneTree
## Real mouse/touch press and release events against the production player.
## No course clock is instantiated; saved records/settings are never written.
## Godot --headless --fixed-fps 60 --path . --script tests/validate_grapple_click.gd

const AudioCleanup = preload("res://tests/audio_test_cleanup.gd")
const START := Vector3(1000, 100, 0)
class Errors extends Logger:
	var captured: Array[String] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, error_type: int, _traces: Array) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			captured.append("%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file, line, function])

var error_log := Errors.new()
var failures: Array[String] = []
var checks := 0
var player
var anchor

func _initialize() -> void:
	OS.add_logger(error_log)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func mouse(pressed: bool, button: int = MOUSE_BUTTON_LEFT, position := Vector2(640, 360)) -> void:
	var event := InputEventMouseButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	event.position = root.get_final_transform() * position
	event.global_position = event.position
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func touch(pressed: bool, index: int = 0, point := Vector2.ZERO, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.device = 0
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	var logical_point: Vector2 = player.hud.mobile_controls._dash_center if point == Vector2.ZERO else point
	# parse_input_event accepts window pixels; headless windows can be 64x64.
	event.position = root.get_final_transform() * logical_point
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func setup(momentum := true, mobile := false, distance := 28.0) -> void:
	paused = false
	player.hud.is_paused = false
	player.hud.pause_screen.hide()
	player.gameplay_active = false
	mouse(false)
	mouse(false, MOUSE_BUTTON_RIGHT)
	Input.action_release("grapple")
	player.set_physics_process(false)
	player.reset_movement_input()
	player._end_hook(true)
	player._recent_anchor = null
	player._anchor_cooldown = 0.0
	player._hook_slide_timer = 0.0
	player._body_collision.shape = player._full_capsule
	player._body_collision.position = player._full_capsule_position
	player._capsule_reduced = false
	player.global_position = START
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.use_momentum_pull = momentum
	player.pull_max_duration = 2.8
	player.hud.mobile_controls.enabled = mobile
	player.hud.mobile_controls.set_active(mobile)
	player.hud.mobile_controls.reset_touches()
	player.grapple.aim_assist_target = null
	anchor.global_position = player.to_global(player._camera_base_pos) + Vector3.FORWARD * distance
	await frames(2)
	player.gameplay_active = true
	player.hud.mobile_controls.set_active(mobile)
	player.set_physics_process(true)
	check(player.grapple.get_lock_target() == anchor, "Isolated click setup acquires the actual anchor collider")

func desktop(momentum: bool, button: int) -> void:
	var label := ("Momentum" if momentum else "Comparison") + (" left mouse" if button == MOUSE_BUTTON_LEFT else " right mouse")
	await setup(momentum)
	mouse(true, button)
	await frames(2)
	check(player.is_hooking, label + " starts from one button press")
	await frames(3)
	check(player.is_hooking, label + " stays active while held without retriggering")
	var velocity: Vector3 = player.velocity.limit_length(player.parkour_speed_limit)
	mouse(false, button)
	check(not player.is_hooking and player.velocity.distance_to(velocity) < 0.001, label + " release immediately stops force and preserves bounded momentum")
	await frames(3)
	check(not player.is_hooking, label + " release cannot restart a pull")

func quick_clicks() -> void:
	await setup()
	mouse(true)
	mouse(false)
	check(not player.is_hooking, "A full tap between physics frames releases immediately")
	await frames(2)
	check(not player.is_hooking and not Input.is_action_pressed("grapple"), "A short tap leaves no pull queued for the next physics tick")
	await setup()
	mouse(true)
	mouse(true, MOUSE_BUTTON_RIGHT)
	mouse(false)
	check(player.is_hooking, "Two mapped mouse buttons keep the pull until both are lifted")
	mouse(false, MOUSE_BUTTON_RIGHT)
	check(not player.is_hooking, "Lifting the last held mouse button releases")

func guards() -> void:
	await setup()
	mouse(true)
	await frames(2)
	var velocity: Vector3 = player.velocity
	player.hud.toggle_pause()
	check(not player.is_hooking and player.velocity.is_equal_approx(velocity), "Entering pause cancels the hold without changing momentum")
	mouse(true)
	mouse(false)
	var jump := InputEventKey.new()
	jump.device = 0
	jump.physical_keycode = KEY_SPACE
	jump.keycode = KEY_SPACE
	jump.pressed = true
	Input.parse_input_event(jump)
	Input.flush_buffered_events()
	player.hud.toggle_pause()
	check(not Input.is_action_pressed("jump_or_dash") and player._jump_buffer_left == 0.0, "Resuming clears Space pressed during pause before polling can replay it")
	jump = jump.duplicate()
	jump.pressed = false
	Input.parse_input_event(jump)
	Input.flush_buffered_events()
	await frames(2)
	check(not player.is_hooking, "Paused clicks are discarded and cannot reacquire on resume")
	player.hud.toggle_pause()
	await frames(2)
	var resume: Button = player.hud.get_node("PauseScreen/PanelContainer/VBoxContainer/ResumeButton")
	var resume_point := resume.get_global_rect().get_center()
	mouse(true, MOUSE_BUTTON_LEFT, resume_point)
	mouse(false, MOUSE_BUTTON_LEFT, resume_point)
	await frames(2)
	check(not paused and not player.hud.is_paused and not player.is_hooking, "Clicking the real RESUME button resumes without starting a pull")
	await setup()
	player.gameplay_active = false
	mouse(true)
	mouse(false)
	player.gameplay_active = true
	await frames(2)
	check(not player.is_hooking, "An inactive click cannot launch after gameplay becomes active")
	await setup(true, true)
	player.request_hook()
	mouse(true)
	mouse(false)
	await frames(2)
	check(player.is_hooking, "Emulated mouse events are ignored when touch controls own input")
	await setup()
	mouse(true)
	root.get_window().focus_exited.emit()
	check(not player.is_hooking and player._pull_input_sources.is_empty(), "Losing window focus releases and clears the held pull")
	await frames(2)
	check(not player.is_hooking, "Focus recovery cannot replay the held press")

func mobile() -> void:
	await setup(true, true)
	touch(true)
	await frames(2)
	check(player.is_hooking and player.hud.mobile_controls.pull_active, "Touch-down starts a pull and highlights the PULL control")
	touch(false, 7)
	check(player.is_hooking, "Lifting an unrelated finger does not release the pull")
	var velocity: Vector3 = player.velocity
	touch(false)
	check(not player.is_hooking and player.velocity.distance_to(velocity) < 0.001, "Lifting the pull finger releases immediately and keeps momentum")
	await frames(2)
	check(not player.hud.mobile_controls.pull_active, "The PULL control returns to neutral after releasing")
	await setup(true, true)
	touch(true)
	touch(false)
	touch(true)
	touch(false)
	await frames(2)
	check(not player.is_hooking, "Rapid touch taps leave no latched or queued pull")
	await setup(true, true)
	touch(true)
	touch(false, 0, Vector2.ZERO, true)
	check(not player.is_hooking, "A canceled touch releases the held pull")
	await setup(true, true)
	touch(true)
	player.hud.mobile_controls.reset_touches()
	check(not player.is_hooking, "Touch reset releases a pull before recovery")
	await setup(true, true)
	touch(true)
	player.hud.toggle_pause()
	touch(true)
	touch(false)
	player.hud.toggle_pause()
	await frames(2)
	check(not player.is_hooking, "Touch pause/resume discards the old hold and menu taps")

func automatic_endings() -> void:
	await setup(true, false, 10.0)
	mouse(true)
	await frames(2)
	check(player.is_hooking, "Holding starts the automatic-arrival probe")
	for _index in range(100):
		await frames(1)
		if not player.is_hooking:
			break
	check(not player.is_hooking and player.global_position.distance_to(anchor.global_position) < player.pull_arrival_distance + 1.0 and player.velocity.length() > 10.0, "Arrival ends a held pull and preserves exit momentum")
	player.set_physics_process(false)
	anchor.global_position = player.to_global(player._camera_base_pos) + Vector3.FORWARD * 20.0
	player._anchor_cooldown = 0.0
	await frames(3)
	check(player.grapple.get_lock_target() == anchor and not player.is_hooking, "A held button cannot reacquire after auto-release even with a valid new target position")
	mouse(false)
	mouse(true)
	check(player.is_hooking, "A fresh release/press can acquire again after automatic arrival")
	mouse(false)
	await setup()
	player.pull_max_duration = 0.5
	mouse(true)
	await frames(2)
	check(player.is_hooking, "Holding starts the duration-limit probe")
	await frames(36)
	check(not player.is_hooking and player._pull_solver.elapsed == 0.0 and player.global_position.distance_to(anchor.global_position) > player.pull_arrival_distance and player.velocity.length() > 10.0, "Duration limit releases a held pull with bounded momentum")
	player.set_physics_process(false)
	anchor.global_position = player.to_global(player._camera_base_pos) + Vector3.FORWARD * 20.0
	player._anchor_cooldown = 0.0
	await frames(40)
	check(not player.is_hooking, "Holding past duration and cooldown never silently reacquires")
	mouse(false)

func run() -> void:
	player = load("res://scenes/player/player.tscn").instantiate()
	player.use_momentum_pull = true
	player.vertical_look_enabled = true
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.hud.parkour_ready()
	player.grapple.hook_range = 32.0
	root.get_node("SoundManager").music_player.stop()
	anchor = load("res://scenes/parkour/grapple_anchor.tscn").instantiate()
	root.add_child(anchor)
	for momentum in [true, false]:
		for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			await desktop(momentum, button)
	await quick_clicks()
	await guards()
	await mobile()
	await automatic_endings()
	check(error_log.captured.is_empty(), "Input validation produced no script errors")
	AudioCleanup.stop_voices(self)
	root.get_node("GameManager").player = null
	player.queue_free()
	anchor.queue_free()
	await frames(3)
	AudioCleanup.drain_mixer()
	print("GRAPPLE_CLICK_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "script_errors": error_log.captured}))
	OS.remove_logger(error_log)
	quit(0 if failures.is_empty() and error_log.captured.is_empty() else 1)
