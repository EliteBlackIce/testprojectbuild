class_name PizzaCar
extends CharacterBody3D
## The delivery car. Arcade handling, upgradeable, carries pizza boxes on a
## roof rack, and has googly eyes on the hood. Forward is -Z.

signal crashed(impact: float)

const GRAVITY := 24.0

var driving := false            ## true while the player is in the driver's seat
var cargo: Array[Pizza] = []
var boost_fuel := 1.0

var _visual: Node3D
var _body_mesh: MeshInstance3D
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
	var hop := false
	_boosting = false
	if driving and not Game.in_dialogue:
		throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		steer_input = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		hop = Input.is_action_just_pressed("hop")
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
	var steer_rate := 2.3 + Game.level("tires") * 0.25
	rotate_y(_steer * steer_rate * steer_power * delta * (0.6 if not on_floor else 1.0))
	forward = -global_basis.z

	var lateral := velocity - forward * velocity.dot(forward)
	lateral.y = 0.0
	lateral = lateral.lerp(Vector3.ZERO, 1.0 - exp(-(grip() if on_floor else 1.5) * delta))

	var vy := velocity.y
	if on_floor:
		vy = maxf(vy, -1.0)
		if hop:
			vy = 7.5
			Sfx.play("boing", randf_range(0.9, 1.15))
			_squash = -0.35
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
	_body_mesh.material_override = Toon.mat(paint, 0.02)
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
	_visual = Node3D.new()
	add_child(_visual)
	var cream := Color("#f1e6d0")
	var trim := Color("#3b2a22")
	# Chunky chamfered body + cabin
	_body_mesh = Toon.block(_visual, Vector3(2.1, 0.85, 3.9), Vector3(0, 0.38, 0), Color("#c0392b"), 0.18, 0.025)
	Toon.block(_visual, Vector3(1.85, 0.8, 2.0), Vector3(0, 1.15, 0.45), cream, 0.16, 0.022).layers = SHELL_LAYER
	# Windows (the cockpit camera looks straight through these)
	for z in [-0.55, 1.45]:
		Toon.box(_visual, Vector3(1.55, 0.5, 0.06), Vector3(0, 1.5, z), Color("#9cc9d9"), 0.0).layers = SHELL_LAYER
	for side: int in [-1, 1]:
		Toon.box(_visual, Vector3(0.06, 0.45, 1.5), Vector3(0.93 * side, 1.52, 0.45), Color("#9cc9d9"), 0.0).layers = SHELL_LAYER
		# Side logo
		var logo := Toon.label(_visual, "TONY'S", Vector3(1.06 * side, 0.82, 0.2), 60, Color("#ffd166"), false)
		logo.rotation.y = PI / 2 * side
	# Bumpers, lights
	Toon.block(_visual, Vector3(2.2, 0.3, 0.3), Vector3(0, 0.28, -2.0), Color("#9aa3ab"), 0.3, 0.012)
	Toon.block(_visual, Vector3(2.2, 0.3, 0.3), Vector3(0, 0.28, 1.95), Color("#9aa3ab"), 0.3, 0.012)
	for side: int in [-1, 1]:
		var hl := MeshInstance3D.new()
		hl.mesh = Shapes.ball(0.17, 8, 4)
		hl.material_override = Toon.glow(Color("#fff3b0"), 1.5)
		hl.position = Vector3(0.68 * side, 0.85, -1.93)
		_visual.add_child(hl)
		Toon.box(_visual, Vector3(0.4, 0.18, 0.06), Vector3(0.7 * side, 0.85, 1.96), Color("#d00000"), 0.0)
	# Googly eyes on the hood
	for side: int in [-1, 1]:
		Toon.ball(_visual, 0.24, Vector3(0.45 * side, 1.05, -1.25), Color("#fbf6ee"), 0.012, 10)
		Toon.ball(_visual, 0.11, Vector3(0.45 * side, 1.07, -1.47), Color("#1d1517"), 0.0, 8)
	# Wheels
	for x: int in [-1, 1]:
		for z: int in [-1, 1]:
			var pivot := Node3D.new()
			pivot.position = Vector3(1.0 * x, 0.42, 1.3 * z)
			_visual.add_child(pivot)
			var spinner := Node3D.new()
			pivot.add_child(spinner)
			var tire := Toon.cyl(spinner, 0.44, 0.44, 0.36, Vector3.ZERO, trim, 0.015, 10)
			tire.rotation.z = PI / 2
			var hub := Toon.cyl(spinner, 0.2, 0.2, 0.38, Vector3.ZERO, Color("#ffd166"), 0.0, 6)
			hub.rotation.z = PI / 2
			_wheels.append(spinner)
			if z == -1:
				_front_wheels.append(pivot)
	# Roof rack with the giant pizza sign
	_rack = Node3D.new()
	_rack.position = Vector3(0, 1.58, 0.45)
	_visual.add_child(_rack)
	Toon.box(_rack, Vector3(1.7, 0.06, 1.8), Vector3(0, 0.0, 0), Color("#555b61"), 0.01).layers = SHELL_LAYER
	var sign_root := Node3D.new()
	sign_root.position = Vector3(0, 0.75, -0.95)
	_rack.add_child(sign_root)
	Toon.block(sign_root, Vector3(1.5, 0.55, 0.14), Vector3(0, -0.27, 0), Color("#ffd166"), 0.2, 0.012)
	Toon.label(sign_root, "PIZZA!", Vector3(0, 0, -0.08), 64, Color("#c0392b"), false).rotation.y = PI
	Toon.label(sign_root, "PIZZA!", Vector3(0, 0, 0.08), 64, Color("#c0392b"), false)
	# Rocket booster flame
	_flame = MeshInstance3D.new()
	_flame.mesh = Shapes.cylinder(0.0, 0.3, 1.2, 6)
	_flame.material_override = Toon.glow(Color("#ff8c42"), 3.0)
	_flame.rotation.x = -PI / 2
	_flame.position = Vector3(0, 0.6, 2.7)
	_flame.visible = false
	_visual.add_child(_flame)
	# You, behind the wheel
	_driver = EggBody.new()
	_visual.add_child(_driver)
	var look: Dictionary = Characters.PLAYER_LOOK.duplicate()
	look.hat = Game.current_hat()
	_driver.build(look)
	_driver.scale = Vector3.ONE * 0.6
	_driver.position = Vector3(-0.35, 0.82, 0.2)
	_driver.rotation.y = PI
	_driver.visible = false
	for n in _driver.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = SHELL_LAYER


