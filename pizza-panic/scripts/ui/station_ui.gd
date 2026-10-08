class_name StationUi
extends CanvasLayer
## Overlay while you're working a station (prep table or cutting board):
## the ticket you're making, a toolbar (click or press 1-9), live meters,
## and Done / Step away buttons. The kitchen fills it in; the actual work
## happens in 3D with the mouse.

signal tool_selected(id: String)
signal done_pressed
signal leave_pressed
signal next_ticket_pressed

var _root: Control
var _title: Label
var _instr: Label
var _card_title: Label
var _card_body: RichTextLabel
var _tools: HFlowContainer
var _meters: VBoxContainer
var _done: Button
var _splat: Control
var _tool_ids: Array[String] = []
var _tool_buttons: Array[Button] = []
var _selected := ""


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.get_theme()
	add_child(_root)

	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -430
	top.offset_right = 430
	top.offset_top = 16
	top.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.CREAM, 4, 18, 12))
	_root.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	_title = UiTheme.label("", 30, UiTheme.RED)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_title)
	_instr = UiTheme.label("", 20)
	_instr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instr.autowrap_mode = TextServer.AUTOWRAP_WORD
	tv.add_child(_instr)

	# Ticket card (left)
	var card := PanelContainer.new()
	card.position = Vector2(20, 130)
	card.custom_minimum_size = Vector2(290, 0)
	card.add_theme_stylebox_override("panel", UiTheme.box(Color("#fffdf5"), 4, 6, 14))
	_root.add_child(card)
	var cv := VBoxContainer.new()
	card.add_child(cv)
	_card_title = UiTheme.label("", 26, UiTheme.RED)
	cv.add_child(_card_title)
	_card_body = RichTextLabel.new()
	_card_body.bbcode_enabled = true
	_card_body.fit_content = true
	_card_body.scroll_active = false
	_card_body.custom_minimum_size = Vector2(260, 0)
	_card_body.add_theme_font_size_override("normal_font_size", 20)
	_card_body.add_theme_color_override("default_color", UiTheme.INK)
	cv.add_child(_card_body)
	var next := Button.new()
	next.text = "Other ticket [Tab]"
	next.pressed.connect(func(): next_ticket_pressed.emit())
	next.name = "NextTicket"
	cv.add_child(next)

	# Meters (right)
	var mp := PanelContainer.new()
	mp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mp.offset_left = -300
	mp.offset_right = -20
	mp.offset_top = 130
	mp.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.CREAM, 4, 18, 14))
	_root.add_child(mp)
	_meters = VBoxContainer.new()
	_meters.add_theme_constant_override("separation", 6)
	mp.add_child(_meters)

	# Toolbar + buttons (bottom)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -620
	bottom.offset_right = 620
	bottom.offset_top = -200
	bottom.offset_bottom = -16
	bottom.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(bottom)
	_tools = HFlowContainer.new()
	_tools.alignment = FlowContainer.ALIGNMENT_CENTER
	_tools.add_theme_constant_override("h_separation", 6)
	_tools.add_theme_constant_override("v_separation", 6)
	bottom.add_child(_tools)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	bottom.add_child(row)
	var leave := Button.new()
	leave.text = "Step away [Esc]"
	leave.pressed.connect(func(): leave_pressed.emit())
	row.add_child(leave)
	_done = Button.new()
	_done.text = "DONE [E]"
	_done.add_theme_font_size_override("font_size", 28)
	_done.pressed.connect(func(): done_pressed.emit())
	row.add_child(_done)

	# Dough-on-your-face overlay
	_splat = Control.new()
	_splat.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splat.draw.connect(_draw_splat)
	_splat.visible = false
	_root.add_child(_splat)
	visible = false


func open(title: String, instructions: String) -> void:
	_title.text = title
	_instr.text = instructions
	visible = true


func close() -> void:
	visible = false


func set_instructions(text: String) -> void:
	_instr.text = text


func set_ticket(t: Dictionary, checklist: String, can_switch: bool) -> void:
	if t.is_empty():
		_card_title.text = "No ticket"
		_card_body.text = ""
	else:
		_card_title.text = "#%d  %s" % [t.id, t.customer]
		_card_body.text = checklist
	(_root.find_child("NextTicket", true, false) as Button).visible = can_switch


