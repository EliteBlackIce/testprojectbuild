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
var _prompt: PanelContainer
var _prompt_text := ""
var _toast: PanelContainer
var _toast_label: Label
var _tickets_panel: PanelContainer
var _order_count: Label
var _hint_box: PanelContainer
var _carry_box: PanelContainer
var _help: PanelContainer
var _help_timer := 0.0
var _seen := {}
var _goal_label: Label
var _streak_label: Label
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

	# Top-left: money, clock, reputation, and what to do next
	var left := VBoxContainer.new()
	left.position = Vector2(20, 18)
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	var stats := PanelContainer.new()
	left.add_child(stats)
	var sv := HBoxContainer.new()
	sv.add_theme_constant_override("separation", 18)
	stats.add_child(sv)
	_money = UiTheme.label("$0", 40, UiTheme.TEAL)
	sv.add_child(_money)
	var sc := VBoxContainer.new()
	sc.add_theme_constant_override("separation", 2)
	sc.alignment = BoxContainer.ALIGNMENT_CENTER
	sv.add_child(sc)
	_clock = UiTheme.label("", UiTheme.BODY)
	_stars = StarBar.new()
	sc.add_child(_clock)
	sc.add_child(_stars)
	_hint_box = PanelContainer.new()
	_hint_box.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.BG, 14, 12))
	_hint_box.custom_minimum_size.x = 300
	left.add_child(_hint_box)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	_hint_box.add_child(hv)
	hv.add_child(UiTheme.caption("Next up", UiTheme.YELLOW))
	_hint = UiTheme.label("", 17)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hv.add_child(_hint)
	_goal_label = UiTheme.label("", 15, UiTheme.TEAL)
	_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	hv.add_child(UiTheme.caption("Today's goal", UiTheme.TEAL))
	hv.add_child(_goal_label)
	_streak_label = UiTheme.label("", 15, UiTheme.YELLOW)
	hv.add_child(_streak_label)

	# Right: tickets
	_tickets_panel = PanelContainer.new()
	_tickets_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tickets_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tickets_panel.offset_left = -340
	_tickets_panel.offset_right = -20
	_tickets_panel.offset_top = 18
	root.add_child(_tickets_panel)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	_tickets_panel.add_child(tv)
	var th := HBoxContainer.new()
	tv.add_child(th)
	var ttl := UiTheme.caption("Orders", UiTheme.YELLOW)
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(ttl)
	_order_count = UiTheme.caption("0")
	th.add_child(_order_count)
	_tickets_box = VBoxContainer.new()
	_tickets_box.add_theme_constant_override("separation", 8)
	tv.add_child(_tickets_box)

	# Phone banner (top center)
	_phone_banner = PanelContainer.new()
	_phone_banner.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.YELLOW, 16, 22, 10, Color(1, 1, 1, 0.5), 2))
	_phone_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phone_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_phone_banner.offset_top = 18
	root.add_child(_phone_banner)
	_phone_label = UiTheme.label("", UiTheme.LABEL, UiTheme.INK)
	_phone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phone_banner.add_child(_phone_label)
	_phone_banner.visible = false

	# Toast (under the phone banner)
	_toast = PanelContainer.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 84
	_toast.modulate.a = 0.0
	root.add_child(_toast)
	_toast_label = UiTheme.label("", UiTheme.LABEL)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_toast.add_child(_toast_label)

	# Crosshair: a little dot that puffs up into a ring when you're aiming at something usable
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	root.add_child(_cross)

	# Interaction prompt: key chips on a dark pill just under the crosshair
	_prompt = PanelContainer.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.offset_top = 38
	_prompt.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.105, 0.075, 0.17, 0.82), 20, 18, 8, UiTheme.LINE, 1))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_prompt)
	_prompt.visible = false

	# Bottom center: what you're carrying / car cargo, boost meter
	_carry_box = PanelContainer.new()
	_carry_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_carry_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_carry_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_carry_box.offset_bottom = -22
	root.add_child(_carry_box)
	_carry = UiTheme.label("", UiTheme.BODY)
	_carry_box.add_child(_carry)
	_carry_box.visible = false

	_boost = ProgressBar.new()
	_boost.show_percentage = false
	_boost.max_value = 1.0
	_boost.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_boost.offset_left = -110
	_boost.offset_right = 110
	_boost.offset_top = -86
	_boost.offset_bottom = -76
	root.add_child(_boost)

	# Bottom-left: controls cheat sheet (shows at the start of a day, F1 toggles)
	_help = PanelContainer.new()
	_help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.offset_left = 20
	_help.offset_bottom = -20
	root.add_child(_help)
	var hbox := VBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	_help.add_child(hbox)
	for line in ["[WASD] Move   [E] Use   [CLICK] Poke / throw   [R-CLICK] Grab prop   [SPACE] Hop   [T] Talk",
			"[F] Car in / out   [V] Camera   [H] Honk   [Q] Phone   [ESC] Pause   [F1] Hide this"]:
		var kt := UiTheme.keyed_text(line, 15)
		kt.alignment = BoxContainer.ALIGNMENT_BEGIN
		hbox.add_child(kt)
	_help.visible = false

	# Bottom-right: how the customers are being run
	_mode_badge = UiTheme.label("", UiTheme.CAPTION, Color(UiTheme.TEXT, 0.55))
	_mode_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_mode_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mode_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_mode_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_badge.offset_right = -20
	_mode_badge.offset_bottom = -14
	root.add_child(_mode_badge)

	Game.money_changed.connect(_on_money)
	Game.toast.connect(show_toast)
	Game.tickets_changed.connect(_rebuild_tickets)
	Game.day_started.connect(_on_day_started)
	Settings.changed.connect(_update_badge)
	_update_badge()
	_on_money(Game.money, 0)
	_rebuild_tickets()


