extends SceneTree
## Mount the Web PCK with its 4.6 runtime and use an absolute --script path.
## Validates active courses/solver/recorder and excludes FPS/tests/editor addons.
var files: Array[String] = []
func _initialize() -> void:
    call_deferred("audit")
func crawl(path: String) -> void:
    for file in DirAccess.get_files_at(path):
        files.append(path.path_join(file))
    for directory in DirAccess.get_directories_at(path):
        crawl(path.path_join(directory))
func audit() -> void:
    crawl("res://")
    var forbidden: Array[String] = []
    for file in files:
        if (file.begins_with("res://addons/") and not file.begins_with("res://addons/logger/")) or file.begins_with("res://scenes/general/debug_menu/") or file.begins_with("res://archive/") or file.begins_with("res://scenes/enemies/") or file.begins_with("res://scenes/weapons/") or file.begins_with("res://scenes/pickups/") or file.begins_with("res://scenes/FXs/") or file.begins_with("res://tests/") or file.begins_with("res://tools/"):
            forbidden.append(file)
    var expected := ResourceLoader.exists("res://levels/parkour/rooftop_trial.tscn") and ResourceLoader.exists("res://scenes/parkour/anchor_pull.gd") and ResourceLoader.exists("res://scenes/parkour/air_control.gd") and ResourceLoader.exists("res://scenes/parkour/run_recorder.gd") and ResourceLoader.exists("res://scenes/parkour/grapple_controller.tscn") and ResourceLoader.exists("res://levels/parkour/riptide.tscn") and ResourceLoader.exists("res://levels/parkour/switchyard.tscn") and ResourceLoader.exists("res://levels/parkour/parkour_trial.tscn")
    expected = expected and ResourceLoader.exists("res://levels/parkour/rooftop_city_district.tscn") and ResourceLoader.exists("res://levels/parkour/parkour_trial_city_scenery.tscn") and ResourceLoader.exists("res://levels/parkour/riptide_city_scenery.tscn") and ResourceLoader.exists("res://levels/parkour/switchyard_city_scenery.tscn") and ResourceLoader.exists("res://scenes/parkour/city_roof.tres") and ResourceLoader.exists("res://scenes/parkour/city_sky.tres")
    expected = expected and ResourceLoader.exists("res://levels/parkour/MainCityRun.tscn") and ResourceLoader.exists("res://scenes/parkour/city_checkpoint.gd")
    expected = expected and ResourceLoader.exists("res://scenes/parkour/contact_traversal.gd") and ResourceLoader.exists("res://scenes/parkour/contact_traversal.tscn")
    var city_runtime_instances := false
    var city_horizontal_aim := false
    var adjacent_roof_solids := 0
    var adjacent_roof_collision := true
    var passive_devices := 0
    var passive_collision := true
    if expected:
        var packed = load("res://levels/parkour/MainCityRun.tscn") as PackedScene
        if packed:
            var city = packed.instantiate()
            city_runtime_instances = city != null and city.has_node("Player") and city.has_node("FinishGate") and city.checkpoint_paths.size() == 6
            city_horizontal_aim = city_runtime_instances and not city.get_node("Player").vertical_look_enabled
            if city:
                for node in city.find_children("*", "Node3D", true, false):
                    if node is Area3D and node.get_script() != null and node.get_script().resource_path == "res://scenes/parkour/contact_traversal.gd":
                        passive_devices += 1
                        passive_collision = passive_collision and node.collision_layer == 0 and node.collision_mask == 4 and not node.is_in_group("grapple_anchors")
                        var volume := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
                        passive_collision = passive_collision and volume != null and not volume.disabled and volume.shape is BoxShape3D
                    if not node.is_in_group("city_adjacent_roof"):
                        continue
                    adjacent_roof_solids += 1
                    var body := node.get_node_or_null("collision_body") as StaticBody3D
                    var shape := node.get_node_or_null("collision_body/collision_shape") as CollisionShape3D
                    var mesh := node.get_node_or_null("mesh_instance") as MeshInstance3D
                    adjacent_roof_collision = adjacent_roof_collision and body != null and (body.collision_layer & 1) != 0
                    adjacent_roof_collision = adjacent_roof_collision and shape != null and not shape.disabled and shape.shape is ConvexPolygonShape3D
                    adjacent_roof_collision = adjacent_roof_collision and mesh != null and not mesh.visible
                # This offline probe never enters the tree. HUD constructs its
                # mobile Control eagerly but parents it only in _ready(), so
                # the probe must free that detached allocation explicitly.
                var hud := city.get_node_or_null("Player/Hud")
                if hud:
                    var controls := hud.get("mobile_controls") as Node
                    if controls and controls.get_parent() == null:
                        controls.free()
                        hud.set("mobile_controls", null)
                city.free()
    adjacent_roof_collision = adjacent_roof_collision and adjacent_roof_solids == 21
    passive_collision = passive_collision and passive_devices == 2
    print("VEILRUN_PACK_AUDIT ",JSON.stringify({"resource_files":files.size(),"forbidden":forbidden,"all_courses_and_grapple":expected,"city_runtime_instances_without_editor_addons":city_runtime_instances,"city_horizontal_aim":city_horizontal_aim,"adjacent_roof_solids":adjacent_roof_solids,"adjacent_roof_collision":adjacent_roof_collision,"passive_devices":passive_devices,"passive_contact_collision":passive_collision,"application_name":ProjectSettings.get_setting("application/config/name")}))
    var sound = root.get_node("SoundManager")
    for child in sound.get_children():
        if child is AudioStreamPlayer:
            child.stop()
            child.stream = null
    if current_scene:
        current_scene.queue_free()
    await process_frame
    await process_frame
    OS.delay_msec(150)
    quit(0 if forbidden.is_empty() and expected and city_runtime_instances and city_horizontal_aim and adjacent_roof_collision and passive_collision else 1)
