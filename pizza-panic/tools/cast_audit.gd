extends Node3D
## Dev tool: four views (front, side, back, head close-up) of every character, for clipping checks.
##   godot --path . res://tools/cast_audit.tscn -- out=/tmp/audit [only=id1,id2]

var out := "/tmp/audit"
var only: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("only="):
			only = Array(a.substr(5).split(","))
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#8fb9d8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d8d0d8")
	env.ambient_light_energy = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 0.8
	add_child(sun)
	Toon.box(self, Vector3(20, 0.1, 20), Vector3(0, -0.05, 0), Color("#b7c9a0"), 0.0)
	var cam := Camera3D.new()
	cam.fov = 28.0
	add_child(cam)
	cam.current = true
	var looks: Array = [["player", Characters.PLAYER_LOOK], ["tony", Characters.TONY.look]]
	for c in Characters.ROSTER:
		looks.append([c.id, c.look])
	for id in StaffData.CANDIDATES:
		looks.append(["staff_" + id, StaffData.CANDIDATES[id].look])
	for entry in looks:
		var id: String = entry[0]
		if not only.is_empty() and not only.has(id):
			continue
		var e := EggBody.new()
		add_child(e)
		e.build((entry[1] as Dictionary).duplicate())
		e.set_process(false)
		for f in 90:
			e._process(1.0 / 60.0)
		var hs := e._s
		var views := [
			["front", Vector3(0, 0.95 * hs, 5.4 * hs), Vector3(0, 0.95 * hs, 0)],
			["side", Vector3(5.4 * hs, 0.95 * hs, 0), Vector3(0, 0.95 * hs, 0)],
			["back", Vector3(0, 0.95 * hs, -5.4 * hs), Vector3(0, 0.95 * hs, 0)],
			["head", Vector3(1.1 * hs, 1.62 * hs, 1.6 * hs), Vector3(0, 1.5 * hs, 0)],
		]
		cam.fov = 28.0
		for v in views:
			cam.fov = 10.0 if v[0] == "head" else 28.0
			cam.global_position = v[1]
			cam.look_at(v[2], Vector3.UP)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, id, v[0]])
		print("shot ", id)
		e.queue_free()
		await get_tree().process_frame
	get_tree().quit()
