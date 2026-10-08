class_name Worker
extends Node3D
## A hired egg. Cooks walk the kitchen and make whole pizzas with the same
## hands-on steps you do (stretch, sauce, cheese, toppings, oven, cut, box)
## just automatically, and a little worse or better depending on skill.
## Phone eggs stand by the phone and take orders.
## Everyone has a quirk (naps, drops sauce, eats toppings, runs into walls...).

signal arrived

## Walkable spots in the kitchen (pizzeria-local) and how they connect.
const NODES := [
	Vector3(-8.2, 0, -2.2), Vector3(-4.5, 0, -2.2), Vector3(-1.2, 0, -2.2),      # 0-2 front aisle
	Vector3(-8.2, 0, -6.3), Vector3(-4.5, 0, -6.3), Vector3(-1.2, 0, -6.3),      # 3-5 back aisle
	Vector3(-9.3, 0, -2.6),                                                      # 6 dough rack
	Vector3(-5.6, 0, -6.7), Vector3(-2.1, 0, -6.7),                              # 7-8 ovens
	Vector3(2.4, 0, -2.75),                                                      # 9 cut island (front)
	Vector3(1.5, 0, 0.25),                                                       # 10 pass window (kitchen side)
	Vector3(-6.0, 0, -2.45), Vector3(-3.0, 0, -2.45),                            # 11-12 cook boards
	Vector3(1.0, 0, -2.2),                                                       # 13 front aisle east
	Vector3(3.4, 0, 0.2),                                                        # 14 phone spot
]
const EDGES := [[0, 1], [1, 2], [2, 13], [13, 9], [13, 10], [0, 6], [0, 3], [3, 4], [4, 5], [5, 2],
	[4, 7], [5, 8], [4, 8], [3, 7], [1, 11], [0, 11], [1, 12], [2, 12], [13, 14], [10, 14]]
const BOARDS := [Vector3(-6.0, 0.96, -3.4), Vector3(-3.0, 0.96, -3.4)]
const BOARD_NODES := [11, 12]
const COOK_CUT := Vector3(2.75, 1.24, -3.75)   # on top of the flat box stack

var id := ""
var info: Dictionary = {}
var skill := 0.6
var kitchen: Kitchen
var phone: PhoneLine
var board_slot := 0
var body: EggBody
var carried: Pizza
var _alive := true
var state := ""            ## what they're doing (debug + staff board)
var _path: Array[Vector3] = []
var _walk_speed := 1.9
var _zzz: Label3D
var _rng := RandomNumberGenerator.new()


func setup(worker_id: String, k: Kitchen, ph: PhoneLine, slot: int) -> void:
	id = worker_id
	info = StaffData.CANDIDATES[id]
	skill = Game.staff_skill(id)
	kitchen = k
	phone = ph
	board_slot = slot
	_rng.randomize()
	if info.quirk == "fast":
		_walk_speed = 3.1
	elif info.quirk == "perfect":
		_walk_speed = 1.4
	body = EggBody.new()
	add_child(body)
	body.build(info.look)
	body.set_meta("on_poked", _poked)
	body.set_meta("on_bonk", _bonked)
	_zzz = Toon.label(self, "", Vector3(0, 2.0, 0), 40, Color("#a29bfe"))
	var name_tag := Toon.label(self, info.name, Vector3(0, 1.85, 0), 22, Color("#ffeaa7"))
	name_tag.pixel_size = 0.006
	if info.role == "cook":
		_cook_loop()
	else:
		_phone_loop()


func quit() -> void:
	_alive = false
	if carried and is_instance_valid(carried):
		var t := Game.ticket(carried.data.ticket)
		if not t.is_empty() and t.status not in ["delivered", "failed", "ready"]:
			Game.set_ticket_status(carried.data.ticket, "new")
		carried.queue_free()
	queue_free()


func _poked() -> void:
	var lines := {
		"naps": "LARRY: ...five more minutes...",
		"drops": "CARLA: AH! Don't startle me, I'm holding sauce!",
		"snacks": "STEVE: I wasn't eating anything. *chewing*",
		"fast": "GONZALEGG: NO TIME TO TALK",
		"perfect": "NONNA: In my day we didn't poke.",
		"polite": "PAM: How may I direct your poke?",
		"rude": "BARRY: Touch me again and I'm telling Gary.",
	}
	Game.say_toast(lines.get(info.quirk, "Hey!"), UiTheme.YELLOW)


