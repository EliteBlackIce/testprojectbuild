class_name Town
extends Node3D
## Generates Eggville: roads with curbs and crosswalks, downtown, the park,
## neighborhoods, Tony's Pizza, a gas station, street lamps, power lines,
## parked cars, junk to knock over, and hills + mountains for depth.
## Same seed = same town.

const COLS := 5
const ROWS := 4
const BLOCK := 30.0
const ROAD := 12.0
const PITCH := BLOCK + ROAD

## What goes on each block (col, row). Anything not listed is houses.
const ZONES := {
	Vector2i(1, 0): "downtown", Vector2i(2, 0): "downtown", Vector2i(3, 0): "downtown",
	Vector2i(0, 1): "park",
	Vector2i(4, 2): "gas",
	Vector2i(2, 3): "pizzeria",
}
const STREETS_X := ["Shell St", "Yolk Ave", "Albumen Rd", "Benedict Blvd", "Omelette Way", "Cluck Ln"]
const STREETS_Z := ["Hatch St", "Poach Pkwy", "Sunny Side Ave", "Scramble St", "Hardboil Rd"]

var houses: Array[House] = []
var pizzeria: Pizzeria
var props: Array[RigidBody3D] = []
var lamps: Array[OmniLight3D] = []
var rng := RandomNumberGenerator.new()
var _origin := Vector3.ZERO
var _clouds: Array[Node3D] = []


func generate(seed_value := 1234) -> void:
	rng.seed = seed_value
	_origin = Vector3(-COLS * PITCH * 0.5, 0, -ROWS * PITCH * 0.5)
	_build_ground()
	_build_roads()
	_build_blocks()
	_build_street_furniture()
	_build_power_lines()
	_build_props()
	_build_edges()
	_build_clouds()


func block_origin(i: int, j: int) -> Vector3:
	return _origin + Vector3(i * PITCH + ROAD * 0.5, 0, j * PITCH + ROAD * 0.5)


## Center line of road number i (running along Z) or j (running along X).
func road_x(i: int) -> float:
	return _origin.x + i * PITCH


func road_z(j: int) -> float:
	return _origin.z + j * PITCH


func size() -> Vector2:
	return Vector2(COLS * PITCH, ROWS * PITCH)


func center() -> Vector3:
	return _origin + Vector3(COLS * PITCH * 0.5, 0, ROWS * PITCH * 0.5)


func zone(i: int, j: int) -> String:
	return ZONES.get(Vector2i(i, j), "houses")


func house_by_number(num: int) -> House:
	for h in houses:
		if h.number == num:
			return h
	return null


# --- ground + roads -----------------------------------------------------------------------------

func _build_ground() -> void:
	var c := center()
	Toon.box(self, Vector3(1400, 1.0, 1400), c + Vector3(0, -0.5, 0), Color("#7bbf68"), 0.0)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	add_child(floor_body)


func _build_roads() -> void:
	var asphalt := Color("#56535c")
	var s := size()
	var c := center()
	var dashes: Array[Transform3D] = []
	var stripes: Array[Transform3D] = []
	for i in COLS + 1:
		var x := road_x(i)
		Toon.box(self, Vector3(ROAD, 0.04, s.y + ROAD), Vector3(x, 0.02, c.z), asphalt, 0.0)
		for j in ROWS:
			var z0 := road_z(j) + ROAD * 0.5
			var z := z0 + 2.0
			while z < z0 + BLOCK - 2.0:
				dashes.append(Transform3D(Basis.from_scale(Vector3(0.22, 1.0, 2.0)), Vector3(x, 0.05, z)))
				z += 4.5
	for j in ROWS + 1:
		var z := road_z(j)
		Toon.box(self, Vector3(s.x + ROAD, 0.042, ROAD), Vector3(c.x, 0.021, z), asphalt, 0.0)
		for i in COLS:
			var x0 := road_x(i) + ROAD * 0.5
			var x := x0 + 2.0
			while x < x0 + BLOCK - 2.0:
				dashes.append(Transform3D(Basis.from_scale(Vector3(2.0, 1.0, 0.22)), Vector3(x, 0.052, z)))
				x += 4.5
	# Crosswalk stripes on every side of every intersection.
	for i in COLS + 1:
		for j in ROWS + 1:
			var p := Vector3(road_x(i), 0.055, road_z(j))
			for k in 5:
				var off := -2.4 + k * 1.2
				for side: int in [-1, 1]:
					stripes.append(Transform3D(Basis.from_scale(Vector3(0.6, 1.0, 2.2)), p + Vector3(off, 0, side * (ROAD * 0.5 + 1.3))))
					stripes.append(Transform3D(Basis.from_scale(Vector3(2.2, 1.0, 0.6)), p + Vector3(side * (ROAD * 0.5 + 1.3), 0, off)))
	var flat := Shapes.box(Vector3(1, 0.02, 1))
	Toon.multimesh(self, flat, Toon.mat(Color("#f2c94c"), 0.0), dashes)
	Toon.multimesh(self, flat, Toon.mat(Color("#f6f4ef"), 0.0), stripes)


