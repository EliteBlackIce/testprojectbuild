class_name Kitchen
extends Node3D
## Tony's kitchen, hands-on:
##   dough rack -> grab a dough ball
##   prep board -> stretch it (drag out to the ring, right-click to TOSS it),
##                 paint sauce, sprinkle cheese, drop toppings piece by piece
##   oven       -> slide it in, watch the crust brown, pull it out in time
##   cut board  -> drag the pizza wheel across it, then fold the box shut
##   pass shelf -> boxed pizzas wait under the heat lamps (or go straight to the car)
## Also hosts the phone, the PC and Tony (their actions are callbacks from main).

signal busy_changed(busy: bool)
## Main hooks these up.
var on_phone: Callable
var phone_prompt: Callable
var on_pc: Callable
var on_tony: Callable

const BAKE_SECONDS := [16.0, 12.5, 9.5, 7.0]   ## time to a perfect bake, by oven level
const PASS_SIZE := 4
const OVEN_SPOTS := [Vector3(0, 0.965, 0.92), Vector3(0, 0.87, 0.74)]

var pizzeria: Pizzeria
var player: PlayerEgg
var ui: StationUi
var phone: PhoneLine
var tony: EggBody

var board_pizza: Pizza          ## on the prep board
var cut_pizza: Pizza            ## on the cutting board
var ovens: Array[Dictionary] = []
var pass_shelf: Array[Pizza] = []
var busy := false
var mode := ""                  ## "", "prep" or "cut" while working a station
var tool := ""

var _board: Node3D
var _cut_spot: Node3D
var _pass_spots: Array[Node3D] = []
var _cursor: Node3D
var _cursor_tool: Node3D
var _cursor_fingers: Array = []
var _rings: Node3D
var _preview: MeshInstance3D
var _phone_handset: Node3D
var _mouse_down := false
var _cursor_local := Vector2.ZERO
var _cursor_ok := false
var _drag_start := Vector2.ZERO
var _last_paint := Vector2(INF, INF)
var _paint_cd := 0.0
var _sound_cd := 0.0
var _tossing := false
var _spills_seen := 0
var _tony_t := 0.0
var _tony_target := Vector3.ZERO
var _alarm_cooldown := 0.0
var _t := 0.0


func setup(p: Pizzeria, pl: PlayerEgg, station_ui: StationUi) -> void:
	pizzeria = p
	player = pl
	ui = station_ui
	ui.tool_selected.connect(_on_tool)
	ui.done_pressed.connect(_on_done)
	ui.leave_pressed.connect(leave_station)
	ui.next_ticket_pressed.connect(_switch_ticket)
	_board = _spot(Pizzeria.ANCHORS.prep_board)
	_cut_spot = _spot(Pizzeria.ANCHORS.cut_board + Vector3(0, 0.02, 0))
	for i in PASS_SIZE:
		_pass_spots.append(_spot((Pizzeria.ANCHORS.pass as Vector3) + Vector3(-0.95 + i * 0.63, 0.0, 0.0)))
	_build_ovens()
	_build_stations()
	_build_phone()
	_build_cursor()
	_build_rings()
	_build_tony()
	add_puddle(Vector3(-8.6, 0.0, -7.2), 0.55, true)
	Game.upgrades_changed.connect(_refresh_ovens)


func _spot(local: Vector3) -> Node3D:
	var s := Node3D.new()
	s.position = local
	pizzeria.add_child(s)
	return s


# --- stations ------------------------------------------------------------------------------

func _build_stations() -> void:
	var A := Pizzeria.ANCHORS
	Station.make(pizzeria, (A.dough as Vector3) + Vector3(0.05, 1.1, 0), _dough_prompt, _dough_use, 2.0, 0.6)
	Station.make(pizzeria, A.prep_board, _prep_prompt, _prep_use, 2.0, 0.45)
	Station.make(pizzeria, A.cut_board, _cut_prompt, _cut_use, 2.0, 0.45)
	Station.make(pizzeria, (A.pass as Vector3) + Vector3(0, 0.1, 0), _pass_prompt, _pass_use, 2.0, 0.9)
	Station.make(pizzeria, (A.trash as Vector3) + Vector3(0.3, 0.8, 0), _trash_prompt, _trash_use, 1.8, 0.5)
	Station.make(pizzeria, A.phone, _phone_prompt_fn, _phone_use, 2.0, 0.35)
	Station.make(pizzeria, (A.pc as Vector3) + Vector3(0, 1.0, 0), _pc_prompt, _pc_use, 1.8, 0.4)
	# A flat box stack you can see shrinking is too fiddly; boxes are free. Label them.
	var lbl := Toon.label(pizzeria, "BOXES", (A.boxes as Vector3) + Vector3(0, 0.45, 0), 22, Color("#c0392b"))
	lbl.pixel_size = 0.006


func _phone_prompt_fn(p: Node) -> String:
	if busy:
		return ""
	return phone_prompt.call(p) if phone_prompt.is_valid() else ""


func _phone_use(p: Node) -> void:
	if on_phone.is_valid():
		on_phone.call(p)


func _pc_prompt(_p: Node) -> String:
	return "" if busy else "[E] Tony's PC: upgrades & hiring"


func _pc_use(p: Node) -> void:
	if on_pc.is_valid():
		on_pc.call(p)


func _new_tickets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in Game.open_tickets():
		if t.status == "new":
			out.append(t)
	return out


func _held_pizza() -> Pizza:
	return player.held as Pizza


