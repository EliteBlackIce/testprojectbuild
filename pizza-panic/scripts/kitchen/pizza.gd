class_name Pizza
extends Node3D
## A physical pizza: starts as dough, gets sauce, cheese and toppings, bakes,
## gets boxed, rides in the car, and ends up with an egg.
##
## All the state lives in `data` so it can be scored by Pizza.quality().

const HEAT_DECAY := [0.7, 0.5, 0.33, 0.2]   ## per second, by Hot Bag level

var data := {
	"ticket": 0,
	"size": "medium",
	"dough_q": 1.0,
	"sauce": "",
	"sauce_q": 0.0,
	"cheese_q": 0.0,
	"toppings": [],        ## one entry per portion, e.g. ["pepperoni", "pepperoni", "olive"]
	"bake": 0.0,           ## 0 raw, 1 perfect, 1.3+ burnt
	"baked": false,
	"cut_q": 0.0,
	"boxed": false,
	"heat": 0.0,           ## 0..100
	"damage": 0.0,         ## 0..100
}
## Where the pizza is, for heat purposes: "kitchen", "oven", "shelf", "car", "carried".
var location := "kitchen"

var _pie: Node3D
var _box: Node3D
var _crust: MeshInstance3D
var _sauce: MeshInstance3D
var _cheese: MeshInstance3D
var _toppings_root: Node3D
var _rng := RandomNumberGenerator.new()


func setup(ticket_id: int, size: String, dough_quality: float) -> void:
	data.ticket = ticket_id
	data.size = size
	data.dough_q = dough_quality
	_rng.seed = ticket_id * 7919 + 13
	_build_pie()


func radius() -> float:
	return float(Menu.SIZES[data.size].radius)


func _build_pie() -> void:
	_pie = Node3D.new()
	add_child(_pie)
	var r := radius()
	_crust = Toon.cyl(_pie, r, r * 1.02, 0.06, Vector3(0, 0.03, 0), Color("#e9cf9b"), 0.006, 12)
	_toppings_root = Node3D.new()
	_pie.add_child(_toppings_root)


func add_sauce(kind: String, q: float) -> void:
	data.sauce = kind
	data.sauce_q = q
	if _sauce:
		_sauce.queue_free()
	var r := radius() * lerpf(0.6, 0.9, clampf(q, 0.0, 1.0))
	_sauce = Toon.cyl(_pie, r, r, 0.012, Vector3(0, 0.066, 0), Color(Menu.SAUCES[kind].color), 0.0, 12)
	_refresh_bake_color()


func add_cheese(q: float) -> void:
	data.cheese_q = q
	if _cheese:
		_cheese.queue_free()
	var r := radius() * lerpf(0.55, 0.88, clampf(q, 0.0, 1.0))
	_cheese = Toon.cyl(_pie, r, r * 1.02, 0.014, Vector3(0, 0.077, 0), Color("#f6dc8a"), 0.0, 9)
	_cheese.rotation.y = 0.3
	_refresh_bake_color()


## One portion = a handful of pieces scattered on top.
func add_topping(kind: String) -> void:
	data.toppings.append(kind)
	var info: Dictionary = Menu.TOPPINGS[kind]
	var col := Color(info.color)
	var r := radius() * 0.78
	for i in 5:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * r
		var p := Vector3(cos(a) * d, 0.09, sin(a) * d)
		var piece: MeshInstance3D
		match info.kind:
			"disc":
				piece = Toon.cyl(_toppings_root, 0.045, 0.045, 0.012, p, col, 0.0, 7)
			"ring":
				piece = Toon.cyl(_toppings_root, 0.03, 0.03, 0.012, p, col, 0.0, 6)
				Toon.cyl(piece, 0.014, 0.014, 0.014, Vector3.ZERO, Color("#f6dc8a"), 0.0, 5)
			"strip":
				piece = Toon.box(_toppings_root, Vector3(0.08, 0.012, 0.018), p, col, 0.0)
			"dome":
				piece = Toon.ball(_toppings_root, 0.03, p, col, 0.0, 6)
				piece.scale = Vector3(1.2, 0.5, 1.2)
			"square":
				piece = Toon.box(_toppings_root, Vector3(0.05, 0.012, 0.05), p, col, 0.0)
			"blob":
				piece = Toon.ball(_toppings_root, 0.028, p, col, 0.0, 5)
			_:
				piece = Toon.box(_toppings_root, Vector3(0.04, 0.03, 0.04), p, col, 0.0)
		piece.rotation.y = _rng.randf() * TAU


func set_bake(amount: float) -> void:
	data.bake = amount
	_refresh_bake_color()


func _refresh_bake_color() -> void:
	var b := float(data.bake)
	var crust := Color("#e9cf9b")
	if b > 0.0:
		crust = crust.lerp(Color("#c98b3f"), clampf(b, 0.0, 1.0))
	if b > 1.25:
		crust = crust.lerp(Color("#2a1a12"), clampf((b - 1.25) * 2.5, 0.0, 1.0))
	_crust.material_override = Toon.mat(crust, 0.006)
	if _cheese:
		var ch := Color("#f6dc8a").lerp(Color("#f2c14e"), clampf(b, 0.0, 1.0))
		if b > 1.25:
			ch = ch.lerp(Color("#3b2414"), clampf((b - 1.25) * 2.0, 0.0, 1.0))
		_cheese.material_override = Toon.mat(ch, 0.0)


func put_in_box(cut_quality: float) -> void:
	data.cut_q = cut_quality
	data.boxed = true
	_pie.visible = false
	_box = Node3D.new()
	add_child(_box)
	var r := radius()
	var size := Vector3(r * 2.25, 0.12, r * 2.25)
	Toon.block(_box, size, Vector3.ZERO, Color("#d9b98c"), 0.04, 0.012)
	# Lid print: red ring + pizza logo, checkered side band.
	Toon.cyl(_box, r * 0.75, r * 0.75, 0.004, Vector3(0, 0.123, 0), Color("#c0392b"), 0.0, 14)
	Toon.cyl(_box, r * 0.62, r * 0.62, 0.006, Vector3(0, 0.124, 0), Color("#d9b98c"), 0.0, 14)
	for i in 6:
		var a := TAU * i / 6.0
		Toon.cyl(_box, r * 0.1, r * 0.1, 0.008, Vector3(cos(a) * r * 0.35, 0.126, sin(a) * r * 0.35), Color("#c0392b"), 0.0, 6)
	for i in 4:
		Toon.box(_box, Vector3(r * 0.2, 0.05, 0.01), Vector3(-r * 1.0 + r * 0.25 + i * r * 0.5, 0.05, size.z * 0.5 + 0.003), Color("#c0392b"), 0.0)
	var tag := Toon.label(_box, "#%d" % data.ticket, Vector3(0, 0.13, size.z * 0.35), 48, Color("#2b1c18"), false)
	tag.rotation.x = -PI / 2
	tag.outline_size = 0


func is_boxed() -> bool:
	return data.boxed


func _process(delta: float) -> void:
	if not data.baked or location == "oven":
		return
	var decay := 0.0
	match location:
		"shelf":
			decay = 0.0 if Game.has_upgrade("heat_lamp") else HEAT_DECAY[0]
		"car":
			decay = HEAT_DECAY[Game.level("hot_bag")]
		_:
			decay = HEAT_DECAY[0]
	if not Game.in_dialogue:
		data.heat = maxf(0.0, data.heat - decay * delta)


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
