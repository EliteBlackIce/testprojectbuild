class_name Kitchen
extends Node3D
## All the cooking: dough fridge -> prep table -> oven -> cut & box -> heat
## shelf. Also hosts the phone, the PC and Tony (their actions are callbacks
## from main, since they open other systems).

signal busy_changed(busy: bool)
## Main hooks these up.
var on_phone: Callable
var phone_prompt: Callable
var on_pc: Callable
var on_tony: Callable

const BAKE_SECONDS := [14.0, 11.0, 8.5, 6.5]   ## time to a perfect bake, by oven level
const SHELF_SIZE := 4

var pizzeria: Pizzeria
var minigame: MinigameUi
var makeline: MakelineUi
var camera: GameCamera
var tony: EggBody

var prep_pizza: Pizza
var ovens: Array[Dictionary] = []
var shelf: Array[Pizza] = []
var busy := false

var _prep_spot: Node3D
var _shelf_spots: Array[Node3D] = []
var _tony_t := 0.0
var _tony_target := Vector3.ZERO
var _alarm_cooldown := 0.0


func setup(p: Pizzeria) -> void:
	pizzeria = p
	_prep_spot = Node3D.new()
	_prep_spot.position = (Pizzeria.ANCHORS.prep as Vector3) + Vector3(0, 0.98, 0.1)
	pizzeria.add_child(_prep_spot)
	for i in SHELF_SIZE:
		var s := Node3D.new()
		s.position = (Pizzeria.ANCHORS.shelf as Vector3) + Vector3(0, 0.97 + (i % 2) * 1.05, -0.55 + (i / 2) * 1.1)
		pizzeria.add_child(s)
		_shelf_spots.append(s)
	_build_ovens()
	_build_stations()
	_build_tony()
	Game.upgrades_changed.connect(_refresh_ovens)


# --- stations --------------------------------------------------------------------------------

func _build_stations() -> void:
	var A := Pizzeria.ANCHORS
	Station.make(pizzeria, (A.fridge as Vector3) + Vector3(0.7, 0.9, 0), _fridge_prompt, _fridge_use, 1.8)
	Station.make(pizzeria, (A.prep as Vector3) + Vector3(0, 0.9, 0.9), _prep_prompt, _prep_use, 2.0)
	Station.make(pizzeria, (A.cut as Vector3) + Vector3(0, 0.9, 0.8), _cut_prompt, _cut_use, 1.8)
	Station.make(pizzeria, (A.shelf as Vector3) + Vector3(-0.9, 0.9, 0), _shelf_prompt, _shelf_use, 1.8)
	Station.make(pizzeria, (A.trash as Vector3) + Vector3(0, 0.7, 0), _trash_prompt, _trash_use, 1.4)
	Station.make(pizzeria, (A.phone as Vector3) + Vector3(-0.7, 0.9, 0), func(p): return phone_prompt.call(p) if phone_prompt.is_valid() else "", func(p): on_phone.call(p), 1.6)
	Station.make(pizzeria, (A.pc as Vector3) + Vector3(0.4, 0.9, 0.8), func(_p): return "[E] Tony's PC (upgrades)", func(p): on_pc.call(p), 1.6)
	# Phone + ticket rail props
	var phone_pos := A.phone as Vector3
	Toon.block(pizzeria, Vector3(0.12, 0.5, 0.35), phone_pos + Vector3(-0.05, 1.3, 0), Color("#c0392b"), 0.1)
	Toon.block(pizzeria, Vector3(0.16, 0.12, 0.42), phone_pos + Vector3(-0.12, 1.72, 0), Color("#2d3436"), 0.3)


func _set_busy(on: bool, player: PlayerEgg) -> void:
	busy = on
	player.controls_enabled = not on
	busy_changed.emit(on)


func _new_tickets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in Game.open_tickets():
		if t.status == "new":
			out.append(t)
	return out


func _fridge_prompt(player: PlayerEgg) -> String:
	if busy or player.is_holding():
		return ""
	if prep_pizza:
		return "Prep table is busy"
	if _new_tickets().is_empty():
		return "No orders to make. Wait for the phone!"
	return "[E] Grab dough"


func _fridge_use(player: PlayerEgg) -> void:
	if busy or player.is_holding() or prep_pizza or _new_tickets().is_empty():
		return
	_set_busy(true, player)
	var tid := await makeline.pick_ticket(_new_tickets())
	var t := Game.ticket(tid)
	var cost := int(ceil(Menu.price_of(t.order) * Menu.INGREDIENT_COST))
	Game.spend(mini(cost, Game.money), "ingredients")
	camera.focus_on(_prep_spot.global_position, 4.0)
	if MakelineUi.autoplay:
		minigame.call_deferred("auto_finish", 1.0)
	var r := await minigame.play("stretch", {"size": t.order.size, "bonus": float(Game.level("dough_press"))})
	var pizza := Pizza.new()
	_prep_spot.add_child(pizza)
	pizza.setup(tid, r.size, r.quality)
	prep_pizza = pizza
	Game.set_ticket_status(tid, "making")
	Sfx.play("splat", 0.8)
	camera.focus_on(Vector3.ZERO, 0.0)
	_set_busy(false, player)


func _prep_prompt(player: PlayerEgg) -> String:
	if busy:
		return ""
	if prep_pizza == null:
		var held := player.held as Pizza
		if held and not held.data.baked:
			return "[E] Put pizza down"
		return ""
	if not prep_pizza.data.get("assembled", false):
		return "[E] Add sauce, cheese & toppings (#%d)" % prep_pizza.data.ticket
	if not player.is_holding():
		return "[E] Pick up pizza #%d" % prep_pizza.data.ticket
	return ""


func _prep_use(player: PlayerEgg) -> void:
	if busy:
		return
	if prep_pizza == null:
		var held := player.held as Pizza
		if held and not held.data.baked:
			player.take_held()
			held.reparent(_prep_spot, false)
			held.position = Vector3.ZERO
			held.rotation = Vector3.ZERO
			prep_pizza = held
		return
	if not prep_pizza.data.get("assembled", false):
		_set_busy(true, player)
		camera.focus_on(_prep_spot.global_position, 2.6)
		await makeline.run(prep_pizza, Game.ticket(prep_pizza.data.ticket), minigame)
		prep_pizza.data["assembled"] = true
		camera.focus_on(Vector3.ZERO, 0.0)
		_set_busy(false, player)
		Game.say_toast("Pizza #%d ready for the oven!" % prep_pizza.data.ticket, UiTheme.TEAL)
	elif not player.is_holding():
		var p := prep_pizza
		prep_pizza = null
		player.hold(p)


# --- ovens ----------------------------------------------------------------------------------------

func _build_ovens() -> void:
	for i in 2:
		var pos := Pizzeria.ANCHORS["oven%d" % (i + 1)] as Vector3
		var root := Node3D.new()
		root.position = pos
		pizzeria.add_child(root)
		# Brick base + dome + chimney + mouth with fire.
		Toon.block(root, Vector3(2.2, 0.9, 1.6), Vector3.ZERO, Color("#a0522d"), 0.06, 0.015)
		Toon.mesh(root, Shapes.lathe(PackedVector2Array([Vector2(1.05, 0), Vector2(1.0, 0.45), Vector2(0.75, 0.9), Vector2(0.3, 1.15), Vector2(0, 1.2)]), 10, 0.5), Vector3(0, 0.9, -0.05), Color("#b5653d"), 0.02)
		Toon.cyl(root, 0.18, 0.2, 1.4, Vector3(0, 2.6, -0.4), Color("#7f4f2f"), 0.012, 6)
		var mouth := Toon.box(root, Vector3(0.9, 0.5, 0.2), Vector3(0, 1.2, 0.75), Color("#1d1517"), 0.0)
		var fire := MeshInstance3D.new()
		fire.mesh = Shapes.ball(0.28, 7, 4)
		fire.material_override = Toon.glow(Color("#ff8c42"), 2.5)
		fire.position = Vector3(0, 1.08, 0.5)
		fire.scale = Vector3(1.4, 0.5, 0.6)
		root.add_child(fire)
		var light := OmniLight3D.new()
		light.light_color = Color("#ff9e57")
		light.light_energy = 0.45
		light.omni_range = 3.5
		light.position = Vector3(0, 1.2, 1.2)
		root.add_child(light)
		var spot := Node3D.new()
		spot.position = Vector3(0, 1.0, 0.55)
		root.add_child(spot)
		var label := Toon.label(root, "", Vector3(0, 2.4, 0.8), 70, Color.WHITE)
		var smoke := Node3D.new()
		root.add_child(smoke)
		ovens.append({"root": root, "spot": spot, "pizza": null, "label": label, "fire": fire, "mouth": mouth, "smoke": smoke, "index": i})
		Station.make(pizzeria, pos + Vector3(0, 0.9, 1.5), _oven_prompt.bind(i), _oven_use.bind(i), 1.8)
	_refresh_ovens()


func _refresh_ovens() -> void:
	var count := 2 if Game.has_upgrade("second_oven") else 1
	for o in ovens:
		(o.root as Node3D).visible = o.index < count


func _oven_prompt(player: PlayerEgg, i: int) -> String:
	var o := ovens[i]
	if busy or not (o.root as Node3D).visible:
		return ""
	var p: Pizza = o.pizza
	if p == null:
		var held := player.held as Pizza
		if held and held.data.get("assembled", false) and not held.data.baked:
			return "[E] Put pizza in the oven"
		return "Oven %d (empty)" % (i + 1)
	if player.is_holding():
		return "Hands full!"
	var b := float(p.data.bake)
	if b > 1.3:
		return "[E] Take out (IT'S BURNING)"
	if b >= 0.88:
		return "[E] Take out NOW (perfect!)"
	return "[E] Take out early (%d%%)" % int(b * 100)


func _oven_use(player: PlayerEgg, i: int) -> void:
	var o := ovens[i]
	var p: Pizza = o.pizza
	if p == null:
		var held := player.held as Pizza
		if held and held.data.get("assembled", false) and not held.data.baked:
			player.take_held()
			held.reparent(o.spot, false)
			held.position = Vector3.ZERO
			held.rotation = Vector3.ZERO
			held.location = "oven"
			o.pizza = held
			Game.set_ticket_status(held.data.ticket, "baking")
			Sfx.play("slam", 1.6, -8.0)
		return
	if player.is_holding():
		return
	o.pizza = null
	p.data.baked = true
	p.data.heat = 100.0
	player.hold(p)
	(o.label as Label3D).text = ""
	Sfx.play("pickup")
	var b := float(p.data.bake)
	if b > 1.3:
		Game.say_toast("Burnt! Customers will notice...", Color("#ff9f1c"))
	elif b >= 0.88:
		Game.say_toast("PERFECT BAKE!", UiTheme.TEAL)


func _process(delta: float) -> void:
	_alarm_cooldown = maxf(0.0, _alarm_cooldown - delta)
	var bake_time: float = BAKE_SECONDS[Game.level("oven")]
	for o in ovens:
		var p: Pizza = o.pizza
		var label := o.label as Label3D
		var fire := o.fire as MeshInstance3D
		fire.scale = Vector3(1.4, 0.5 + sin(Time.get_ticks_msec() * 0.01 + o.index) * 0.08, 0.6)
		if p == null:
			continue
		if not Game.in_dialogue:
			p.set_bake(float(p.data.bake) + delta / bake_time)
		var b := float(p.data.bake)
		if b < 0.88:
			label.text = "%d%%" % int(b * 100)
			label.modulate = Color.WHITE
		elif b <= 1.15:
			label.text = "PERFECT!"
			label.modulate = UiTheme.TEAL
		elif b <= 1.3:
			label.text = "HURRY!"
			label.modulate = Color("#ff9f1c")
		else:
			label.text = "BURNING!!!"
			label.modulate = UiTheme.RED
			if _alarm_cooldown <= 0.0:
				_alarm_cooldown = 1.2
				Sfx.play("honk", 1.6, -8.0)
	_update_tony(delta)


# --- cut, shelf, trash ----------------------------------------------------------------------

func _cut_prompt(player: PlayerEgg) -> String:
	var held := player.held as Pizza
	if busy or held == null:
		return ""
	if held.data.baked and not held.is_boxed():
		return "[E] Cut & box it"
	return ""


