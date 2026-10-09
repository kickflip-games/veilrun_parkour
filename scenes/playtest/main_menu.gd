extends Control

const UI = preload("res://scenes/playtest/playtest_ui.gd")
const MOBILE_CONTROLS = preload("res://scenes/player/mobile_controls.gd")
const SETTINGS = preload("res://scenes/parkour/presentation_settings.gd")
const PARKOUR_COURSES := [
	{"title":"THE CITY RUN", "type":"7 SECTORS / ONE CONTINUOUS RUN", "path":"res://levels/parkour/MainCityRun.tscn", "hint":"Race the eaves, chimneys, slate banks and high ward. Hold to pull; let go to fly."},
	{"title":"VEILRUN ROOFTOPS", "type":"REFERENCE / ROOFTOP", "path":"res://levels/parkour/rooftop_trial.tscn", "hint":"The original rooftop study. Chain pulls across misty rooftops."},
	{"title":"SWITCHBACK", "type":"COMPARISON / LONG CIRCUIT", "path":"res://levels/parkour/parkour_trial.tscn", "hint":"Springs, aerial links and a sky hairpin. Chase the long line."},
	{"title":"RIPTIDE", "type":"COMPARISON / SURF", "path":"res://levels/parkour/riptide.tscn", "hint":"Drop into the banks. Carry speed through sweeping transfers."},
	{"title":"SWITCHYARD", "type":"COMPARISON / PRECISION", "path":"res://levels/parkour/switchyard.tscn", "hint":"Offset gates, pillar slalom and split routes. Pick your line."},
]

var _center: CenterContainer
var _panel: PanelContainer
var _cards: GridContainer
var _comparison_cards: GridContainer
var _settings: GridContainer
var _course_buttons: Array[Button] = []
var _settings_status: Label

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false
	GameManager.player = null
	SoundManager.music_player.stop()
	SETTINGS.load_settings()
	theme = UI.theme()
	var background := ColorRect.new()
	background.color = Color(0.025, 0.025, 0.025)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	# A narrow window can scroll the stacked cards; the standard landscape
	# viewport shows the complete course selection without scrolling.
	var scroll := ScrollContainer.new()
	scroll.name = "MenuScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_top = 16
	scroll.offset_right = -16
	scroll.offset_bottom = -16
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_center = CenterContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_center)
	_panel = PanelContainer.new()
	_panel.name = "CoursePanel"
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.055, 0.055, 0.98)
	panel_style.border_color = Color(0.35, 0.35, 0.35)
	panel_style.set_border_width_all(1)
	panel_style.content_margin_left = 24
	panel_style.content_margin_right = 24
	panel_style.content_margin_top = 20
	panel_style.content_margin_bottom = 20
	_panel.add_theme_stylebox_override("panel", panel_style)
	_center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	column.add_child(heading)
	var eyebrow := UI.label("PARKOUR  /  CITY TIME TRIAL", 14)
	eyebrow.modulate = Color(0.65, 0.65, 0.65)
	heading.add_child(eyebrow)
	var title := UI.label("VEILRUN", 42)
	title.modulate = Color(0.95, 0.95, 0.95)
	heading.add_child(title)
	heading.add_child(UI.label("Hold to bend your line. Release to carry the speed.", 18))
	_cards = GridContainer.new()
	_cards.name = "Courses"
	_cards.columns = 1
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 12)
	column.add_child(_cards)
	_add_course_card(0, _cards)
	var comparisons := UI.button("COURSE STUDIES  +", _toggle_comparisons)
	comparisons.name = "ComparisonCoursesToggle"
	comparisons.custom_minimum_size.y = 38
	column.add_child(comparisons)
	_comparison_cards = GridContainer.new()
	_comparison_cards.name = "CourseStudies"
	_comparison_cards.columns = 2
	_comparison_cards.add_theme_constant_override("h_separation", 12)
	_comparison_cards.add_theme_constant_override("v_separation", 12)
	column.add_child(_comparison_cards)
	for index in range(1, PARKOUR_COURSES.size()):
		_add_course_card(index, _comparison_cards)
	_comparison_cards.hide()
	_settings = GridContainer.new()
	_settings.name = "Presentation"
	_settings.columns = 2
	_settings.add_theme_constant_override("h_separation", 32)
	_settings.add_theme_constant_override("v_separation", 8)
	column.add_child(_settings)
	_add_effects_setting(_settings)
	_add_volume_setting(_settings)
	var divider := ColorRect.new()
	divider.color = Color(0.25, 0.25, 0.25)
	divider.custom_minimum_size.y = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(divider)
	var mobile := MOBILE_CONTROLS.is_mobile_web() or OS.get_cmdline_user_args().has("--mobile-controls")
	var controls := UI.label("MOVE / LOOK · JUMP · Hold PULL; let go to fly\nSECTOR practice · RETRY full run · II pause" if mobile else "WASD / arrows move · Mouse look · Space jump · Hold PULL; let go to fly\nR sector retry · Shift+R full run · Esc pause", 16)
	controls.name = "Controls"
	controls.modulate = Color(0.75, 0.75, 0.75)
	column.add_child(controls)
	resized.connect(_fit_layout)
	_fit_layout()
	_course_buttons[0].grab_focus()

