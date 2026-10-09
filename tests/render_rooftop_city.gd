extends SceneTree
## Render actual Compatibility city views, record desktop GPU counters, isolate PBs.
## Godot --path . --script tests/render_rooftop_city.gd --resolution 1280x720
const Settings = preload("res://scenes/parkour/presentation_settings.gd")
const VIEWS := [
	{"name":"01_rooftop_start", "position":Vector3(0,14.6,10), "target":Vector3(0,16,-37)},
	{"name":"02_city_canyon", "position":Vector3(-27,31,15), "target":Vector3(4,15,-94)},
	{"name":"03_crane_transfer", "position":Vector3(-4,18,-82), "target":Vector3(0,19,-119)},
	{"name":"04_clockcourt", "position":Vector3(22,29,-158), "target":Vector3(-4,28,-217)},
	{"name":"05_last_light", "position":Vector3(0,30,-372), "target":Vector3(0,48,-451)},
]
var course
var camera: Camera3D
var initial_strength := 1.0

func _initialize() -> void:
	call_deferred("render_views")

func render_views() -> void:
	initial_strength = Settings.effects_strength
	Settings.effects_strength = 0.0
	root.size = Vector2i(1280,720)
	course = load("res://levels/parkour/rooftop_trial.tscn").instantiate()
	course.clock.save_path = "user://city_render_%d.cfg" % OS.get_process_id()
	root.add_child(course)
	current_scene = course
	await physics_frame
	course.set_physics_process(false)
	course.player.set_physics_process(false)
	for audio in root.get_node("SoundManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
	course.player.hud.hide()
	for child in course.get_children():
		if child is CanvasLayer:
			child.hide()
	camera = Camera3D.new()
	camera.fov = 75
	camera.far = 650
	course.add_child(camera)
	camera.make_current()
	if RenderingServer.has_method("viewport_set_measure_render_time"):
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	DirAccess.make_dir_recursive_absolute("res://build/city_previews")
	for view in VIEWS:
		camera.global_position = view.position
		camera.look_at(view.target)
		# Let startup/import and the prior camera's work leave the FPS sample.
		for i in range(90):
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://build/city_previews/%s.png" % view.name
		var result := root.get_texture().get_image().save_png(path)
		var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) if RenderingServer.has_method("viewport_get_measured_render_time_cpu") else -1.0
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()) if RenderingServer.has_method("viewport_get_measured_render_time_gpu") else -1.0
		print("CITY_RENDER ", JSON.stringify({"view":view.name,"save_error":result,"path":ProjectSettings.globalize_path(path),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"fps":Performance.get_monitor(Performance.TIME_FPS),"render_cpu_ms":cpu_ms,"render_gpu_ms":gpu_ms}))
	Settings.effects_strength = initial_strength
	root.get_node("GameManager").player = null
	for audio in root.get_node("SoundManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	course.player.parkour_juice.wind_player.stop()
	course.player.parkour_juice.wind_player.stream = null
	course.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	OS.delay_msec(150)
	quit()
