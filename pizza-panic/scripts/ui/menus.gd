class_name Menus
extends CanvasLayer
## Title screen, pause menu, settings, the end-of-day report and the upgrade shop.

signal start_requested(new_game: bool)
signal next_day_requested
signal resume_requested
signal title_requested

var _root: Control
var _title: Control
var _pause: Control
var _settings: Control
var _results: Control
var _shop: Control
var _results_body: Label
var _logo: Label
var _continue_btn: Button
var _return_to: Control
var _test_status: Label
var _shop_list: VBoxContainer
var _shop_money: Label
var _shop_from_results := false

# settings widgets
var _mode: OptionButton
var _voice: OptionButton
var _reply: OptionButton
var _anthropic: LineEdit
var _openai: LineEdit
var _eleven: LineEdit
var _model: LineEdit
var _master: HSlider
var _voice_vol: HSlider
var _music_vol: HSlider
var _hints: CheckBox

const MODES := ["auto", "offline", "direct"]
const MODE_NAMES := ["Auto (AI if keys are set)", "Offline (no AI, free)", "AI with my own API keys"]
const VOICES := ["auto", "openai", "elevenlabs", "system", "babble"]
const VOICE_NAMES := ["Auto", "OpenAI voices (acting!)", "ElevenLabs (most realistic)", "Computer robot voice", "Gibberish babble"]
const REPLIES := ["voice", "text"]
const REPLY_NAMES := ["Voice + text (they talk out loud)", "Text only (they text back, cheaper)"]


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
	_build_shop()
	show_title()


# --- screens ------------------------------------------------------------------------------

func show_title() -> void:
	_hide_all()
	_title.visible = true
	_continue_btn.visible = Game.has_save()
	_continue_btn.text = "CONTINUE (Day %d, $%d)" % [Game.day, Game.money]


func show_pause() -> void:
	_hide_all()
	_pause.visible = true


func show_results(s: Dictionary) -> void:
	_hide_all()
	_results.visible = true
	var rep_delta: float = s.rep_end - s.rep_start
	_results_body.text = "Pizzas delivered: %d  (perfect: %d)\nBotched / stolen / never delivered: %d\nMissed phone calls: %d\n\nMoney made: $%d  (tips: $%d)\nIngredients: -$%d\nStaff wages: -$%d  (they made %d pizzas)\nReputation: %.1f stars (%s%.1f)\n\nBank account: $%d\n\nRANK: %s" % [
		s.delivered, s.perfect, s.failed, s.missed_calls, s.earned, s.tips, s.costs, int(s.get("wages", 0)), int(s.get("staff_made", 0)), s.rep_end,
		"+" if rep_delta >= 0 else "", rep_delta, s.money, s.rank]


func open_shop(from_results := false) -> void:
	_shop_from_results = from_results
	_hide_all()
	_shop.visible = true
	_refresh_shop()


func hide_menus() -> void:
	_hide_all()


func is_open() -> bool:
	for c in [_title, _pause, _settings, _results, _shop]:
		if c.visible:
			return true
	return false


func _hide_all() -> void:
	for c in [_title, _pause, _settings, _results, _shop]:
		if c:
			c.visible = false


func _process(_delta: float) -> void:
	if _logo and _title.visible:
		var t := Time.get_ticks_msec() / 1000.0
		_logo.rotation = sin(t * 2.0) * 0.04
		_logo.scale = Vector2.ONE * (1.0 + sin(t * 3.3) * 0.03)


# --- builders ---------------------------------------------------------------------------------

func _screen(dim := true) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(c)
	if dim:
		var bg := ColorRect.new()
		bg.color = Color(0.1, 0.05, 0.12, 0.6)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.add_child(bg)
	return c


func _center_column(parent: Control, width := 560) -> VBoxContainer:
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
	b.custom_minimum_size.y = 60
	b.pressed.connect(_on_button.bind(cb))
	parent.add_child(b)
	return b


func _on_button(cb: Callable) -> void:
	Sfx.play("click")
	cb.call()


func _build_title() -> void:
	_title = _screen(false)
	var v := _center_column(_title, 680)
	_logo = UiTheme.label("PIZZA PANIC!", 124, UiTheme.YELLOW, 28)
	_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.pivot_offset = Vector2(340, 70)
	v.add_child(_logo)
	var sub := UiTheme.label("you are an egg. you deliver pizza. the customers are worse.", 28, Color.WHITE, 10)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(Control.new())
	_continue_btn = _button(v, "CONTINUE", func(): start_requested.emit(false))
	_continue_btn.add_theme_font_size_override("font_size", 34)
	_button(v, "NEW GAME", func(): start_requested.emit(true)).add_theme_font_size_override("font_size", 30)
	_button(v, "Settings / AI Voice Setup", func(): _open_settings(_title))
	_button(v, "Quit", func(): get_tree().quit())