func _cut_use(player: PlayerEgg) -> void:
	var held := player.held as Pizza
	if busy or held == null or not held.data.baked or held.is_boxed():
		return
	_set_busy(true, player)
	camera.focus_on(pizzeria.anchor("cut") + Vector3(0, 1.0, 0), 3.0)
	if MakelineUi.autoplay:
		minigame.call_deferred("auto_finish", 1.0)
	var r := await minigame.play("chop", {"bonus": 0.0})
	held.put_in_box(r.quality)
	Game.set_ticket_status(held.data.ticket, "ready")
	Sfx.play("slam", 1.8, -6.0)
	camera.focus_on(Vector3.ZERO, 0.0)
	_set_busy(false, player)
	Game.say_toast("Boxed! Load it into the car out front.", UiTheme.YELLOW)


func _shelf_prompt(player: PlayerEgg) -> String:
	if busy:
		return ""
	var held := player.held as Pizza
	if held and held.is_boxed():
		if shelf.size() >= SHELF_SIZE:
			return "Shelf is full"
		return "[E] Put on %s (%d/%d)" % ["heat shelf" if Game.has_upgrade("heat_lamp") else "shelf", shelf.size(), SHELF_SIZE]
	if not player.is_holding() and not shelf.is_empty():
		return "[E] Grab pizza #%d" % shelf[0].data.ticket
	return ""


func _shelf_use(player: PlayerEgg) -> void:
	var held := player.held as Pizza
	if held and held.is_boxed() and shelf.size() < SHELF_SIZE:
		player.take_held()
		shelf.append(held)
		held.location = "shelf"
		_layout_shelf()
	elif not player.is_holding() and not shelf.is_empty():
		var p: Pizza = shelf.pop_front()
		player.hold(p)
		_layout_shelf()


func _layout_shelf() -> void:
	for i in shelf.size():
		shelf[i].reparent(_shelf_spots[i], false)
		shelf[i].position = Vector3.ZERO
		shelf[i].rotation = Vector3.ZERO


func _trash_prompt(player: PlayerEgg) -> String:
	return "[E] Throw it away" if player.is_holding() and not busy else ""


func _trash_use(player: PlayerEgg) -> void:
	var item := player.take_held()
	if item is Pizza:
		var tid: int = (item as Pizza).data.ticket
		var t := Game.ticket(tid)
		if not t.is_empty() and t.status not in ["delivered", "failed"]:
			Game.set_ticket_status(tid, "new")
	item.queue_free()
	Sfx.play("splat")


## Every pizza currently sitting in the kitchen (for tests and the HUD).
func pizzas_in_kitchen() -> Array[Pizza]:
	var out: Array[Pizza] = []
	if prep_pizza:
		out.append(prep_pizza)
	for o in ovens:
		if o.pizza:
			out.append(o.pizza)
	out.append_array(shelf)
	return out


# --- Tony ------------------------------------------------------------------------------------

func _build_tony() -> void:
	tony = EggBody.new()
	pizzeria.add_child(tony)
	tony.build(Characters.TONY.look)
	tony.position = Pizzeria.ANCHORS.tony
	_tony_target = tony.position
	var talk := Station.make(tony, Vector3(0, 1.0, 0), func(p): return "" if busy or (p as PlayerEgg).is_holding() else "[E] Talk to Tony", func(p): on_tony.call(p), 1.8)
	talk.name = "TonyTalk"


func _update_tony(delta: float) -> void:
	if Game.in_dialogue:
		tony.speed = 0.0
		return
	_tony_t -= delta
	if _tony_t <= 0.0:
		_tony_t = randf_range(3.0, 7.0)
		var spots := [Vector3(2.0, 0, -2.0), Vector3(-0.2, 0, -4.4), Vector3(3.0, 0, -4.0), Vector3(0.5, 0, 0.5), Vector3(-1.5, 0, -1.0)]
		_tony_target = spots[randi() % spots.size()]
	var to := _tony_target - tony.position
	to.y = 0.0
	if to.length() > 0.15:
		var step := to.normalized() * minf(2.0 * delta, to.length())
		tony.position += step
		tony.rotation.y = lerp_angle(tony.rotation.y, atan2(to.x, to.z), 1.0 - exp(-8.0 * delta))
		tony.speed = 0.8
	else:
		tony.speed = 0.0
