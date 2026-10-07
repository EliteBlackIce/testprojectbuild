class_name Pizzeria
extends Node3D
## Tony's Pizza: the building, inside and out. Kitchen stations are added by
## Kitchen at the anchor points below. Front faces +Z (the street).
##
## When you're inside, the roof and the top of the front wall hide so the
## camera can see in (cutaway).

const W := 18.0
const D := 14.0
const H := 4.2
const T := 0.3

## Where stations go (local positions, on the floor).
const ANCHORS := {
	"fridge": Vector3(-8.0, 0, -4.2),
	"prep": Vector3(-4.0, 0, -3.0),
	"oven1": Vector3(-1.2, 0, -6.2),
	"oven2": Vector3(1.6, 0, -6.2),
	"cut": Vector3(4.6, 0, -6.0),
	"shelf": Vector3(8.0, 0, -3.6),
	"trash": Vector3(-6.6, 0, -0.6),
	"phone": Vector3(8.75, 0, 0.6),
	"board": Vector3(-4.0, 0, -6.85),
	"pc": Vector3(7.2, 0, 5.2),
	"tony": Vector3(2.0, 0, -2.0),
	"door": Vector3(0, 0, 7.0),
	"parking": Vector3(0, 0, 13.5),
	"spawn": Vector3(0, 0, 3.0),
}

var _roof: Node3D
var _front_upper: Node3D
var _upper_walls: Array = []   ## [node, local outward normal]
var _neon: Array[Node3D] = []
var _inside_area := AABB(Vector3(-W * 0.5, -1, -D * 0.5), Vector3(W, 6, D))
var _lamps: Array[OmniLight3D] = []


func build() -> void:
	_build_floor()
	_build_walls()
	_build_roof()
	_build_kitchen_furniture()
	_build_dining()
	_build_decor()
	_build_exterior()


func anchor(name: String) -> Vector3:
	return to_global(ANCHORS[name])


func is_inside(world_pos: Vector3) -> bool:
	return _inside_area.has_point(to_local(world_pos))


## Hides the roof and any wall between the camera and the inside.
func set_cutaway(on: bool, camera_pos := Vector3.ZERO) -> void:
	_roof.visible = not on
	var to_cam := camera_pos - global_position
	to_cam.y = 0.0
	to_cam = to_cam.normalized()
	for w in _upper_walls:
		var n: Vector3 = global_basis * (w[1] as Vector3)
		(w[0] as Node3D).visible = not on or n.dot(to_cam) < 0.15


## True if a point is inside the building footprint (plus a margin).
func covers(world_pos: Vector3, margin := 2.0) -> bool:
	var p := to_local(world_pos)
	return absf(p.x) < W * 0.5 + margin and absf(p.z) < D * 0.5 + margin


func set_night(amount: float) -> void:
	for l in _lamps:
		l.light_energy = lerpf(0.12, 0.5, amount)
	for n in _neon:
		n.visible = amount > 0.25 or Game.level("neon_sign") > 0


# --- structure --------------------------------------------------------------------------

func _build_floor() -> void:
	var red: Array[Transform3D] = []
	var white: Array[Transform3D] = []
	for ix in int(W):
		for iz in int(D):
			var xf := Transform3D(Basis(), Vector3(-W * 0.5 + 0.5 + ix, 0.045, -D * 0.5 + 0.5 + iz))
			if (ix + iz) % 2 == 0:
				red.append(xf)
			else:
				white.append(xf)
	var tile := Shapes.box(Vector3(1.0, 0.06, 1.0))
	Toon.multimesh(self, tile, Toon.mat(Color("#b23a2e"), 0.0), red)
	Toon.multimesh(self, tile, Toon.mat(Color("#efe6d6"), 0.0), white)


func _wall(size: Vector3, pos: Vector3, color: Color, parent: Node3D = self) -> void:
	Toon.box(parent, size, pos, color, 0.0)
	Toon.solid_box(self, size, pos)


func _build_walls() -> void:
	var wall := Color("#f0d9b5")
	var trim := Color("#7a3b2e")
	# Back + sides: a 1 m band that's always visible, the rest can be cut away.
	_split_wall(Vector3(W, H, T), Vector3(0, 0, -D * 0.5), Vector3.BACK * -1.0, wall, trim)
	_split_wall(Vector3(T, H, D), Vector3(-W * 0.5, 0, 0), Vector3.LEFT, wall, trim)
	_split_wall(Vector3(T, H, D), Vector3(W * 0.5, 0, 0), Vector3.RIGHT, wall, trim)
	# Front: low wall always, windows + upper part cut away.
	var door_half := 1.6
	var side_w := W * 0.5 - door_half
	for side: int in [-1, 1]:
		var cx := (door_half + side_w * 0.5) * side
		_wall(Vector3(side_w, 1.0, T), Vector3(cx, 0.5, D * 0.5), trim)
	_front_upper = Node3D.new()
	add_child(_front_upper)
	_upper_walls.append([_front_upper, Vector3.BACK])
	for side: int in [-1, 1]:
		var cx := (door_half + side_w * 0.5) * side
		var glass := Toon.box(_front_upper, Vector3(side_w - 0.4, 2.2, 0.08), Vector3(cx, 2.1, D * 0.5), Color("#a8d8ea"), 0.0)
		glass.material_override = _glass_mat()
		Toon.box(_front_upper, Vector3(side_w, 0.25, T + 0.05), Vector3(cx, 3.3, D * 0.5), wall, 0.0)
		Toon.box(_front_upper, Vector3(side_w, 0.9, T), Vector3(cx, H - 0.45, D * 0.5), wall, 0.0)
		for k in 3:
			Toon.box(_front_upper, Vector3(0.14, 2.3, T + 0.08), Vector3(cx - side_w * 0.5 + 0.07 + k * (side_w - 0.14) * 0.5, 2.15, D * 0.5), trim, 0.0)
		Toon.solid_box(self, Vector3(side_w, H - 1.0, T), Vector3(cx, 1.0 + (H - 1.0) * 0.5, D * 0.5))
	Toon.box(_front_upper, Vector3(door_half * 2.0 + 0.3, 1.0, T), Vector3(0, H - 0.5, D * 0.5), wall, 0.0)
	for side: int in [-1, 1]:
		Toon.box(self, Vector3(0.2, 3.2, T + 0.12), Vector3(door_half * side, 1.6, D * 0.5), trim, 0.0)


func _split_wall(size: Vector3, base: Vector3, normal: Vector3, wall: Color, trim: Color) -> void:
	Toon.solid_box(self, size, base + Vector3(0, H * 0.5, 0))
	var low := Vector3(size.x, 1.0, size.z)
	Toon.box(self, low, base + Vector3(0, 0.5, 0), wall, 0.0)
	# Dark wood band on the inside face
	var inset := -normal * (T * 0.5 + 0.03)
	var band := Vector3(maxf(size.x - 0.4, 0.05) if size.x > size.z else 0.05, 1.0, maxf(size.z - 0.4, 0.05) if size.z > size.x else 0.05)
	Toon.box(self, band, base + Vector3(0, 0.5, 0) + inset, trim, 0.0)
	var upper := Node3D.new()
	add_child(upper)
	Toon.box(upper, Vector3(size.x, H - 1.0, size.z), base + Vector3(0, 1.0 + (H - 1.0) * 0.5, 0), wall, 0.0)
	_upper_walls.append([upper, normal])


func _glass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.66, 0.85, 0.92, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _build_roof() -> void:
	_roof = Node3D.new()
	add_child(_roof)
	Toon.box(_roof, Vector3(W + 0.6, 0.35, D + 0.6), Vector3(0, H + 0.17, 0), Color("#8c3b2f"), 0.02)
	Toon.box(_roof, Vector3(W + 0.9, 0.3, 0.5), Vector3(0, H + 0.45, D * 0.5 + 0.2), Color("#c0392b"), 0.02)
	# Rooftop AC units, pipes, the giant pizza sign
	Toon.block(_roof, Vector3(2.0, 1.0, 1.5), Vector3(-5, H + 0.35, -3), Color("#a5a9ad"), 0.1)
	Toon.block(_roof, Vector3(1.4, 0.8, 1.4), Vector3(5.5, H + 0.35, -4), Color("#a5a9ad"), 0.1)
	var sign_root := Node3D.new()
	sign_root.name = "PizzaSign"
	sign_root.position = Vector3(0, H + 3.2, 1.0)
	_roof.add_child(sign_root)
	var crust := Toon.cyl(sign_root, 2.4, 2.4, 0.4, Vector3.ZERO, Color("#d9a35b"), 0.04, 16)
	crust.rotation.x = PI / 2
	var cheese := Toon.cyl(sign_root, 2.1, 2.1, 0.45, Vector3.ZERO, Color("#f2c14e"), 0.0, 16)
	cheese.rotation.x = PI / 2
	for i in 7:
		var a := TAU * i / 7.0
		var p := Toon.cyl(sign_root, 0.36, 0.36, 0.5, Vector3(cos(a) * 1.3, sin(a) * 1.3, 0.02), Color("#b8321f"), 0.0, 8)
		p.rotation.x = PI / 2
	Toon.cyl(_roof, 0.12, 0.12, 2.0, Vector3(0, H + 1.2, 1.0), Color("#555b61"), 0.01, 6)
	var tw := create_tween().set_loops()
	tw.tween_property(sign_root, "rotation:y", TAU, 5.0).from(0.0)
	var name_sign := Toon.label(_roof, "TONY'S PIZZA", Vector3(0, H + 1.1, D * 0.5 + 0.5), 230, Color("#ffd166"), false)
	name_sign.outline_size = 50


# --- kitchen -------------------------------------------------------------------------------

func _counter(size: Vector3, pos: Vector3, top := Color("#c9ced3"), body := Color("#8a5a44")) -> void:
	Toon.block(self, Vector3(size.x, size.y - 0.08, size.z), pos, body, 0.04, 0.012)
	Toon.box(self, Vector3(size.x + 0.08, 0.08, size.z + 0.08), pos + Vector3(0, size.y - 0.04, 0), top, 0.008)
	Toon.solid_box(self, size, pos + Vector3(0, size.y * 0.5, 0))


