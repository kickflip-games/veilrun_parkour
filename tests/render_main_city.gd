extends SceneTree
## Fresh Compatibility snapshots. Static desktop views do not establish play FPS.
const Settings = preload("res://scenes/parkour/presentation_settings.gd")
const VIEWS := [
	{"name":"01_eaves", "position":Vector3(0,29,12), "target":Vector3(-4,26,-75)},
	{"name":"02_chimneys", "position":Vector3(0,34,-278), "target":Vector3(0,33,-390)},
	{"name":"03_blackglass", "position":Vector3(0,39,-500), "target":Vector3(0,13,-690)},
	{"name":"04_underway", "position":Vector3(0,14,-795), "target":Vector3(0,12,-935)},
	{"name":"05_bell_turn", "position":Vector3(0,20,-1070), "target":Vector3(48,27,-1125)},
	{"name":"06_high_ward", "position":Vector3(130,35,-1130), "target":Vector3(199,85,-1224)},
	{"name":"07_final_send", "position":Vector3(130,77,-1340), "target":Vector3(130,53,-1658)},
]

func _initialize() -> void:
	call_deferred("render_views")

func render_views() -> void:
	var original_strength: float = Settings.effects_strength
	var pull_feedback := "--pull-feedback" in OS.get_cmdline_user_args()
	var racing_slice := "--bellmaker-slice" in OS.get_cmdline_user_args() or pull_feedback
	Settings.effects_strength = 0.65 if racing_slice else 0.0
	root.size = Vector2i(1280, 720)
	var course = load("res://levels/parkour/MainCityRun.tscn").instantiate()
	course.clock.save_path = "user://main_city_render_%d.cfg" % OS.get_process_id()
	root.add_child(course)
	current_scene = course
	await physics_frame
	course.set_physics_process(false)
	course.player.set_physics_process(false)
	load("res://tests/audio_test_cleanup.gd").stop_voices(self)
	DirAccess.make_dir_recursive_absolute("res://build/main_city_previews")
	for i in range(15 if racing_slice else 150):
		await process_frame
	if racing_slice:
		RenderingServer.force_draw(false)
	else:
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/main_city_previews/00_ready_hud.png")
	course.player.hud.hide()
	for child in course.get_children():
		if child is CanvasLayer:
			child.hide()
	var camera := Camera3D.new()
	camera.fov = 75
	camera.far = 700
	course.add_child(camera)
	camera.make_current()
	var views: Array = VIEWS.duplicate()
	if racing_slice:
		views = [
			{"name":"bellmaker_split", "position":Vector3(0,15,-1015), "target":Vector3(30,15,-1035)},
			{"name":"bellmaker_gallery", "position":Vector3(40,26,-1010), "target":Vector3(85,23,-1041)},
			{"name":"bellmaker_gap", "position":Vector3(29,26,-1039), "target":Vector3(62,18,-1033)},
			{"name":"bellmaker_alley", "position":Vector3(28,8,-1035), "target":Vector3(78,8,-1035)},
			{"name":"bellmaker_apex", "position":Vector3(20,22,-1130), "target":Vector3(70,22,-1125)},
			{"name":"bellmaker_overview", "position":Vector3(45,80,-990), "target":Vector3(48,13,-1060)},
		]
	if "--adjacent-roofs" in OS.get_cmdline_user_args():
		views.clear()
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/main_city/route_manifest.json"))
		for roof in manifest.get("playable_adjacent_roofs", []):
			var center := Vector3(roof.center[0], roof.center[1], roof.center[2])
			var position := center + Vector3(0, float(roof.rise) + 1.7, 0)
			var target := Vector3(roof.rejoin[0], position.y, roof.rejoin[2])
			views.append({"name":"adjacent_%02d" % int(roof.sector_index), "position":position, "target":target})
	if pull_feedback:
		views.clear()
	for view in views:
		camera.global_position = view.position
		camera.look_at(view.target)
		for i in range(20 if racing_slice else 120):
			await process_frame
		if racing_slice:
			# Explicit draws also capture this bounded static audit if the
			# native preview window loses foreground focus during the run.
			RenderingServer.force_draw(false)
		else:
			await RenderingServer.frame_post_draw
		var path: String = "res://build/main_city_previews/%s.png" % view.name
		var error := root.get_texture().get_image().save_png(path)
		print("MAIN_CITY_RENDER ", JSON.stringify({"view":view.name,"save_error":error,
			"path":ProjectSettings.globalize_path(path),
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"fps":Performance.get_monitor(Performance.TIME_FPS)}))
	if pull_feedback:
		# A frozen presentation seed verifies the real level-camera acquisition,
		# world highlight and HUD glyph. It is separate from motion evidence.
		var player = course.player
		var anchor = course.get_node("CitySections/Sector05/ArchitecturalAnchors/BellMount00")
		player.global_position = Vector3(0,12.6,-1044)
		var offset: Vector3 = anchor.global_position-player.global_position
		player.rotation.y = atan2(-offset.x,-offset.z)
		player.camera.rotation.x = 0.0
		player.camera.make_current()
		player.gameplay_active = true
		player.hud.game_started = true
		player.hud.show()
		for _i in range(20):
			await process_frame
		RenderingServer.force_draw(false)
		var path := "res://build/main_city_previews/bellmaker_pull_feedback.png"
		var error := root.get_texture().get_image().save_png(path)
		print("MAIN_CITY_PULL_RENDER ",JSON.stringify({"save_error":error,"path":ProjectSettings.globalize_path(path),"target":str(player.grapple.aim_assist_target.name) if is_instance_valid(player.grapple.aim_assist_target) else "","indicator_visible":player.hud._aim_assist_indicator.visible,"manual_pitch":player.camera.rotation.x}))
	Settings.effects_strength = original_strength
	root.get_node("GameManager").player = null
	load("res://tests/audio_test_cleanup.gd").stop_voices(self)
	course.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	load("res://tests/audio_test_cleanup.gd").drain_mixer()
	quit()
