extends SceneTree
## Environment audit uses pre-dressing shape/config signatures. Existing real-body
## route harnesses remain the playability checks; this script does not move routes.
## --capture prints a baseline before scenery edits; never updates it automatically.
const COURSES := [
	"res://levels/parkour/parkour_trial.tscn",
	"res://levels/parkour/riptide.tscn",
	"res://levels/parkour/switchyard.tscn",
	"res://levels/parkour/rooftop_trial.tscn",
]
const EXPECTED := {
	"res://levels/parkour/parkour_trial.tscn": {"sha256":"33abede435175ee6d2848a3e4a4267f0a00fb1755b374263c41fa400a65579df", "record_count":253},
	"res://levels/parkour/riptide.tscn": {"sha256":"7aa72a8e71bab3bd57a0fd5f6ff059491b677acbdb95810d18c3fbbfa6f40859", "record_count":163},
	"res://levels/parkour/switchyard.tscn": {"sha256":"2ec721eadc17ae9ed14586af420648cc748d063355504e1d20cc8be85e6fbbd8", "record_count":158},
	"res://levels/parkour/rooftop_trial.tscn": {"sha256":"858c0379b963d6b2c458c1608113aaf4b592c3e7199afa4c06b97466e80bea27", "record_count":224},
}
const CONTROL_SOURCES := [
	"res://scenes/parkour/air_control.gd", "res://scenes/parkour/anchor_pull.gd",
	"res://scenes/parkour/spring_pad.gd",
	"res://scenes/parkour/trial_clock.gd",
]
const PHYSICS_FUNCTIONS := {
	"res://scenes/player/player.gd": ["get_aim_basis", "start_grapple", "_handle_hook_movement",
		"_on_hook_impact", "_end_hook", "_try_restore_capsule", "_read_move_input",
		"request_jump", "handle_movement", "_apply_gravity", "apply_spring_launch",
		"reset_pull_state", "_release_hook", "_finish_pull_pass"],
	"res://scenes/parkour/grapple_controller.gd": ["can_hook_target", "_target_point", "_find_lock_target"],
}
# Reviewed 2026-10-04: authorized held input, buffered/coyote jump, assisted
# acquisition, independent sector timing and architectural spring presentation,
# including the flush directional metal inlay for contact launchers.
# Force/air/spring body solvers and original course collision remain covered by
# physical regression probes. The four geometry signatures stay unchanged.
const EXPECTED_CONTROLS := "c91e2231f7c66ad52f5774fcfd00ae69b0e4af6a8ff7046bee68971804d01277"
const CONFIG_FIELDS := [
	"course_id", "checkpoint_paths", "finish_path", "fall_height", "grapple_range",
	"acquisition_horizontal_degrees", "acquisition_vertical_degrees",
]
const PLAYER_FIELDS := [
	"parkour_mode", "use_momentum_pull", "vertical_look_enabled", "surf_mode",
	"pull_acceleration", "pull_tangent_retention", "pull_upward_scale",
	"pull_arrival_distance", "pull_max_duration", "pull_air_acceleration",
	"pull_air_turn_speed", "surf_drag", "parkour_air_acceleration",
	"parkour_air_turn_speed", "parkour_air_braking", "parkour_air_drag",
	"parkour_ground_momentum_drag", "parkour_ground_coast_drag",
	"parkour_speed_limit", "hook_blocked_timeout", "anchor_reuse_delay",
	"hook_exit_speed", "hook_exit_vertical_fraction", "hook_capsule_scale",
]
var checks := 0
var failures: Array[String] = []
var captures := {}
var capture_only := false

func _initialize() -> void:
	capture_only = OS.get_cmdline_user_args().has("--capture")
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value: failures.append(message)

