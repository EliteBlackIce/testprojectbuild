class_name Menus
extends CanvasLayer
## Title screen, pause menu, settings and the end-of-shift report.

signal start_requested
signal resume_requested
signal title_requested

var _root: Control
var _title: Control
var _pause: Control
var _settings: Control
var _results: Control
var _results_body: Label
var _logo: Label
var _settings_return: Control
var _test_status: Label

# settings widgets
var _mode: OptionButton
var _voice: OptionButton
var _anthropic: LineEdit
var _openai: LineEdit
var _eleven: LineEdit
var _proxy_url: LineEdit
var _proxy_token: LineEdit
var _model: LineEdit
var _master: HSlider
var _voice_vol: HSlider

const MODES := ["auto", "offline", "direct", "proxy"]
const MODE_NAMES := ["Auto (AI if keys are set)", "Offline (no AI, free)", "Direct (my own API keys)", "Game server (Steam release)"]
const VOICES := ["auto", "openai", "elevenlabs", "system", "babble"]
const VOICE_NAMES := ["Auto", "OpenAI voices (acting!)", "ElevenLabs (most realistic)", "Computer robot voice", "Gibberish babble"]


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_title()
	_build_pause()
	_build_settings()
	_build_results()
	show_title()


# --- screens ------------------------------------------------------------------------

func show_title() -> void:
	_hide_all()
	_title.visible = true


func show_pause() -> void:
	_hide_all()
	_pause.visible = true


func show_results(summary: Dictionary) -> void:
	_hide_all()
	_results.visible = true
	_results_body.text = "Money made: $%d\nPizzas delivered: %d\nPizzas botched/stolen: %d\nBiggest tip: $%d\n\nRANK: %s" % [
		summary.money, summary.deliveries, summary.failed, summary.best_tip, summary.rank]


func hide_menus() -> void:
	_hide_all()


func is_open() -> bool:
	return _title.visible or _pause.visible or _settings.visible or _results.visible


func _hide_all() -> void:
	for c in [_title, _pause, _settings, _results]:
		if c:
			c.visible = false


func _process(_delta: float) -> void:
	if _logo and _title.visible:
		var t := Time.get_ticks_msec() / 1000.0
		_logo.rotation = sin(t * 2.0) * 0.04
		_logo.scale = Vector2.ONE * (1.0 + sin(t * 3.3) * 0.03)


# --- builders ---------------------------------------------------------------------------

func _screen(dim := true) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(c)
	if dim:
		var bg := ColorRect.new()
		bg.color = Color(0.1, 0.05, 0.15, 0.55)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.add_child(bg)
	return c


func _center_column(parent: Control, width := 520) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = width
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	return v


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 64
	b.pressed.connect(_on_button.bind(cb))
	parent.add_child(b)
	return b


func _on_button(cb: Callable) -> void:
	Sfx.play("click")
	cb.call()


func _build_title() -> void:
	_title = _screen(false)
	var v := _center_column(_title, 640)
	_logo = UiTheme.label("PIZZA PANIC!", 120, UiTheme.YELLOW, 28)
	_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.pivot_offset = Vector2(320, 70)
	v.add_child(_logo)
	var sub := UiTheme.label("a game about pizza and poor decisions", 30, Color.WHITE, 10)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(Control.new())
	var start := _button(v, "START SHIFT", func(): start_requested.emit())
	start.add_theme_font_size_override("font_size", 38)
	_button(v, "Settings / AI Voice Setup", func(): _open_settings(_title))
	if not OS.has_feature("web"):
		_button(v, "Quit", func(): get_tree().quit())
	var tip := UiTheme.label("Hold T to talk to people with your real voice.\nThey will be weird about it.", 22, Color.WHITE, 8)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tip)


func _build_pause() -> void:
	_pause = _screen()
	var v := _center_column(_pause)
	var t := UiTheme.label("PAUSED", 80, UiTheme.YELLOW, 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_button(v, "Resume", func(): resume_requested.emit())
	_button(v, "Settings", func(): _open_settings(_pause))
	_button(v, "Quit to Title", func(): title_requested.emit())


func _build_results() -> void:
	_results = _screen()
	var v := _center_column(_results, 640)
	var t := UiTheme.label("SHIFT OVER!", 90, UiTheme.YELLOW, 22)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var panel := PanelContainer.new()
	v.add_child(panel)
	_results_body = UiTheme.label("", 30)
	_results_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_results_body)
	_button(v, "Work Another Shift", func(): start_requested.emit())
	_button(v, "Title Screen", func(): title_requested.emit())


