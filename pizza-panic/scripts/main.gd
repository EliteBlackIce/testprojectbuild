extends Node
## Builds Eggville and runs the game loop, in first person:
##   title -> day (phone rings -> make the pizza by hand -> load car -> drive -> deliver)
##   -> closing time -> report + upgrades/hiring -> next day

const ENTER_CAR_DISTANCE := 4.5

var town: Town
var day_cycle: DayCycle
var kitchen: Kitchen
var staff: Staff
var phone: PhoneLine
var player: PlayerEgg
var car: PizzaCar
var camera: GameCamera          ## title orbit + chase cam (V in the car)
var traffic: Traffic
var pedestrians: Pedestrians
var gags: Gags
var hud: Hud
var dialogue: DialogueUi
var station_ui: StationUi
var convo: Conversation
var menus: Menus
var arrow: Node3D
var in_car := false
var chase_view := false
var _on_title := true


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
	station_ui = StationUi.new()
	add_child(station_ui)

	kitchen = Kitchen.new()
	add_child(kitchen)
	kitchen.phone = phone
	kitchen.setup(town.pizzeria, player, station_ui)
	kitchen.on_phone = _answer_phone
	kitchen.phone_prompt = _phone_prompt
	kitchen.on_pc = _open_pc
	kitchen.on_tony = _talk_to_tony

	staff = Staff.new()
	staff.kitchen = kitchen
	staff.phone = phone
	add_child(staff)

	gags = Gags.new()
	gags.town = town
	gags.car = car
	gags.player = player
	add_child(gags)
	gags.setup()

	convo = Conversation.new()
	convo.ui = dialogue
	convo.player = player
	convo.car = car
	convo.kitchen = kitchen
	convo.gags = gags
	add_child(convo)
	dialogue.mic_level_source = convo.mic.level
	dialogue.player_typed.connect(convo.player_says)
	dialogue.talk_pressed.connect(convo.push_to_talk_pressed)
	dialogue.talk_released.connect(convo.push_to_talk_released)
	dialogue.leave_pressed.connect(convo.leave)
	House.on_knock = _on_knock

	var car_station := Station.make(car, Vector3(0, 1.1, 0.4), _car_prompt, _car_use, 3.4, 1.3)
	car_station.name = "CarStation"

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

	for n in [day_cycle, town, kitchen, staff, player, car, camera, traffic, pedestrians, phone, hud, dialogue, station_ui, convo, gags, arrow]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	go_to_title()


# --- flow ---------------------------------------------------------------------------------

func go_to_title() -> void:
	get_tree().paused = false
	convo.end()
	kitchen.leave_station()
	if Game.day_running:
		Game.save_game()
	Game.day_running = false
	staff.clear()
	_on_title = true
	player.controls_enabled = false
	hud.visible = false
	arrow.visible = false
	camera.orbiting = true
	camera.orbit_center = town.pizzeria.global_position
	camera.current = true
	day_cycle.apply(0.62)
	menus.show_title()


func _start_game(new_game: bool) -> void:
	if new_game:
		Game.reset_save()
	start_day()


func start_day() -> void:
	get_tree().paused = false
	convo.end()
	kitchen.leave_station()
	menus.hide_menus()
	_on_title = false
	hud.visible = true
	camera.orbiting = false
	_exit_car(false)
	player.global_position = town.pizzeria.anchor("spawn")
	player.reset_state()
	# Face the kitchen (the pizzeria may be rotated in town).
	var to_kitchen := town.pizzeria.anchor("prep") - player.global_position
	player.face(atan2(-to_kitchen.x, -to_kitchen.z), -0.15)
	player.controls_enabled = true
	if player.held:
		player.take_held().queue_free()
	_park_car()
	for p in car.cargo.duplicate():
		car.unload_pizza(p)
		p.queue_free()
	for p in kitchen.pizzas_in_kitchen():
		p.queue_free()
	kitchen.board_pizza = null
	kitchen.cut_pizza = null
	kitchen.pass_shelf.clear()
	for o in kitchen.ovens:
		o.pizza = null
	player.camera.current = true
	phone.reset()
	Game.start_day()
	staff.clear()
	staff.sync()
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
	kitchen.leave_station()
	staff.clear()
	player.controls_enabled = false
	hud.visible = false
	arrow.visible = false
	Sfx.play("cash")
	menus.show_results(summary)


# --- phone ------------------------------------------------------------------------------------

func _phone_prompt(_p: Node) -> String:
	if phone.is_ringing():
		return "[E] ANSWER THE PHONE! (%s)" % phone.caller.display_name()
	return "Order phone (quiet... for now)"


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
	if not Game.day_running or get_tree().paused or kitchen.busy:
		return
	if convo.active:
		if dialogue.is_typing():
			return
		if event.is_action_pressed("push_to_talk") and not event.is_echo():
			convo.push_to_talk_pressed()
		elif event.is_action_released("push_to_talk"):
			convo.push_to_talk_released()
		return
	if player.is_tumbling():
		return
	if event.is_action_pressed("interact") and not in_car:
		player.interact()
	elif event.is_action_pressed("poke") and not in_car and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if player.focus:
			player.interact()
		else:
			player.poke()
	elif event.is_action_pressed("car"):
		if in_car:
			_exit_car(true)
		else:
			_try_enter_car()
	elif event.is_action_pressed("view") and in_car:
		chase_view = not chase_view
		_update_car_camera()
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
	_update_car_camera()
	Sfx.play("slam", 1.4, -8.0)


func _update_car_camera() -> void:
	if not in_car:
		return
	car.set_cockpit(not chase_view)
	if chase_view:
		camera.target = car
		camera.current = true
		camera.snap()


