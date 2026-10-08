class_name Pizzeria
extends Node3D
## Tony's Pizza, built at first-person scale like a real restaurant.
## Front faces +Z (the street). Layout (local coords, meters):
##
##   z +9  ┌──────────── storefront + front door ────────────┐
##         │ DINING: booths, tables, jukebox, arcade, soda   │
##   z 2.2 │        order counter + register   [menu board]  │
##   z 1.0 ├─door─┬────────[pass window]───────┬─────────────┤
##         │      KITCHEN                      │   OFFICE    │
##         │ dough rack   make-line island     │  PC, staff  │
##         │ mixer        (ticket rail above)  ├─────────────┤
##         │ dish pit     ovens + hood    cut  │  WALK-IN    │
##   z -9  └───────────────────────── back door┴─────────────┘
##                       ALLEY (dumpsters)
##        x -11                              x 4.5          x 11

const W := 22.0
const D := 18.0
const H := 4.0
const T := 0.25
const PARTITION_Z := 1.0
const BACKROOM_X := 4.5

## Where things are (local, on the floor unless noted).
const ANCHORS := {
	"spawn": Vector3(-2.0, 0, -1.2),
	"door": Vector3(0, 0, 9.0),
	"parking": Vector3(0, 0, 15.5),
	"dough": Vector3(-10.1, 0, -2.6),         # dough proofing rack
	"prep": Vector3(-4.5, 0, -3.6),           # center of the make-line island
	"prep_board": Vector3(-4.5, 0.96, -3.35),  # where the pizza sits (on the counter)
	"sauce": Vector3(-6.25, 0.96, -3.15),
	"cheese": Vector3(-2.75, 0.96, -3.15),
	"oven1": Vector3(-5.6, 0, -8.1),
	"oven2": Vector3(-2.1, 0, -8.1),
	"cut": Vector3(2.0, 0, -4.0),
	"cut_board": Vector3(1.6, 0.96, -3.7),
	"boxes": Vector3(2.75, 0.96, -3.75),
	"pass": Vector3(1.5, 1.08, 1.0),           # heat shelf in the pass window
	"phone": Vector3(3.9, 1.45, 0.82),
	"trash": Vector3(-0.8, 0, -1.2),
	"pc": Vector3(8.0, 0, 0.1),
	"staff_board": Vector3(10.85, 1.7, -1.6),
	"tony": Vector3(-1.0, 0, -5.0),
	"walkin": Vector3(8.0, 0, -6.5),
	"backdoor": Vector3(3.2, 0, -9.0),
	"kitchen_door": Vector3(-5.2, 0, PARTITION_Z),
}

var ticket_rail: Node3D
var _door_flaps: Array[Node3D] = []
var _lamps: Array[OmniLight3D] = []
var _neon: Array[Node3D] = []
var _roof: Node3D
var _night_glows: Array[GeometryInstance3D] = []


func build() -> void:
	_build_floors()
	_build_walls()
	_build_ceiling_and_roof()
	_build_dining()
	_build_counter()
	_build_kitchen()
	_build_walkin()
	_build_office()
	_build_lights()
	_build_exterior()
	_build_alley()
	Game.tickets_changed.connect(_refresh_ticket_rail)


func anchor(name: String) -> Vector3:
	return to_global(ANCHORS[name])


func is_inside(world_pos: Vector3) -> bool:
	var p := to_local(world_pos)
	return absf(p.x) < W * 0.5 and absf(p.z) < D * 0.5 and p.y < H


func covers(world_pos: Vector3, margin := 2.0) -> bool:
	var p := to_local(world_pos)
	return absf(p.x) < W * 0.5 + margin and absf(p.z) < D * 0.5 + margin


## In first person the roof only gets in the way for overhead cameras.
func set_cutaway(on: bool, _camera_pos := Vector3.ZERO) -> void:
	_roof.visible = not on


func set_night(amount: float) -> void:
	for l in _lamps:
		l.light_energy = l.get_meta("day", 0.5) + amount * float(l.get_meta("night_boost", 0.3))
	for n in _neon:
		n.visible = amount > 0.25 or Game.level("neon_sign") > 0


# --- small builders ---------------------------------------------------------------------------

func _solid(size: Vector3, center: Vector3) -> void:
	Toon.solid_box(self, size, center)


## Wall segment from a to b (on the floor plane), with optional color.
func _wall(a: Vector2, b: Vector2, color: Color, height := H, y0 := 0.0, solid := true) -> void:
	var mid := (a + b) * 0.5
	var horiz := absf(a.y - b.y) < 0.001
	var length := absf(b.x - a.x) if horiz else absf(b.y - a.y)
	var size := Vector3(length, height, T) if horiz else Vector3(T, height, length)
	var c := Vector3(mid.x, y0 + height * 0.5, mid.y)
	Toon.box(self, size, c, color, 0.0)
	if solid:
		_solid(size, c)


## Counter with a body, a top and collision. Origin = floor center.
func _counter(size: Vector3, pos: Vector3, body: Color, top: Color, solid := true) -> void:
	Toon.block(self, Vector3(size.x - 0.04, size.y - 0.06, size.z - 0.04), pos, body, 0.04, 0.0)
	Toon.box(self, Vector3(size.x + 0.04, 0.06, size.z + 0.04), pos + Vector3(0, size.y - 0.03, 0), top, 0.006)
	Toon.box(self, Vector3(size.x - 0.1, 0.1, size.z - 0.08), pos + Vector3(0, 0.05, 0.02), body.darkened(0.35), 0.0)
	if solid:
		_solid(size, pos + Vector3(0, size.y * 0.5, 0))


