class_name MakelineUi
extends CanvasLayer
## The prep-table screen: pick an order, choose sauce, grate cheese, add toppings.
## Number keys work for everything, so you never need the mouse.

signal _picked(value: Variant)

## Tests turn this on so the make-line plays itself perfectly.
static var autoplay := false

var _panel: PanelContainer
var _title: Label
var _ticket: Label
var _step: Label
var _grid: GridContainer
var _done_btn: Button
var _options: Array = []      ## values matching number keys
var _waiting := false


func _ready() -> void:
	layer = 7
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_panel.offset_left = 24
	_panel.offset_right = 540
	_panel.offset_top = -330
	_panel.offset_bottom = 330
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_title = UiTheme.label("", 34, UiTheme.RED)
	v.add_child(_title)
	_ticket = UiTheme.label("", 22)
	_ticket.autowrap_mode = TextServer.AUTOWRAP_WORD
	_ticket.custom_minimum_size.x = 480
	v.add_child(_ticket)
	_step = UiTheme.label("", 24, Color("#8338ec"))
	_step.autowrap_mode = TextServer.AUTOWRAP_WORD
	_step.custom_minimum_size.x = 480
	v.add_child(_step)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	v.add_child(_grid)
	_done_btn = Button.new()
	_done_btn.text = "DONE  [Enter]"
	_done_btn.pressed.connect(func(): _choose("done"))
	v.add_child(_done_btn)
	visible = false


## Which order is this dough for? Returns a ticket id.
func pick_ticket(tickets: Array[Dictionary]) -> int:
	if tickets.size() == 1 or autoplay:
		return tickets[0].id
	_open("WHICH ORDER?", "", "Pick the ticket this dough is for.")
	var opts: Array = []
	var labels: Array[String] = []
	for t in tickets.slice(0, 9):
		opts.append(t.id)
		labels.append("#%d %s: %s" % [t.id, t.customer, Menu.describe(t.order)])
	_show_options(opts, labels, false)
	var id = await _picked
	visible = false
	return int(id)


## Runs sauce -> cheese -> toppings on the pizza. Uses the minigame UI.
func run(pizza: Pizza, ticket: Dictionary, minigame: MinigameUi) -> void:
	var order: Dictionary = ticket.get("order", {})
	var sauce_bonus := float(Game.level("sauce_gun"))
	# 1. Sauce
	_open("SAUCE", _ticket_text(ticket, pizza), "Which sauce? (press 1-3)")
	var sauce: String
	if autoplay:
		sauce = order.get("sauce", "tomato")
	else:
		var keys := Menu.SAUCES.keys()
		var labels: Array[String] = []
		for k in keys:
			labels.append(Menu.SAUCES[k].label)
		_show_options(keys, labels, false)
		sauce = str(await _picked)
	_panel.visible = false
	var r := await _minigame(minigame, "fill", {"label": Menu.SAUCES[sauce].label, "bonus": sauce_bonus})
	pizza.add_sauce(sauce, r.quality)
	# 2. Cheese
	r = await _minigame(minigame, "mash", {"bonus": sauce_bonus})
	pizza.add_cheese(r.quality)
	# 3. Toppings
	_panel.visible = true
	if autoplay:
		for t in order.get("toppings", []):
			pizza.add_topping(t)
	else:
		while true:
			_open("TOPPINGS", _ticket_text(ticket, pizza), "Press a number to add a scoop. Enter when done.")
			var avail := Menu.available_toppings()
			var labels: Array[String] = []
			for t in avail:
				var n: int = pizza.data.toppings.count(t)
				labels.append("%s%s" % [Menu.TOPPINGS[t].label, ("  x%d" % n) if n > 0 else ""])
			_show_options(avail, labels, true)
			var pick = await _picked
			if str(pick) == "done":
				break
			pizza.add_topping(str(pick))
			Sfx.play("click", randf_range(0.9, 1.2))
	visible = false


func _minigame(minigame: MinigameUi, kind: String, params: Dictionary) -> Dictionary:
	if autoplay:
		minigame.call_deferred("auto_finish", 1.0)
	return await minigame.play(kind, params)


func _ticket_text(ticket: Dictionary, pizza: Pizza) -> String:
	var order: Dictionary = ticket.get("order", {})
	var lines: PackedStringArray = []
	lines.append("TICKET #%d for %s" % [ticket.get("id", 0), ticket.get("customer", "?")])
	lines.append("Size: %s%s" % [Menu.SIZES[order.size].label, "" if pizza.data.size == order.size else "  (dough is %s!)" % pizza.data.size])
	lines.append("Sauce: %s" % Menu.SAUCES[order.get("sauce", "tomato")].label)
	var tops: PackedStringArray = []
	for t in order.get("toppings", []):
		tops.append(("[x] " if t in pizza.data.toppings else "[ ] ") + Menu.TOPPINGS[t].label)
	lines.append("Toppings: " + (", ".join(tops) if not tops.is_empty() else "just cheese"))
	return "\n".join(lines)


func _open(title: String, ticket_text: String, step: String) -> void:
	visible = true
	_panel.visible = true
	_title.text = title
	_ticket.text = ticket_text
	_ticket.visible = ticket_text != ""
	_step.text = step


func _show_options(values: Array, labels: Array[String], allow_done: bool) -> void:
	for c in _grid.get_children():
		c.queue_free()
	_options = values
	for i in values.size():
		var b := Button.new()
		var key := str(i + 1) if i < 9 else ("0" if i == 9 else ("-" if i == 10 else "="))
		b.text = "%s  %s" % [key, labels[i]]
		b.custom_minimum_size = Vector2(230, 44)
		b.add_theme_font_size_override("font_size", 20)
		var val = values[i]
		b.pressed.connect(func(): _choose(val))
		_grid.add_child(b)
	_done_btn.visible = allow_done
	_waiting = true


func _choose(value: Variant) -> void:
	if not _waiting:
		return
	_waiting = false
	_picked.emit(value)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _waiting or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	var idx := -1
	if k >= KEY_1 and k <= KEY_9:
		idx = k - KEY_1
	elif k == KEY_0:
		idx = 9
	elif k == KEY_MINUS:
		idx = 10
	elif k == KEY_EQUAL:
		idx = 11
	elif (k == KEY_ENTER or k == KEY_KP_ENTER) and _done_btn.visible:
		get_viewport().set_input_as_handled()
		_choose("done")
		return
	if idx >= 0 and idx < _options.size():
		get_viewport().set_input_as_handled()
		_choose(_options[idx])
