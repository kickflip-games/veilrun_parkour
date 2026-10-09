extends SceneTree
## Actual player/capsule physics on isolated probe geometry. No course PB writes.
## Godot --headless --path . --script tests/validate_surf_movement.gd --fixed-fps 60

var course
var player
var failures: Array[String] = []
var metrics: Dictionary = {}
var flat: StaticBody3D
var shallow: StaticBody3D
var steep: StaticBody3D

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for _tick in range(count):
		await physics_frame

func check(condition: bool, message: String) -> void:
	print("CHECK ", "PASS " if condition else "FAIL ", message)
	if not condition:
		failures.append(message)

func box(name: String, position: Vector3, size: Vector3, angle := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
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

func profile(enabled: bool) -> void:
	player.surf_mode = enabled
	player.floor_stop_on_slope = not enabled
	player.floor_constant_speed = false
	player.floor_block_on_wall = not enabled

func release_inputs() -> void:
	for action in ["move_forwards", "move_backwards", "move_left", "move_right", "grapple", "jump_or_dash"]:
		Input.action_release(action)
	player.hud.mobile_controls.reset_touches()

func place(body: StaticBody3D, enabled: bool) -> void:
	release_inputs()
	profile(enabled)
	player._end_hook(true)
	player.grapple._clear_pending()
	player._body_collision.shape = player._full_capsule
	player._body_collision.position = player._full_capsule_position
	player._capsule_reduced = false
	player._hook_slide_timer = 0.0
	player.rotation = Vector3.ZERO
	# Capsule support above the slanted box's upper plane, with upright body.
	var normal: Vector3 = body.global_basis.y
	var capsule: CapsuleShape3D = player._full_capsule
	var support := capsule.radius + (capsule.height * 0.5 - capsule.radius) * normal.y
	var center_offset: float = player._full_capsule_position.y
	var height := (0.5 + support) / normal.y - center_offset + 0.035
	player.global_position = body.global_position + Vector3.UP * height
	player.velocity = Vector3.ZERO
	player.input_dir = Vector3.ZERO
	player.gameplay_active = true
	await frames(8)

func downhill_probe(enabled: bool) -> Dictionary:
	await place(shallow, enabled)
	var start: Vector3 = player.global_position
	var start_speed: float = player.velocity.length()
	await frames(120)
	return {"distance": player.global_position.distance_to(start), "dx": player.global_position.x - start.x,
		"initial_speed": start_speed, "final_speed": player.velocity.length(), "on_floor": player.is_on_floor()}

func run() -> void:
	course = load("res://levels/parkour/parkour_trial.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	await frames(5)
	player = course.player
	# These probes do not use rhythm timing; release MP3 playback before the
	# accelerated fixed-fps run so the audio thread can clean up normally.
	root.get_node("SoundManager").music_player.stop()
	root.get_node("SoundManager").music_player.stream = null
	course.set_physics_process(false)
	course.clock.save_path = "user://surf_movement_validation.cfg"
	# Probe bodies are far outside the course's areas; timer remains READY.
	flat = box("SurfFlatProbe", Vector3(1000, 20, 0), Vector3(120, 1, 120))
	shallow = box("SurfShallowProbe", Vector3(1200, 20, 0), Vector3(100, 1, 120), 15.0)
	steep = box("SurfSteepProbe", Vector3(1400, 20, 0), Vector3(120, 1, 160), 55.0)
	await frames(3)
	check(player.parkour_mode and player.gameplay_active, "Probe uses the initialized course player")

	metrics["normal_downhill"] = await downhill_probe(false)
	metrics["surf_downhill"] = await downhill_probe(true)
	print("DOWNHILL ", JSON.stringify(metrics["normal_downhill"]), " surf=", JSON.stringify(metrics["surf_downhill"]))
	check(metrics["normal_downhill"]["distance"] < 0.1, "Normal player stays still on a shallow ramp")
	check(metrics["surf_downhill"]["dx"] < -1.0 and metrics["surf_downhill"]["final_speed"] > 1.0,
		"Surf player accelerates downhill without input")

	await place(steep, true)
	player.velocity = Vector3(0, 0, -20)
	player._hook_slide_timer = 0.5
	var start: Vector3 = player.global_position
	var contacts := 0
	var peak_speed := 0.0
	for _tick in range(90):
		await physics_frame
		peak_speed = maxf(peak_speed, player.velocity.length())
		for index in range(player.get_slide_collision_count()):
			var normal: Vector3 = player.get_slide_collision(index).get_normal()
			if normal.y > 0.4 and normal.y < 0.7:
				contacts += 1
				break
	metrics["steep_bank"] = {"dz": player.global_position.z - start.z, "dx": player.global_position.x - start.x,
		"forward_speed": -player.velocity.z, "contacts": contacts, "peak_speed": peak_speed, "slide_timer": player._hook_slide_timer}
	print("STEEP_BANK ", JSON.stringify(metrics["steep_bank"]))
	check(contacts >= 45 and player.global_position.z - start.z < -20.0 and -player.velocity.z > 15.0,
		"A real 55 degree bank sustains forward momentum after hook slide grace")
	check(player._hook_slide_timer <= 0.0 and peak_speed <= 32.01, "Bank glide stays capped after hook slide expires")

	await place(flat, true)
	player.global_position.y += 3.0
	player.velocity = Vector3(0, 0, -20)
	await frames(120)
	var surf_flat_speed: float = -player.velocity.z
	var surf_landed: bool = player.is_on_floor()
	await place(flat, false)
	player.global_position.y += 3.0
	player.velocity = Vector3(0, 0, -20)
	Input.action_press("move_forwards")
	var normal_landed := false
	var landing_speed := 0.0
	var previous_floor_speed := 0.0
	var floor_ticks := 0
	var maximum_tick_drop := 0.0
	var smooth_decay := true
	var normal_after_two_seconds := 0.0
	for tick in range(240):
		await physics_frame
		var speed: float = -player.velocity.z
		if tick == 119:
			normal_after_two_seconds = speed
		if player.is_on_floor():
			if not normal_landed:
				normal_landed = true
				landing_speed = speed
				previous_floor_speed = speed
			else:
				var drop := previous_floor_speed - speed
				maximum_tick_drop = maxf(maximum_tick_drop, drop)
				# Earned speed carries into landing and declines across successive
				# body steps, rather than being replaced by walking speed at once.
				smooth_decay = smooth_decay and drop >= -0.02 and drop < 0.5
				previous_floor_speed = speed
				floor_ticks += 1
	var normal_flat_speed: float = -player.velocity.z
	release_inputs()
	metrics["flat_momentum"] = {"surf_speed": surf_flat_speed, "normal_landing_speed":landing_speed,
		"normal_speed_after_2s":normal_after_two_seconds, "normal_speed_after_4s":normal_flat_speed,
		"normal_floor_ticks":floor_ticks, "maximum_floor_tick_drop":maximum_tick_drop,
		"surf_landed": surf_landed, "normal_landed": normal_landed and player.is_on_floor()}
	print("FLAT_MOMENTUM ", JSON.stringify(metrics["flat_momentum"]))
	check(surf_landed and player.is_on_floor() and surf_flat_speed > 17.0 and landing_speed > 16.0
		and floor_ticks > 120 and smooth_decay and maximum_tick_drop > 0.05 and absf(normal_flat_speed - 8.0) < 0.1,
		"Surf landing retains boost; ordinary landing carries speed, decays smoothly and settles to eight")

	await place(flat, true)
	player.velocity = Vector3(0, 0, -20)
	Input.action_press("move_backwards")
	await frames(60)
	var braking_speed: float = -player.velocity.z
	await frames(60)
	var reverse_speed: float = player.velocity.z
	release_inputs()
	metrics["braking"] = {"forward_after_1s": braking_speed, "reverse_after_2s": reverse_speed}
	print("BRAKING ", JSON.stringify(metrics["braking"]))
	check(braking_speed > 0.0 and braking_speed < 10.0 and reverse_speed > 1.0,
		"Existing backward input brakes and reverses surf momentum")

	for probe in [flat, shallow]:
		await place(probe, true)
		check(player.is_on_floor(), probe.name + " supports ordinary ground jump")
		var launch: Vector3 = player.global_position
		player.request_jump()
		await frames(2)
		var detached: bool = not player.is_on_floor()
		await frames(18)
		var lift: float = (player.global_position - launch).dot(probe.global_basis.y)
		metrics[probe.name + "_jump"] = {"detached": detached, "normal_lift": lift}
		check(detached and lift > 0.75, probe.name + " jump detaches from snap and gains height")

	await place(flat, true)
	player.velocity = Vector3(45, -20, 0)
	await frames(2)
	var capped_speed: float = player.velocity.length()
	metrics["speed_cap"] = capped_speed
	check(capped_speed <= 32.01, "Actual physics caps excessive incoming velocity")

	var wall := box("SurfWallProbe", Vector3(1000, 25, -12), Vector3(20, 10, 1))
	await frames(3)
	await place(flat, true)
	player.velocity = Vector3(0, 0, -20)
	player._hook_slide_timer = 0.5
	await frames(90)
	metrics["wall"] = {"z": player.global_position.z, "forward_speed": -player.velocity.z, "on_wall": player.is_on_wall()}
	print("WALL ", JSON.stringify(metrics["wall"]))
	check(player.global_position.z > -11.2 and absf(player.velocity.z) < 0.1,
		"Full-speed surf capsule stops at an upright obstacle")
	await place(flat, true)
	var anchor = load("res://scenes/parkour/grapple_anchor.tscn").instantiate()
	root.add_child(anchor)
	anchor.global_position = Vector3(1000, 24, -20)
	await frames(3)
	check(player.grapple._find_lock_target(player.camera.global_position) == null, "Obstacle blocks actual grapple acquisition")
	# Deliberate direct launch checks the flight sweep independently of acquisition.
	player.start_grapple(anchor)
	await frames(90)
	metrics["blocked_hook"] = {"z": player.global_position.z, "hooking": player.is_hooking}
	check(player.global_position.z > -11.3 and not player.is_hooking,
		"Hook flight also stops at the obstacle and releases after blocked timeout")
	check(course.clock.state == 0, "Isolated probes never start or save a course run")
	release_inputs()
	DirAccess.remove_absolute("user://surf_movement_validation.cfg")
	print("SURF_MOVEMENT_RESULT ", JSON.stringify({"metrics": metrics, "failures": failures}))
	# Free scene-owned tweens/capsules before shutting down the SceneTree.
	player.gameplay_active = false
	load("res://tests/audio_test_cleanup.gd").stop_voices(self)
	root.get_node("SoundManager").music_player.stop()
	course.queue_free()
	for body in [flat, shallow, steep, wall, anchor]:
		body.queue_free()
	await frames(2)
	load("res://tests/audio_test_cleanup.gd").drain_mixer()
	quit(0 if failures.is_empty() else 1)
