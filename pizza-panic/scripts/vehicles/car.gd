class_name PizzaCar
extends CharacterBody3D
## The delivery car. Arcade handling, upgradeable, carries pizza boxes on a
## roof rack, and a giant pizza slice on top. Forward is -Z.

signal crashed(impact: float)

const GRAVITY := 24.0

var driving := false            ## true while the player is in the driver's seat
var cargo: Array[Pizza] = []
var boost_fuel := 1.0
var drifting := false

var _visual: Node3D
var _wheels: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
var _rack: Node3D
var _cargo_spots: Array[Node3D] = []
var _driver: EggBody
var _flame: MeshInstance3D
var _engine: AudioStreamPlayer
var _engine_pb: AudioStreamGeneratorPlayback
var _engine_phase := 0.0
var _engine_freq := 50.0
var _steer := 0.0
var _was_on_floor := true
var _crash_cooldown := 0.0
var _squash := 0.0
var _boosting := false
## First-person cockpit (V switches to the chase camera)
var cockpit_cam: Camera3D
var _wheel: Node3D
var _needle: Node3D
var _bobble: Node3D
var _bobble_v := Vector2.ZERO
var _bobble_p := Vector2.ZERO
var _freshener: Node3D
var _look := Vector2.ZERO
var _look_idle := 0.0
var _prev_vel := Vector3.ZERO
const SHELL_LAYER := 8


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.35
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.1, 1.3, 4.0)
	shape.shape = box
	shape.position = Vector3(0, 0.8, 0)
	add_child(shape)
	_build_body()
	_build_cockpit()
	_build_bumper()
	_build_engine()
	Game.upgrades_changed.connect(_apply_upgrades)
	_apply_upgrades()


# --- stats from upgrades ----------------------------------------------------------------------

func max_speed() -> float:
	return 18.0 + Game.level("engine") * 3.5


func grip() -> float:
	return 6.5 + Game.level("tires") * 2.2


func crash_softness() -> float:
	return 1.0 - Game.level("suspension") * 0.22


func capacity() -> int:
	return Game.cargo_capacity()


func forward_speed() -> float:
	return velocity.dot(-global_basis.z)


# --- driving ---------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_crash_cooldown = maxf(0.0, _crash_cooldown - delta)
	var throttle := 0.0
	var steer_input := 0.0
	var handbrake := false
	_boosting = false
	if driving and not Game.in_dialogue:
		throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		steer_input = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		handbrake = Input.is_action_pressed("hop")     # SPACE: handbrake drift
		if Input.is_action_just_pressed("honk"):
			Sfx.honk(Game.level("horn"))
		if Game.has_upgrade("boost") and Input.is_action_pressed("boost") and boost_fuel > 0.0:
			_boosting = true
	boost_fuel = clampf(boost_fuel + (-0.45 if _boosting else 0.12) * delta, 0.0, 1.0)

	var forward := -global_basis.z
	var fwd := velocity.dot(forward)
	var on_floor := is_on_floor()
	var top := max_speed() * (1.45 if _boosting else 1.0)
	var accel := 15.0 + Game.level("engine") * 2.0 + (30.0 if _boosting else 0.0)
	if _boosting:
		throttle = 1.0
	if throttle > 0.0:
		fwd = move_toward(fwd, top, accel * throttle * delta) if fwd >= 0.0 else move_toward(fwd, 0.0, 32.0 * delta)
	elif throttle < 0.0:
		fwd = move_toward(fwd, -9.0, 32.0 * -throttle * delta) if fwd <= 0.5 else move_toward(fwd, 0.0, 32.0 * delta)
	else:
		fwd = move_toward(fwd, 0.0, (4.0 if driving else 12.0) * delta)
	if fwd > top:
		fwd = move_toward(fwd, top, 20.0 * delta)

	_steer = lerpf(_steer, steer_input, 1.0 - exp(-10.0 * delta))
	var steer_power := clampf(absf(fwd) / 6.0, 0.0, 1.0) * signf(fwd)
	var steer_rate := (2.3 + Game.level("tires") * 0.25) * (1.6 if handbrake else 1.0)
	if handbrake:
		fwd = move_toward(fwd, 0.0, 9.0 * delta)
	drifting = handbrake and absf(fwd) > 5.0
	rotate_y(_steer * steer_rate * steer_power * delta * (0.6 if not on_floor else 1.0))
	forward = -global_basis.z

	var lateral := velocity - forward * velocity.dot(forward)
	lateral.y = 0.0
	lateral = lateral.lerp(Vector3.ZERO, 1.0 - exp(-((1.1 if handbrake else grip()) if on_floor else 1.5) * delta))

	var vy := velocity.y
	if on_floor:
		vy = maxf(vy, -1.0)
	else:
		vy -= GRAVITY * delta

	var before := forward * fwd + lateral + Vector3(0, vy, 0)
	velocity = before
	move_and_slide()

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.6:
			continue
		var impact := -before.dot(n)
		if impact > 5.0 and _crash_cooldown <= 0.0:
			_crash_cooldown = 0.4
			velocity += n * impact * 0.6
			_squash = 0.4
			Sfx.play("bonk", clampf(1.4 - impact / 30.0, 0.6, 1.4))
			for p in cargo:
				p.data.damage = minf(100.0, float(p.data.damage) + impact * 1.6 * crash_softness())
			crashed.emit(impact)
	if on_floor and not _was_on_floor:
		_squash = 0.3
		for p in cargo:
			p.data.damage = minf(100.0, float(p.data.damage) + 1.5 * crash_softness())
	_was_on_floor = on_floor
	if global_position.y < -10.0:
		respawn_at(Vector3(0, 2, 0))


