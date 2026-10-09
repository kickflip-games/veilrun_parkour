extends RefCounted
## Shared presentation preference for the menu and active parkour course.

const SAVE_PATH := "user://parkour_settings.cfg"
static var effects_strength: float = 1.0

static func load_settings() -> void:
	effects_strength = 1.0
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var saved: Variant = config.get_value("presentation", "effects_strength", 1.0)
	if not (saved is float or saved is int):
		return
	var value := float(saved)
	if is_finite(value):
		effects_strength = clampf(value, 0.0, 1.0)

static func set_effects_strength(value: float) -> Error:
	effects_strength = clampf(value, 0.0, 1.0) if is_finite(value) else 1.0
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("presentation", "effects_strength", effects_strength)
	return config.save(SAVE_PATH)
