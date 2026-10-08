extends Node3D
## Dev tool: renders an egg character in a T-pose (front + 3/4) and relaxed,
## on a plain grey backdrop, to compare against concept art.
##   godot --path . res://tools/model_sheet.tscn -- out=/tmp/sheet

const LOOK := {"skin": "#d9a066", "boots": "#d9a066", "legs": "#d9a066"}


func _ready() -> void:
	var out := "/tmp/sheet"
	var look: Dictionary = LOOK
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a == "player":
			look = Characters.PLAYER_LOOK
		if a == "tony":
			look = Characters.TONY.look
		if a.begins_with("who="):
			for c in Characters.ROSTER:
				if c.id == a.substr(4):
					look = c.look
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#4b4b4b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e0dcd8")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	sun.light_energy = 0.75
	add_child(sun)
	var e := EggBody.new()
	add_child(e)
	e.build(look)
	e.idle_fidgets = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.6
	add_child(cam)
	cam.current = true
	var tpose := {"arm_out": [PI / 2 - 0.1, PI / 2 - 0.1], "arm_fwd": [0.0, 0.0], "arm_bend": [0.0, 0.0],
		"twist": [0.0, 0.0], "grip": [0.15, 0.15], "lean_x": 0.0, "lean_z": 0.0, "yaw": 0.0, "y": 0.0,
		"leg": [0.0, 0.0], "lift": [0.0, 0.0]}
	var shots := [
		["tpose_front", tpose, Vector3(0, 1.0, 6), 0.0],
		["tpose_34", tpose, Vector3(4.2, 1.6, 4.2), 0.0],
		["relaxed_front", {}, Vector3(0, 1.0, 6), 0.0],
		["relaxed_34", {}, Vector3(4.2, 1.6, 4.2), 0.0],
		["side", {}, Vector3(6, 1.0, 0), 0.0],
	]
	for sh in shots:
		e.pose_override = sh[1]
		cam.position = sh[2]
		cam.look_at(Vector3(0, 0.95, 0))
		for i in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, sh[0]])
		print("shot ", sh[0])
	get_tree().quit()