func _exit_car(sound: bool) -> void:
	if not in_car:
		player.visible = true
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		return
	in_car = false
	car.set_driver(false)
	car.set_cockpit(false)
	var side := car.global_basis.x * -1.9
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.global_position = car.global_position + side + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	player.face(car.global_rotation.y)
	player.visible = true
	player.controls_enabled = true
	player.camera.current = true
	if sound:
		Sfx.play("slam", 1.4, -8.0)


func _load_into_car(p: Pizza) -> void:
	player.take_held()
	car.load_pizza(p)
	Game.set_ticket_status(p.data.ticket, "in_car")
	player.hands.play("push")
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
	if held:
		return "Box it first! (cutting board in the kitchen)"
	if not car.cargo.is_empty():
		var best := _cargo_for_nearby_house()
		if best:
			return "[E] Grab pizza #%d for house #%d · [F] Drive" % [best.data.ticket, Game.ticket(best.data.ticket).house.number]
		return "[E] Grab pizza #%d · [F] Drive" % car.cargo[0].data.ticket
	return "[F] Drive"


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
	player.hands.play("knock")
	convo.start_door(h)


# --- per frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_mouse()
	if get_tree().paused or not Game.day_running:
		return
	var prompt := ""
	if not convo.active and not kitchen.busy and not in_car and player.focus:
		prompt = player.focus.prompt(player)
	if in_car and not convo.active:
		prompt = "[F] Get out   ·   [SPACE] Drift   ·   [V] %s" % ("cockpit view" if chase_view else "chase cam") + ("   ·   [SHIFT] Rocket boost" if Game.has_upgrade("boost") else "")
	hud.set_prompt(prompt)
	hud.set_crosshair(not in_car and not kitchen.busy and not convo.active)
	hud.visible = not kitchen.busy
	hud.set_hint(_next_step())
	Sfx.set_music_mood(day_cycle.night)
	_update_arrow(delta)
	if in_car:
		var tgt = _arrow_target()
		car.set_gps(town, tgt, _gps_label())


## Mouse is captured for looking around, and freed for menus, talking and station work.
func _update_mouse() -> void:
	var want_free := _on_title or get_tree().paused or menus.is_open() or convo.active or kitchen.busy or not Game.day_running
	var mode := Input.MOUSE_MODE_VISIBLE if want_free else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != mode and DisplayServer.get_name() != "headless":
		Input.mouse_mode = mode


## Plain-English "what should I do now" for the HUD.
func _next_step() -> String:
	if phone.is_ringing():
		return "Answer the phone! (%s)" % ("press Q" if Game.has_upgrade("headset") else "red phone by the pass window")
	if kitchen.busy:
		return ""
	var held := player.held as Pizza
	if held:
		if held.is_boxed():
			return "Load pizza #%d into the car out front (or leave it on the pass shelf)." % held.data.ticket if not convo.active else ""
		if held.data.baked:
			return "Cut & box it at the cutting board (right side of the kitchen)."
		if held.data.assembled:
			return "Slide it into the oven (back wall)."
		return "Put the dough on the prep board (middle island) and make it."
	if kitchen.board_pizza and not kitchen.board_pizza.data.assembled:
		return "Finish pizza #%d at the prep board." % kitchen.board_pizza.data.ticket
	if kitchen.board_pizza:
		return "Pick up pizza #%d and slide it into the oven." % kitchen.board_pizza.data.ticket
	for o in kitchen.ovens:
		if o.pizza:
			return "Watch the oven! Pull it out when it says PERFECT."
	if kitchen.cut_pizza:
		return "Finish cutting pizza #%d." % kitchen.cut_pizza.data.ticket
	if not kitchen.pass_shelf.is_empty():
		return "Grab the boxed pizza from the pass shelf and load the car."
	if not car.cargo.is_empty():
		var t := Game.ticket(car.cargo[0].data.ticket)
		var where := "house #%d" % t.house.number if not t.is_empty() else "the customer"
		if in_car:
			return "Follow the arrow to %s. Park, get out (F), grab the pizza from the car (E) and knock." % where
		return "Drive the pizza to %s (F near the car)." % where
	for t in Game.open_tickets():
		if t.status == "new":
			return "Grab dough from the rack (back left wall) for #%d." % t.id
	if not Game.day_running:
		return ""
	return "Wait for the phone. Meanwhile: talk to Tony, poke Tony, or hire help on the office PC."


## What the dashboard GPS says it's driving you to.
func _gps_label() -> String:
	for p in car.cargo:
		var t := Game.ticket(p.data.ticket)
		if not t.is_empty():
			return "#%d %s (house %d)" % [t.id, t.customer, (t.house as House).number]
	return "Back to Tony's"


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
	if phone.is_ringing() or not Game.open_tickets().is_empty():
		if in_car or not town.pizzeria.is_inside(player.global_position):
			return town.pizzeria.anchor("parking") if in_car else town.pizzeria.anchor("door")
	return null


func _update_arrow(_delta: float) -> void:
	if in_car and not chase_view:
		arrow.visible = false    # the dashboard GPS does the guiding in the cockpit
		return
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
	var cockpit := in_car and not chase_view
	var ahead := to.normalized() * ((9.0 if cockpit else 4.5) if in_car else 2.2) + to.normalized() * sin(t * 5.0) * 0.25
	arrow.global_position = me.global_position + ahead + Vector3(0, 1.7 if cockpit else 0.35, 0)
	arrow.look_at(arrow.global_position + to.normalized(), Vector3.UP)
	arrow.scale = Vector3.ONE * (1.4 if in_car else 0.8)
