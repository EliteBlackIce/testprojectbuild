class_name Pizza
extends Node3D
## A physical pizza you build by hand: a dough ball you stretch, sauce you paint
## on in splats, cheese you sprinkle, toppings you drop one by one, a bake that
## browns the crust, cuts you drag with the wheel, and a box that folds shut.
##
## All the scoring state lives in `data` so Pizza.quality() can grade it, and
## quality comes from what you actually did (coverage, spills, crooked cuts...).

const HEAT_DECAY := [0.7, 0.5, 0.33, 0.2]   ## per second, by Hot Bag level
const MAX_SPLATS := 420
const MAX_SHREDS := 520
const SPLAT_R := 0.055                       ## one sauce splat (meters)
const SHRED_R := 0.04                        ## reach of one cheese pinch
const PIECES_PER_PORTION := 4
const DOUGH_COLOR := Color("#efd9a8")
const CHEESE_COLOR := Color("#f7d56a")

var data := {
	"ticket": 0,
	"size": "medium",
	"radius": 0.12,        ## actual stretched radius (meters)
	"stretched": false,
	"dough_q": 0.0,
	"sauce": "",
	"sauce_q": 0.0,
	"cheese_q": 0.0,
	"spills": 0,           ## splats/shreds that missed the pizza
	"toppings": [],        ## one entry per portion, e.g. ["pepperoni", "pepperoni", "olive"]
	"pieces": {},          ## kind -> how many pieces were dropped
	"assembled": false,
	"bake": 0.0,           ## 0 raw, 1 perfect, 1.3+ burnt
	"baked": false,
	"cuts": 0,
	"cut_q": 0.0,
	"boxed": false,
	"heat": 0.0,           ## 0..100
	"damage": 0.0,         ## 0..100
	"made_by": "you",
}
## Where the pizza is, for heat purposes: "kitchen", "oven", "shelf", "car", "carried".
var location := "kitchen"

var _pie: Node3D
var _ball: MeshInstance3D
var _crust: MeshInstance3D
var _crust_mat: ShaderMaterial
var _sauce_mm: MultiMesh
var _sauce_mat: ShaderMaterial
var _cheese_mm: MultiMesh
var _cheese_mat: ShaderMaterial
var _toppings_root: Node3D
var _cuts_root: Node3D
var _box: Node3D
var _lid: Node3D
var _steam: Array[MeshInstance3D] = []
var _rng := RandomNumberGenerator.new()
## Coverage sample points (normalized: unit circle) and which are covered.
var _samples: PackedVector2Array = []
var _sauce_hits: PackedByteArray = []
var _cheese_hits: PackedByteArray = []
var _cut_lines: Array[PackedVector2Array] = []
var _t := 0.0


func setup(ticket_id: int) -> void:
	data.ticket = ticket_id
	_rng.seed = ticket_id * 7919 + 13 + randi() % 1000
	_build()


func radius() -> float:
	return float(data.radius)


func target_radius() -> float:
	return float(Menu.SIZES[data.size].radius)


# --- visuals --------------------------------------------------------------------------------

