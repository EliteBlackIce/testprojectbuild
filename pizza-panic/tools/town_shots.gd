extends Node
## Dev tool: renders the town from the air, down the streets and up to individual porches.
##   godot --path . res://tools/town_shots.tscn -- out=/tmp/town [houses=0,3,9]

var out := "/tmp/town"
var main: Node
var cam: Camera3D
var picks: Array = [0, 7, 14, 21, 28, 35]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("houses="):
			picks = Array(a.substr(7).split(",")).map(func(x): return int(x))
	DirAccess.make_dir_recursive_absolute(out)
	Settings.ai_mode = "offline"
	Game.reset_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	main._start_game(true)
	await _frames(10)
	main.hud.visible = false
	main.menus.hide_menus()
	main.player.visible = false
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	var t: Town = main.town
	var mid := t.center()
	await _look(mid + Vector3(0, 175, 120), mid, "t0_aerial")
	var dt := t.block_origin(2, 0) + Vector3(15, 0, 15)
	await _look(dt + Vector3(-34, 26, 56), dt + Vector3(0, 8, 0), "t1_downtown")
	await _look(dt + Vector3(0, 2.0, 40), dt + Vector3(0, 10, 0), "t2_downtown_street")
	for k in picks.size():
		var idx: int = picks[k] % t.houses.size()
		var h: House = t.houses[idx]
		var fwd := h.global_basis.z
		await _look(h.global_position + fwd * 15.0 + Vector3(0, 7.0, 0) + h.global_basis.x * 6.0, h.global_position + Vector3(0, 2.0, 0), "h%d_wide_%d" % [k, h.number])
		await _look(h.global_position + fwd * 9.5 + Vector3(0, 1.7, 0) + h.global_basis.x * 2.0, h.door_spot.global_position + Vector3(0, 1.2, 0), "h%d_porch_%d" % [k, h.number])
	await _look(t.block_origin(0, 2) + Vector3(15, 3.0, 0.5), t.block_origin(0, 2) + Vector3(15, 3.5, 30), "t3_suburb_street")
	get_tree().quit()


func _look(from: Vector3, at: Vector3, name: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