func _fit_layout() -> void:
	if not is_instance_valid(_panel):
		return
	var available := maxf(280.0, size.x - 48.0)
	_panel.custom_minimum_size.x = minf(1040.0, available)
	_center.custom_minimum_size.y = maxf(0.0, size.y - 32.0)
	_comparison_cards.columns = 2 if available >= 820.0 else 1
	_settings.columns = 2 if available >= 620.0 else 1
	for button in _course_buttons:
		button.custom_minimum_size.y = 148.0 if available >= 820.0 else 174.0
		_fit_course_card(button)

func _fit_course_card(button: Button) -> void:
	if not button.has_meta("inline_kind"):
		return
	var stacked := button.size.x < 430.0
	button.get_meta("inline_kind").visible = not stacked
	button.get_meta("stacked_kind").visible = stacked

func _toggle_comparisons() -> void:
	_comparison_cards.visible = not _comparison_cards.visible
	var toggle := find_child("ComparisonCoursesToggle", true, false) as Button
	toggle.text = "COURSE STUDIES  −" if _comparison_cards.visible else "COURSE STUDIES  +"
	_fit_layout()

func _add_course_card(index: int, parent: GridContainer) -> void:
	var course: Dictionary = PARKOUR_COURSES[index]
	var button := UI.button("", _play_course.bind(String(course.path)))
	button.name = course.title
	button.tooltip_text = "%s · %s\n%s" % [course.title, course.type, course.hint]
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("course_path", course.path)
	parent.add_child(button)
	_course_buttons.append(button)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 6)
	margin.add_child(text)
	var card_heading := HBoxContainer.new()
	card_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(card_heading)
	var card_title := UI.label(course.title, 23)
	card_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_heading.add_child(card_title)
	var kind := UI.label(course.type, 12)
	kind.autowrap_mode = TextServer.AUTOWRAP_OFF
	kind.modulate = Color(0.7, 0.7, 0.7)
	kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_heading.add_child(kind)
	var stacked_kind := kind.duplicate() as Label
	stacked_kind.hide()
	text.add_child(stacked_kind)
	button.set_meta("inline_kind", kind)
	button.set_meta("stacked_kind", stacked_kind)
	button.resized.connect(_fit_course_card.bind(button))
	var description := UI.label(course.hint, 16)
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.modulate = Color(0.75, 0.75, 0.75)
	text.add_child(description)
	var run := UI.label("RUN COURSE  →", 16)
	run.modulate = Color(0.95, 0.95, 0.95)
	text.add_child(run)
	for child in text.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _setting_column(parent: GridContainer, name_text: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var name_label := UI.label(name_text, 18)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(name_label)
	return column

func _add_effects_setting(parent: GridContainer) -> void:
	var column := _setting_column(parent, "Effects strength")
	var value_label := UI.label("%d%%" % roundi(SETTINGS.effects_strength * 100.0), 18)
	value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.get_child(0).add_child(value_label)
	var slider := HSlider.new()
	slider.name = "EffectsStrength"
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = SETTINGS.effects_strength * 100.0
	slider.custom_minimum_size.y = 44
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(slider)
	_settings_status = UI.label("Camera, effects & movement sound", 14)
	_settings_status.modulate = Color(0.65, 0.65, 0.65)
	column.add_child(_settings_status)
	slider.value_changed.connect(func(value: float):
		value_label.text = "%d%%" % roundi(value)
		var error := SETTINGS.set_effects_strength(value / 100.0)
		_settings_status.text = "Camera, effects & movement sound" if error == OK else "Settings could not be saved."
	)

func _add_volume_setting(parent: GridContainer) -> void:
	var column := _setting_column(parent, "Volume")
	var value := clampf(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.0, 1.0)
	var value_label := UI.label("%d%%" % roundi(value * 100.0), 18)
	value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.get_child(0).add_child(value_label)
	var volume := HSlider.new()
	volume.name = "Volume"
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.01
	volume.value = value
	volume.custom_minimum_size.y = 44
	volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(volume)
	var caption := UI.label("Game audio", 14)
	caption.modulate = Color(0.65, 0.65, 0.65)
	column.add_child(caption)
	volume.value_changed.connect(func(level: float):
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(level, 0.001)))
		value_label.text = "%d%%" % roundi(level * 100.0)
	)

func _play_course(path: String) -> void:
	get_tree().change_scene_to_file(path)