func _shelf(pos: Vector3, size: Vector3, levels: int, color: Color, rot := 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot
	add_child(root)
	for i in levels:
		Toon.box(root, Vector3(size.x, 0.04, size.z), Vector3(0, 0.25 + i * (size.y - 0.3) / maxf(levels - 1, 1), 0), color, 0.004)
	for x: int in [-1, 1]:
		for z: int in [-1, 1]:
			Toon.box(root, Vector3(0.04, size.y, 0.04), Vector3(x * (size.x * 0.5 - 0.02), size.y * 0.5, z * (size.z * 0.5 - 0.02)), color.darkened(0.2), 0.0)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(cs)
	root.add_child(body)
	return root


func _label(text: String, pos: Vector3, size := 40, color := Color("#2b1c18"), rot_y := 0.0, outline := 0) -> Label3D:
	var l := Toon.label(self, text, pos, size, color, false)
	l.rotation.y = rot_y
	l.outline_size = outline
	return l


# --- floors, walls, ceiling ----------------------------------------------------------------

func _build_floors() -> void:
	# Floors sit 2cm above the town's block slab (top at 0.06) so they never z-fight.
	var a: Array[Transform3D] = []
	var b: Array[Transform3D] = []
	# Dining: red + cream checker
	var tile := 0.6
	var z := PARTITION_Z + tile * 0.5
	while z < D * 0.5:
		var x := -W * 0.5 + tile * 0.5
		while x < W * 0.5:
			var xf := Transform3D(Basis(), Vector3(x, 0.05, z))
			if (int(floor(x / tile)) + int(floor(z / tile))) % 2 == 0:
				a.append(xf)
			else:
				b.append(xf)
			x += tile
		z += tile
	Toon.multimesh(self, Shapes.box(Vector3(tile, 0.06, tile)), Toon.mat(Color("#a8382c"), 0.0), a)
	Toon.multimesh(self, Shapes.box(Vector3(tile, 0.06, tile)), Toon.mat(Color("#efe3cc"), 0.0), b)
	# Kitchen: terracotta quarry tile with grout
	var q1: Array[Transform3D] = []
	var q2: Array[Transform3D] = []
	var qt := 0.5
	z = -D * 0.5 + qt * 0.5
	while z < PARTITION_Z:
		var x := -W * 0.5 + qt * 0.5
		while x < BACKROOM_X:
			var xf := Transform3D(Basis(), Vector3(x, 0.05, z))
			if (int(floor(x / qt * 1.0)) * 7 + int(floor(z / qt)) * 3) % 5 == 0:
				q2.append(xf)
			else:
				q1.append(xf)
			x += qt
		z += qt
	var quarry := Shapes.box(Vector3(qt - 0.03, 0.06, qt - 0.03))
	Toon.multimesh(self, quarry, Toon.mat(Color("#9c5137"), 0.0), q1)
	Toon.multimesh(self, quarry, Toon.mat(Color("#8a4630"), 0.0), q2)
	Toon.box(self, Vector3(BACKROOM_X + W * 0.5, 0.05, PARTITION_Z + D * 0.5), Vector3((BACKROOM_X - W * 0.5) * 0.5, 0.04, (PARTITION_Z - D * 0.5) * 0.5), Color("#5e3a2c"), 0.0)
	# Walk-in: diamond plate; office: wood planks
	Toon.box(self, Vector3(W * 0.5 - BACKROOM_X, 0.06, 5.0), Vector3((BACKROOM_X + W * 0.5) * 0.5, 0.05, -6.5), Color("#9aa3ab"), 0.0)
	for i in 10:
		Toon.box(self, Vector3(W * 0.5 - BACKROOM_X, 0.065, 0.42), Vector3((BACKROOM_X + W * 0.5) * 0.5, 0.052, -3.55 + i * 0.45), Color("#9b6b45") if i % 2 == 0 else Color("#8d603d"), 0.0)


func _build_walls() -> void:
	var outer := Color("#e9d4b0")
	var dining := Color("#f2e2c4")
	var tile := Color("#e2e6df")
	var steel := Color("#b4bcc3")
	var hx := W * 0.5
	var hz := D * 0.5
	# Back wall with the back door opening
	var bd := (ANCHORS.backdoor as Vector3).x
	_wall(Vector2(-hx, -hz), Vector2(bd - 0.7, -hz), tile)
	_wall(Vector2(bd + 0.7, -hz), Vector2(hx, -hz), steel)
	_wall(Vector2(bd - 0.7, -hz), Vector2(bd + 0.7, -hz), tile, H - 2.3, 2.3)
	# Side walls
	_wall(Vector2(-hx, -hz), Vector2(-hx, hz), dining)
	_wall(Vector2(hx, -hz), Vector2(hx, hz), dining)
	# Front: low wall + big windows + door gap
	for side: int in [-1, 1]:
		var x0 := 1.3 * side
		var x1 := hx * side
		_wall(Vector2(minf(x0, x1), hz), Vector2(maxf(x0, x1), hz), Color("#7a3b2e"), 0.9)
		_wall(Vector2(minf(x0, x1), hz), Vector2(maxf(x0, x1), hz), outer, H - 3.1, 3.1)
		var glass := Toon.box(self, Vector3(hx - 1.3, 2.2, 0.06), Vector3((1.3 + hx) * 0.5 * side, 2.0, hz), Color("#a8d8ea"), 0.0)
		glass.material_override = _glass_mat()
		_solid(Vector3(hx - 1.3, 2.2, T), Vector3((1.3 + hx) * 0.5 * side, 2.0, hz))
		for k in 4:
			Toon.box(self, Vector3(0.1, 2.2, 0.16), Vector3((1.3 + k * (hx - 1.3) / 3.0) * side, 2.0, hz), Color("#7a3b2e"), 0.0)
		# Door frame
		Toon.box(self, Vector3(0.18, 3.1, 0.3), Vector3(1.3 * side, 1.55, hz), Color("#7a3b2e"), 0.0)
	_wall(Vector2(-1.3, hz), Vector2(1.3, hz), outer, H - 2.6, 2.6)
	_label("TONY'S", Vector3(0, 2.8, hz + 0.16), 70, Color("#ffd166"), 0.0, 14)
	# Partition (dining | kitchen) with the kitchen door + pass window
	var kd := (ANCHORS.kitchen_door as Vector3).x
	_wall(Vector2(-hx, PARTITION_Z), Vector2(kd - 0.8, PARTITION_Z), dining)
	_wall(Vector2(kd - 0.8, PARTITION_Z), Vector2(kd + 0.8, PARTITION_Z), dining, H - 2.3, 2.3)
	_wall(Vector2(kd + 0.8, PARTITION_Z), Vector2(0.0, PARTITION_Z), dining)
	_wall(Vector2(0.0, PARTITION_Z), Vector2(3.0, PARTITION_Z), dining, 1.05)
	_wall(Vector2(0.0, PARTITION_Z), Vector2(3.0, PARTITION_Z), dining, H - 2.15, 2.15)
	_wall(Vector2(3.0, PARTITION_Z), Vector2(hx, PARTITION_Z), dining)
	# Back rooms: wall at x = BACKROOM_X with doors to the walk-in and office
	_wall(Vector2(BACKROOM_X, -hz), Vector2(BACKROOM_X, -7.2), steel)
	_wall(Vector2(BACKROOM_X, -7.2), Vector2(BACKROOM_X, -5.8), steel, H - 2.3, 2.3)
	_wall(Vector2(BACKROOM_X, -5.8), Vector2(BACKROOM_X, -2.0), tile)
	_wall(Vector2(BACKROOM_X, -2.0), Vector2(BACKROOM_X, -0.7), tile, H - 2.3, 2.3)
	_wall(Vector2(BACKROOM_X, -0.7), Vector2(BACKROOM_X, PARTITION_Z), tile)
	_wall(Vector2(BACKROOM_X, -3.8), Vector2(hx, -3.8), steel)
	# Wainscoting + chair rail in the dining room
	for seg in [[Vector2(-hx + 0.14, PARTITION_Z), Vector2(-hx + 0.14, hz)], [Vector2(hx - 0.14, PARTITION_Z), Vector2(hx - 0.14, hz)]]:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		Toon.box(self, Vector3(0.04, 1.0, b.y - a.y), Vector3(a.x, 0.5, (a.y + b.y) * 0.5), Color("#a8382c"), 0.0)
		Toon.box(self, Vector3(0.07, 0.08, b.y - a.y), Vector3(a.x, 1.02, (a.y + b.y) * 0.5), Color("#6d4c41"), 0.0)
	Toon.box(self, Vector3(W, 1.0, 0.04), Vector3(0, 0.5, PARTITION_Z + 0.14), Color("#a8382c"), 0.0)
	Toon.box(self, Vector3(W, 0.08, 0.07), Vector3(0, 1.02, PARTITION_Z + 0.15), Color("#6d4c41"), 0.0)
	# Kitchen subway tile grout lines (makes the tile read as tile)
	var side_grout: Array[Transform3D] = []
	for i in 13:
		side_grout.append(Transform3D(Basis(), Vector3(-hx + 0.14, 0.15 + i * 0.14, (PARTITION_Z - hz) * 0.5)))
	Toon.multimesh(self, Shapes.box(Vector3(0.012, 0.012, PARTITION_Z + hz)), Toon.mat(Color("#c7cdca"), 0.0), side_grout)
	var back_grout: Array[Transform3D] = []
	for i in 13:
		back_grout.append(Transform3D(Basis(), Vector3((BACKROOM_X - hx) * 0.5, 0.15 + i * 0.14, -hz + 0.14)))
	Toon.multimesh(self, Shapes.box(Vector3(BACKROOM_X + hx, 0.012, 0.012)), Toon.mat(Color("#c7cdca"), 0.0), back_grout)
	# Swinging kitchen door flaps (they swing when you walk through)
	for side: int in [-1, 1]:
		var hinge := Node3D.new()
		hinge.position = Vector3(kd + 0.78 * side, 0.15, PARTITION_Z)
		add_child(hinge)
		var flap := Toon.block(hinge, Vector3(0.76, 1.9, 0.06), Vector3(-0.38 * side, 0, 0), Color("#b84a3a"), 0.08, 0.01)
		flap.name = "Flap"
		var port := Toon.cyl(hinge, 0.15, 0.15, 0.08, Vector3(-0.38 * side, 1.35, 0), Color("#a8d8ea"), 0.0, 10)
		port.rotation.x = PI / 2
		Toon.box(hinge, Vector3(0.7, 0.12, 0.08), Vector3(-0.38 * side, 0.55, 0), Color("#c7ced4"), 0.0)
		hinge.set_meta("side", side)
		_door_flaps.append(hinge)
	_label("KITCHEN\nEGGS ONLY", Vector3(kd, 2.55, PARTITION_Z + 0.14), 30, Color("#f6f4ef"), 0.0, 6)


func _glass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.66, 0.85, 0.92, 0.3)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _build_ceiling_and_roof() -> void:
	# Inside ceiling (what you see looking up) + ceiling tiles grid in the dining room
	Toon.box(self, Vector3(W, 0.1, D), Vector3(0, H + 0.05, 0), Color("#e8e2d6"), 0.0)
	var grid: Array[Transform3D] = []
	var x := -W * 0.5 + 1.2
	while x < W * 0.5:
		grid.append(Transform3D(Basis(), Vector3(x, H - 0.01, 5.0)))
		x += 1.2
	Toon.multimesh(self, Shapes.box(Vector3(0.04, 0.03, D * 0.5 - 1.0)), Toon.mat(Color("#cfc7b8"), 0.0), grid)
	# Outside roof
	_roof = Node3D.new()
	add_child(_roof)
	Toon.box(_roof, Vector3(W + 0.6, 0.35, D + 0.6), Vector3(0, H + 0.28, 0), Color("#8c3b2f"), 0.02)
	Toon.box(_roof, Vector3(W + 0.9, 0.3, 0.5), Vector3(0, H + 0.55, D * 0.5 + 0.2), Color("#c0392b"), 0.02)
	Toon.block(_roof, Vector3(2.2, 1.1, 1.6), Vector3(-5.5, H + 0.45, -6.0), Color("#a5a9ad"), 0.1)
	Toon.block(_roof, Vector3(1.4, 0.8, 1.4), Vector3(6.0, H + 0.45, -6.0), Color("#a5a9ad"), 0.1)
	Toon.cyl(_roof, 0.35, 0.35, 1.6, Vector3(-4.0, H + 1.2, -8.0), Color("#7f8c8d"), 0.012, 10)   # oven flue
	var sign_root := Node3D.new()
	sign_root.position = Vector3(0, H + 3.3, 3.0)
	_roof.add_child(sign_root)
	var crust := Toon.cyl(sign_root, 2.4, 2.4, 0.4, Vector3.ZERO, Color("#d9a35b"), 0.04, 18)
	crust.rotation.x = PI / 2
	var cheese := Toon.cyl(sign_root, 2.1, 2.1, 0.45, Vector3.ZERO, Color("#f2c14e"), 0.0, 18)
	cheese.rotation.x = PI / 2
	for i in 7:
		var a := TAU * i / 7.0
		var p := Toon.cyl(sign_root, 0.36, 0.36, 0.5, Vector3(cos(a) * 1.3, sin(a) * 1.3, 0.02), Color("#b8321f"), 0.0, 9)
		p.rotation.x = PI / 2
	Toon.cyl(_roof, 0.12, 0.12, 2.0, Vector3(0, H + 1.3, 3.0), Color("#555b61"), 0.01, 6)
	var tw := create_tween().set_loops()
	tw.tween_property(sign_root, "rotation:y", TAU, 5.0).from(0.0)
	var name_sign := Toon.label(_roof, "TONY'S PIZZA", Vector3(0, H + 1.2, D * 0.5 + 0.5), 230, Color("#ffd166"), false)
	name_sign.outline_size = 50


