class_name Hud
extends CanvasLayer
## Money, clock, reputation, order tickets, the ringing phone, prompts, toasts.

var phone: PhoneLine
var car: PizzaCar
var player: PlayerEgg

var _money: Label
var _clock: Label
var _stars: StarBar
var _tickets_box: VBoxContainer
var _phone_banner: PanelContainer
var _phone_label: Label
var _prompt: Label
var _toast: Label
var _carry: Label
var _boost: ProgressBar
var _mode_badge: Label
var _hint: Label
var _toast_tween: Tween
var _toast_queue: Array = []
var _toast_busy := false
var _cross: Control
var crosshair_on := true
var crosshair_hot := false


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)

	# Top-left: money, clock, reputation
	var stats := PanelContainer.new()
	stats.position = Vector2(20, 20)
	root.add_child(stats)
	var sv := VBoxContainer.new()
	stats.add_child(sv)
	_money = UiTheme.label("$0", 44, Color("#2a9d8f"))
	_clock = UiTheme.label("", 24)
	_stars = StarBar.new()
	for l in [_money, _clock, _stars]:
		sv.add_child(l)
	_hint = UiTheme.label("", 19, Color("#8338ec"))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint.custom_minimum_size.x = 260
	sv.add_child(_hint)

	# Right: tickets
	var tickets_panel := PanelContainer.new()
	tickets_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tickets_panel.offset_left = -360
	tickets_panel.offset_right = -20
	tickets_panel.offset_top = 104
	root.add_child(tickets_panel)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	tickets_panel.add_child(tv)
	tv.add_child(UiTheme.label("ORDERS", 26, UiTheme.RED))
	_tickets_box = VBoxContainer.new()
	_tickets_box.add_theme_constant_override("separation", 6)
	tv.add_child(_tickets_box)

	# Phone banner
	_phone_banner = PanelContainer.new()
	_phone_banner.add_theme_stylebox_override("panel", UiTheme.box(Color("#ffd166"), 5, 18, 16))
	_phone_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phone_banner.offset_left = -300
	_phone_banner.offset_right = 300
	_phone_banner.offset_top = 20
	root.add_child(_phone_banner)
	_phone_label = UiTheme.label("", 28)
	_phone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phone_banner.add_child(_phone_label)
	_phone_banner.visible = false

	# Crosshair: a little dot that puffs up into a ring when you're aiming at something usable
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	root.add_child(_cross)

	_prompt = UiTheme.label("", 28, Color.WHITE, 10)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.offset_left = -500
	_prompt.offset_right = 500
	_prompt.offset_top = 34
	_prompt.offset_bottom = 80
	root.add_child(_prompt)

	_carry = UiTheme.label("", 22, Color.WHITE, 8)
	_carry.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_carry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_carry.offset_left = -500
	_carry.offset_right = 500
	_carry.offset_top = -78
	_carry.offset_bottom = -48
	root.add_child(_carry)

	_boost = ProgressBar.new()
	_boost.show_percentage = false
	_boost.max_value = 1.0
	_boost.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_boost.offset_left = -120
	_boost.offset_right = 120
	_boost.offset_top = -40
	_boost.offset_bottom = -22
	root.add_child(_boost)

	_toast = UiTheme.label("", 46, UiTheme.YELLOW, 14)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD
	_toast.offset_left = -650
	_toast.offset_right = 650
	_toast.offset_top = 110
	_toast.offset_bottom = 230
	_toast.pivot_offset = Vector2(650, 50)
	root.add_child(_toast)

	_mode_badge = UiTheme.label("", 16, Color.WHITE, 6)
	_mode_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_mode_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_badge.offset_left = -760
	_mode_badge.offset_right = -16
	_mode_badge.offset_top = -40
	_mode_badge.offset_bottom = -12
	root.add_child(_mode_badge)

	var help := UiTheme.label("MOUSE look · WASD walk · E / CLICK use · CLICK poke/throw · RIGHT CLICK grab props · F car · V car camera · SPACE hop · T talk · Q phone (headset) · H honk · ESC pause", 16, Color.WHITE, 6)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 16
	help.offset_right = 1100
	help.offset_top = -40
	help.offset_bottom = -12
	root.add_child(help)

	Game.money_changed.connect(_on_money)
	Game.toast.connect(show_toast)
	Game.tickets_changed.connect(_rebuild_tickets)
	Settings.changed.connect(_update_badge)
	_update_badge()
	_on_money(Game.money, 0)


func _update_badge() -> void:
	match Settings.effective_mode():
		"offline":
			_mode_badge.text = "OFFLINE: scripted customers, type to talk (add keys in Settings for AI)"
		"proxy":
			_mode_badge.text = "AI via game server · replies: " + Settings.voice_engine()
		_:
			_mode_badge.text = "AI: Claude%s · replies: %s" % [" + voice chat" if Settings.has_speech_to_text() else " (type to talk)", "text only" if Settings.voice_engine() == "none" else Settings.voice_engine()]


func set_hint(text: String) -> void:
	_hint.text = ("NEXT: " + text) if text != "" and Settings.show_hints else ""
	_hint.visible = _hint.text != ""