func set_done_text(text: String, enabled := true) -> void:
	_done.text = text
	_done.disabled = not enabled


## tools: Array of [id, label, color]
func set_tools(tools: Array) -> void:
	for c in _tools.get_children():
		c.queue_free()
	_tool_ids.clear()
	_tool_buttons.clear()
	for i in tools.size():
		var t: Array = tools[i]
		var b := Button.new()
		b.text = ("%d  %s" % [i + 1, t[1]]) if i < 9 else str(t[1])
		b.add_theme_font_size_override("font_size", 16)
		var col: Color = t[2]
		b.add_theme_stylebox_override("normal", UiTheme.box(col.lerp(Color.WHITE, 0.55), 3, 12, 8))
		b.add_theme_stylebox_override("hover", UiTheme.box(col.lerp(Color.WHITE, 0.3), 3, 12, 8))
		b.add_theme_stylebox_override("pressed", UiTheme.box(col, 5, 12, 8))
		b.pressed.connect(_on_tool.bind(str(t[0])))
		_tools.add_child(b)
		_tool_ids.append(str(t[0]))
		_tool_buttons.append(b)
	_highlight()


func select_index(i: int) -> void:
	if i >= 0 and i < _tool_ids.size():
		_on_tool(_tool_ids[i])


func select(id: String) -> void:
	_selected = id
	_highlight()


func _on_tool(id: String) -> void:
	_selected = id
	_highlight()
	tool_selected.emit(id)
	Sfx.play("click")


func _highlight() -> void:
	for i in _tool_buttons.size():
		var b := _tool_buttons[i]
		var on := _tool_ids[i] == _selected
		b.scale = Vector2.ONE * (1.12 if on else 1.0)
		b.pivot_offset = b.size * 0.5
		b.add_theme_color_override("font_color", UiTheme.RED if on else UiTheme.INK)


## meters: Array of [label, value 0..1, color, text]
func set_meters(meters: Array) -> void:
	while _meters.get_child_count() < meters.size() * 2:
		var l := UiTheme.label("", 18)
		_meters.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(240, 18)
		bar.show_percentage = false
		bar.max_value = 1.0
		_meters.add_child(bar)
	for i in _meters.get_child_count() / 2:
		var l := _meters.get_child(i * 2) as Label
		var bar := _meters.get_child(i * 2 + 1) as ProgressBar
		var on := i < meters.size()
		l.visible = on
		bar.visible = on
		if not on:
			continue
		var m: Array = meters[i]
		l.text = "%s  %s" % [m[0], m[3]]
		bar.value = float(m[1])
		var fill := StyleBoxFlat.new()
		fill.bg_color = m[2]
		fill.set_corner_radius_all(6)
		bar.add_theme_stylebox_override("fill", fill)


# --- dough to the face -------------------------------------------------------------------------

var _splat_t := 0.0


func splat() -> void:
	_splat.visible = true
	_splat_t = 1.8
	_splat.queue_redraw()


func _process(delta: float) -> void:
	if _splat_t > 0.0:
		_splat_t -= delta
		_splat.modulate.a = clampf(_splat_t / 0.6, 0.0, 1.0)
		if _splat_t <= 0.0:
			_splat.visible = false


func _draw_splat() -> void:
	var c := _splat.size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var r := minf(_splat.size.x, _splat.size.y) * 0.42
	_splat.draw_circle(c, r, Color("#efd9a8"))
	for k in 14:
		var a := TAU * k / 14.0
		var d := r * rng.randf_range(0.85, 1.15)
		_splat.draw_circle(c + Vector2(cos(a), sin(a)) * d, r * rng.randf_range(0.18, 0.32), Color("#efd9a8"))
	_splat.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.12, Color("#f8ecd0"))
	var f := Toon.goofy_font()
	_splat.draw_string(f, c + Vector2(-r * 0.6, 20), "DOUGH IN FACE", HORIZONTAL_ALIGNMENT_CENTER, r * 1.2, 42, Color("#8b5e3c"))