func _build_settings() -> void:
	_settings = _screen()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 720)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)

	v.add_child(UiTheme.label("SETTINGS", 48, UiTheme.RED))
	v.add_child(_small("AI brains: Claude (Anthropic). Your voice -> text + NPC voices: OpenAI and/or ElevenLabs.\nNo keys? Offline mode still works: type to talk, NPCs speak gibberish."))

	_mode = _option(v, "AI mode", MODE_NAMES)
	_anthropic = _field(v, "Anthropic API key (NPC brains)", "sk-ant-...", true)
	_openai = _field(v, "OpenAI API key (your voice -> text, NPC voices)", "sk-...", true)
	_eleven = _field(v, "ElevenLabs API key (optional, fancier voices)", "", true)
	_voice = _option(v, "NPC voices", VOICE_NAMES)
	_model = _field(v, "Claude model", "claude-opus-5-5", false)
	v.add_child(_small("Game server mode (for the Steam release): the game talks to YOUR server, which holds the keys. See server/README.md."))
	_proxy_url = _field(v, "Game server URL", "https://pizza-panic-ai.yourname.workers.dev", false)
	_proxy_token = _field(v, "Game server token", "", true)
	_master = _slider(v, "Master volume")
	_voice_vol = _slider(v, "NPC voice volume")
	var warn := _small("Keys are saved in plain text on this computer (user://settings.cfg). Never put your keys in a build you share.")
	warn.add_theme_color_override("font_color", UiTheme.RED)
	v.add_child(warn)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_button(row, "Save", _save_settings).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "Test AI + Voice", _test_ai).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "Back", _close_settings).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_test_status = _small("")
	v.add_child(_test_status)


func _small(text: String) -> Label:
	var l := UiTheme.label(text, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 840
	return l


func _field(parent: Control, label_text: String, placeholder: String, secret: bool) -> LineEdit:
	parent.add_child(UiTheme.label(label_text, 20))
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size.x = 840
	parent.add_child(e)
	return e


func _option(parent: Control, label_text: String, names: Array) -> OptionButton:
	parent.add_child(UiTheme.label(label_text, 20))
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	parent.add_child(o)
	return o


func _slider(parent: Control, label_text: String) -> HSlider:
	parent.add_child(UiTheme.label(label_text, 20))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(840, 28)
	parent.add_child(s)
	return s


func _open_settings(from: Control) -> void:
	_settings_return = from
	_mode.selected = maxi(0, MODES.find(Settings.ai_mode))
	_voice.selected = maxi(0, VOICES.find(Settings.tts_provider))
	_anthropic.text = Settings.anthropic_key
	_openai.text = Settings.openai_key
	_eleven.text = Settings.elevenlabs_key
	_model.text = Settings.claude_model
	_proxy_url.text = Settings.proxy_url
	_proxy_token.text = Settings.proxy_token
	_master.value = Settings.master_volume
	_voice_vol.value = Settings.voice_volume
	_test_status.text = "Current mode: %s" % Settings.effective_mode()
	_hide_all()
	_settings.visible = true


func _close_settings() -> void:
	_hide_all()
	if _settings_return:
		_settings_return.visible = true


func _save_settings() -> void:
	Settings.ai_mode = MODES[_mode.selected]
	Settings.tts_provider = VOICES[_voice.selected]
	Settings.anthropic_key = _anthropic.text.strip_edges()
	Settings.openai_key = _openai.text.strip_edges()
	Settings.elevenlabs_key = _eleven.text.strip_edges()
	Settings.claude_model = _model.text.strip_edges() if _model.text.strip_edges() != "" else "claude-opus-5-5"
	Settings.proxy_url = _proxy_url.text.strip_edges()
	Settings.proxy_token = _proxy_token.text.strip_edges()
	Settings.master_volume = _master.value
	Settings.voice_volume = _voice_vol.value
	Settings.save_settings()
	_test_status.text = "Saved! Mode: %s · voice: %s" % [Settings.effective_mode(), Settings.voice_engine()]


func _test_ai() -> void:
	_save_settings()
	if not Settings.has_brain():
		_test_status.text = "No AI brain configured (mode: %s). Add an Anthropic key or game server URL." % Settings.effective_mode()
		return
	_test_status.text = "Asking Tony to say hi..."
	var brain := ClaudeBrain.new()
	var tts := TextToSpeech.new()
	add_child(brain)
	add_child(tts)
	var r := await brain.think(Characters.TONY, [], "Hi Tony! This is a microphone test. Say hi back.", "You're at your shop. This is a quick test.")
	if r.get("ok", false):
		_test_status.text = "Tony says: \"%s\" (generating voice...)" % r.say
		var voice := await tts.synthesize(r.say, Characters.TONY)
		if voice.stream:
			var p := AudioStreamPlayer.new()
			add_child(p)
			p.stream = voice.stream
			p.play()
			p.finished.connect(p.queue_free)
		_test_status.text = "Tony says: \"%s\"  (voice: %s%s)" % [r.say, Settings.voice_engine(),
			"" if tts.last_error == "" else ", voice error: " + tts.last_error.left(120)]
	else:
		_test_status.text = "AI test failed: " + str(r.get("error", "unknown")).left(300)
	brain.queue_free()
	tts.queue_free()
