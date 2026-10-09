extends SceneTree

var course: Node3D
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
	print("CHECK ", "PASS " if value else "FAIL ", message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func drive_to(point: Vector3, label: String) -> void:
	Input.action_press("move_forwards")
	var reached := false
	for tick in range(1800):
		var offset: Vector3 = point - course.player.global_position
		offset.y = 0.0
		if offset.length() < 1.2 or course.clock.state == 2:
			reached = true
			break
		course.player.rotation.y = atan2(-offset.x, -offset.z)
		await physics_frame
	Input.action_release("move_forwards")
	check(reached, label + " walking reachability " + str(course.player.global_position))

func run() -> void:
	course = load("res://levels/parkour/parkour_trial.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	await frames(5)
	# There is no audio timing dependency in the parkour controller. Release
	# music before accelerated physics so its mixer does not race test teardown.
	root.get_node("SoundManager").music_player.stop()
	root.get_node("SoundManager").music_player.stream = null
	if course._checkpoints.size() != 6:
		push_error("Course did not initialize six checkpoints")
		quit(1)
		return
	course.clock.save_path = "user://long_course_validation.cfg"
	course.clock.personal_best = 0.0
	course.clock.best_splits.clear()
	print("BOOT ", course.player.global_position, " course=", course.clock.course_id)
	check(course.player.gameplay_active, "Player active in parkour")
	check(course.clock.checkpoint_count == 6, "Six required gates")
	course._start_entered(course.player)
	course._finish_entered(course.player)
	check(course.clock.state == 1, "Cannot skip ordered checkpoints to finish")
	course.player.global_position = Vector3(40,3.55,-223)
	course.player.velocity = Vector3.ZERO
	await frames(5)
	var points := [Vector3(40,3,-340),Vector3(40,3,-365),Vector3(48,4,-380),Vector3(68,6,-397),Vector3(93,9,-410),Vector3(125,11,-405),Vector3(150,11,-405),Vector3(174,11,-416),Vector3(190,11,-432),Vector3(200,11,-446),Vector3(218,11,-450),Vector3(232,11,-434),Vector3(234,11,-416),Vector3(234,11,-355),Vector3(225,11,-330),Vector3(225,11,-310),Vector3(242,11,-303),Vector3(269,10,-310),Vector3(292,7,-335),Vector3(300,5,-360),Vector3(300,3,-386),Vector3(300,3,-414),Vector3(318,3,-414),Vector3(318,-2,-435),Vector3(318,-2,-508),Vector3(300,3,-530),Vector3(300,3,-595)]
	for i in range(points.size()):
		await drive_to(points[i], "Main/safe leg %d" % i)
		if not failures.is_empty():
			break
	check(course.clock.state == 2 and course.clock.clean_run, "Actual walking route crosses all ordered gates and FINISH cleanly")
	check(course.clock.checkpoint_splits.size() == 6, "Actual route crossed six Area3D checkpoint triggers")
	course.clock.state = 1
	course.clock.checkpoint_splits.clear()
	course.clock.personal_best = 0.0
	course.player.gameplay_active = true
	course.player.hud.game_started = true
	for index in range(6):
		course._checkpoint_entered(course.player, index + 1)
		course.respawn_checkpoint()
		await frames(10)
		check(course.player.is_on_floor(), "CP%d respawn settles on collision floor" % (index + 1))
		check(course.player._body_collision.shape == course.player._full_capsule and not course.player.is_hooking, "CP%d restores player capsule and hook state" % (index + 1))
		check(course.clock.checkpoint_splits.size() == index + 1, "CP%d keeps completed gates on respawn" % (index + 1))
	course._finish_entered(course.player)
	check(course.clock.state == 2 and course.clock.personal_best == 0.0, "Practice finishes without saving PB")
	# Start a fresh partial run at CP5 and cross the entire spring chain using
	# ordinary held movement, relying on Area3D launches and physical landings.
	course.clock.state = 1
	course.clock.checkpoint_splits.clear()
	course.clock.clean_run = true
	course.player.gameplay_active = true
	course.player.hud.game_started = true
	for i in range(5):
		course._checkpoint_entered(course.player, i + 1)
	course.player.global_position = Vector3(300,3.55,-420)
	course.player.velocity = Vector3.ZERO
	course.player.rotation.y = 0.0
	await frames(5)
	Input.action_press("move_forwards")
	var landings := []
	for tick in range(1800):
		if tick % 30 == 0:
			landings.append({"z":course.player.global_position.z,"y":course.player.global_position.y})
		if course.clock.state == 2:
			break
		await physics_frame
	Input.action_release("move_forwards")
	for name in ["ChainSpringA", "ChainSpringB", "ChainSpringC"]:
		check(course.get_node("LongCourse/" + name).activations > 0, name + " activates from physical entry")
	check(course.clock.state == 2 and course.clock.clean_run, "Three spring chain lands and crosses CP6/FINISH without a fall")
	print("SPRING_ARC ", JSON.stringify(landings))
	# Exercise the narrow beam shortcut with ordinary movement.
	course.clock.state = 1
	course.clock.checkpoint_splits.clear()
	course.player.gameplay_active = true
	course.player.hud.game_started = true
	for i in range(3):
		course._checkpoint_entered(course.player, i + 1)
	course.player.global_position = Vector3(128,11.55,-405)
	course.player.velocity = Vector3.ZERO
	await frames(5)
	await drive_to(Vector3(151,11,-405), "Beam entry")
	await drive_to(Vector3(210,11,-328), "Beam cut")
	await drive_to(Vector3(225,11,-310), "Beam exit")
	check(course.clock.checkpoint_splits.size() == 4, "Beam shortcut crosses CP4 in order")
	for anchor_name in ["DriveAnchor1", "RiseAnchor03", "SkyAnchor04", "BeamCutAnchorC", "DownhillAnchor04", "ChainAnchorA", "FinishAnchor1"]:
		var anchor: Node3D = course.get_node("LongCourse/" + anchor_name)
		course.player._end_hook(true)
		course.player._recent_anchor = null
		course.player._anchor_cooldown = 0.0
		course.player.global_position = anchor.global_position + Vector3(0,-4.45,20)
		course.player.rotation.y = 0.0
		course.player.camera.rotation = Vector3.ZERO
		await frames(2)
		var locked = course.player.grapple._find_lock_target(course.player.camera.global_position)
		check(locked == anchor, anchor_name + " acquired through range/angular/LOS checks")
		course.player.request_hook()
		check(course.player.is_hooking, anchor_name + " actual grapple starts")
		await frames(40)
		check(not course.player.is_hooking and anchor.is_grapple_available(), anchor_name + " arrives and remains reusable")
	course.clock.state = 1
	course.clock.checkpoint_splits.clear()
	course.player.gameplay_active = true
	course.player.hud.game_started = true
	course._checkpoint_entered(course.player, 1)
	course._checkpoint_entered(course.player, 2)
	course.player.global_position.y = -13
	await frames(3)
	check(not course.clock.clean_run and course.player.global_position.y > 0.0 and course.clock.checkpoint_splits.size() == 2, "Fall restores last checkpoint and marks practice")
	var before_pause: float = course.clock.elapsed
	paused = true
	await frames(10)
	check(course.clock.elapsed == before_pause, "Pause excludes physics time")
	paused = false
	await frames(2)
	if course.player.hud.mobile_controls.enabled:
		var mobile = course.player.hud.mobile_controls
		mobile.movement = Vector2(1,1)
		mobile.turn = 1.0
		var touch := InputEventScreenTouch.new()
		touch.index = 77
		touch.pressed = true
		touch.position = mobile.extra_touch_buttons[1].get_global_rect().get_center()
		mobile._input(touch)
		check(mobile.movement == Vector2.ZERO and mobile.turn == 0.0 and not course.clock.clean_run, "Touch CHECKPOINT works and clears held sticks")
		print("TOUCH_BUTTONS ", mobile.extra_touch_buttons[0].get_global_rect(), " ", mobile.extra_touch_buttons[1].get_global_rect())
		var retry_touch := InputEventScreenTouch.new()
		retry_touch.index = 78
		retry_touch.pressed = true
		retry_touch.position = mobile.extra_touch_buttons[0].get_global_rect().get_center()
		mobile._input(retry_touch)
	else:
		course.restart()
	await frames(20)
	check(current_scene.clock.state == 0 and current_scene.clock.checkpoint_splits.is_empty() and current_scene.clock.clean_run, "Full retry recreates READY with no checkpoints")
	print("VALIDATION_RESULT ", JSON.stringify({"failures": failures}))
	DirAccess.remove_absolute("user://long_course_validation.cfg")
	for child in root.get_node("SoundManager").get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	root.get_node("GameManager").player = null
	current_scene.queue_free()
	await frames(2)
	OS.delay_msec(200)
	quit(0 if failures.is_empty() else 1)