# --- dining room ------------------------------------------------------------------------------

func _build_dining() -> void:
	var hx := W * 0.5
	var hz := D * 0.5
	# Booths along the left wall: two benches + table each
	for i in 3:
		var z := 3.4 + i * 1.9
		var x := -hx + 1.0
		for side: int in [-1, 1]:
			var bz := z + 0.68 * side
			Toon.block(self, Vector3(1.5, 0.48, 0.5), Vector3(x + 0.2, 0, bz), Color("#c0392b"), 0.12, 0.012)
			Toon.block(self, Vector3(1.5, 0.75, 0.16), Vector3(x + 0.2, 0.45, bz + 0.25 * side), Color("#c0392b"), 0.3, 0.012)
			Toon.box(self, Vector3(1.4, 0.06, 0.08), Vector3(x + 0.2, 1.22, bz + 0.25 * side), Color("#6d4c41"), 0.0)
		Toon.box(self, Vector3(1.2, 0.06, 0.75), Vector3(x + 0.1, 0.76, z), Color("#e8d5b5"), 0.008)
		Toon.cyl(self, 0.06, 0.18, 0.73, Vector3(x + 0.1, 0.37, z), Color("#2d3436"), 0.006, 8)
		_table_dressing(Vector3(x + 0.1, 0.79, z))
		_solid(Vector3(1.5, 1.2, 1.9), Vector3(x + 0.2, 0.6, z))
		# Little framed photo above each booth
		Toon.box(self, Vector3(0.05, 0.5, 0.7), Vector3(-hx + 0.16, 2.0, z), Color("#6d4c41"), 0.0)
		Toon.box(self, Vector3(0.05, 0.4, 0.6), Vector3(-hx + 0.19, 2.0, z), [Color("#74b9ff"), Color("#ffeaa7"), Color("#fab1a0")][i], 0.0)
	# Round tables + chairs in the middle
	for p: Vector3 in [Vector3(-4.2, 0, 4.4), Vector3(-1.6, 0, 6.6), Vector3(1.6, 0, 4.6), Vector3(-4.6, 0, 7.6)]:
		Toon.cyl(self, 0.06, 0.22, 0.74, p + Vector3(0, 0.37, 0), Color("#2d3436"), 0.006, 8)
		Toon.cyl(self, 0.55, 0.55, 0.05, p + Vector3(0, 0.76, 0), Color("#f6f4ef"), 0.008, 14)
		Toon.cyl(self, 0.57, 0.57, 0.015, p + Vector3(0, 0.79, 0), Color("#c0392b"), 0.0, 14)
		_table_dressing(p + Vector3(0, 0.8, 0))
		_solid(Vector3(1.1, 0.8, 1.1), p + Vector3(0, 0.4, 0))
		for k in 3:
			var a := TAU * k / 3.0 + 0.4
			var c := p + Vector3(cos(a) * 0.9, 0, sin(a) * 0.9)
			Toon.cyl(self, 0.22, 0.22, 0.06, c + Vector3(0, 0.47, 0), Color("#8b5e3c"), 0.006, 10)
			Toon.cyl(self, 0.03, 0.03, 0.45, c + Vector3(0, 0.23, 0), Color("#2d3436"), 0.0, 5)
			var back := Toon.box(self, Vector3(0.36, 0.42, 0.05), c + Vector3(cos(a) * 0.18, 0.72, sin(a) * 0.18), Color("#8b5e3c"), 0.006)
			back.rotation.y = -a + PI / 2
	# Jukebox + arcade cabinet in the right front
	var jb := Vector3(hx - 0.7, 0, 7.6)
	Toon.block(self, Vector3(0.75, 1.6, 1.1), jb, Color("#8e44ad"), 0.3, 0.015)
	var dome := MeshInstance3D.new()
	dome.mesh = Shapes.box(Vector3(0.06, 0.6, 0.8))
	dome.material_override = Toon.glow(Color("#fd79a8"), 1.4)
	dome.position = jb + Vector3(-0.38, 1.15, 0)
	add_child(dome)
	_night_glows.append(dome)
	for k in 4:
		Toon.box(self, Vector3(0.05, 0.08, 0.6), jb + Vector3(-0.39, 0.6 + k * 0.1, 0), [Color("#ffd166"), Color("#55efc4"), Color("#74b9ff"), Color("#ff7675")][k], 0.0)
	_solid(Vector3(0.75, 1.6, 1.1), jb + Vector3(0, 0.8, 0))
	var arc := Vector3(hx - 0.6, 0, 5.8)
	Toon.block(self, Vector3(0.8, 1.9, 0.9), arc, Color("#2d3436"), 0.1, 0.015)
	var scr := MeshInstance3D.new()
	scr.mesh = Shapes.box(Vector3(0.05, 0.5, 0.6))
	scr.material_override = Toon.glow(Color("#55efc4"), 1.3)
	scr.position = arc + Vector3(-0.42, 1.45, 0)
	add_child(scr)
	Toon.box(self, Vector3(0.3, 0.12, 0.7), arc + Vector3(-0.45, 1.0, 0), Color("#636e72"), 0.006)
	Toon.ball(self, 0.05, arc + Vector3(-0.55, 1.1, 0.15), Color("#d63031"), 0.0, 6)
	_label("EGG\nINVADERS", arc + Vector3(-0.43, 1.82, 0), 26, Color("#ffd166"), -PI / 2, 6)
	_solid(Vector3(0.8, 1.9, 0.9), arc + Vector3(0, 0.95, 0))
	# Restroom door (out of order, obviously)
	Toon.box(self, Vector3(0.08, 2.2, 1.0), Vector3(hx - 0.15, 1.1, 3.3), Color("#6d4c41"), 0.006)
	Toon.box(self, Vector3(0.09, 0.3, 0.5), Vector3(hx - 0.18, 1.6, 3.3), Color("#f6f4ef"), 0.0)
	_label("RESTROOM\n(out of order)", Vector3(hx - 0.24, 1.6, 3.3), 18, Color("#2b1c18"), -PI / 2)
	# Wall posters + plants + coat rack
	_poster(Vector3(hx - 0.14, 2.4, 6.7), -PI / 2, "#ffeaa7", "EMPLOYEE\nOF THE\nMONTH:\nTONY\n(again)")
	_poster(Vector3(-hx + 0.14, 2.6, 8.4), PI / 2, "#74b9ff", "NO SHOES\nNO SHELL\nNO SERVICE")
	_poster(Vector3(-hx + 0.14, 2.6, 1.9), PI / 2, "#fab1a0", "TRY OUR\nNEW CRUST:\nSTILL CRUST")
	for p: Vector3 in [Vector3(1.9, 0, 8.4), Vector3(-1.9, 0, 8.4), Vector3(hx - 0.7, 0, 1.8)]:
		Toon.cyl(self, 0.28, 0.22, 0.5, p + Vector3(0, 0.25, 0), Color("#b5651d"), 0.01, 10)
		Toon.mesh(self, Shapes.blob(0.42, int(p.x * 10), 0.2), p + Vector3(0, 0.82, 0), Color("#40916c"), 0.015)
		Toon.mesh(self, Shapes.blob(0.28, int(p.x * 10) + 3, 0.2), p + Vector3(0.12, 1.18, 0.05), Color("#52b788"), 0.012)
	# Bell above the door
	Toon.cyl(self, 0.0, 0.08, 0.12, Vector3(0.0, 2.45, hz - 0.2), Color("#f1c40f"), 0.006, 8)