func _build() -> void:
	_pie = Node3D.new()
	add_child(_pie)
	# The dough ball (before stretching)
	_ball = MeshInstance3D.new()
	_ball.mesh = Shapes.blob(0.11, _rng.randi() % 9999, 0.08)
	_ball.material_override = Toon.mat(DOUGH_COLOR, 0.008)
	_ball.position.y = 0.06
	_ball.scale = Vector3(1, 0.62, 1)
	_pie.add_child(_ball)
	# The stretched crust: a unit-radius lathe with a puffy rim, scaled to size.
	_crust = MeshInstance3D.new()
	_crust.mesh = Shapes.lathe(PackedVector2Array([Vector2(0.98, 0.0), Vector2(1.02, 0.03), Vector2(0.99, 0.065), Vector2(0.92, 0.07), Vector2(0.8, 0.046), Vector2(0.0, 0.04)]), 18, 0.3)
	_crust_mat = Toon.mat(DOUGH_COLOR, 0.0).duplicate()   # no ink hull: the dish shape is concave
	_crust.material_override = _crust_mat
	_crust.visible = false
	_pie.add_child(_crust)
	# Sauce + cheese are batched splats so painting stays cheap.
	_sauce_mat = Toon.mat(Color("#c8321f"), 0.0).duplicate()
	_sauce_mm = _make_mm(Shapes.cylinder(1.0, 1.0, 0.006, 7), _sauce_mat, MAX_SPLATS)
	_cheese_mat = Toon.mat(CHEESE_COLOR, 0.0).duplicate()
	_cheese_mm = _make_mm(Shapes.box(Vector3(0.04, 0.008, 0.01)), _cheese_mat, MAX_SHREDS)
	_toppings_root = Node3D.new()
	_pie.add_child(_toppings_root)
	_cuts_root = Node3D.new()
	_pie.add_child(_cuts_root)
	_build_samples()
	for i in 3:
		var puff := MeshInstance3D.new()
		puff.mesh = Shapes.ball(0.03, 6, 4)
		puff.material_override = Toon.mat(Color(1, 1, 1), 0.0)
		puff.visible = false
		add_child(puff)
		_steam.append(puff)


func _make_mm(m: Mesh, material: Material, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	_pie.add_child(mmi)
	return mm


func _build_samples() -> void:
	_samples.append(Vector2.ZERO)
	var rings := [[0.18, 6], [0.36, 12], [0.54, 18], [0.7, 24], [0.84, 30]]
	for ring in rings:
		for k in int(ring[1]):
			var a := TAU * k / float(ring[1]) + float(ring[0]) * 3.0
			_samples.append(Vector2(cos(a), sin(a)) * float(ring[0]))
	_sauce_hits.resize(_samples.size())
	_cheese_hits.resize(_samples.size())


# --- 1. stretch ------------------------------------------------------------------------------

## Live preview while you pull the dough (r in meters).
func set_stretch(r: float) -> void:
	data.radius = clampf(r, 0.1, 0.62)
	var t := clampf((radius() - 0.1) / 0.12, 0.0, 1.0)
	_ball.visible = t < 0.9
	_ball.scale = Vector3(1.0 + t * 2.0, 0.62 * (1.0 - t * 0.85), 1.0 + t * 2.0)
	_crust.visible = t > 0.4
	_crust.scale = Vector3(radius(), 1.0 + (1.0 - t) * 0.8, radius())


## Locks in the size. `wanted` is the size on the ticket.
func finish_stretch(wanted: String) -> void:
	var best := "medium"
	var best_d := INF
	for s: String in Menu.SIZE_ORDER:
		var d := absf(float(Menu.SIZES[s].radius) - radius())
		if d < best_d:
			best_d = d
			best = s
	data.size = best
	var want_r := float(Menu.SIZES[wanted].radius)
	var tolerance := 0.09 + Game.level("dough_press") * 0.035   # Dough Press upgrade: easier sweet spot
	data.dough_q = clampf(1.0 - absf(radius() - want_r) / tolerance, 0.0, 1.0)
	data.stretched = true
	_ball.visible = false
	_crust.visible = true
	_crust.scale = Vector3(radius(), 1.0, radius())


## Way too thin: it tears. Comedy, then you start over.
func is_torn() -> bool:
	return radius() > 0.58


# --- 2. sauce + 3. cheese ----------------------------------------------------------------------

## `local` is a point on the pizza (meters, in the pizza's XZ plane).
## Returns false if nothing was added (out of sauce budget).
func paint_sauce(local: Vector2, kind: String) -> bool:
	if _sauce_mm.visible_instance_count >= MAX_SPLATS or not data.stretched:
		return false
	if data.sauce != kind:
		data.sauce = kind
		_sauce_mat.set_shader_parameter("albedo", Color(Menu.SAUCES[kind].color))
	var jitter := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.012
	var p := local + jitter
	var s := SPLAT_R * _rng.randf_range(0.75, 1.15) * (1.0 + Game.level("sauce_gun") * 0.3)   # Sauce Gun: bigger splats
	var i := _sauce_mm.visible_instance_count
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, 1.0, s * _rng.randf_range(0.75, 1.0)))
	var y := 0.046 + i * 0.000004
	if p.length() > radius() * 0.98:
		data.spills += 1
		y = -0.004   # it slopped off onto the board
	_sauce_mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, y, p.y)))
	_sauce_mm.visible_instance_count = i + 1
	_mark(_sauce_hits, p, s * 1.25)
	return true


