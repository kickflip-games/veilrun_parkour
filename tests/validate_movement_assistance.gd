extends SceneTree
## Actual production capsule on isolated roof edges/slopes plus collider-backed
## target scoring. No course clock is instantiated and no saves are written.
## Godot --headless --fixed-fps 60 --path . --script tests/validate_movement_assistance.gd -- --assist-fps=60

const AudioCleanup = preload("res://tests/audio_test_cleanup.gd")
var player
var anchor
var second_anchor
var flat: StaticBody3D
var edge: StaticBody3D
var slope: StaticBody3D
var checks := 0
var failures: Array[String] = []
var fps := 60
var metrics := {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--assist-fps="):
			fps = int(argument.get_slice("=", 1))
	Engine.physics_ticks_per_second = fps
	call_deferred("run")

func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func box(label: String, position: Vector3, size: Vector3, angle := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position
	body.rotation.z = deg_to_rad(angle)
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	return body

func clear() -> void:
	player.set_physics_process(false)
	player.reset_movement_input()
	player._end_hook(true)
	for action in ["move_forwards", "move_backwards", "move_left", "move_right"]:
		Input.action_release(action)
	player._body_collision.shape = player._full_capsule
	player._body_collision.position = player._full_capsule_position
	player._capsule_reduced = false
	player._hook_slide_timer = 0.0
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.input_dir = Vector3.ZERO
	player.gameplay_active = true
	anchor.global_position = Vector3(2000, 100, 0)
	second_anchor.global_position = Vector3(2010, 100, 0)
	player.grapple.aim_assist_target = null

func roof(body: StaticBody3D, surf := false) -> void:
	clear()
	player.surf_mode = surf
	player.floor_stop_on_slope = not surf
	player.floor_constant_speed = false
	player.floor_block_on_wall = not surf
	var normal: Vector3 = body.global_basis.y
	var capsule: CapsuleShape3D = player._full_capsule
	var support := capsule.radius + (capsule.height * 0.5 - capsule.radius) * normal.y
	var height: float = (0.5 + support) / normal.y - player._full_capsule_position.y + 0.035
	player.global_position = body.global_position + Vector3.UP * height
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await frames(maxi(4, roundi(0.15 * fps)))
	check(player.is_on_floor(), body.name + " supports the actual standing capsule")

func coyote() -> void:
	await roof(edge)
	player.global_position.z = -2.0
	player.velocity = Vector3(0, 0, -24)
	Input.action_press("move_forwards")
	var left := false
	for _tick in range(fps):
		await frames(1)
		if not player.is_on_floor():
			left = true
			break
	await frames(maxi(1, roundi(0.04 * fps)))
	var before: Vector3 = player.velocity
	var count: int = player.parkour_juice.jump_count
	player.request_jump()
	check(left and player.velocity.y >= player.JUMP_SPEED and player.velocity.x == before.x and player.velocity.z == before.z,
		"A late edge jump uses coyote time and preserves horizontal velocity")
	player.request_jump()
	check(player.parkour_juice.jump_count == count + 1, "Coyote time permits one jump and cannot create a second air jump")
	await frames(2)
	check(not player.is_on_floor() and player.velocity.y > 0.0, "The coyote launch lifts the real capsule beyond the edge")
	metrics["coyote_speed"] = Vector2(player.velocity.x, player.velocity.z).length()
	await roof(edge)
	player.global_position.z = -2.0
	player.velocity = Vector3(0, 0, -24)
	Input.action_press("move_forwards")
	for _tick in range(fps):
		await frames(1)
		if not player.is_on_floor():
			break
	await frames(ceili((player.coyote_time + 0.06) * fps))
	count = player.parkour_juice.jump_count
	player.request_jump()
	check(player.velocity.y < 0.0 and player.parkour_juice.jump_count == count, "A fall beyond the coyote window cannot jump in midair")

func buffered_landing() -> void:
	await roof(flat)
	var roof_height: float = player.global_position.y
	player.velocity = Vector3(0, 0, -20)
	Input.action_press("move_forwards")
	player.request_jump()
	await frames(2)
	for _tick in range(2 * fps):
		await frames(1)
		if player.velocity.y < 0.0 and player.global_position.y < roof_height + 0.62:
			break
	check(not player.is_on_floor(), "Buffered-jump setup descends from an actual previous jump")
	var count: int = player.parkour_juice.jump_count
	var approach_speed: float = -player.velocity.z
	player.request_jump()
	check(player.velocity.y < 0.0 and player.parkour_juice.jump_count == count, "Pressing just before landing buffers without an air jump")
	var jumped := false
	for _tick in range(ceili(0.2 * fps)):
		await frames(1)
		if player.parkour_juice.jump_count > count:
			jumped = true
			break
	check(jumped and player.velocity.y > 0.0 and -player.velocity.z > approach_speed * 0.9, "The buffered press launches once on landing with racing momentum")
	await frames(maxi(2, roundi(0.25 * fps)))
	check(player.parkour_juice.jump_count == count + 1, "A consumed landing buffer does not repeat the jump")
	await roof(flat)
	player.reset_movement_input()
	player.global_position.y += 3.0
	player.velocity = Vector3(0, -1, 0)
	await frames(1)
	player.reset_movement_input()
	count = player.parkour_juice.jump_count
	player.request_jump()
	await frames(fps)
	check(player.is_on_floor() and player.parkour_juice.jump_count == count, "An expired early press does not surprise-jump on a later landing")
	player.request_jump()
	player.reset_movement_input()
	check(player._jump_buffer_left == 0.0 and player._coyote_time_left == 0.0, "Recovery reset clears both jump assistance windows")

func slope_launch() -> void:
	await roof(slope, true)
	player.velocity = Vector3(12, 7, -20)
	var before: Vector3 = player.velocity
	player.request_jump()
	check(player.velocity == before, "A slope-edge jump preserves a stronger incoming upward launch and horizontal speed")
	await frames(2)
	check(not player.is_on_floor() and player.velocity.y > 5.5, "The stronger slope launch detaches from floor snap")
	await roof(slope, true)
	player.velocity = Vector3(0, 0, -20)
	var height: float = player.global_position.y
	player.request_jump()
	await frames(maxi(2, roundi(0.1 * fps)))
	check(not player.is_on_floor() and player.global_position.y > height + 0.3 and -player.velocity.z > 19.0, "Ordinary surf-slope jumping lifts the capsule without consuming forward momentum")
	await roof(flat)
	player.jump_buffer_time = 0.0
	player.request_jump()
	check(player.velocity.y == player.JUMP_SPEED, "Turning jump buffering off retains immediate grounded jump")
	player.jump_buffer_time = 0.14

func targeting() -> void:
	clear()
	player.global_position = Vector3(1000, 100, 0)
	player.velocity = Vector3(20, 0, -20)
	player.grapple.hook_range = 32.0
	var origin: Vector3 = player.to_global(player._camera_base_pos)
	anchor.global_position = origin + Vector3(-0.8, 0, -20)
	second_anchor.global_position = origin + Vector3(0.8, 0, -20)
	await frames(2)
	player.grapple.aim_assist_target = null
	check(player.grapple.get_lock_target() == second_anchor, "Near-equal camera candidates prefer the current movement direction")
	anchor.global_position = origin + Vector3(0, 0, -20)
	second_anchor.global_position = origin + Vector3(2.0, 0, -20)
	await frames(2)
	player.grapple.aim_assist_target = null
	check(player.grapple.get_lock_target() == anchor, "Camera aim outweighs movement assistance for clearly distinct candidates")
	var neutral: Basis = player.get_aim_basis()
	player.camera.rotation.z = 0.15
	player.camera.position.y -= 0.15
	player.camera.fov = 100.0
	check(player.get_aim_basis().is_equal_approx(neutral) and player.grapple.get_lock_target() == anchor,
		"Presentation roll, dip and FOV do not change assisted acquisition")
	var wall := box("TargetLOS", origin + Vector3(0, 0, -10), Vector3(0.8, 8, 0.5))
	await frames(2)
	player.grapple.aim_assist_target = null
	check(player.grapple.get_lock_target() == second_anchor, "Scoring never acquires through a real LOS obstacle")
	wall.queue_free()
	await frames(2)
	anchor.global_position = origin + Vector3(100, 0, 0)
	second_anchor.global_position = origin + Vector3(sin(deg_to_rad(12.2)), 0, -cos(deg_to_rad(12.2))) * 20.0
	await frames(2)
	player.grapple.aim_assist_target = second_anchor
	check(player.grapple.get_lock_target() == null, "Retention and motion scoring do not extend the exact acquisition cone")

func run() -> void:
	player = load("res://scenes/player/player.tscn").instantiate()
	player.use_momentum_pull = true
	player.vertical_look_enabled = true
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.hud.parkour_ready()
	root.get_node("SoundManager").music_player.stop()
	anchor = load("res://scenes/parkour/grapple_anchor.tscn").instantiate()
	second_anchor = load("res://scenes/parkour/grapple_anchor.tscn").instantiate()
	root.add_child(anchor)
	root.add_child(second_anchor)
	flat = box("WideRoof", Vector3(1000, 20, 0), Vector3(100, 1, 100))
	edge = box("RoofEdge", Vector3(1200, 20, 0), Vector3(12, 1, 8))
	slope = box("SlateSlope", Vector3(1400, 20, 0), Vector3(100, 1, 100), 15.0)
	await frames(2)
	await coyote()
	await buffered_landing()
	await slope_launch()
	await targeting()
	AudioCleanup.stop_voices(self)
	root.get_node("GameManager").player = null
	for node in [player, anchor, second_anchor, flat, edge, slope]:
		node.queue_free()
	await frames(3)
	AudioCleanup.drain_mixer()
	print("MOVEMENT_ASSIST_RESULT ", JSON.stringify({"physics_fps":fps, "checks":checks, "failures":failures, "metrics":metrics}))
	quit(0 if failures.is_empty() else 1)