func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func bytes_at(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func stable(value: Variant) -> String:
	if value is Vector3:
		return "(%.6f,%.6f,%.6f)" % [value.x, value.y, value.z]
	if value is Transform3D:
		return stable(value.basis.x) + stable(value.basis.y) + stable(value.basis.z) + stable(value.origin)
	if value is float:
		return "%.6f" % value
	return str(value)

func shape_parameters(shape: Shape3D) -> String:
	var parameters: Array[String] = [shape.get_class()]
	for property in shape.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_STORAGE == 0: continue
		var name: String = property.name
		if name in ["resource_local_to_scene", "resource_path", "resource_name", "script"]: continue
		parameters.append(name + "=" + stable(shape.get(name)))
	parameters.sort()
	return "|".join(parameters)

func collision_records(course: Node, node: Node, inherited: Transform3D, records: Array[String]) -> void:
	var transform := inherited
	if node is Node3D: transform *= node.transform
	var path := str(course.get_path_to(node))
	if node is CollisionObject3D:
		var entry := path + "|" + node.get_class() + "|" + stable(transform)
		entry += "|layer=" + str(node.collision_layer) + "|mask=" + str(node.collision_mask)
		if node is Area3D: entry += "|monitor=" + str(node.monitoring) + "|monitorable=" + str(node.monitorable)
		records.append(entry)
	if node is CollisionShape3D:
		records.append(path + "|shape|" + stable(transform) + "|disabled=" + str(node.disabled)
			+ "|" + shape_parameters(node.shape))
	if node is CSGShape3D and node.use_collision:
		var entry := path + "|" + node.get_class() + "|" + stable(transform)
		for property in ["size", "radius", "height", "sides", "operation", "collision_layer", "collision_mask"]:
			if property in node: entry += "|" + property + "=" + stable(node.get(property))
		records.append(entry)
	if node is Marker3D and node.name == "Respawn":
		records.append(path + "|respawn|" + stable(transform))
	if node.scene_file_path in ["res://scenes/parkour/grapple_anchor.tscn", "res://scenes/parkour/spring_pad.tscn"]:
		var entry := path + "|fixture|" + stable(transform)
		for property in ["targetable", "launch_direction", "launch_strength", "lateral_retention", "speed_limit"]:
			if property in node: entry += "|" + property + "=" + stable(node.get(property))
		records.append(entry)
	for child in node.get_children(): collision_records(course, child, transform, records)

func fingerprint(course: Node) -> Dictionary:
	var records: Array[String] = []
	collision_records(course, course, Transform3D.IDENTITY, records)
	for field in CONFIG_FIELDS: records.append("course|" + field + "=" + stable(course.get(field)))
	var player: Node = course.get_node("Player")
	for field in PLAYER_FIELDS: records.append("player|" + field + "=" + stable(player.get(field)))
	records.sort()
	return {"sha256":"\n".join(records).sha256_text(), "record_count":records.size(), "records":records}

func control_fingerprint() -> String:
	var sources: Array[String] = []
	for path in CONTROL_SOURCES:
		sources.append(path + "|" + FileAccess.get_file_as_string(path).sha256_text())
	# A separately authorized click-dispatch fix may change _input and the input
	# prefix of _physics_process. Freeze the body solvers/acquisition themselves.
	for path in PHYSICS_FUNCTIONS:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for method in PHYSICS_FUNCTIONS[path]:
			var body: Array[String] = []
			var collecting := false
			for line in lines:
				if line.begins_with("func "):
					if collecting: break
					collecting = line.begins_with("func " + method + "(")
				if collecting: body.append(line)
			sources.append(path + "|" + method + "|" + "\n".join(body).strip_edges().sha256_text())
	sources.append("gravity|" + stable(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)))
	return "\n".join(sources).sha256_text()

func find_scenery(course: Node) -> Node:
	for child in course.get_children():
		if child.name in ["CityScenery", "CityDistrict"] or child.is_in_group("city_scenery"):
			return child
	return null

