extends SceneTree
## Structural budgets and preserved targeting for the authored rooftop district.
## Physical traversal, timing and keyboard retry have separate scene harnesses.
## Godot --headless --path . --script tests/validate_rooftop_city.gd --fixed-fps 60
const ROOF := "res://levels/parkour/rooftop_trial.tscn"
const CITY := "res://levels/parkour/rooftop_city_district.tscn"
const Settings = preload("res://scenes/parkour/presentation_settings.gd")
const ANCHOR_POSITIONS := {
	"IntroRing": Vector3(0,16,-37),
	"GapLeftRing": Vector3(-10,16,-101),
	"GapRightRing": Vector3(8,16,-117),
	"GapExitRing": Vector3(8,16,-134),
	"GapSkipRing": Vector3(0,19,-111),
	"CourtyardLowRing": Vector3(-8,23,-176),
	"CourtyardMidRing": Vector3(8,26,-192),
	"CourtyardTopRing": Vector3(0,30,-212),
	"CourtyardSkipRing": Vector3(0,30,-181),
	"ChainLeftRing": Vector3(-7,28,-267),
	"ChainRightRing": Vector3(7,29,-287),
	"ChainExitRing": Vector3(0,29,-310),
	"FinalLeftRing": Vector3(-8,28,-350),
	"FinalRightRing": Vector3(8,28,-378),
	"FinishRing": Vector3(0,29,-408),
}
const RECOVERY_GEOMETRY := [
	"IntroCatchA", "IntroCatchRamp", "IntroCatchLanding", "IntroCatchJoin",
	"GapSafeEntry", "GapSafeCross", "GapSafeExit", "GapExpertBeam",
	"CourtyardLowerRamp", "CourtyardMiddleRamp", "CourtyardUpperRamp",
	"CourtyardUpperLanding", "CourtyardUpperJoin",
	"ChainLowEntry", "ChainLowStraight", "ChainLowRise", "ChainLowExit",
	"FinalSafeEntry", "FinalSafeCross", "FinalSafeExit",
]
var checks := 0
var failures: Array[String] = []
var course
var save_path := "user://rooftop_city_validation_%d.cfg" % OS.get_process_id()

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func bytes_at(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func has_static_box(node: Node) -> bool:
	if node == null:
		return false
	for shape_node in node.find_children("*", "CollisionShape3D", true, false):
		if shape_node.shape is BoxShape3D and shape_node.get_parent() is StaticBody3D and not shape_node.disabled:
			return true
	return false

func district_checks(district: Node) -> void:
	var meshes := district.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty() and meshes.size() <= 140, "District art stays within a 140 static mesh-instance budget")
	check(district.find_children("*", "CSGShape3D", true, false).is_empty(), "District renders prebuilt meshes without runtime CSG")
	check(district.find_children("*", "CollisionObject3D", true, false).is_empty(), "Decorative district introduces no small collision hazards")
	var usable_meshes := true
	var triangles := 0
	for mesh_node in meshes:
		usable_meshes = usable_meshes and mesh_node.mesh != null and mesh_node.visible
		if mesh_node.mesh == null:
			continue
		for surface in range(mesh_node.mesh.get_surface_count()):
			var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
			var indices = arrays[Mesh.ARRAY_INDEX]
			triangles += int(indices.size() / 3) if indices != null and indices.size() > 0 else int(arrays[Mesh.ARRAY_VERTEX].size() / 3)
	check(usable_meshes, "Every static visual batch has an imported visible mesh")
	check(triangles > 0 and triangles <= 160000, "District triangles stay within a 160000 static geometry budget")
	var landmarks := district.find_children("*Landmark*", "Marker3D", true, false)
	var streets := district.find_children("*Street*", "Marker3D", true, false)
	check(not landmarks.is_empty(), "District retains a named orienting landmark")
	check(not streets.is_empty(), "District retains a named lower street layer")
	var lights: Array[Node] = course.find_children("*", "OmniLight3D", true, false)
	var bounded_lights: bool = lights.size() > 0 and lights.size() <= 6
	for light in lights:
		bounded_lights = bounded_lights and not light.shadow_enabled and light.omni_range <= 14.0
	check(bounded_lights, "At most six short-range shadowless lamps create local warm pools")
	print("CITY_BUDGET ", JSON.stringify({"mesh_instances":meshes.size(),"triangles":triangles,"point_lights":lights.size(),"landmarks":landmarks.size(),"street_layers":streets.size()}))