func _table_dressing(top: Vector3) -> void:
	# Shakers, napkins, a candle in a bottle. Makes tables feel used.
	Toon.cyl(self, 0.025, 0.03, 0.09, top + Vector3(-0.08, 0.045, 0.0), Color("#f6f4ef"), 0.0, 6)
	Toon.cyl(self, 0.025, 0.03, 0.09, top + Vector3(-0.02, 0.045, 0.0), Color("#c0392b"), 0.0, 6)
	Toon.box(self, Vector3(0.12, 0.1, 0.06), top + Vector3(0.08, 0.05, 0.0), Color("#b2bec3"), 0.0)
	Toon.cyl(self, 0.035, 0.05, 0.16, top + Vector3(0.0, 0.08, 0.14), Color("#27ae60"), 0.0, 6)
	Toon.cyl(self, 0.012, 0.012, 0.06, top + Vector3(0.0, 0.19, 0.14), Color("#f6f4ef"), 0.0, 4)


func _poster(pos: Vector3, rot: float, col: String, text: String) -> void:
	var p := Toon.box(self, Vector3(1.2, 1.4, 0.04), pos, Color(col), 0.006)
	p.rotation.y = rot
	var frame := Toon.box(self, Vector3(1.3, 1.5, 0.03), pos - Vector3(sin(rot), 0, cos(rot)) * 0.01, Color("#6d4c41"), 0.0)
	frame.rotation.y = rot
	_label(text, pos + Vector3(sin(rot), 0, cos(rot)) * 0.03, 28, Color("#2b1c18"), rot)


# --- order counter -----------------------------------------------------------------------------

func _build_counter() -> void:
	var cz := 2.25
	# L-shaped order counter in front of the pass window
	_counter(Vector3(8.0, 1.05, 0.75), Vector3(0.5, 0, cz), Color("#7a3b2e"), Color("#d9cbb3"))
	Toon.box(self, Vector3(8.0, 0.05, 0.05), Vector3(0.5, 0.55, cz + 0.39), Color("#ffd166"), 0.0)
	# Register + tip jar + bell + menu stand
	Toon.block(self, Vector3(0.5, 0.25, 0.4), Vector3(2.8, 1.05, cz), Color("#2d3436"), 0.15)
	var reg_screen := Toon.box(self, Vector3(0.36, 0.22, 0.04), Vector3(2.8, 1.42, cz - 0.05), Color("#55efc4"), 0.0)
	reg_screen.material_override = Toon.glow(Color("#55efc4"), 1.0)
	reg_screen.rotation.x = -0.4
	Toon.cyl(self, 0.09, 0.09, 0.2, Vector3(1.8, 1.15, cz + 0.15), Color("#a8d8ea"), 0.006, 10)
	_label("TIPS\n(please)", Vector3(1.8, 1.2, cz + 0.25), 14, Color("#2b1c18"))
	Toon.cyl(self, 0.06, 0.07, 0.04, Vector3(1.3, 1.07, cz + 0.2), Color("#b2bec3"), 0.006, 8)
	Toon.ball(self, 0.04, Vector3(1.3, 1.12, cz + 0.2), Color("#f1c40f"), 0.0, 6)
	# Soda fountain at the left end
	var sf := Vector3(-2.6, 1.05, cz - 0.05)
	Toon.block(self, Vector3(1.1, 0.75, 0.55), sf, Color("#c7ced4"), 0.08, 0.012)
	for k in 4:
		var col: Color = [Color("#c0392b"), Color("#27ae60"), Color("#f39c12"), Color("#2d3436")][k]
		Toon.box(self, Vector3(0.18, 0.22, 0.04), sf + Vector3(-0.39 + k * 0.26, 0.5, 0.29), col, 0.0)
		Toon.cyl(self, 0.02, 0.02, 0.08, sf + Vector3(-0.39 + k * 0.26, 0.25, 0.25), Color("#7f8c8d"), 0.0, 5)
	for k in 5:
		Toon.cyl(self, 0.05, 0.04, 0.12, sf + Vector3(0.7, 0.06 + k * 0.1, 0.0), Color("#f6f4ef"), 0.0, 8)
	# Menu board on the partition wall above the counter
	var mb := Vector3(-1.5, 2.85, PARTITION_Z + 0.16)
	Toon.box(self, Vector3(4.2, 1.4, 0.06), mb, Color("#2d3436"), 0.01)
	Toon.box(self, Vector3(4.3, 1.5, 0.04), mb - Vector3(0, 0, 0.02), Color("#6d4c41"), 0.0)
	_label("~ TONY'S MENU ~", mb + Vector3(0, 0.5, 0.05), 46, Color("#ffeaa7"), 0.0, 6)
	_label("SMALL  $8     MEDIUM  $11     LARGE  $14", mb + Vector3(0, 0.15, 0.05), 30, Color("#f6f4ef"), 0.0, 4)
	_label("toppings +$1 to $3  ·  sauces: tomato, bbq, white", mb + Vector3(0, -0.15, 0.05), 24, Color("#fab1a0"), 0.0, 4)
	_label("* no refunds for pizzas thrown at you *", mb + Vector3(0, -0.45, 0.05), 18, Color("#b2bec3"), 0.0, 2)


