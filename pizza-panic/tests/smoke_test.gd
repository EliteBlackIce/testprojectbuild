extends Node
## Headless play-through of a whole day loop (offline brain):
##   phone call -> ticket -> aim at stations -> dough -> stretch/sauce/cheese/toppings by hand
##   -> oven -> cut & box -> load car -> drive -> knock -> deliver -> paid -> hire a cook
##   (who makes a whole pizza alone) -> upgrades -> end of day + wages -> save
##   godot --headless --path . res://tests/smoke_test.tscn

var main: Node
var failures: PackedStringArray = []


func _ready() -> void:
	Settings.ai_mode = "offline"       # in memory only
	Game.reset_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	main._start_game(true)
	await _frames(5)
	var player: PlayerEgg = main.player
	var kitchen: Kitchen = main.kitchen
	var car: PizzaCar = main.car
	var pz: Pizzeria = main.town.pizzeria
	check(Game.day_running, "day started")
	check(main.town.houses.size() >= 40, "town has lots of houses (%d)" % main.town.houses.size())
	check(player.camera.current, "first-person camera is active")

	# 1. Walk + hop
	var start := player.global_position
	Input.action_press("accelerate")
	await _physics(40)
	Input.action_release("accelerate")
	check(player.global_position.distance_to(start) > 1.0, "player walks (moved %.1f)" % player.global_position.distance_to(start))

	# 2. Phone rings, we answer, customer orders (offline: orders right away)
	main.phone.ring(main.town.houses[3])
	check(main.phone.is_ringing(), "phone rings")
	main._answer_phone()
	await _seconds(0.6)
	check(Game.open_tickets().size() == 1, "phone call created a ticket")
	await _seconds(4.5)
	check(not main.convo.active, "call ended")
	var t: Dictionary = Game.open_tickets()[0]
	t.order = {"size": "medium", "sauce": "tomato", "toppings": ["pepperoni"]}
	print("     order: ", Menu.describe(t.order), " for ", t.customer)

	# 3. Aim at the dough rack and grab dough (crosshair interaction)
	await _aim_at(player, pz.anchor("dough") + Vector3(0, 1.1, 0), pz.anchor("dough") + pz.global_basis * Vector3(1.6, 1.35, 0.0))
	check(player.focus != null and player.focus.prompt(player).contains("dough"), "crosshair finds the dough rack (%s)" % (player.focus.prompt(player) if player.focus else "nothing"))
	player.interact()
	check(player.held is Pizza, "holding a dough ball")

	# 4. Prep board: put it down -> work mode
	await _aim_at(player, pz.anchor("prep_board"), pz.anchor("prep_board") + pz.global_basis * Vector3(0, 0.5, 1.3))
	check(player.focus != null and player.focus.prompt(player).contains("dough down"), "crosshair finds the prep board")
	player.interact()
	await _frames(3)
	check(kitchen.busy and kitchen.mode == "prep", "entered prep work mode")
	var p: Pizza = kitchen.board_pizza
	# stretch by "dragging"
	for k in 30:
		p.set_stretch(0.1 + k * 0.01)
	kitchen._select_tool("sauce:tomato")
	check(p.data.size == "medium" and float(p.data.dough_q) > 0.6, "stretched to medium (q %.2f)" % p.data.dough_q)
	for k in 260:
		var a := k * 0.7
		var d := fmod(k * 0.013, 1.0) * p.radius() * 0.85
		p.paint_sauce(Vector2(cos(a), sin(a)) * d, "tomato")
	kitchen._select_tool("cheese")
	for k in 120:
		var a := k * 1.3
		var d := fmod(k * 0.017, 1.0) * p.radius() * 0.82
		p.sprinkle_cheese(Vector2(cos(a), sin(a)) * d)
	kitchen._select_tool("top:pepperoni")
	for k in 5:
		p.place_topping("pepperoni", Vector2(cos(k), sin(k)) * 0.15)
	check(p.coverage("sauce") > 0.6, "sauce coverage %.0f%%" % (p.coverage("sauce") * 100))
	kitchen._on_done()
	await _frames(3)
	check(not kitchen.busy, "left the prep station")
	check(player.held == p and p.data.assembled, "holding the assembled pizza")
	check(p.data.toppings == ["pepperoni"], "toppings counted from pieces (%s)" % str(p.data.toppings))
	check(float(p.data.sauce_q) > 0.6 and float(p.data.cheese_q) > 0.5, "sauce/cheese quality from coverage (%.2f / %.2f)" % [p.data.sauce_q, p.data.cheese_q])

	# 5. Oven
	kitchen._oven_use(player, 0)
	check(kitchen.ovens[0].pizza == p, "pizza in the oven")
	while float(p.data.bake) < 0.98:
		await get_tree().process_frame
	kitchen._oven_use(player, 0)
	check(player.held == p and p.data.baked, "took a baked pizza out")

	# 6. Cut + box
	kitchen._cut_use(player)
	await _frames(2)
	check(kitchen.mode == "cut", "entered cut mode")
	var r := p.radius()
	for k in 4:
		var a := k * PI / 4.0
		p.add_cut(Vector2(cos(a), sin(a)) * -r * 1.2, Vector2(cos(a), sin(a)) * r * 1.2)
	check(p.data.cuts == 4, "4 cuts")
	kitchen._on_done()
	await _seconds(1.0)
	check(player.held == p and p.is_boxed(), "cut and boxed")
	check(float(p.data.cut_q) > 0.9, "perfect cuts score high (%.2f)" % p.data.cut_q)

	# 7. Pass shelf round trip
	kitchen._pass_use(player)
	check(kitchen.pass_shelf.size() == 1 and player.held == null, "put on the pass shelf")
	kitchen._pass_use(player)
	check(player.held == p, "grabbed it back")

	# 8. Load the car and drive there
	player.global_position = car.global_position + car.global_basis.z * 3.0
	await _physics(3)
	main._car_use(player)
	check(car.cargo.size() == 1, "pizza loaded in the car")
	main._try_enter_car()
	check(main.in_car and car.cockpit_cam.current, "in the car, cockpit view")
	Input.action_press("accelerate")
	await _physics(60)
	Input.action_release("accelerate")
	check(car.velocity.length() > 3.0, "car drives")
	main._unhandled_input(_action_event("view"))
	check(main.camera.current, "V switches to the chase cam")
	main._unhandled_input(_action_event("view"))
	var house: House = t.house
	car.respawn_at(house.curb_spot.global_position + Vector3(0, 0.4, 0) + house.global_basis.z * 3.0, house.global_rotation.y + PI / 2)
	await _physics(5)
	main._exit_car(false)
	check(not main.in_car and player.camera.current, "got out of the car")

	# 9. Grab the pizza from the car, knock, deliver
	main._car_use(player)
	check(player.held is Pizza, "grabbed the pizza from the car")
	player.global_position = house.knock_spot.global_position + Vector3(0, -0.85, 0)
	await _physics(3)
	main._on_knock(house, player)
	await _seconds(0.8)
	check(main.convo.active and main.convo.mode == "door", "door conversation started")
	var money_before := Game.money
	for i in 5:
		if Game.today.delivered > 0:
			break
		main.convo.player_says("Here's your pizza! good boy tuba kevin abracadabra rival goo boo deal npc arr rhyme wake sing horse beep exquisite sorry whisper yeehaw hat pigeon")
		await _seconds(0.5)
		if Game.today.delivered == 0 and main.gags._wrestle >= 0.0:
			main.gags._wrestle = 1.0   # Chad: we win the arm wrestle
			await _seconds(0.3)
	check(Game.today.delivered == 1, "pizza delivered")
	check(Game.money > money_before, "got paid ($%d -> $%d)" % [money_before, Game.money])
	await _seconds(4.0)
	check(not main.convo.active, "conversation closed")

	# 10. Poke + slip + tumble don't break anything
	player.global_position = pz.anchor("spawn") + Vector3(0, 0.2, 0)
	await _physics(5)
	player.poke()
	player.tumble(Vector3.FORWARD, 1.0)
	check(player.is_tumbling(), "egg tumbles")
	await _seconds(2.5)
	check(not player.is_tumbling(), "egg gets back up")

	# 11. Hire a cook: they make a whole pizza alone
	Game.money = 2000
	check(Game.hire("yolanda"), "hired Nonna Yolanda")
	check(main.staff.workers.has("yolanda"), "cook showed up in the kitchen")
	Game.add_ticket(main.town.houses[7], "Test Egg", {"size": "large", "sauce": "bbq", "toppings": ["mushroom"]})
	Engine.time_scale = 8.0
	var waited := 0.0
	while kitchen.pass_shelf.is_empty() and waited < 40.0:
		await get_tree().create_timer(0.5, true, false, true).timeout
		waited += 0.5
	Engine.time_scale = 1.0
	check(not kitchen.pass_shelf.is_empty(), "cook put a boxed pizza on the pass (%.0fs real)" % waited)
	if not kitchen.pass_shelf.is_empty():
		var cp: Pizza = kitchen.pass_shelf[0]
		check(cp.is_boxed() and cp.data.baked and cp.data.size == "large", "cook's pizza is baked, boxed, large")
		var q := Pizza.quality(cp.data, Game.ticket(cp.data.ticket).order)
		check(q.match > 0.7, "cook's pizza matches the order (%.2f)" % q.match)
	check(Game.hire("pam"), "hired Pam for the phone")
	main.phone.ring(main.town.houses[9])
	var tickets_before := Game.tickets.size()
	var waited_pam := 0.0
	while Game.tickets.size() <= tickets_before and waited_pam < 10.0:
		await _seconds(0.25)
		waited_pam += 0.25
	check(Game.tickets.size() > tickets_before, "Pam answered the phone and wrote a ticket (%.1fs)" % waited_pam)

	# 12. Upgrades
	check(Game.buy_upgrade("engine"), "bought an engine upgrade")
	check(car.max_speed() > 18.0, "engine upgrade makes the car faster")
	check(Game.buy_upgrade("cargo") and car.capacity() == 3, "roof rack holds 3")
	check(Game.buy_upgrade("hat") and Game.current_hat() == "beanie", "bought a new hat")

	# 13. Every hand-made character + all staff build
	for c in Characters.ROSTER:
		var e := EggBody.new()
		add_child(e)
		e.build(c.look)
		await _frames(1)
		e.queue_free()

	# 14. Phone timeout = missed call (fire the phone egg first)
	Game.fire("pam")
	await _frames(2)
	var missed := int(Game.today.missed_calls)
	main.phone.ring(main.town.houses[5])
	main.phone.ring_left = 0.05
	await _seconds(0.2)
	check(Game.today.missed_calls == missed + 1, "unanswered phone counts as missed")

	# 15. End of day: wages + save/load
	var money_pre := Game.money
	Game.clock = Game.CLOSE_MINUTE - 0.01
	await _seconds(0.3)
	check(not Game.day_running, "day ended at closing time")
	check(Game.day == 2, "next day is day 2")
	check(Game.money == money_pre - Game.wages_total(), "wages paid ($%d)" % Game.wages_total())
	var saved_money := Game.money
	Game.money = 0
	Game.load_game()
	check(Game.money == saved_money and Game.level("engine") == 1 and Game.is_hired("yolanda"), "save game loads (money, upgrades, staff)")

	if failures.is_empty():
		print("SMOKE TEST PASSED")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		get_tree().quit(1)


## Stand somewhere and look at a point, then let focus update.
func _aim_at(player: PlayerEgg, target: Vector3, stand: Vector3) -> void:
	player.global_position = Vector3(stand.x, target.y - 1.2 if target.y > 1.2 else 0.0, stand.z)
	player.global_position.y = main.town.pizzeria.global_position.y + 0.05
	await _physics(4)
	var eye := player.global_position + Vector3(0, PlayerEgg.EYE, 0)
	var to := target - eye
	player.face(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	await _frames(2)
	await _physics(3)


func _action_event(action: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


func check(cond: bool, msg: String) -> void:
	print(("ok   - " if cond else "FAIL - ") + msg)
	if not cond:
		failures.append(msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
