extends Node
## Builds Eggville and runs the game loop:
##   title -> day (phone rings -> make pizza -> load car -> drive -> deliver) -> closing time
##   -> report + upgrades -> next day

const ENTER_CAR_DISTANCE := 4.5

var town: Town
var day_cycle: DayCycle
var kitchen: Kitchen
var phone: PhoneLine
var player: PlayerEgg
var car: PizzaCar
var camera: GameCamera
var traffic: Traffic
var pedestrians: Pedestrians
var hud: Hud
var dialogue: DialogueUi
var minigame: MinigameUi
var makeline: MakelineUi
var convo: Conversation
var menus: Menus
var arrow: Node3D
var in_car := false
var _car_station: Station


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261007

	day_cycle = DayCycle.new()
	add_child(day_cycle)
	town = Town.new()
	add_child(town)
	town.generate(20261007)
	day_cycle.town = town

	kitchen = Kitchen.new()
	add_child(kitchen)

	player = PlayerEgg.new()
	add_child(player)
	car = PizzaCar.new()
	add_child(car)
	car.crashed.connect(_on_crash)

	camera = GameCamera.new()
	add_child(camera)
	camera.current = true

	traffic = Traffic.new()
	traffic.town = town
	traffic.player_car = car
	traffic.player = player
	add_child(traffic)
	traffic.spawn(10, rng)
	pedestrians = Pedestrians.new()
	pedestrians.town = town
	pedestrians.car = car
	add_child(pedestrians)
	pedestrians.spawn(22, rng)
	pedestrians.yeeted.connect(_on_yeet)

	phone = PhoneLine.new()
	phone.town = town
	add_child(phone)

	# UI
	hud = Hud.new()
	hud.phone = phone
	hud.car = car
	hud.player = player
	add_child(hud)
	dialogue = DialogueUi.new()
	add_child(dialogue)
	minigame = MinigameUi.new()
	add_child(minigame)
	makeline = MakelineUi.new()
	add_child(makeline)

	kitchen.minigame = minigame
	kitchen.makeline = makeline
	kitchen.camera = camera
	kitchen.setup(town.pizzeria)
	kitchen.on_phone = _answer_phone
	kitchen.phone_prompt = _phone_prompt
	kitchen.on_pc = _open_pc
	kitchen.on_tony = _talk_to_tony

	convo = Conversation.new()
	convo.ui = dialogue
	convo.player = player
	convo.car = car
	convo.camera = camera
	convo.kitchen = kitchen
	add_child(convo)
	dialogue.mic_level_source = convo.mic.level
	dialogue.player_typed.connect(convo.player_says)
	dialogue.talk_pressed.connect(convo.push_to_talk_pressed)
	dialogue.talk_released.connect(convo.push_to_talk_released)
	dialogue.leave_pressed.connect(convo.leave)
	House.on_knock = _on_knock

	_car_station = Station.make(car, Vector3(0, 1.0, 2.6), _car_prompt, _car_use, 2.6)

	menus = Menus.new()
	add_child(menus)
	menus.start_requested.connect(_start_game)
	menus.next_day_requested.connect(start_day)
	menus.resume_requested.connect(resume)
	menus.title_requested.connect(go_to_title)

	arrow = _make_arrow()
	add_child(arrow)

	Game.day_ended.connect(_on_day_ended)
	Game.tickets_changed.connect(_refresh_targets)

	for n in [day_cycle, town, kitchen, player, car, camera, traffic, pedestrians, phone, hud, dialogue, minigame, makeline, convo, arrow]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	go_to_title()


# --- flow ---------------------------------------------------------------------------------

func go_to_title() -> void:
	get_tree().paused = false
	convo.end()
	if Game.day_running:
		Game.save_game()
	Game.day_running = false
	player.controls_enabled = false
	hud.visible = false
	arrow.visible = false
	camera.orbiting = true
	camera.orbit_center = town.pizzeria.global_position
	day_cycle.apply(0.62)
	menus.show_title()