# --- blocks ----------------------------------------------------------------------------------------

func _build_blocks() -> void:
	var cast := Characters.ROSTER.duplicate()
	_shuffle(cast)
	var slots: Array = []   # [block i, j, lot]
	for j in ROWS:
		for i in COLS:
			var o := block_origin(i, j)
			var z := zone(i, j)
			# Curb + sidewalk slab + (lawn for green blocks)
			Toon.box(self, Vector3(BLOCK + 0.3, 0.05, BLOCK + 0.3), o + Vector3(BLOCK * 0.5, 0.025, BLOCK * 0.5), Color("#8f8a85"), 0.0)
			Toon.box(self, Vector3(BLOCK, 0.06, BLOCK), o + Vector3(BLOCK * 0.5, 0.03, BLOCK * 0.5), Color("#cfc9c2"), 0.0)
			if z in ["houses", "park"]:
				Toon.box(self, Vector3(BLOCK - 3.0, 0.07, BLOCK - 3.0), o + Vector3(BLOCK * 0.5, 0.035, BLOCK * 0.5), Color("#86c56f"), 0.0)
			match z:
				"downtown":
					for k in 2:
						Landmarks.shop(self, o + Vector3(8.0 + k * 14.0, 0, BLOCK - 7.0), 0.0, i * 4 + k, rng)
						Landmarks.shop(self, o + Vector3(8.0 + k * 14.0, 0, 7.0), PI, i * 4 + k + 2, rng)
				"park":
					Landmarks.park(self, o, BLOCK, rng)
				"gas":
					Landmarks.gas_station(self, o + Vector3(BLOCK * 0.5, 0, BLOCK - 10.0), 0.0)
					slots.append([i, j, 0])
					slots.append([i, j, 1])
				"pizzeria":
					pizzeria = Pizzeria.new()
					pizzeria.position = o + Vector3(BLOCK * 0.5, 0.0, 21.5)
					pizzeria.rotation.y = PI
					add_child(pizzeria)
					pizzeria.build()
				_:
					for lot in 4:
						slots.append([i, j, lot])
	_shuffle(slots)
	for s in slots:
		var c: Dictionary
		if not cast.is_empty():
			c = cast.pop_back()
		else:
			c = Characters.generate_extra(rng)
		_place_house(s[0], s[1], s[2], c)
	houses.sort_custom(func(a: House, b: House): return a.number < b.number)


## Deterministic shuffle (Array.shuffle uses the global RNG).
func _shuffle(arr: Array) -> void:
	for k in range(arr.size() - 1, 0, -1):
		var m := rng.randi_range(0, k)
		var tmp = arr[k]
		arr[k] = arr[m]
		arr[m] = tmp


func _place_house(i: int, j: int, lot: int, c: Dictionary) -> void:
	var o := block_origin(i, j)
	var h := House.new()
	var south := lot >= 2
	var x := 7.5 + (lot % 2) * 15.0
	if south:
		h.position = o + Vector3(x, 0.0, 20.0)
	else:
		h.position = o + Vector3(x, 0.0, 10.0)
		h.rotation.y = PI
	add_child(h)
	var number := 100 + (j * COLS + i) * 10 + lot * 2 + (1 if south else 0)
	h.build(number, c, rng)
	houses.append(h)


