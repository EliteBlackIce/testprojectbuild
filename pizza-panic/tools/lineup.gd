extends Node3D
## Dev tool: renders a lineup of egg characters to a PNG.
##   godot --path . res://tools/lineup.tscn -- out=/tmp/lineup.png

## You, Tony, then the whole hand-made cast.
func _looks() -> Array:
	var out: Array = [Characters.PLAYER_LOOK, Characters.TONY.look]
	for c in Characters.ROSTER:
		out.append(c.look)
	return out


func _ready() -> void:
	var out := "/tmp/lineup.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9a9690")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d8d0d8")
	env.ambient_light_energy = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 0.8
	add_child(sun)
	Toon.box(self, Vector3(30, 0.1, 10), Vector3(0, -0.05, 0), Color("#a7a29b"), 0.0)
	var looks := _looks()
	for i in looks.size():
		var e := EggBody.new()
		add_child(e)
		e.build(looks[i])
		var row := 0 if i < 7 else 1
		var col := i if i < 7 else i - 7
		var count := 7 if row == 0 else looks.size() - 7
		e.position = Vector3((col - (count - 1) * 0.5) * 1.55, 0, -row * 2.2)
		e.rotation.y = 0.2
		if i == 0:
			e.carrying = true
			var p := Pizza.new()
			p.setup(7, "large", 1.0)
			p.put_in_box(1.0)
			e.hand_socket.add_child(p)
		if i == 4:
			e.waving = true
		if i == 1:
			e.express("happy", 99)
		if i == 9:
			e.express("angry", 99)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.0, 8.5)
	cam.fov = 55
	add_child(cam)
	cam.look_at(Vector3(0, 0.6, -1.0))
	cam.current = true
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
