extends RefCounted

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 20
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.055, 0.055, 0.055, 0.98)
	panel.border_color = Color(0.4, 0.4, 0.4)
	panel.set_border_width_all(1)
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 24
	panel.content_margin_bottom = 24
	result.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.65, 0.025, 0.035) if state == "hover" or state == "pressed" else Color(0.13, 0.13, 0.13)
		style.border_color = Color(0.75, 0.75, 0.75)
		style.set_border_width_all(2 if state == "focus" else 1)
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		style.content_margin_left = 16
		style.content_margin_right = 16
		result.set_stylebox(state, "Button", style)
	return result

static func label(text: String, size: int = 20) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

static func button(text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.pressed.connect(callback)
	return node
