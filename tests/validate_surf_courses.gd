extends SceneTree
## Input-driven course checks. Test saves never write the player's PB file.
const ROUTES := [
	{"path": "res://levels/parkour/riptide.tscn", "points": [Vector3(0,18,-5),Vector3(0,5,-70),Vector3(0,5,-90),Vector3(0,-5,-170),Vector3(0,-5,-190),Vector3(30,-13,-260),Vector3(30,-13,-280),Vector3(36,-15,-310),Vector3(46.9029,-17,-339.0194),Vector3(48.3029,-17.4667,-346.0194),Vector3(45,-18,-355),Vector3(45,-18,-365),Vector3(45,-18,-425)]},
	{"path": "res://levels/parkour/switchyard.tscn", "points": [Vector3(-6,0,-16),Vector3(-6,0,-28),Vector3(0,0,-35),Vector3(6,0,-40),Vector3(6,0,-52),Vector3(0,0,-58),Vector3(-6,0,-62),Vector3(-6,0,-75),Vector3(0,0,-86),Vector3(-8,0,-93),Vector3(-8,0,-106),Vector3(8,0,-113),Vector3(8,0,-126),Vector3(-8,0,-133),Vector3(-8,0,-146),Vector3(0,0,-162),Vector3(-6.5,0,-171),Vector3(-6.5,0,-238),Vector3(0,0,-249),Vector3(0,0,-253),Vector3(0,.5,-256),Vector3(0,1.5,-260),Vector3(0,3.5,-268),Vector3(12,3.5,-271),Vector3(12,3.5,-327),Vector3(0,3.5,-334),Vector3(0,3.5,-342),Vector3(0,3.5,-352),Vector3(42,3.5,-352)]},
]
var course: Node3D
var failures: Array[String] = []
var checks := 0
var save_path := "user://surf_courses_mobile_validation.cfg" if OS.get_cmdline_user_args().has("--mobile-controls") else "user://surf_courses_validation.cfg"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
	print("CHECK ", "PASS " if value else "FAIL ", message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func drive_to(point: Vector3, label: String) -> bool:
	var reached := false
	for tick in range(1800):
		var offset: Vector3 = point - course.player.global_position
		offset.y = 0.0
		if offset.length() < 1.0 or course.clock.state == 2:
			reached = true
			break
		# Feed ordinary movement inputs. Countersteer/brake existing momentum
		# rather than warping or replacing player velocity at every waypoint.
		var desired := offset.normalized() * minf(8.0, offset.length() * 2.0)
		var current := Vector3(course.player.velocity.x, 0, course.player.velocity.z)
		var steering := desired - current
		if steering.length() > 0.3:
			course.player.rotation.y = atan2(-steering.x, -steering.z)
			Input.action_press("move_forwards")
		else:
			Input.action_release("move_forwards")
		await physics_frame
	Input.action_release("move_forwards")
	check(reached, label + " " + str(course.player.global_position))
	return reached

func run() -> void:
	for route in ROUTES:
		if is_instance_valid(course):
			course.queue_free()
			root.get_node("GameManager").player = null
			await frames(3)
		course = load(route.path).instantiate()
		root.add_child(course)
		current_scene = course
		await frames(8)
		root.get_node("SoundManager").music_player.stop()
		root.get_node("SoundManager").music_player.stream = null
		course.clock.save_path = save_path
		course.clock.personal_best = 0.0
		course.clock.best_splits.clear()
		check(course.player.surf_mode and not course.player.floor_stop_on_slope, course.name + " opts into surf before child ready")
		check(course.clock.checkpoint_count == 4 and course._checkpoints.size() == 4, course.name + " four ordered checkpoints")
		for index in range(route.points.size()):
			if not await drive_to(route.points[index], "%s safe leg %d" % [course.name,index]):
				break
		check(course.clock.state == 2 and course.clock.clean_run, course.name + " reaches actual FINISH cleanly")
		check(course.clock.checkpoint_splits.size() == 4, course.name + " physically crosses all four Area3D gates")
		print("COURSE_TIME ", course.name, " ", course.clock.elapsed)
		course.clock.state = 1
		course.clock.checkpoint_splits.clear()
		course.player.gameplay_active = true
		course.player.hud.game_started = true
		for index in range(4):
			course._checkpoint_entered(course.player, index + 1)
			course.respawn_checkpoint()
			await frames(12)
			check(course.player.is_on_floor(), "%s CP%d respawn settles" % [course.name,index+1])
			check(course.player.surf_mode and not course.player.is_hooking and not course.player._capsule_reduced, "%s CP%d resets full surf player" % [course.name,index+1])
		if course.player.hud.mobile_controls.enabled:
			var mobile = course.player.hud.mobile_controls
			mobile.movement = Vector2(1, 1)
			mobile.turn = 1.0
			var touch := InputEventScreenTouch.new()
			touch.index = 77
			touch.pressed = true
			touch.position = mobile.extra_touch_buttons[1].get_global_rect().get_center()
			mobile._input(touch)
			check(mobile.movement == Vector2.ZERO and mobile.turn == 0.0 and not course.clock.clean_run, course.name + " touch checkpoint clears held sticks")
		var best: float = course.clock.personal_best
		course._finish_entered(course.player)
		check(course.clock.state == 2 and course.clock.personal_best == best and not course.clock.clean_run, course.name + " practice keeps previous PB")
		if course.player.hud.mobile_controls.enabled:
			# Retry's overlay touch dispatch is active during a running attempt.
			# The finish panel uses the normal Godot GUI retry button instead.
			course.clock.state = 1
			course.player.gameplay_active = true
			course.player.hud.game_started = true
			course._finish_panel.hide()
			course.player.hud.mobile_controls.set_active(true)
			await frames(2)
			var mobile = course.player.hud.mobile_controls
			var touch := InputEventScreenTouch.new()
			touch.index = 78
			touch.pressed = true
			touch.position = mobile.extra_touch_buttons[0].get_global_rect().get_center()
			mobile._input(touch)
		else:
			course.restart()
		await frames(20)
		course = current_scene
		root.get_node("SoundManager").music_player.stop()
		root.get_node("SoundManager").music_player.stream = null
		check(course.clock.state == 0 and course.clock.checkpoint_splits.is_empty() and course.clock.clean_run, course.name + " retry recreates READY")
	DirAccess.remove_absolute(save_path)
	root.get_node("SoundManager").music_player.stop()
	root.get_node("SoundManager").music_player.stream = null
	for audio in root.get_node("SoundManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	course.queue_free()
	await frames(3)
	OS.delay_msec(50)
	print("VALIDATION_RESULT ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
