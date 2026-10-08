class_name Downtown
extends RefCounted
## The city centre: glass towers, brick mid-rises, art-deco landmarks with real
## storefronts, café patios, street trees, bus shelters and a plaza with a fountain.
## Every facade is drawn with Batch (a few MultiMeshes per building).

const NAMES := [
	["EGG-CELLENT BANK", "#2e86de"], ["YOLK'S HARDWARE", "#c0392b"], ["OMELETTE CAFÉ", "#e67e22"],
	["SCRAMBLED RECORDS", "#8e44ad"], ["SHELL-FIE STUDIO", "#16a085"], ["THE BOILED ROOM", "#6d4c41"],
	["NOT TONY'S PIZZA", "#2d3436"], ["HARD BOILED DETECTIVES", "#34495e"], ["CRACKED PHONE REPAIR", "#0984e3"],
	["SUNNY SIDE LAUNDRY", "#e1a21b"], ["BENEDICT BOOKS", "#a0522d"], ["POACHED PETS", "#d6336c"],
	["SHELLTER INSURANCE", "#1c7ed6"], ["HATCH HOTEL", "#7048e8"], ["WHISK TAKERS BAKERY", "#f08c00"],
]
const BRICKS := ["#b5654b", "#a0553f", "#c97b5a", "#9c6644", "#b98b6d"]
const CREAMS := ["#e8dcc4", "#dfd2b8", "#efe3cc", "#d9cdb4"]
const GLASS_WALLS := ["#6f8ea3", "#7d9bb0", "#5d7388", "#86a3b3", "#6a8795"]


## Fills one 30x30 downtown block: paving, four buildings, and a sidewalk full of life.
static func block(parent: Node3D, origin: Vector3, bi: int, bj: int, rng: RandomNumberGenerator, centre: bool) -> void:
	var root := Node3D.new()
	root.position = origin
	parent.add_child(root)
	var size := Town.BLOCK
	_paving(root, size)
	var name_i := (bi * 5 + bj * 3) % NAMES.size()
	var styles := ["glass", "brick", "deco", "brick", "glass", "shop", "deco", "shop"]
	var cut := rng.randi_range(12, 16)
	for row in 2:
		var widths := [float(cut) - 0.3, size - float(cut) - 0.3] if row == 0 else [size - float(cut) - 0.3, float(cut) - 0.3]
		var x := 0.0
		for k in 2:
			var w: float = widths[k]
			var idx := bi * 7 + bj * 11 + row * 3 + k
			var style: String = styles[(idx + rng.randi() % 3) % styles.size()]
			var floors := rng.randi_range(8, 14) if (centre and style in ["glass", "deco"]) else rng.randi_range(3, 7)
			if style == "shop":
				floors = rng.randi_range(3, 5)
			var nm: Array = NAMES[(name_i + row * 2 + k) % NAMES.size()]
			var cx := x + w * 0.5 + 0.15
			if row == 0:
				building(root, Vector3(cx, 0, size - 3.0 - 5.0), 0.0, w, 10.0, floors, style, nm[0], Color(nm[1]), rng)
			else:
				building(root, Vector3(size - cx, 0, 3.0 + 5.0), PI, w, 10.0, floors, style, nm[0], Color(nm[1]), rng)
			x += w + 0.6
	_alley(root, size, rng)
	_street_life(root, size, bi, bj, rng)


static func _paving(root: Node3D, size: float) -> void:
	Toon.box(root, Vector3(size, 0.012, size), Vector3(size * 0.5, 0.066, size * 0.5), Color("#d6d1c9"), 0.0)
	var b := Batch.new()
	var t := 2.0
	while t < size:
		b.box(Vector3(t, 0.074, size * 0.5), Vector3(0.04, 0.006, size), Color("#bdb7ae"))
		b.box(Vector3(size * 0.5, 0.074, t), Vector3(size, 0.006, 0.04), Color("#bdb7ae"))
		t += 2.0
	b.flush(root, 120.0)