func _start_game(new_game: bool) -> void:
	if new_game:
		Game.reset_save()
	start_day()


func start_day() -> void:
	get_tree().paused = false
	convo.end()
	menus.hide_menus()
	hud.visible = true
	camera.orbiting = false
	_exit_car(false)
	player.global_position = town.pizzeria.anchor("spawn")
	player.velocity = Vector3.ZERO
	player.controls_enabled = true
	_park_car()
	for p in car.cargo.duplicate():
		car.unload_pizza(p)
		p.queue_free()
	camera.target = player
	camera.snap()
	phone.reset()
	Game.start_day()
	Sfx.start_music()
	Game.say_toast("DAY %d! Tony's is OPEN. Wait for the phone..." % Game.day)


func _park_car() -> void:
	var spot := town.pizzeria.anchor("parking")
	car.respawn_at(spot + Vector3(0, 0.3, 0), town.pizzeria.global_rotation.y)


func pause() -> void:
	if not Game.day_running:
		return
	get_tree().paused = true
	menus.show_pause()


func resume() -> void:
	menus.hide_menus()
	get_tree().paused = false


func _open_pc(_p: Node) -> void:
	get_tree().paused = true
	menus.open_shop(false)


func _talk_to_tony(_p: Node) -> void:
	if not convo.active:
		convo.start_tony()


func _on_day_ended(summary: Dictionary) -> void:
	convo.end()
	player.controls_enabled = false
	hud.visible = false
	arrow.visible = false
	Sfx.play("cash")
	menus.show_results(summary)


# --- phone ------------------------------------------------------------------------------------

func _phone_prompt(_p: Node) -> String:
	if phone.is_ringing():
		return "[E] ANSWER THE PHONE! (%s)" % phone.caller.display_name()
	return "Phone (quiet... for now)"


func _answer_phone(_p: Node = null) -> void:
	if not phone.is_ringing() or convo.active or kitchen.busy:
		return
	var caller := phone.answer()
	convo.start_phone(caller)


# --- input ---------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if convo.active:
			convo.leave()
		elif get_tree().paused:
			resume()
		elif Game.day_running and not kitchen.busy:
			pause()
		get_viewport().set_input_as_handled()
		return
	if not Game.day_running or get_tree().paused:
		return
	if convo.active:
		if dialogue.is_typing():
			return
		if event.is_action_pressed("push_to_talk") and not event.is_echo():
			convo.push_to_talk_pressed()
		elif event.is_action_released("push_to_talk"):
			convo.push_to_talk_released()
		return
	if kitchen.busy:
		return
	if event.is_action_pressed("interact") and not in_car:
		player.interact()
	elif event.is_action_pressed("car"):
		if in_car:
			_exit_car(true)
		else:
			_try_enter_car()
	elif event.is_action_pressed("answer_phone") and Game.has_upgrade("headset"):
		_answer_phone()
	elif event.is_action_pressed("respawn") and in_car:
		car.respawn_at(car.global_position + Vector3(0, 1.5, 0), car.rotation.y)


# --- car ------------------------------------------------------------------------------------------

func _try_enter_car() -> void:
	if player.global_position.distance_to(car.global_position) > ENTER_CAR_DISTANCE:
		return
	if player.is_holding():
		var held := player.held as Pizza
		if held and held.is_boxed() and car.cargo.size() < car.capacity():
			_load_into_car(held)
		else:
			Game.say_toast("Put that down first!", Color("#ff9f1c"))
			return
	in_car = true
	player.controls_enabled = false
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = car.global_position + Vector3(0, -50, 0)
	car.set_driver(true)
	camera.target = car
	Sfx.play("slam", 1.4, -8.0)


func _exit_car(sound: bool) -> void:
	if not in_car:
		player.visible = true
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		return
	in_car = false
	car.set_driver(false)
	var side := car.global_basis.x * -1.9
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.global_position = car.global_position + side + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	player.visible = true
	player.controls_enabled = true
	camera.target = player
	if sound:
		Sfx.play("slam", 1.4, -8.0)