# --- kitchen --------------------------------------------------------------------------------------

func _build_kitchen() -> void:
	var steel := Color("#c7ced4")
	var steel_dark := Color("#8e969e")
	# Make-line island (the prep table): steel body, butcher-block top, topping rail behind
	var prep := ANCHORS.prep as Vector3
	_counter(Vector3(4.4, 0.95, 1.3), prep, steel_dark, Color("#d9b98c"))
	for k in 3:
		Toon.box(self, Vector3(0.04, 0.6, 0.02), prep + Vector3(-1.5 + k * 1.5, 0.45, 0.66), steel, 0.0)   # cabinet doors
	Toon.block(self, Vector3(4.2, 0.24, 0.42), prep + Vector3(0, 0.95, -0.46), steel, 0.1, 0.008)
	Toon.box(self, Vector3(4.25, 0.03, 0.46), prep + Vector3(0, 1.2, -0.46), Color("#e8eef1"), 0.0)
	# Sneeze guard over the topping rail
	var guard := Toon.box(self, Vector3(4.2, 0.03, 0.4), prep + Vector3(0, 1.5, -0.38), Color("#a8d8ea"), 0.0)
	guard.material_override = _glass_mat()
	for x: int in [-1, 1]:
		Toon.cyl(self, 0.015, 0.015, 0.35, prep + Vector3(2.0 * x, 1.33, -0.55), steel, 0.0, 5)
	# Ticket rail hanging above the make-line (live tickets appear here)
	ticket_rail = Node3D.new()
	ticket_rail.position = prep + Vector3(0, 2.25, -0.2)
	add_child(ticket_rail)
	Toon.box(ticket_rail, Vector3(3.6, 0.05, 0.08), Vector3.ZERO, steel, 0.0)
	for x: int in [-1, 1]:
		Toon.cyl(ticket_rail, 0.01, 0.01, 1.7, Vector3(1.7 * x, 0.85, 0), steel_dark, 0.0, 4)
	# Dough station: proofing rack with dough balls + big stand mixer + flour bins
	var dough := ANCHORS.dough as Vector3
	var rack := _shelf(dough, Vector3(0.7, 1.9, 1.1), 6, steel)
	var dough_balls: Array[Transform3D] = []
	for lvl in 5:
		for k in 3:
			dough_balls.append(Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), dough + Vector3(0.05, 0.3 + lvl * 0.32 + 0.06, -0.35 + k * 0.35)))
	Toon.multimesh(self, Shapes.ball(0.11, 10, 6), Toon.mat(Color("#f3e3c3"), 0.006), dough_balls)
	rack.name = "DoughRack"
	_label("DOUGH", dough + Vector3(0.38, 2.05, 0), 32, Color("#c0392b"), PI / 2, 4)
	var mixer := dough + Vector3(0.1, 0, -2.3)
	Toon.block(self, Vector3(0.7, 0.5, 0.8), mixer, Color("#dfe6e9"), 0.1, 0.012)
	Toon.block(self, Vector3(0.35, 1.2, 0.35), mixer + Vector3(-0.1, 0.5, -0.15), Color("#dfe6e9"), 0.15, 0.012)
	Toon.block(self, Vector3(0.45, 0.25, 0.75), mixer + Vector3(0, 1.55, 0.05), Color("#dfe6e9"), 0.25, 0.012)
	Toon.cyl(self, 0.24, 0.18, 0.35, mixer + Vector3(0, 0.75, 0.1), steel, 0.01, 12)
	_solid(Vector3(0.7, 1.8, 0.8), mixer + Vector3(0, 0.9, 0))
	for k in 2:
		Toon.block(self, Vector3(0.55, 0.7, 0.55), dough + Vector3(0.05, 0, 1.0 + k * 0.62), Color("#f6f4ef"), 0.1, 0.01)
		_label("FLOUR" if k == 0 else "SEMOLINA", dough + Vector3(0.34, 0.45, 1.0 + k * 0.62), 16, Color("#2b1c18"), PI / 2)
	_solid(Vector3(0.6, 0.7, 1.3), dough + Vector3(0.05, 0.35, 1.3))
	# Ovens on the back wall under a big exhaust hood
	for i in 2:
		_build_oven(ANCHORS["oven%d" % (i + 1)] as Vector3, i)
	var hood_c := Vector3(-3.85, 3.25, -8.4)
	Toon.block(self, Vector3(5.4, 0.7, 1.4), hood_c - Vector3(0, 0.35, 0), steel, 0.1, 0.012)
	Toon.box(self, Vector3(5.0, 0.04, 1.2), hood_c + Vector3(0, -0.36, 0.05), Color("#7f8c8d"), 0.0)
	for k in 5:
		Toon.box(self, Vector3(0.9, 0.3, 0.02), hood_c + Vector3(-2.0 + k * 1.0, 0.0, 0.69), Color("#9aa3ab"), 0.0)
	Toon.cyl(self, 0.3, 0.3, 0.8, hood_c + Vector3(0, 0.75, -0.2), steel, 0.01, 10)
	# Pizza peels hanging on the wall
	for k in 3:
		var pl := Vector3(-7.9 + k * 0.35, 1.5, -8.82)
		Toon.box(self, Vector3(0.04, 1.0, 0.03), pl + Vector3(0, 0.4, 0), Color("#8b5e3c"), 0.0)
		Toon.cyl(self, 0.17, 0.17, 0.02, pl + Vector3(0, -0.15, 0.0), Color("#b98b5e"), 0.006, 10).rotation.x = PI / 2
	# Cut & box station (island) + flat box stacks + shelf of folded boxes above
	var cut := ANCHORS.cut as Vector3
	_counter(Vector3(2.4, 0.95, 1.1), cut, steel_dark, steel)
	Toon.box(self, Vector3(0.9, 0.04, 0.8), (ANCHORS.cut_board as Vector3) + Vector3(0, -0.0, 0), Color("#b08b5a"), 0.006)
	for k in 6:
		Toon.block(self, Vector3(0.7, 0.04, 0.7), (ANCHORS.boxes as Vector3) + Vector3(0, k * 0.045, 0), Color("#d9b98c"), 0.02, 0.004)
	var box_shelf := _shelf(cut + Vector3(0.0, 0, -0.9), Vector3(2.2, 2.4, 0.5), 4, steel)
	box_shelf.name = "BoxShelf"
	for lvl in range(1, 4):
		for k in 4:
			Toon.block(self, Vector3(0.45, 0.32, 0.45), cut + Vector3(-0.8 + k * 0.52, 0.27 + lvl * 0.7, -0.9), Color("#d9b98c"), 0.02, 0.005)
	# Dish pit: three-compartment sink, rack, sprayer, soap
	var sink := Vector3(-9.4, 0, -8.35)
	_counter(Vector3(2.6, 0.95, 0.9), sink, steel_dark, steel)
	for k in 3:
		Toon.box(self, Vector3(0.65, 0.05, 0.6), sink + Vector3(-0.8 + k * 0.8, 0.9, 0.0), Color("#5d6d7e"), 0.0)
	Toon.cyl(self, 0.03, 0.03, 0.9, sink + Vector3(0.6, 1.4, -0.3), steel, 0.0, 6)
	var spray := Toon.cyl(self, 0.02, 0.02, 0.5, sink + Vector3(0.6, 1.85, -0.05), steel, 0.0, 6)
	spray.rotation.x = 1.2
	_shelf(sink + Vector3(0, 0, 0.0) + Vector3(0, 1.5, 0), Vector3(2.4, 0.9, 0.4), 2, steel)
	for k in 6:
		Toon.cyl(self, 0.15, 0.15, 0.02, sink + Vector3(-0.9 + k * 0.35, 1.9, -0.05), Color("#f6f4ef"), 0.004, 10).rotation.x = PI / 2
	_label("WASH YOUR SHELL", sink + Vector3(0, 2.7, 0.33), 22, Color("#c0392b"))
	# Hand sink + towels by the kitchen door
	var hs := Vector3(-7.4, 0, PARTITION_Z - 0.35)
	Toon.block(self, Vector3(0.55, 0.3, 0.45), hs + Vector3(0, 0.75, 0), steel, 0.15, 0.008)
	Toon.box(self, Vector3(0.3, 0.4, 0.12), hs + Vector3(0.55, 1.35, 0.15), Color("#f6f4ef"), 0.004)
	_label("HANDS!", hs + Vector3(0, 1.6, 0.22), 18, Color("#2b1c18"))
	# Wall shelves with tomato cans, spice jars, olive oil
	var ws := _shelf(Vector3(-1.0, 1.4, -8.75), Vector3(1.6, 1.0, 0.3), 2, steel)
	ws.name = "SpiceShelf"
	for k in 6:
		Toon.cyl(self, 0.07, 0.07, 0.16, Vector3(-1.6 + k * 0.24, 1.73, -8.75), Color("#c0392b"), 0.004, 8)
		Toon.cyl(self, 0.045, 0.045, 0.12, Vector3(-1.6 + k * 0.24, 2.36, -8.75), [Color("#27ae60"), Color("#e67e22"), Color("#8e44ad"), Color("#f1c40f")][k % 4], 0.004, 6)
	# Trash + recycling, mop bucket, fire extinguisher, first aid, clock
	var tr := ANCHORS.trash as Vector3
	Toon.cyl(self, 0.3, 0.26, 0.85, tr + Vector3(0, 0.42, 0), Color("#4f5b62"), 0.012, 12)
	Toon.cyl(self, 0.32, 0.32, 0.05, tr + Vector3(0, 0.86, 0), Color("#37474f"), 0.008, 12)
	Toon.cyl(self, 0.26, 0.22, 0.75, tr + Vector3(0.65, 0.37, 0), Color("#2e86de"), 0.01, 12)
	Toon.cyl(self, 0.25, 0.22, 0.35, Vector3(-8.8, 0.17, -0.2), Color("#f1c40f"), 0.01, 10)
	Toon.cyl(self, 0.02, 0.02, 1.3, Vector3(-8.75, 0.75, -0.25), Color("#8b5e3c"), 0.0, 5).rotation.z = 0.2
	Toon.cyl(self, 0.08, 0.08, 0.45, Vector3(-W * 0.5 + 0.22, 1.1, -5.9), Color("#d63031"), 0.008, 8)
	Toon.box(self, Vector3(0.05, 0.3, 0.35), Vector3(-W * 0.5 + 0.16, 1.6, -6.6), Color("#f6f4ef"), 0.004)
	Toon.box(self, Vector3(0.06, 0.08, 0.2), Vector3(-W * 0.5 + 0.18, 1.6, -6.6), Color("#d63031"), 0.0)
	var clock := Toon.cyl(self, 0.25, 0.25, 0.05, Vector3(0.5, 3.0, PARTITION_Z - 0.16), Color("#f6f4ef"), 0.008, 16)
	clock.rotation.x = PI / 2
	clock.name = "KitchenClock"
	# Utensil rail above the make-line
	for k in 6:
		var u := prep + Vector3(-1.6 + k * 0.6, 1.95, -0.62)
		Toon.cyl(self, 0.01, 0.01, 0.35, u, Color("#7f8c8d"), 0.0, 4)
		Toon.box(self, Vector3(0.1, 0.06, 0.02), u + Vector3(0, -0.2, 0), Color("#7f8c8d"), 0.0)


