class_name Disasters
extends Node
## The slapstick director. Every shift has a silly "today" rule (low gravity,
## ice floors...) and every minute or so something goes wrong on purpose:
## chicken rain, grease spills, a burning oven, a goat, a blackout, aliens.

const MUTATORS := {
	"low_gravity": {"title": "MOON PIZZA DAY", "text": "Low gravity. Jump responsibly.", "gravity": 0.35},
	"ice": {"title": "ICE FLOOR FRIDAY", "text": "Everything is slippery. Steer early.", "accel": 0.13},
	"sugar": {"title": "SUGAR RUSH", "text": "You are fast. Stopping is optional.", "speed": 1.6, "accel": 1.6},
}
const EVENTS := ["chicken_rain", "grease", "oven_fire", "goat", "blackout", "ufo", "chicken_rain", "grease", "goat"]

var main: Node
var mutator := ""
var current_event := ""
var _next := 40.0
var _scatter_kinds := ["chicken", "chicken", "pan", "tomato", "tomato", "cone", "bucket", "watermelon", "plunger", "rolling_pin", "baguette", "baguette", "anvil"]
var _fire: FireSpot
var _goat: Goat
var _dark: CanvasLayer
var _ufo: Node3D


func setup(m: Node) -> void:
	main = m
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Game.day_started.connect(_on_day_started)
	Game.day_ended.connect(_on_day_ended)


func _pz() -> Pizzeria:
	return main.town.pizzeria


# --- day start / end -------------------------------------------------------------------------------

func _on_day_started(day: int) -> void:
	_cleanup_events()
	for n in get_tree().get_nodes_in_group("throwable"):
		if (n as Throwable).spawned and not (n as Throwable).grabbed:
			n.queue_free()
	await get_tree().process_frame
	scatter(18)
	_next = 40.0
	set_mutator("" if day == 1 or randf() < 0.3 else MUTATORS.keys().pick_random())


func _on_day_ended(_summary: Dictionary) -> void:
	_cleanup_events()
	set_mutator("")


func set_mutator(name: String) -> void:
	mutator = name
	var p: PlayerEgg = main.player
	p.gravity_mult = 1.0
	p.accel_mult = 1.0
	p.speed_mult = 1.0
	if name == "":
		return
	var m: Dictionary = MUTATORS[name]
	p.gravity_mult = m.get("gravity", 1.0)
	p.accel_mult = m.get("accel", 1.0)
	p.speed_mult = m.get("speed", 1.0)
	Game.say_toast("%s: %s" % [m.title, m.text], UiTheme.PINK)


func mutator_title() -> String:
	return MUTATORS[mutator].title if mutator != "" else ""


# --- props -------------------------------------------------------------------------------------------

func _floor_spot() -> Vector3:
	var local: Vector3
	if randf() < 0.65:
		local = Vector3(randf_range(-9.0, 9.0), 1.6, randf_range(2.8, 7.5))        # dining room
	else:
		local = Vector3(randf_range(-10.0, 3.0), 1.6, randf_range(-1.8, 0.4))       # kitchen front aisle
	return _pz().to_global(local)


func spawn_prop(kind: String, at: Vector3, velocity := Vector3.ZERO) -> Throwable:
	var t := Throwable.make(kind)
	main.add_child(t)
	t.global_position = at
	t.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	t.linear_velocity = velocity
	_trim_props()
	return t


func _trim_props() -> void:
	var all := get_tree().get_nodes_in_group("throwable")
	var over := all.size() - 70
	for n in all:
		if over <= 0:
			break
		var t := n as Throwable
		if t.spawned and not t.grabbed and t.harmful_t <= 0.0:
			t.queue_free()
			over -= 1


func scatter(count: int) -> void:
	for i in count:
		spawn_prop(_scatter_kinds.pick_random(), _floor_spot())


# --- scheduling --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not Game.day_running or get_tree().paused:
		return
	_next -= delta
	if _next <= 0.0:
		if main.kitchen.busy or main.convo.active or current_event != "":
			_next = 4.0
			return
		_next = randf_range(55.0, 95.0)
		trigger(EVENTS.pick_random())


func trigger(event: String) -> void:
	if event == "ufo" and (main.in_car or main.car.global_position.distance_to(main.town.pizzeria.global_position) > 40.0):
		event = "chicken_rain"
	call("_do_" + event)


func _cleanup_events() -> void:
	current_event = ""
	if _fire and is_instance_valid(_fire):
		_fire.queue_free()
	if _goat and is_instance_valid(_goat):
		_goat.queue_free()
	if _dark and is_instance_valid(_dark):
		_dark.queue_free()
	if _ufo and is_instance_valid(_ufo):
		_ufo.queue_free()
	for n in get_tree().get_nodes_in_group("grease"):
		n.queue_free()