func _build_pause() -> void:
	_pause = _screen()
	var v := _center_column(_pause)
	var t := UiTheme.label("PAUSED", 80, UiTheme.YELLOW, 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_button(v, "Resume", func(): resume_requested.emit())
	_button(v, "Upgrades", func(): open_shop(false))
	_button(v, "Settings", func(): _open_settings(_pause))
	_button(v, "Save & Quit to Title", func(): title_requested.emit())


func _build_results() -> void:
	_results = _screen()
	var v := _center_column(_results, 700)
	var t := UiTheme.label("CLOSING TIME!", 84, UiTheme.YELLOW, 22)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var panel := PanelContainer.new()
	v.add_child(panel)
	_results_body = UiTheme.label("", 26)
	_results_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_results_body)
	_button(v, "Spend money on upgrades", func(): open_shop(true))
	_button(v, "Start the next day", func(): next_day_requested.emit())
	_button(v, "Save & Quit to Title", func(): title_requested.emit())


func _build_shop() -> void:
	_shop = _screen()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	head.add_child(UiTheme.label("TONY'S PC  ·  UPGRADES & HIRING", 40, UiTheme.RED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_shop_money = UiTheme.label("", 36, Color("#2a9d8f"))
	head.add_child(_shop_money)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1000, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_shop_list = VBoxContainer.new()
	_shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_shop_list)
	_button(outer, "Done", _close_shop)


func _refresh_shop() -> void:
	_shop_money.text = "$%d" % Game.money
	for c in _shop_list.get_children():
		c.queue_free()
	var cat := ""
	for id: String in Upgrades.LIST:
		var u: Dictionary = Upgrades.LIST[id]
		if u.cat != cat:
			cat = u.cat
			_shop_list.add_child(UiTheme.label(cat.to_upper(), 30, UiTheme.RED))
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiTheme.box(Color("#fffdf5"), 3, 12, 12))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var lv := Game.level(id)
		var max_lv := int(u.levels)
		info.add_child(UiTheme.label("%s  %s" % [u.name, "(level %d/%d)" % [lv, max_lv]], 24))
		var d := UiTheme.label(u.desc, 17, Color(UiTheme.INK, 0.75))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD
		d.custom_minimum_size.x = 700
		info.add_child(d)
		var b := Button.new()
		b.custom_minimum_size = Vector2(180, 56)
		if Upgrades.maxed(id, lv):
			b.text = "MAXED"
			b.disabled = true
		else:
			var cost := Upgrades.cost(id, lv)
			b.text = "BUY $%d" % cost
			b.disabled = cost > Game.money
			b.pressed.connect(_buy.bind(id))
		h.add_child(b)
		_shop_list.add_child(row)
	_staff_rows()


## Hire eggs to cook and answer the phone. Wages are paid at closing time.
func _staff_rows() -> void:
	_shop_list.add_child(UiTheme.label("HIRE STAFF  (wages today: $%d/day)" % Game.wages_total(), 30, UiTheme.RED))
	var hint := UiTheme.label("Cooks make whole pizzas by themselves and put them on the pass shelf. Phone eggs take orders. Wages come out at closing time.", 17, Color(UiTheme.INK, 0.75))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.custom_minimum_size.x = 900
	_shop_list.add_child(hint)
	for id: String in StaffData.CANDIDATES:
		var c: Dictionary = StaffData.CANDIDATES[id]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiTheme.box(Color("#f1fff7") if Game.is_hired(id) else Color("#fffdf5"), 3, 12, 12))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var role := "Cook" if c.role == "cook" else "Phones"
		var skill := Game.staff_skill(id) if Game.is_hired(id) else float(c.skill)
		info.add_child(UiTheme.label("%s  ·  %s  ·  skill %d%%  ·  $%d/day%s" % [c.name, role, int(skill * 100), c.wage, "  ·  HIRED" if Game.is_hired(id) else ""], 22))
		var d := UiTheme.label(str(c.pitch), 17, Color(UiTheme.INK, 0.75))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD
		d.custom_minimum_size.x = 640
		info.add_child(d)
		if Game.is_hired(id):
			var lv := int(Game.staff[id].training)
			var tb := Button.new()
			tb.custom_minimum_size = Vector2(150, 50)
			if lv >= StaffData.TRAIN_MAX:
				tb.text = "TRAINED"
				tb.disabled = true
			else:
				var cost := StaffData.TRAIN_COST * (lv + 1)
				tb.text = "TRAIN $%d" % cost
				tb.disabled = cost > Game.money
				tb.pressed.connect(_train.bind(id))
			h.add_child(tb)
			var fb := Button.new()
			fb.custom_minimum_size = Vector2(110, 50)
			fb.text = "FIRE"
			fb.pressed.connect(_fire.bind(id))
			h.add_child(fb)
		else:
			var b := Button.new()
			b.custom_minimum_size = Vector2(180, 56)
			b.text = "HIRE $%d" % int(c.hire)
			b.disabled = int(c.hire) > Game.money
			b.pressed.connect(_hire.bind(id))
			h.add_child(b)
		_shop_list.add_child(row)


func _hire(id: String) -> void:
	Sfx.play("register" if Game.hire(id) else "fail")
	_refresh_shop()


