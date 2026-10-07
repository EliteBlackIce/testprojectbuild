extends Node
## Headless smoke test: boots the real game, drives, gets an order from Tony,
## delivers it (offline brain), crashes into a wall, and checks the results.
##   godot --headless --path . res://tests/smoke_test.tscn

var main: Node
var failures: PackedStringArray = []


func _ready() -> void:
	Settings.ai_mode = "offline"   # in memory only; never saved by this test
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	main.start_shift()
	check(Game.running, "shift should be running")

	# 1. Drive forward for a second.
	var start_pos: Vector3 = main.car.global_position
	Input.action_press("accelerate")
	await _physics(60)
	Input.action_release("accelerate")
	var moved: float = main.car.global_position.distance_to(start_pos)
	check(moved > 3.0, "car should drive forward (moved %.2f)" % moved)

	# 2. Hop.
	Input.action_press("hop")
	await _physics(2)
	Input.action_release("hop")
	await _physics(10)
	check(main.car.global_position.y > 0.3, "car should be airborne after hop")
	await _physics(60)

	# 3. Get an order from Tony.
	main.car.respawn_at(main.town.shop.stop_point + Vector3(0, 0.6, 0))
	await _physics(5)
	main.convo.start(main.town.shop)
	await _seconds(0.5)
	check(Game.has_order(), "Tony should hand out an order")
	main.convo.player_says("can I get a raise?")
	await _seconds(0.3)
	main.convo.end()
	check(not Game.in_dialogue, "dialogue should be closed")

	# 4. Deliver it.
	var house: House = Game.order.house
	main.car.respawn_at(house.stop_point + Vector3(0, 0.6, 0))
	await _physics(5)
	main.convo.start(house)
	await _seconds(0.8)
	for i in 5:
		if Game.deliveries > 0:
			break
		main.convo.player_says("Here's your pizza! good boy, tuba, Kevin, abracadabra, rival, goo goo, boo, deal, npc")
		await _seconds(0.4)
	check(Game.deliveries == 1, "delivery should complete (deliveries=%d)" % Game.deliveries)
	check(Game.money > 0, "should have earned money ($%d)" % Game.money)
	await _seconds(4.0)
	check(not main.convo.active, "conversation should auto-close after delivery")

	# 5. Wrong-house / no-pizza conversation shouldn't break anything.
	var other: House = main.town.houses[0]
	main.convo.start(other)
	await _seconds(0.7)
	main.convo.player_says("pizza delivery!")
	await _seconds(0.3)
	main.convo.leave()

	# 6. Slam into a house at full speed.
	var target: House = main.town.houses[1]
	main.car.respawn_at(target.global_position + Vector3(0, 0.6, 14.0), 0.0)
	Input.action_press("accelerate")
	await _physics(120)
	Input.action_release("accelerate")
	check(main.car.global_position.distance_to(target.global_position) > 3.0, "car shouldn't clip into houses")

	# 7. Babble + all the synthesized sounds exist.
	var b := Sfx.babble("Hello there, pizza person!", 220.0)
	check(b.data.size() > 1000, "babble should produce audio")

	# 8. Every character builds.
	for c in Characters.ROSTER:
		var n := Npc.new()
		n.setup(c)
		add_child(n)
		await _frames(1)
		n.queue_free()

	# 9. End the shift early.
	Game.shift_time = Game.SHIFT_SECONDS
	await _frames(3)
	check(not Game.running, "shift should end")

	if failures.is_empty():
		print("SMOKE TEST PASSED")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		get_tree().quit(1)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok   - " + msg)
	else:
		print("FAIL - " + msg)
		failures.append(msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