# --- dough rack ---------------------------------------------------------------------------

func _dough_prompt(_p: Node) -> String:
	if busy or player.is_holding():
		return ""
	if _new_tickets().is_empty():
		return "Dough rack (no orders waiting. Wait for the phone!)"
	return "[E] Grab a dough ball for #%d" % _new_tickets()[0].id


func _dough_use(_p: Node) -> void:
	if busy or player.is_holding() or _new_tickets().is_empty():
		return
	var t: Dictionary = _new_tickets()[0]
	var cost := int(ceil(Menu.price_of(t.order) * Menu.INGREDIENT_COST))
	Game.spend(mini(cost, Game.money), "ingredients")
	var pizza := new_dough(t.id)
	player.hold(pizza)
	Sfx.play("squish", 1.3, -6.0)


func new_dough(ticket_id: int) -> Pizza:
	var pizza := Pizza.new()
	add_child(pizza)
	pizza.setup(ticket_id)
	Game.set_ticket_status(ticket_id, "making")
	return pizza


# --- prep board -----------------------------------------------------------------------------

func _prep_prompt(_p: Node) -> String:
	if busy:
		return ""
	var held := _held_pizza()
	if board_pizza == null:
		if held and not held.data.assembled:
			return "[E] Put the dough down and make pizza #%d" % held.data.ticket
		if held and held.data.assembled and not held.data.baked:
			return "[E] Put it back on the board"
		return "Prep board (grab dough from the rack on the left wall)"
	if not board_pizza.data.assembled:
		return "[E] Keep making pizza #%d" % board_pizza.data.ticket
	if not player.is_holding():
		return "[E] Pick up pizza #%d" % board_pizza.data.ticket
	return ""


func _prep_use(_p: Node) -> void:
	if busy:
		return
	var held := _held_pizza()
	if board_pizza == null and held and not held.data.baked:
		player.take_held()
		_place(held, _board)
		board_pizza = held
		if not held.data.assembled:
			_enter("prep")
		return
	if board_pizza and not board_pizza.data.assembled:
		_enter("prep")
	elif board_pizza and not player.is_holding():
		var p := board_pizza
		board_pizza = null
		player.hold(p)


func _place(p: Pizza, spot: Node3D) -> void:
	p.reparent(spot, true)
	var tw := p.create_tween()
	tw.tween_property(p, "position", Vector3.ZERO, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "rotation", Vector3.ZERO, 0.22)
	p.location = "kitchen"


# --- cutting board ------------------------------------------------------------------------

func _cut_prompt(_p: Node) -> String:
	if busy:
		return ""
	var held := _held_pizza()
	if cut_pizza:
		return "[E] Finish cutting #%d" % cut_pizza.data.ticket
	if held and held.data.baked and not held.is_boxed():
		return "[E] Cut & box pizza #%d" % held.data.ticket
	return "Cutting board (bring a baked pizza)"


func _cut_use(_p: Node) -> void:
	if busy:
		return
	var held := _held_pizza()
	if cut_pizza == null and held and held.data.baked and not held.is_boxed():
		player.take_held()
		_place(held, _cut_spot)
		cut_pizza = held
	if cut_pizza:
		_enter("cut")


# --- work mode ----------------------------------------------------------------------------------

func _enter(m: String) -> void:
	mode = m
	busy = true
	busy_changed.emit(true)
	var spot := _board if m == "prep" else _cut_spot
	var local := Transform3D(Basis(), spot.position + Vector3(0, 1.02, 0.6))
	local = local.looking_at(spot.position + Vector3(0, 0, -0.04), Vector3.UP)
	player.enter_view(pizzeria.global_transform * local, 52.0)
	_cursor.visible = true
	_mouse_down = false
	if m == "prep":
		_build_rings()
		ui.open("MAKE PIZZA #%d" % board_pizza.data.ticket, "")
		var tools := [["stretch", "Stretch", Color("#efd9a8")]]
		for s: String in Menu.SAUCES:
			tools.append(["sauce:" + s, Menu.SAUCES[s].label, Color(Menu.SAUCES[s].color)])
		tools.append(["cheese", "Cheese", Pizza.CHEESE_COLOR])
		for t in Menu.available_toppings():
			tools.append(["top:" + t, Menu.TOPPINGS[t].label, Color(Menu.TOPPINGS[t].color)])
		ui.set_tools(tools)
		_select_tool("stretch" if not board_pizza.data.stretched else "sauce:" + str(Game.ticket(board_pizza.data.ticket).get("order", {}).get("sauce", "tomato")))
		ui.set_done_text("DONE [E]", true)
	else:
		ui.open("CUT & BOX #%d" % cut_pizza.data.ticket, "Drag the pizza wheel across the pie. 4 cuts through the middle = 8 perfect slices.")
		ui.set_tools([["wheel", "Pizza wheel", Color("#b2bec3")]])
		_select_tool("wheel")
		ui.set_done_text("BOX IT [E]", true)
	_refresh_ui()


func leave_station() -> void:
	if mode == "":
		return
	if mode == "prep" and board_pizza and not board_pizza.data.stretched and board_pizza.radius() > 0.12:
		board_pizza.finish_stretch(_order_of(board_pizza).get("size", "medium"))
	mode = ""
	busy = false
	_mouse_down = false
	_cursor.visible = false
	_rings.visible = false
	_preview.visible = false
	player.exit_view()
	ui.close()
	busy_changed.emit(false)


func _order_of(p: Pizza) -> Dictionary:
	return Game.ticket(p.data.ticket).get("order", {"size": "medium", "sauce": "tomato", "toppings": []})