func respawn_at(p: Vector3, yaw := 0.0) -> void:
	global_position = p
	rotation = Vector3(0, yaw, 0)
	velocity = Vector3.ZERO


func set_driver(on: bool) -> void:
	driving = on
	_driver.visible = on


func _process(delta: float) -> void:
	var fwd := forward_speed()
	for w in _wheels:
		w.rotation.x -= fwd * delta / 0.45
	for w in _front_wheels:
		w.rotation.y = _steer * 0.5
	_squash = lerpf(_squash, 0.0, 1.0 - exp(-8.0 * delta))
	var lean := -_steer * clampf(absf(fwd) / max_speed(), 0.0, 1.0) * 0.16
	_visual.rotation.z = lerpf(_visual.rotation.z, lean, 0.15)
	_visual.rotation.x = lerpf(_visual.rotation.x, clampf(velocity.y * 0.03, -0.3, 0.3), 0.15)
	_visual.scale = Vector3(1.0 + _squash * 0.5, 1.0 - _squash, 1.0 + _squash * 0.5)
	var t := Time.get_ticks_msec() / 1000.0
	_rack.rotation.z = sin(t * 9.0) * 0.03 * clampf(absf(fwd) / 8.0, 0.0, 1.0) - lean
	(_rack.get_node("Slice") as Node3D).rotation.y = sin(t * 1.3) * 0.35
	_flame.visible = _boosting
	if _boosting:
		_flame.scale = Vector3(1, 1, randf_range(0.8, 1.4))
	_driver.speed = 0.0
	_update_cockpit(delta, fwd)
	_update_engine(fwd)


# --- cargo -----------------------------------------------------------------------------------

func load_pizza(p: Pizza) -> bool:
	if cargo.size() >= capacity():
		return false
	cargo.append(p)
	p.location = "car"
	_layout_cargo()
	return true


func unload_pizza(p: Pizza) -> void:
	cargo.erase(p)
	_layout_cargo()


func pizza_for_house(house: Node) -> Pizza:
	for p in cargo:
		var t := Game.ticket(p.data.ticket)
		if not t.is_empty() and t.house == house:
			return p
	return null


func _layout_cargo() -> void:
	for i in cargo.size():
		if i < _cargo_spots.size():
			cargo[i].reparent(_cargo_spots[i], false)
			cargo[i].position = Vector3.ZERO
			cargo[i].rotation = Vector3(0, 0.1 * (i % 2), 0)


func _apply_upgrades() -> void:
	var paint := Color(Upgrades.PAINTS[Game.level("paint") % Upgrades.PAINTS.size()])
	for mi in _paint_parts:
		mi.material_override = Toon.mat(paint.darkened(0.18) if mi.get_meta("darker", false) else paint, float(mi.get_meta("outline", 0.02)))
	# Roof rack grows with cargo capacity.
	for s in _cargo_spots:
		s.queue_free()
	_cargo_spots.clear()
	var cap := capacity()
	var columns := 1 if cap <= 3 else 2
	for i in cap:
		var spot := Node3D.new()
		var col := i % columns
		var row := i / columns
		spot.position = Vector3((col - (columns - 1) * 0.5) * 1.0, 0.18 + row * 0.15, 0.0)
		_rack.add_child(spot)
		_cargo_spots.append(spot)
	_layout_cargo()


# --- props: knock stuff over --------------------------------------------------------------------

func _build_bumper() -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 1.6, 4.6)
	cs.shape = box
	cs.position = Vector3(0, 0.8, 0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_prop_hit)


func _on_prop_hit(body: Node3D) -> void:
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		var speed := velocity.length()
		if speed < 1.5:
			return
		var away := rb.global_position - global_position
		away.y = 0.0
		var dir := (velocity.normalized() * 0.7 + away.normalized() * 0.3).normalized()
		rb.sleeping = false
		rb.apply_central_impulse((dir * speed * 1.1 + Vector3(0, speed * 0.6, 0)) * rb.mass)
		rb.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * rb.mass * speed * 0.3)
		Sfx.play("bonk", randf_range(1.5, 2.0), -6.0)


# --- looks ---------------------------------------------------------------------------------------