func body_visual_corridors(course: Node) -> Array[Dictionary]:
	var corridors: Array[Dictionary] = []
	for deck in course.find_children("*", "CSGBox3D", true, false):
		if not deck.use_collision or deck.size.y > 1.05 or deck.global_basis.y.y < 0.05: continue
		var first := true
		var bounds := AABB()
		for x in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				var top: Vector3 = deck.global_transform * (deck.size * Vector3(x, 0.5, z))
				bounds = AABB(top, Vector3.ZERO) if first else bounds.expand(top)
				first = false
		# A conservative prism above each actual deck, following the full capsule
		# height. Sloped decks use a larger prism, so false obstructions are caught.
		bounds.position.y += 0.001
		bounds.size.y += 2.25
		corridors.append({"name":str(course.get_path_to(deck)), "bounds":bounds})
	return corridors

func visual_clearance_checks(course: Node, scenery: Node, meshes: Array[Node], label: String) -> void:
	# VEILRUN's original district also contains its actual playable surface art.
	# The three scenery-only instances must not draw phantom walls in body space.
	if scenery.name != "CityScenery": return
	var corridors := body_visual_corridors(course)
	var overlap_count := 0
	var examples: Array[Dictionary] = []
	for instance in meshes:
		if instance.mesh == null: continue
		for surface in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			var indexed: bool = indices != null and not indices.is_empty()
			var count: int = indices.size() if indexed else vertices.size()
			for triangle in range(0, count, 3):
				var a: Vector3 = instance.global_transform * vertices[indices[triangle] if indexed else triangle]
				var b: Vector3 = instance.global_transform * vertices[indices[triangle + 1] if indexed else triangle + 1]
				var c: Vector3 = instance.global_transform * vertices[indices[triangle + 2] if indexed else triangle + 2]
				var lower := a.min(b).min(c)
				var upper := a.max(b).max(c)
				for corridor in corridors:
					var bounds: AABB = corridor.bounds
					var start := bounds.position
					var end := bounds.end
					if upper.x > start.x + 0.0005 and lower.x < end.x - 0.0005 \
						and upper.y > start.y + 0.0005 and lower.y < end.y - 0.0005 \
						and upper.z > start.z + 0.0005 and lower.z < end.z - 0.0005:
						overlap_count += 1
						if examples.size() < 4:
							examples.append({"mesh":str(instance.name), "deck":corridor.name,
								"triangle_min":stable(lower), "triangle_max":stable(upper)})
	check(overlap_count == 0, label + " decorative meshes stay out of the visible capsule corridor")
	print("CITY_VISUAL_CLEARANCE ", JSON.stringify({"course":label, "overlaps":overlap_count, "examples":examples}))

func scenery_checks(course: Node, label: String) -> void:
	var scenery := find_scenery(course)
	check(scenery != null, label + " instances authored rooftop city scenery")
	if scenery == null: return
	var noncollision := scenery.find_children("*", "CollisionObject3D", true, false).is_empty()
	noncollision = noncollision and scenery.find_children("*", "CollisionShape3D", true, false).is_empty()
	for csg in scenery.find_children("*", "CSGShape3D", true, false):
		noncollision = noncollision and not csg.use_collision
	check(noncollision, label + " scenery introduces no route or grapple-LOS collision")
	var meshes := scenery.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty() and meshes.size() <= 200, label + " city uses bounded prebuilt mesh batches")
	check(scenery.find_children("*", "CSGShape3D", true, false).is_empty(), label + " decorative city needs no runtime CSG")
	var triangles := 0
	var valid_meshes := true
	for instance in meshes:
		valid_meshes = valid_meshes and instance.mesh != null and instance.visible
		if instance.mesh == null: continue
		for surface in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var indices = arrays[Mesh.ARRAY_INDEX]
			triangles += int(indices.size() / 3) if indices != null and indices.size() > 0 else int(arrays[Mesh.ARRAY_VERTEX].size() / 3)
	check(valid_meshes and triangles > 0 and triangles <= 180000, label + " imported city geometry stays bounded and visible")
	var lamps := scenery.find_children("*", "OmniLight3D", true, false)
	var bounded_lamps := lamps.size() <= 6
	for lamp in lamps: bounded_lamps = bounded_lamps and not lamp.shadow_enabled and lamp.omni_range <= 14.0
	check(bounded_lamps, label + " local lighting stays short-range and shadowless")
	print("COURSE_CITY_BUDGET ", JSON.stringify({"course":label, "meshes":meshes.size(), "triangles":triangles, "lamps":lamps.size()}))
	visual_clearance_checks(course, scenery, meshes, label)