# --- the disasters -----------------------------------------------------------------------------------

func _do_chicken_rain() -> void:
	Game.say_toast("RUBBER CHICKEN RAIN! Heads up!", Color("#ffd23f"))
	Sfx.play("airhorn", 1.0, -4.0)
	current_event = "chicken_rain"
	for i in 14:
		var at := _pz().to_global(Vector3(randf_range(-9.0, 9.0), 3.7, randf_range(-6.5, 7.5)))
		var t := spawn_prop("chicken", at, Vector3(0, -3.0, 0))
		t.harmful_t = 6.0
		await get_tree().create_timer(0.18).timeout
		if not Game.day_running:
			return
	current_event = ""


func _do_grease() -> void:
	Game.say_toast("GREASE SPILL! The whole kitchen is a slip-n-slide.", Color("#ff9f1c"))
	Sfx.play("splat", 0.7)
	current_event = "grease"
	for i in 4:
		var local := Vector3(randf_range(-9.0, 3.0), 0.09, randf_range(-6.5, 0.2)) if i < 2 else Vector3(randf_range(-8.0, 8.0), 0.09, randf_range(3.0, 7.0))
		var puddle := Node3D.new()
		puddle.position = local
		puddle.set_meta("radius", 1.3)
		puddle.add_to_group("slippery")
		puddle.add_to_group("grease")
		_pz().add_child(puddle)
		var blob := Toon.cyl(puddle, 1.3, 1.3, 0.006, Vector3.ZERO, Color("#d19a1a"), 0.0, 14)
		blob.scale = Vector3(1.0, 1.0, 0.8)
		Toon.cyl(puddle, 0.5, 0.5, 0.008, Vector3(0.3, 0, 0.2), Color("#e8b73a"), 0.0, 10)
		var tw := puddle.create_tween()
		tw.tween_interval(40.0)
		tw.tween_callback(puddle.queue_free)
	get_tree().create_timer(3.0).timeout.connect(func() -> void: if current_event == "grease": current_event = "")


func _do_oven_fire() -> void:
	Game.say_toast("THE OVEN IS ON FIRE! Stomp it out! (E, mash it)", Color("#ff5d3a"))
	Sfx.play("awooga", 1.0, -4.0)
	current_event = "oven_fire"
	_fire = FireSpot.new()
	_fire.position = Pizzeria.ANCHORS.oven1 + Vector3(0.0, 0.95, 0.5)
	_pz().add_child(_fire)
	_fire.finished.connect(_on_fire_done)


func _on_fire_done(won: bool) -> void:
	current_event = ""
	var p: PlayerEgg = main.player
	if won:
		Game.money += 25
		Game.money_changed.emit(Game.money, 25)
		Game.say_toast("FIRE OUT! You're a hero. +$25", UiTheme.TEAL)
		Sfx.play("cash")
		return
	Game.say_toast("KABOOM. Everyone is on the floor. -$30 for the oven.", Color("#ff5d3a"))
	Sfx.play("slam", 0.6)
	Game.money = maxi(0, Game.money - 30)
	Game.money_changed.emit(Game.money, -30)
	var center := _pz().to_global(Pizzeria.ANCHORS.oven1)
	for n in get_tree().get_nodes_in_group("eggs"):
		var e := n as EggBody
		if e == null or not e.is_visible_in_tree() or e.global_position.distance_to(center) > 14.0:
			continue
		var away := e.global_position - center
		if e == p.body:
			p.tumble(away, 1.6)
		else:
			Chaos.bonk(e, away, 1.6, "KABOOM")
	for n in get_tree().get_nodes_in_group("throwable"):
		var t := n as Throwable
		if t.global_position.distance_to(center) < 8.0 and not t.grabbed:
			t.linear_velocity = (t.global_position - center).normalized() * 9.0 + Vector3(0, 7.0, 0)


func _do_goat() -> void:
	Game.say_toast("A GOAT got into the kitchen. Nobody knows how.", Color("#c7f464"))
	Sfx.play("goat")
	current_event = "goat"
	_goat = Goat.new()
	_goat.player = main.player
	_goat.pz = _pz()
	_pz().add_child(_goat)
	_goat.position = Vector3(0.0, 0.0, 8.0)
	_goat.done.connect(func() -> void: current_event = "")