func _build_body() -> void:
	# Tony's delivery van: a soft, rounded little "bread van". One big friendly
	# rounded box with a red lower half, a cream upper half, a big windshield,
	# round headlights, tucked-in wheels and a giant pizza slice on the roof rack.
	_visual = Node3D.new()
	add_child(_visual)
	var cream := Color("#fff3df")
	var chrome := Color("#e3e9f0")
	var glass := Color("#7cc9ee")
	var rubber := Color("#2d2a32")
	var rb := func(size: Vector3, r: float) -> ArrayMesh: return Shapes.rounded_box(size, r)
	# Lower body (paint) and upper body (cream, hidden from the cockpit)
	_paint(rb.call(Vector3(2.04, 0.78, 3.96), 0.3), Vector3(0, 0.74, 0), 0.022)
	_shell(Toon.mesh(_visual, rb.call(Vector3(1.94, 1.0, 3.6), 0.42), Vector3(0, 1.45, 0.12), cream, 0.022))
	# Belt-line stripe where the two colors meet
	_paint(rb.call(Vector3(2.05, 0.05, 3.9), 0.025), Vector3(0, 1.13, 0.0), 0.0, true)
	# Glass: big windshield, front side windows (driver), small rear side windows, rear window
	_shell(Toon.mesh(_visual, rb.call(Vector3(1.62, 0.58, 0.06), 0.05), Vector3(0, 1.5, -1.66), glass, 0.0))
	_shell(Toon.mesh(_visual, rb.call(Vector3(1.2, 0.42, 0.06), 0.05), Vector3(0, 1.52, 1.93), glass, 0.0))
	for side: int in [-1, 1]:
		_shell(Toon.mesh(_visual, rb.call(Vector3(0.06, 0.5, 1.0), 0.05), Vector3(0.95 * side, 1.5, -0.92), glass, 0.0))
		_shell(Toon.mesh(_visual, rb.call(Vector3(0.06, 0.36, 0.7), 0.05), Vector3(0.95 * side, 1.55, 1.3), glass, 0.0))
		# Logo on the cargo side: a red circle with a pizza + lettering
		var logo := Node3D.new()
		logo.position = Vector3(0.985 * side, 1.48, 0.25)
		logo.rotation.y = PI / 2 * side
		_visual.add_child(logo)
		_shell(Toon.cyl(logo, 0.3, 0.3, 0.02, Vector3.ZERO, Color("#e63946"), 0.0, 20)).rotation.x = PI / 2
		_shell(Toon.cyl(logo, 0.24, 0.24, 0.025, Vector3(0, 0, 0.005), Color("#ffcf5c"), 0.0, 20)).rotation.x = PI / 2
		for pp: Vector2 in [Vector2(-0.08, 0.06), Vector2(0.09, 0.04), Vector2(0.0, -0.1)]:
			_shell(Toon.cyl(logo, 0.045, 0.045, 0.03, Vector3(pp.x, pp.y, 0.01), Color("#d63031"), 0.0, 10)).rotation.x = PI / 2
		var lbl := Toon.label(_visual, "TONY'S PIZZA", Vector3(1.03 * side, 0.82, 0.0), 24, Color("#ffd166"), false)
		lbl.rotation.y = PI / 2 * side
	# Wheels: tucked under, whitewalls, chrome hubcaps, dark wheel wells
	for x: int in [-1, 1]:
		for z: int in [-1, 1]:
			var well := Toon.mesh(_visual, rb.call(Vector3(0.3, 0.7, 1.0), 0.15), Vector3(0.9 * x, 0.55, 1.25 * z), Color("#3a2e3d"), 0.0)
			well.layers = 1
			var pivot := Node3D.new()
			pivot.position = Vector3(0.9 * x, 0.4, 1.25 * z)
			_visual.add_child(pivot)
			var spinner := Node3D.new()
			pivot.add_child(spinner)
			var tire := Toon.mesh(spinner, Shapes.smoothed(Shapes.cylinder(0.4, 0.4, 0.32, 20)), Vector3.ZERO, rubber, 0.012)
			tire.rotation.z = PI / 2
			var wall := Toon.cyl(spinner, 0.28, 0.28, 0.335, Vector3.ZERO, Color("#f6f4ef"), 0.0, 20)
			wall.rotation.z = PI / 2
			var hub := Toon.mesh(spinner, Shapes.smoothed(Shapes.cylinder(0.18, 0.2, 0.36, 16)), Vector3.ZERO, chrome, 0.0)
			hub.rotation.z = PI / 2
			Toon.ball(spinner, 0.05, Vector3(0.18 * x, 0, 0), Color("#e63946"), 0.0, 8)
			_wheels.append(spinner)
			if z == -1:
				_front_wheels.append(pivot)
	# Face of the van: round headlights, a little smiling grille, chrome bumpers
	for side: int in [-1, 1]:
		var rim := Toon.mesh(_visual, Shapes.smoothed(Shapes.cylinder(0.2, 0.2, 0.08, 20)), Vector3(0.64 * side, 0.78, -1.97), chrome, 0.008)
		rim.rotation.x = PI / 2
		var lens := MeshInstance3D.new()
		lens.mesh = Shapes.smoothed(Shapes.ball(0.16, 16, 8))
		lens.material_override = Toon.glow(Color("#fff6c8"), 1.5)
		lens.position = Vector3(0.64 * side, 0.78, -2.0)
		lens.scale = Vector3(1, 1, 0.4)
		_visual.add_child(lens)
		var sig := Toon.mesh(_visual, rb.call(Vector3(0.16, 0.08, 0.04), 0.03), Vector3(0.64 * side, 0.52, -1.98), Color("#ffb020"), 0.0)
		sig.material_override = Toon.glow(Color("#ffb020"), 0.8)
	var smile := Toon.mesh(_visual, rb.call(Vector3(0.5, 0.1, 0.04), 0.05), Vector3(0, 0.6, -1.99), Color("#3a2e3d"), 0.0)
	smile.rotation.x = 0.0
	Toon.mesh(_visual, rb.call(Vector3(0.12, 0.12, 0.04), 0.05), Vector3(0, 0.84, -1.99), Color("#ffd166"), 0.0)   # little "T" badge
	Toon.mesh(_visual, rb.call(Vector3(1.96, 0.16, 0.18), 0.07), Vector3(0, 0.36, -1.98), chrome, 0.01)
	Toon.mesh(_visual, rb.call(Vector3(1.96, 0.16, 0.18), 0.07), Vector3(0, 0.36, 1.98), chrome, 0.01)
	# Rear: tall rounded tail lights, door seam, plate, exhaust
	for side: int in [-1, 1]:
		var tl := Toon.mesh(_visual, rb.call(Vector3(0.18, 0.4, 0.06), 0.06), Vector3(0.8 * side, 0.85, 1.97), Color("#ff3b4e"), 0.0)
		tl.material_override = Toon.glow(Color("#ff3b4e"), 0.9)
	_shell(Toon.box(_visual, Vector3(0.02, 0.9, 0.02), Vector3(0, 1.45, 1.93), Color("#c9bda8"), 0.0))
	Toon.mesh(_visual, rb.call(Vector3(0.5, 0.2, 0.03), 0.04), Vector3(0, 0.7, 1.99), Color("#fff4c2"), 0.004)
	var plate := Toon.label(_visual, "PIZZA 1", Vector3(0, 0.7, 2.01), 15, Color("#2b1c18"), false)
	plate.outline_size = 0
	var pipe := Toon.cyl(_visual, 0.06, 0.06, 0.3, Vector3(-0.6, 0.32, 2.05), chrome, 0.006, 10)
	pipe.rotation.x = PI / 2
	# Side mirrors on short stalks by the front corners (you see them from the seat)
	for side: int in [-1, 1]:
		var stalk := Toon.cyl(_visual, 0.025, 0.025, 0.2, Vector3(1.04 * side, 1.3, -1.4), chrome, 0.0, 6)
		stalk.rotation.z = PI / 2
		var housing := Toon.mesh(_visual, rb.call(Vector3(0.09, 0.2, 0.16), 0.04), Vector3(1.16 * side, 1.32, -1.4), Color("#e63946"), 0.006)
		var face := Toon.box(_visual, Vector3(0.01, 0.15, 0.12), Vector3(1.16 * side, 1.32, -1.32), Color("#bfe7ff"), 0.0)
		face.rotation.y = PI / 2
		face.material_override = Toon.glow(Color("#bfe7ff"), 0.6)
	# Roof rack + a giant pizza slice sign
	_rack = Node3D.new()
	_rack.position = Vector3(0, 1.96, 0.45)
	_visual.add_child(_rack)
	for side: int in [-1, 1]:
		Toon.cyl(_rack, 0.03, 0.03, 2.4, Vector3(0.7 * side, 0.06, 0), chrome, 0.006, 6).rotation.x = PI / 2
	for z in [-1.1, 0.0, 1.1]:
		Toon.cyl(_rack, 0.03, 0.03, 1.4, Vector3(0, 0.06, z), chrome, 0.006, 6).rotation.z = PI / 2
	var sign_root := Node3D.new()
	sign_root.name = "Slice"
	sign_root.position = Vector3(0, 0.62, -1.15)
	_rack.add_child(sign_root)
	var slice := Toon.mesh(sign_root, Shapes.prism(Vector3(1.0, 0.95, 0.12)), Vector3.ZERO, Color("#ffcf5c"), 0.014)
	slice.rotation.z = PI
	Toon.mesh(sign_root, rb.call(Vector3(1.08, 0.16, 0.18), 0.07), Vector3(0, 0.48, 0), Color("#d98b3a"), 0.012)
	for pp: Vector3 in [Vector3(-0.15, 0.15, 0.07), Vector3(0.17, 0.12, 0.07), Vector3(0.0, -0.15, 0.07), Vector3(-0.15, 0.15, -0.07), Vector3(0.17, 0.12, -0.07), Vector3(0.0, -0.15, -0.07)]:
		var pep := Toon.cyl(sign_root, 0.08, 0.08, 0.02, pp, Color("#d63031"), 0.0, 10)
		pep.rotation.x = PI / 2
	# Rocket booster flame
	_flame = MeshInstance3D.new()
	_flame.mesh = Shapes.cylinder(0.0, 0.3, 1.2, 8)
	_flame.material_override = Toon.glow(Color("#ff8c42"), 3.0)
	_flame.rotation.x = -PI / 2
	_flame.position = Vector3(0, 0.6, 2.7)
	_flame.visible = false
	_visual.add_child(_flame)
	# You, behind the wheel (only seen from the chase camera)
	_driver = EggBody.new()
	_visual.add_child(_driver)
	var look: Dictionary = Characters.PLAYER_LOOK.duplicate()
	look.hat = Game.current_hat()
	_driver.build(look)
	_driver.scale = Vector3.ONE * 0.55
	_driver.position = Vector3(-0.4, 0.95, -0.75)
	_driver.rotation.y = PI
	_driver.visible = false
	for n in _driver.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = SHELL_LAYER