func _build_oven(pos: Vector3, index: int) -> void:
	# Index 0 = big brick dome oven, 1 = stainless deck oven (upgrade).
	var root := Node3D.new()
	root.name = "OvenBody%d" % (index + 1)
	root.position = pos
	add_child(root)
	if index == 0:
		Toon.block(root, Vector3(2.6, 0.95, 1.8), Vector3(0, 0, -0.1), Color("#a0522d"), 0.05, 0.015)
		Toon.mesh(root, Shapes.lathe(PackedVector2Array([Vector2(1.05, 0), Vector2(1.0, 0.45), Vector2(0.8, 0.9), Vector2(0.35, 1.2), Vector2(0, 1.25)]), 14, 0.5), Vector3(0, 0.95, -0.35), Color("#b5653d"), 0.02)
		# Brick pattern
		var bricks: Array[Transform3D] = []
		for row in 4:
			for k in 6:
				bricks.append(Transform3D(Basis(), Vector3(-1.1 + k * 0.44 + (0.22 if row % 2 == 1 else 0.0), 0.12 + row * 0.22, 0.81)))
		Toon.multimesh(root, Shapes.box(Vector3(0.4, 0.18, 0.02)), Toon.mat(Color("#8e4424"), 0.0), bricks)
		# The mouth: a brick arch with a dark opening, and a stone ledge to slide pizzas onto
		Toon.cyl(root, 0.66, 0.66, 0.08, Vector3(0, 0.95, 0.66), Color("#8e4424"), 0.012, 14).rotation.x = PI / 2
		Toon.cyl(root, 0.52, 0.52, 0.06, Vector3(0, 0.95, 0.71), Color("#1d1517"), 0.0, 14).rotation.x = PI / 2
		Toon.block(root, Vector3(1.4, 0.08, 0.5), Vector3(0, 0.88, 0.95), Color("#9a8f86"), 0.03, 0.01)
		var lbl := _label("TONY'S\nOVEN", Vector3(0, 1.75, 0.62), 26, Color("#ffd166"), 0.0, 6)
		lbl.reparent(root, false)
		lbl.position = Vector3(0, 2.0, 0.5)
	else:
		Toon.block(root, Vector3(2.0, 1.6, 1.5), Vector3(0, 0, -0.2), Color("#c7ced4"), 0.06, 0.015)
		Toon.box(root, Vector3(1.6, 0.35, 0.04), Vector3(0, 1.0, 0.56), Color("#1d1517"), 0.0)
		Toon.block(root, Vector3(1.6, 0.06, 0.45), Vector3(0, 0.8, 0.76), Color("#9aa3ab"), 0.02, 0.008)
		Toon.box(root, Vector3(1.7, 0.05, 0.08), Vector3(0, 1.25, 0.6), Color("#7f8c8d"), 0.0)
		for k in 3:
			var knob := Toon.cyl(root, 0.05, 0.05, 0.05, Vector3(-0.5 + k * 0.5, 0.45, 0.57), Color("#2d3436"), 0.0, 8)
			knob.rotation.x = PI / 2
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6 if index == 0 else 2.0, 2.2, 1.6)
	cs.shape = bs
	cs.position = Vector3(0, 1.1, -0.2)
	body.add_child(cs)
	root.add_child(body)


# --- walk-in cooler + office -------------------------------------------------------------------

func _build_walkin() -> void:
	var c := ANCHORS.walkin as Vector3
	var steel := Color("#c7ced4")
	# Strip curtain in the doorway
	for k in 6:
		var strip := Toon.box(self, Vector3(0.03, 2.2, 0.22), Vector3(BACKROOM_X + 0.05, 1.15, -7.05 + k * 0.23), Color("#dff6ff"), 0.0)
		strip.material_override = _glass_mat()
	_label("WALK-IN\nCOOLER", Vector3(BACKROOM_X - 0.15, 2.55, -6.5), 26, Color("#2e86de"), -PI / 2, 4)
	# Shelves full of stuff: one along the right wall, one along the back
	var shelves := [
		[Vector3(W * 0.5 - 0.5, 0, -6.4), 0.0, 4],
		[Vector3(7.6, 0, -8.5), PI / 2, 3],
	]
	for sdef in shelves:
		var root := _shelf(sdef[0], Vector3(0.7, 2.0, 3.6 if sdef[2] == 4 else 2.7), 4, steel, sdef[1])
		for lvl in 3:
			for k in int(sdef[2]):
				var item := Vector3(0, 0.3 + lvl * 0.57, -1.35 + k * 0.9)
				match (k + lvl) % 4:
					0:
						Toon.block(root, Vector3(0.5, 0.3, 0.5), item, Color("#e67e22"), 0.1, 0.006)
						for t in 3:
							Toon.ball(root, 0.08, item + Vector3(0, 0.33, -0.12 + t * 0.12), Color("#d63031"), 0.0, 6)
					1:
						Toon.cyl(root, 0.2, 0.2, 0.14, item + Vector3(0, 0.07, 0), Color("#f6dc8a"), 0.006, 12)
						Toon.cyl(root, 0.2, 0.2, 0.14, item + Vector3(0, 0.21, 0), Color("#f2c14e"), 0.006, 12)
					2:
						Toon.block(root, Vector3(0.4, 0.35, 0.55), item, Color("#f6f4ef"), 0.2, 0.006)
					_:
						Toon.block(root, Vector3(0.4, 0.4, 0.4), item, Color("#27ae60"), 0.1, 0.006)
	# Frost and a sad lone egg-shaped ice block
	Toon.box(self, Vector3(W * 0.5 - BACKROOM_X - 0.2, 0.08, 0.1), Vector3(c.x, 3.9, -8.85), Color("#dff6ff"), 0.0)
	Toon.mesh(self, Shapes.body_egg(0.7, 0.25, 0.0, 12, 8), c + Vector3(0, 0, 1.6), Color("#bfe9ff"), 0.012)
	_label("(it's just ice)", c + Vector3(0, 0.95, 1.85), 14, Color("#2e86de"))


