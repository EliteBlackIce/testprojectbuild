class_name UiTheme
extends RefCounted
## Chunky cartoon UI: thick dark outlines, rounded corners, loud colors.

const INK := Color("#2b1d33")
const CREAM := Color("#fff8e7")
const RED := Color("#e63946")
const YELLOW := Color("#ffd166")
const TEAL := Color("#06d6a0")
const PINK := Color("#ff8fab")

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = Toon.goofy_font()
	t.default_font_size = 24

	t.set_stylebox("panel", "PanelContainer", box(CREAM))
	t.set_stylebox("panel", "Panel", box(CREAM))

	t.set_stylebox("normal", "Button", box(YELLOW, 4, 14, 10))
	t.set_stylebox("hover", "Button", box(YELLOW.lightened(0.25), 4, 14, 10))
	t.set_stylebox("pressed", "Button", box(PINK, 4, 14, 10))
	t.set_stylebox("disabled", "Button", box(Color("#cccccc"), 4, 14, 10))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 4, 14, 10, TEAL))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", INK)
	t.set_font_size("font_size", "Button", 26)

	t.set_stylebox("normal", "LineEdit", box(Color.WHITE, 3, 12, 8))
	t.set_stylebox("focus", "LineEdit", box(Color.WHITE, 4, 12, 8, TEAL))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.45))
	t.set_color("caret_color", "LineEdit", INK)

	t.set_stylebox("normal", "OptionButton", box(Color.WHITE, 3, 12, 8))
	t.set_stylebox("hover", "OptionButton", box(Color("#f0f0f0"), 3, 12, 8))
	t.set_stylebox("pressed", "OptionButton", box(Color("#e0e0e0"), 3, 12, 8))
	t.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), 4, 12, 8, TEAL))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "OptionButton", INK)

	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)

	var bar_bg := box(Color("#ffffff"), 3, 10, 0)
	var bar_fill := box(TEAL, 0, 8, 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", INK)

	t.set_stylebox("slider", "HSlider", box(Color.WHITE, 3, 8, 4))
	t.set_stylebox("grabber_area", "HSlider", box(YELLOW, 3, 8, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(YELLOW, 3, 8, 4))
	_theme = t
	return t


static func box(fill: Color, border := 4, radius := 18, pad := 14, border_color := INK) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border_color
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 0 if border == 0 else 4
	s.shadow_offset = Vector2(4, 5)
	return s


static func label(text: String, size := 24, color := INK, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", INK)
	return l