var _paint_parts: Array[MeshInstance3D] = []


func _soft(m: Mesh) -> ArrayMesh:
	return Shapes.smoothed(m)


## A body panel in the current paint color (recolored by the Paint Job upgrade).
func _paint(m: Mesh, pos: Vector3, outline: float, darker := false) -> MeshInstance3D:
	var mi := Toon.mesh(_visual, m, pos, Color("#c0392b"), outline)
	mi.set_meta("darker", darker)
	mi.set_meta("outline", outline)
	_paint_parts.append(mi)
	return mi


## Parts of the outside shell the cockpit camera looks through.
func _shell(mi: MeshInstance3D) -> MeshInstance3D:
	mi.layers = SHELL_LAYER
	return mi


# --- first-person cockpit ------------------------------------------------------------------------

var _gps: GpsScreen
var _grips: Array[Node3D] = []
var _arms: Array = []
var _speed_label: Label3D
var _lines: Control

func _build_cockpit() -> void:
	var c := Node3D.new()
	c.name = "Cockpit"
	c.position = Vector3(0, 0, -0.97)    # the driver sits up front in the van
	_visual.add_child(c)
	var dash := Color("#e9dcc6")
	var dash_dark := Color("#5b4a5e")
	var trim := Color("#c0392b")
	# Dashboard: soft cream top pad over a darker body, with a hood over the gauges
	Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(1.86, 0.3, 0.5), 0.4)), Vector3(0, 1.0, -0.5), dash_dark, 0.01)
	Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(1.86, 0.09, 0.46), 0.45)), Vector3(0, 1.28, -0.52), dash, 0.008)
	Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(0.5, 0.12, 0.22), 0.45)), Vector3(-0.35, 1.33, -0.42), dash_dark, 0.008)
	# Gauge cluster under the hood: speedometer (needle) + a little pizza-heat gauge
	var gauge := Toon.cyl(c, 0.1, 0.1, 0.02, Vector3(-0.42, 1.37, -0.31), Color("#fff8e7"), 0.006, 20)
	gauge.rotation.x = PI / 2 - 0.45
	for k in 9:
		var a := lerpf(1.9, -1.9, k / 8.0)
		var tick := Toon.box(c, Vector3(0.006, 0.02, 0.004), Vector3(-0.42 + sin(-a) * 0.08, 1.37 + cos(a) * 0.08 * 0.9, -0.3 + cos(a) * 0.02), Color("#2b1c18"), 0.0)
		tick.rotation = Vector3(-0.45, 0, a)
	_needle = Node3D.new()
	_needle.position = Vector3(-0.42, 1.37, -0.297)
	_needle.rotation.x = -0.45
	c.add_child(_needle)
	Toon.box(_needle, Vector3(0.01, 0.085, 0.006), Vector3(0, 0.038, 0), Color("#ff3b4e"), 0.0)
	var small := Toon.cyl(c, 0.055, 0.055, 0.02, Vector3(-0.25, 1.36, -0.31), Color("#fff8e7"), 0.005, 14)
	small.rotation.x = PI / 2 - 0.45
	_speed_label = Toon.label(c, "0", Vector3(-0.42, 1.335, -0.286), 26, Color("#2b1c18"), false)
	_speed_label.outline_size = 0
	_speed_label.pixel_size = 0.0022
	_speed_label.rotation.x = -0.45
	# GPS screen in the middle of the dash (the big one)
	var bezel := Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(0.46, 0.3, 0.05), 0.3)), Vector3(0.12, 1.26, -0.33), Color("#2d2a32"), 0.008)
	bezel.rotation.x = -0.35
	_gps = GpsScreen.new()
	c.add_child(_gps)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.26)
	screen.mesh = quad
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = _gps.get_texture()
	screen.material_override = sm
	screen.position = Vector3(0.12, 1.41, -0.3)
	screen.rotation.x = -0.35
	c.add_child(screen)
	# Radio + vents + hazard button on the center console
	Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(0.36, 0.08, 0.04), 0.4)), Vector3(0.12, 1.1, -0.27), Color("#3a3340"), 0.0)
	for k in 4:
		Toon.cyl(c, 0.018, 0.018, 0.02, Vector3(0.0 + k * 0.08, 1.14, -0.245), [Color("#ffd166"), Color("#06d6a0"), Color("#ff8fab"), Color("#8fd3f4")][k], 0.0, 8).rotation.x = PI / 2
	var hz := Toon.cyl(c, 0.025, 0.025, 0.02, Vector3(0.12, 1.05, -0.245), Color("#ff3b4e"), 0.0, 3)
	hz.rotation.x = PI / 2
	for x: float in [-0.8, 0.62]:
		for k in 3:
			Toon.box(c, Vector3(0.14, 0.012, 0.02), Vector3(x, 1.2 + k * 0.025, -0.255), Color("#2b1c18"), 0.0)
	# Glovebox
	Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(0.44, 0.16, 0.03), 0.4)), Vector3(0.55, 1.04, -0.255), dash, 0.006)
	Toon.box(c, Vector3(0.08, 0.02, 0.02), Vector3(0.55, 1.15, -0.24), Color("#c9bda8"), 0.0)
	# Steering wheel + your hands gripping it
	_wheel = Node3D.new()
	_wheel.position = Vector3(-0.35, 1.38, -0.08)
	_wheel.rotation.x = 1.0
	c.add_child(_wheel)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.13
	torus.outer_radius = 0.165
	torus.rings = 24
	torus.ring_segments = 8
	rim.mesh = torus
	rim.material_override = Toon.mat(Color("#3a3340"), 0.006)
	_wheel.add_child(rim)
	Toon.box(_wheel, Vector3(0.28, 0.03, 0.04), Vector3.ZERO, Color("#3a3340"), 0.0)
	var horn := Toon.cyl(_wheel, 0.055, 0.055, 0.04, Vector3.ZERO, trim, 0.004, 14)
	var tl := Toon.label(horn, "T", Vector3(0, 0.022, 0), 30, Color("#ffd166"), false)
	tl.rotation.x = -PI / 2
	tl.pixel_size = 0.0018
	tl.outline_size = 0
	for side: int in [-1, 1]:
		var grip := Node3D.new()
		grip.position = Vector3(0.15 * side, 0.02, 0.0)
		grip.rotation = Vector3(-PI / 2, 0.0, -0.5 * side)
		_wheel.add_child(grip)
		var built := EggBody.build_hand(grip, FpHands.SKIN, -float(side), 0.42, 0.005)
		EggBody.curl_hand(built[1], 1.0)
		_grips.append(grip)
		# Real arms: shoulder (just below your eyes) -> elbow -> wrist on the wheel
		var upper := Node3D.new()
		c.add_child(upper)
		Toon.mesh(upper, Shapes.smoothed(Shapes.limb(1.0, 0.055, 0.05, 10)), Vector3.ZERO, FpHands.SKIN.darkened(0.03), 0.005)
		var fore := Node3D.new()
		c.add_child(fore)
		Toon.mesh(fore, Shapes.smoothed(Shapes.limb(1.0, 0.05, 0.042, 10)), Vector3.ZERO, FpHands.SKIN, 0.005)
		_arms.append([upper, fore, float(side)])
	# Doors: inside panels with armrests and window frames
	for side: int in [-1, 1]:
		Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(0.08, 0.5, 1.9), 0.3)), Vector3(0.93 * side, 0.82, 0.45), dash_dark, 0.006)
		Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(0.12, 0.07, 0.7), 0.45)), Vector3(0.88 * side, 1.18, 0.5), dash, 0.005)
		Toon.box(c, Vector3(0.06, 0.06, 1.85), Vector3(0.95 * side, 1.29, 0.45), trim, 0.004)
		var pillar := Toon.box(c, Vector3(0.08, 0.72, 0.09), Vector3(0.88 * side, 1.6, -0.55), Color("#fff4e0"), 0.006)
		pillar.rotation.z = 0.16 * side
		pillar.rotation.x = -0.3
		Toon.box(c, Vector3(0.07, 0.6, 0.08), Vector3(0.94 * side, 1.58, 1.4), Color("#fff4e0"), 0.006)
	# Roof liner, header, sun visors, rear-view mirror + pizza air freshener
	Toon.box(c, Vector3(1.8, 0.1, 0.14), Vector3(0, 1.84, -0.55), Color("#fff4e0"), 0.006)
	Toon.box(c, Vector3(1.86, 0.04, 2.1), Vector3(0, 1.9, 0.45), Color("#f3e7d3"), 0.0)
	for side: int in [-1, 1]:
		var visor := Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(0.6, 0.03, 0.22), 0.4)), Vector3(0.42 * side, 1.88, -0.38), Color("#e9dcc6"), 0.006)
		visor.rotation.x = 0.15
	Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(0.3, 0.09, 0.04), 0.4)), Vector3(0, 1.78, -0.46), Color("#3a3340"), 0.005)
	var mirror := Toon.box(c, Vector3(0.26, 0.065, 0.01), Vector3(0, 1.825, -0.435), Color("#bfe7ff"), 0.0)
	mirror.material_override = Toon.glow(Color("#bfe7ff"), 0.6)
	_freshener = Node3D.new()
	_freshener.position = Vector3(0, 1.77, -0.43)
	c.add_child(_freshener)
	Toon.cyl(_freshener, 0.003, 0.003, 0.1, Vector3(0, -0.05, 0), Color("#f6f4ef"), 0.0, 3)
	var fr := Toon.mesh(_freshener, Shapes.prism(Vector3(0.08, 0.1, 0.01)), Vector3(0, -0.15, 0), Color("#f2c14e"), 0.004)
	fr.rotation.z = PI
	Toon.ball(_freshener, 0.012, Vector3(0.01, -0.13, 0.01), Color("#d63031"), 0.0, 5)
	# Passenger seat with the insulated pizza bag riding shotgun
	Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(0.6, 0.18, 0.6), 0.45)), Vector3(0.45, 0.82, 0.65), Color("#c0392b"), 0.008)
	var back := Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(0.6, 0.75, 0.16), 0.45)), Vector3(0.45, 0.95, 1.0), Color("#c0392b"), 0.008)
	back.rotation.x = -0.2
	Toon.mesh(c, _soft(Shapes.chamfer_box(Vector3(0.5, 0.2, 0.45), 0.35)), Vector3(0.45, 1.0, 0.62), Color("#2e86de"), 0.008)
	var bag_lbl := Toon.label(c, "HOT", Vector3(0.45, 1.11, 0.39), 30, Color("#ffd166"), false)
	bag_lbl.outline_size = 6
	# Bobblehead Tony on the dash
	_bobble = Node3D.new()
	_bobble.position = Vector3(0.62, 1.33, -0.48)
	c.add_child(_bobble)
	Toon.cyl(_bobble, 0.004, 0.004, 0.05, Vector3(0, 0.025, 0), Color("#7f8c8d"), 0.0, 3)
	var head := Toon.mesh(_bobble, _soft(Shapes.body_egg(0.12, 0.045, 0.01, 12, 8)), Vector3(0, 0.05, 0), Color("#f2d0a9"), 0.004)
	head.rotation.y = PI
	Toon.box(_bobble, Vector3(0.05, 0.008, 0.01), Vector3(0, 0.11, 0.035), Color("#3b2a22"), 0.0)
	Toon.cyl(_bobble, 0.03, 0.035, 0.025, Vector3(0, 0.16, 0), Color("#f6f4ef"), 0.0, 8)
	# The camera (your eyes)
	cockpit_cam = Camera3D.new()
	cockpit_cam.position = Vector3(-0.35, 1.64, 0.42)
	cockpit_cam.rotation.x = -0.1
	cockpit_cam.fov = 78.0
	cockpit_cam.near = 0.03
	cockpit_cam.far = 900.0
	cockpit_cam.cull_mask = 0xFFFFF & ~SHELL_LAYER & ~2
	c.add_child(cockpit_cam)
	# Anime speed lines when you're flooring it
	var layer := CanvasLayer.new()
	layer.layer = 2
	c.add_child(layer)
	_lines = Control.new()
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_speed_lines)
	layer.add_child(_lines)
	c.visible = false