func _build_office() -> void:
	var hx := W * 0.5
	# Desk with Tony's ancient PC
	var pc := ANCHORS.pc as Vector3
	_counter(Vector3(1.9, 0.78, 0.85), pc + Vector3(0, 0, 0.35), Color("#6d4c41"), Color("#a1785a"))
	Toon.block(self, Vector3(0.62, 0.5, 0.5), pc + Vector3(0, 0.78, 0.35), Color("#dfe6e9"), 0.1, 0.01)
	var screen := Toon.box(self, Vector3(0.48, 0.32, 0.02), pc + Vector3(0, 1.04, 0.09), Color("#55efc4"), 0.0)
	screen.material_override = Toon.glow(Color("#55efc4"), 1.2)
	_label("UPGRADES\n& STAFF", pc + Vector3(0, 1.05, 0.07), 14, Color("#1d1517"), PI)
	Toon.box(self, Vector3(0.5, 0.03, 0.18), pc + Vector3(0, 0.8, -0.05), Color("#b2bec3"), 0.0)
	Toon.cyl(self, 0.26, 0.26, 0.08, pc + Vector3(0, 0.48, -0.55), Color("#2d3436"), 0.008, 10)
	Toon.box(self, Vector3(0.48, 0.5, 0.06), pc + Vector3(0, 0.78, -0.78), Color("#2d3436"), 0.006)
	Toon.cyl(self, 0.05, 0.12, 0.45, pc + Vector3(0, 0.22, -0.55), Color("#555b61"), 0.0, 6)
	# Coffee mug + family photo (it's a pizza)
	Toon.cyl(self, 0.05, 0.05, 0.1, pc + Vector3(0.6, 0.83, 0.2), Color("#e17055"), 0.004, 8)
	Toon.box(self, Vector3(0.2, 0.16, 0.03), pc + Vector3(-0.65, 0.88, 0.5), Color("#f2c14e"), 0.004)
	# Staff board (shows who you've hired)
	var sb := ANCHORS.staff_board as Vector3
	Toon.box(self, Vector3(0.05, 1.0, 1.5), sb, Color("#b98b5e"), 0.006)
	_label("STAFF", sb + Vector3(-0.04, 0.4, 0), 30, Color("#2b1c18"), -PI / 2)
	var staff_lbl := _label("", sb + Vector3(-0.04, -0.05, 0), 20, Color("#2b1c18"), -PI / 2)
	staff_lbl.name = "StaffList"
	# Lockers, safe, filing cabinet, little couch
	for k in 4:
		Toon.block(self, Vector3(0.45, 1.9, 0.5), Vector3(5.2 + k * 0.48, 0, -3.45), [Color("#2e86de"), Color("#3a86ff"), Color("#2e86de"), Color("#3a86ff")][k], 0.04, 0.008)
		Toon.box(self, Vector3(0.2, 0.06, 0.02), Vector3(5.2 + k * 0.48, 1.6, -3.19), Color("#1d1517"), 0.0)
	_solid(Vector3(2.0, 1.9, 0.5), Vector3(5.92, 0.95, -3.45))
	Toon.block(self, Vector3(0.6, 0.7, 0.6), Vector3(hx - 0.5, 0, -3.1), Color("#636e72"), 0.08, 0.01)
	Toon.cyl(self, 0.1, 0.1, 0.05, Vector3(hx - 0.5, 0.4, -2.79), Color("#b2bec3"), 0.0, 10).rotation.x = PI / 2
	_solid(Vector3(0.6, 0.7, 0.6), Vector3(hx - 0.5, 0.35, -3.1))
	Toon.block(self, Vector3(1.6, 0.45, 0.7), Vector3(6.2, 0, -1.2), Color("#a8382c"), 0.2, 0.01)
	Toon.block(self, Vector3(1.6, 0.5, 0.18), Vector3(6.2, 0.4, -1.5), Color("#a8382c"), 0.3, 0.01)
	_solid(Vector3(1.6, 0.8, 0.7), Vector3(6.2, 0.4, -1.2))
	# Coffee machine on a little cart
	Toon.block(self, Vector3(0.5, 0.75, 0.4), Vector3(9.9, 0, -0.1), Color("#6d4c41"), 0.05)
	Toon.block(self, Vector3(0.32, 0.4, 0.3), Vector3(9.9, 0.75, -0.1), Color("#2d3436"), 0.15)
	Toon.cyl(self, 0.07, 0.06, 0.14, Vector3(9.9, 0.82, 0.05), Color("#a8d8ea"), 0.0, 8)


## Rewrites the staff board text (main calls this when you hire/fire).
func set_staff_board(lines: PackedStringArray) -> void:
	var l := get_node_or_null("StaffList") as Label3D
	if l == null:
		for c in get_children():
			if c.name == "StaffList":
				l = c
	if l:
		l.text = "\n".join(lines) if not lines.is_empty() else "(just you)"


# --- lights -------------------------------------------------------------------------------------

