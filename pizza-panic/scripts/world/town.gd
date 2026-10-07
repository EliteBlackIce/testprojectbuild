class_name Town
extends Node3D
## Generates the whole neighborhood: sky, sun, roads, houses, Tony's,
## trees, clouds and knock-over-able junk. Same seed = same town.

const COLS := 4
const ROWS := 3
const BLOCK := 28.0
const ROAD := 12.0
const PITCH := BLOCK + ROAD
const SHOP_BLOCK := Vector2i(1, 1)

var houses: Array[House] = []
var shop: House
var props: Array[RigidBody3D] = []
var spawn_point := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var _clouds: Array[Node3D] = []
var _origin := Vector3.ZERO


func generate(seed_value := 1234) -> void:
	rng.seed = seed_value
	_origin = Vector3(-COLS * PITCH * 0.5, 0, -ROWS * PITCH * 0.5)
	_build_environment()
	_build_ground_and_roads()
	_build_blocks()
	_build_trees()
	_build_props()
	_build_clouds()
	_build_bounds()


## Every place you can knock: all houses plus Tony's.
func all_stops() -> Array[House]:
	var out: Array[House] = houses.duplicate()
	out.append(shop)
	return out


## Top-left corner of a block.
func block_origin(i: int, j: int) -> Vector3:
	return _origin + Vector3(i * PITCH + ROAD * 0.5, 0, j * PITCH + ROAD * 0.5)


func world_size() -> Vector2:
	return Vector2(COLS * PITCH + ROAD, ROWS * PITCH + ROAD)


# --- sky, sun ----------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3fa7f5")
	sky_mat.sky_horizon_color = Color("#c9f0ff")
	sky_mat.ground_horizon_color = Color("#c9f0ff")
	sky_mat.ground_bottom_color = Color("#7bc96f")
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d7d2ff")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color("#c9f0ff")
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color("#fff4e0")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


# --- ground, roads -------------------------------------------------------------------

func _build_ground_and_roads() -> void:
	var size := world_size()
	var center := _origin + Vector3(COLS * PITCH * 0.5, 0, ROWS * PITCH * 0.5)
	# Grass far beyond the edges so the horizon isn't a cliff.
	Toon.box(self, Vector3(size.x + 400, 1.0, size.y + 400), center + Vector3(0, -0.5, 0), Color("#7bc96f"), 0.0)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	add_child(floor_body)

	var asphalt := Color("#5a5560")
	var dash_xf: Array[Transform3D] = []
	for i in COLS + 1:
		var x := _origin.x + i * PITCH
		Toon.box(self, Vector3(ROAD, 0.04, size.y), Vector3(x, 0.02, center.z), asphalt, 0.0)
		var z := _origin.z
		while z < _origin.z + size.y - ROAD:
			dash_xf.append(Transform3D(Basis.from_scale(Vector3(0.25, 0.03, 2.0)), Vector3(x, 0.05, z + ROAD)))
			z += 5.0
	for j in ROWS + 1:
		var z := _origin.z + j * PITCH
		Toon.box(self, Vector3(size.x, 0.045, ROAD), Vector3(center.x, 0.022, z), asphalt, 0.0)
		var x := _origin.x
		while x < _origin.x + size.x - ROAD:
			dash_xf.append(Transform3D(Basis.from_scale(Vector3(2.0, 0.03, 0.25)), Vector3(x + ROAD, 0.055, z)))
			x += 5.0
	_multimesh(BoxMesh.new(), Toon.mat(Color("#ffd166"), 0.0), dash_xf)


