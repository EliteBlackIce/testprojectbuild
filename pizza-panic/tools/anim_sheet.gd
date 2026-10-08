extends Node3D
## Dev tool: renders eggs frozen mid-animation into one PNG.
##   godot --path . res://tools/anim_sheet.tscn -- out=/tmp/anim.png

const SHOTS := [
	["walk", 0.0], ["walk", 0.18], ["run", 0.1], ["wave", 0.5], ["celebrate", 0.45], ["laugh", 0.5],
	["flex", 0.5], ["stomp", 0.3], ["shrug", 0.5], ["knock", 0.4], ["carry", 0.0], ["tumble", 0.6],
]


func _ready() -> void:
	var out := "/tmp/anim.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9a9690")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d8d0d8")
	env.ambient_light_energy = 0.22
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	add_child(sun)
	Toon.box(self, Vector3(40, 0.1, 20), Vector3(0, -0.05, 0), Color("#b7b1a8"), 0.0)
	var eggs: Array = []
	for i in SHOTS.size():
		var e := EggBody.new()
		add_child(e)
		e.build(Characters.PLAYER_LOOK if i % 2 == 0 else Characters.ROSTER[(i * 5) % Characters.ROSTER.size()].look)
		e.idle_fidgets = false
		var row := i / 6
		var col := i % 6
		e.position = Vector3((col - 2.5) * 1.7, 0, -row * 2.6)
		e.rotation.y = 0.35
		eggs.append(e)
		var kind: String = SHOTS[i][0]
		var lbl := Toon.label(self, kind.to_upper(), e.position + Vector3(0, -0.02, 0.9), 40, Color.WHITE, false)
		lbl.rotation.x = -PI / 2
	# Start everything, then step to the right moment.
	var elapsed := 0.0
	for i in SHOTS.size():
		var e: EggBody = eggs[i]
		var kind: String = SHOTS[i][0]
		match kind:
			"walk":
				e.velocity_hint = e.global_basis * Vector3(0, 0, 1.4)
			"run":
				e.velocity_hint = e.global_basis * Vector3(0, 0, 3.4)
			"carry":
				e.carrying = true
				var p := Pizza.new()
				p.setup(3)
				p.auto_assemble({"size": "large", "sauce": "tomato", "toppings": ["pepperoni"]}, 1.0)
				p.put_in_box(true)
				e.hand_socket.add_child(p)
			"tumble":
				e.tumble(Vector3(1, 0, 0))
			_:
				e.play(kind)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.6, 7.5)
	cam.fov = 50
	add_child(cam)
	cam.look_at(Vector3(0, 0.7, -1.3))
	cam.current = true
	# Advance until each shot's moment; we freeze by pausing per-egg processing.
	for f in 120:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		for i in SHOTS.size():
			var e: EggBody = eggs[i]
			var when: float = SHOTS[i][1] * 2.0 + 0.2
			if elapsed >= when and e.process_mode != Node.PROCESS_MODE_DISABLED:
				e.process_mode = Node.PROCESS_MODE_DISABLED
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