func _load_into_car(p: Pizza) -> void:
	player.take_held()
	car.load_pizza(p)
	Game.set_ticket_status(p.data.ticket, "in_car")
	Sfx.play("pickup", 0.9)


func _car_prompt(p: Node) -> String:
	var pl := p as PlayerEgg
	if in_car or convo.active:
		return ""
	var held := pl.held as Pizza
	if held and held.is_boxed():
		if car.cargo.size() >= car.capacity():
			return "Car is full! (%d/%d) · [F] Drive" % [car.cargo.size(), car.capacity()]
		return "[E] Load pizza #%d (%d/%d) · [F] Load & drive" % [held.data.ticket, car.cargo.size(), car.capacity()]
	if not pl.is_holding() and not car.cargo.is_empty():
		var best := _cargo_for_nearby_house()
		if best:
			return "[E] Grab pizza #%d for #%d · [F] Drive" % [best.data.ticket, Game.ticket(best.data.ticket).house.number]
		return "[E] Grab pizza #%d · [F] Drive" % car.cargo[0].data.ticket
	if not pl.is_holding():
		return "[F] Drive"
	return ""


func _car_use(p: Node) -> void:
	var pl := p as PlayerEgg
	var held := pl.held as Pizza
	if held and held.is_boxed():
		if car.cargo.size() < car.capacity():
			_load_into_car(held)
		return
	if not pl.is_holding() and not car.cargo.is_empty():
		var pick := _cargo_for_nearby_house()
		if pick == null:
			pick = car.cargo[0]
		car.unload_pizza(pick)
		pl.hold(pick)