static func _alley(root: Node3D, size: float, rng: RandomNumberGenerator) -> void:
	var b := Batch.new()
	for k in rng.randi_range(2, 4):
		var p := Vector3(rng.randf_range(2.0, size - 2.0), 0, size * 0.5 + rng.randf_range(-1.2, 1.2))
		match rng.randi() % 4:
			0:   # dumpster
				b.box(p + Vector3(0, 0.6, 0), Vector3(2.0, 1.2, 1.0), Color("#2f6f4f"))
				b.box(p + Vector3(0, 1.25, 0), Vector3(2.1, 0.1, 1.1), Color("#25563d"))
			1:   # crates
				for q in 3:
					b.box(p + Vector3(q * 0.55 - 0.5, 0.25 + (q % 2) * 0.5, 0), Vector3(0.5, 0.5, 0.5), Color("#b58b5b"))
			2:   # bins
				for q in 2:
					b.cyl(p + Vector3(q * 0.6, 0.45, 0), 0.25, 0.9, Color("#6b7380"))
			_:   # steam pipe
				b.cyl(p + Vector3(0, 1.0, 0), 0.12, 2.0, Color("#8a8f98"))
				b.cyl(p + Vector3(0, 2.05, 0), 0.2, 0.15, Color("#6b7380"))
	b.flush(root, 100.0)


# --- one building --------------------------------------------------------------------------------

