extends Node
## Dev tool: cockpit view with the wheel turned left / straight / right.
var main: Node
func _ready() -> void:
	var out := "/tmp/wheel"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	Settings.ai_mode = "offline"
	Game.reset_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _f(10)
	main._start_game(true)
	await _f(10)
	main.player.global_position = main.car.global_position + main.car.global_basis.x * 2.0
	await _f(2)
	main._try_enter_car()
	main.car.respawn_at(Vector3(main.town.road_x(2) + 2.6, 0.4, main.town.road_z(1) + 16.0), 0.0)
	await _f(30)
	for k in [["left", 1.0], ["straight", 0.0], ["right", -1.0]]:
		main.car._steer = k[1]
		for i in 40:
			main.car._update_cockpit(1.0 / 60.0, 0.0)
			main.car._steer = k[1]
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/wheel_%s.png" % [out, k[0]])
	get_tree().quit()
func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame
