extends Node
## Dev tool: boots the real game and saves screenshots of key views.
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
	main._start_game(true)
	var player: PlayerEgg = main.player
	var pz: Pizzeria = main.town.pizzeria
	# Kitchen: stand by the prep table, a ticket + pizza in progress
	main.phone.ring(main.town.houses[2])
	main._answer_phone()
	await get_tree().create_timer(5.5).timeout
	player.global_position = pz.anchor("prep") + pz.global_basis.z * 2.0
	main.camera.foot_yaw = pz.global_rotation.y
	MakelineUi.autoplay = true
	await _frames(30)
	await _shot("02_kitchen")
	# Ringing phone banner + carrying a box like the poster
	var p := Pizza.new()
	p.setup(1, "large", 1.0)
	p.put_in_box(1.0)
	player.hold(p)
	player.global_position = pz.anchor("door") + pz.global_basis.z * 3.0
	main.camera.foot_yaw = pz.global_rotation.y + 0.5
	await _frames(40)
	await _shot("03_outside_carrying")
	# Driving through downtown
	main._try_enter_car()
	var c: PizzaCar = main.car
	c.respawn_at(Vector3(main.town.road_x(2) + 2.6, 0.4, main.town.road_z(1) + 16.0), 0.0)
	main.camera.snap()
	await _frames(40)
	await _shot("04_driving")
	# A house + resident at the door
	var h: House = main.town.houses[6]
	main._exit_car(false)
	player.global_position = h.knock_spot.global_position + h.global_basis.z * 2.5
	h.come_out()
	main.camera.foot_yaw = h.global_rotation.y
	await _frames(40)
	await _shot("05_house")
	# Sunset + night
	Game.clock = Game.OPEN_MINUTE + 0.72 * (Game.CLOSE_MINUTE - Game.OPEN_MINUTE)
	player.global_position = pz.anchor("parking") + pz.global_basis.z * 8.0
	main.camera.foot_yaw = pz.global_rotation.y + PI + 0.4
	await _frames(30)
	await _shot("06_sunset")
	Game.clock = Game.OPEN_MINUTE + 0.95 * (Game.CLOSE_MINUTE - Game.OPEN_MINUTE)
	player.global_position = pz.anchor("parking") + pz.global_basis.z * 4.0
	main.camera.foot_yaw = pz.global_rotation.y + 0.3
	await _frames(30)
	await _shot("07_night")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
