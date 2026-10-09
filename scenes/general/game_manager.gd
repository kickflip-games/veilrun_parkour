extends Node
## The active parkour player is shared by course and presentation code.

var player: Node3D

func _ready() -> void:
	_migrate_parkour_saves()

func register_player(value: Node3D) -> void:
	player = value

func _migrate_parkour_saves() -> void:
	# Keep existing times and preferences when the working title changes.
	# Existing destination files always take precedence over the old project.
	var old_directory := OS.get_user_data_dir().get_base_dir().path_join("Kill Bit")
	for filename: String in ["parkour_bests.cfg", "parkour_settings.cfg"]:
		var destination := "user://" + filename
		var source := old_directory.path_join(filename)
		if FileAccess.file_exists(destination) or not FileAccess.file_exists(source):
			continue
		var error := DirAccess.copy_absolute(source, ProjectSettings.globalize_path(destination))
		if error != OK:
			push_warning("Could not migrate %s: %s" % [filename, error_string(error)])