func _cargo_for_nearby_house() -> Pizza:
	var best: Pizza = null
	var best_d := 40.0
	for p in car.cargo:
		var t := Game.ticket(p.data.ticket)
		if t.is_empty():
			continue
		var d := (t.house as House).global_position.distance_to(car.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _on_knock(h: House, _p: Node) -> void:
	if convo.active or in_car:
		return
	convo.start_door(h)


# --- per frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if get_tree().paused or not Game.day_running:
		return
	var inside := not in_car and town.pizzeria.is_inside(player.global_position)
	var cam_over := town.pizzeria.covers(camera.global_position, 1.0)
	town.pizzeria.set_cutaway(inside or (cam_over and not in_car), camera.global_position)
	player.view_yaw = camera.foot_yaw
	var prompt := ""
	if not convo.active and not kitchen.busy and not in_car and player.focus:
		prompt = player.focus.prompt(player)
	if in_car and not convo.active:
		prompt = "[F] Get out" + ("   ·   [SHIFT] Rocket boost" if Game.has_upgrade("boost") else "")
	hud.set_prompt(prompt)
	hud.set_hint(_next_step())
	Sfx.set_music_mood(day_cycle.night)
	_update_arrow(delta)


## Plain-English "what should I do now" for the HUD.
func _next_step() -> String:
	if phone.is_ringing():
		return "Answer the phone! (%s)" % ("press Q" if Game.has_upgrade("headset") else "it's on the right wall")
	var held := player.held as Pizza
	if held:
		if held.is_boxed():
			return "Load pizza #%d into the car out front, then drive it over." % held.data.ticket if not convo.active else ""
		if held.data.baked:
			return "Cut & box it at the counter in the back right."
		if held.data.get("assembled", false):
			return "Put it in the oven (back wall)."
		return "Put it back on the prep table."
	if kitchen.prep_pizza:
		if not kitchen.prep_pizza.data.get("assembled", false):
			return "Make pizza #%d at the prep table." % kitchen.prep_pizza.data.ticket
		return "Pick up pizza #%d and put it in the oven." % kitchen.prep_pizza.data.ticket
	for o in kitchen.ovens:
		if o.pizza:
			return "Watch the oven! Take it out when it says PERFECT."
	if not kitchen.shelf.is_empty():
		return "Grab the pizza on the shelf and load the car."
	if not car.cargo.is_empty():
		var t := Game.ticket(car.cargo[0].data.ticket)
		var where := "house #%d" % t.house.number if not t.is_empty() else "the customer"
		if in_car:
			return "Follow the arrow to %s. Park, get out (F), grab the pizza (E) and knock." % where
		return "Drive the pizza to %s (F near the car)." % where
	for t in Game.open_tickets():
		if t.status == "new":
			return "Grab dough from the fridge (back left) for #%d." % t.id
	if not Game.day_running:
		return ""
	return "Wait for the phone. Meanwhile: talk to Tony, or buy upgrades on the PC."


func _on_crash(impact: float) -> void:
	camera.shake(clampf(impact / 20.0, 0.2, 1.0))
	if impact > 9.0 and not car.cargo.is_empty():
		Game.say_toast(["BONK", "The pizzas felt that.", "CHEESE DISPLACEMENT", "OOF", "crunch"].pick_random(), UiTheme.RED)


func _on_yeet() -> void:
	camera.shake(0.6)
	Game.say_toast(["YEET", "SORRY!!", "Insurance won't cover that", "They're fine. Probably."].pick_random(), UiTheme.PINK)


func _refresh_targets() -> void:
	var waiting := {}
	for t in Game.open_tickets():
		if t.status == "in_car":
			waiting[t.house] = true
	for h in town.houses:
		h.set_target(waiting.has(h))


# --- the bouncing GPS arrow ------------------------------------------------------------------------

## A flat chevron that hovers just above the ground ahead of you.
func _make_arrow() -> Node3D:
	var root := Node3D.new()
	var head := MeshInstance3D.new()
	head.mesh = Shapes.prism(Vector3(1.0, 0.8, 0.14))
	head.material_override = Toon.glow(Color("#ffd166"), 1.2)
	head.rotation.x = -PI / 2
	head.position = Vector3(0, 0, -0.4)
	root.add_child(head)
	var shaft := MeshInstance3D.new()
	shaft.mesh = Shapes.box(Vector3(0.36, 0.14, 0.7))
	shaft.material_override = Toon.glow(Color("#ffd166"), 1.2)
	shaft.position = Vector3(0, 0, 0.3)
	root.add_child(shaft)
	return root


func _arrow_target() -> Variant:
	var me: Node3D = car if in_car else player
	# Delivering: closest house we have a pizza for (in hand or in the car).
	var pizzas: Array[Pizza] = []
	if player.held is Pizza and (player.held as Pizza).is_boxed():
		pizzas.append(player.held as Pizza)
	pizzas.append_array(car.cargo)
	var best: Variant = null
	var best_d := INF
	for p in pizzas:
		var t := Game.ticket(p.data.ticket)
		if t.is_empty():
			continue
		var h := t.house as House
		var target := h.curb_spot.global_position if in_car else h.knock_spot.global_position
		var d := me.global_position.distance_to(target)
		if d < best_d:
			best_d = d
			best = target
	if best != null:
		return best
	# Otherwise head back to Tony's if there's work there.
	if phone.is_ringing() or not Game.open_tickets().is_empty():
		if in_car or not town.pizzeria.is_inside(player.global_position):
			return town.pizzeria.anchor("parking") if in_car else town.pizzeria.anchor("door")
	return null


func _update_arrow(_delta: float) -> void:
	var target = _arrow_target()
	var me: Node3D = car if in_car else player
	if target == null or convo.active:
		arrow.visible = false
		return
	var to: Vector3 = (target as Vector3) - me.global_position
	to.y = 0.0
	arrow.visible = to.length() > 4.0
	if not arrow.visible:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var ahead := to.normalized() * ((4.5 if in_car else 1.8) + sin(t * 5.0) * 0.25)
	arrow.global_position = me.global_position + ahead + Vector3(0, 0.35, 0)
	arrow.look_at(arrow.global_position + to.normalized(), Vector3.UP)
	arrow.scale = Vector3.ONE * (1.6 if in_car else 1.0)