# --- moving -----------------------------------------------------------------------------------

var _stun := 0.0
var _slide := Vector3.ZERO


## Hit by something thrown: sprawl, skid a little, and lie there confused.
func _bonked(dir: Vector3, strength: float) -> void:
	body.tumble(dir, strength)
	_stun = 1.8 + strength
	var local := get_parent_node_3d().global_basis.inverse() * dir
	_slide = Vector3(local.x, 0, local.z).normalized() * 3.5 * strength
	Game.say_toast("%s: \"%s\"" % [info.name.split(" ")[0], ["ow.", "WHY.", "I felt that in my yolk.", "that's coming out of your tip jar"].pick_random()], Color("#ff9f1c"))


func _process(delta: float) -> void:
	if _stun > 0.0:
		_stun -= delta
		position += _slide * delta
		_slide = _slide.move_toward(Vector3.ZERO, 6.0 * delta)
		body.velocity_hint = Vector3.ZERO
		return
	if Game.in_dialogue:
		body.velocity_hint = Vector3.ZERO
		return
	if _path.is_empty():
		body.velocity_hint = Vector3.ZERO
		return
	var target := _path[0]
	var to := target - position
	to.y = 0.0
	var step := _walk_speed * delta
	if to.length() <= step:
		position = Vector3(target.x, 0, target.z)
		_path.pop_front()
		if _path.is_empty():
			body.velocity_hint = Vector3.ZERO
			arrived.emit()
		return
	var dir := to.normalized()
	position += dir * step
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-10.0 * delta))
	body.velocity_hint = get_parent_node_3d().global_basis * (dir * _walk_speed)


func _walk_to_node(target_node: int) -> void:
	_path = _route(position, target_node)
	if _path.is_empty():
		return
	await arrived
	# Speedy sometimes eats a wall.
	if info.quirk == "fast" and _rng.randf() < 0.12 and _alive:
		body.tumble(Vector3(sin(rotation.y), 0, cos(rotation.y)), 0.8)
		Sfx.play("bonk", 1.3, -8.0)
		await _wait(2.2)


func _face(local_point: Vector3) -> void:
	var to := local_point - position
	rotation.y = atan2(to.x, to.z)


static func _nearest(p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in NODES.size():
		var d := p.distance_to(NODES[i])
		if d < best_d:
			best_d = d
			best = i
	return best


## Dijkstra over the little kitchen graph.
static func _route(from: Vector3, target_node: int) -> Array[Vector3]:
	var start := _nearest(from)
	var dist := {}
	var prev := {}
	var open: Array[int] = []
	for i in NODES.size():
		dist[i] = INF
		open.append(i)
	dist[start] = 0.0
	while not open.is_empty():
		var u := open[0]
		for n in open:
			if dist[n] < dist[u]:
				u = n
		open.erase(u)
		if u == target_node:
			break
		for e in EDGES:
			var v := -1
			if e[0] == u:
				v = e[1]
			elif e[1] == u:
				v = e[0]
			if v < 0 or v not in open:
				continue
			var alt: float = dist[u] + (NODES[u] as Vector3).distance_to(NODES[v])
			if alt < dist[v]:
				dist[v] = alt
				prev[v] = u
	var out: Array[Vector3] = []
	var cur := target_node
	while cur != start and prev.has(cur):
		out.push_front(NODES[cur])
		cur = prev[cur]
	if start == target_node or out.is_empty():
		out.append(NODES[target_node])
	elif from.distance_to(NODES[start]) > 0.3:
		out.push_front(NODES[start])
	return out


## Waits real seconds, frozen while paused or talking.
func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and _alive and is_inside_tree():
		await get_tree().process_frame
		if not get_tree().paused and not Game.in_dialogue:
			left -= get_process_delta_time()


func _speed_mult() -> float:
	match str(info.quirk):
		"fast":
			return 0.6
		"perfect":
			return 1.35
	return 1.0


# --- cooking ----------------------------------------------------------------------------------------

func _cook_loop() -> void:
	await _wait(0.5)
	while _alive:
		if not Game.day_running:
			await _wait(1.0)
			continue
		var t := _claim()
		if t.is_empty():
			await _loiter()
			continue
		await _make(t)


func _claim() -> Dictionary:
	for t in Game.open_tickets():
		if t.status == "new":
			Game.set_ticket_status(t.id, "making")
			return t
	return {}


func _loiter() -> void:
	if _rng.randf() < 0.3:
		await _walk_to_node([1, 2, 4, 13][_rng.randi() % 4])
	if not _alive:
		return
	if info.quirk == "naps" and _rng.randf() < 0.5:
		await _nap(5.0)
	else:
		body.play(["look_around", "tap_foot", "scratch", "yawn", "dance"][_rng.randi() % 5])
		await _wait(_rng.randf_range(2.0, 4.0))


func _nap(seconds: float) -> void:
	body.play("yawn")
	await _wait(1.0)
	_zzz.text = "Z z z"
	body.express("sad", seconds)
	await _wait(seconds)
	_zzz.text = ""


func _ticket_alive(tid: int) -> bool:
	var t := Game.ticket(tid)
	return not t.is_empty() and t.status not in ["delivered", "failed"]


func _make(t: Dictionary) -> void:
	var tid: int = t.id
	var order: Dictionary = t.order
	var m := _speed_mult()
	# 1. dough
	state = "dough"
	await _walk_to_node(6)
	if not _alive:
		return
	_face(NODES[6] + Vector3(-1, 0, 0))
	body.play("work")
	await _wait(0.8 * m)
	var cost := int(ceil(Menu.price_of(order) * Menu.INGREDIENT_COST))
	Game.spend(mini(cost, Game.money), "ingredients")
	carried = kitchen.new_dough(tid)
	_carry(carried)
	# 2. make it at my board
	state = "board"
	await _walk_to_node(BOARD_NODES[board_slot])
	if not _alive:
		return
	var board := BOARDS[board_slot] as Vector3
	_face(board)
	var p := carried
	_set_down(p, board)
	await _assemble(p, order, m)
	if not _alive or not _ticket_alive(tid):
		_drop_task(p)
		return
	_carry(p)
	# 3. oven (wait for a free one)
	state = "oven"
	var oven := kitchen.free_oven()
	while oven < 0 and _alive:
		await _walk_to_node(4)
		body.play("tap_foot")
		await _wait(1.5)
		oven = kitchen.free_oven()
	if not _alive:
		return
	await _walk_to_node(7 if oven == 0 else 8)
	if not _alive:
		return
	if kitchen.ovens[oven].pizza != null:
		oven = kitchen.free_oven()
		if oven < 0:
			_drop_task(p)
			return
	_face(Pizzeria.ANCHORS["oven%d" % (oven + 1)])
	body.play("work")
	carried = null
	body.carrying = false
	kitchen.put_in_oven(p, oven)
	state = "baking"
	var target_bake := 1.0 + _rng.randf_range(-0.25, 0.3) * (1.0 - skill)
	var napping: bool = info.quirk == "naps" and _rng.randf() < 0.3
	if napping:
		_zzz.text = "Z z z"
	while _alive and kitchen.ovens[oven].pizza == p and float(p.data.bake) < target_bake + (0.25 if napping else 0.0):
		await _wait(0.2)
	_zzz.text = ""
	if not _alive or kitchen.ovens[oven].pizza != p:
		return   # someone (you) took it out
	if napping:
		Game.say_toast("Larry fell asleep at the oven...", Color("#ff9f1c"))
	kitchen.take_from_oven(oven)
	carried = p
	_carry(p)
	# 4. cut + box
	state = "cut"
	await _walk_to_node(9)
	if not _alive:
		return
	_face(COOK_CUT)
	_set_down(p, COOK_CUT)
	for k in 4:
		body.play("slam")
		await _wait(0.45 * m)
	p.auto_cut(skill)
	Sfx.play("chop", 1.0, -10.0)
	await _wait(0.3)
	p.put_in_box()
	Game.set_ticket_status(tid, "ready")
	await _wait(0.6)
	_carry(p)
	# 5. pass shelf
	state = "pass"
	await _walk_to_node(10)
	while _alive and not kitchen.pass_has_room():
		body.play("tap_foot")
		await _wait(1.0)
	if not _alive:
		return
	carried = null
	body.carrying = false
	kitchen.put_on_pass(p)
	Game.today.staff_made = int(Game.today.get("staff_made", 0)) + 1
	body.play("celebrate")
	Game.say_toast("%s put pizza #%d on the pass!" % [info.name, tid], UiTheme.TEAL)
	await _wait(1.0)


func _assemble(p: Pizza, order: Dictionary, m: float) -> void:
	var want_r := float(Menu.SIZES[order.get("size", "medium")].radius)
	var final_r := want_r + _rng.randf_range(-1, 1) * 0.07 * (1.0 - skill)
	# stretch
	var steps := int(12 * m)
	for k in steps:
		p.set_stretch(lerpf(0.1, final_r, float(k + 1) / steps))
		if k % 4 == 0:
			body.play("work")
		await _wait(0.12)
	p.finish_stretch(order.get("size", "medium"))
	# sauce
	var sauce: String = order.get("sauce", "tomato")
	var n := int(lerpf(45.0, 110.0, skill))
	var spill_spot: bool = info.quirk == "drops" and _rng.randf() < 0.4
	for k in n:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * p.radius() * lerpf(1.05, 0.88, skill)
		p.paint_sauce(Vector2(cos(a), sin(a)) * d, sauce)
		if k % 6 == 0:
			await _wait(0.06 * m)
	if spill_spot and _alive:
		kitchen.add_puddle(position + Vector3(sin(rotation.y), 0, cos(rotation.y)) * -0.6, 0.45, false)
		body.play("facepalm")
		Game.say_toast("Carla dropped the sauce bucket. Floor's slippery!", Color("#ff9f1c"))
		await _wait(1.0)
	# cheese
	for k in int(lerpf(30.0, 70.0, skill)):
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * p.radius() * lerpf(1.0, 0.84, skill)
		p.sprinkle_cheese(Vector2(cos(a), sin(a)) * d)
		if k % 5 == 0:
			await _wait(0.06 * m)
	# toppings (Steve "taste tests")
	var tops: Array = order.get("toppings", []).duplicate()
	if info.quirk == "snacks" and not tops.is_empty() and _rng.randf() < 0.35:
		var eaten: String = tops.pop_back()
		body.play("eat")
		Game.say_toast("Steve ate all the %s. Pizza #%d is missing some." % [Menu.TOPPINGS[eaten].label.to_lower(), p.data.ticket], Color("#ff9f1c"))
		await _wait(1.5)
	for kind: String in tops:
		for k in Pizza.PIECES_PER_PORTION + 1:
			var a := _rng.randf() * TAU
			var d := sqrt(_rng.randf()) * p.radius() * 0.75
			p.place_topping(kind, Vector2(cos(a), sin(a)) * d)
			await _wait(0.1 * m)
	p.finish_assembly()
	body.play("nod")
	await _wait(0.4)


func _carry(p: Pizza) -> void:
	carried = p
	p.reparent(body.hand_socket, false)
	p.position = Vector3(0, 0.02, 0)
	p.rotation = Vector3.ZERO
	p.location = "carried"
	body.carry_style = "front"
	body.carrying = true


func _set_down(p: Pizza, local: Vector3) -> void:
	body.carrying = false
	p.reparent(get_parent(), false)
	p.position = local
	p.rotation = Vector3.ZERO
	p.location = "kitchen"


func _drop_task(p: Pizza) -> void:
	carried = null
	body.carrying = false
	if p and is_instance_valid(p):
		if _ticket_alive(p.data.ticket):
			Game.set_ticket_status(p.data.ticket, "new")
		p.queue_free()


# --- phone duty -----------------------------------------------------------------------------------------

func _phone_loop() -> void:
	await _walk_to_node(14)
	while _alive:
		_face(Pizzeria.ANCHORS.phone)
		await _wait(0.3)
		if phone == null or not phone.is_ringing() or not Game.day_running:
			if _rng.randf() < 0.02:
				body.play(["tap_foot", "yawn", "look_around"][_rng.randi() % 3])
			continue
		await _wait(1.6)
		if not phone.is_ringing() or not _alive:
			continue
		var caller := phone.answer()
		body.phone_mode = true
		body.talking = true
		Sfx.play("blip")
		await _wait(2.5 if info.quirk == "polite" else 1.5)
		body.talking = false
		body.phone_mode = false
		if caller == null:
			continue
		if info.quirk == "rude" and _rng.randf() < 0.25:
			Game.missed_call()
			Sfx.play("hangup")
			body.play("shrug")
			Game.say_toast("Barry hung up on %s. \"Weird voice.\"" % caller.display_name(), Color("#ff9f1c"))
			continue
		var order := Menu.random_order(_rng, caller.character.get("favorites", []))
		var t := Game.add_ticket(caller, caller.display_name(), order)
		Sfx.play("register")
		body.play("nod")
		Game.say_toast("%s took an order! #%d: %s for %s" % [info.name.split(" ")[0], t.id, Menu.describe(order), caller.display_name()], UiTheme.YELLOW)
