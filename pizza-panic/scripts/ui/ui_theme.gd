class_name UiTheme
extends RefCounted
## One look for every screen: soft dark glass panels, a single clean font,
## yellow primary buttons, round corners, thin borders, key-cap chips.
##
## Type scale: CAPTION 14 · BODY 18 · LABEL 22 · HEADING 30 · DISPLAY 52
## Spacing: 8 / 14 / 22.  Corners: 10 (small), 16 (panels).

const INK := Color("#2b1d33")
const BG := Color(0.105, 0.075, 0.17, 0.9)       # panels
const CARD := Color(0.19, 0.145, 0.29, 0.95)      # cards inside panels
const LINE := Color(1, 1, 1, 0.1)
const TEXT := Color("#f7f2ff")
const MUTED := Color("#b4a8cf")
const YELLOW := Color("#ffd166")
const TEAL := Color("#2fe3b2")
const PINK := Color("#ff8fab")
const RED := Color("#ff5d73")
const BLUE := Color("#7aa7ff")
const PURPLE := Color("#b69bff")
const CREAM := TEXT     # old name, kept so older callers still compile

const CAPTION := 14
const BODY := 18
const LABEL := 22
const HEADING := 30
const DISPLAY := 52

static var _theme: Theme
static var _font: Font


## Clean UI font: Outfit Bold, shipped in res://fonts (system fallback if not imported).
static func ui_font() -> Font:
	if _font == null:
		if ResourceLoader.exists("res://fonts/Outfit-Bold.ttf"):
			_font = load("res://fonts/Outfit-Bold.ttf") as Font
		if _font == null:
			var f := SystemFont.new()
			f.font_names = PackedStringArray(["SF Pro Rounded", "Avenir Next Rounded", "Arial Rounded MT Bold", "Avenir Next", "Segoe UI", "Helvetica Neue", "Noto Sans"])
			f.font_weight = 600
			_font = f
	return _font


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = ui_font()
	t.default_font_size = BODY

	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())

	# Primary button: yellow. Variation "Ghost": quiet dark button.
	t.set_stylebox("normal", "Button", flat(YELLOW, 12, 18, 10))
	t.set_stylebox("hover", "Button", flat(YELLOW.lightened(0.2), 12, 18, 10))
	t.set_stylebox("pressed", "Button", flat(YELLOW.darkened(0.12), 12, 18, 10))
	t.set_stylebox("disabled", "Button", flat(Color(1, 1, 1, 0.1), 12, 18, 10))
	t.set_stylebox("focus", "Button", flat(Color(0, 0, 0, 0), 12, 18, 10, TEAL, 2))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_font_size("font_size", "Button", LABEL)

	t.set_type_variation("Ghost", "Button")
	t.set_stylebox("normal", "Ghost", flat(Color(0.13, 0.095, 0.21, 0.92), 12, 18, 10, Color(1, 1, 1, 0.16), 1))
	t.set_stylebox("hover", "Ghost", flat(Color(0.22, 0.17, 0.34, 0.95), 12, 18, 10, Color(1, 1, 1, 0.25), 1))
	t.set_stylebox("pressed", "Ghost", flat(Color(0.09, 0.065, 0.15, 0.95), 12, 18, 10, LINE, 1))
	t.set_stylebox("disabled", "Ghost", flat(Color(0.13, 0.095, 0.21, 0.6), 12, 18, 10, LINE, 1))
	t.set_color("font_disabled_color", "Ghost", Color(1, 1, 1, 0.35))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Ghost", TEXT)

	var field := flat(Color(0, 0, 0, 0.3), 10, 14, 9, LINE, 1)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", flat(Color(0, 0, 0, 0.3), 10, 14, 9, TEAL, 2))
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT, 0.4))
	t.set_color("caret_color", "LineEdit", YELLOW)
	t.set_color("selection_color", "LineEdit", Color(TEAL, 0.35))

	t.set_stylebox("normal", "OptionButton", field)
	t.set_stylebox("hover", "OptionButton", flat(Color(1, 1, 1, 0.12), 10, 14, 9, LINE, 1))
	t.set_stylebox("pressed", "OptionButton", flat(Color(1, 1, 1, 0.06), 10, 14, 9, LINE, 1))
	t.set_stylebox("focus", "OptionButton", flat(Color(0, 0, 0, 0), 10, 14, 9, TEAL, 2))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "OptionButton", TEXT)
	t.set_stylebox("panel", "PopupMenu", flat(Color("#241a3a"), 10, 6, 6, LINE, 1))
	t.set_stylebox("hover", "PopupMenu", flat(Color(1, 1, 1, 0.14), 8, 6, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", TEXT)

	t.set_color("font_color", "Label", TEXT)
	for ty in ["CheckBox"]:
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_hover_color", ty, TEXT)
		t.set_color("font_pressed_color", ty, TEXT)
		t.set_color("font_hover_pressed_color", ty, TEXT)
		t.set_color("font_focus_color", ty, TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)

	t.set_stylebox("background", "ProgressBar", flat(Color(0, 0, 0, 0.35), 8, 0, 0))
	t.set_stylebox("fill", "ProgressBar", flat(TEAL, 8, 0, 0))
	t.set_color("font_color", "ProgressBar", TEXT)

	var track := flat(Color(0, 0, 0, 0.35), 6, 0, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", flat(YELLOW, 6, 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(YELLOW.lightened(0.2), 6, 0, 0))
	_theme = t
	return t


## Plain rounded box. `border` 0 = none.
static func flat(fill: Color, radius := 12, pad_x := 14, pad_y := 8, border_color := LINE, border := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border_color
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.anti_aliasing = true
	return s


## The standard floating panel: dark glass, hairline border, soft shadow.
static func panel(fill := BG, radius := 16, pad := 14) -> StyleBoxFlat:
	var s := flat(fill, radius, pad, pad * 0.8, LINE, 1)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	return s


## A lighter card that sits inside a panel; `accent` draws a colored stripe on the left.
static func card(accent := Color(0, 0, 0, 0), pad := 12, fill := CARD) -> StyleBoxFlat:
	var s := flat(fill, 12, pad, pad * 0.7, LINE, 0)
	if accent.a > 0.0:
		s.border_color = accent
		s.border_width_left = 5
		s.content_margin_left = pad + 2
	return s


## Older call sites: map the chunky cartoon box onto the new look.
static func box(fill: Color, _border := 0, radius := 14, pad := 12, border_color := LINE) -> StyleBoxFlat:
	var s := flat(fill, radius, pad, pad * 0.6, border_color, 0)
	return s


static func label(text: String, size := BODY, color := TEXT, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", INK)
	return l


## Small uppercase section label.
static func caption(text: String, color := MUTED) -> Label:
	var l := label(text.to_upper(), CAPTION, color)
	l.add_theme_constant_override("line_spacing", 0)
	return l


## A row of text where every "[KEY]" becomes a little key-cap chip, e.g.
## "[E] Grab dough  ·  [F] car". Returns an HBoxContainer.
static func keyed_text(text: String, size := LABEL) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var rx := RegEx.new()
	rx.compile("\\[([^\\]]+)\\]")
	var pos := 0
	for m in rx.search_all(text):
		var before := text.substr(pos, m.get_start() - pos).strip_edges(false, true) if pos == 0 else text.substr(pos, m.get_start() - pos)
		if before.strip_edges() != "":
			row.add_child(label(before.strip_edges(), size))
		row.add_child(key_chip(m.get_string(1), size))
		pos = m.get_end()
	var rest := text.substr(pos).strip_edges()
	if rest != "":
		row.add_child(label(rest, size))
	return row


static func key_chip(key: String, size := LABEL) -> PanelContainer:
	var chip := PanelContainer.new()
	var s := flat(YELLOW, 8, 9, 2)
	s.border_width_bottom = 3
	s.border_color = YELLOW.darkened(0.25)
	chip.add_theme_stylebox_override("panel", s)
	var l := label(key, maxi(CAPTION, size - 5), INK)
	chip.add_child(l)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return chip