func _train(id: String) -> void:
	Sfx.play("register" if Game.train(id) else "fail")
	_refresh_shop()


func _fire(id: String) -> void:
	Game.fire(id)
	Sfx.play("hangup")
	_refresh_shop()


func _buy(id: String) -> void:
	if Game.buy_upgrade(id):
		Sfx.play("register")
	else:
		Sfx.play("fail")
	_refresh_shop()


func _close_shop() -> void:
	_hide_all()
	if _shop_from_results:
		_results.visible = true
	else:
		resume_requested.emit()


func _build_settings() -> void:
	_settings = _screen()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 720)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	v.add_child(UiTheme.label("SETTINGS", 48, UiTheme.RED))
	v.add_child(_small("Customer brains: Claude (Anthropic). Your voice -> text and their voices: OpenAI and/or ElevenLabs.\nNo keys? Offline mode still works: you type, they answer from a script."))
	_mode = _option(v, "AI mode", MODE_NAMES)
	_anthropic = _field(v, "Anthropic API key (customer brains)", "sk-ant-...", true)
	_openai = _field(v, "OpenAI API key (your voice -> text, and their voices)", "sk-...", true)
	_eleven = _field(v, "ElevenLabs API key (optional, fancier voices)", "", true)
	_reply = _option(v, "How customers answer", REPLY_NAMES)
	_voice = _option(v, "Customer voices", VOICE_NAMES)
	_model = _field(v, "Claude model", "claude-opus-5-5", false)
	_master = _slider(v, "Master volume")
	_voice_vol = _slider(v, "Voice volume")
	_music_vol = _slider(v, "Music volume")
	_hints = CheckBox.new()
	_hints.text = "Show 'what to do next' hints"
	v.add_child(_hints)
	var warn := _small("Keys are saved in plain text on this computer (user://settings.cfg). Never put your keys in a build you share.")
	warn.add_theme_color_override("font_color", UiTheme.RED)
	v.add_child(warn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_button(row, "Save", _save_settings).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "Test AI", _test_ai).size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_return_to = from
	_mode.selected = maxi(0, MODES.find(Settings.ai_mode))
	_voice.selected = maxi(0, VOICES.find(Settings.tts_provider))
	_reply.selected = maxi(0, REPLIES.find(Settings.reply_mode))
	_anthropic.text = Settings.anthropic_key
	_openai.text = Settings.openai_key
	_eleven.text = Settings.elevenlabs_key
	_model.text = Settings.claude_model
	_master.value = Settings.master_volume
	_voice_vol.value = Settings.voice_volume
	_music_vol.value = Settings.music_volume
	_hints.button_pressed = Settings.show_hints
	_test_status.text = "Current mode: %s" % Settings.effective_mode()
	_hide_all()
	_settings.visible = true


func _close_settings() -> void:
	_hide_all()
	if _return_to:
		_return_to.visible = true


func _save_settings() -> void:
	Settings.ai_mode = MODES[_mode.selected]
	Settings.tts_provider = VOICES[_voice.selected]
	Settings.reply_mode = REPLIES[_reply.selected]
	Settings.anthropic_key = _anthropic.text.strip_edges()
	Settings.openai_key = _openai.text.strip_edges()
	Settings.elevenlabs_key = _eleven.text.strip_edges()
	Settings.claude_model = _model.text.strip_edges() if _model.text.strip_edges() != "" else "claude-opus-5-5"
	Settings.master_volume = _master.value
	Settings.voice_volume = _voice_vol.value
	Settings.music_volume = _music_vol.value
	Settings.show_hints = _hints.button_pressed
	Settings.save_settings()
	Sfx.set_music_mood(0.0)
	_test_status.text = "Saved! Mode: %s · replies: %s" % [Settings.effective_mode(), "text only" if Settings.voice_engine() == "none" else Settings.voice_engine()]


func _test_ai() -> void:
	_save_settings()
	if not Settings.has_brain():
		_test_status.text = "No AI configured (mode: %s). Add an Anthropic key." % Settings.effective_mode()
		return
	_test_status.text = "Calling Tony..."
	var brain := ClaudeBrain.new()
	var tts := TextToSpeech.new()
	add_child(brain)
	add_child(tts)
	var r := await brain.think(Characters.TONY, [], "Hi Tony! This is a microphone test. Say hi back.", "You're at your shop. This is a quick test.")
	if r.get("ok", false):
		_test_status.text = "Tony says: \"%s\"" % r.say
		var voice := await tts.synthesize(r.say, Characters.TONY)
		if voice.stream:
			var p := AudioStreamPlayer.new()
			add_child(p)
			p.stream = voice.stream
			p.play()
			p.finished.connect(p.queue_free)
		if tts.last_error != "":
			_test_status.text += "  (voice error: %s)" % tts.last_error.left(160)
	else:
		_test_status.text = "AI test failed: " + str(r.get("error", "unknown")).left(300)
	brain.queue_free()
	tts.queue_free()