# --- street furniture -------------------------------------------------------------------------------

func _build_street_furniture() -> void:
	var posts: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var glow_heads: Array[Transform3D] = []
	var hydrants: Array[Transform3D] = []
	for i in COLS + 1:
		for j in ROWS + 1:
			var p := Vector3(road_x(i), 0, road_z(j))
			for corner: Vector2 in [Vector2(1, 1), Vector2(-1, -1)]:
				var lp := p + Vector3(corner.x * (ROAD * 0.5 + 0.8), 0, corner.y * (ROAD * 0.5 + 0.8))
				posts.append(Transform3D(Basis(), lp + Vector3(0, 2.7, 0)))
				var head := lp + Vector3(-corner.x * 0.6, 5.4, -corner.y * 0.6)
				heads.append(Transform3D(Basis(), head))
				glow_heads.append(Transform3D(Basis(), head + Vector3(0, -0.16, 0)))
				var light := OmniLight3D.new()
				light.position = head + Vector3(0, -0.5, 0)
				light.light_color = Color("#ffd59a")
				light.omni_range = 11.0
				light.light_energy = 0.0
				add_child(light)
				lamps.append(light)
				Toon.solid_box(self, Vector3(0.4, 5.0, 0.4), lp + Vector3(0, 2.5, 0))
			if rng.randf() < 0.5:
				hydrants.append(Transform3D(Basis(), p + Vector3(ROAD * 0.5 + 0.7, 0.45, -(ROAD * 0.5 + 2.5))))
			if i < COLS and j < ROWS and rng.randf() < 0.6:
				var sp := p + Vector3(-(ROAD * 0.5 + 0.8), 0, ROAD * 0.5 + 0.8)
				Toon.cyl(self, 0.05, 0.05, 3.0, sp + Vector3(0, 1.5, 0), Color("#3f6b4f"), 0.006, 5)
				var sn := Toon.label(self, STREETS_X[i % STREETS_X.size()], sp + Vector3(0, 3.1, 0), 40, Color("#f6f4ef"), false)
				sn.rotation.y = PI / 2
				Toon.label(self, STREETS_Z[j % STREETS_Z.size()], sp + Vector3(0, 2.75, 0), 40, Color("#f6f4ef"), false)
	Toon.multimesh(self, Shapes.cylinder(0.1, 0.14, 5.4, 6), Toon.mat(Color("#3d4a4f"), 0.01), posts)
	Toon.multimesh(self, Shapes.chamfer_box(Vector3(0.7, 0.3, 0.45), 0.3), Toon.mat(Color("#3d4a4f"), 0.01), heads)
	var g := Toon.multimesh(self, Shapes.box(Vector3(0.5, 0.06, 0.3)), Toon.mat(Color("#d9d2c0"), 0.0), glow_heads)
	g.add_to_group("lamp_glow")
	Toon.multimesh(self, Shapes.chamfer_box(Vector3(0.35, 0.8, 0.35), 0.4), Toon.mat(Color("#d63031"), 0.01), hydrants)
	# Parked cars along the downtown street
	var car_colors := ["#2e86de", "#27ae60", "#f39c12", "#8e44ad", "#dfe6e9", "#16a085", "#e84393"]
	for i in range(1, 4):
		for k in 3:
			var x := block_origin(i, 0).x + 5.0 + k * 9.0
			var z := road_z(1) - ROAD * 0.5 + 1.4
			if rng.randf() < 0.7:
				_parked_car(Vector3(x, 0, z), Color(car_colors[rng.randi() % car_colors.size()]))