func _on_day_started(_day: int) -> void:
	_show_help(true)
	_help_timer = 28.0
	_seen.clear()


func _show_help(on: bool) -> void:
	_help.visible = on
	if not on:
		_help_timer = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F1:
		_help_timer = 0.0 if _help.visible else 28.0
		_show_help(not _help.visible)
		if _help.visible:
			_help_timer = 28.0


func _update_badge() -> void:
	match Settings.effective_mode():
		"offline":
			_mode_badge.text = "Offline mode: scripted customers (add keys in Settings for AI)"
		"proxy":
			_mode_badge.text = "AI via game server · replies: " + Settings.voice_engine()
		_:
			_mode_badge.text = "Claude AI%s · replies: %s" % [" + voice chat" if Settings.has_speech_to_text() else " (type to talk)", "text only" if Settings.voice_engine() == "none" else Settings.voice_engine()]


func set_hint(text: String) -> void:
	_hint.text = text
	_hint_box.visible = text != "" and Settings.show_hints


func set_prompt(text: String) -> void:
	if text != _prompt_text:
		_prompt_text = text
		for c in _prompt.get_children():
			c.queue_free()
		if text != "":
			_prompt.add_child(UiTheme.keyed_text(text, UiTheme.LABEL))
		_prompt.visible = text != ""
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
		_cross.draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 32, Color(0, 0, 0, 0.45), 5.0, true)
		_cross.draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 32, UiTheme.YELLOW, 2.5, true)
	else:
		_cross.draw_circle(Vector2.ZERO, 4.5, Color(0, 0, 0, 0.45))
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
	var text: String = item[0]
	var accent: Color = item[1]
	_toast_label.text = text
	var f := UiTheme.ui_font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.LABEL).x + 8.0
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD if w > 760.0 else TextServer.AUTOWRAP_OFF
	_toast_label.custom_minimum_size = Vector2(clampf(w, 160.0, 760.0), 0.0)
	_toast.custom_minimum_size = Vector2.ZERO
	_toast.size = Vector2.ZERO
	var st := UiTheme.panel(UiTheme.BG, 16, 18)
	st.border_color = accent
	st.border_width_left = 6
	_toast.add_theme_stylebox_override("panel", st)
	_toast.pivot_offset = _toast.size * 0.5
	_toast.modulate.a = 0.0
	_toast.scale = Vector2(0.94, 0.94)
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_property(_toast, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.chain().tween_interval(1.8 if _toast_queue.is_empty() else 0.9)
	_toast_tween.chain().tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tween.chain().tween_callback(_next_toast)


func _on_money(total: int, delta: int) -> void:
	_money.text = "$%d" % total
	if delta > 0:
		var tw := create_tween()
		_money.pivot_offset = _money.size * 0.5
		tw.tween_property(_money, "scale", Vector2(1.25, 1.25), 0.1)
		tw.tween_property(_money, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


const STATUS_TEXT := {
	"new": "Needs making", "making": "Being made", "baking": "In the oven",
	"ready": "Boxed: load the car", "in_car": "In the car: deliver it",
}
const STATUS_COLOR := {
	"new": UiTheme.PINK, "making": UiTheme.YELLOW, "baking": Color("#ff9f43"),
	"ready": UiTheme.TEAL, "in_car": UiTheme.BLUE,
}


func _rebuild_tickets() -> void:
	for c in _tickets_box.get_children():
		c.queue_free()
	var open := Game.open_tickets()
	_order_count.text = str(open.size())
	if open.is_empty():
		var l := UiTheme.label("No orders yet. Wait for the phone.", 16, UiTheme.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size.x = 280
		_tickets_box.add_child(l)
		return
	for t in open:
		var accent: Color = STATUS_COLOR.get(t.status, UiTheme.MUTED)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiTheme.card(accent))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		card.add_child(v)
		var head := HBoxContainer.new()
		v.add_child(head)
		var name_l := UiTheme.label("#%d  %s" % [t.id, t.customer], 17)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		head.add_child(name_l)
		head.add_child(UiTheme.label("House %d" % t.house.number, 15, UiTheme.MUTED))
		# A proper receipt: size and sauce on top, then one line per topping.
		var o: Dictionary = t.order
		var sauce: String = o.get("sauce", "tomato")
		var spec := UiTheme.label("%s  ·  %s sauce" % [str(Menu.SIZES[o.get("size", "medium")].label).to_upper(), Menu.SAUCES[sauce].label], 14, accent)
		v.add_child(spec)
		var tops: Array = o.get("toppings", [])
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 0)
		v.add_child(list)
		if tops.is_empty():
			list.add_child(UiTheme.label("  plain cheese", 15, UiTheme.MUTED))
		var counted := {}
		for tp in tops:
			counted[tp] = int(counted.get(tp, 0)) + 1
		for tp in counted:
			var n: int = counted[tp]
			list.add_child(UiTheme.label("  +  %s%s" % [Menu.TOPPINGS[tp].label, ("  x%d" % n) if n > 1 else ""], 15, UiTheme.TEXT))
		var foot := HBoxContainer.new()
		v.add_child(foot)
		var status := UiTheme.label(STATUS_TEXT.get(t.status, t.status), 14, accent)
		status.name = "Status"
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(status)
		var timer := UiTheme.label("", 14, UiTheme.TEXT)
		timer.name = "Timer"
		timer.set_meta("ticket", t.id)
		foot.add_child(timer)
		_tickets_box.add_child(card)
		if not _seen.has(t.id):
			_seen[t.id] = true
			card.modulate = Color(1.6, 1.5, 1.0)
			var tw := card.create_tween()
			tw.tween_property(card, "modulate", Color.WHITE, 0.8)
			Sfx.play("register", 1.2, -10.0)


func _process(delta: float) -> void:
	if _help_timer > 0.0:
		_help_timer -= delta
		if _help_timer <= 0.0:
			_show_help(false)
	if not Game.goal.is_empty():
		var done: bool = Game.goal.done
		_goal_label.text = "%s  %s" % [Game.goal.label, "(done!)" if done else "%d/%d  ·  +$%d" % [mini(Game.goal_progress(), int(Game.goal.target)), int(Game.goal.target), int(Game.goal.reward)]]
		_goal_label.add_theme_color_override("font_color", UiTheme.MUTED if done else UiTheme.TEAL)
	_streak_label.text = "Streak: %d" % Game.streak if Game.streak >= 2 else ""
	_clock.text = "Day %d  ·  %s%s" % [Game.day, Game.clock_text(), "  ·  last call!" if Game.is_last_call() and Game.day_running else ""]
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
				timer.add_theme_color_override("font_color", UiTheme.TEXT if left > 15 else UiTheme.RED)
	# Phone
	if phone and phone.is_ringing():
		_phone_banner.visible = true
		var where := "press Q to answer" if Game.has_upgrade("headset") else "run to the phone"
		_phone_label.text = "%s is calling  ·  %ds  ·  %s" % [phone.caller.display_name(), int(phone.ring_left), where]
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.015) * 0.025
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
	_carry.text = "   ·   ".join(lines)
	_carry_box.visible = not lines.is_empty()
	_boost.visible = car != null and car.driving and Game.has_upgrade("boost")
	if _boost.visible:
		_boost.value = car.boost_fuel
