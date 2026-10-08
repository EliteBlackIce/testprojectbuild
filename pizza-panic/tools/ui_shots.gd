extends Node
## Dev tool: screenshots of every menu and overlay.
##   godot --path . res://tools/ui_shots.tscn -- out=/tmp/ui

var out := "/tmp/ui"
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	Settings.ai_mode = "offline"
	Game.reset_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(15)
	await _shot("u1_title")
	Game.money = 340
	main._start_game(true)
	await _frames(10)
	Game.hire("carla")
	main.phone.ring(main.town.houses[2])
	Game.add_ticket(main.town.houses[4], "Gary", {"size": "large", "sauce": "tomato", "toppings": ["pepperoni", "mushroom"]})
	Game.add_ticket(main.town.houses[7], "Edna Crumble", {"size": "small", "sauce": "bbq", "toppings": ["sausage"]})
	Game.tickets[1].status = "baking"
	Game.tickets_changed.emit()
	Game.say_toast("Pam took an order! #2: Small BBQ sausage for Edna", UiTheme.YELLOW)
	await _frames(25)
	await _shot("u2_hud")
	main.hud.set_prompt("[E] Slide pizza #1 into the oven")
	await _frames(5)
	await _shot("u3_prompt")
	main.hud.set_prompt("")
	main.pause()
	await _frames(8)
	await _shot("u4_pause")
	main.resume()
	main.menus.show_results({"delivered": 6, "perfect": 3, "failed": 1, "missed_calls": 2, "earned": 188, "tips": 24, "costs": 36, "wages": 40, "staff_made": 5, "rep_start": 2.5, "rep_end": 3.1, "money": 452, "rank": "Pretty Good Egg"})
	await _frames(8)
	await _shot("u5_results")
	main.menus.open_shop(true)
	await _frames(8)
	await _shot("u6_shop")
	main.menus.hide_menus()
	main.menus._open_settings(main.menus._pause)
	await _frames(8)
	await _shot("u7_settings")
	main.menus.hide_menus()
	main.dialogue.open("Gary", "A Very Hungry Customer", true)
	main.dialogue.show_npc_line("Gary", "Hello? Is this the pizza place? *taps phone* I would like the LARGE one. With everything on it.")
	main.dialogue.show_player_line("One large with everything, coming right up!")
	await _frames(40)
	await _shot("u8_dialogue")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