func _parked_car(p: Vector3, col: Color) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = PI / 2 + (PI if rng.randf() < 0.5 else 0.0)
	add_child(root)
	Toon.block(root, Vector3(1.9, 0.8, 3.8), Vector3(0, 0.3, 0), col, 0.2, 0.02)
	Toon.block(root, Vector3(1.6, 0.65, 2.0), Vector3(0, 1.05, 0.2), col.lightened(0.25), 0.2, 0.02)
	Toon.box(root, Vector3(1.5, 0.4, 2.02), Vector3(0, 1.38, 0.2), Color("#9cc9d9"), 0.0)
	for x: int in [-1, 1]:
		for z: int in [-1, 1]:
			Toon.cyl(root, 0.38, 0.38, 0.3, Vector3(0.9 * x, 0.38, 1.2 * z), Color("#2d3436"), 0.01, 8).rotation.z = PI / 2
	var body := Toon.solid_box(self, Vector3(1.9, 1.6, 3.8), p + Vector3(0, 0.8, 0))
	body.rotation.y = root.rotation.y


func _build_power_lines() -> void:
	# Wooden poles + sagging wires along two long streets, for depth.
	for j: int in [1, 3]:
		var z := road_z(j) + ROAD * 0.5 + 0.9
		var poles: Array[Vector3] = []
		var x := _origin.x + 4.0
		while x < _origin.x + size().x:
			poles.append(Vector3(x, 0, z))
			x += 16.0
		for p in poles:
			Toon.cyl(self, 0.16, 0.2, 9.0, p + Vector3(0, 4.5, 0), Color("#7a5236"), 0.012, 6)
			Toon.box(self, Vector3(0.18, 0.18, 2.2), p + Vector3(0, 8.4, 0), Color("#7a5236"), 0.008)
		for k in poles.size() - 1:
			for w: int in [-1, 0, 1]:
				var off := Vector3(0, 8.55, w * 0.9)
				_wire(poles[k] + off, poles[k + 1] + off)


func _wire(a: Vector3, b: Vector3) -> void:
	# Two straight segments that dip in the middle = cheap sag.
	var mid := (a + b) * 0.5 + Vector3(0, -0.7, 0)
	for seg in [[a, mid], [mid, b]]:
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var mi := MeshInstance3D.new()
		mi.mesh = Shapes.box(Vector3(0.04, 0.04, 1.0))
		mi.material_override = Toon.mat(Color("#2d3436"), 0.0)
		add_child(mi)
		mi.look_at_from_position((p0 + p1) * 0.5, p1, Vector3.UP)
		mi.scale = Vector3(1, 1, p0.distance_to(p1))


# --- props: cones, trash cans, lawn flamingos ------------------------------------------------------

func _build_props() -> void:
	for n in 90:
		var i := rng.randi() % COLS
		var j := rng.randi() % ROWS
		if zone(i, j) == "pizzeria":
			continue
		var o := block_origin(i, j)
		var t := rng.randf_range(2.0, BLOCK - 2.0)
		var p: Vector3
		match rng.randi() % 4:
			0:
				p = o + Vector3(t, 0.0, 0.6)
			1:
				p = o + Vector3(t, 0.0, BLOCK - 0.6)
			2:
				p = o + Vector3(0.6, 0.0, t)
			_:
				p = o + Vector3(BLOCK - 0.6, 0.0, t)
		match rng.randi() % 4:
			0, 1:
				_prop_cone(p)
			2:
				_prop_trash(p)
			_:
				_prop_flamingo(p)


