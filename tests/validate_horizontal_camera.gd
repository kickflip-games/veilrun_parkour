extends SceneTree
## Actual main-city input, neutral acquisition and upward pull with yaw-only
## manual look. Godot --headless --path . --script this_file --fixed-fps 60.
const CITY := "res://levels/parkour/MainCityRun.tscn"
const ANCHOR := "res://scenes/parkour/grapple_anchor.tscn"
const Settings = preload("res://scenes/parkour/presentation_settings.gd")
var checks := 0
var failures: Array[String] = []
var save_path := ""
var course
var anchor
var settings_before := PackedByteArray()
var saved_strength := 1.0
var saved_accumulation := true

func _initialize() -> void:
	save_path = "user://horizontal_camera_validation_%d.cfg" % OS.get_process_id()
	node_added.connect(_isolate)
	call_deferred("run")

func _isolate(node: Node) -> void:
	if node.scene_file_path == CITY:
		node.clock.save_path = save_path

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func settings_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(Settings.SAVE_PATH) if FileAccess.file_exists(Settings.SAVE_PATH) else PackedByteArray()

func mouse_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	Input.parse_input_event(event)

func touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)

func drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	Input.parse_input_event(event)

func run() -> void:
	root.size = Vector2i(1280, 720)
	settings_before = settings_bytes()
	saved_strength = Settings.effects_strength
	saved_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	course = load(CITY).instantiate()
	root.add_child(course)
	current_scene = course
	await frames(12)
	var player = course.player
	var mobile = player.hud.mobile_controls
	check(not player.vertical_look_enabled, "Authored main city disables manual vertical look")
	check(player.use_momentum_pull and player.gameplay_active, "Horizontal look retains the active momentum pull controller")
	check(player.is_on_floor(), "Authored starting capsule settles on its roof")
	check(not root.get_node("SoundManager").music_player.playing, "Main-city startup keeps background music off")
	course.set_physics_process(false)
	player.set_physics_process(false)
	player.set_process(false)
	Settings.effects_strength = 0.0
	player.parkour_juice.reset_effects()
	mobile.enabled = false
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	mouse_motion(Vector2(0, 1800))
	await process_frame
	check(is_zero_approx(player.camera.rotation.x) and is_zero_approx(player.rotation.y), "Real vertical mouse motion leaves pitch and yaw unchanged")
	mouse_motion(Vector2(0, -1800))
	await process_frame
	check(is_zero_approx(player.camera.rotation.x), "Opposite vertical mouse motion also leaves the horizon level")
	mouse_motion(Vector2(160, 240))
	await process_frame
	check(absf(wrapf(player.rotation.y + 160.0 * player.MOUSE_SENS, -PI, PI)) < 0.00001, "Real horizontal mouse motion turns the body by its configured sensitivity")
	check(is_zero_approx(player.camera.rotation.x) and absf(player.get_aim_basis().z.y) < 0.00001, "Diagonal mouse motion retains a horizontal aim vector")
	mobile.enabled = true
	mobile.set_active(true)
	await process_frame
	var touch_yaw: float = player.rotation.y
	touch(3, mobile._look_center, true)
	drag(3, mobile._look_center + Vector2(0, -mobile._radius))
	await process_frame
	check(mobile.pitch < -0.9 and is_zero_approx(mobile.turn), "Actual look-stick touch routing supplies independent vertical intent")
	player._process(0.25)
	check(is_zero_approx(player.camera.rotation.x) and is_equal_approx(player.rotation.y, touch_yaw), "Main controller ignores touch pitch while preserving yaw")
	drag(3, mobile._look_center + Vector2(mobile._radius, 0))
	await process_frame
	check(mobile.turn > 0.9 and is_zero_approx(mobile.pitch), "Horizontal look-stick drag supplies turn intent")
	player._process(0.2)
	check(absf(wrapf(player.rotation.y - touch_yaw + mobile.TURN_SPEED * 0.2, -PI, PI)) < 0.00001, "Touch turn rotates yaw at the production analog rate")
	check(is_zero_approx(player.camera.rotation.x), "Touch turning keeps the horizon level")
	touch(3, mobile._look_center, false)
	await process_frame
	check(is_zero_approx(mobile.turn) and is_zero_approx(mobile.pitch), "Releasing the look stick clears both input axes")
	mobile.enabled = false
	mobile.set_active(false)
	player.global_position = Vector3(2000, 40, 2000)
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.velocity = Vector3(4, 0, -10)
	player.parkour_juice.reset_effects()
	anchor = load(ANCHOR).instantiate()
	anchor.architectural_fixture = true
	anchor.show_label = false
	root.add_child(anchor)
	anchor.global_position = player.to_global(player._camera_base_pos) + Vector3(0, 7, -20)
	await frames(2)
	player.grapple.aim_assist_target = null
	check(player.grapple.get_lock_target() == anchor, "Level manual aim still acquires an elevated fixture inside the accepted frustum")
	var neutral_aim: Basis = player.get_aim_basis()
	Settings.effects_strength = 1.0
	player.velocity = Vector3(20, 0, -16)
	player.parkour_juice.jump()
	player.parkour_juice.update_effects(0.05)
	check(absf(player.camera.rotation.z) > 0.01 and player.camera.position.y < player._camera_base_pos.y - 0.001, "Production presentation produces actual roll and jump dip")
	check(player.get_aim_basis().is_equal_approx(neutral_aim) and absf(player.get_aim_basis().z.y) < 0.00001 and player.get_aim_basis().y.is_equal_approx(Vector3.UP), "Production aim stays level and unchanged through roll, dip and speed FOV")
	check(player.grapple.get_lock_target() == anchor, "Presentation offsets preserve elevated-anchor acquisition")
	Settings.effects_strength = 0.0
	player.parkour_juice.reset_effects()
	player.velocity = Vector3(4, 0, -10)
	var start_height: float = player.global_position.y
	player.press_pull(&"horizontal_probe")
	check(player.is_hooking, "Holding pull acquires the elevated fixture without manual pitch")
	player.set_physics_process(true)
	await frames(6)
	player.set_physics_process(false)
	check(player.velocity.y > 0.3 and player.global_position.y > start_height + 0.01, "Production pull physics still creates upward velocity and lift")
	check(is_zero_approx(player.camera.rotation.x) and absf(player.get_aim_basis().z.y) < 0.00001, "Upward traversal leaves manual aim horizontal")
	var release_velocity: Vector3 = player.velocity
	player.release_pull(&"horizontal_probe")
	check(not player.is_hooking and player.velocity.is_equal_approx(release_velocity), "Releasing the hold preserves the upward traversal momentum")
	mobile.enabled = true
	mobile.set_active(true)
	await process_frame
	touch(9, mobile._look_center, true)
	drag(9, mobile._look_center + Vector2(mobile._radius * 0.7, -mobile._radius * 0.7))
	await process_frame
	player.press_pull(&"retry_hold")
	player.request_jump()
	course.respawn_checkpoint()
	await process_frame
	check(player._pull_input_sources.is_empty() and is_zero_approx(mobile.turn) and is_zero_approx(mobile.pitch) and mobile._look_finger == -1, "Sector retry clears held pull and touch look input")
	check(player._jump_buffer_left == 0.0 and player._coyote_time_left == 0.0 and not player.is_hooking, "Sector retry clears jump assistance and active hook state")
	check(player.camera.rotation.is_zero_approx() and player.get_aim_basis().is_equal_approx(course._spawn_transform.basis), "Sector retry restores neutral camera and authored forward aim")
	check(not course.clock.clean_run and not FileAccess.file_exists(save_path), "The retry remains practice and never writes a real PB")
	course.restart()
	await frames(12)
	course = current_scene
	player = course.player
	check(not player.vertical_look_enabled and player.camera.rotation.is_zero_approx(), "Full scene retry preserves the authored horizontal-look setting")
	check(course.clock.clean_run and course.clock.state == 0 and player._pull_input_sources.is_empty(), "Full retry restores clean READY and no held pull")
	check(settings_bytes() == settings_before, "Camera validation leaves saved preferences byte identical")
	Settings.effects_strength = saved_strength
	Input.use_accumulated_input = saved_accumulation
	player.parkour_juice.wind_player.stop()
	player.parkour_juice.wind_player.stream = null
	for child in root.get_node("SoundManager").get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	root.get_node("GameManager").player = null
	anchor.queue_free()
	course.queue_free()
	current_scene = null
	await frames(3)
	DirAccess.remove_absolute(save_path)
	OS.delay_msec(150)
	print("HORIZONTAL_CAMERA_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
