extends Node
## Headless play-through of a whole day loop (offline brain, auto-played minigames):
##   phone call -> ticket -> dough -> sauce/cheese/toppings -> oven -> cut & box
##   -> load car -> drive -> knock -> deliver -> paid -> upgrade -> end of day -> save
##   godot --headless --path . res://tests/smoke_test.tscn

var main: Node
var failures: PackedStringArray = []


func _ready() -> void:
	Settings.ai_mode = "offline"       # in memory only
	MakelineUi.autoplay = true
	Game.reset_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	main._start_game(true)
	await _frames(5)
	var player: PlayerEgg = main.player
	var kitchen: Kitchen = main.kitchen
	var car: PizzaCar = main.car
	check(Game.day_running, "day started")
	check(main.town.houses.size() >= 40, "town has lots of houses (%d)" % main.town.houses.size())

	# 1. Walk around
	var start := player.global_position
	Input.action_press("accelerate")
	await _physics(40)
	Input.action_release("accelerate")
	check(player.global_position.distance_to(start) > 1.5, "player walks (moved %.1f)" % player.global_position.distance_to(start))

	# 2. Phone rings, we answer, customer orders (offline: orders right away)
	main.phone.ring(main.town.houses[3])
	check(main.phone.is_ringing(), "phone rings")
	main._answer_phone()
	await _seconds(0.6)
	check(Game.open_tickets().size() == 1, "phone call created a ticket")
	await _seconds(4.5)
	check(not main.convo.active, "call ended")
	var t: Dictionary = Game.open_tickets()[0]
	print("     order: ", Menu.describe(t.order), " for ", t.customer)

	# 3. Make the pizza at each station
	await _use_station(player, "fridge")
	check(kitchen.prep_pizza != null, "dough on the prep table")
	await _use_station(player, "prep")
	check(kitchen.prep_pizza != null and kitchen.prep_pizza.data.get("assembled", false), "sauce, cheese and toppings added")
	check(kitchen.prep_pizza.data.toppings.size() == t.order.toppings.size(), "right toppings")
	await _use_station(player, "prep")     # pick up
	check(player.held is Pizza, "holding the raw pizza")
	await _use_station(player, "oven1")
	check(kitchen.ovens[0].pizza != null, "pizza in the oven")
	# Bake to perfect
	var oven_pizza: Pizza = kitchen.ovens[0].pizza
	while float(oven_pizza.data.bake) < 0.98:
		await get_tree().process_frame
	await _use_station(player, "oven1")    # take out
	check(player.held is Pizza and (player.held as Pizza).data.baked, "took a baked pizza out")
	await _use_station(player, "cut")
	check((player.held as Pizza).is_boxed(), "cut and boxed")

	# 4. Load the car and drive there
	player.global_position = car.global_position + car.global_basis.z * 3.0
	await _physics(3)
	main._car_use(player)
	check(car.cargo.size() == 1, "pizza loaded in the car")
	main._try_enter_car()
	check(main.in_car, "got in the car")
	Input.action_press("accelerate")
	await _physics(60)
	Input.action_release("accelerate")
	check(car.forward_speed() > 3.0 or car.velocity.length() > 3.0, "car drives")
	var house: House = t.house
	car.respawn_at(house.curb_spot.global_position + Vector3(0, 0.4, 0) + house.global_basis.z * 3.0, house.global_rotation.y + PI / 2)
	await _physics(5)
	main._exit_car(false)
	check(not main.in_car, "got out of the car")

	# 5. Grab the pizza from the car, knock, deliver
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
	check(Game.today.delivered == 1, "pizza delivered")
	check(Game.money > money_before, "got paid ($%d -> $%d)" % [money_before, Game.money])
	await _seconds(4.0)
	check(not main.convo.active, "conversation closed")

	# 6. Upgrades
	Game.money = 1000
	check(Game.buy_upgrade("engine"), "bought an engine upgrade")
	check(car.max_speed() > 18.0, "engine upgrade makes the car faster")
	check(Game.buy_upgrade("cargo") and car.capacity() == 3, "roof rack holds 3")
	check(Game.buy_upgrade("hat") and Game.current_hat() == "beanie", "bought a new hat")

	# 7. Wrong-house + empty-handed knock don't break anything
	main.convo.start_door(main.town.houses[0])
	await _seconds(0.6)
	main.convo.player_says("pizza!")
	await _seconds(0.3)
	main.convo.leave()

	# 8. Every hand-made character + extras build
	for c in Characters.ROSTER:
		var e := EggBody.new()
		add_child(e)
		e.build(c.look)
		await _frames(1)
		e.queue_free()

	# 9. Phone timeout = missed call
	main.phone.ring(main.town.houses[5])
	main.phone.ring_left = 0.05
	await _seconds(0.2)
	check(Game.today.missed_calls == 1, "unanswered phone counts as missed")

	# 10. End of day + save/load
	Game.clock = Game.CLOSE_MINUTE - 0.01
	await _seconds(0.3)
	check(not Game.day_running, "day ended at closing time")
	check(Game.day == 2, "next day is day 2")
	var saved_money := Game.money
	Game.money = 0
	Game.load_game()
	check(Game.money == saved_money and Game.level("engine") == 1, "save game loads")

	if failures.is_empty():
		print("SMOKE TEST PASSED")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		get_tree().quit(1)


## Walks to a station and presses E (and waits for any minigame to finish).
func _use_station(player: PlayerEgg, anchor: String) -> void:
	var target: Vector3 = main.town.pizzeria.anchor(anchor)
	var station: Station = null
	var best := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Station and n.is_visible_in_tree():
			var d: float = (n as Node3D).global_position.distance_to(target)
			if d < best:
				best = d
				station = n
	station.use(player)
	await _frames(2)
	while main.kitchen.busy:
		await get_tree().process_frame


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