static func building(parent: Node3D, pos: Vector3, rot_y: float, w: float, d: float, floors: int, style: String, label: String, accent: Color, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	parent.add_child(root)
	var b := Batch.new()
	var gh := 4.6
	var fh := 3.3
	var h := gh + (floors - 1) * fh
	var fz := d * 0.5
	var wall: Color
	var trim := Color("#f4efe6")
	match style:
		"glass":
			wall = Color(GLASS_WALLS[rng.randi() % GLASS_WALLS.size()])
			trim = Color("#35424f")
		"brick":
			wall = Color(BRICKS[rng.randi() % BRICKS.size()])
		"deco":
			wall = Color(CREAMS[rng.randi() % CREAMS.size()])
		_:
			wall = Color(["#e7c9a9", "#cfe0d4", "#e9d1d0", "#d7d9ec"][rng.randi() % 4])
	Toon.block(root, Vector3(w, h, d), Vector3.ZERO, wall, 0.03, 0.03)
	Toon.solid_box(root, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	_storefront(b, root, w, fz, gh, accent, label, rng)
	match style:
		"glass":
			_facade_glass(b, w, fz, gh, fh, floors, trim, rng)
		"brick":
			_facade_brick(b, w, fz, gh, fh, floors, wall, trim, rng)
		"deco":
			_facade_deco(b, w, fz, gh, fh, floors, trim, accent, rng)
		_:
			_facade_shop(b, w, fz, gh, fh, floors, wall, trim, rng)
	_side_windows(b, w, d, gh, fh, floors, rng)
	_roof(b, root, w, d, h, style, accent, trim, rng)
	b.flush(root, 260.0)


static func _win(b: Batch, c: Vector3, w: float, h: float, trim: Color, rng: RandomNumberGenerator, curtains := true) -> void:
	b.glass(c + Vector3(0, 0, 0.01), Vector3(w, h, 0.05), rng.randf() < 0.45)
	for sx: int in [-1, 1]:
		b.box(c + Vector3(sx * (w * 0.5 + 0.06), 0, 0.05), Vector3(0.12, h + 0.2, 0.12), trim)
	b.box(c + Vector3(0, h * 0.5 + 0.1, 0.06), Vector3(w + 0.4, 0.16, 0.18), trim)
	b.box(c + Vector3(0, -h * 0.5 - 0.06, 0.1), Vector3(w + 0.36, 0.1, 0.26), trim)
	b.box(c + Vector3(0, 0, 0.04), Vector3(0.05, h, 0.06), trim)
	b.box(c + Vector3(0, h * 0.12, 0.04), Vector3(w, 0.05, 0.06), trim)
	if curtains and rng.randf() < 0.4:
		b.box(c + Vector3(-w * 0.3, h * 0.05, 0.04), Vector3(w * 0.3, h * 0.8, 0.03), Color("#e9c46a").lerp(Color.WHITE, 0.3))


static func _storefront(b: Batch, root: Node3D, w: float, fz: float, gh: float, accent: Color, label: String, rng: RandomNumberGenerator) -> void:
	var dark := Color("#2d3436")
	var bays := maxi(2, int((w - 3.0) / 2.6))
	var bay_w := (w - 3.0) / bays
	# glass bays on a stall riser, with mullions and a transom row
	for k in bays:
		var x := -w * 0.5 + 0.8 + bay_w * (k + 0.5)
		b.glass(Vector3(x, 1.95, fz + 0.03), Vector3(bay_w - 0.18, 2.5, 0.06), rng.randf() < 0.6)
		b.box(Vector3(x, 0.38, fz + 0.06), Vector3(bay_w - 0.1, 0.72, 0.12), accent.darkened(0.35))
		b.box(Vector3(x - bay_w * 0.5, 1.9, fz + 0.07), Vector3(0.1, 3.0, 0.12), dark)
		b.glass(Vector3(x, 3.5, fz + 0.03), Vector3(bay_w - 0.18, 0.5, 0.06), rng.randf() < 0.5)
	b.box(Vector3(-w * 0.5 + 0.8 + bay_w * bays, 1.9, fz + 0.07), Vector3(0.1, 3.0, 0.12), dark)
	# entrance on the right: recessed double door, canopy, steps
	var dx := w * 0.5 - 1.2
	b.box(Vector3(dx, 1.2, fz + 0.05), Vector3(2.0, 2.5, 0.1), dark)
	b.glass(Vector3(dx - 0.45, 1.25, fz + 0.12), Vector3(0.8, 2.2, 0.05), true)
	b.glass(Vector3(dx + 0.45, 1.25, fz + 0.12), Vector3(0.8, 2.2, 0.05), true)
	b.box(Vector3(dx, 1.25, fz + 0.15), Vector3(0.06, 2.2, 0.06), Color("#cfd4d8"))
	b.box(Vector3(dx, 0.06, fz + 0.5), Vector3(2.4, 0.12, 1.0), Color("#b9b3aa"))
	# sign band, blade sign and a striped awning
	Signs.board(root, label, Vector3(0, 4.1, fz + 0.16), Vector2(w - 0.8, 0.95), accent, Color("#fff8e7"), 0.0, "lit", accent.darkened(0.55)).name = "ShopSign"
	for k in int(w / 0.9) - 2:
		var c := accent.lightened(0.15) if k % 2 == 0 else Color("#f6f4ef")
		b.box(Vector3(-w * 0.5 + 1.6 + k * 0.9, 3.35, fz + 0.75), Vector3(0.9, 0.06, 1.7), c, Vector3(0.32, 0, 0))
	b.box(Vector3(0, 2.92, fz + 1.5), Vector3(w - 3.0, 0.1, 0.08), accent.darkened(0.2))
	if rng.randf() < 0.5:
		var bx := -w * 0.5 + 0.2
		b.box(Vector3(bx, 5.0, fz + 0.6), Vector3(0.1, 0.1, 1.2), dark)
		b.box(Vector3(bx, 4.4, fz + 1.2), Vector3(0.1, 1.2, 0.9), accent.lightened(0.2))
		b.ball(Vector3(bx, 4.4, fz + 1.22), 0.22, Color("#fff8e7"), Vector3(0.3, 1.0, 1.0))
	# sidewalk bits in front: planters, an A-frame board, a bench, a patio
	for sx: int in [-1, 1]:
		b.box(Vector3(sx * (w * 0.5 - 0.5), 0.35, fz + 1.8), Vector3(0.8, 0.7, 0.8), Color("#7a6a5a"))
		b.ball(Vector3(sx * (w * 0.5 - 0.5), 0.95, fz + 1.8), 0.45, Color("#3c8d4f"), Vector3(1, 1.1, 1))
	if rng.randf() < 0.55:
		var px := rng.randf_range(-w * 0.25, w * 0.1)
		b.box(Vector3(px - 0.25, 0.5, fz + 1.7), Vector3(0.06, 1.0, 0.8), Color("#fff8e7"), Vector3(0, 0, 0.22))
		b.box(Vector3(px + 0.25, 0.5, fz + 1.7), Vector3(0.06, 1.0, 0.8), Color("#fff8e7"), Vector3(0, 0, -0.22))
	if label.contains("CAFÉ") or label.contains("BAKERY") or label.contains("PIZZA") or rng.randf() < 0.3:
		for t in 3:
			var tp := Vector3(-w * 0.3 + t * 2.4, 0, fz + 3.0)
			b.cyl(tp + Vector3(0, 0.7, 0), 0.4, 0.05, Color("#fff8e7"))
			b.cyl(tp + Vector3(0, 0.35, 0), 0.04, 0.7, Color("#444a50"))
			for sd: int in [-1, 1]:
				b.box(tp + Vector3(sd * 0.6, 0.45, 0), Vector3(0.38, 0.05, 0.38), Color("#c0674b"))
				b.box(tp + Vector3(sd * 0.74, 0.7, 0), Vector3(0.05, 0.5, 0.38), Color("#c0674b"))
			if t != 1:
				b.cyl(tp + Vector3(0, 1.4, 0), 0.03, 1.6, Color("#444a50"))
				b.cone(tp + Vector3(0, 2.1, 0), 1.1, 0.35, accent.lightened(0.1))


static func _facade_glass(b: Batch, w: float, fz: float, gh: float, fh: float, floors: int, trim: Color, rng: RandomNumberGenerator) -> void:
	var bays := int((w - 0.8) / 1.5)
	var bw := (w - 0.8) / bays
	for f in range(1, floors):
		var y0 := gh + (f - 1) * fh
		for k in bays:
			var x := -w * 0.5 + 0.4 + bw * (k + 0.5)
			b.glass(Vector3(x, y0 + fh * 0.55, fz + 0.03), Vector3(bw - 0.1, fh - 1.0, 0.06), rng.randf() < 0.5)
			b.box(Vector3(x - bw * 0.5, y0 + fh * 0.5, fz + 0.07), Vector3(0.1, fh, 0.1), trim)
		b.box(Vector3(0, y0 + 0.2, fz + 0.06), Vector3(w, 0.55, 0.12), trim)
	b.box(Vector3(w * 0.5 - 0.4, (gh + (floors - 1) * fh) * 0.5, fz + 0.07), Vector3(0.1, gh + (floors - 1) * fh, 0.1), trim)


static func _facade_brick(b: Batch, w: float, fz: float, gh: float, fh: float, floors: int, wall: Color, trim: Color, rng: RandomNumberGenerator) -> void:
	var cols := int(w / 2.7)
	var cw := w / cols
	for f in range(1, floors):
		var y0 := gh + (f - 1) * fh
		for k in cols:
			var x := -w * 0.5 + cw * (k + 0.5)
			_win(b, Vector3(x, y0 + fh * 0.5, fz + 0.01), 1.3, 1.9, trim, rng)
			b.box(Vector3(x, y0 + fh * 0.5 + 1.2, fz + 0.06), Vector3(1.7, 0.2, 0.14), wall.darkened(0.25))
		b.box(Vector3(0, y0 + 0.04, fz + 0.06), Vector3(w + 0.1, 0.14, 0.12), wall.darkened(0.2))
		if rng.randf() < 0.3:
			b.box(Vector3(-w * 0.5 + cw * (rng.randi() % cols + 0.5), y0 + 0.7, fz + 0.4), Vector3(0.7, 0.55, 0.6), Color("#cfd4d8"))
	# fire escape down one side
	if rng.randf() < 0.65 and floors >= 4:
		var ex := w * 0.5 - cw * 0.5 - 1.4
		for f in range(1, floors):
			var y := gh + (f - 1) * fh + 0.1
			b.box(Vector3(ex, y, fz + 0.65), Vector3(2.0, 0.07, 1.1), Color("#2d3436"))
			for q in 6:
				b.box(Vector3(ex - 0.9 + q * 0.36, y + 0.5, fz + 1.18), Vector3(0.04, 0.9, 0.04), Color("#2d3436"))
			b.box(Vector3(ex, y + 0.98, fz + 1.18), Vector3(2.0, 0.05, 0.05), Color("#2d3436"))
			if f < floors - 1:
				b.box(Vector3(ex + 0.55, y + fh * 0.5, fz + 0.9), Vector3(0.55, 0.05, 1.9), Color("#2d3436"), Vector3(0.0, 0.0, 0.0))


static func _facade_deco(b: Batch, w: float, fz: float, gh: float, fh: float, floors: int, trim: Color, accent: Color, rng: RandomNumberGenerator) -> void:
	var top := gh + (floors - 1) * fh
	var piers := maxi(3, int(w / 2.8))
	var pw := w / piers
	for k in piers + 1:
		var x := -w * 0.5 + pw * k
		b.box(Vector3(x, gh + (top - gh) * 0.5, fz + 0.18), Vector3(0.55, top - gh, 0.36), trim)
		b.box(Vector3(x, top + 0.2, fz + 0.2), Vector3(0.7, 0.5, 0.4), accent.lightened(0.3))
	for f in range(1, floors):
		var y0 := gh + (f - 1) * fh
		for k in piers:
			var x := -w * 0.5 + pw * (k + 0.5)
			b.glass(Vector3(x, y0 + fh * 0.55, fz + 0.03), Vector3(pw - 0.9, fh - 1.1, 0.06), rng.randf() < 0.5)
			b.box(Vector3(x, y0 + 0.2, fz + 0.1), Vector3(pw - 0.5, 0.6, 0.1), accent.darkened(0.1))
			b.box(Vector3(x, y0 + fh * 0.55, fz + 0.06), Vector3(0.05, fh - 1.1, 0.06), trim)
	b.box(Vector3(0, top + 0.1, fz + 0.1), Vector3(w + 0.3, 0.3, 0.3), accent)


static func _facade_shop(b: Batch, w: float, fz: float, gh: float, fh: float, floors: int, wall: Color, trim: Color, rng: RandomNumberGenerator) -> void:
	var cols := maxi(2, int(w / 4.2))
	var cw := w / cols
	for f in range(1, floors):
		var y0 := gh + (f - 1) * fh
		for k in cols:
			var x := -w * 0.5 + cw * (k + 0.5)
			# bay window: a little box that juts out with three panes
			b.box(Vector3(x, y0 + fh * 0.5, fz + 0.5), Vector3(2.4, 2.3, 1.0), wall.lightened(0.12))
			b.glass(Vector3(x, y0 + fh * 0.55, fz + 1.02), Vector3(2.0, 1.7, 0.05), rng.randf() < 0.45)
			for sd: int in [-1, 1]:
				b.glass(Vector3(x + sd * 1.3, y0 + fh * 0.55, fz + 0.75), Vector3(0.9, 1.7, 0.05), rng.randf() < 0.45, Vector3(0, -sd * 0.9, 0))
			b.box(Vector3(x, y0 + fh * 0.5 + 1.25, fz + 0.55), Vector3(2.7, 0.18, 1.2), trim)
			b.box(Vector3(x, y0 + fh * 0.5 - 1.2, fz + 0.55), Vector3(2.6, 0.12, 1.15), trim)
		b.box(Vector3(0, y0 + 0.02, fz + 0.06), Vector3(w + 0.1, 0.14, 0.12), trim)


static func _side_windows(b: Batch, w: float, d: float, gh: float, fh: float, floors: int, rng: RandomNumberGenerator) -> void:
	var trim := Color("#d8d2c6")
	for sd: int in [-1, 1]:
		for f in floors:
			var y := (2.0 if f == 0 else gh + (f - 1) * fh + fh * 0.5)
			var z := -d * 0.5 + 1.8
			while z < d * 0.5 - 1.0:
				b.glass(Vector3(sd * (w * 0.5 + 0.02), y, z), Vector3(0.05, 1.5, 1.1), rng.randf() < 0.4)
				b.box(Vector3(sd * (w * 0.5 + 0.05), y - 0.85, z), Vector3(0.2, 0.08, 1.4), trim)
				z += 2.6


static func _roof(b: Batch, root: Node3D, w: float, d: float, h: float, style: String, accent: Color, trim: Color, rng: RandomNumberGenerator) -> void:
	# parapet + cornice
	var cor := Color("#cfc7b8") if style != "glass" else Color("#2d3a45")
	b.box(Vector3(0, h + 0.15, 0), Vector3(w + 0.5, 0.3, d + 0.5), cor)
	for sx: int in [-1, 1]:
		b.box(Vector3(sx * (w * 0.5 + 0.05), h + 0.6, 0), Vector3(0.18, 0.7, d), cor.darkened(0.08))
	for sz: int in [-1, 1]:
		b.box(Vector3(0, h + 0.6, sz * (d * 0.5 + 0.05)), Vector3(w, 0.7, 0.18), cor.darkened(0.08))
	if style == "shop" or style == "brick":
		var x := -w * 0.5 + 0.4
		while x < w * 0.5 - 0.2:
			b.box(Vector3(x, h - 0.1, d * 0.5 + 0.18), Vector3(0.28, 0.24, 0.24), cor)   # dentils
			x += 0.62
	var top := h
	if style in ["glass", "deco"] and h > 22.0:
		# setback crown + spire
		Toon.block(root, Vector3(w * 0.7, 5.4, d * 0.7), Vector3(0, h + 0.3, 0), (Color("#8fb0c4") if style == "glass" else Color("#e6dcc5")), 0.03, 0.03)
		b.box(Vector3(0, h + 5.9, 0), Vector3(w * 0.7 + 0.4, 0.4, d * 0.7 + 0.4), cor)
		for k in 4:
			b.glass(Vector3(-w * 0.26 + k * w * 0.175, h + 2.8, d * 0.35 + 0.03), Vector3(w * 0.12, 3.4, 0.06), rng.randf() < 0.6)
		b.cone(Vector3(0, h + 8.0, 0), 0.5, 4.0, accent.lightened(0.2))
		b.cyl(Vector3(0, h + 11.2, 0), 0.05, 2.6, Color("#cfd4d8"))
		var beacon := Toon.ball(root, 0.22, Vector3(0, h + 12.6, 0), Color("#ff4d4d"), 0.0, 8)
		beacon.material_override = Toon.glow(Color("#ff4d4d"), 2.2)
		top = h + 6.0
	# rooftop gear
	var n := rng.randi_range(2, 4)
	for k in n:
		var px := rng.randf_range(-w * 0.35, w * 0.35)
		var pz := rng.randf_range(-d * 0.25, d * 0.25)
		match rng.randi() % 4:
			0:
				b.box(Vector3(px, top + 0.8, pz), Vector3(1.8, 1.0, 1.4), Color("#a5a9ad"))
				b.cyl(Vector3(px, top + 1.5, pz), 0.4, 0.2, Color("#6c7378"))
			1:
				b.cyl(Vector3(px, top + 2.0, pz), 0.9, 1.8, Color("#8b5e3c"))
				b.cone(Vector3(px, top + 3.3, pz), 1.1, 0.7, Color("#6d4c41"))
				for sd: int in [-1, 1]:
					b.cyl(Vector3(px + 0.6 * sd, top + 0.6, pz), 0.05, 1.2, Color("#555b61"))
			2:
				b.box(Vector3(px, top + 0.6, pz), Vector3(2.4, 0.8, 1.6), Color("#8f969d"))
				for q in 3:
					b.cyl(Vector3(px - 0.7 + q * 0.7, top + 1.05, pz), 0.28, 0.1, Color("#4d5359"))
			_:
				b.cyl(Vector3(px, top + 1.8, pz), 0.04, 3.2, Color("#cfd4d8"))
				b.box(Vector3(px, top + 2.8, pz), Vector3(0.9, 0.05, 0.05), Color("#cfd4d8"))
	# big roof billboard on some low buildings
	if h < 24.0 and rng.randf() < 0.25:
		b.box(Vector3(0, top + 2.4, 0), Vector3(w * 0.5, 2.4, 0.2), accent)
		b.box(Vector3(-w * 0.2, top + 1.0, 0), Vector3(0.2, 2.0, 0.2), Color("#555b61"))
		b.box(Vector3(w * 0.2, top + 1.0, 0), Vector3(0.2, 2.0, 0.2), Color("#555b61"))


# --- the sidewalks ---------------------------------------------------------------------------------

static func _street_life(root: Node3D, size: float, bi: int, bj: int, rng: RandomNumberGenerator) -> void:
	var b := Batch.new()
	for edge in 2:
		var z := 0.9 if edge == 0 else size - 0.9
		var x := 4.0
		while x < size - 2.0:
			if rng.randf() < 0.55:
				# a street tree in a planter
				b.box(Vector3(x, 0.25, z), Vector3(1.0, 0.5, 1.0), Color("#8a7a68"))
				b.cyl(Vector3(x, 1.3, z), 0.12, 1.7, Color("#7a5236"))
				b.ball(Vector3(x, 2.6, z), 1.0, Color(["#52b788", "#40916c", "#74c69d"][rng.randi() % 3]), Vector3(1, 1.1, 1))
				b.ball(Vector3(x + 0.4, 3.1, z - 0.2), 0.7, Color("#74c69d"))
			elif rng.randf() < 0.5:
				# bench
				b.box(Vector3(x, 0.5, z), Vector3(1.7, 0.08, 0.5), Color("#8b5e3c"))
				b.box(Vector3(x, 0.85, z + (0.22 if edge == 0 else -0.22)), Vector3(1.7, 0.45, 0.06), Color("#8b5e3c"))
				for sd: int in [-1, 1]:
					b.box(Vector3(x + sd * 0.75, 0.25, z), Vector3(0.08, 0.5, 0.45), Color("#2d3436"))
			else:
				# trash can / bike rack / newspaper box
				match rng.randi() % 3:
					0:
						b.cyl(Vector3(x, 0.45, z), 0.28, 0.9, Color("#4d5b65"))
						b.cyl(Vector3(x, 0.92, z), 0.3, 0.08, Color("#3a444c"))
					1:
						for q in 4:
							b.box(Vector3(x + q * 0.3 - 0.45, 0.4, z), Vector3(0.04, 0.8, 0.5), Color("#8a9097"))
					_:
						b.box(Vector3(x, 0.55, z), Vector3(0.5, 1.1, 0.5), Color(["#2e86de", "#e63946", "#f4a261"][rng.randi() % 3]))
			x += rng.randf_range(4.0, 7.0)
	# a bus shelter on some blocks
	if (bi + bj) % 2 == 0:
		var sx := size * 0.5 + 6.0
		var sz := 1.4
		for k in 4:
			b.box(Vector3(sx - 1.4 + (k % 2) * 2.8, 1.1, sz + (k / 2) * 0.0), Vector3(0.08, 2.2, 0.08), Color("#2d3436"))
		b.box(Vector3(sx, 2.25, sz), Vector3(3.2, 0.1, 1.2), Color("#2d3436"))
		b.glass(Vector3(sx, 1.2, sz - 0.5), Vector3(2.8, 1.8, 0.04), true)
		b.box(Vector3(sx, 0.55, sz - 0.2), Vector3(2.0, 0.07, 0.4), Color("#8b5e3c"))
		b.box(Vector3(sx + 1.8, 1.0, sz), Vector3(0.12, 2.0, 0.5), Color("#e63946"))
	b.flush(root, 140.0)


## The middle block downtown: a paved plaza with a fountain, a founder-egg statue,
## planters, a hot-dog cart, a clock tower and café tables.
static func plaza(parent: Node3D, origin: Vector3, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = origin
	parent.add_child(root)
	var size := Town.BLOCK
	_paving(root, size)
	var c := size * 0.5
	var b := Batch.new()
	# concentric paving rings
	for r in 3:
		b.cyl(Vector3(c, 0.08 + r * 0.004, c), 12.5 - r * 2.6, 0.01, Color("#e8e2d6") if r % 2 == 0 else Color("#cfc7b8"))
	# fountain
	Toon.cyl(root, 4.2, 4.4, 0.8, Vector3(c, 0.4, c), Color("#c9ced3"), 0.02, 18)
	Toon.cyl(root, 3.8, 3.8, 0.1, Vector3(c, 0.78, c), Color("#74b9ff"), 0.0, 18)
	Toon.cyl(root, 0.5, 0.7, 1.6, Vector3(c, 1.6, c), Color("#c9ced3"), 0.015, 10)
	Toon.cyl(root, 1.6, 1.2, 0.3, Vector3(c, 2.5, c), Color("#c9ced3"), 0.015, 12)
	Toon.cyl(root, 1.4, 1.4, 0.06, Vector3(c, 2.68, c), Color("#74b9ff"), 0.0, 12)
	Toon.mesh(root, Shapes.egg(1.0, 0.45), Vector3(c, 3.9, c), Color("#e8dccb"), 0.02)
	Toon.solid_box(root, Vector3(8.6, 1.0, 8.6), Vector3(c, 0.5, c))
	for k in 10:
		var a := TAU * k / 10.0
		b.ball(Vector3(c + cos(a) * 2.2, 3.0, c + sin(a) * 2.2), 0.12, Color("#bfe9ff"))
		b.ball(Vector3(c + cos(a) * 3.0, 1.6, c + sin(a) * 3.0), 0.09, Color("#bfe9ff"))
	Signs.board(root, "FOUNDER EGG", Vector3(c, 0.65, c + 4.6), Vector2(2.2, 0.5), Color("#b08d57"), Color("#2b1c18"), 0.0, "none", Color("#5a4630"))
	# clock tower in the corner
	var ct := Vector3(5.0, 0, 5.0)
	Toon.block(root, Vector3(3.0, 14.0, 3.0), ct, Color("#c9a97a"), 0.04, 0.03)
	Toon.solid_box(root, Vector3(3.0, 14.0, 3.0), ct + Vector3(0, 7.0, 0))
	Toon.block(root, Vector3(3.6, 3.4, 3.6), ct + Vector3(0, 14.0, 0), Color("#d9c39a"), 0.04, 0.03)
	Toon.cyl(root, 0.0, 2.9, 3.6, ct + Vector3(0, 19.0, 0), Color("#4d6b5a"), 0.03, 4).rotation.y = PI / 4.0
	for sd in 4:
		var face_pos := ct + Vector3(0, 15.7, 0)
		var ang := sd * PI * 0.5
		var off := Vector3(sin(ang), 0, cos(ang)) * 1.83
		var face := Toon.cyl(root, 1.2, 1.2, 0.08, face_pos + off, Color("#fff8e7"), 0.01, 20)
		face.rotation = Vector3(PI / 2, ang, 0)
		var hand := Toon.box(root, Vector3(0.1, 0.8, 0.05), face_pos + off + Vector3(sin(ang), 0, cos(ang)) * 0.07 + Vector3(0, 0.3, 0), Color("#2b1c18"), 0.0)
		hand.rotation.y = ang
	var win_h := 1.0
	for k in 4:
		b.glass(Vector3(ct.x, 3.0 + k * 2.6, ct.z + 1.53), Vector3(0.6, 1.2, 0.05), rng.randf() < 0.5)
	# hot dog cart + café patio + planters + benches
	var cart := Vector3(c + 8.5, 0, c - 8.0)
	b.box(cart + Vector3(0, 0.8, 0), Vector3(1.8, 1.0, 1.0), Color("#e63946"))
	b.box(cart + Vector3(0, 1.4, 0), Vector3(1.9, 0.1, 1.1), Color("#fff8e7"))
	for wx: float in [-0.7, 0.7]:
		b.cyl(cart + Vector3(wx, 0.3, 0.55), 0.3, 0.08, Color("#2d3436"), Vector3(0, 0, PI / 2))
	b.cyl(cart + Vector3(0, 2.0, 0), 0.03, 1.8, Color("#444a50"))
	b.cone(cart + Vector3(0, 2.7, 0), 1.4, 0.5, Color("#f6bd60"))
	for k in 5:
		var tp := Vector3(c - 9.0 + (k % 3) * 2.4, 0, c + 7.0 + (k / 3) * 2.6)
		b.cyl(tp + Vector3(0, 0.7, 0), 0.4, 0.05, Color("#fff8e7"))
		b.cyl(tp + Vector3(0, 0.35, 0), 0.04, 0.7, Color("#444a50"))
		for sd: int in [-1, 1]:
			b.box(tp + Vector3(sd * 0.6, 0.45, 0), Vector3(0.38, 0.05, 0.38), Color("#2a9d8f"))
		if k % 2 == 0:
			b.cyl(tp + Vector3(0, 1.4, 0), 0.03, 1.6, Color("#444a50"))
			b.cone(tp + Vector3(0, 2.1, 0), 1.1, 0.35, Color("#e76f51"))
	for k in 12:
		var a := TAU * k / 12.0
		var p := Vector3(c + cos(a) * 12.8, 0, c + sin(a) * 12.8)
		b.box(p + Vector3(0, 0.3, 0), Vector3(1.2, 0.6, 1.2), Color("#8a7a68"))
		b.ball(p + Vector3(0, 1.1, 0), 0.7, Color(["#52b788", "#74c69d", "#95d5b2"][k % 3]))
		if k % 2 == 0:
			var bp := Vector3(c + cos(a + 0.26) * 12.8, 0, c + sin(a + 0.26) * 12.8)
			b.box(bp + Vector3(0, 0.5, 0), Vector3(1.6, 0.08, 0.5), Color("#8b5e3c"), Vector3(0, -a, 0))
	# banners on flag poles
	for k in 4:
		var fp := Vector3(c + (k % 2 * 2 - 1) * 12.0, 0, c + (k / 2 * 2 - 1) * 12.0)
		b.cyl(fp + Vector3(0, 3.0, 0), 0.05, 6.0, Color("#cfd4d8"))
		b.box(fp + Vector3(0.6, 5.3, 0), Vector3(1.1, 0.7, 0.03), Color(["#e63946", "#2e86de", "#ffd166", "#2a9d8f"][k]))
	b.flush(root, 200.0)
	Signs.board(root, "EGG SQUARE", Vector3(c, 4.2, size - 1.2), Vector2(7.0, 1.5), Color("#2a6f77"), Color("#fff8e7"), 0.0, "posts", Color("#2b2d42"))
