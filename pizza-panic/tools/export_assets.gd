extends Node
## Dev tool: exports every model in the game as a .glb file (opens in Blender,
## Unity, Unreal, ...). Everything in the game is procedural, so this builds each
## thing and bakes it out: toon materials become plain colored materials, the
## ink outlines are dropped, multimeshes are expanded into real meshes.
##   godot --headless --path . res://tools/export_assets.tscn -- out=/some/folder

var out := "/tmp/exported-assets"
var index: PackedStringArray = []
var _mats: Dictionary = {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	Settings.ai_mode = "offline"
	for d in ["characters", "staff", "vehicles", "food", "world", "props"]:
		DirAccess.make_dir_recursive_absolute("%s/%s" % [out, d])
	await _characters()
	await _vehicles()
	await _food()
	await _world()
	var f := FileAccess.open(out + "/INDEX.txt", FileAccess.WRITE)
	f.store_string("PIZZA PANIC - exported models (.glb)\nUnits are meters, +Y up, characters face +Z.\nCharacters keep a joint hierarchy (Torso, Shoulder_L/R, Elbow_L/R, Wrist_L/R, Leg_L/R, Foot_L/R) you can rig or animate.\nColors are flat albedo colors; the game's cel shading + ink outlines are shader effects and are not exported.\n\n" + "\n".join(index) + "\n")
	print("EXPORTED ", index.size(), " files to ", out)
	get_tree().quit()


# --- the assets ----------------------------------------------------------------------------------

func _characters() -> void:
	var looks: Array = [["player", Characters.PLAYER_LOOK], ["tony_pepperoni", Characters.TONY.look]]
	for c in Characters.ROSTER:
		looks.append([str(c.id), c.look])
	for l in looks:
		await _export_egg("characters/" + l[0], l[1], {})
	var tpose := {"arm_out": [PI / 2 - 0.1, PI / 2 - 0.1], "arm_fwd": [0.0, 0.0], "arm_bend": [0.0, 0.0],
		"twist": [0.0, 0.0], "grip": [0.15, 0.15], "lean_x": 0.0, "lean_z": 0.0, "yaw": 0.0, "y": 0.0,
		"leg": [0.0, 0.0], "lift": [0.0, 0.0]}
	await _export_egg("characters/player_tpose", Characters.PLAYER_LOOK, tpose)
	await _export_egg("characters/base_egg_tpose", {"skin": "#d9a066", "boots": "#d9a066", "legs": "#d9a066"}, tpose)
	for id: String in StaffData.CANDIDATES:
		await _export_egg("staff/" + id, StaffData.CANDIDATES[id].look, {})


func _export_egg(path: String, look: Dictionary, pose: Dictionary) -> void:
	var e := EggBody.new()
	add_child(e)
	e.build(look)
	e.idle_fidgets = false
	e.pose_override = pose
	for i in 40:
		await get_tree().process_frame
	_save(e, path)


func _vehicles() -> void:
	var car := PizzaCar.new()
	add_child(car)
	car.set_physics_process(false)
	car.set_driver(true)
	car.set_cockpit(true)
	for i in 5:
		await get_tree().process_frame
	_save(car, "vehicles/delivery_van")
	var tr := Traffic.new()
	for k in 3:
		var root := Node3D.new()
		add_child(root)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7 + k
		tr._build_car(root, [Color("#2e86de"), Color("#e84393"), Color("#27ae60")][k], rng)
		_save(root, "vehicles/traffic_car_%d" % (k + 1))


func _food() -> void:
	var order := {"size": "large", "sauce": "tomato", "toppings": ["pepperoni", "mushroom", "olive", "pepper"]}
	var steps := ["dough_ball", "pizza_raw", "pizza_baked", "pizza_in_box"]
	for s in steps:
		var p := Pizza.new()
		add_child(p)
		p.setup(1)
		if s != "dough_ball":
			p.auto_assemble(order, 1.0)
		if s == "pizza_baked" or s == "pizza_in_box":
			p.set_bake(1.0)
			p.data.baked = true
			p.data.heat = 0.0
			p.auto_cut(1.0)
		if s == "pizza_in_box":
			p.put_in_box(true)
		await get_tree().process_frame
		_save(p, "food/" + s)
	var o2 := {"size": "medium", "sauce": "bbq", "toppings": ["pineapple", "ham"]}
	var p2 := Pizza.new()
	add_child(p2)
	p2.setup(2)
	p2.auto_assemble(o2, 1.0)
	p2.set_bake(1.0)
	p2.data.baked = true
	await get_tree().process_frame
	_save(p2, "food/pizza_hawaiian")


func _world() -> void:
	var pz := Pizzeria.new()
	add_child(pz)
	pz.build()
	await get_tree().process_frame
	_save(pz, "world/tonys_pizzeria")
	# One house per style
	var seen := {}
	for seed_v in 200:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_v
		var style: String = House.STYLES[probe.randi() % House.STYLES.size()]
		if seen.has(style):
			continue
		seen[style] = true
		var h := House.new()
		add_child(h)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		h.build(101, Characters.ROSTER[0], rng)
		h.resident.visible = true
		await get_tree().process_frame
		_save(h, "world/house_" + style)
	# Trees (three kinds), water tower, gas station, shops, park
	var kinds_seen := {}
	for seed_v in 80:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_v
		var kind := probe.randi() % 3        # tree() picks its kind from the first random number... after h? see below
		if kinds_seen.has(kind):
			continue
		kinds_seen[kind] = true
		var root := Node3D.new()
		add_child(root)
		var r := RandomNumberGenerator.new()
		r.seed = seed_v
		Landmarks.tree(root, Vector3.ZERO, r)
		_save(root, "props/tree_%d" % (kinds_seen.size()))
	var wt := Node3D.new()
	add_child(wt)
	Landmarks.water_tower(wt, Vector3.ZERO)
	_save(wt, "world/water_tower")
	var gs := Node3D.new()
	add_child(gs)
	Landmarks.gas_station(gs, Vector3.ZERO, 0.0)
	_save(gs, "world/gas_station")
	var park := Node3D.new()
	add_child(park)
	Landmarks.park(park, Vector3.ZERO, 30.0, RandomNumberGenerator.new())
	_save(park, "world/yolk_park")
	for i in 3:
		var shop := Node3D.new()
		add_child(shop)
		var r := RandomNumberGenerator.new()
		r.seed = i
		Landmarks.shop(shop, Vector3.ZERO, 0.0, i, r)
		_save(shop, "world/shop_%d" % (i + 1))
	# The surrounding land + the whole town in one file
	var town := Town.new()
	add_child(town)
	town.generate(20261007)
	await get_tree().process_frame
	var terrain := town.get_node_or_null("Terrain")
	if terrain:
		var holder := Node3D.new()
		add_child(holder)
		terrain.reparent(holder, false)
		_save(holder, "world/terrain_hills")
	_save(town, "world/eggville_full_town")


# --- baking + writing ---------------------------------------------------------------------------

func _save(root: Node3D, path: String) -> void:
	_bake(root)
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, "%s/%s.glb" % [out, path])
	var size := FileAccess.get_file_as_bytes("%s/%s.glb" % [out, path]).size() if err == OK else 0
	index.append("%-34s %s" % [path + ".glb", "%.1f KB" % (size / 1024.0) if err == OK else "FAILED (%d)" % err])
	print("export ", path, " ", err, " ", size / 1024, " KB")
	root.process_mode = Node.PROCESS_MODE_DISABLED
	root.queue_free()


