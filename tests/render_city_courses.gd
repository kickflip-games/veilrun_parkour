extends SceneTree
## Actual Compatibility render views; isolated PB paths and in-memory FX setting.
const Settings = preload("res://scenes/parkour/presentation_settings.gd")
const VIEWS := [
	{"course":"parkour_trial", "name":"switchback_start", "position":Vector3(0,2.15,6), "target":Vector3(0,5,-42)},
	{"course":"parkour_trial", "name":"switchback_hairpin", "position":Vector3(152,18,-433), "target":Vector3(227,11,-371)},
	{"course":"riptide", "name":"riptide_start", "position":Vector3(0,20.15,12), "target":Vector3(0,7,-80)},
	{"course":"riptide", "name":"riptide_banks", "position":Vector3(0,10,-116), "target":Vector3(0,-2,-175)},
	{"course":"switchyard", "name":"switchyard_start", "position":Vector3(0,2.15,6), "target":Vector3(0,3,-62)},
	{"course":"switchyard", "name":"switchyard_bridges", "position":Vector3(-12,14,-261), "target":Vector3(0,1,-328)},
]

func _initialize() -> void:
	call_deferred("render_views")

func render_views() -> void:
	var strength: float = Settings.effects_strength
	Settings.effects_strength = 0.0
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/city_previews")
	for view in VIEWS:
		var course = load("res://levels/parkour/%s.tscn" % view.course).instantiate()
		var save_path := "user://city_course_render_%d.cfg" % OS.get_process_id()
		course.clock.save_path = save_path
		root.add_child(course)
		current_scene = course
		course.set_physics_process(false)
		course.player.set_physics_process(false)
		course.player.set_process(false)
		course.player.set_process_input(false)
		course.player.set_process_unhandled_input(false)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		course.player.hud.hide()
		for child in course.get_children():
			if child is CanvasLayer:
				child.hide()
		var camera := Camera3D.new()
		camera.fov = 75
		camera.far = 650
		course.add_child(camera)
		camera.global_position = view.position
		camera.look_at(view.target)
		camera.make_current()
		for _tick in range(45):
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://build/city_previews/%s.png" % view.name
		var error := root.get_texture().get_image().save_png(path)
		print("COURSE_CITY_RENDER ", JSON.stringify({"view":view.name,"save_error":error,
			"path":ProjectSettings.globalize_path(path),
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}))
		for audio in root.get_node("SoundManager").get_children():
			if audio is AudioStreamPlayer:
				audio.stop()
				audio.stream = null
		course.player.parkour_juice.wind_player.stop()
		course.player.parkour_juice.wind_player.stream = null
		root.get_node("GameManager").player = null
		course.queue_free()
		current_scene = null
		await process_frame
		await process_frame
		DirAccess.remove_absolute(save_path)
	Settings.effects_strength = strength
	OS.delay_msec(150)
	quit()