func _new_prop(p: Vector3, mass: float, shape_size: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = mass
	body.position = p + Vector3(0, shape_size.y * 0.5 + 0.02, 0)
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
	Toon.cyl(b, 0.04, 0.28, 0.8, Vector3.ZERO, Color("#ff7b00"), 0.012, 7)
	Toon.cyl(b, 0.15, 0.19, 0.12, Vector3(0, 0.05, 0), Color("#f6f4ef"), 0.0, 7)
	Toon.box(b, Vector3(0.65, 0.08, 0.65), Vector3(0, -0.41, 0), Color("#ff7b00"), 0.008)


func _prop_trash(p: Vector3) -> void:
	var b := _new_prop(p, 6.0, Vector3(0.8, 1.1, 0.8))
	Toon.cyl(b, 0.42, 0.36, 1.05, Vector3.ZERO, Color("#5d6d7e"), 0.015, 8)
	Toon.cyl(b, 0.46, 0.46, 0.1, Vector3(0, 0.56, 0), Color("#34495e"), 0.01, 8)


func _prop_flamingo(p: Vector3) -> void:
	var b := _new_prop(p, 1.0, Vector3(0.5, 1.4, 0.5))
	Toon.cyl(b, 0.025, 0.025, 0.8, Vector3(0, -0.3, 0), Color("#ff4d8d"), 0.0, 4)
	Toon.mesh(b, Shapes.egg(0.5, 0.25, 8, 5), Vector3(0, 0.05, 0), Color("#ff69b4"), 0.01).rotation.x = PI / 2
	Toon.cyl(b, 0.04, 0.05, 0.5, Vector3(0, 0.5, 0.22), Color("#ff69b4"), 0.006, 5)
	Toon.ball(b, 0.1, Vector3(0, 0.76, 0.28), Color("#ff69b4"), 0.006, 6)
	Toon.cyl(b, 0.0, 0.04, 0.15, Vector3(0, 0.72, 0.42), Color("#2d3436"), 0.0, 4).rotation.x = PI / 2


# --- edges, sky dressing -------------------------------------------------------------------------------

func _build_edges() -> void:
	var s := size()
	var c := center()
	var half := Vector3(s.x * 0.5 + ROAD * 0.5, 0, s.y * 0.5 + ROAD * 0.5)
	var walls := [
		[Vector3(s.x + 30, 10, 2), c + Vector3(0, 5, -half.z - 3)],
		[Vector3(s.x + 30, 10, 2), c + Vector3(0, 5, half.z + 3)],
		[Vector3(2, 10, s.y + 30), c + Vector3(-half.x - 3, 5, 0)],
		[Vector3(2, 10, s.y + 30), c + Vector3(half.x + 3, 5, 0)],
	]
	for w in walls:
		Toon.solid_box(self, w[0], w[1])
	var rails: Array[Transform3D] = []
	var x := -half.x - 2.0
	while x <= half.x + 2.0:
		rails.append(Transform3D(Basis(), c + Vector3(x, 0.5, -half.z - 2.0)))
		rails.append(Transform3D(Basis(), c + Vector3(x, 0.5, half.z + 2.0)))
		x += 2.5
	var z := -half.z - 2.0
	while z <= half.z + 2.0:
		rails.append(Transform3D(Basis(), c + Vector3(-half.x - 2.0, 0.5, z)))
		rails.append(Transform3D(Basis(), c + Vector3(half.x + 2.0, 0.5, z)))
		z += 2.5
	Toon.multimesh(self, Shapes.chamfer_box(Vector3(0.3, 1.0, 0.3), 0.3), Toon.mat(Color("#f6f4ef"), 0.01), rails)
	Landmarks.hills(self, c, Vector2(half.x, half.z), rng)
	Landmarks.water_tower(self, c + Vector3(-half.x - 14.0, 0, half.z - 20.0))
	for k in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.05, 1.2)
		var tp := c + Vector3(cos(a) * (half.x + 8.0) * r, 0, sin(a) * (half.z + 8.0) * r)
		Landmarks.tree(self, tp, rng)
	var welcome := Toon.label(self, "WELCOME TO EGGVILLE\npop. a lot of eggs", c + Vector3(0, 4.0, half.z + 6.0), 200, Color("#ffd166"), false)
	welcome.rotation.y = PI


func _build_clouds() -> void:
	for n in 18:
		var cl := Node3D.new()
		cl.position = Vector3(rng.randf_range(-260, 260), rng.randf_range(55, 80), rng.randf_range(-260, 260))
		add_child(cl)
		for k in rng.randi_range(4, 7):
			Toon.mesh(cl, Shapes.blob(rng.randf_range(4.0, 8.0), k + n * 10, 0.12), Vector3(rng.randf_range(-9, 9), rng.randf_range(-1, 2), rng.randf_range(-4, 4)), Color("#ffffff"), 0.0)
		_clouds.append(cl)


func _process(delta: float) -> void:
	for cl in _clouds:
		cl.position.x += delta * 1.2
		if cl.position.x > 300.0:
			cl.position.x = -300.0