func _do_blackout() -> void:
	Game.say_toast("BLACKOUT! Somebody hit the breaker with a baguette.", Color("#a29bfe"))
	Sfx.play("awooga", 0.6, -4.0)
	current_event = "blackout"
	_dark = CanvasLayer.new()
	_dark.layer = 3
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	float d = distance(UV * vec2(1.78, 1.0), vec2(0.89, 0.5));
	float a = smoothstep(0.22, 0.62, d) * 0.93 + 0.55;
	COLOR = vec4(0.02, 0.0, 0.08, clamp(a, 0.0, 0.97) * amount);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("amount", 0.0)
	rect.material = mat
	_dark.add_child(rect)
	add_child(_dark)
	var tw := create_tween()
	tw.tween_property(mat, "shader_parameter/amount", 1.0, 0.3)
	tw.tween_interval(10.0)
	tw.tween_property(mat, "shader_parameter/amount", 0.0, 0.8)
	tw.tween_callback(func() -> void:
		if _dark and is_instance_valid(_dark):
			_dark.queue_free()
		Game.say_toast("The lights are back. Nobody saw anything.", UiTheme.YELLOW)
		current_event = "")


func _do_ufo() -> void:
	Game.say_toast("ALIENS ARE STEALING YOUR VAN!", Color("#7CFC00"))
	Sfx.play("awooga", 1.6)
	current_event = "ufo"
	var car: PizzaCar = main.car
	_ufo = Node3D.new()
	main.add_child(_ufo)
	_ufo.global_position = car.global_position + Vector3(0, 14.0, 0)
	Toon.ball(_ufo, 1.8, Vector3.ZERO, Color("#b7bdc9"), 0.03, 20).scale = Vector3(1.0, 0.28, 1.0)
	Toon.ball(_ufo, 0.9, Vector3(0, 0.35, 0), Color("#8de9ff"), 0.02, 14)
	for k in 8:
		var a := TAU * k / 8.0
		Toon.ball(_ufo, 0.14, Vector3(cos(a) * 1.55, -0.05, sin(a) * 1.55), Color("#ffd166"), 0.0, 6)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.8
	cm.bottom_radius = 2.2
	cm.height = 14.0
	cm.radial_segments = 20
	beam.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(0.5, 1.0, 0.6, 0.28)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bm
	beam.position = Vector3(0, -7.0, 0)
	_ufo.add_child(beam)
	var tw := create_tween()
	tw.tween_property(_ufo, "global_position:y", car.global_position.y + 6.5, 1.4)
	tw.tween_callback(func() -> void: Sfx.play("whoosh", 0.5))
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(car):
			car.respawn_at(Vector3(car.global_position.x, 0.4 + k * 4.5, car.global_position.z), car.rotation.y + 0.15), 0.0, 1.0, 1.6)
	tw.tween_callback(func() -> void:
		var t: Town = main.town
		var dest := Vector3(t.road_x(randi() % (Town.COLS + 1)), 0.5, t.road_z(randi() % (Town.ROWS + 1)))
		car.respawn_at(dest, randf() * TAU)
		Game.say_toast("Your van got dumped in the middle of the street. Rude.", UiTheme.YELLOW))
	tw.tween_property(_ufo, "global_position:y", 40.0, 1.2)
	tw.tween_callback(func() -> void:
		if _ufo and is_instance_valid(_ufo):
			_ufo.queue_free()
		current_event = "")


# --- the fire --------------------------------------------------------------------------------------