func _on_tool(id: String) -> void:
	_select_tool(id)


func _select_tool(id: String) -> void:
	if mode == "prep" and board_pizza:
		if id != "stretch" and board_pizza.radius() < 0.2:
			Game.say_toast("Stretch the dough first! (drag outward from the middle)", Color("#ff9f1c"))
			id = "stretch"
		elif id == "stretch" and board_pizza.has_sauce():
			Game.say_toast("Too late to stretch, it's sauced!", Color("#ff9f1c"))
			id = tool if tool != "stretch" else "cheese"
		if tool == "stretch" and id != "stretch":
			board_pizza.finish_stretch(_order_of(board_pizza).get("size", "medium"))
	tool = id
	ui.select(id)
	_rings.visible = mode == "prep" and id == "stretch"
	_build_cursor_tool()
	_refresh_ui()


func _on_done() -> void:
	if mode == "prep":
		var p := board_pizza
		if p.radius() < 0.2:
			Game.say_toast("That's a dough ball, not a pizza. Stretch it!", Color("#ff9f1c"))
			return
		p.finish_stretch(_order_of(p).get("size", "medium"))
		p.finish_assembly()
		board_pizza = null
		leave_station()
		player.hold(p)
		var q := (float(p.data.dough_q) + float(p.data.sauce_q) + float(p.data.cheese_q)) / 3.0
		if q > 0.8:
			Game.say_toast(["Beautiful. Into the oven!", "Tony would cry. Oven time!", "Chef's kiss. OVEN."].pick_random(), UiTheme.TEAL)
		else:
			Game.say_toast("Pizza #%d is ready for the oven (back wall)." % p.data.ticket, UiTheme.YELLOW)
	elif mode == "cut":
		var p := cut_pizza
		p.finish_cuts()
		p.put_in_box()
		Sfx.play("slam", 1.8, -6.0)
		cut_pizza = null
		Game.set_ticket_status(p.data.ticket, "ready")
		await get_tree().create_timer(0.75).timeout
		leave_station()
		player.hold(p)
		Game.say_toast("Boxed! Put it on the pass shelf or load it into the car.", UiTheme.YELLOW)


func _switch_ticket() -> void:
	if mode != "prep" or board_pizza == null:
		return
	var options := _new_tickets()
	if options.is_empty():
		return
	var old: int = board_pizza.data.ticket
	var next: Dictionary = options[0]
	Game.set_ticket_status(old, "new")
	board_pizza.data.ticket = next.id
	Game.set_ticket_status(next.id, "making")
	ui.open("MAKE PIZZA #%d" % next.id, "")
	_build_rings()
	_rings.visible = tool == "stretch"
	_refresh_ui()