func set_prompt(text: String) -> void:
	_prompt.text = text
	if crosshair_hot != (text != ""):
		crosshair_hot = text != ""
		_cross.queue_redraw()


func set_crosshair(on: bool) -> void:
	if crosshair_on != on:
		crosshair_on = on
		_cross.queue_redraw()


func _draw_cross() -> void:
	if not crosshair_on:
		return
	if crosshair_hot:
		_cross.draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, UiTheme.INK, 6.0)
		_cross.draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, UiTheme.YELLOW, 3.0)
	else:
		_cross.draw_circle(Vector2.ZERO, 5.0, UiTheme.INK)
		_cross.draw_circle(Vector2.ZERO, 3.0, Color.WHITE)


func show_toast(text: String, color := UiTheme.YELLOW) -> void:
	_toast_queue.append([text, color])
	if not _toast_busy:
		_next_toast()


func _next_toast() -> void:
	if _toast_queue.is_empty():
		_toast_busy = false
		return
	_toast_busy = true
	var item: Array = _toast_queue.pop_front()
	_toast.text = item[0]
	_toast.add_theme_color_override("font_color", item[1])
	_toast.modulate.a = 1.0
	_toast.scale = Vector2(0.3, 0.3)
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(1.4 if _toast_queue.is_empty() else 0.8)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(_next_toast)


func _on_money(total: int, delta: int) -> void:
	_money.text = "$%d" % total
	if delta > 0:
		var tw := create_tween()
		_money.pivot_offset = _money.size * 0.5
		tw.tween_property(_money, "scale", Vector2(1.4, 1.4), 0.1)
		tw.tween_property(_money, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BOUNCE)


const STATUS_TEXT := {
	"new": "Needs making!", "making": "Being made", "baking": "In the oven",
	"ready": "Boxed - load the car!", "in_car": "In the car - deliver it!",
}


func _rebuild_tickets() -> void:
	for c in _tickets_box.get_children():
		c.queue_free()
	var open := Game.open_tickets()
	if open.is_empty():
		var l := UiTheme.label("No orders yet.\nWait for the phone!", 18, Color(UiTheme.INK, 0.6))
		_tickets_box.add_child(l)
		return
	for t in open:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiTheme.box(Color("#fffdf5"), 3, 10, 10))
		var v := VBoxContainer.new()
		card.add_child(v)
		var head := UiTheme.label("#%d  %s  (house %d)" % [t.id, t.customer, t.house.number], 18, UiTheme.RED)
		v.add_child(head)
		var body := UiTheme.label(Menu.describe(t.order), 17)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD
		body.custom_minimum_size.x = 300
		v.add_child(body)
		var status := UiTheme.label(STATUS_TEXT.get(t.status, t.status), 16, Color("#8338ec"))
		status.name = "Status"
		v.add_child(status)
		var timer := UiTheme.label("", 16)
		timer.name = "Timer"
		timer.set_meta("ticket", t.id)
		v.add_child(timer)
		_tickets_box.add_child(card)


func _process(_delta: float) -> void:
	_clock.text = "Day %d · %s%s" % [Game.day, Game.clock_text(), "  (last call!)" if Game.is_last_call() and Game.day_running else ""]
	var full := int(floor(Game.reputation))
	_stars.value = Game.reputation
	# Ticket timers
	for card in _tickets_box.get_children():
		var timer := card.find_child("Timer", true, false) as Label
		if timer and timer.has_meta("ticket"):
			var t := Game.ticket(timer.get_meta("ticket"))
			if not t.is_empty():
				var left := Game.minutes_left(t)
				timer.text = ("%d min left" % int(left)) if left >= 0 else "LATE by %d min!" % int(-left)
				timer.add_theme_color_override("font_color", UiTheme.INK if left > 15 else UiTheme.RED)
	# Phone
	if phone and phone.is_ringing():
		_phone_banner.visible = true
		var where := "answer with Q!" if Game.has_upgrade("headset") else "run to the phone!"
		_phone_label.text = "RING RING! %s is calling (%ds) - %s" % [phone.caller.display_name(), int(phone.ring_left), where]
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.015) * 0.04
		_phone_banner.scale = Vector2(pulse, pulse)
		_phone_banner.pivot_offset = _phone_banner.size * 0.5
	else:
		_phone_banner.visible = false
	# Carry / cargo / boost
	var lines: PackedStringArray = []
	if player and player.held is Pizza:
		var p := player.held as Pizza
		var what := "pizza box" if p.is_boxed() else ("baked pizza" if p.data.baked else ("raw pizza" if p.data.assembled else "dough"))
		lines.append("Holding %s #%d%s" % [what, p.data.ticket, ("  · heat %d%%" % int(p.data.heat)) if p.data.baked else ""])
	if car and car.driving:
		var hot := 0
		for p in car.cargo:
			hot += int(p.data.heat)
		lines.append("Car: %d/%d pizzas%s" % [car.cargo.size(), car.capacity(), ("  · avg heat %d%%" % (hot / car.cargo.size())) if not car.cargo.is_empty() else ""])
	_carry.text = "   ".join(lines)
	_boost.visible = car != null and car.driving and Game.has_upgrade("boost")
	if _boost.visible:
		_boost.value = car.boost_fuel
