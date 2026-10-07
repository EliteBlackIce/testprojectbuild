extends Node
## Builds the game and runs the main loop: title -> shift -> results.

const TALK_DISTANCE := 6.5

var town: Town
var car: PizzaCar
var camera: ChaseCamera
var hud: Hud
var dialogue: DialogueUi
var convo: Conversation
var menus: Menus
var arrow: Node3D
var _title_orbit := 0.0
var _nearby: House
var _target_house: House


func _ready() -> void:
	# Main keeps running while paused so Esc can unpause; the game world doesn't.
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	town = Town.new()
	add_child(town)
	town.generate(20261007)

	car = PizzaCar.new()
	add_child(car)
	car.respawn_at(town.spawn_point, 0.0)
	car.crashed.connect(_on_crash)

	camera = ChaseCamera.new()
	camera.target = car
	add_child(camera)
	camera.current = true
	camera.snap()

	arrow = _make_arrow()
	add_child(arrow)

	hud = Hud.new()
	add_child(hud)
	dialogue = DialogueUi.new()
	add_child(dialogue)

	convo = Conversation.new()
	convo.ui = dialogue
	convo.car = car
	convo.camera = camera
	convo.town = town
	add_child(convo)
	dialogue.mic_level_source = convo.mic.level
	dialogue.player_typed.connect(convo.player_says)
	dialogue.talk_pressed.connect(convo.push_to_talk_pressed)
	dialogue.talk_released.connect(convo.push_to_talk_released)
	dialogue.leave_pressed.connect(convo.leave)

	menus = Menus.new()
	add_child(menus)
	menus.start_requested.connect(start_shift)
	menus.resume_requested.connect(resume)
	menus.title_requested.connect(go_to_title)

	Game.order_changed.connect(_on_order_changed)
	Game.shift_ended.connect(_on_shift_ended)
	for h in town.all_stops():
		h.resident.launched.connect(_on_npc_launched)

	for n in [town, car, camera, arrow, hud, dialogue, convo]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE

	go_to_title()


# --- flow ---------------------------------------------------------------------------

func go_to_title() -> void:
	get_tree().paused = false
	convo.end()
	Game.running = false
	car.controls_enabled = false
	hud.visible = false
	arrow.visible = false
	camera.follow = false
	menus.show_title()


func start_shift() -> void:
	get_tree().paused = false
	convo.end()
	menus.hide_menus()
	hud.visible = true
	car.respawn_at(town.spawn_point, 0.0)
	car.controls_enabled = true
	camera.follow = true
	camera.snap()
	Game.start_shift()
	Game.say_toast("Go see Tony! (the spinning pizza)")


func pause() -> void:
	if not Game.running:
		return
	get_tree().paused = true
	menus.show_pause()


func resume() -> void:
	menus.hide_menus()
	get_tree().paused = false


func _on_shift_ended(summary: Dictionary) -> void:
	convo.end()
	car.controls_enabled = false
	hud.visible = false
	arrow.visible = false
	Sfx.play("cash")
	menus.show_results(summary)


# --- input --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if convo.active:
			convo.leave()
		elif get_tree().paused:
			resume()
		elif Game.running:
			pause()
		get_viewport().set_input_as_handled()
		return
	if not Game.running or get_tree().paused:
		return
	if convo.active:
		if dialogue.is_typing():
			return
		if event.is_action_pressed("push_to_talk") and not event.is_echo():
			convo.push_to_talk_pressed()
		elif event.is_action_released("push_to_talk"):
			convo.push_to_talk_released()
		return
	if event.is_action_pressed("interact") and _nearby:
		convo.start(_nearby)
	elif event.is_action_pressed("respawn"):
		# Unflip: pop the car back upright where it is.
		car.respawn_at(car.global_position + Vector3(0, 1.5, 0), car.rotation.y)


# --- per frame ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if not Game.running:
		# Slow cinematic orbit behind the title screen.
		_title_orbit += delta * 0.08
		var center := town.shop.global_position
		camera.global_position = center + Vector3(sin(_title_orbit) * 45.0, 22.0, cos(_title_orbit) * 45.0)
		camera.look_at(center + Vector3(0, 4, 0))
		return

	_nearby = null
	if not convo.active:
		var best := TALK_DISTANCE
		for h in town.all_stops():
			var d := Vector2(car.global_position.x - h.stop_point.x, car.global_position.z - h.stop_point.z).length()
			if d < best:
				best = d
				_nearby = h
	if convo.active:
		hud.set_prompt("")
	elif _nearby:
		if _nearby.is_shop:
			hud.set_prompt("[E] Talk to Tony" + ("" if Game.has_order() else " (get an order)"))
		else:
			hud.set_prompt("[E] Knock on #%d (%s)" % [_nearby.number, _nearby.resident.display_name()])
	else:
		hud.set_prompt("")

	_check_npc_hits()
	_update_arrow(delta)


func _check_npc_hits() -> void:
	var speed := car.velocity.length()
	if speed < 7.0:
		return
	for h in town.all_stops():
		var npc := h.resident
		if npc.is_flying() or npc.hidden_inside:
			continue
		var p := npc.global_position
		var c := car.global_position
		if Vector2(p.x - c.x, p.z - c.z).length() < 1.8 and absf(p.y - c.y) < 2.0:
			npc.launch(car.velocity)


func _on_npc_launched() -> void:
	Sfx.play("bonk", 0.7)
	camera.shake(0.6)
	Game.damage_pizza(8.0)
	Game.say_toast(["YEET", "SORRY!!", "THAT'S A CUSTOMER", "Insurance won't cover that"].pick_random(), UiTheme.PINK)


func _on_crash(impact: float) -> void:
	camera.shake(clampf(impact / 20.0, 0.2, 1.0))
	if Game.has_order():
		Game.damage_pizza(impact * 1.6)
		if impact > 9.0:
			Game.say_toast(["BONK", "The pizza felt that.", "CHEESE DISPLACEMENT", "OOF", "crunch"].pick_random(), UiTheme.RED)


func _on_order_changed(order: Dictionary) -> void:
	if _target_house:
		_target_house.set_target(false)
	_target_house = order.get("house") if not order.is_empty() else town.shop
	if _target_house:
		_target_house.set_target(not order.is_empty())


# --- the bouncing arrow over the car --------------------------------------------------

func _make_arrow() -> Node3D:
	var root := Node3D.new()
	var tip := Toon.cylinder(root, 0.0, 0.6, 1.0, Vector3(0, 0, -0.6), Color("#ffd166"), 0.05)
	tip.rotation.x = -PI / 2
	var shaft := Toon.box(root, Vector3(0.4, 0.25, 1.0), Vector3(0, 0, 0.3), Color("#ffd166"), 0.05)
	shaft.position.z = 0.4
	return root


func _update_arrow(_delta: float) -> void:
	var target := town.shop.stop_point
	if Game.has_order():
		target = (Game.order.house as House).stop_point
	var to := target - car.global_position
	to.y = 0.0
	arrow.visible = not convo.active and to.length() > 9.0
	if not arrow.visible:
		return
	var t := Time.get_ticks_msec() / 1000.0
	arrow.global_position = car.global_position + Vector3(0, 3.8 + sin(t * 4.0) * 0.25, 0)
	arrow.look_at(arrow.global_position + to.normalized(), Vector3.UP)
