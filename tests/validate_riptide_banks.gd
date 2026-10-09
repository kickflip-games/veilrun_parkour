extends SceneTree
## Real geometry bank glides. Feature probes seed an incoming boost, then let
## ordinary controller collision, gravity and momentum carry the capsule.
const PROBES := [
	["V right", Vector3(9,6.74477,-125), 0.0],
	["V left", Vector3(-9,6.74477,-125), 0.0],
	["Transfer", Vector3(21.3973,-2.38023,-217.07973), -0.404892],
	["Bridge", Vector3(40.82523,-7.54690,-288.23495), -0.197396],
]
var course
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
	print("CHECK ", "PASS " if value else "FAIL ", label)
func run() -> void:
	course = load("res://levels/parkour/riptide.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	await frames(8)
	course.set_physics_process(false)
	course.clock.save_path = "user://riptide_banks_validation.cfg"
	root.get_node("SoundManager").music_player.stop()
	root.get_node("SoundManager").music_player.stream = null
	var player = course.player
	for probe in PROBES:
		player._end_hook(true)
		player.global_position = probe[1]
		player.rotation = Vector3(0, probe[2], 0)
		player.velocity = Vector3.ZERO
		await frames(3)
		var forward: Vector3 = -player.global_basis.z
		player.velocity = forward * 20.0
		player._hook_slide_timer = 0.5
		var start: Vector3 = player.global_position
		var contacts := 0
		var peak := 0.0
		for tick in range(90):
			await physics_frame
			peak = maxf(peak, player.velocity.length())
			for index in range(player.get_slide_collision_count()):
				var normal: Vector3 = player.get_slide_collision(index).get_normal()
				if normal.y > 0.4 and normal.y < 0.7:
					contacts += 1
					break
		var advance: float = (player.global_position - start).dot(forward)
		var speed: float = player.velocity.dot(forward)
		print("BANK ", probe[0], " contacts=", contacts, " distance=", advance, " speed=", speed, " peak=", peak, " end=", player.global_position)
		check(contacts >= 10 and advance > 20.0 and speed > 12.0, str(probe[0]) + " glides through real inclined segments")
		check(peak <= 32.01 and player.global_position.y > course.fall_height, str(probe[0]) + " stays capped and above the fall zone")
	check(course.clock.state == 0, "Bank probes never start or save a course run")
	DirAccess.remove_absolute(course.clock.save_path)
	player.gameplay_active = false
	load("res://tests/audio_test_cleanup.gd").stop_voices(self)
	course.queue_free()
	await frames(3)
	load("res://tests/audio_test_cleanup.gd").drain_mixer()
	print("RIPTIDE_BANK_RESULT ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
