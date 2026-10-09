extends SceneTree
## Actual acquisition + flight through the offset-window anchor chain.
## Only the initial ground approach is seeded; subsequent links keep momentum.

var course
var player
var failures: Array[String] = []
var links: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for _tick in range(count):
		await physics_frame

func check(condition: bool, message: String) -> void:
	print("CHECK ", "PASS " if condition else "FAIL ", message)
	if not condition:
		failures.append(message)

func aim_at(anchor: Node3D) -> void:
	var offset: Vector3 = anchor.global_position - player.camera.global_position
	player.rotation.y = atan2(-offset.x, -offset.z)
	player.camera.rotation.x = 0.0

func grapple(anchor: Node3D) -> bool:
	aim_at(anchor)
	var lock = player.grapple._find_lock_target(player.camera.global_position)
	check(lock == anchor, anchor.name + " acquires through actual angular/range/LOS checks")
	if lock != anchor:
		links.append({"anchor": anchor.name, "lock": str(lock), "position": str(player.global_position)})
		return false
	var previous_pulse = anchor._pulse
	var launch: Vector3 = player.global_position
	player.request_hook()
	check(player.is_hooking, anchor.name + " launches via ordinary grapple request")
	var contacts: Array[Dictionary] = []
	var tick_count := 0
	while player.is_hooking and tick_count < 180:
		aim_at(anchor)
		await physics_frame
		tick_count += 1
		for index in range(player.get_slide_collision_count()):
			var collision: KinematicCollision3D = player.get_slide_collision(index)
			var collider = collision.get_collider()
			contacts.append({"tick": tick_count, "body": str(collider.name) if collider else "unknown",
				"normal": str(collision.get_normal()), "position": str(player.global_position)})
	var arrived: bool = anchor._pulse != previous_pulse
	var entry := {"anchor": anchor.name, "arrived": arrived, "ticks": tick_count, "start": str(launch),
		"end": str(player.global_position), "velocity": str(player.velocity), "blocked_time": player._hook_blocked_time,
		"contacts": contacts}
	links.append(entry)
	print("GRAPPLE_LINK ", JSON.stringify(entry))
	check(arrived, anchor.name + " reaches arrival without a blocked-flight timeout")
	return arrived

func run() -> void:
	course = load("res://levels/parkour/switchyard.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	await frames(5)
	player = course.player
	course.set_physics_process(false)
	course.clock.save_path = "user://switchyard_grapple_validation.cfg"
	root.get_node("SoundManager").music_player.stop()
	root.get_node("SoundManager").music_player.stream = null
	# Optional diagnostic adjustment acts only on this in-memory test instance.
	var lowering := 0.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lower-anchors="):
			lowering = argument.trim_prefix("--lower-anchors=").to_float()
	var names := ["Window01Anchor", "WindowTransfer01", "Window02Anchor", "WindowTransfer02", "Window03Anchor"]
	for name in names:
		course.get_node(name).position.y -= lowering
	player.global_position = Vector3(-6, 0.55, -10)
	player.velocity = Vector3.ZERO
	player._end_hook(true)
	await frames(10)
	check(player.is_on_floor(), "Initial approach begins on the real runway")
	for name in names:
		if not await grapple(course.get_node(name)):
			break
	check(links.size() == names.size() and failures.is_empty(), "Complete five-anchor window chain preserves live exit momentum")
	print("SWITCHYARD_GRAPPLE_RESULT ", JSON.stringify({"lowering": lowering, "links": links, "failures": failures}))
	DirAccess.remove_absolute("user://switchyard_grapple_validation.cfg")
	for child in root.get_node("SoundManager").get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	course.queue_free()
	await frames(2)
	# The fixed-fps chain finishes faster than the audio mixer. Let its stop
	# queue release the MP3/WAV playback references before engine shutdown.
	OS.delay_msec(50)
	quit(0 if failures.is_empty() else 1)