func _bake(root: Node) -> void:
	var all := root.find_children("*", "", true, false)
	all.reverse()
	for n in all:
		if not is_instance_valid(n) or n == root:
			continue
		if n is Node3D and not (n as Node3D).visible:
			n.free()
		elif n is Label3D or n is Light3D or n is Camera3D or n is CollisionShape3D or n is Interactable \
				or n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is CanvasLayer or n is SubViewport \
				or n is Area3D or n is CollisionObject3D and n.get_child_count() == 0:
			n.free()
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		var parent := mmi.get_parent()
		var mm := mmi.multimesh
		var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		for i in count:
			var mi := MeshInstance3D.new()
			mi.mesh = mm.mesh
			mi.material_override = mmi.material_override
			mi.transform = mmi.transform * mm.get_instance_transform(i)
			parent.add_child(mi)
		mmi.free()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).get_shader_parameter("use_vertex_color") == true:
			_split_by_color(mi)
			continue
		mi.material_override = _standard(mi.material_override)
		mi.layers = 1
	# Give anonymous nodes friendly names
	var k := 0
	for n in root.find_children("@*", "", true, false):
		n.name = "%s_%d" % [n.get_class(), k]
		k += 1


func _standard(m: Material) -> Material:
	var key := ""
	var color := Color.WHITE
	var vcol := false
	var glow := 0.0
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var uv = sm.get_shader_parameter("use_vertex_color")
		vcol = uv == true
		var g = sm.get_shader_parameter("emission_strength")
		glow = float(g) if g != null else 0.0
		var alb = sm.get_shader_parameter("albedo")
		color = alb if alb is Color else Color.WHITE
	elif m is StandardMaterial3D:
		var st := m as StandardMaterial3D
		if st.albedo_texture is ViewportTexture:
			color = Color("#10163a")
			key = "screen"
		else:
			return st
	else:
		color = Color("#cccccc")
	key = "%s|%s|%s|%s" % [color.to_html(), vcol, glow, key]
	if _mats.has(key):
		return _mats[key]
	var s := StandardMaterial3D.new()
	s.albedo_color = color
	s.roughness = 0.9
	s.vertex_color_use_as_albedo = vcol
	s.vertex_color_is_srgb = false
	if glow > 0.0:
		s.emission_enabled = true
		s.emission = color
		s.emission_energy_multiplier = glow
	if color.a < 1.0:
		s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = s
	return s


## Terrain: turn per-vertex colors into a handful of plain colored materials, so
## every 3D program shows the right colors without any vertex-color setup.
func _split_by_color(mi: MeshInstance3D) -> void:
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var groups: Dictionary = {}
	for t in range(0, verts.size() - 2, 3):
		var c := cols[t]
		var q := Color(snappedf(c.r, 0.02), snappedf(c.g, 0.02), snappedf(c.b, 0.02))
		var key := q.to_html()
		if not groups.has(key):
			groups[key] = [q, PackedVector3Array(), PackedVector3Array()]
		var gv: PackedVector3Array = groups[key][1]
		var gn: PackedVector3Array = groups[key][2]
		for k in 3:
			gv.append(verts[t + k])
			gn.append(norms[t + k])
		groups[key][1] = gv
		groups[key][2] = gn
	var mesh := ArrayMesh.new()
	for key in groups:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = groups[key][1]
		a[Mesh.ARRAY_NORMAL] = groups[key][2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		var m := StandardMaterial3D.new()
		m.albedo_color = (groups[key][0] as Color).linear_to_srgb()
		m.roughness = 0.9
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	mi.mesh = mesh
	mi.material_override = null
