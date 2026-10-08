extends Node
## Dev tool: first-person hands in each pose and mid-animation.
##   godot --path . res://tools/hand_shots.tscn -- out=/tmp/hands
var main: Node
var out := "/tmp/hands"
func _ready() -> void:
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
	main.hud.get_child(0).visible = false
	main.hud.set_process(false)
	var p: PlayerEgg = main.player
	var pz: Pizzeria = main.town.pizzeria
	p.global_position = pz.to_global(Vector3(-4.5, 0.05, -1.5))
	p.face(PI, -0.12)
	await _f(30)
	await _shot("idle")
	for g in ["open", "fist", "point", "grip", "pinch"]:
		for i in 2:
			pass
	# prop on the floor to pick up
	var prop: Throwable = main.disasters.spawn_prop("chicken", p.camera.global_position + p.forward() * 1.0 + Vector3(0, -1.2, 0))
	await _f(40)
	p.chaos_focus = prop
	p.chaos_toggle()
	for k in [4, 10, 16, 22, 30, 44]:
		await _f(k - (0 if k == 4 else _last))
		_last = k
		await _shot("pickup_%02d" % k)
	await _f(30)
	await _shot("holding")
	p.throw_chaos()
	_last = 0
	for k in [6, 12, 18, 24]:
		await _f(6)
		await _shot("throw_%02d" % k)
	await _f(30)
	# a pizza box in both hands
	p.hands.play("poke")
	await _f(8)
	await _shot("poke")
	get_tree().quit()
var _last := 0
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame
