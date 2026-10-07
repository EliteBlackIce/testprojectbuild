class_name Landmarks
extends RefCounted
## Builders for the non-house parts of town. Each builds facing +Z.

const SHOPS := [
	["EGG-CELLENT BANK", "#d6e0f0", "#2e86de"],
	["YOLK'S HARDWARE", "#efe4b0", "#c0392b"],
	["OMELETTE CAFÉ", "#f6d6c8", "#e67e22"],
	["SCRAMBLED RECORDS", "#e8d0e8", "#8e44ad"],
	["SHELL-FIE STUDIO", "#cfe3d4", "#16a085"],
	["THE BOILED ROOM", "#d9c3a5", "#6d4c41"],
	["NOT TONY'S PIZZA", "#f3e2c7", "#2d3436"],
	["HARD BOILED DETECTIVE AGENCY", "#dfe6e9", "#2d3436"],
	["CRACKED PHONE REPAIR", "#c9e4de", "#0984e3"],
	["SUNNY SIDE LAUNDRY", "#ffeaa7", "#fdcb6e"],
]


## A downtown storefront building. Returns its footprint size.
static func shop(parent: Node3D, pos: Vector3, rot: float, idx: int, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot
	parent.add_child(root)
	var info: Array = SHOPS[idx % SHOPS.size()]
	var wall := Color(info[1])
	var accent := Color(info[2])
	var w := rng.randf_range(10.0, 13.0)
	var d := 10.0
	var floors := rng.randi_range(2, 4)
	var h := 1.0 + floors * 3.2
	Toon.block(root, Vector3(w, h, d), Vector3.ZERO, wall, 0.03, 0.03)
	Toon.solid_box(root, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	Toon.box(root, Vector3(w + 0.4, 0.5, d + 0.4), Vector3(0, h + 0.25, 0), wall.darkened(0.25), 0.02)
	# Storefront glass + door + awning + sign
	var glass := Toon.box(root, Vector3(w - 2.0, 2.6, 0.08), Vector3(0, 1.6, d * 0.5 + 0.03), Color("#9cc9d9"), 0.0)
	glass.add_to_group("night_window")
	Toon.box(root, Vector3(1.4, 2.6, 0.12), Vector3(w * 0.3, 1.3, d * 0.5 + 0.06), accent.darkened(0.3), 0.008)
	for i in 8:
		var c := accent if i % 2 == 0 else Color("#f6f4ef")
		var a := Toon.box(root, Vector3((w - 1.0) / 8.0, 0.1, 1.6), Vector3(-(w - 1.0) * 0.5 + (w - 1.0) / 16.0 + i * (w - 1.0) / 8.0, 3.3, d * 0.5 + 0.7), c, 0.0)
		a.rotation.x = 0.3
	Toon.box(root, Vector3(w - 1.0, 1.0, 0.2), Vector3(0, 4.2, d * 0.5 + 0.1), accent, 0.01)
	Toon.label(root, info[0], Vector3(0, 4.2, d * 0.5 + 0.25), 90 if str(info[0]).length() < 18 else 64, Color("#fff8e7"), false)
	# Upper windows
	for f in range(1, floors):
		for k in 4:
			var wx := -w * 0.36 + k * w * 0.24
			var pane := MeshInstance3D.new()
			pane.mesh = Shapes.box(Vector3(1.4, 1.6, 0.06))
			pane.material_override = Toon.mat(Color("#8fb8c9"), 0.0)
			pane.position = Vector3(wx, 1.0 + f * 3.2 + 1.6, d * 0.5 + 0.02)
			root.add_child(pane)
			if rng.randf() < 0.5:
				pane.add_to_group("night_window")
			Toon.box(root, Vector3(1.6, 0.14, 0.14), Vector3(wx, 1.0 + f * 3.2 + 0.75, d * 0.5 + 0.05), wall.darkened(0.25), 0.0)
	# Rooftop clutter: water tank / AC / antenna
	Toon.block(root, Vector3(1.6, 1.0, 1.4), Vector3(-w * 0.25, h + 0.5, -1.5), Color("#a5a9ad"), 0.1)
	if rng.randf() < 0.5:
		Toon.cyl(root, 0.9, 0.9, 1.6, Vector3(w * 0.25, h + 1.6, 0), Color("#8b5e3c"), 0.015, 8)
		Toon.cyl(root, 0.0, 1.1, 0.6, Vector3(w * 0.25, h + 2.7, 0), Color("#6d4c41"), 0.012, 8)
		for side: int in [-1, 1]:
			Toon.cyl(root, 0.06, 0.06, 1.0, Vector3(w * 0.25 + 0.6 * side, h + 0.8, 0), Color("#555b61"), 0.0, 4)


static func gas_station(parent: Node3D, pos: Vector3, rot: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot
	parent.add_child(root)
	Toon.box(root, Vector3(18, 0.06, 14), Vector3(0, 0.03, 2), Color("#8a8f98"), 0.0)
	# Canopy on pillars
	Toon.box(root, Vector3(12, 0.6, 7), Vector3(0, 5.0, 4.5), Color("#f6f4ef"), 0.02)
	Toon.box(root, Vector3(12.1, 0.3, 7.1), Vector3(0, 4.6, 4.5), Color("#e74c3c"), 0.0)
	Toon.label(root, "SHELL-OUT GAS", Vector3(0, 5.0, 8.05), 110, Color("#c0392b"), false)
	for x in [-4.0, 4.0]:
		Toon.cyl(root, 0.25, 0.25, 4.6, Vector3(x, 2.3, 4.5), Color("#dfe6e9"), 0.01, 6)
		Toon.solid_box(root, Vector3(0.6, 4.6, 0.6), Vector3(x, 2.3, 4.5))
		Toon.block(root, Vector3(0.9, 1.6, 0.6), Vector3(x + 1.6, 0, 4.5), Color("#e74c3c"), 0.15)
		Toon.box(root, Vector3(0.5, 0.4, 0.05), Vector3(x + 1.6, 1.2, 4.83), Color("#2d3436"), 0.0)
		Toon.solid_box(root, Vector3(0.9, 1.6, 0.6), Vector3(x + 1.6, 0.8, 4.5))
	# Mini mart
	Toon.block(root, Vector3(10, 4.0, 6), Vector3(0, 0, -4.5), Color("#ffeaa7"), 0.04, 0.025)
	Toon.solid_box(root, Vector3(10, 4.0, 6), Vector3(0, 2.0, -4.5))
	Toon.box(root, Vector3(6, 2.2, 0.08), Vector3(-1, 1.5, -1.47), Color("#9cc9d9"), 0.0).add_to_group("night_window")
	Toon.label(root, "MINI MART · EGGS SOLD HERE (??)", Vector3(0, 3.3, -1.4), 50, Color("#2d3436"), false)
	# Tall price sign
	Toon.cyl(root, 0.15, 0.15, 7.0, Vector3(8, 3.5, 7.5), Color("#555b61"), 0.01, 6)
	Toon.box(root, Vector3(2.4, 2.4, 0.3), Vector3(8, 7.4, 7.5), Color("#f6f4ef"), 0.015)
	Toon.label(root, "GAS\n$9.99", Vector3(8, 7.4, 7.7), 70, Color("#c0392b"), false)


static func park(parent: Node3D, origin: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = origin
	parent.add_child(root)
	var c := size * 0.5
	# Pond (sunken water disc with a rock rim)
	var pond := Vector3(c - 4.0, 0, c + 3.0)
	var water := Toon.cyl(root, 6.0, 6.0, 0.1, pond + Vector3(0, 0.12, 0), Color("#5fa8d3"), 0.0, 16)
	water.material_override = Toon.mat(Color("#5fa8d3"), 0.0, 0.15)
	for i in 14:
		var a := TAU * i / 14.0
		Toon.mesh(root, Shapes.blob(rng.randf_range(0.5, 0.8), i, 0.25), pond + Vector3(cos(a) * 6.2, 0.2, sin(a) * 6.2), Color("#9aa3ab"), 0.012)
	# Ducks (eggs again, obviously)
	for i in 3:
		var duck := EggBody.new()
		root.add_child(duck)
		duck.build({"skin": "#fdfdfd", "eye": "tiny", "snout": true, "size": 0.35, "ghost": true})
		duck.position = pond + Vector3(rng.randf_range(-3, 3), 0.05, rng.randf_range(-3, 3))
		duck.rotation.y = rng.randf() * TAU
	# Fountain
	var f := Vector3(c + 7.0, 0, c - 6.0)
	Toon.cyl(root, 2.6, 2.8, 0.7, f + Vector3(0, 0.35, 0), Color("#c9ced3"), 0.015, 12)
	Toon.cyl(root, 2.3, 2.3, 0.1, f + Vector3(0, 0.66, 0), Color("#74b9ff"), 0.0, 12)
	Toon.cyl(root, 0.3, 0.4, 1.8, f + Vector3(0, 1.5, 0), Color("#c9ced3"), 0.01, 8)
	Toon.mesh(root, Shapes.egg(1.2, 0.5), f + Vector3(0, 2.4, 0), Color("#e8dccb"), 0.015)
	Toon.solid_box(root, Vector3(5.2, 1.0, 5.2), f + Vector3(0, 0.5, 0))
	# Paths
	Toon.box(root, Vector3(2.4, 0.05, size), Vector3(c + 7.0, 0.04, c), Color("#e3d5ca"), 0.0)
	Toon.box(root, Vector3(size, 0.05, 2.4), Vector3(c, 0.04, c - 6.0), Color("#e3d5ca"), 0.0)
	# Benches + lamps along the paths
	for z in [3.0, 10.0, 20.0, 26.0]:
		var b := Vector3(c + 5.3, 0, z)
		Toon.box(root, Vector3(0.5, 0.1, 1.8), b + Vector3(0, 0.5, 0), Color("#8b5e3c"), 0.008)
		Toon.box(root, Vector3(0.1, 0.5, 1.8), b + Vector3(-0.25, 0.8, 0), Color("#8b5e3c"), 0.008)
		Toon.box(root, Vector3(0.4, 0.5, 0.1), b + Vector3(0, 0.25, 0.8), Color("#2d3436"), 0.0)
		Toon.box(root, Vector3(0.4, 0.5, 0.1), b + Vector3(0, 0.25, -0.8), Color("#2d3436"), 0.0)
	# Playground: slide + swing
	var pg := Vector3(5.0, 0, 6.0)
	Toon.block(root, Vector3(1.6, 2.2, 1.6), pg, Color("#e74c3c"), 0.1)
	var slide := Toon.box(root, Vector3(0.9, 0.12, 3.6), pg + Vector3(0, 1.2, 2.3), Color("#f1c40f"), 0.01)
	slide.rotation.x = 0.55
	Toon.solid_box(root, Vector3(1.6, 2.2, 1.6), pg + Vector3(0, 1.1, 0))
	var sw := pg + Vector3(5.0, 0, 0)
	for side: int in [-1, 1]:
		var leg := Toon.cyl(root, 0.08, 0.08, 3.0, sw + Vector3(1.5 * side, 1.4, 0), Color("#2e86de"), 0.008, 5)
		leg.rotation.z = 0.15 * side
	Toon.cyl(root, 0.08, 0.08, 3.4, sw + Vector3(0, 2.9, 0), Color("#2e86de"), 0.008, 5).rotation.z = PI / 2
	Toon.box(root, Vector3(0.6, 0.08, 0.3), sw + Vector3(0, 0.8, 0), Color("#8b5e3c"), 0.006)
	# Trees, lots of them
	for i in 16:
		var p := Vector3(rng.randf_range(2.0, size - 2.0), 0, rng.randf_range(2.0, size - 2.0))
		if p.distance_to(pond) < 8.0 or p.distance_to(f) < 4.0 or absf(p.x - (c + 7.0)) < 2.0 or absf(p.z - (c - 6.0)) < 2.0 or p.distance_to(pg) < 4.0 or p.distance_to(sw) < 3.0:
			continue
		tree(root, p, rng)
	Toon.label(root, "YOLK PARK", Vector3(c + 7.0, 3.0, size - 1.0), 120, Color("#2d6a4f"))


static func tree(parent: Node3D, p: Vector3, rng: RandomNumberGenerator) -> void:
	var kind := rng.randi() % 3
	var h := rng.randf_range(2.0, 3.0)
	Toon.cyl(parent, 0.22, 0.32, h, p + Vector3(0, h * 0.5, 0), Color("#8b5e3c"), 0.012, 6)
	Toon.solid_box(parent, Vector3(0.7, 3.0, 0.7), p + Vector3(0, 1.5, 0))
	var greens := ["#40916c", "#52b788", "#2d6a4f", "#74c69d"]
	var g := Color(greens[rng.randi() % greens.size()])
	match kind:
		0:
			var r := rng.randf_range(1.5, 2.2)
			Toon.mesh(parent, Shapes.blob(r, rng.randi(), 0.2), p + Vector3(0, h + r * 0.6, 0), g, 0.03)
			Toon.mesh(parent, Shapes.blob(r * 0.6, rng.randi(), 0.2), p + Vector3(r * 0.4, h + r * 1.3, 0.2), g.lightened(0.12), 0.02)
		1:
			# Pine: stacked cones
			for k in 3:
				Toon.cyl(parent, 0.0, 1.7 - k * 0.4, 1.7, p + Vector3(0, h + 0.4 + k * 1.0, 0), g.darkened(0.1), 0.02, 7)
		2:
			Toon.mesh(parent, Shapes.blob(1.4, rng.randi(), 0.15), p + Vector3(0, h + 1.0, 0), Color(["#f4a261", "#e76f51", "#f6bd60"][rng.randi() % 3]), 0.025)


static func water_tower(parent: Node3D, pos: Vector3) -> void:
	for x: int in [-1, 1]:
		for z: int in [-1, 1]:
			var leg := Toon.cyl(parent, 0.2, 0.25, 14.0, pos + Vector3(x * 2.2, 7.0, z * 2.2), Color("#9aa3ab"), 0.012, 5)
			leg.rotation = Vector3(z * 0.06, 0, -x * 0.06)
	Toon.mesh(parent, Shapes.egg(6.5, 3.8, 14, 8), pos + Vector3(0, 12.5, 0), Color("#f1e6d0"), 0.05)
	Toon.label(parent, "EGGVILLE", pos + Vector3(0, 16.5, 3.9), 220, Color("#c0392b"), false)


## Rolling low-poly hills ringing the town, plus far mountains for depth.
static func hills(parent: Node3D, center: Vector3, half: Vector2, rng: RandomNumberGenerator) -> void:
	var greens := ["#6fae5b", "#7bbf68", "#5e9e4f", "#86c06c"]
	var rx := half.x + 30.0
	var rz := half.y + 30.0
	for i in 40:
		var a := TAU * i / 40.0 + rng.randf_range(-0.05, 0.05)
		var p := center + Vector3(cos(a) * rx * rng.randf_range(1.0, 1.25), -2.0, sin(a) * rz * rng.randf_range(1.0, 1.25))
		var r := rng.randf_range(18.0, 32.0)
		var hill := Toon.mesh(parent, Shapes.blob(r, i, 0.12), p, Color(greens[i % greens.size()]), 0.0)
		hill.scale = Vector3(1.0, rng.randf_range(0.35, 0.6), 1.0)
		if rng.randf() < 0.5:
			tree(parent, p + Vector3(rng.randf_range(-6, 6), r * 0.3, rng.randf_range(-6, 6)), rng)
	for i in 14:
		var a := TAU * i / 14.0
		var p := center + Vector3(cos(a) * (rx + 180.0), -5.0, sin(a) * (rz + 180.0))
		var m := Toon.cyl(parent, 0.0, rng.randf_range(45.0, 70.0), rng.randf_range(60.0, 110.0), p, Color("#8e9fb5"), 0.0, 5)
		m.rotation.y = rng.randf() * TAU
		Toon.cyl(parent, 0.0, 12.0, 20.0, p + Vector3(0, m.mesh.get_aabb().size.y * 0.5 - 9.8, 0), Color("#f6f4ef"), 0.0, 5)