func _build_blocks() -> void:
	var number := 101
	for j in ROWS:
		for i in COLS:
			var o := block_origin(i, j)
			# Sidewalk rim + lawn.
			Toon.box(self, Vector3(BLOCK, 0.08, BLOCK), o + Vector3(BLOCK * 0.5, 0.04, BLOCK * 0.5), Color("#d8d3cd"), 0.0)
			Toon.box(self, Vector3(BLOCK - 2.4, 0.1, BLOCK - 2.4), o + Vector3(BLOCK * 0.5, 0.05, BLOCK * 0.5), Color("#8fd16a"), 0.0)
			if Vector2i(i, j) == SHOP_BLOCK:
				shop = House.new()
				shop.position = o + Vector3(BLOCK * 0.5, 0, 18.0)
				add_child(shop)
				shop.build(0, true, Characters.TONY, rng)
				shop.stop_point = shop.global_position + Vector3(0, 0, 10.0)
				spawn_point = shop.stop_point + Vector3(0, 0.6, 2.0)
				continue
			for lot in 2:
				var h := House.new()
				h.position = o + Vector3(7.0 + lot * 14.0, 0, 19.0)
				add_child(h)
				h.build(number, false, Characters.random_resident(rng), rng)
				h.stop_point = h.global_position + Vector3(0, 0, 10.0)
				houses.append(h)
				number += rng.randi_range(2, 9)


func _build_trees() -> void:
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var crowns2: Array[Transform3D] = []
	for j in ROWS:
		for i in COLS:
			var o := block_origin(i, j)
			# Backyard trees
			for n in 4:
				var p := o + Vector3(rng.randf_range(3.0, BLOCK - 3.0), 0, rng.randf_range(3.0, 10.0))
				_tree(p, trunks, crowns, crowns2)
			# A couple of street trees on the sidewalk corners
			for corner: Vector3 in [Vector3(1.0, 0, 1.0), Vector3(BLOCK - 1.0, 0, 1.0)]:
				_tree(o + corner, trunks, crowns, crowns2)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.25
	trunk_mesh.bottom_radius = 0.35
	trunk_mesh.height = 1.0
	_multimesh(trunk_mesh, Toon.mat(Color("#8b5e3c"), 0.04), trunks)
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.0
	crown_mesh.height = 2.0
	crown_mesh.radial_segments = 16
	crown_mesh.rings = 8
	_multimesh(crown_mesh, Toon.mat(Color("#40916c"), 0.05), crowns)
	_multimesh(crown_mesh, Toon.mat(Color("#74c69d"), 0.05), crowns2)


func _tree(p: Vector3, trunks: Array[Transform3D], crowns: Array[Transform3D], crowns2: Array[Transform3D]) -> void:
	var h := rng.randf_range(2.0, 3.2)
	trunks.append(Transform3D(Basis.from_scale(Vector3(1, h, 1)), p + Vector3(0, h * 0.5, 0)))
	var r := rng.randf_range(1.4, 2.2)
	crowns.append(Transform3D(Basis.from_scale(Vector3.ONE * r), p + Vector3(0, h + r * 0.6, 0)))
	crowns2.append(Transform3D(Basis.from_scale(Vector3.ONE * r * 0.6), p + Vector3(r * 0.4, h + r * 1.2, r * 0.2)))
	Toon.solid_box(self, Vector3(0.7, 3.0, 0.7), p + Vector3(0, 1.5, 0))


func _multimesh(mesh: Mesh, material: Material, xforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)


# --- props: cones, trash cans, lawn flamingos -------------------------------------------

func _build_props() -> void:
	for n in 70:
		var i := rng.randi() % COLS
		var j := rng.randi() % ROWS
		var o := block_origin(i, j)
		# Along the front sidewalk of a block, or on a random road edge.
		var p := o + Vector3(rng.randf_range(1.0, BLOCK - 1.0), 0.0, BLOCK - rng.randf_range(0.3, 1.0))
		match rng.randi() % 3:
			0:
				_prop_cone(p)
			1:
				_prop_trash(p)
			2:
				_prop_flamingo(p + Vector3(0, 0, -3.0))


