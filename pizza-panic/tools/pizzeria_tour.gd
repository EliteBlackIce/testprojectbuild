extends Node3D
## Dev tool: renders Tony's from first-person viewpoints.
##   godot --path . res://tools/pizzeria_tour.tscn -- out=/tmp/tour

const VIEWS := [
	["01_dining", Vector3(-6.5, 1.4, 8.3), Vector3(1.0, 1.3, 1.5)],
	["02_counter", Vector3(3.5, 1.4, 6.5), Vector3(-1.0, 1.6, 1.0)],
	["03_kitchen_door", Vector3(-5.0, 1.4, 0.2), Vector3(-4.0, 0.9, -5.5)],
	["04_makeline", Vector3(-4.5, 1.45, -1.9), Vector3(-4.5, 0.9, -4.2)],
	["05_ovens", Vector3(-1.0, 1.4, -4.6), Vector3(-4.5, 1.2, -8.5)],
	["06_cut_pass", Vector3(-1.5, 1.4, -5.5), Vector3(2.0, 1.0, 0.5)],
	["07_walkin", Vector3(5.2, 1.4, -6.5), Vector3(10.0, 1.0, -6.5)],
	["08_office", Vector3(5.2, 1.5, -2.6), Vector3(9.0, 0.9, 0.5)],
	["09_outside", Vector3(-6.0, 2.2, 22.0), Vector3(0.0, 2.0, 6.0)],
]


func _ready() -> void:
	var out := "/tmp/tour"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var dc := DayCycle.new()
	add_child(dc)
	dc.apply(0.3)
	Toon.box(self, Vector3(200, 1, 200), Vector3(0, -0.5, 0), Color("#7bbf68"), 0.0)
	Toon.box(self, Vector3(40, 0.04, 14), Vector3(0, 0.02, 16), Color("#56535c"), 0.0)
	var pz := Pizzeria.new()
	add_child(pz)
	pz.build()
	var cam := Camera3D.new()
	cam.fov = 75
	add_child(cam)
	cam.current = true
	for v in VIEWS:
		cam.position = v[1]
		cam.look_at(v[2])
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, v[0]])
		print("shot ", v[0])
	get_tree().quit()