func sprinkle_cheese(local: Vector2) -> bool:
	if _cheese_mm.visible_instance_count >= MAX_SHREDS - 12 or not data.stretched:
		return false
	for k in 4 + Game.level("sauce_gun") * 2:
		var p := local + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * SHRED_R
		var i := _cheese_mm.visible_instance_count
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3))
		var y := 0.052 + _rng.randf() * 0.006
		if p.length() > radius() * 0.98:
			data.spills += 1
			y = -0.002
		_cheese_mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, y, p.y)))
		_cheese_mm.visible_instance_count = i + 1
	_mark(_cheese_hits, local, SHRED_R * (1.5 + Game.level("sauce_gun") * 0.3))
	return true


func _mark(hits: PackedByteArray, p: Vector2, reach: float) -> void:
	var r := radius()
	for k in _samples.size():
		if hits[k] == 0 and (_samples[k] * r).distance_to(p) < reach:
			hits[k] = 1


func coverage(which: String) -> float:
	var hits := _sauce_hits if which == "sauce" else _cheese_hits
	var n := 0
	for h in hits:
		n += h
	return float(n) / float(hits.size())


func has_sauce() -> bool:
	return _sauce_mm.visible_instance_count > 0


func has_cheese() -> bool:
	return _cheese_mm.visible_instance_count > 0


# --- 4. toppings ------------------------------------------------------------------------------------