func preserved_route_checks() -> void:
	check(course.course_id == "rooftop_pull_v1" and course._checkpoints.size() == 4, "Environment dressing retains the course ID and four ordered gates")
	check(is_equal_approx(course.grapple_range, 26.0) and is_equal_approx(course.acquisition_horizontal_degrees, 20.0) and is_equal_approx(course.acquisition_vertical_degrees, 42.0), "Environment dressing retains the authored acquisition bounds")
	var recovery_boxes := true
	for name in RECOVERY_GEOMETRY:
		recovery_boxes = recovery_boxes and has_static_box(course.get_node_or_null(name))
	check(recovery_boxes, "Every authored recovery bridge, climb and expert beam retains simple collision")
	for anchor_name in ANCHOR_POSITIONS:
		var anchor = course.get_node_or_null(anchor_name)
		check(anchor != null, anchor_name + " remains an inspectable authored fixture")
		if anchor == null:
			continue
		var collider = anchor.get_node_or_null("CollisionShape3D")
		check(anchor.global_position.is_equal_approx(ANCHOR_POSITIONS[anchor_name]) and collider != null and collider.shape is SphereShape3D and is_equal_approx(collider.shape.radius, 0.35) and collider.position.is_zero_approx(), anchor_name + " retains its fixed original aim point and collider")
		var core = anchor.get_node_or_null("Diamond/Core")
		check(anchor.targetable and not anchor.show_label and core != null and not core.is_visible_in_tree(), anchor_name + " reads as an iron fixture without a floating glowing core or label")
		var support: Node = course.get_node_or_null(anchor_name + "Hanger")
		check(support != null, anchor_name + " keeps an architectural hanger")
		var before: Vector3 = anchor.global_position
		anchor.set_pull_feedback(false, false, false)
		var dormant: Color = anchor._ring_material.albedo_color
		anchor.set_pull_feedback(true, true, false)
		var selected: Color = anchor._ring_material.albedo_color
		check(selected.get_luminance() > dormant.get_luminance() and anchor.global_position == before, anchor_name + " highlights when selected without moving its aim point")
		anchor.set_pull_feedback(false, false, false)

func run() -> void:
	var settings_existed := FileAccess.file_exists(Settings.SAVE_PATH)
	var settings_before := bytes_at(Settings.SAVE_PATH)
	var best_existed := FileAccess.file_exists("user://parkour_bests.cfg")
	var best_before := bytes_at("user://parkour_bests.cfg")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "City targets the Compatibility renderer")
	course = load(ROOF).instantiate()
	course.clock.save_path = save_path
	root.add_child(course)
	current_scene = course
	await frames(10)
	course.set_physics_process(false)
	course.player.set_physics_process(false)
	var environment: Environment = course.get_node("WorldEnvironment").environment
	check(environment != null and environment.fog_enabled and not environment.volumetric_fog_enabled and environment.fog_density > 0.0 and environment.fog_density <= 0.012, "Inexpensive distance fog leaves nearby traversal visible without volumetrics")
	var district: Node = null
	for child in course.get_children():
		if child.scene_file_path == CITY:
			district = child
			break
	check(district != null, "Authored city district is instanced into the playable rooftop course")
	if district != null:
		district_checks(district)
	preserved_route_checks()
	check(FileAccess.file_exists(Settings.SAVE_PATH) == settings_existed and bytes_at(Settings.SAVE_PATH) == settings_before, "City validation leaves real presentation preferences unchanged")
	check(FileAccess.file_exists("user://parkour_bests.cfg") == best_existed and bytes_at("user://parkour_bests.cfg") == best_before, "City validation leaves real personal bests unchanged")
	for audio in root.get_node("SoundManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	course.player.parkour_juice.wind_player.stop()
	course.player.parkour_juice.wind_player.stream = null
	root.get_node("GameManager").player = null
	course.queue_free()
	current_scene = null
	await frames(3)
	DirAccess.remove_absolute(save_path)
	OS.delay_msec(150)
	print("ROOFTOP_CITY_RESULT ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