func _unhandled_input(event: InputEvent) -> void:
	if mode == "":
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mouse_down = mb.pressed
			if mb.pressed:
				_press()
			else:
				_release()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_alt()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			ui.select_index(k - KEY_1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("interact"):
		_on_done()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		leave_station()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tickets"):
		_switch_ticket()
		get_viewport().set_input_as_handled()


func _work_pizza() -> Pizza:
	return board_pizza if mode == "prep" else cut_pizza


func _press() -> void:
	var p := _work_pizza()
	if p == null or not _cursor_ok or _tossing:
		return
	_last_paint = Vector2(INF, INF)
	_paint_cd = 0.0
	_drag_start = _cursor_local
	if tool.begins_with("top:"):
		_drop_topping()
	elif tool == "wheel":
		_preview.visible = true


func _release() -> void:
	if mode == "cut" and cut_pizza and tool == "wheel" and _preview.visible:
		_preview.visible = false
		if cut_pizza.add_cut(_drag_start, _cursor_local):
			Sfx.play("chop", randf_range(0.9, 1.1), -4.0)
			_cursor_tool.rotation.z += 2.0
		else:
			Game.say_toast("Drag the wheel all the way across the pizza!", Color("#ff9f1c"))
	if mode == "prep" and tool == "stretch" and board_pizza:
		EggBody.curl_hand(_cursor_fingers, 0.0)
		if board_pizza.is_torn():
			_tear()


## Right click: toss the dough! (stretch only, before sauce)
func _alt() -> void:
	var p := board_pizza
	if mode != "prep" or p == null or tool != "stretch" or p.has_sauce() or _tossing:
		return
	_tossing = true
	var face := randf() < 0.12
	Sfx.play("whoosh", 1.3, -4.0)
	var tw := create_tween()
	var spin := p.rotation.y + TAU * 2.0
	tw.tween_property(p, "position", Vector3(0, 0.55, 0.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "rotation:y", spin, 0.7)
	if face:
		tw.tween_property(p, "position", Vector3(0, 0.75, 0.42), 0.18)
		tw.tween_callback(_face_splat)
		tw.tween_interval(0.9)
		tw.tween_property(p, "position", Vector3.ZERO, 0.3)
	else:
		tw.tween_property(p, "position", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_toss_landed)


func _face_splat() -> void:
	ui.splat()
	Sfx.play("splat", 0.8)
	Game.say_toast(["MY EYES", "Dough to the face!", "Can't see. Smells great though."].pick_random(), UiTheme.PINK)


func _toss_landed() -> void:
	_tossing = false
	var p := board_pizza
	if p == null:
		return
	p.rotation = Vector3.ZERO
	p.set_stretch(p.radius() + randf_range(0.025, 0.05))
	Sfx.play("splat", 1.4, -8.0)
	if p.is_torn():
		_tear()
	_refresh_ui()


func _tear() -> void:
	Game.say_toast("RRRRIP! Too thin! Squish it back into a ball...", UiTheme.RED)
	Sfx.play("splat", 0.6)
	board_pizza.set_stretch(0.1)
	board_pizza.data.stretched = false


func _drop_topping() -> void:
	var kind := tool.substr(4)
	board_pizza.place_topping(kind, _cursor_local + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 0.01)
	Sfx.play("poke", randf_range(1.4, 1.8), -12.0)
	_squash_cursor()


func _squash_cursor() -> void:
	_cursor.scale = Vector3(1.25, 0.7, 1.25)
	var tw := _cursor.create_tween()
	tw.tween_property(_cursor, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _work_process(delta: float) -> void:
	var p := _work_pizza()
	if p == null:
		return
	# Mouse -> point on the pizza
	var cam := player.camera
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var plane_y := p.global_position.y + 0.05
	_cursor_ok = absf(dir.y) > 0.01
	if _cursor_ok:
		var hit := from + dir * ((plane_y - from.y) / dir.y)
		var local := p.to_local(hit)
		_cursor_local = Vector2(local.x, local.z).limit_length(0.75)
		var hover := 0.03 if _mouse_down else 0.11
		var target := p.to_global(Vector3(_cursor_local.x, 0.05 + hover, _cursor_local.y))
		_cursor.global_position = _cursor.global_position.lerp(target, 1.0 - exp(-30.0 * delta))
		_cursor.global_rotation = Vector3(0, pizzeria.global_rotation.y, 0)
	if _tossing:
		return
	_paint_cd -= delta
	_sound_cd -= delta
	if _mouse_down and _cursor_ok:
		if tool == "stretch":
			EggBody.curl_hand(_cursor_fingers, 0.45)
			var want := _cursor_local.length() + 0.03
			if want > p.radius():
				var rate := 4.0 * (1.0 + Game.level("dough_press") * 0.6)
				p.set_stretch(p.radius() + (want - p.radius()) * (1.0 - exp(-rate * delta)))
				_cursor_tool.rotation.y += delta * 6.0
				if _sound_cd <= 0.0:
					_sound_cd = 0.35
					Sfx.play("squish", randf_range(1.2, 1.5), -14.0)
			if p.is_torn():
				_mouse_down = false
				_tear()
		elif tool.begins_with("sauce:"):
			if _paint_cd <= 0.0 or _cursor_local.distance_to(_last_paint) > 0.022:
				_paint_cd = 0.04
				_last_paint = _cursor_local
				if p.paint_sauce(_cursor_local, tool.substr(6)):
					_cursor_tool.rotation.z = sin(_t * 20.0) * 0.4
					if _sound_cd <= 0.0:
						_sound_cd = 0.25
						Sfx.play("squish", randf_range(0.9, 1.2), -12.0)
		elif tool == "cheese":
			if _paint_cd <= 0.0:
				_paint_cd = 0.05
				if p.sprinkle_cheese(_cursor_local):
					_cursor_tool.position.y = 0.02 * sin(_t * 40.0)
					if _sound_cd <= 0.0:
						_sound_cd = 0.12
						Sfx.play("sprinkle", randf_range(0.8, 1.3), -10.0)
		elif tool.begins_with("top:"):
			if _paint_cd <= -0.18:
				_paint_cd = 0.0
				_drop_topping()
		elif tool == "wheel":
			_update_preview(p)
	# Too much spilling = a puddle on the floor you can slip on.
	if mode == "prep" and int(p.data.spills) - _spills_seen >= 14:
		_spills_seen = int(p.data.spills)
		add_puddle((Pizzeria.ANCHORS.prep_board as Vector3) * Vector3(1, 0, 1) + Vector3(randf_range(-0.6, 0.6), 0.0, 1.0), 0.45, false)
		Game.say_toast("You slopped sauce on the floor. Careful...", Color("#ff9f1c"))
	_refresh_ui()


func _update_preview(p: Pizza) -> void:
	var a := _drag_start
	var b := _cursor_local
	var mid := (a + b) * 0.5
	_preview.position = Vector3(mid.x, 0.085, mid.y)
	_preview.rotation = Vector3(0, -atan2(b.y - a.y, b.x - a.x), 0)
	_preview.scale = Vector3(maxf(0.01, a.distance_to(b)), 1, 1)
	_cursor_tool.rotation.z -= 0.2


func _refresh_ui() -> void:
	if mode == "prep" and board_pizza:
		var p := board_pizza
		var t := Game.ticket(p.data.ticket)
		var order := _order_of(p)
		var want_size: String = order.get("size", "medium")
		var lines: PackedStringArray = []
		var size_ok := absf(p.radius() - float(Menu.SIZES[want_size].radius)) < 0.035
		lines.append(_check(size_ok, "Size: " + Menu.SIZES[want_size].label))
		var sauce: String = order.get("sauce", "tomato")
		lines.append(_check(p.data.sauce == sauce and p.coverage("sauce") > 0.6, "Sauce: " + Menu.SAUCES[sauce].label))
		lines.append(_check(p.coverage("cheese") > 0.55, "Cheese"))
		var counts := p.piece_counts()
		var tops: Array = order.get("toppings", [])
		for kind: String in tops:
			var n := int(counts.get(kind, 0))
			lines.append(_check(n >= Pizza.PIECES_PER_PORTION, "%s  %d/%d" % [Menu.TOPPINGS[kind].label, mini(n, Pizza.PIECES_PER_PORTION), Pizza.PIECES_PER_PORTION]))
		if tops.is_empty():
			lines.append("[color=#9d92b8](no toppings, just cheese)[/color]")
		for kind: String in counts:
			if kind not in tops:
				lines.append("[color=#ff5d73]%s (NOT ordered!)[/color]" % Menu.TOPPINGS[kind].label)
		ui.set_ticket(t, "\n".join(lines), not _new_tickets().is_empty())
		var size_name := "dough ball"
		for s: String in Menu.SIZE_ORDER:
			if absf(p.radius() - float(Menu.SIZES[s].radius)) < 0.045:
				size_name = Menu.SIZES[s].label
		if p.radius() > 0.5:
			size_name = "TOO THIN"
		ui.set_meters([
			["Dough", clampf(p.radius() / 0.6, 0, 1), Color("#e9c46a"), size_name],
			["Sauce", p.coverage("sauce"), Color("#e63946"), "%d%%" % int(p.coverage("sauce") * 100)],
			["Cheese", p.coverage("cheese"), Color("#ffd166"), "%d%%" % int(p.coverage("cheese") * 100)],
			["Spills", clampf(float(p.data.spills) / 30.0, 0, 1), Color("#8338ec"), str(p.data.spills)],
		])
		var instr := ""
		match tool:
			"stretch":
				instr = "Hold LEFT CLICK and drag out from the middle to the yellow ring. RIGHT CLICK to toss it!"
			"cheese":
				instr = "Hold LEFT CLICK and wiggle over the pizza to sprinkle cheese."
			_:
				if tool.begins_with("sauce:"):
					instr = "Hold LEFT CLICK and paint sauce on. Stay off the crust!"
				elif tool.begins_with("top:"):
					instr = "Click to drop %s. About %d pieces is one portion." % [Menu.TOPPINGS[tool.substr(4)].label.to_lower(), Pizza.PIECES_PER_PORTION]
		ui.set_instructions(instr + "   [E] when done.")
	elif mode == "cut" and cut_pizza:
		var p := cut_pizza
		ui.set_ticket(Game.ticket(p.data.ticket), "Cuts: %d / 4\n%s" % [p.data.cuts, Pizza.describe_condition(p.data)], false)
		ui.set_meters([["Cuts", clampf(p.data.cuts / 4.0, 0, 1), Color("#06d6a0"), "%d/4" % p.data.cuts],
			["Heat", float(p.data.heat) / 100.0, Color("#e76f51"), "%d%%" % int(p.data.heat)]])


func _check(ok: bool, text: String) -> String:
	return ("[color=#2fe3b2][b]%s  - ok[/b][/color]" % text) if ok else text


# --- the work cursor (a mitten holding the current tool) ------------------------------------------------

func _build_cursor() -> void:
	_cursor = Node3D.new()
	pizzeria.add_child(_cursor)
	# Your hand, hovering over the board (fingers pointing away from you, palm down)
	var wrist := Node3D.new()
	wrist.position = Vector3(0.02, 0.08, 0.12)
	wrist.rotation = Vector3(PI / 2 - 0.5, 0.25, 0.0)
	_cursor.add_child(wrist)
	_cursor_fingers = EggBody.build_hand(wrist, FpHands.SKIN, -1.0, 0.95, 0.007)[1]
	_cursor_tool = Node3D.new()
	_cursor.add_child(_cursor_tool)
	_cursor.visible = false
	_preview = Toon.box(_cut_spot, Vector3(1.0, 0.006, 0.012), Vector3.ZERO, Color("#ffffff"), 0.0)
	_preview.material_override = Toon.glow(Color("#ffd166"), 1.5)
	_preview.visible = false


func _build_cursor_tool() -> void:
	if not _cursor_fingers.is_empty():
		EggBody.curl_hand(_cursor_fingers, 0.0 if tool == "stretch" else 0.85)
	for c in _cursor_tool.get_children():
		c.queue_free()
	_cursor_tool.rotation = Vector3.ZERO
	_cursor_tool.position = Vector3.ZERO
	if tool.begins_with("sauce:"):
		var col := Color(Menu.SAUCES[tool.substr(6)].color)
		Toon.cyl(_cursor_tool, 0.008, 0.008, 0.25, Vector3(0, 0.15, 0.06), Color("#b2bec3"), 0.0, 5).rotation.x = 0.5
		var bowl := Toon.ball(_cursor_tool, 0.045, Vector3(0, 0.02, 0), Color("#b2bec3"), 0.006, 8)
		bowl.scale = Vector3(1, 0.55, 1)
		Toon.cyl(_cursor_tool, 0.04, 0.04, 0.01, Vector3(0, 0.035, 0), col, 0.0, 8)
	elif tool == "cheese":
		for k in 7:
			var s := Toon.box(_cursor_tool, Vector3(0.04, 0.008, 0.01), Vector3(randf_range(-0.03, 0.03), 0.03 + randf() * 0.02, randf_range(-0.02, 0.03)), Pizza.CHEESE_COLOR, 0.0)
			s.rotation.y = randf() * TAU
	elif tool.begins_with("top:"):
		var info: Dictionary = Menu.TOPPINGS[tool.substr(4)]
		Toon.ball(_cursor_tool, 0.028, Vector3(0, 0.03, 0.0), Color(info.color), 0.005, 6)
	elif tool == "wheel":
		var w := Toon.cyl(_cursor_tool, 0.06, 0.06, 0.012, Vector3(0, 0.06, 0), Color("#dfe6e9"), 0.006, 12)
		w.rotation.z = PI / 2
		Toon.cyl(_cursor_tool, 0.015, 0.015, 0.16, Vector3(0, 0.12, 0.08), Color("#e63946"), 0.004, 6).rotation.x = 0.8


func _build_rings() -> void:
	if _rings == null:
		_rings = Node3D.new()
		_board.add_child(_rings)
	for c in _rings.get_children():
		c.queue_free()
	var want := "medium"
	if board_pizza:
		want = str(_order_of(board_pizza).get("size", "medium"))
	for s: String in Menu.SIZE_ORDER:
		var r := float(Menu.SIZES[s].radius)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = r - 0.006
		torus.outer_radius = r + 0.006
		torus.rings = 40
		torus.ring_segments = 4
		ring.mesh = torus
		ring.material_override = Toon.glow(Color("#ffd166") if s == want else Color(1, 1, 1, 1), 1.4 if s == want else 0.35)
		ring.position.y = 0.012
		_rings.add_child(ring)
		var l := Toon.label(_rings, Menu.SIZES[s].label.to_upper(), Vector3(r + 0.02, 0.02, 0.0), 22 if s == want else 14, Color("#ffd166") if s == want else Color.WHITE, false)
		l.rotation.x = -PI / 2
		l.pixel_size = 0.004
	_rings.visible = false


# --- ovens ----------------------------------------------------------------------------------------------

func _build_ovens() -> void:
	for i in 2:
		var root := pizzeria.get_node_or_null("OvenBody%d" % (i + 1)) as Node3D
		if root == null:
			root = _spot(Pizzeria.ANCHORS["oven%d" % (i + 1)])
		var spot := Node3D.new()
		spot.position = OVEN_SPOTS[i]
		root.add_child(spot)
		var fire := MeshInstance3D.new()
		fire.mesh = Shapes.blob(0.3, 11 + i, 0.3)
		fire.material_override = Toon.glow(Color("#ff8c42"), 2.6)
		fire.position = Vector3(0, 1.08, 0.75) if i == 0 else Vector3(0, 1.0, 0.59)
		fire.scale = Vector3(1.2, 0.4, 0.08)
		root.add_child(fire)
		var light := OmniLight3D.new()
		light.light_color = Color("#ff9e57")
		light.light_energy = 0.35
		light.omni_range = 3.2
		light.position = Vector3(0, 1.2, 1.3)
		root.add_child(light)
		var label := Toon.label(root, "", Vector3(0, 2.05 if i == 0 else 1.95, 0.9), 54, Color.WHITE)
		label.pixel_size = 0.006
		var smoke: Array[MeshInstance3D] = []
		for k in 4:
			var puff := Toon.ball(root, 0.14, Vector3(0, 1.4, 0.8), Color("#4a4a4a"), 0.0, 6)
			puff.visible = false
			smoke.append(puff)
		ovens.append({"root": root, "spot": spot, "pizza": null, "label": label, "fire": fire, "smoke": smoke, "index": i, "light": light})
		Station.make(root, Vector3(0, 1.05, 0.9), _oven_prompt.bind(i), _oven_use.bind(i), 2.2, 0.7)
	_refresh_ovens()


func _refresh_ovens() -> void:
	var count := 2 if Game.has_upgrade("second_oven") else 1
	for o in ovens:
		(o.root as Node3D).visible = o.index < count


func oven_count() -> int:
	return 2 if Game.has_upgrade("second_oven") else 1


func _oven_prompt(_p: Node, i: int) -> String:
	var o := ovens[i]
	if busy or not (o.root as Node3D).visible:
		return ""
	var p: Pizza = o.pizza
	if p == null:
		var held := _held_pizza()
		if held and held.data.assembled and not held.data.baked:
			return "[E] Slide pizza #%d into the oven" % held.data.ticket
		return "Oven %d (empty, hot)" % (i + 1)
	if player.is_holding():
		return "Hands full!"
	var b := float(p.data.bake)
	if b > 1.3:
		return "[E] PULL IT OUT (IT'S ON FIRE)"
	if b >= 0.88:
		return "[E] Take it out NOW (perfect!)"
	return "[E] Take it out early (still pale)"


func _oven_use(_p: Node, i: int) -> void:
	var o := ovens[i]
	var p: Pizza = o.pizza
	if p == null:
		var held := _held_pizza()
		if held and held.data.assembled and not held.data.baked:
			player.take_held()
			player.hands.play("push")
			put_in_oven(held, i)
		return
	if player.is_holding():
		return
	take_from_oven(i)
	player.hold(p)
	var b := float(p.data.bake)
	if b > 1.3:
		Game.say_toast("Burnt! Customers will notice...", Color("#ff9f1c"))
	elif b >= 0.88:
		Game.say_toast("PERFECT BAKE!", UiTheme.TEAL)
		if tony:
			tony.play("celebrate")


func free_oven() -> int:
	for o in ovens:
		if o.pizza == null and o.index < oven_count():
			return o.index
	return -1


func put_in_oven(p: Pizza, i: int) -> void:
	var o := ovens[i]
	p.reparent(o.spot as Node3D, true)
	p.location = "oven"
	o.pizza = p
	var tw := p.create_tween()
	tw.tween_property(p, "position", Vector3(0, 0, 0.35), 0.18)
	tw.tween_property(p, "position", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "rotation", Vector3.ZERO, 0.3)
	Game.set_ticket_status(p.data.ticket, "baking")
	Sfx.play("whoosh", 1.0, -6.0)


func take_from_oven(i: int) -> Pizza:
	var o := ovens[i]
	var p: Pizza = o.pizza
	o.pizza = null
	if p:
		p.data.baked = true
		p.data.heat = 100.0
		(o.label as Label3D).text = ""
		Sfx.play("pickup")
	return p


func _process(delta: float) -> void:
	_t += delta
	_alarm_cooldown = maxf(0.0, _alarm_cooldown - delta)
	if mode != "":
		_work_process(delta)
	var bake_time: float = BAKE_SECONDS[Game.level("oven")]
	for o in ovens:
		var p: Pizza = o.pizza
		var label := o.label as Label3D
		var fire := o.fire as MeshInstance3D
		var flick := sin(_t * 9.0 + o.index * 2.0) * 0.06 + sin(_t * 23.0) * 0.03
		fire.scale = Vector3(1.2, 0.4 + flick, 0.08)
		(o.light as OmniLight3D).light_energy = 0.35 + flick
		var smoke: Array = o.smoke
		var burning := p != null and float(p.data.bake) > 1.25
		for k in smoke.size():
			var puff := smoke[k] as MeshInstance3D
			puff.visible = burning
			if burning:
				var ph := fmod(_t * 0.5 + k / 4.0, 1.0)
				puff.position = Vector3(sin(k * 1.9 + _t) * 0.25, 1.4 + ph * 1.6, 0.8 + ph * 0.3)
				puff.scale = Vector3.ONE * (0.5 + ph * 1.6)
		if p == null:
			continue
		if not Game.in_dialogue:
			p.set_bake(float(p.data.bake) + delta / bake_time)
		var b := float(p.data.bake)
		if b < 0.6:
			label.text = "baking..."
			label.modulate = Color.WHITE
		elif b < 0.88:
			label.text = "almost..."
			label.modulate = UiTheme.YELLOW
		elif b <= 1.15:
			label.text = "PERFECT!"
			label.modulate = UiTheme.TEAL
		elif b <= 1.3:
			label.text = "HURRY!"
			label.modulate = Color("#ff9f1c")
		else:
			label.text = "ON FIRE!!!"
			label.modulate = UiTheme.RED
			if _alarm_cooldown <= 0.0:
				_alarm_cooldown = 1.2
				Sfx.play("honk", 1.6, -8.0)
	_update_phone()
	_update_tony(delta)


# --- pass shelf (heat lamps), trash ---------------------------------------------------------------------

func _pass_prompt(_p: Node) -> String:
	if busy:
		return ""
	var held := _held_pizza()
	if held and held.is_boxed():
		if pass_shelf.size() >= PASS_SIZE:
			return "Pass shelf is full"
		return "[E] Put #%d under the heat lamps (%d/%d)" % [held.data.ticket, pass_shelf.size(), PASS_SIZE]
	if not player.is_holding() and not pass_shelf.is_empty():
		return "[E] Grab pizza #%d" % pass_shelf[0].data.ticket
	return ""


func _pass_use(_p: Node) -> void:
	var held := _held_pizza()
	if held and held.is_boxed() and pass_shelf.size() < PASS_SIZE:
		player.take_held()
		put_on_pass(held)
	elif not player.is_holding() and not pass_shelf.is_empty():
		var p: Pizza = pass_shelf.pop_front()
		player.hold(p)
		_layout_pass()


func pass_has_room() -> bool:
	return pass_shelf.size() < PASS_SIZE


func put_on_pass(p: Pizza) -> void:
	pass_shelf.append(p)
	p.location = "shelf"
	_layout_pass()
	Sfx.play("ding", 1.0, -8.0)


func _layout_pass() -> void:
	for i in pass_shelf.size():
		var p := pass_shelf[i]
		p.reparent(_pass_spots[i], true)
		var tw := p.create_tween()
		tw.tween_property(p, "position", Vector3.ZERO, 0.2)
		tw.parallel().tween_property(p, "rotation", Vector3.ZERO, 0.2)


func _trash_prompt(_p: Node) -> String:
	return "[E] Throw it away" if player.is_holding() and not busy else ""


func _trash_use(_p: Node) -> void:
	var item := player.take_held()
	if item is Pizza:
		var tid: int = (item as Pizza).data.ticket
		var t := Game.ticket(tid)
		if not t.is_empty() and t.status not in ["delivered", "failed"]:
			Game.set_ticket_status(tid, "new")
	item.queue_free()
	player.hands.play("push")
	Sfx.play("splat")


## Every pizza currently sitting in the kitchen (for tests and the HUD).
func pizzas_in_kitchen() -> Array[Pizza]:
	var out: Array[Pizza] = []
	if board_pizza:
		out.append(board_pizza)
	if cut_pizza:
		out.append(cut_pizza)
	for o in ovens:
		if o.pizza:
			out.append(o.pizza)
	out.append_array(pass_shelf)
	return out


# --- puddles ----------------------------------------------------------------------------------------------

func add_puddle(local: Vector3, r: float, permanent: bool) -> void:
	var puddle := Node3D.new()
	puddle.position = local + Vector3(0, 0.084, 0)
	puddle.set_meta("radius", r)
	puddle.add_to_group("slippery")
	pizzeria.add_child(puddle)
	var col := Color("#a9dcef") if permanent else Color("#c8321f")
	var blob := Toon.cyl(puddle, r, r, 0.006, Vector3.ZERO, col, 0.0, 10)
	blob.scale = Vector3(1.0, 1.0, 0.75)
	for k in 3:
		var a := randf() * TAU
		Toon.cyl(puddle, r * 0.3, r * 0.3, 0.006, Vector3(cos(a) * r * 0.8, 0, sin(a) * r * 0.6), col, 0.0, 7)
	if permanent:
		# The famous yellow sign nobody reads
		var sign := Node3D.new()
		sign.position = Vector3(r + 0.15, 0, 0)
		puddle.add_child(sign)
		for s: int in [-1, 1]:
			var leg := Toon.box(sign, Vector3(0.32, 0.6, 0.02), Vector3(0, 0.3, 0.1 * s), Color("#f1c40f"), 0.008)
			leg.rotation.x = 0.2 * s
		var l := Toon.label(sign, "CAUTION\nWET\nFLOOR", Vector3(0, 0.33, 0.13), 14, Color("#2b1c18"), false)
		l.outline_size = 0
		l.rotation.x = 0.2
	else:
		get_tree().create_timer(90.0).timeout.connect(puddle.queue_free)


# --- phone prop -----------------------------------------------------------------------------------------

func _build_phone() -> void:
	var pos := Pizzeria.ANCHORS.phone as Vector3
	var root := _spot(pos)
	Toon.block(root, Vector3(0.24, 0.36, 0.08), Vector3(0, -0.18, 0.1), Color("#c0392b"), 0.04, 0.008)
	for k in 9:
		Toon.cyl(root, 0.018, 0.018, 0.01, Vector3(-0.06 + (k % 3) * 0.06, -0.02 - (k / 3) * 0.06, 0.06), Color("#f6f4ef"), 0.0, 6).rotation.x = PI / 2
	_phone_handset = Node3D.new()
	_phone_handset.position = Vector3(0.0, 0.06, 0.05)
	root.add_child(_phone_handset)
	Toon.block(_phone_handset, Vector3(0.3, 0.06, 0.07), Vector3(0, 0, 0), Color("#c0392b"), 0.03, 0.008)
	for s: int in [-1, 1]:
		Toon.ball(_phone_handset, 0.045, Vector3(0.14 * s, -0.01, 0.0), Color("#c0392b"), 0.006, 8)
	# Curly cord
	for k in 8:
		Toon.ball(root, 0.012, Vector3(0.15 + sin(k * 1.4) * 0.02, -0.05 - k * 0.04, 0.12), Color("#2d3436"), 0.0, 4)
	var l := Toon.label(root, "ORDERS", Vector3(0, 0.25, 0.06), 20, Color("#2b1c18"), false)
	l.outline_size = 0
	l.rotation.y = PI


func _update_phone() -> void:
	if _phone_handset == null:
		return
	var ringing := phone != null and phone.is_ringing()
	if ringing:
		_phone_handset.position.y = 0.06 + absf(sin(_t * 30.0)) * 0.035
		_phone_handset.rotation.z = sin(_t * 41.0) * 0.12
	else:
		_phone_handset.position.y = 0.06
		_phone_handset.rotation.z = 0.0


# --- Tony ----------------------------------------------------------------------------------------------------

const TONY_SPOTS := [Vector3(-1.0, 0, -5.0), Vector3(0.6, 0, -2.0), Vector3(-7.4, 0, -5.4), Vector3(-2.6, 0, -1.6), Vector3(3.0, 0, -6.2), Vector3(-0.5, 0, -6.8)]
const TONY_FIDGETS := ["look_around", "scratch", "tap_foot", "yawn", "flex", "shrug"]


func _build_tony() -> void:
	tony = EggBody.new()
	pizzeria.add_child(tony)
	tony.build(Characters.TONY.look)
	tony.position = Pizzeria.ANCHORS.tony
	tony.set_meta("on_poked", _tony_poked)
	tony.set_meta("tony", true)
	_tony_target = tony.position
	var talk := Station.make(tony, Vector3(0, 1.1, 0), _tony_prompt, _tony_use, 2.0, 0.5)
	talk.name = "TonyTalk"


func _tony_prompt(_p: Node) -> String:
	return "" if busy or player.is_holding() else "[E] Talk to Tony"


func _tony_use(p: Node) -> void:
	if on_tony.is_valid():
		on_tony.call(p)


func _tony_poked() -> void:
	Game.say_toast(["TONY: Don't poke the boss!", "TONY: Do I look like a doorbell?!", "TONY: That's coming outta your paycheck!", "TONY: HEY. Pizza. Now."].pick_random(), UiTheme.YELLOW)


func _update_tony(delta: float) -> void:
	if Game.in_dialogue:
		tony.speed = 0.0
		return
	_tony_t -= delta
	if _tony_t <= 0.0:
		_tony_t = randf_range(4.0, 9.0)
		if randf() < 0.35:
			tony.play(TONY_FIDGETS.pick_random())
		else:
			_tony_target = TONY_SPOTS.pick_random()
	# Watch the player when they're working nearby.
	tony.look_target = player if player and player.global_position.distance_to(tony.global_position) < 4.0 else null
	var to := _tony_target - tony.position
	to.y = 0.0
	if to.length() > 0.15 and not tony.is_playing():
		var step := to.normalized() * minf(1.6 * delta, to.length())
		tony.position += step
		tony.rotation.y = lerp_angle(tony.rotation.y, atan2(to.x, to.z), 1.0 - exp(-8.0 * delta))
		tony.speed = 0.7
	else:
		tony.speed = 0.0
