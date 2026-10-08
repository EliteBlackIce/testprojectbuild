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
	Signs.board(root, "SHELL-OUT GAS", Vector3(0, 4.62, 8.1), Vector2(10.5, 1.2), Color("#fff4dc"), Color("#c0392b"), 0.0, "none", Color("#8a2a1f"))
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
	Signs.board(root, "MINI MART · EGGS SOLD HERE (??)", Vector3(0, 3.3, -1.42), Vector2(8.2, 0.9), Color("#2d3436"), Color("#ffeaa7"), 0.0, "lit")
	# Tall price sign
	Toon.cyl(root, 0.15, 0.15, 7.0, Vector3(8, 3.5, 7.5), Color("#555b61"), 0.01, 6)
	Toon.box(root, Vector3(2.4, 2.4, 0.3), Vector3(8, 7.4, 7.5), Color("#f6f4ef"), 0.015)
	Signs.board(root, "GAS\n$9.99", Vector3(8, 7.4, 7.68), Vector2(2.1, 2.1), Color("#fff4dc"), Color("#c0392b"), 0.0, "none", Color("#555b61"))


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
	Signs.board(root, "YOLK PARK", Vector3(c + 7.0, 2.4, size - 1.0), Vector2(5.0, 1.1), Color("#2d6a4f"), Color("#fff4dc"), 0.0, "posts", Color("#5a3d28"))


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
	Signs.board(parent, "EGGVILLE", pos + Vector3(0, 12.5, 3.75), Vector2(6.2, 1.6), Color("#fff4dc"), Color("#c0392b"), 0.0, "none", Color("#8a2a1f"))