func set_cockpit(on: bool) -> void:
	var c := _visual.get_node("Cockpit") as Node3D
	c.visible = on
	_driver.visible = driving and not on
	_gps.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	(_lines.get_parent() as CanvasLayer).visible = on
	if on:
		cockpit_cam.current = true
		_look = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if driving and cockpit_cam.current and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := (event as InputEventMouseMotion).relative * 0.0022 * Settings.mouse_sensitivity
		_look.x = clampf(_look.x - m.x, -1.6, 1.6)
		_look.y = clampf(_look.y - m.y, -0.6, 0.5)
		_look_idle = 0.0


var _cam_bump := 0.0
var _cam_bump_v := 0.0
var _speed_t := 0.0


func _update_cockpit(delta: float, fwd: float) -> void:
	if not driving or cockpit_cam == null or not cockpit_cam.current:
		return
	_wheel.rotation.z = lerp_angle(_wheel.rotation.z, _steer * 1.8, 1.0 - exp(-12.0 * delta))
	_update_arms()
	var speed01 := clampf(absf(fwd) / (max_speed() * 1.4), 0.0, 1.0)
	_needle.rotation.z = lerpf(1.9, -1.9, speed01) + sin(Time.get_ticks_msec() * 0.05) * 0.02 * clampf(absf(fwd), 0.0, 1.0)
	_speed_label.text = "%d" % int(absf(fwd) * 2.237)
	# Bobblehead + freshener react to acceleration (in car space)
	var acc := (velocity - _prev_vel) / maxf(delta, 0.001)
	_prev_vel = velocity
	var local_acc := global_basis.inverse() * acc
	var force := Vector2(-local_acc.x, -local_acc.z) * 0.004
	var h := minf(delta, 0.05) / 4.0
	for k in 4:
		_bobble_v += (force.limit_length(3.0) - _bobble_p * 90.0 - _bobble_v * 4.0) * h
		_bobble_p += _bobble_v * h
		# Seat suspension: bumps, landings and braking bob your head
		_cam_bump_v += (-_cam_bump * 160.0 - _cam_bump_v * 10.0 + clampf(-local_acc.y * 0.02 - _squash * 6.0, -4.0, 4.0)) * h
		_cam_bump += _cam_bump_v * h
	_bobble_p = _bobble_p.limit_length(0.6)
	if not _bobble_p.is_finite() or not is_finite(_cam_bump):
		_bobble_p = Vector2.ZERO
		_bobble_v = Vector2.ZERO
		_cam_bump = 0.0
		_cam_bump_v = 0.0
	_bobble.rotation = Vector3(_bobble_p.y, 0, -_bobble_p.x)
	_freshener.rotation = Vector3(_bobble_p.y * 1.4, 0, -_bobble_p.x * 1.4)
	# Look around (recenters on its own), glance into turns, lean, road shake
	_look_idle += delta
	if _look_idle > 1.2:
		_look = _look.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * delta))
	var look_pad := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var glance := _steer * 0.22 * clampf(absf(fwd) / 6.0, 0.0, 1.0)
	var lx := _look.x - look_pad.x * 1.2 + glance
	var shake := clampf(absf(fwd) / max_speed(), 0.0, 1.0) * 0.004 + (0.01 if _boosting else 0.0)
	var idle_rumble := sin(Time.get_ticks_msec() * 0.06) * 0.0015
	cockpit_cam.position = Vector3(-0.35 + _steer * 0.03 * speed01, 1.64 + _cam_bump * 0.05 + idle_rumble, 0.42)
	cockpit_cam.rotation = Vector3(-0.13 + _look.y + randf_range(-1, 1) * shake - _cam_bump * 0.02, lx, -_steer * 0.05 * speed01)
	cockpit_cam.fov = lerpf(cockpit_cam.fov, 76.0 + speed01 * 14.0 + (8.0 if _boosting else 0.0), 1.0 - exp(-4.0 * delta))
	_speed_t = move_toward(_speed_t, 1.0 if (speed01 > 0.62 or _boosting) else 0.0, delta * 2.5)
	_lines.queue_redraw()


