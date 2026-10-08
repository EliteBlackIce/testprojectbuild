extends Node
## Dev tool: boots the real game and saves first-person screenshots of key moments.
##   godot --path . res://tools/screens.tscn -- out=/tmp/shots

var main: Node
var out := "/tmp/shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	Settings.ai_mode = "offline"
	Game.reset_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	await _shot("01_title")
	Game.money = 5000
	main._start_game(true)
	Game.hire("carla")
	var player: PlayerEgg = main.player
	var pz: Pizzeria = main.town.pizzeria
	var kitchen: Kitchen = main.kitchen
	main.phone.ring(main.town.houses[2])
	main._answer_phone()
	await get_tree().create_timer(5.5).timeout
	Game.add_ticket(main.town.houses[4], "Gary", {"size": "large", "sauce": "tomato", "toppings": ["pepperoni", "mushroom"]})
	await get_tree().create_timer(3.0).timeout
	# Kitchen overview in first person
	await _stand(player, pz.to_global(Vector3(-1.2, 0, -1.4)), pz.to_global(Vector3(-5.0, 1.0, -4.5)))
	await _frames(20)
	await _shot("02_kitchen")
	if OS.get_cmdline_user_args().has("quick"):
		player.hands.play("poke")
		await get_tree().create_timer(0.12).timeout
		await _shot("02b_poke")
		get_tree().quit()
		return
	# Grab dough, start the pizza
	await _stand(player, pz.to_global(Vector3(-8.6, 0, -2.6)), pz.anchor("dough") + Vector3(0, 1.0, 0))
	await _frames(10)
	await _shot("03_dough_rack")
	player.interact()
	await _frames(10)
	await _stand(player, pz.to_global(Vector3(-4.5, 0, -2.0)), pz.anchor("prep_board"))
	await _frames(8)
	await _shot("04_holding_dough")
	player.interact()
	await get_tree().create_timer(1.0).timeout
	var p: Pizza = kitchen.board_pizza
	for k in 26:
		p.set_stretch(0.1 + k * 0.012)
	await _frames(5)
	await _shot("05_stretch")
	kitchen._select_tool("sauce:tomato")
	for k in 150:
		var a := k * 0.7
		var d := fmod(k * 0.013, 1.0) * p.radius() * 0.9
		p.paint_sauce(Vector2(cos(a), sin(a)) * d, "tomato")
	kitchen._select_tool("cheese")
	for k in 60:
		var a := k * 1.3
		var d := fmod(k * 0.017, 1.0) * p.radius() * 0.8
		p.sprinkle_cheese(Vector2(cos(a), sin(a)) * d)
	kitchen._select_tool("top:pepperoni")
	for k in 7:
		p.place_topping("pepperoni", Vector2(cos(k * 0.9), sin(k * 0.9)) * (0.1 + k * 0.025))
	await _frames(10)
	await _shot("06_toppings")
	kitchen._on_done()
	await get_tree().create_timer(1.2).timeout
	# Oven
	await _stand(player, pz.to_global(Vector3(-5.6, 0, -6.0)), pz.anchor("oven1") + Vector3(0, 1.0, 0) + pz.global_basis.z * 0.8)
	kitchen._oven_use(player, 0)
	p.set_bake(0.9)
	await _frames(20)
	await _shot("07_oven")
	p.set_bake(1.0)
	kitchen._oven_use(player, 0)
	await _frames(5)
	# Cut
	await _stand(player, pz.to_global(Vector3(1.6, 0, -2.4)), pz.anchor("cut_board"))
	kitchen._cut_use(player)
	await get_tree().create_timer(1.0).timeout
	var r := p.radius()
	for k in 3:
		var a := k * PI / 4.0 + 0.1
		p.add_cut(Vector2(cos(a), sin(a)) * -r * 1.2, Vector2(cos(a), sin(a)) * r * 1.2)
	await _frames(5)
	await _shot("08_cut")
	kitchen._on_done()
	await get_tree().create_timer(1.6).timeout
	# Carrying the box out the front door
	await _stand(player, pz.to_global(Vector3(0, 0, 10.5)), pz.anchor("parking") + Vector3(0, 0.8, 0))
	await _frames(30)
	await _shot("09_carry_box")
	# Driving (cockpit)
	player.global_position = main.car.global_position + main.car.global_basis.x * 2.0
	await _frames(2)
	main._try_enter_car()
	var c: PizzaCar = main.car
	c.respawn_at(Vector3(main.town.road_x(2) + 2.6, 0.4, main.town.road_z(1) + 16.0), 0.0)
	await _frames(40)
	await _shot("10_cockpit")
	main.chase_view = true
	main._update_car_camera()
	await _frames(30)
	await _shot("11_chase_cam")
	main.chase_view = false
	# A house + resident at the door
	var h: House = main.town.houses[6]
	main._exit_car(false)
	h.come_out()
	await _stand(player, h.knock_spot.global_position + h.global_basis.z * 1.5, h.resident.global_position + Vector3(0, 1.0, 0))
	await _frames(40)
	await _shot("12_house")
	# Staff at work
	await _stand(player, pz.to_global(Vector3(-3.0, 0, -0.8)), pz.to_global(Vector3(-6.0, 1.0, -3.0)))
	await _frames(20)
	await _shot("13_staff")
	# Night
	Game.clock = Game.OPEN_MINUTE + 0.95 * (Game.CLOSE_MINUTE - Game.OPEN_MINUTE)
	await _stand(player, pz.anchor("parking") + pz.global_basis.z * 6.0, pz.global_position + Vector3(0, 3.0, 0))
	await _frames(30)
	await _shot("14_night")
	get_tree().quit()


func _stand(player: PlayerEgg, where: Vector3, look: Vector3) -> void:
	player.global_position = Vector3(where.x, main.town.pizzeria.global_position.y + 0.05, where.z)
	player.velocity = Vector3.ZERO
	var to := look - (player.global_position + Vector3(0, PlayerEgg.EYE, 0))
	player.face(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	await _frames(3)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