func _new_prop(p: Vector3, mass: float, shape_size: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = mass
	body.position = p + Vector3(0, shape_size.y * 0.5 + 0.05, 0)
	body.collision_layer = 2
	body.collision_mask = 1 | 2
	body.can_sleep = true
	body.sleeping = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = shape_size
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	props.append(body)
	return body


func _prop_cone(p: Vector3) -> void:
	var b := _new_prop(p, 2.0, Vector3(0.6, 0.9, 0.6))
	Toon.cylinder(b, 0.05, 0.3, 0.8, Vector3(0, 0.0, 0), Color("#ff7b00"), 0.03)
	Toon.cylinder(b, 0.16, 0.2, 0.12, Vector3(0, 0.05, 0), Color.WHITE, 0.0)
	Toon.box(b, Vector3(0.7, 0.08, 0.7), Vector3(0, -0.41, 0), Color("#ff7b00"), 0.02)


func _prop_trash(p: Vector3) -> void:
	var b := _new_prop(p, 6.0, Vector3(0.8, 1.1, 0.8))
	Toon.cylinder(b, 0.42, 0.36, 1.05, Vector3.ZERO, Color("#6c757d"), 0.035)
	Toon.cylinder(b, 0.46, 0.46, 0.1, Vector3(0, 0.56, 0), Color("#495057"), 0.03)


func _prop_flamingo(p: Vector3) -> void:
	var b := _new_prop(p, 1.0, Vector3(0.5, 1.4, 0.5))
	Toon.cylinder(b, 0.025, 0.025, 0.8, Vector3(0, -0.3, 0), Color("#ff4d8d"), 0.01)
	var body := Toon.sphere(b, 0.28, Vector3(0, 0.25, 0), Color("#ff69b4"), 0.025, 0.7)
	body.scale = Vector3(1.0, 1.0, 1.5)
	Toon.capsule(b, 0.05, 0.5, Vector3(0, 0.5, 0.25), Color("#ff69b4"), 0.015)
	Toon.sphere(b, 0.1, Vector3(0, 0.75, 0.3), Color("#ff69b4"), 0.015)
	Toon.cylinder(b, 0.0, 0.04, 0.15, Vector3(0, 0.72, 0.42), Color("#1b1b1b"), 0.0).rotation.x = PI / 2


# --- clouds + world edge --------------------------------------------------------------

func _build_clouds() -> void:
	for n in 14:
		var c := Node3D.new()
		c.position = Vector3(rng.randf_range(-160, 160), rng.randf_range(38, 55), rng.randf_range(-160, 160))
		add_child(c)
		for k in rng.randi_range(4, 7):
			var r := rng.randf_range(3.0, 6.0)
			Toon.sphere(c, r, Vector3(rng.randf_range(-7, 7), rng.randf_range(-1, 2), rng.randf_range(-3, 3)), Color("#ffffff"), 0.15)
		_clouds.append(c)


func _build_bounds() -> void:
	var size := world_size()
	var center := _origin + Vector3(COLS * PITCH * 0.5, 0, ROWS * PITCH * 0.5)
	var half := Vector3(size.x * 0.5, 0, size.y * 0.5)
	var walls := [
		[Vector3(size.x + 4, 8, 2), center + Vector3(0, 4, -half.z - 1)],
		[Vector3(size.x + 4, 8, 2), center + Vector3(0, 4, half.z + 1)],
		[Vector3(2, 8, size.y + 4), center + Vector3(-half.x - 1, 4, 0)],
		[Vector3(2, 8, size.y + 4), center + Vector3(half.x + 1, 4, 0)],
	]
	for w in walls:
		Toon.solid_box(self, w[0], w[1])
	# Fence posts so the invisible walls aren't a total surprise.
	var posts: Array[Transform3D] = []
	var x := -half.x
	while x <= half.x:
		posts.append(Transform3D(Basis(), center + Vector3(x, 0.6, -half.z)))
		posts.append(Transform3D(Basis(), center + Vector3(x, 0.6, half.z)))
		x += 3.0
	var z := -half.z
	while z <= half.z:
		posts.append(Transform3D(Basis(), center + Vector3(-half.x, 0.6, z)))
		posts.append(Transform3D(Basis(), center + Vector3(half.x, 0.6, z)))
		z += 3.0
	var post := BoxMesh.new()
	post.size = Vector3(0.3, 1.2, 0.3)
	_multimesh(post, Toon.mat(Color("#ffffff"), 0.03, true), posts)
	Toon.label(self, "THE WORLD ENDS HERE.\nPLEASE TURN AROUND.", center + Vector3(0, 3.0, half.z - 0.5), 160, Color("#ff5d73"))
	Toon.label(self, "NOTHING OUT HERE\nBUT VIBES", center + Vector3(0, 3.0, -half.z + 0.5), 160, Color("#ff5d73"))


func _process(delta: float) -> void:
	for c in _clouds:
		c.position.x += delta * 1.5
		if c.position.x > 200.0:
			c.position.x = -200.0