func place_topping(kind: String, local: Vector2) -> void:
	var info: Dictionary = Menu.TOPPINGS[kind]
	var col := Color(info.color)
	var p := Vector3(local.x, 0.062, local.y)
	var piece: MeshInstance3D
	match info.kind:
		"disc":
			piece = Toon.cyl(_toppings_root, 0.042, 0.042, 0.012, p, col, 0.004, 8)
		"ring":
			piece = Toon.cyl(_toppings_root, 0.03, 0.03, 0.012, p, col, 0.0, 7)
			Toon.cyl(piece, 0.015, 0.015, 0.014, Vector3.ZERO, CHEESE_COLOR, 0.0, 5)
		"strip":
			piece = Toon.box(_toppings_root, Vector3(0.08, 0.012, 0.02), p, col, 0.0)
		"dome":
			piece = Toon.ball(_toppings_root, 0.03, p, col, 0.004, 6)
			piece.scale = Vector3(1.2, 0.55, 1.2)
		"square":
			piece = Toon.box(_toppings_root, Vector3(0.05, 0.012, 0.05), p, col, 0.0)
		"blob":
			piece = Toon.ball(_toppings_root, 0.026, p, col, 0.004, 5)
		_:
			piece = Toon.box(_toppings_root, Vector3(0.036, 0.03, 0.036), p, col, 0.004)
	piece.rotation.y = _rng.randf() * TAU
	if local.length() > radius() * 0.98:
		piece.position.y = 0.0
		data.spills += 1
	var pieces: Dictionary = data.pieces
	pieces[kind] = int(pieces.get(kind, 0)) + 1
	# Drop-in squash so it feels like it landed.
	piece.scale *= Vector3(1.4, 0.4, 1.4)
	var tw := piece.create_tween()
	tw.tween_property(piece, "scale", piece.scale / Vector3(1.4, 0.4, 1.4), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Pieces of each topping, e.g. {"pepperoni": 6}.
func piece_counts() -> Dictionary:
	return data.pieces


## Called when you hit Done at the prep table: turns what you did into scores.
func finish_assembly() -> void:
	var spill_pen := float(data.spills) * 0.012
	data.sauce_q = clampf(coverage("sauce") / 0.8, 0.0, 1.0) - spill_pen if has_sauce() else 0.0
	data.cheese_q = clampf(coverage("cheese") / 0.7, 0.0, 1.0) - spill_pen if has_cheese() else 0.0
	data.sauce_q = clampf(float(data.sauce_q), 0.0, 1.0)
	data.cheese_q = clampf(float(data.cheese_q), 0.0, 1.0)
	var tops: Array = []
	for kind: String in data.pieces:
		var n: int = data.pieces[kind]
		if n >= 2:
			for k in maxi(1, n / PIECES_PER_PORTION):
				tops.append(kind)
	data.toppings = tops
	data.assembled = true


# --- 5. bake -----------------------------------------------------------------------------------------

func set_bake(amount: float) -> void:
	data.bake = amount
	var b := clampf(amount, 0.0, 2.0)
	var crust := DOUGH_COLOR.lerp(Color("#cf8a3a"), clampf(b, 0.0, 1.0))
	var cheese := CHEESE_COLOR.lerp(Color("#f0b43c"), clampf(b, 0.0, 1.0))
	if b > 1.15:
		var burn := clampf((b - 1.15) * 3.0, 0.0, 1.0)
		crust = crust.lerp(Color("#2a1a12"), burn)
		cheese = cheese.lerp(Color("#3b2414"), burn * 0.85)
	_crust_mat.set_shader_parameter("albedo", crust)
	_cheese_mat.set_shader_parameter("albedo", cheese)
	if data.sauce != "":
		var sc := Color(Menu.SAUCES[data.sauce].color)
		_sauce_mat.set_shader_parameter("albedo", sc.darkened(clampf(b - 0.3, 0.0, 1.0) * 0.35))


# --- 6. cut -------------------------------------------------------------------------------------------

## A wheel stroke from a to b (pizza-local meters). Only the part over the pizza counts.
func add_cut(a: Vector2, b: Vector2) -> bool:
	var dir := b - a
	if dir.length() < radius() * 0.6:
		return false
	dir = dir.normalized()
	# Closest point to center + chord through the circle.
	var closest := a + dir * (-a).dot(dir)
	var d := closest.length()
	var r := radius()
	if d >= r * 0.95:
		return false
	var half := sqrt(r * r - d * d)
	var p0 := closest - dir * half
	var p1 := closest + dir * half
	_cut_lines.append(PackedVector2Array([p0, p1]))
	data.cuts = _cut_lines.size()
	var mid := (p0 + p1) * 0.5
	var line := Toon.box(_cuts_root, Vector3(half * 2.0, 0.012, 0.012), Vector3(mid.x, 0.07, mid.y), Color("#7a3b1c"), 0.0)
	line.rotation.y = -atan2(dir.y, dir.x)
	return true


## 4 straight cuts through the middle at even angles = 8 perfect slices.
func finish_cuts() -> void:
	if _cut_lines.is_empty():
		data.cut_q = 0.0
		return
	var r := radius()
	var centered := 0.0
	var angles: Array[float] = []
	for l in _cut_lines:
		var mid := (l[0] + l[1]) * 0.5
		centered += 1.0 - clampf(mid.length() / (r * 0.4), 0.0, 1.0)
		angles.append(fposmod(atan2(l[1].y - l[0].y, l[1].x - l[0].x), PI))
	centered /= float(_cut_lines.size())
	angles.sort()
	var n := angles.size()
	var even := 1.0
	if n > 1:
		var ideal := PI / n
		var err := 0.0
		for k in n:
			var gap := (angles[(k + 1) % n] + (PI if k == n - 1 else 0.0)) - angles[k]
			err += absf(gap - ideal) / ideal
		even = clampf(1.0 - err / n, 0.0, 1.0)
	var count_score := clampf(1.0 - absf(n - 4) * 0.25, 0.0, 1.0)
	data.cut_q = clampf(centered * 0.45 + even * 0.3 + count_score * 0.25, 0.0, 1.0)


# --- 7. box ------------------------------------------------------------------------------------------------

## Folds a box around the pizza. Animated unless `instant`.
func put_in_box(instant := false) -> void:
	if data.boxed:
		return
	data.boxed = true
	var side := float(Menu.SIZES[data.size].radius) * 2.3
	_box = Node3D.new()
	add_child(_box)
	Toon.block(_box, Vector3(side, 0.09, side), Vector3(0, -0.01, 0), Color("#d9b98c"), 0.02, 0.01)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.08, -side * 0.5)
	_box.add_child(_lid)
	var lid_body := Node3D.new()
	lid_body.position = Vector3(0, 0, side * 0.5)
	_lid.add_child(lid_body)
	Toon.block(lid_body, Vector3(side, 0.035, side), Vector3(0, 0, 0), Color("#e2c497"), 0.015, 0.01)
	# Lid print: Tony's logo ring with a chef egg doodle + ticket number
	Toon.cyl(lid_body, side * 0.33, side * 0.33, 0.004, Vector3(0, 0.037, 0), Color("#c0392b"), 0.0, 16)
	Toon.cyl(lid_body, side * 0.27, side * 0.27, 0.006, Vector3(0, 0.038, 0), Color("#f6efe2"), 0.0, 16)
	var egg := Toon.mesh(lid_body, Shapes.body_egg(0.16, 0.06, 0.02, 10, 7), Vector3(0, 0.04, 0.05), Color("#f2c9a0"), 0.0)
	egg.rotation.x = -PI / 2
	egg.scale = Vector3(1, 1, 0.25)
	Toon.box(lid_body, Vector3(0.12, 0.004, 0.035), Vector3(0, 0.043, -0.09), Color("#f6f4ef"), 0.0)
	var tag := Toon.label(lid_body, "TONY'S  #%d" % data.ticket, Vector3(0, 0.042, side * 0.4), 34, Color("#c0392b"), false)
	tag.rotation.x = -PI / 2
	tag.outline_size = 0
	for k in 5:
		Toon.box(_box, Vector3(side * 0.1, 0.04, 0.006), Vector3(-side * 0.4 + k * side * 0.2, 0.03, side * 0.5 + 0.003), Color("#c0392b"), 0.0)
	if instant:
		_pie.visible = false
		return
	_lid.rotation.x = -1.9
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", 0.15, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_lid, "rotation:x", 0.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_hide_pie)
	tw.parallel().tween_property(_box, "scale", Vector3(1.08, 0.8, 1.08), 0.06)
	tw.tween_property(_box, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _hide_pie() -> void:
	_pie.visible = false


func is_boxed() -> bool:
	return data.boxed


## Rough footprint for stacking/holding.
func footprint() -> float:
	return (float(Menu.SIZES[data.size].radius) * 2.3) if data.boxed else radius() * 2.0


# --- heat --------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	var hot: bool = data.baked and not data.boxed and float(data.heat) > 45.0 and location != "oven"
	for k in _steam.size():
		var puff := _steam[k]
		puff.visible = hot
		if hot:
			var ph := fmod(_t * 0.6 + k / 3.0, 1.0)
			puff.position = Vector3(sin(k * 2.1 + _t) * 0.08, 0.12 + ph * 0.45 + (0.09 if data.boxed else 0.0), cos(k * 1.7) * 0.08)
			puff.scale = Vector3.ONE * (0.4 + ph) * (1.0 - ph)
	if not data.baked or location == "oven":
		return
	var decay := 0.0
	match location:
		"shelf":
			decay = 0.0 if Game.has_upgrade("heat_lamp") else HEAT_DECAY[0] * 0.5
		"car":
			decay = HEAT_DECAY[Game.level("hot_bag")]
		_:
			decay = HEAT_DECAY[0]
	if data.boxed:
		decay *= 0.7
	if not Game.in_dialogue:
		data.heat = maxf(0.0, data.heat - decay * delta)


# --- workers + tests: build a pizza without hands ------------------------------------------------------------

## Makes the whole raw pizza instantly to a given skill (0..1). Used by hired cooks
## (who animate around it) and the automated tests.
func auto_assemble(order: Dictionary, skill: float) -> void:
	var want_r := float(Menu.SIZES[order.get("size", "medium")].radius)
	set_stretch(want_r + _rng.randf_range(-1, 1) * 0.08 * (1.0 - skill))
	finish_stretch(order.get("size", "medium"))
	var sauce: String = order.get("sauce", "tomato")
	var n := int(lerpf(30.0, 110.0, skill))
	for k in n:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * radius() * lerpf(1.05, 0.86, skill)
		paint_sauce(Vector2(cos(a), sin(a)) * d, sauce)
	for k in int(lerpf(25.0, 70.0, skill)):
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * radius() * lerpf(1.0, 0.82, skill)
		sprinkle_cheese(Vector2(cos(a), sin(a)) * d)
	for t: String in order.get("toppings", []):
		for k in PIECES_PER_PORTION + 1:
			var a := _rng.randf() * TAU
			var d := sqrt(_rng.randf()) * radius() * 0.75
			place_topping(t, Vector2(cos(a), sin(a)) * d)
	finish_assembly()


func auto_cut(skill: float) -> void:
	var base := _rng.randf() * PI
	for k in 4:
		var a := base + k * PI / 4.0 + _rng.randf_range(-0.35, 0.35) * (1.0 - skill)
		var off := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * radius() * 0.3 * (1.0 - skill)
		var dir := Vector2(cos(a), sin(a)) * radius() * 1.3
		add_cut(off - dir, off + dir)
	finish_cuts()


# --- scoring ------------------------------------------------------------------------------------------------

## Scores a pizza against its order. Every part is 0..1.
static func quality(p: Dictionary, order: Dictionary) -> Dictionary:
	var match_score := 1.0
	if p.get("size", "") != order.get("size", ""):
		match_score -= 0.3
	if p.get("sauce", "") != order.get("sauce", "tomato"):
		match_score -= 0.25 if p.get("sauce", "") != "" else 0.4
	var want: Array = order.get("toppings", [])
	var have: Array = p.get("toppings", [])
	for t in want:
		if t not in have:
			match_score -= 0.2
	var extras := 0
	for t in have:
		if t not in want:
			extras += 1
	match_score -= 0.08 * extras
	match_score = clampf(match_score, 0.0, 1.0)
	var bake_score := clampf(1.0 - absf(float(p.get("bake", 0.0)) - 1.0) * 2.5, 0.0, 1.0)
	var heat_score := clampf(float(p.get("heat", 0.0)) / 100.0, 0.0, 1.0)
	var damage_score := clampf(1.0 - float(p.get("damage", 0.0)) / 100.0, 0.0, 1.0)
	var prep := (float(p.get("dough_q", 0.0)) + float(p.get("sauce_q", 0.0)) + float(p.get("cheese_q", 0.0)) + float(p.get("cut_q", 0.0))) / 4.0
	var total := match_score * 0.35 + bake_score * 0.2 + heat_score * 0.15 + damage_score * 0.15 + prep * 0.15
	return {"match": match_score, "bake": bake_score, "heat": heat_score, "damage": damage_score, "prep": prep, "total": total}


## Words the AI (and the summary screen) use to describe a pizza.
static func describe_condition(p: Dictionary) -> String:
	var bits: PackedStringArray = []
	var bake := float(p.get("bake", 0.0))
	if bake < 0.75:
		bits.append("undercooked and doughy")
	elif bake > 1.3:
		bits.append("BURNT")
	elif absf(bake - 1.0) < 0.12:
		bits.append("baked perfectly")
	if float(p.get("sauce_q", 1.0)) < 0.35:
		bits.append("barely any sauce")
	if float(p.get("cheese_q", 1.0)) < 0.35:
		bits.append("weirdly bald (almost no cheese)")
	if int(p.get("cuts", 4)) == 0:
		bits.append("not even cut")
	elif float(p.get("cut_q", 1.0)) < 0.4:
		bits.append("cut into chaotic jagged slices")
	var heat := float(p.get("heat", 0.0))
	if heat > 75.0:
		bits.append("piping hot")
	elif heat > 40.0:
		bits.append("warm")
	elif heat > 15.0:
		bits.append("lukewarm")
	else:
		bits.append("COLD")
	var dmg := float(p.get("damage", 0.0))
	if dmg > 60.0:
		bits.append("completely smushed into a cube")
	elif dmg > 25.0:
		bits.append("a bit smushed from car crashes")
	return ", ".join(bits)