func _build_kitchen_furniture() -> void:
	# Prep table island + topping rail
	var prep := ANCHORS.prep as Vector3
	_counter(Vector3(3.4, 0.95, 1.3), prep)
	Toon.box(self, Vector3(3.4, 0.25, 0.45), prep + Vector3(0, 1.05, -0.48), Color("#d6dadf"), 0.008)
	# Sauce bottles on the left end, cheese tub on the right
	for i in 3:
		var col: Color = [Color("#c8321f"), Color("#6b2e1a"), Color("#f1e6cf")][i]
		Toon.cyl(self, 0.06, 0.08, 0.3, prep + Vector3(-1.45 + i * 0.17, 1.1, 0.35), col, 0.008, 6)
		Toon.cyl(self, 0.0, 0.03, 0.08, prep + Vector3(-1.45 + i * 0.17, 1.29, 0.35), Color("#f6f4ef"), 0.0, 5)
	Toon.cyl(self, 0.18, 0.15, 0.2, prep + Vector3(1.4, 1.05, 0.35), Color("#f6f4ef"), 0.01, 8)
	Toon.cyl(self, 0.16, 0.16, 0.02, prep + Vector3(1.4, 1.16, 0.35), Color("#f6dc8a"), 0.0, 8)
	# Topping bins (colored by topping)
	var tops := Menu.TOPPING_ORDER
	for i in tops.size():
		var t: String = tops[i]
		var x := -1.55 + i * (3.1 / (tops.size() - 1))
		Toon.box(self, Vector3(0.22, 0.12, 0.3), prep + Vector3(x, 1.22, -0.48), Color("#e9ecef"), 0.006)
		Toon.box(self, Vector3(0.18, 0.06, 0.26), prep + Vector3(x, 1.26, -0.48), Color(Menu.TOPPINGS[t].color), 0.0)
	# Dough fridge
	var fridge := ANCHORS.fridge as Vector3
	Toon.block(self, Vector3(1.1, 2.3, 1.6), fridge + Vector3(-0.2, 0, 0), Color("#d9dde1"), 0.06, 0.015)
	Toon.box(self, Vector3(0.06, 0.8, 0.08), fridge + Vector3(0.38, 1.4, 0.4), Color("#7f8c8d"), 0.0)
	Toon.box(self, Vector3(0.02, 2.0, 0.02), fridge + Vector3(0.36, 1.15, 0.0), Color("#9aa3ab"), 0.0)
	Toon.label(self, "DOUGH", fridge + Vector3(0.36, 1.9, 0.0), 40, Color("#c0392b"), false).rotation.y = PI / 2
	Toon.solid_box(self, Vector3(1.1, 2.3, 1.6), fridge + Vector3(-0.2, 1.15, 0))
	# Back counters + cut station + shelves
	_counter(Vector3(2.4, 0.95, 1.0), ANCHORS.cut as Vector3)
	Toon.cyl(self, 0.32, 0.32, 0.03, (ANCHORS.cut as Vector3) + Vector3(-0.4, 0.97, 0), Color("#b08b5a"), 0.006, 10)
	for i in 4:
		Toon.block(self, Vector3(0.7, 0.06, 0.7), (ANCHORS.cut as Vector3) + Vector3(0.6, 0.96 + i * 0.07, 0), Color("#d9b98c"), 0.02, 0.006)
	_counter(Vector3(1.2, 0.95, 2.4), ANCHORS.shelf as Vector3, Color("#c9ced3"), Color("#6d6f72"))
	Toon.box(self, Vector3(1.2, 0.08, 2.4), (ANCHORS.shelf as Vector3) + Vector3(0, 2.0, 0), Color("#6d6f72"), 0.008)
	for side: int in [-1, 1]:
		Toon.box(self, Vector3(0.08, 1.1, 0.08), (ANCHORS.shelf as Vector3) + Vector3(-0.5, 1.5, 1.1 * side), Color("#6d6f72"), 0.0)
	# Sink + dish rack along the back wall
	_counter(Vector3(2.2, 0.95, 1.0), Vector3(-6.2, 0, -6.2))
	Toon.box(self, Vector3(1.0, 0.2, 0.6), Vector3(-6.2, 0.9, -6.2), Color("#9aa3ab"), 0.006)
	Toon.cyl(self, 0.03, 0.03, 0.4, Vector3(-6.2, 1.2, -6.55), Color("#9aa3ab"), 0.0, 5)
	# Trash can
	Toon.cyl(self, 0.32, 0.28, 0.85, (ANCHORS.trash as Vector3) + Vector3(0, 0.42, 0), Color("#4f5b62"), 0.012, 9)
	Toon.cyl(self, 0.34, 0.34, 0.06, (ANCHORS.trash as Vector3) + Vector3(0, 0.87, 0), Color("#37474f"), 0.008, 9)
	# Ticket rail on the back wall + order board
	Toon.box(self, Vector3(3.8, 0.06, 0.08), (ANCHORS.board as Vector3) + Vector3(0, 2.6, 0.1), Color("#9aa3ab"), 0.0)
	# Hanging pans
	for i in 4:
		var p := Toon.cyl(self, 0.2 - i * 0.02, 0.2 - i * 0.02, 0.04, Vector3(-2.8 + i * 0.5, 2.6, -6.75), Color("#3d3d3d"), 0.006, 8)
		p.rotation.x = PI / 2
	# Flour sacks, tomato crate
	for i in 3:
		Toon.mesh(self, Shapes.blob(0.32, 20 + i, 0.08), Vector3(-8.2, 0.3 + (0.45 if i == 2 else 0.0), -1.5 + (0.6 if i == 1 else 0.0) + (0.3 if i == 2 else 0.0)), Color("#efe6d6"), 0.012).scale = Vector3(1.0, 0.8, 0.8)
	Toon.block(self, Vector3(0.8, 0.4, 0.6), Vector3(-7.9, 0, 0.8), Color("#a1785a"), 0.05)
	for i in 6:
		Toon.ball(self, 0.11, Vector3(-8.15 + (i % 3) * 0.22, 0.48, 0.68 + (i / 3) * 0.22), Color("#d63031"), 0.008, 6)
	# Ceiling lamps (warm)
	for p in [Vector3(-4, 3.6, -3), Vector3(1.5, 3.6, -3.5), Vector3(5.5, 3.6, -2), Vector3(-4, 3.6, 3.5), Vector3(4, 3.6, 4)]:
		# Shades live on the roof node so they hide with the cutaway.
		Toon.cyl(_roof, 0.1, 0.45, 0.3, p, Color("#2d3436"), 0.01, 8)
		var bulb := MeshInstance3D.new()
		bulb.mesh = Shapes.ball(0.14, 8, 4)
		bulb.material_override = Toon.glow(Color("#ffd89a"), 3.0)
		bulb.position = p + Vector3(0, -0.2, 0)
		_roof.add_child(bulb)
		var lamp := OmniLight3D.new()
		lamp.position = p + Vector3(0, -0.4, 0)
		lamp.light_color = Color("#ffd8a0")
		lamp.omni_range = 7.0
		lamp.light_energy = 0.12
		add_child(lamp)
		_lamps.append(lamp)