# --- first-person cockpit ------------------------------------------------------------------------

func _build_cockpit() -> void:
	var c := Node3D.new()
	c.name = "Cockpit"
	_visual.add_child(c)
	var dash := Color("#3d3430")
	# Dashboard, glovebox, little vents
	Toon.block(c, Vector3(1.8, 0.28, 0.38), Vector3(0, 1.05, -0.42), dash, 0.1, 0.012)
	Toon.block(c, Vector3(1.75, 0.06, 0.3), Vector3(0, 1.33, -0.44), Color("#4b403b"), 0.03, 0.008)
	for k in 3:
		Toon.box(c, Vector3(0.14, 0.05, 0.02), Vector3(0.15 + k * 0.2, 1.25, -0.22), Color("#1d1517"), 0.0)
	Toon.box(c, Vector3(0.4, 0.1, 0.02), Vector3(0.45, 1.13, -0.22), Color("#58493f"), 0.004)
	# Speedometer with a wobbly needle
	var gauge := Toon.cyl(c, 0.12, 0.12, 0.02, Vector3(0.02, 1.3, -0.3), Color("#fff8e7"), 0.006, 14)
	gauge.rotation.x = PI / 2 - 0.5
	_needle = Node3D.new()
	_needle.position = Vector3(0.02, 1.3, -0.285)
	_needle.rotation.x = -0.5
	c.add_child(_needle)
	Toon.box(_needle, Vector3(0.012, 0.1, 0.006), Vector3(0, 0.045, 0), Color("#e63946"), 0.0)
	var mph := Toon.label(c, "MPH", Vector3(0.02, 1.25, -0.27), 18, Color("#2b1c18"), false)
	mph.outline_size = 0
	mph.pixel_size = 0.003
	mph.rotation.x = -0.5
	# Steering wheel + your mittens on it
	_wheel = Node3D.new()
	_wheel.position = Vector3(-0.35, 1.38, -0.08)
	_wheel.rotation.x = 1.0
	c.add_child(_wheel)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.13
	torus.outer_radius = 0.165
	torus.rings = 16
	torus.ring_segments = 6
	rim.mesh = torus
	rim.material_override = Toon.mat(Color("#2d3436"), 0.006)
	_wheel.add_child(rim)
	Toon.box(_wheel, Vector3(0.28, 0.03, 0.04), Vector3.ZERO, Color("#2d3436"), 0.0)
	Toon.cyl(_wheel, 0.05, 0.05, 0.04, Vector3.ZERO, Color("#e63946"), 0.004, 10)
	for side: int in [-1, 1]:
		# Hands gripping the rim (fingers wrapped around it)
		var grip := Node3D.new()
		grip.position = Vector3(0.15 * side, 0.02, 0.0)
		grip.rotation = Vector3(-PI / 2, 0.0, -0.5 * side)
		_wheel.add_child(grip)
		var built := EggBody.build_hand(grip, FpHands.SKIN, -float(side), 0.42, 0.005)
		EggBody.curl_hand(built[1], 1.0)
		var arm := Toon.mesh(_wheel, Shapes.limb(0.45, 0.05, 0.045, 8), Vector3(0.16 * side, 0.03, 0.0), FpHands.SKIN.darkened(0.04), 0.006)
		arm.rotation = Vector3(-0.3, 0.0, -0.4 * side)
	# Pillars + roof edge frame the windshield
	for side: int in [-1, 1]:
		var pillar := Toon.box(c, Vector3(0.08, 0.72, 0.08), Vector3(0.88 * side, 1.6, -0.5), Color("#f1e6d0"), 0.006)
		pillar.rotation.z = 0.18 * side
	Toon.box(c, Vector3(1.8, 0.1, 0.12), Vector3(0, 1.93, -0.5), Color("#f1e6d0"), 0.006)
	Toon.box(c, Vector3(1.8, 0.05, 2.0), Vector3(0, 1.97, 0.45), Color("#e6d8bd"), 0.0)
	# Rear-view mirror + a pizza-slice air freshener
	Toon.box(c, Vector3(0.28, 0.08, 0.03), Vector3(0, 1.84, -0.45), Color("#2d3436"), 0.004)
	Toon.box(c, Vector3(0.25, 0.06, 0.01), Vector3(0, 1.84, -0.43), Color("#a8d8ea"), 0.0)
	_freshener = Node3D.new()
	_freshener.position = Vector3(0, 1.8, -0.43)
	c.add_child(_freshener)
	Toon.cyl(_freshener, 0.003, 0.003, 0.1, Vector3(0, -0.05, 0), Color("#f6f4ef"), 0.0, 3)
	var slice := Toon.mesh(_freshener, Shapes.prism(Vector3(0.08, 0.1, 0.01)), Vector3(0, -0.15, 0), Color("#f2c14e"), 0.004)
	slice.rotation.z = PI
	Toon.ball(_freshener, 0.012, Vector3(0.01, -0.13, 0.01), Color("#c0392b"), 0.0, 5)
	# Bobblehead egg on the dash (Tony, obviously)
	_bobble = Node3D.new()
	_bobble.position = Vector3(0.35, 1.36, -0.45)
	c.add_child(_bobble)
	Toon.cyl(_bobble, 0.004, 0.004, 0.05, Vector3(0, 0.025, 0), Color("#7f8c8d"), 0.0, 3)
	var head := Toon.mesh(_bobble, Shapes.body_egg(0.12, 0.045, 0.01, 10, 7), Vector3(0, 0.05, 0), Color("#e8b77a"), 0.004)
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
	c.visible = false