func _light(pos: Vector3, color: Color, rng: float, day: float, boost: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.omni_range = rng
	l.light_energy = day
	l.set_meta("day", day)
	l.set_meta("night_boost", boost)
	add_child(l)
	_lamps.append(l)


func _build_lights() -> void:
	# Dining: warm pendants
	for p: Vector3 in [Vector3(-4.0, H - 0.9, 5.0), Vector3(1.0, H - 0.9, 5.6), Vector3(-8.5, H - 0.9, 5.3), Vector3(6.0, H - 0.9, 5.3)]:
		Toon.cyl(self, 0.01, 0.01, 0.6, p + Vector3(0, 0.6, 0), Color("#2d3436"), 0.0, 4)
		Toon.cyl(self, 0.12, 0.45, 0.32, p, Color("#c0392b"), 0.01, 12)
		var bulb := MeshInstance3D.new()
		bulb.mesh = Shapes.ball(0.12, 8, 4)
		bulb.material_override = Toon.glow(Color("#ffd89a"), 3.0)
		bulb.position = p + Vector3(0, -0.18, 0)
		add_child(bulb)
	_light(Vector3(-3.0, H - 1.2, 5.2), Color("#ffd8a0"), 9.0, 0.16, 0.2)
	_light(Vector3(4.5, H - 1.2, 5.2), Color("#ffd8a0"), 8.0, 0.14, 0.2)
	# Kitchen: long fluorescent tubes (cool white)
	for p: Vector3 in [Vector3(-4.5, H - 0.05, -3.4), Vector3(-4.5, H - 0.05, -6.6), Vector3(1.5, H - 0.05, -3.4), Vector3(-8.5, H - 0.05, -4.5)]:
		Toon.box(self, Vector3(1.8, 0.08, 0.3), p, Color("#dfe6e9"), 0.0)
		var tube := MeshInstance3D.new()
		tube.mesh = Shapes.box(Vector3(1.6, 0.04, 0.16))
		tube.material_override = Toon.glow(Color("#f5fbff"), 1.0)
		tube.position = p + Vector3(0, -0.05, 0)
		add_child(tube)
	_light(Vector3(-4.5, H - 0.6, -3.6), Color("#eef6ff"), 8.0, 0.2, 0.1)
	_light(Vector3(-3.5, H - 0.6, -7.2), Color("#eef6ff"), 7.0, 0.16, 0.1)
	_light(Vector3(1.8, H - 0.6, -3.6), Color("#eef6ff"), 6.0, 0.16, 0.1)
	# Walk-in: cold blue; office: desk lamp
	_light(Vector3(8.0, H - 0.6, -6.5), Color("#bfe9ff"), 6.0, 0.25, 0.05)
	_light(Vector3(8.0, H - 0.5, -1.4), Color("#ffe1a8"), 6.0, 0.13, 0.12)
	# Heat lamps over the pass window (glowing red-orange)
	for k in 3:
		var hl := MeshInstance3D.new()
		hl.mesh = Shapes.cylinder(0.08, 0.16, 0.18, 8)
		hl.material_override = Toon.glow(Color("#ff8c42"), 2.2)
		hl.position = (ANCHORS.pass as Vector3) + Vector3(-0.9 + k * 0.9, 0.95, 0.0)
		add_child(hl)
	_light((ANCHORS.pass as Vector3) + Vector3(0, 0.7, 0), Color("#ffb070"), 2.5, 0.35, 0.0)


# --- exterior -----------------------------------------------------------------------------------

func _build_exterior() -> void:
	var hz := D * 0.5
	# Striped awning over the storefront
	for i in 14:
		var c := Color("#c0392b") if i % 2 == 0 else Color("#f6f4ef")
		var a := Toon.box(self, Vector3(W / 14.0, 0.1, 1.8), Vector3(-W * 0.5 + W / 28.0 + i * W / 14.0, 3.35, hz + 0.8), c, 0.0)
		a.rotation.x = 0.3
	# Neon OPEN sign in the window
	var neon := Node3D.new()
	add_child(neon)
	var n1 := MeshInstance3D.new()
	n1.mesh = Shapes.box(Vector3(1.4, 0.45, 0.05))
	n1.material_override = Toon.glow(Color("#ff4757"), 3.0)
	n1.position = Vector3(5.0, 2.4, hz - 0.1)
	neon.add_child(n1)
	Toon.label(neon, "OPEN", Vector3(5.0, 2.4, hz - 0.05), 56, Color.WHITE, false)
	_neon.append(neon)
	# Outdoor tables with umbrellas
	for x: float in [-7.5, -4.5, 5.5]:
		var p := Vector3(x, 0, hz + 2.6)
		Toon.cyl(self, 0.06, 0.15, 0.7, p + Vector3(0, 0.35, 0), Color("#2d3436"), 0.006, 6)
		Toon.cyl(self, 0.5, 0.5, 0.05, p + Vector3(0, 0.72, 0), Color("#f6f4ef"), 0.008, 12)
		Toon.cyl(self, 0.03, 0.03, 1.6, p + Vector3(0, 1.4, 0), Color("#7f8c8d"), 0.0, 5)
		Toon.cyl(self, 0.0, 1.2, 0.5, p + Vector3(0, 2.3, 0), Color("#c0392b") if x < 0 else Color("#27ae60"), 0.012, 10)
		_solid(Vector3(1.0, 0.8, 1.0), p + Vector3(0, 0.4, 0))
	# Parking spot paint + sign
	var park := ANCHORS.parking as Vector3
	for side: int in [-1, 1]:
		Toon.box(self, Vector3(0.15, 0.02, 5.0), park + Vector3(1.8 * side, 0.06, 0), Color("#f6f4ef"), 0.0)
	Toon.label(self, "DELIVERY\nCAR ONLY", park + Vector3(0, 0.08, -1.8), 60, Color("#f6f4ef"), false).rotation.x = -PI / 2
	# Side windows (so the building isn't a blank box from the street)
	for side: int in [-1, 1]:
		for k in 3:
			var wnd := Toon.box(self, Vector3(0.06, 1.2, 1.4), Vector3((W * 0.5 + 0.13) * side, 2.2, 3.5 + k * 2.2), Color("#9cc9d9"), 0.0)
			wnd.add_to_group("night_window")


func _build_alley() -> void:
	var hz := D * 0.5
	# Back door frame + "employees only" sign
	var bd := ANCHORS.backdoor as Vector3
	Toon.box(self, Vector3(1.6, 0.15, 0.32), bd + Vector3(0, 2.32, 0), Color("#6d4c41"), 0.0)
	_label("EMPLOYEES ONLY\n(and raccoons)", bd + Vector3(0, 2.6, -0.17), 18, Color("#f6f4ef"), PI, 4)
	# Dumpsters, crates, a raccoon-shaped egg
	for k in 2:
		var dp := Vector3(-2.0 + k * 2.6, 0, -hz - 1.6)
		Toon.block(self, Vector3(2.0, 1.3, 1.2), dp, Color("#27ae60") if k == 0 else Color("#2e86de"), 0.06, 0.015)
		var lid := Toon.box(self, Vector3(2.05, 0.08, 1.25), dp + Vector3(0, 1.36, -0.1), Color("#1e8449") if k == 0 else Color("#1f618d"), 0.008)
		lid.rotation.x = -0.15 if k == 1 else 0.0
		_solid(Vector3(2.0, 1.3, 1.2), dp + Vector3(0, 0.65, 0))
	for k in 3:
		Toon.block(self, Vector3(0.6, 0.45, 0.6), Vector3(5.5 + (k % 2) * 0.3, k / 2 * 0.45, -hz - 1.0), Color("#a1785a"), 0.06, 0.008)
	var racc := EggBody.new()
	add_child(racc)
	racc.build({"skin": "#7f8c8d", "ears": true, "hair_color": "#4b4f54", "tail": true, "eye": "big", "size": 0.5, "boots": "#2d3436", "glasses": true})
	racc.position = Vector3(1.0, 1.35, -hz - 1.6)
	racc.rotation.y = PI


# --- live bits -----------------------------------------------------------------------------------

func _refresh_ticket_rail() -> void:
	if ticket_rail == null:
		return
	for c in ticket_rail.get_children():
		if c.has_meta("slip"):
			c.queue_free()
	var open := Game.open_tickets()
	for i in mini(open.size(), 6):
		var t: Dictionary = open[i]
		var slip := Node3D.new()
		slip.set_meta("slip", true)
		slip.position = Vector3(-1.5 + i * 0.6, -0.22, 0.03)
		ticket_rail.add_child(slip)
		Toon.box(slip, Vector3(0.5, 0.42, 0.01), Vector3.ZERO, Color("#fffdf5"), 0.0)
		var txt := Toon.label(slip, "#%d %s\n%s\n%s" % [t.id, str(t.customer).split(" ")[0], Menu.describe(t.order), str(t.status).to_upper()], Vector3(0, 0, 0.01), 13, Color("#2b1c18"), false)
		txt.outline_size = 0
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD
		txt.width = 46.0


func _process(_delta: float) -> void:
	# Swinging kitchen doors push open away from whoever walks through.
	var who: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("door_pushers"):
		who.append(n as Node3D)
	var push := 0.0
	for n in who:
		var local := to_local(n.global_position)
		var d := Vector2(local.x - (ANCHORS.kitchen_door as Vector3).x, local.z - PARTITION_Z)
		if absf(d.x) < 1.0 and absf(d.y) < 1.2:
			push = signf(d.y) * (1.0 - absf(d.y) / 1.2) * 1.6 if absf(d.y) > 0.05 else push
	for f in _door_flaps:
		var side: int = f.get_meta("side")
		var target := -push * side
		f.rotation.y = lerpf(f.rotation.y, target, 0.15) + sin(Time.get_ticks_msec() * 0.012) * 0.02 * absf(f.rotation.y)