## Rolling low-poly hills ringing the town, plus far mountains for depth.
## The hills, forests, rocks, lake, windmill, barn and mountains around town.
## Returns the windmill's blade hub so Town can spin it.
static func hills(parent: Node3D, center: Vector3, half: Vector2, rng: RandomNumberGenerator) -> Node3D:
	# --- forests (pines + round trees + autumn trees in clusters) -----------------
	var trunks: Array[Transform3D] = []
	var pines_a: Array[Transform3D] = []
	var pines_b: Array[Transform3D] = []
	var rounds: Array[Transform3D] = []
	var autumn: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var tries := 0
	var placed := 0
	while placed < 1500 and tries < 9000:
		tries += 1
		var x := center.x + rng.randf_range(-Terrain.EXTENT, Terrain.EXTENT) * 0.95
		var z := center.z + rng.randf_range(-Terrain.EXTENT, Terrain.EXTENT) * 0.95
		var d := Terrain.outside(x, z)
		if d < 22.0:
			continue
		var h := Terrain.height(x, z)
		if h < 0.8 or h > 50.0:
			continue
		# Clumpy: only plant where a low-frequency noise is high.
		var clump := Terrain._ridge.get_noise_2d(x * 0.9 + 500.0, z * 0.9)
		if clump < -0.05 and rng.randf() < 0.9:
			continue
		var sc := rng.randf_range(0.8, 1.9) * (1.0 + h * 0.004)
		var base := Vector3(x, h - 0.2, z)
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		var kind := rng.randf()
		if kind < 0.55:
			trunks.append(Transform3D(yaw.scaled(Vector3(sc, sc, sc)), base + Vector3(0, 0.9 * sc, 0)))
			pines_a.append(Transform3D(yaw.scaled(Vector3(sc, sc, sc)), base + Vector3(0, 2.2 * sc, 0)))
			pines_b.append(Transform3D(yaw.scaled(Vector3(sc * 0.72, sc * 0.9, sc * 0.72)), base + Vector3(0, 3.9 * sc, 0)))
		elif kind < 0.88:
			trunks.append(Transform3D(yaw.scaled(Vector3(sc, sc, sc)), base + Vector3(0, 0.9 * sc, 0)))
			(rounds if rng.randf() < 0.8 else autumn).append(Transform3D(yaw.scaled(Vector3(sc, sc, sc)), base + Vector3(0, 2.7 * sc, 0)))
		else:
			rocks.append(Transform3D(yaw.scaled(Vector3(sc * 1.4, sc * rng.randf_range(0.6, 1.2), sc * 1.4)), base + Vector3(0, 0.2, 0)))
		placed += 1
	Toon.multimesh(parent, Shapes.cylinder(0.2, 0.28, 1.8, 6), Toon.mat(Color("#8b5e3c"), 0.0), trunks)
	Toon.multimesh(parent, Shapes.cylinder(0.0, 1.5, 3.2, 7), Toon.mat(Color("#2f7d55"), 0.0), pines_a)
	Toon.multimesh(parent, Shapes.cylinder(0.0, 1.2, 2.6, 7), Toon.mat(Color("#3b9468"), 0.0), pines_b)
	Toon.multimesh(parent, Shapes.blob(1.7, 3, 0.18), Toon.mat(Color("#58b86a"), 0.0), rounds)
	Toon.multimesh(parent, Shapes.blob(1.7, 4, 0.18), Toon.mat(Color("#f0a23a"), 0.0), autumn)
	Toon.multimesh(parent, Shapes.blob(1.0, 9, 0.25), Toon.mat(Color("#9aa4ad"), 0.0), rocks)
	# --- a windmill on a ridge, with a little barn below it -----------------------
	var blades := Node3D.new()
	var wp := _hill_spot(center, half, rng, 28.0, 38.0, Vector2(1, -1))
	var wm := Node3D.new()
	wm.position = wp
	parent.add_child(wm)
	Toon.mesh(wm, Shapes.lathe(PackedVector2Array([Vector2(3.2, 0), Vector2(2.8, 4), Vector2(2.0, 11), Vector2(0, 12)]), 10, 0.0), Vector3(0, 0, 0), Color("#f4e7d0"), 0.0)
	Toon.mesh(wm, Shapes.cylinder(0.0, 2.6, 3.0, 10), Vector3(0, 0, 0), Color("#c0392b"), 0.0).position = Vector3(0, 13.2, 0)
	Toon.box(wm, Vector3(1.0, 1.6, 0.1), Vector3(0, 1.0, 3.1), Color("#6d4c41"), 0.0)
	blades.position = Vector3(0, 9.5, 3.0)
	wm.add_child(blades)
	for k in 4:
		var arm := Node3D.new()
		arm.rotation.z = TAU * k / 4.0
		blades.add_child(arm)
		Toon.box(arm, Vector3(0.25, 7.6, 0.12), Vector3(0, 4.0, 0), Color("#8b5e3c"), 0.0)
		Toon.box(arm, Vector3(1.5, 4.8, 0.06), Vector3(0.9, 5.0, 0.05), Color("#fff8e7"), 0.0)
	Toon.ball(blades, 0.6, Vector3.ZERO, Color("#6d4c41"), 0.0, 8)
	var bp := wp + Vector3(-22.0, 0, 16.0)
	bp.y = Terrain.height(bp.x, bp.z)
	var barn := Node3D.new()
	barn.position = bp
	parent.add_child(barn)
	Toon.block(barn, Vector3(9.0, 5.0, 12.0), Vector3.ZERO, Color("#b3372c"), 0.0, 0.0)
	var roof := Toon.mesh(barn, Shapes.prism(Vector3(10.0, 3.6, 13.0)), Vector3(0, 6.8, 0), Color("#7b2a24"), 0.0)
	roof.rotation.z = 0.0
	Toon.box(barn, Vector3(3.2, 4.0, 0.2), Vector3(0, 2.0, 6.05), Color("#f6efe2"), 0.0)
	# --- far mountains ---------------------------------------------------------------
	for i in 18:
		var a := TAU * i / 18.0 + rng.randf_range(-0.08, 0.08)
		var dist := rng.randf_range(0.97, 1.06) * (Terrain.EXTENT - 40.0)
		var p := center + Vector3(cos(a) * dist, -6.0, sin(a) * dist)
		var hgt := rng.randf_range(120.0, 210.0)
		var rad := rng.randf_range(90.0, 140.0)
		var m := Toon.cyl(parent, 0.0, rad, hgt, p + Vector3(0, hgt * 0.5, 0), Color("#7e8fb0"), 0.0, 6)
		m.rotation.y = rng.randf() * TAU
		Toon.cyl(parent, 0.0, rad * 0.33, hgt * 0.3, p + Vector3(0, hgt * 0.85, 0), Color("#f6f7fb"), 0.0, 6).rotation.y = m.rotation.y
	return blades


## A spot on a hill with a roughly-flat top, away from the lake.
static func _hill_spot(center: Vector3, half: Vector2, rng: RandomNumberGenerator, min_h: float, max_h: float, side: Vector2) -> Vector3:
	var best := center + Vector3(side.x * (half.x + 100.0), 0, side.y * (half.y + 100.0))
	var best_score := -INF
	for k in 160:
		var x := center.x + side.x * rng.randf_range(half.x + 50.0, half.x + 260.0)
		var z := center.z + side.y * rng.randf_range(half.y + 30.0, half.y + 220.0)
		var h := Terrain.height(x, z)
		var slope := absf(Terrain.height(x + 6.0, z) - h) + absf(Terrain.height(x, z + 6.0) - h)
		var score := -absf(h - (min_h + max_h) * 0.5) - slope * 4.0
		if score > best_score and h > min_h * 0.6:
			best_score = score
			best = Vector3(x, h - 0.3, z)
	return best