func set_cockpit(on: bool) -> void:
	(_visual.get_node("Cockpit") as Node3D).visible = on
	_driver.visible = driving and not on
	if on:
		cockpit_cam.current = true
		_look = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if driving and cockpit_cam.current and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := (event as InputEventMouseMotion).relative * 0.0022 * Settings.mouse_sensitivity
		_look.x = clampf(_look.x - m.x, -1.6, 1.6)
		_look.y = clampf(_look.y - m.y, -0.6, 0.5)
		_look_idle = 0.0


func _update_cockpit(delta: float, fwd: float) -> void:
	if not driving or cockpit_cam == null or not cockpit_cam.current:
		return
	_wheel.rotation.z = lerp_angle(_wheel.rotation.z, _steer * 1.8, 1.0 - exp(-12.0 * delta))
	_needle.rotation.z = lerpf(1.9, -1.9, clampf(absf(fwd) / (max_speed() * 1.4), 0.0, 1.0)) + sin(Time.get_ticks_msec() * 0.05) * 0.02 * clampf(absf(fwd), 0.0, 1.0)
	# Bobblehead + freshener react to acceleration (in car space)
	var acc := (velocity - _prev_vel) / maxf(delta, 0.001)
	_prev_vel = velocity
	var local_acc := global_basis.inverse() * acc
	var force := Vector2(-local_acc.x, -local_acc.z) * 0.004
	var h := minf(delta, 0.05) / 4.0
	for k in 4:
		_bobble_v += (force.limit_length(3.0) - _bobble_p * 90.0 - _bobble_v * 4.0) * h
		_bobble_p += _bobble_v * h
	_bobble_p = _bobble_p.limit_length(0.6)
	if not _bobble_p.is_finite():
		_bobble_p = Vector2.ZERO
		_bobble_v = Vector2.ZERO
	_bobble.rotation = Vector3(_bobble_p.y, 0, -_bobble_p.x)
	_freshener.rotation = Vector3(_bobble_p.y * 1.4, 0, -_bobble_p.x * 1.4)
	# Look around (recenters on its own), lean into turns, little road shake
	_look_idle += delta
	if _look_idle > 1.2:
		_look = _look.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * delta))
	var look_pad := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var lx := _look.x - look_pad.x * 1.2
	var shake := clampf(absf(fwd) / max_speed(), 0.0, 1.0) * 0.004
	cockpit_cam.rotation = Vector3(-0.13 + _look.y + randf_range(-1, 1) * shake, lx - _steer * 0.12, -_steer * 0.03)


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