class FireSpot extends Interactable:
	signal finished(won: bool)
	var progress := 0
	var need := 9
	var time_left := 20.0
	var _flames: Array[MeshInstance3D] = []
	var _light: OmniLight3D
	var _t := 0.0
	var _done := false

	func _init() -> void:
		reach = 2.2
		aim_radius = 0.9

	func _ready() -> void:
		for k in 7:
			var a := TAU * k / 7.0
			var col := Color("#ff6b1a") if k % 2 == 0 else Color("#ffd23f")
			var f := Toon.cyl(self, 0.0, 0.2, 0.7, Vector3(cos(a) * 0.35, 0.3, sin(a) * 0.35), col, 0.0, 8)
			f.material_override = Toon.glow(col, 2.2)
			_flames.append(f)
		var core := Toon.cyl(self, 0.0, 0.3, 1.1, Vector3(0, 0.5, 0), Color("#ffe27a"), 0.0, 8)
		core.material_override = Toon.glow(Color("#ffe27a"), 2.6)
		_flames.append(core)
		_light = OmniLight3D.new()
		_light.light_color = Color("#ff8a3a")
		_light.omni_range = 7.0
		_light.position = Vector3(0, 1.0, 0)
		add_child(_light)

	func prompt(_p: Node) -> String:
		return "[E] STOMP IT OUT!  (%d/%d)" % [progress, need] if not _done else ""

	func use(p: Node) -> void:
		if _done:
			return
		progress += 1
		Sfx.play("squish", randf_range(0.8, 1.4), -4.0)
		Chaos.popup(global_position + Vector3(0, 1.6, 0), ["STOMP", "FWOOSH", "AAAH"].pick_random(), Color("#ffd166"), 100)
		if p is PlayerEgg:
			(p as PlayerEgg).body.play("stomp")
		if progress >= need:
			_finish(true)

	func _process(delta: float) -> void:
		if _done:
			return
		_t += delta
		time_left -= delta
		var size := clampf(1.0 - float(progress) / need * 0.8, 0.2, 1.0)
		for i in _flames.size():
			var f := _flames[i]
			f.scale = Vector3(1.5, (0.7 + sin(_t * 11.0 + i * 1.7) * 0.3) * 1.6 * size, 1.5) * size
		_light.light_energy = (1.6 + sin(_t * 20.0) * 0.5) * size
		# A thrown bucket of water counts as a lot of stomping.
		for n in get_tree().get_nodes_in_group("throwable"):
			var t := n as Throwable
			if t.kind == "bucket" and not t.grabbed and t.linear_velocity.length() > 2.5 and t.global_position.distance_to(global_position) < 1.5:
				progress += 5
				Chaos.popup(global_position + Vector3(0, 1.8, 0), "SPLASH!", Color("#8de9ff"), 120)
				Sfx.play("splat", 0.8)
				t.linear_velocity *= 0.2
				if progress >= need:
					_finish(true)
				break
		if time_left <= 0.0:
			_finish(false)

	func _finish(won: bool) -> void:
		_done = true
		finished.emit(won)
		queue_free()


# --- the goat --------------------------------------------------------------------------------------

class Goat extends Node3D:
	signal done
	var player: PlayerEgg
	var pz: Pizzeria
	var egg: EggBody
	var _state := "enter"
	var _t := 0.0
	var _life := 28.0
	var _dir := Vector3.FORWARD
	var _bleat := 2.0

	func _ready() -> void:
		egg = EggBody.new()
		add_child(egg)
		egg.build({"skin": "#efe6d2", "shirt": "#7a5b3a", "sleeves": "none", "ears": true, "snout": true, "tail": true, "beard": true, "eye": "big", "round": 1.1, "size": 0.85})

	func _process(delta: float) -> void:
		_life -= delta
		_t -= delta
		_bleat -= delta
		if _bleat <= 0.0:
			_bleat = randf_range(3.0, 5.0)
			Sfx.play("goat", randf_range(0.8, 1.3), -3.0)
		var local_player := pz.to_local(player.global_position)
		if _life <= 0.0:
			_state = "leave"
		var speed := 0.0
		match _state:
			"enter", "seek":
				var to := local_player - position
				to.y = 0
				_dir = to.normalized() if to.length() > 0.1 else _dir
				speed = 3.2
				if _state == "enter" and position.z < 5.5:
					_state = "seek"
				if to.length() < 5.0 and _state == "seek":
					_state = "windup"
					_t = 0.9
					egg.play("stomp")
					egg.express("angry", 1.5)
			"windup":
				speed = 0.0
				if _t <= 0.0:
					_state = "charge"
					_t = 1.4
			"charge":
				speed = 9.5
				if _t <= 0.0:
					_state = "seek"
			"retreat":
				speed = 3.0
				_dir = (position - local_player).normalized()
				if _t <= 0.0:
					_state = "seek"
			"leave":
				_dir = (Vector3(0, 0, 10.0) - position).normalized()
				speed = 4.5
				if position.z > 8.8:
					done.emit()
					queue_free()
					return
		position += _dir * speed * delta
		position.x = clampf(position.x, -10.0, 10.0)
		position.z = clampf(position.z, -8.5, 10.0)
		rotation.y = lerp_angle(rotation.y, atan2(_dir.x, _dir.z), 1.0 - exp(-9.0 * delta))
		egg.speed = speed / 1.6
		if _state == "charge" or _state == "seek":
			_check_hits()

	func _check_hits() -> void:
		for n in get_tree().get_nodes_in_group("eggs"):
			var e := n as EggBody
			if e == null or e == egg or not e.is_visible_in_tree():
				continue
			var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
			if d > 0.95:
				continue
			var away := e.global_position - global_position
			if e == player.body:
				player.tumble(away, 1.4)
				Chaos.popup(player.global_position + Vector3(0, 2.0, 0), "BAAAH!", Color("#c7f464"))
			elif _state == "charge":
				Chaos.bonk(e, away, 1.3, "BAAAH!")
			else:
				continue
			_state = "retreat"
			_t = 1.6
			Sfx.play("goat", 1.4)
			return
