extends SceneTree
## Actual pitch-aware acquisition, target feedback and sound lifecycle.
const Settings = preload("res://scenes/parkour/presentation_settings.gd")
var checks := 0
var failures: Array[String] = []
var player
var anchor
var other
var settings_before := PackedByteArray()
var saved_strength := 1.0
func _initialize() -> void:
	call_deferred("run")
func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
func check(condition: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if condition else "FAIL ", message)
	if not condition:
		failures.append(message)
func settings_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(Settings.SAVE_PATH) if FileAccess.file_exists(Settings.SAVE_PATH) else PackedByteArray()
func sound_count() -> int:
	return root.get_node("SoundManager").get_child_count()
func run() -> void:
	settings_before = settings_bytes()
	saved_strength = Settings.effects_strength
	player = load("res://scenes/player/player.tscn").instantiate()
	player.use_momentum_pull = true
	player.vertical_look_enabled = true
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(1200, 40, 0)
	player.gameplay_active = true
	var sound = root.get_node("SoundManager")
	sound.music_player.stop()
	sound.music_player.stream = null
	Settings.effects_strength = 0.0
	anchor = load("res://scenes/parkour/grapple_anchor.tscn").instantiate()
	other = load("res://scenes/parkour/grapple_anchor.tscn").instantiate()
	root.add_child(anchor)
	root.add_child(other)
	var origin: Vector3 = player.to_global(player._camera_base_pos)
	anchor.global_position = origin + Vector3(0, 1, -1).normalized() * 20.0
	other.global_position = origin + Vector3(12, 0, -15)
	await frames(3)
	player.camera.rotation.x = 0.0
	check(player.grapple.get_lock_target() == null, "An overhead anchor needs an upward look within the base screen bounds")
	player.grapple._refresh_anchor_feedback(null)
	check(anchor.feedback_state == 1 and other.feedback_state == 1, "Visible rings in reach brighten even before they are selected")
	player.camera.rotation.x = deg_to_rad(45.0)
	check(player.grapple.get_lock_target() == anchor, "Manual upward pitch acquires the actual overhead anchor collider")
	player.camera.rotation.z = deg_to_rad(7.0)
	player.camera.position.y -= 0.12
	player.camera.fov += 14.0
	check(player.grapple.get_lock_target() == anchor, "Camera roll, dip and speed FOV preserve the pitched acquisition")
	player.grapple._refresh_anchor_feedback(anchor)
	check(anchor.feedback_state == 2 and other.feedback_state == 1, "Target confirmation is distinct and isolated to the selected fixture")
	check(anchor._ring_material != other._ring_material and anchor._core_material != other._core_material, "Each fixture owns its highlight materials")
	player.request_hook()
	player.grapple._refresh_anchor_feedback(anchor)
	check(player.is_hooking and anchor.feedback_state == 3, "Pull activation marks the held fixture")
	player.request_hook()
	check(not player.is_hooking and player.velocity.is_zero_approx(), "Release from rest does not invent a release boost")
	anchor.global_position = origin + Vector3(0, 1, -1).normalized() * 30.0
	await frames(2)
	player.grapple._refresh_anchor_feedback(null)
	check(anchor.feedback_state == 0, "Out of reach fixtures return to the dormant state")
	player.camera.rotation.x = 0.0
	player._recent_anchor = null
	player.grapple.aim_assist_target = null
	anchor.global_position = origin + Vector3(tan(deg_to_rad(2.0)), 0, -1).normalized() * 20.0
	other.global_position = origin + Vector3(0, tan(deg_to_rad(25.0)), -1).normalized() * 20.0
	await frames(2)
	player.grapple.aim_assist_target = null
	check(player.grapple.get_lock_target() == anchor, "Pitched aiming favors the ring closest to the crosshair across both axes")
	player.vertical_look_enabled = false
	player.grapple.aim_assist_target = null
	check(player.grapple.get_lock_target() == other, "Comparison courses preserve their original horizontal target ordering")
	player.vertical_look_enabled = true
	var mobile = player.hud.mobile_controls
	mobile._look_finger = 3
	mobile._update_stick(3, mobile._look_center + Vector2(0, -mobile._radius))
	check(mobile.pitch < -0.9 and is_zero_approx(mobile.turn) and mobile.look_caption == "LOOK", "The look stick supports independent upward pitch")
	mobile._release_finger(3)
	check(is_zero_approx(mobile.pitch) and is_zero_approx(mobile.turn), "Releasing the look stick clears both axes")
	mobile.pitch = 1.0
	mobile.reset_touches()
	check(is_zero_approx(mobile.pitch), "Recovery clears held pitch")
	var juice = player.parkour_juice
	player.velocity = Vector3(0, 32, 0)
	for i in range(120):
		juice.update_effects(1.0 / 60.0)
	check(not juice.wind_player.playing and is_equal_approx(player.camera.fov, player._base_fov), "Zero effects disables wind and speed camera cues during vertical travel")
	var children_before := sound_count()
	sound.play_pull_cue(sound.SFX_PULL_ON)
	check(sound_count() == children_before, "Zero effects suppresses new pull sounds")
	Settings.effects_strength = 1.0
	for i in range(120):
		juice.update_effects(1.0 / 60.0)
	check(juice.wind_player.playing and juice.wind_player.volume_db > -27.0 and player.camera.fov > player._base_fov + 10.0, "Vertical pull speed drives bounded wind and FOV feedback")
	var clock_before: float = juice.motion_time
	paused = true
	await frames(3)
	juice.update_effects(0.5)
	check(juice.motion_time == clock_before and juice.wind_player.stream_paused, "Pause freezes presentation time and pauses wind playback")
	paused = false
	juice.reset_effects()
	check(not juice.wind_player.playing and is_equal_approx(player.camera.fov, player._base_fov), "Recovery immediately stops wind and restores the neutral camera")
	sound.play_pull_cue(sound.SFX_PULL_ON)
	check(sound_count() == children_before + 1, "Activation creates one short owned sound")
	OS.delay_msec(300) # Dummy audio uses wall time while --fixed-fps accelerates the scene.
	for i in range(4):
		await process_frame
	check(sound_count() == children_before, "A completed pull sound removes its playback node")
	check(settings_bytes() == settings_before, "Feedback validation leaves real saved preferences byte identical")
	Settings.effects_strength = saved_strength
	juice.wind_player.stop()
	juice.wind_player.stream = null
	for child in sound.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	root.get_node("GameManager").player = null
	player.queue_free()
	anchor.queue_free()
	other.queue_free()
	await frames(3)
	OS.delay_msec(150)
	print("PULL_FEEDBACK_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
