extends SceneTree
## Real CharacterBody air-control benchmark. Position/velocity are seeded only at
## isolated setup; the measured interval uses production input and swept physics.
## Run --fixed-fps 30/60/120 --script tests/validate_air_control.gd -- --air-fps=60.
## --baseline records old responsiveness while keeping safety assertions active.

var player
var anchor
var fps := 60
var baseline := false
var checks := 0
var failures: Array[String] = []
var metrics := {}
var trace: Array[Dictionary] = []
const START := Vector3(1000, 100, 0)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--air-fps="):
			fps = int(argument.get_slice("=", 1))
		if argument == "--baseline":
			baseline = true
	Engine.physics_ticks_per_second = fps
	call_deferred("run")

func ticks(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func check(condition: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if condition else "FAIL ", message)
	if not condition:
		failures.append(message)

func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func release_inputs() -> void:
	for action in ["move_forwards", "move_backwards", "move_left", "move_right", "grapple", "jump_or_dash"]:
		Input.action_release(action)
	player.hud.mobile_controls.reset_touches()
	player.hud.mobile_controls.enabled = false
	player.hud.mobile_controls.set_active(false)

func setup(speed: float, vertical: float = 0.0) -> void:
	release_inputs()
	player.set_physics_process(false)
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
	player.velocity = Vector3(0, vertical, -speed)
	player.input_dir = Vector3.ZERO
	player.gameplay_active = true
	anchor.global_position = Vector3(1800, 150, 0)
	await ticks(2)
	player.set_physics_process(true)

func yaw(degrees: float) -> void:
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(-deg_to_rad(degrees) / player.MOUSE_SENS, 0)
	player._input(mouse)

func hold(action: String, mobile := false, magnitude := 1.0) -> void:
	if not mobile:
		Input.action_press(action)
		return
	player.hud.mobile_controls.enabled = true
	player.hud.mobile_controls.set_active(true)
	var direction := Vector2.ZERO
	match action:
		"move_forwards": direction = Vector2.UP
		"move_backwards": direction = Vector2.DOWN
		"move_right": direction = Vector2.RIGHT
		"move_left": direction = Vector2.LEFT
	var controls = player.hud.mobile_controls
	var touch := InputEventScreenTouch.new()
	touch.index = 31
	touch.pressed = true
	touch.position = controls._move_center
	controls._input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 31
	drag.position = controls._move_center + direction * controls._radius * (controls.DEADZONE + (1.0 - controls.DEADZONE) * magnitude)
	controls._input(drag)

func record(label: String, seconds: float, desired := Vector3.ZERO) -> Dictionary:
	var peak: float = player.velocity.length()
	var max_step := 0.0
	var previous: Vector3 = player.global_position
	var wall_contacts := 0
	var previous_horizontal := Vector3(player.velocity.x, 0, player.velocity.z).length()
	var max_horizontal_drop := 0.0
	var first_floor_time := -1.0
	var first_floor_speed := 0.0
	var grounded_after_grace := false
	for index in range(roundi(seconds * fps)):
		await ticks(1)
		peak = maxf(peak, player.velocity.length())
		max_step = maxf(max_step, player.global_position.distance_to(previous))
		previous = player.global_position
		if player.is_on_wall(): wall_contacts += 1
		var horizontal_speed := Vector3(player.velocity.x, 0, player.velocity.z).length()
		max_horizontal_drop = maxf(max_horizontal_drop, previous_horizontal - horizontal_speed)
		previous_horizontal = horizontal_speed
		if player.is_on_floor():
			if first_floor_time < 0.0:
				first_floor_time = float(index + 1) / fps
				first_floor_speed = horizontal_speed
			if player._hook_slide_timer <= 0.0: grounded_after_grace = true
		if index % maxi(1, fps / 10) == 0:
			trace.append({"probe":label, "time":float(index + 1) / fps,
				"position":vector(player.global_position), "velocity":vector(player.velocity), "pulling":player.is_hooking,
				"grounded":player.is_on_floor(), "release_grace":player._hook_slide_timer})
	var horizontal := Vector3(player.velocity.x, 0, player.velocity.z)
	var result := {"position":vector(player.global_position), "velocity":vector(player.velocity),
		"horizontal_speed":horizontal.length(), "forward_speed":-horizontal.z,
		"side_speed":horizontal.x, "peak_speed":peak, "max_step":max_step,
		"wall_contacts":wall_contacts, "view_yaw_degrees":rad_to_deg(player.rotation.y),
		"max_horizontal_drop":max_horizontal_drop, "first_floor_time":first_floor_time,
		"first_floor_speed":first_floor_speed, "grounded_after_grace":grounded_after_grace}
	if not desired.is_zero_approx() and not horizontal.is_zero_approx():
		result["heading_error_degrees"] = rad_to_deg(horizontal.angle_to(desired))
	metrics[label] = result
	check(peak <= 32.02 and max_step <= 32.02 / fps + 0.02, label + " stays capped and moves continuously")
	return result

func turn_probe(speed: float, degrees: float, mobile := false) -> Dictionary:
	await setup(speed)
	yaw(degrees)
	hold("move_forwards", mobile)
	var desired: Vector3 = -player.global_basis.z
	return await record("turn_%d_%d_%s" % [speed, degrees, "touch" if mobile else "keys"], 0.5, desired)

func run() -> void:
	var sound = root.get_node("SoundManager")
	sound.music_player.stop()
	sound.music_player.stream = null
	player = load("res://scenes/player/player.tscn").instantiate()
	player.use_momentum_pull = true
	player.vertical_look_enabled = true
	root.add_child(player)
	current_scene = player
	anchor = load("res://scenes/parkour/grapple_anchor.tscn").instantiate()
	root.add_child(anchor)
	await ticks(3)
	player.hud.parkour_ready()
	player.grapple.hook_range = 32.0
	for speed in [24.0, 32.0]:
		for degrees in [45.0, 90.0]:
			var turned := await turn_probe(speed, degrees)
			if not baseline:
				check(turned["heading_error_degrees"] < 20.0 and turned["horizontal_speed"] > speed * 0.8,
					"Held forward corrects a %d degree air turn at %d m/s within half a second" % [degrees, speed])
	await setup(32)
	yaw(30)
	hold("move_forwards")
	var shallow := await record("shallow_turn_32", 0.2, -player.global_basis.z)
	if not baseline:
		check(shallow["heading_error_degrees"] < 5.0 and shallow["horizontal_speed"] > 32.0 * 0.9,
			"A shallow high-speed turn responds within a fifth of a second")
	await setup(24, 6)
	yaw(45)
	hold("move_forwards")
	var vertical := await record("vertical_turn", 0.5, -player.global_basis.z)
	check(absf(vertical["velocity"][1] - (6.0 - player._gravity * 0.5)) < 0.02,
		"Horizontal air steering preserves the independent vertical/gravity arc")
	await setup(24)
	hold("move_right")
	var right := await record("side_right", 0.5, Vector3.RIGHT)
	await setup(24)
	hold("move_left")
	var left := await record("side_left", 0.5, Vector3.LEFT)
	check(absf(right["side_speed"] + left["side_speed"]) < 0.02, "Left and right air corrections are symmetric")
	if not baseline:
		check(right["side_speed"] > 12.0 and right["heading_error_degrees"] < 35.0,
			"Side input makes a useful high-speed correction within half a second")
	await setup(24)
	hold("move_backwards")
	var brake_initial := await record("brake_initial", 0.2)
	var brake := await record("brake_half", 0.3)
	var reversed := await record("brake_full", 0.5)
	if not baseline:
		check(brake_initial["forward_speed"] > 0.0 and brake_initial["forward_speed"] < 16.0
			and absf(brake_initial["side_speed"]) < 0.01,
			"Opposing input first brakes along the existing heading")
		check(brake["forward_speed"] < 0.0 and brake["horizontal_speed"] <= 8.02,
			"Held backward input reverses only after forward momentum is spent")
		check(absf(reversed["forward_speed"] + 8.0) < 0.05 and absf(reversed["side_speed"]) < 0.01,
			"Continued backward input reaches bounded reverse walking speed")
	for speed in [24.0, 32.0]:
		await setup(speed)
		var coast := await record("coast_%d" % speed, 0.5)
		check(coast["horizontal_speed"] > speed * 0.85 and absf(coast["side_speed"]) < 0.01,
			"No-input coast keeps momentum and heading")
	var keyboard := await turn_probe(24, 45)
	var touch := await turn_probe(24, 45, true)
	check(absf(keyboard["heading_error_degrees"] - touch["heading_error_degrees"]) < 0.05
		and absf(keyboard["horizontal_speed"] - touch["horizontal_speed"]) < 0.05,
		"Full touch-stick and keyboard intents use equivalent control")
	await setup(24)
	hold("move_right", true, 0.4)
	var analog := await record("side_touch_partial", 0.5, Vector3.RIGHT)
	if not baseline:
		var partial_angle: float = 90.0 - analog["heading_error_degrees"]
		var full_angle: float = 90.0 - right["heading_error_degrees"]
		check(partial_angle > 5.0 and partial_angle < full_angle * 0.8,
			"Partial touch input gives a smaller deliberate correction")
	await setup(24)
	hold("move_forwards", true)
	var look_touch := InputEventScreenTouch.new()
	look_touch.index = 32
	look_touch.pressed = true
	look_touch.position = player.hud.mobile_controls._look_center
	player.hud.mobile_controls._input(look_touch)
	var look_drag := InputEventScreenDrag.new()
	look_drag.index = 32
	look_drag.position = look_touch.position + Vector2.LEFT * player.hud.mobile_controls._radius
	player.hud.mobile_controls._input(look_drag)
	var mobile_turn := await record("touch_live_turn", 0.5)
	check(mobile_turn["view_yaw_degrees"] > 70.0, "Live look-stick rotates the production player during flight")
	if not baseline:
		var heading := Vector3(mobile_turn["velocity"][0], 0, mobile_turn["velocity"][2])
		check(rad_to_deg(heading.angle_to(-player.global_basis.z)) < 35.0,
			"Velocity follows a continuously turning touch view")

	await setup(24, 2)
	anchor.global_position = START + Vector3(0, 8, -30)
	await ticks(1)
	player.start_grapple(anchor)
	hold("move_right")
	var pull := await record("pull_steer", 0.4, Vector3.RIGHT)
	check(player.is_hooking, "Pull-steering probe remains a live force flight")
	if not baseline:
		check(pull["side_speed"] > 5.0, "Air input has useful steering authority during a strong pull")

	var wall := StaticBody3D.new()
	wall.position = START + Vector3(3, 5, -7)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 20, 10)
	collision.shape = shape
	wall.add_child(collision)
	root.add_child(wall)
	await setup(20, 2)
	player.velocity.x = 10.0
	anchor.global_position = START + Vector3(6, 7, -28)
	await ticks(1)
	player.start_grapple(anchor)
	await record("wall_before_release", 0.2)
	var released: Vector3 = player.velocity
	player.request_hook()
	check(player.velocity.distance_to(released) < 0.001, "Release begins with the existing trajectory")
	var wall_slide := await record("wall_after_release", 0.5)
	check(wall_slide["wall_contacts"] > 0, "Released-air probe makes real side-wall contact")
	if not baseline:
		check(wall_slide["horizontal_speed"] > 15.0 and wall_slide["position"][2] < -13.0,
			"Released wall contact retains useful projected speed past the wall")
	wall.queue_free()
	await ticks(2)

	# The full capsule falls onto an actual floor during release grace. Holding
	# forward crosses the timer boundary without reseeding body state mid-run.
	var floor_body := StaticBody3D.new()
	floor_body.position = START + Vector3(0, -2.5, -12)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(100, 1, 100)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	root.add_child(floor_body)
	await setup(24, -4)
	player._hook_slide_timer = 0.5
	hold("move_forwards")
	var landing := await record("landing_grace", 0.8)
	check(landing["first_floor_time"] > 0.0 and landing["first_floor_time"] < 0.5
		and landing["grounded_after_grace"], "Landing probe crosses release grace on a real floor")
	if not baseline:
		check(landing["max_horizontal_drop"] < 2.0 and landing["horizontal_speed"] > 16.0,
			"Landing and grace expiry preserve speed with smooth deceleration")
	floor_body.queue_free()

	release_inputs()
	player.gameplay_active = false
	player._end_hook(true)
	load("res://tests/audio_test_cleanup.gd").stop_voices(self)
	root.get_node("GameManager").player = null
	player.queue_free()
	anchor.queue_free()
	await ticks(6)
	load("res://tests/audio_test_cleanup.gd").drain_mixer()
	print("AIR_CONTROL_RESULT ", JSON.stringify({"physics_fps":fps, "baseline":baseline,
		"checks":checks, "failures":failures, "metrics":metrics, "trace":trace}))
	quit(0 if failures.is_empty() else 1)