## Two-bone arms from your shoulders to your hands on the wheel, so they stay
## attached however the wheel turns.
func _update_arms() -> void:
	var c := _visual.get_node("Cockpit") as Node3D
	var cam := cockpit_cam.position
	for k in _arms.size():
		var upper: Node3D = _arms[k][0]
		var fore: Node3D = _arms[k][1]
		var side: float = _arms[k][2]
		var sh := Vector3(cam.x + 0.22 * side, cam.y - 0.3, cam.z + 0.12)
		var hand := c.to_local(_grips[k].global_position)
		var l1 := 0.3
		var l2 := 0.33
		var to := hand - sh
		var d := clampf(to.length(), 0.05, l1 + l2 - 0.002)
		var dir := to.normalized()
		var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
		var hint := Vector3(side, -1.0, 0.2)
		var pole := (hint - dir * hint.dot(dir)).normalized()
		var elbow := sh + dir * a + pole * h
		_limb_between(upper, sh, elbow, l1)
		_limb_between(fore, elbow, hand, (hand - elbow).length())


func _limb_between(node: Node3D, from: Vector3, to: Vector3, length: float) -> void:
	var y := (from - to).normalized()      # limb meshes hang down -Y
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	node.transform = Transform3D(Basis(x, y * length, z), from)


