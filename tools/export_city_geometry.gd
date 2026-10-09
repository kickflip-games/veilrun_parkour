extends SceneTree
## Offline art input from the actual instanced course transforms; no scene writes.
const COURSES := ["parkour_trial", "riptide", "switchyard"]

func _initialize() -> void:
	call_deferred("export_geometry")

func world_transform(node: Node3D) -> Transform3D:
	var pose := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		pose = parent.transform * pose
		parent = parent.get_parent()
	return pose

func values(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func export_geometry() -> void:
	var result := {}
	for name in COURSES:
		var course = load("res://levels/parkour/%s.tscn" % name).instantiate()
		course.clock.save_path = "user://city_geometry_%d.cfg" % OS.get_process_id()
		course.set_physics_process(false)
		course.get_node("Player").set_physics_process(false)
		course.get_node("Player").set_process(false)
		root.add_child(course)
		var solids: Array = []
		for node in course.find_children("*", "CSGBox3D", true, false):
			if not node.use_collision:
				continue
			var pose := world_transform(node)
			var bounds := AABB()
			var first := true
			for x in [-0.5, 0.5]:
				for y in [-0.5, 0.5]:
					for z in [-0.5, 0.5]:
						var point: Vector3 = pose * (node.size * Vector3(x, y, z))
						bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
						first = false
			var corners: Array = []
			for x in [-0.5, 0.5]:
				for z in [-0.5, 0.5]:
					corners.append(values(pose * (node.size * Vector3(x, -0.5, z))))
			solids.append({"name":String(course.get_path_to(node)), "min":values(bounds.position),
				"max":values(bounds.end), "size":values(node.size), "up":values(pose.basis.y), "corners":corners})
		result[name] = {"solids":solids, "fall_height":course.fall_height}
		root.get_node("GameManager").player = null
		course.player.parkour_juice.wind_player.stop()
		course.player.parkour_juice.wind_player.stream = null
		course.queue_free()
		await process_frame
		await process_frame
	DirAccess.make_dir_recursive_absolute("res://build")
	var file := FileAccess.open("res://build/course_city_geometry.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	for audio in root.get_node("SoundManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	await process_frame
	await process_frame
	OS.delay_msec(150)
	print("CITY_GEOMETRY_EXPORTED ", result.keys())
	quit()
