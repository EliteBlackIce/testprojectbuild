class_name DialogueUi
extends CanvasLayer
## Anime visual-novel style dialogue box with push-to-talk + typing.

signal player_typed(text: String)
signal talk_pressed
signal talk_released
signal leave_pressed

var mic_level_source: Callable

var _root: Control
var _box: PanelContainer
var _name: Label
var _title: Label
var _text: RichTextLabel
var _you: Label
var _status: Label
var _input: LineEdit
var _mic_btn: Button
var _meter: ProgressBar
var _hint: Label
var _typing_tween: Tween
var _listening := false
var _note: PanelContainer
var _note_label: Label


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.get_theme()
	add_child(_root)

	_box = PanelContainer.new()
	_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_box.offset_left = -620
	_box.offset_right = 620
	_box.offset_top = -330
	_box.offset_bottom = -24
	_box.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.105, 0.075, 0.17, 0.94), 22, 22))
	_root.add_child(_box)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_box.add_child(v)

	var name_row := HBoxContainer.new()
	v.add_child(name_row)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.PINK, 12, 16, 4))
	name_row.add_child(plate)
	_name = UiTheme.label("NAME", UiTheme.HEADING, UiTheme.INK)
	plate.add_child(_name)
	_title = UiTheme.label("", 18, UiTheme.MUTED)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(spacer)
	var leave := Button.new()
	leave.text = "Leave  (Esc)"
	leave.theme_type_variation = "Ghost"
	leave.pressed.connect(func(): leave_pressed.emit())
	name_row.add_child(leave)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(0, 90)
	_text.add_theme_font_size_override("normal_font_size", 30)
	_text.add_theme_color_override("default_color", UiTheme.TEXT)
	_text.scroll_active = false
	v.add_child(_text)

	_you = UiTheme.label("", 20, UiTheme.BLUE)
	_you.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_you)

	_status = UiTheme.label("", 17, UiTheme.PURPLE)
	v.add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_mic_btn = Button.new()
	_mic_btn.text = "Hold T to talk"
	_mic_btn.custom_minimum_size = Vector2(230, 0)
	_mic_btn.button_down.connect(func(): talk_pressed.emit())
	_mic_btn.button_up.connect(func(): talk_released.emit())
	row.add_child(_mic_btn)
	_meter = ProgressBar.new()
	_meter.show_percentage = false
	_meter.custom_minimum_size = Vector2(70, 18)
	_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_meter.max_value = 1.0
	row.add_child(_meter)
	_input = LineEdit.new()
	_input.placeholder_text = "...or type here and press Enter"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(_on_submit)
	row.add_child(_input)
	var send := Button.new()
	send.text = "Say it"
	send.pressed.connect(func(): _on_submit(_input.text))
	row.add_child(send)

	_hint = UiTheme.label("", 15, UiTheme.MUTED)
	v.add_child(_hint)
	# Notepad: the order, written down the moment they place it
	_note = PanelContainer.new()
	_note.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_note.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_note.offset_left = 330
	_note.offset_right = 620
	_note.offset_bottom = -344
	_note.add_theme_stylebox_override("panel", UiTheme.flat(Color("#fff4dc"), 10, 16, 12, Color("#3b2a22"), 2))
	_root.add_child(_note)
	_note_label = UiTheme.label("", 18, Color("#2b1c18"))
	_note.add_child(_note_label)
	_note.visible = false
	visible = false


func open(npc_name: String, npc_title: String, voice_ok: bool, phone := false) -> void:
	visible = true
	_note.visible = false
	_box.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.07, 0.17, 0.17, 0.95) if phone else Color(0.105, 0.075, 0.17, 0.94), 22, 22))
	_name.text = npc_name
	_title.text = "  " + npc_title
	_text.text = ""
	_you.text = ""
	_status.text = ""
	_input.text = ""
	_mic_btn.disabled = not voice_ok
	_mic_btn.text = "Hold T to talk" if voice_ok else "No mic (offline)"
	_meter.visible = voice_ok
	if phone:
		_hint.text = "They're ordering! Write it down in your head... (it's also added to your tickets). Esc = hang up."
	elif voice_ok:
		_hint.text = "Talk to them like a real person. Play along with their weirdness to get paid."
	else:
		_hint.text = "Type to talk (add API keys in Settings to use your voice + AI brains)."
	_box.scale = Vector2(1, 0.2)
	_box.pivot_offset = Vector2(620, 300)
	var tw := create_tween()
	tw.tween_property(_box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	_input.release_focus()
	visible = false


func is_typing() -> bool:
	return visible and _input.has_focus()


func show_npc_line(npc_name: String, text: String) -> void:
	_name.text = npc_name
	_text.text = _format(text)
	_text.visible_ratio = 0.0
	if _typing_tween:
		_typing_tween.kill()
	_typing_tween = create_tween()
	_typing_tween.tween_property(_text, "visible_ratio", 1.0, clampf(text.length() * 0.025, 0.2, 2.0))
	Sfx.play("blip", randf_range(0.9, 1.2), -10.0)


func show_player_line(text: String) -> void:
	_you.text = "You: \"%s\"" % text


## The order, written down on a notepad next to the conversation.
func show_order(id: int, who: String, order: Dictionary) -> void:
	var lines: PackedStringArray = ["ORDER #%d  (%s)" % [id, who], "%s, %s sauce" % [str(Menu.SIZES[order.get("size", "medium")].label), Menu.SAUCES[order.get("sauce", "tomato")].label]]
	var tops: Array = order.get("toppings", [])
	if tops.is_empty():
		lines.append("- plain cheese")
	for tp in tops:
		lines.append("- " + str(Menu.TOPPINGS[tp].label))
	_note_label.text = "\n".join(lines)
	_note.visible = true


func set_status(text: String) -> void:
	_status.text = text


func set_listening(on: bool) -> void:
	_listening = on
	_mic_btn.text = "LISTENING..." if on else "Hold T to talk"
	_status.text = "Talk now! Let go of T when you're done." if on else _status.text


func _on_submit(text: String) -> void:
	if text.strip_edges() == "":
		return
	_input.text = ""
	player_typed.emit(text)


func _process(_delta: float) -> void:
	if visible and mic_level_source.is_valid():
		_meter.value = lerpf(_meter.value, mic_level_source.call() if _listening else 0.0, 0.4)


## *actions* become italic purple.
static func _format(text: String) -> String:
	var safe := text.replace("[", "(").replace("]", ")")
	var rx := RegEx.create_from_string("\\*([^*]+)\\*")
	return rx.sub(safe, "[i][color=#b69bff]$1[/color][/i]", true)
