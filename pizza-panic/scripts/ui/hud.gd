class_name Hud
extends CanvasLayer
## Money, shift clock, current order, pizza health, toasts and prompts.

var _money: Label
var _clock: Label
var _deliveries: Label
var _order_box: PanelContainer
var _order_title: Label
var _order_pizza: Label
var _timer_bar: ProgressBar
var _timer_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _prompt: Label
var _toast: Label
var _mode_badge: Label
var _toast_tween: Tween


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)

	# Top-left: money + clock
	var stats := PanelContainer.new()
	stats.position = Vector2(20, 20)
	root.add_child(stats)
	var sv := VBoxContainer.new()
	stats.add_child(sv)
	_money = UiTheme.label("$0", 44, Color("#2a9d8f"))
	_deliveries = UiTheme.label("0 delivered", 20)
	_clock = UiTheme.label("Shift: 7:00", 22)
	for l in [_money, _deliveries, _clock]:
		sv.add_child(l)

	# Top-right: order card
	_order_box = PanelContainer.new()
	_order_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_order_box.offset_left = -380
	_order_box.offset_right = -20
	_order_box.offset_top = 20
	root.add_child(_order_box)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 6)
	_order_box.add_child(ov)
	_order_title = UiTheme.label("NO PIZZA", 30, UiTheme.RED)
	_order_pizza = UiTheme.label("Go to Tony's Pizza and press E", 18)
	_order_pizza.autowrap_mode = TextServer.AUTOWRAP_WORD
	_order_pizza.custom_minimum_size.x = 320
	ov.add_child(_order_title)
	ov.add_child(_order_pizza)
	_timer_label = UiTheme.label("", 18)
	ov.add_child(_timer_label)
	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size.y = 18
	ov.add_child(_timer_bar)
	_hp_label = UiTheme.label("Pizza condition", 18)
	ov.add_child(_hp_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size.y = 18
	ov.add_child(_hp_bar)

	# Bottom: interaction prompt
	_prompt = UiTheme.label("", 30, Color.WHITE, 10)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.offset_left = -400
	_prompt.offset_right = 400
	_prompt.offset_top = -120
	_prompt.offset_bottom = -70
	root.add_child(_prompt)

	# Center: toasts
	_toast = UiTheme.label("", 54, UiTheme.YELLOW, 16)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.offset_left = -600
	_toast.offset_right = 600
	_toast.offset_top = 120
	_toast.offset_bottom = 200
	_toast.pivot_offset = Vector2(600, 40)
	root.add_child(_toast)

	_mode_badge = UiTheme.label("", 16, Color.WHITE, 6)
	_mode_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_mode_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_badge.offset_left = -700
	_mode_badge.offset_right = -16
	_mode_badge.offset_top = -40
	_mode_badge.offset_bottom = -12
	root.add_child(_mode_badge)

	var help := UiTheme.label("WASD drive · SPACE hop · H honk · E talk · R unflip · ESC pause", 16, Color.WHITE, 6)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 16
	help.offset_right = 900
	help.offset_top = -40
	help.offset_bottom = -12
	root.add_child(help)

	Game.money_changed.connect(_on_money)
	Game.toast.connect(show_toast)
	Settings.changed.connect(_update_badge)
	_update_badge()


func _update_badge() -> void:
	var mode := Settings.effective_mode()
	var text := ""
	match mode:
		"offline":
			text = "OFFLINE MODE: scripted NPCs, type to talk (add keys in Settings for AI)"
		"proxy":
			text = "AI: Claude via game server · voice: " + Settings.voice_engine()
		_:
			text = "AI: Claude%s · voice: %s" % [" + voice chat" if Settings.has_speech_to_text() else " (type to talk)", Settings.voice_engine()]
	_mode_badge.text = text


func set_prompt(text: String) -> void:
	_prompt.text = text


func show_toast(text: String, color := UiTheme.YELLOW) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	_toast.scale = Vector2(0.3, 0.3)
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _on_money(total: int, delta: int) -> void:
	_money.text = "$%d" % total
	if delta > 0:
		var tw := create_tween()
		_money.pivot_offset = _money.size * 0.5
		tw.tween_property(_money, "scale", Vector2(1.4, 1.4), 0.1)
		tw.tween_property(_money, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BOUNCE)


func _process(_delta: float) -> void:
	var left := Game.time_left_in_shift()
	_clock.text = "Shift: %d:%02d" % [floori(left / 60.0), int(left) % 60]
	_deliveries.text = "%d delivered · %d botched" % [Game.deliveries, Game.failed]
	if Game.has_order():
		var o := Game.order
		var secs := Game.order_seconds_left()
		_order_title.text = "DELIVER TO #%d" % o.house.number
		_order_pizza.text = str(o.pizza)
		_timer_bar.visible = true
		_hp_bar.visible = true
		_hp_label.visible = true
		_timer_bar.max_value = o.time_limit
		_timer_bar.value = maxf(secs, 0.0)
		if secs >= 0.0:
			_timer_label.text = "%d seconds left" % int(ceil(secs))
			_timer_label.add_theme_color_override("font_color", UiTheme.INK)
		else:
			_timer_label.text = "LATE!!! (%ds)" % int(-secs)
			_timer_label.add_theme_color_override("font_color", UiTheme.RED)
		_hp_bar.value = Game.pizza_hp
		_hp_label.text = "Pizza condition: %s" % _pizza_face(Game.pizza_hp)
	else:
		_order_title.text = "NO PIZZA"
		_order_pizza.text = "Go to Tony's Pizza (big spinning pizza) and press E"
		_timer_label.text = ""
		_timer_bar.visible = false
		_hp_bar.visible = false
		_hp_label.visible = false


static func _pizza_face(hp: float) -> String:
	if hp > 85.0:
		return "pristine"
	if hp > 60.0:
		return "a little smushed"
	if hp > 35.0:
		return "cheese has relocated"
	if hp > 10.0:
		return "pizza soup"
	return "it's a cube now"