func run() -> void:
	var controls := control_fingerprint()
	if not capture_only:
		check(controls == EXPECTED_CONTROLS, "Movement, acquisition, spring presentation and clock match the reviewed city revision")
		check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "All city courses target Compatibility")
	var bests_existed := FileAccess.file_exists("user://parkour_bests.cfg")
	var preferences_existed := FileAccess.file_exists("user://parkour_settings.cfg")
	var saved_bests := bytes_at("user://parkour_bests.cfg")
	var saved_preferences := bytes_at("user://parkour_settings.cfg")
	for path in COURSES:
		var course: Node = load(path).instantiate()
		var before := fingerprint(course)
		captures[path] = before
		if not capture_only:
			check(path in EXPECTED and before.sha256 == EXPECTED.get(path, {}).get("sha256", ""), path + " preserves every original collision, fixture, recovery and movement setting")
		course.clock.save_path = "user://city_courses_%d.cfg" % OS.get_process_id()
		root.add_child(course)
		current_scene = course
		course.set_physics_process(false)
		course.player.set_physics_process(false)
		await frames(6)
		var environment_node := course.get_node_or_null("WorldEnvironment")
		var sun := course.get_node_or_null("Sun")
		if not capture_only:
			check(course._checkpoints.size() == course.checkpoint_paths.size()
				and course.clock.checkpoint_count == course.checkpoint_paths.size(),
				path + " initializes every ordered gate with the existing clock")
			for checkpoint_path in course.checkpoint_paths:
				var marker: Marker3D = course.get_node(checkpoint_path).get_node("Respawn")
				var query := PhysicsRayQueryParameters3D.create(marker.global_position + Vector3.UP * 0.5,
					marker.global_position + Vector3.DOWN * 3.0, 1, [course.player.get_rid()])
				var hit: Dictionary = course.get_world_3d().direct_space_state.intersect_ray(query)
				check(not hit.is_empty() and hit.normal.y > 0.7,
					path + " " + str(checkpoint_path) + " retains a physical recovery floor")
			check(environment_node is WorldEnvironment and environment_node.environment != null
				and sun is DirectionalLight3D and sun.visible and sun.light_energy > 0,
				path + " retains explicit environment and directional light")
			if environment_node is WorldEnvironment and environment_node.environment != null:
				var environment: Environment = environment_node.environment
				check(environment.fog_enabled and not environment.volumetric_fog_enabled
					and environment.fog_density > 0.0 and environment.fog_density <= 0.012,
					path + " uses inexpensive readable city distance fog")
			scenery_checks(course, path)
		load("res://tests/audio_test_cleanup.gd").stop_voices(self)
		root.get_node("GameManager").player = null
		course.queue_free()
		current_scene = null
		await frames(4)
		DirAccess.remove_absolute("user://city_courses_%d.cfg" % OS.get_process_id())
	load("res://tests/audio_test_cleanup.gd").drain_mixer()
	if capture_only:
		print("CITY_COURSES_CAPTURE ", JSON.stringify({"controls_sha256":controls, "courses":captures}))
	else:
		check(FileAccess.file_exists("user://parkour_bests.cfg") == bests_existed
			and bytes_at("user://parkour_bests.cfg") == saved_bests, "City audit leaves personal bests unchanged")
		check(FileAccess.file_exists("user://parkour_settings.cfg") == preferences_existed
			and bytes_at("user://parkour_settings.cfg") == saved_preferences, "City audit leaves presentation preferences unchanged")
		print("CITY_COURSES_RESULT ", JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
