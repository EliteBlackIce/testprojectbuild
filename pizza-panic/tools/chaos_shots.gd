extends Node
## Dev tool: screenshots of the slapstick layer (props, a bonk, fire, goat, blackout).
##   godot --path . res://tools/chaos_shots.tscn -- out=/tmp/chaos

var out := "/tmp/chaos"
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
	await _frames(10)
	Game.money = 500
	main._start_game(true)
	await get_tree().create_timer(1.5).timeout
	var player: PlayerEgg = main.player
	var pz: Pizzeria = main.town.pizzeria
	# Dining room full of props
	await _stand(pz.to_global(Vector3(-2.0, 0.05, 2.6)), pz.to_global(Vector3(-2.0, 0.6, 6.5)))
	main.disasters.scatter(14)
	await get_tree().create_timer(2.0).timeout
	await _shot("c1_props")
	# Grab + throw
	var t: Throwable = null
	for n in get_tree().get_nodes_in_group("throwable"):
		if t == null or n.global_position.distance_to(player.global_position) < t.global_position.distance_to(player.global_position):
			t = n
	t.global_position = player.camera.global_position + player.forward() * 1.3 + Vector3(0, -0.3, 0)
	t.linear_velocity = Vector3.ZERO
	await _frames(3)
	player.chaos_focus = t
	player.chaos_toggle()
	await _frames(12)
	await _shot("c2_holding")
	var victim := EggBody.new()
	main.add_child(victim)
	victim.build(Characters.random_pedestrian_look(RandomNumberGenerator.new()))
	victim.global_position = player.global_position + Vector3(player.forward().x, 0, player.forward().z).normalized() * 3.2
	player.throw_chaos()
	await get_tree().create_timer(0.38).timeout
	await _shot("c3_bonk")
	await get_tree().create_timer(1.0).timeout
	victim.queue_free()
	# Fire
	await _stand(pz.to_global(Vector3(-4.0, 0.05, -5.6)), pz.to_global(Vector3(-5.6, 0.8, -8.1)))
	main.disasters.trigger("oven_fire")
	await get_tree().create_timer(1.2).timeout
	await _shot("c4_fire")
	main.disasters._cleanup_events()
	# Goat
	await _stand(pz.to_global(Vector3(-2.0, 0.05, 4.5)), pz.to_global(Vector3(-2.0, 0.8, 8.5)))
	main.disasters.trigger("goat")
	await get_tree().create_timer(2.6).timeout
	await _shot("c5_goat")
	main.disasters._cleanup_events()
	main.disasters.trigger("blackout")
	await get_tree().create_timer(1.0).timeout
	await _shot("c6_blackout")
	main.disasters._cleanup_events()
	get_tree().quit()


func _stand(pos: Vector3, look: Vector3) -> void:
	var p: PlayerEgg = main.player
	p.global_position = pos
	var to := look - pos
	p.face(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	await _frames(6)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