func _build_dining() -> void:
	# Front counter with register
	_counter(Vector3(7.0, 1.05, 0.9), Vector3(-5.4, 0, 2.0), Color("#c0392b"), Color("#7a3b2e"))
	Toon.block(self, Vector3(0.6, 0.35, 0.45), Vector3(-3.2, 1.05, 2.0), Color("#2d3436"), 0.1)
	Toon.box(self, Vector3(0.45, 0.22, 0.05), Vector3(-3.2, 1.35, 2.15), Color("#55efc4"), 0.0)
	# Tables with checkered cloths + chairs
	for p in [Vector3(-6, 0, 5), Vector3(-2.5, 0, 5.2), Vector3(3.2, 0, 5.0)]:
		Toon.cyl(self, 0.08, 0.2, 0.75, p + Vector3(0, 0.37, 0), Color("#2d3436"), 0.008, 6)
		Toon.cyl(self, 0.6, 0.6, 0.06, p + Vector3(0, 0.78, 0), Color("#f6f4ef"), 0.01, 10)
		Toon.cyl(self, 0.62, 0.62, 0.02, p + Vector3(0, 0.8, 0), Color("#c0392b"), 0.0, 5)
		Toon.cyl(self, 0.05, 0.05, 0.14, p + Vector3(0.15, 0.88, 0.1), Color("#c0392b"), 0.0, 5)
		Toon.solid_box(self, Vector3(1.2, 0.8, 1.2), p + Vector3(0, 0.4, 0))
		for side: int in [-1, 1]:
			Toon.cyl(self, 0.25, 0.25, 0.08, p + Vector3(0.95 * side, 0.48, 0), Color("#7a3b2e"), 0.008, 8)
			Toon.cyl(self, 0.05, 0.05, 0.45, p + Vector3(0.95 * side, 0.22, 0), Color("#2d3436"), 0.0, 5)
	# Office desk with Tony's ancient PC (upgrades)
	var pc := ANCHORS.pc as Vector3
	_counter(Vector3(1.8, 0.85, 0.9), pc + Vector3(0.4, 0, 0), Color("#a1785a"), Color("#6d4c41"))
	Toon.block(self, Vector3(0.7, 0.6, 0.6), pc + Vector3(0.4, 0.85, -0.05), Color("#dfe6e9"), 0.08)
	var screen := Toon.box(self, Vector3(0.5, 0.38, 0.02), pc + Vector3(0.4, 1.17, 0.26), Color("#55efc4"), 0.0)
	screen.material_override = Toon.glow(Color("#55efc4"), 1.2)
	# Jukebox + arcade machine, because Tony's has vibes
	Toon.block(self, Vector3(1.0, 1.7, 0.7), Vector3(-8.2, 0, 5.5), Color("#8e44ad"), 0.25)
	var juke := MeshInstance3D.new()
	juke.mesh = Shapes.box(Vector3(0.7, 0.5, 0.05))
	juke.material_override = Toon.glow(Color("#fd79a8"), 1.5)
	juke.position = Vector3(-7.85, 1.2, 5.5)
	juke.rotation.y = PI / 2
	add_child(juke)
	Toon.solid_box(self, Vector3(1.0, 1.7, 0.7), Vector3(-8.2, 0.85, 5.5))