func _draw_speed_lines() -> void:
	if _speed_t <= 0.01:
		return
	var size := _lines.size
	var c := size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_msec() / 50)
	for k in 46:
		var a := rng.randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		var r0 := size.length() * rng.randf_range(0.36, 0.46)
		var r1 := r0 + size.length() * rng.randf_range(0.08, 0.2)
		var w := rng.randf_range(1.5, 4.0)
		_lines.draw_line(c + dir * r0, c + dir * r1, Color(1, 1, 1, 0.55 * _speed_t), w)


## Main tells the GPS where to go (null = nothing to deliver right now).
func set_gps(town: Town, target: Variant, label: String) -> void:
	if _gps:
		_gps.town = town
		_gps.car = self
		_gps.target = target
		_gps.label = label


# --- engine noise ----------------------------------------------------------------------------------

func _build_engine() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.1
	_engine = AudioStreamPlayer.new()
	_engine.stream = gen
	_engine.volume_db = -18.0
	add_child(_engine)
	_engine.play()
	_engine_pb = _engine.get_stream_playback() as AudioStreamGeneratorPlayback


func _update_engine(fwd: float) -> void:
	if _engine_pb == null:
		return
	var target := (40.0 + absf(fwd) * 4.5 + (25.0 if _boosting else 0.0)) if driving else 32.0
	_engine.volume_db = -18.0 if driving else -30.0
	var frames := _engine_pb.get_frames_available()
	for i in frames:
		_engine_freq = lerpf(_engine_freq, target, 0.0005)
		_engine_phase = fmod(_engine_phase + _engine_freq / 22050.0, 1.0)
		var s := (_engine_phase * 2.0 - 1.0) * 0.5 + (0.3 if _engine_phase < 0.25 else -0.1)
		_engine_pb.push_frame(Vector2(s, s) * 0.5)
