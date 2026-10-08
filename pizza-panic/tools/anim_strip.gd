extends Node3D
## Dev tool: filmstrips of the egg animation. Row 1: a ragdoll fall over time. Row 2: walk cycle.
## Row 3: run cycle. Every egg is stepped manually with a fixed time step, so frames line up.
##   godot --path . res://tools/anim_strip.tscn -- out=/tmp/strip [who=player|tony|<id>] [mode=fall|walk|all]

var out := "/tmp/strip"
var who := "player"
var mode := "all"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("who="):
			who = a.substr(4)
		elif a.begins_with("mode="):
			mode = a.substr(5)
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
	sun.rotation_degrees = Vector3(-45, 25, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	fs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(fs)
	add_child(floor_body)
	Toon.box(self, Vector3(80, 0.1, 30), Vector3(0, -0.05, 0), Color("#b7c9a0"), 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var look := _look()
	var times := [136, 140, 144, 148, 152, 156, 160, 164, 168, 174, 182, 192]
	var rows: Array = []
	if mode in ["fall", "all"]:
		await _fall_frames(look, times)
	if mode in ["walk", "all"]:
		await _gait_frames(look, "walk", 1.6, 4)
		await _gait_frames(look, "run", 3.4, 3)
		await _gait_frames(look, "idle", 0.0, 24)
	var z := 0.0
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.current = true
	for r in rows:
		var eggs: Array[EggBody] = []
		var ts: Array = r[1]
		for k in ts.size():
			var e := EggBody.new()
			add_child(e)
			e.build(look.duplicate())
			e.position = Vector3(-ts.size() * 1.1 + k * 2.2, 0.0, z)
			e.rotation.y = 0.5
			e.set_process(false)
			eggs.append(e)
		for k in ts.size():
			var e := eggs[k]
			var vel := Vector3.ZERO
			if r[0] == "walk":
				vel = Vector3(0, 0, 1.6)
			elif r[0] == "run":
				vel = Vector3(0, 0, 3.4)
			e.velocity_hint = vel
			e.position.z = z
			if r[0] != "fall":
				for f in 70:
					e._process(1.0 / 60.0)
			if r[0] == "fall":
				seed(11)
				e.tumble(Vector3(1, 0, 0.3), 1.4)
			for f in int(ts[k]):
				e._process(1.0 / 60.0)
		await get_tree().process_frame
		var cx := 0.0
		cam.global_position = Vector3(cx, 1.6, z + 21.0)
		cam.look_at(Vector3(cx, 0.75, z), Vector3.UP)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, who, r[0]])
		print("shot ", r[0])
		for e in eggs:
			e.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _look() -> Dictionary:
	if who == "player":
		return Characters.PLAYER_LOOK
	if who == "tony":
		return Characters.TONY.look
	for c in Characters.ROSTER:
		if c.id == who:
			return c.look
	return Characters.PLAYER_LOOK


## Each frame of the fall is its own capture with the camera following the body.
func _fall_frames(look: Dictionary, times: Array) -> void:
	var cam := Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	cam.current = true
	for k in times.size():
		var e := EggBody.new()
		add_child(e)
		e.build(look.duplicate())
		e.position = Vector3(0, 0, 0)
		e.rotation.y = 0.0
		e.set_process(false)
		e.velocity_hint = Vector3.ZERO
		for f in 30:
			e._process(1.0 / 60.0)
		seed(11)
		e.tumble(Vector3(1, 0, 0.3), 1.2)
		for f in int(times[k]):
			e._process(1.0 / 60.0)
		await get_tree().process_frame
		var c := e._hips.global_position
		cam.global_position = Vector3(c.x + 0.4, 1.1, c.z + 7.5)
		cam.look_at(Vector3(c.x + 0.4, 0.9, c.z), Vector3.UP)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/fall_%02d.png" % [out, k])
		e.queue_free()
		await get_tree().process_frame
	print("shot fall")


## Side-on frames of a locomotion cycle: name_00.png ... name_11.png.
func _gait_frames(look: Dictionary, label: String, speed: float, step_frames: int) -> void:
	var cam := Camera3D.new()
	cam.fov = 22.0
	add_child(cam)
	cam.current = true
	var e := EggBody.new()
	add_child(e)
	e.build(look.duplicate())
	e.rotation.y = PI / 2
	e.set_process(false)
	e.velocity_hint = Vector3(speed, 0, 0)
	for f in 120:
		e._process(1.0 / 60.0)
	cam.global_position = Vector3(0.0, 1.0, 9.0)
	cam.look_at(Vector3(0.0, 0.85, 0), Vector3.UP)
	for k in 12:
		for f in step_frames:
			e._process(1.0 / 60.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%02d.png" % [out, label, k])
	e.queue_free()
	await get_tree().process_frame
	print("shot ", label)