func _build_decor() -> void:
	# Menu board above the counter
	var board := Toon.box(self, Vector3(4.0, 1.4, 0.08), Vector3(-5.0, 3.0, -6.8), Color("#2d3436"), 0.01)
	board.name = "MenuBoard"
	Toon.label(self, "MENU\nSmall $8  ·  Medium $11  ·  Large $14\nToppings +$1-3", Vector3(-5.0, 3.0, -6.74), 34, Color("#ffeaa7"), false)
	# Posters
	Toon.box(self, Vector3(1.4, 1.8, 0.04), Vector3(8.8, 2.4, 3.5), Color("#ffeaa7"), 0.008).rotation.y = -PI / 2
	Toon.label(self, "EMPLOYEE\nOF THE\nMONTH:\nTONY", Vector3(8.75, 2.4, 3.5), 34, Color("#c0392b"), false).rotation.y = -PI / 2
	Toon.box(self, Vector3(1.6, 1.0, 0.04), Vector3(-8.8, 2.6, 2.6), Color("#74b9ff"), 0.008).rotation.y = PI / 2
	Toon.label(self, "NO SHOES\nNO SHELL\nNO SERVICE", Vector3(-8.75, 2.6, 2.6), 30, Color("#2d3436"), false).rotation.y = PI / 2
	# Potted plants
	for p in [Vector3(1.9, 0, 6.2), Vector3(-1.9, 0, 6.2), Vector3(8.2, 0, 6.3)]:
		Toon.cyl(self, 0.28, 0.22, 0.5, p + Vector3(0, 0.25, 0), Color("#b5651d"), 0.01, 7)
		Toon.mesh(self, Shapes.blob(0.45, int(p.x * 10), 0.2), p + Vector3(0, 0.85, 0), Color("#40916c"), 0.015)


func _build_exterior() -> void:
	# Striped awning over the front windows
	for i in 12:
		var c := Color("#c0392b") if i % 2 == 0 else Color("#f6f4ef")
		var a := Toon.box(self, Vector3(W / 12.0, 0.12, 1.8), Vector3(-W * 0.5 + W / 24.0 + i * W / 12.0, 3.55, D * 0.5 + 0.8), c, 0.0)
		a.rotation.x = 0.3
	# Neon OPEN sign (lights up at night, always on with the Neon Sign upgrade)
	var neon := Node3D.new()
	add_child(neon)
	var n1 := MeshInstance3D.new()
	n1.mesh = Shapes.box(Vector3(1.6, 0.5, 0.06))
	n1.material_override = Toon.glow(Color("#ff4757"), 3.0)
	n1.position = Vector3(5.0, 2.6, D * 0.5 + 0.12)
	neon.add_child(n1)
	Toon.label(neon, "OPEN", Vector3(5.0, 2.6, D * 0.5 + 0.17), 60, Color.WHITE, false)
	_neon.append(neon)
	# Outdoor tables
	for x in [-6.0, -3.0]:
		var p := Vector3(x, 0, D * 0.5 + 2.6)
		Toon.cyl(self, 0.06, 0.15, 0.7, p + Vector3(0, 0.35, 0), Color("#2d3436"), 0.006, 6)
		Toon.cyl(self, 0.5, 0.5, 0.05, p + Vector3(0, 0.72, 0), Color("#f6f4ef"), 0.008, 9)
		Toon.cyl(self, 0.03, 0.03, 1.6, p + Vector3(0, 1.4, 0), Color("#7f8c8d"), 0.0, 5)
		Toon.cyl(self, 0.0, 1.2, 0.5, p + Vector3(0, 2.3, 0), Color("#c0392b") if x < -4 else Color("#27ae60"), 0.012, 8)
	# Parking spot paint
	var park := ANCHORS.parking as Vector3
	for side: int in [-1, 1]:
		Toon.box(self, Vector3(0.15, 0.02, 5.0), park + Vector3(1.8 * side, 0.06, 0), Color("#f6f4ef"), 0.0)
	Toon.label(self, "DELIVERY\nCAR ONLY", park + Vector3(0, 0.08, -1.8), 60, Color("#f6f4ef"), false).rotation.x = -PI / 2
