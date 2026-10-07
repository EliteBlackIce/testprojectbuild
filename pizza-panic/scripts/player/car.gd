class_name PizzaCar
extends CharacterBody3D
## Arcade delivery car. Floaty, bouncy, drifty, and it can hop for no reason.
## Forward is -Z.

signal crashed(impact: float)

@export var max_speed := 24.0
@export var max_reverse := 9.0
@export var acceleration := 16.0
@export var brake_force := 32.0
@export var coast_drag := 4.0
@export var steer_rate := 2.6
@export var grip := 9.0
@export var drift_grip := 2.0
@export var hop_strength := 7.5
@export var gravity := 24.0

var controls_enabled := true
var _visual: Node3D
var _wheels: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
var _pizza_box: Node3D
var _engine: AudioStreamPlayer
var _engine_pb: AudioStreamGeneratorPlayback
var _engine_phase := 0.0
var _engine_freq := 60.0
var _steer := 0.0
var _was_on_floor := true
var _crash_cooldown := 0.0
var _squash := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.3
	_build_body()
	_build_bumper()
	_build_engine()


func forward_speed() -> float:
	return velocity.dot(-global_basis.z)


func _physics_process(delta: float) -> void:
	_crash_cooldown = maxf(0.0, _crash_cooldown - delta)
	var throttle := 0.0
	var steer_input := 0.0
	var hop := false
	if controls_enabled:
		throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		steer_input = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		hop = Input.is_action_just_pressed("hop")
		if Input.is_action_just_pressed("honk"):
			Sfx.play("honk", randf_range(0.95, 1.05))

	var forward := -global_basis.z
	var fwd := velocity.dot(forward)
	var on_floor := is_on_floor()

	# Gas / brake / reverse
	if throttle > 0.0:
		fwd = move_toward(fwd, max_speed, acceleration * throttle * delta) if fwd >= 0.0 else move_toward(fwd, 0.0, brake_force * delta)
	elif throttle < 0.0:
		fwd = move_toward(fwd, -max_reverse, brake_force * -throttle * delta) if fwd <= 0.5 else move_toward(fwd, 0.0, brake_force * delta)
	else:
		fwd = move_toward(fwd, 0.0, coast_drag * delta)

	# Steering scales with speed so you can't spin in place.
	_steer = lerpf(_steer, steer_input, 1.0 - exp(-10.0 * delta))
	var steer_power := clampf(absf(fwd) / 6.0, 0.0, 1.0) * signf(fwd)
	rotate_y(_steer * steer_rate * steer_power * delta * (0.6 if not on_floor else 1.0))
	forward = -global_basis.z

	# Kill sideways sliding (less grip in the air = drifty landings).
	var lateral := velocity - forward * velocity.dot(forward)
	lateral.y = 0.0
	lateral = lateral.lerp(Vector3.ZERO, 1.0 - exp(-(grip if on_floor else drift_grip) * delta))

	var vy := velocity.y
	if on_floor:
		vy = maxf(vy, -1.0)
		if hop:
			vy = hop_strength
			Sfx.play("boing", randf_range(0.9, 1.15))
			_squash = -0.35
	else:
		vy -= gravity * delta

	var before := forward * fwd + lateral + Vector3(0, vy, 0)
	velocity = before
	move_and_slide()

	# Bonk detection: big head-on hits hurt the pizza and bounce you off.
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
			crashed.emit(impact)

	if on_floor and not _was_on_floor:
		_squash = 0.3
	_was_on_floor = on_floor

	if global_position.y < -10.0:
		respawn_at(Vector3(0, 2, 0))


func respawn_at(p: Vector3, yaw := 0.0) -> void:
	global_position = p
	rotation = Vector3(0, yaw, 0)
	velocity = Vector3.ZERO


func _process(delta: float) -> void:
	var fwd := forward_speed()
	# Wheels spin, front wheels steer.
	for w in _wheels:
		w.rotation.x -= fwd * delta / 0.45
	for w in _front_wheels:
		w.rotation.y = _steer * 0.5
	# Body leans into turns, pitches with acceleration, squashes on landings.
	_squash = lerpf(_squash, 0.0, 1.0 - exp(-8.0 * delta))
	var lean := -_steer * clampf(absf(fwd) / max_speed, 0.0, 1.0) * 0.18
	_visual.rotation.z = lerpf(_visual.rotation.z, lean, 0.15)
	_visual.rotation.x = lerpf(_visual.rotation.x, clampf(velocity.y * 0.03, -0.3, 0.3), 0.15)
	_visual.scale = Vector3(1.0 + _squash * 0.5, 1.0 - _squash, 1.0 + _squash * 0.5)
	# The pizza box on the roof wobbles like it's barely holding on.
	var t := Time.get_ticks_msec() / 1000.0
	_pizza_box.rotation.z = sin(t * 9.0) * 0.04 * clampf(absf(fwd) / 8.0, 0.2, 1.0) - lean
	_pizza_box.position.y = 1.95 + absf(sin(t * 7.0)) * 0.05
	_update_engine(fwd)


# --- props: knock stuff over -----------------------------------------------------------

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
		var away := (rb.global_position - global_position)
		away.y = 0.0
		var dir := (velocity.normalized() * 0.7 + away.normalized() * 0.3).normalized()
		rb.sleeping = false
		rb.apply_central_impulse((dir * speed * 1.1 + Vector3(0, speed * 0.6, 0)) * rb.mass)
		rb.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * rb.mass * speed * 0.3)
		Sfx.play("bonk", randf_range(1.5, 2.0), -6.0)


# --- looks -----------------------------------------------------------------------------

func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.2, 3.8)
	shape.shape = box
	shape.position = Vector3(0, 0.75, 0)
	add_child(shape)

	_visual = Node3D.new()
	add_child(_visual)
	var red := Color("#e63946")
	Toon.box(_visual, Vector3(2.0, 0.8, 3.8), Vector3(0, 0.75, 0), red, 0.05)
	Toon.box(_visual, Vector3(1.8, 0.75, 2.0), Vector3(0, 1.45, 0.35), Color("#f1faee"), 0.05)
	# Windshield + windows
	Toon.box(_visual, Vector3(1.6, 0.55, 0.08), Vector3(0, 1.45, -0.66), Color("#a8dadc"), 0.0)
	for side: int in [-1, 1]:
		Toon.box(_visual, Vector3(0.08, 0.5, 1.6), Vector3(0.91 * side, 1.47, 0.35), Color("#a8dadc"), 0.0)
	# Bumpers, headlights, tail lights
	Toon.box(_visual, Vector3(2.1, 0.3, 0.3), Vector3(0, 0.45, -1.95), Color("#adb5bd"), 0.03)
	Toon.box(_visual, Vector3(2.1, 0.3, 0.3), Vector3(0, 0.45, 1.95), Color("#adb5bd"), 0.03)
	for side: int in [-1, 1]:
		Toon.sphere(_visual, 0.2, Vector3(0.65 * side, 0.8, -1.88), Color("#fff3b0"), 0.02).material_override = Toon.mat(Color("#fff3b0"), 0.02, false, 1.2)
		Toon.box(_visual, Vector3(0.4, 0.2, 0.08), Vector3(0.7 * side, 0.85, 1.92), Color("#d00000"), 0.0)
	# Googly eyes on the hood, because of course.
	for side: int in [-1, 1]:
		Toon.sphere(_visual, 0.24, Vector3(0.45 * side, 1.18, -1.2), Color.WHITE, 0.02)
		var pupil := Toon.sphere(_visual, 0.12, Vector3(0.45 * side, 1.2, -1.42), Color("#111111"), 0.0)
		pupil.material_override = Toon.pupil_mat()
	# Wheels
	for x: int in [-1, 1]:
		for z: int in [-1, 1]:
			var pivot := Node3D.new()
			pivot.position = Vector3(1.0 * x, 0.45, 1.25 * z)
			_visual.add_child(pivot)
			var spinner := Node3D.new()
			pivot.add_child(spinner)
			var tire := Toon.cylinder(spinner, 0.45, 0.45, 0.35, Vector3.ZERO, Color("#212529"), 0.03)
			tire.rotation.z = PI / 2
			var hub := Toon.cylinder(spinner, 0.2, 0.2, 0.37, Vector3.ZERO, Color("#ffd166"), 0.0)
			hub.rotation.z = PI / 2
			_wheels.append(spinner)
			if z == -1:
				_front_wheels.append(pivot)
	# Giant pizza box on the roof
	_pizza_box = Node3D.new()
	_pizza_box.position = Vector3(0, 1.95, 0.35)
	_visual.add_child(_pizza_box)
	Toon.box(_pizza_box, Vector3(1.7, 0.25, 1.7), Vector3.ZERO, Color("#f4e1c1"), 0.04)
	var sign_board := Toon.box(_pizza_box, Vector3(1.9, 0.7, 0.12), Vector3(0, 0.5, 0), Color("#ffd166"), 0.04)
	sign_board.rotation.y = 0.0
	Toon.label(_pizza_box, "PIZZA!", Vector3(0, 0.5, 0.08), 70, Color("#d62828"), false)
	var back := Toon.label(_pizza_box, "PIZZA!", Vector3(0, 0.5, -0.08), 70, Color("#d62828"), false)
	back.rotation.y = PI


# --- engine noise ------------------------------------------------------------------------

func _build_engine() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.1
	_engine = AudioStreamPlayer.new()
	_engine.stream = gen
	_engine.volume_db = -16.0
	add_child(_engine)
	_engine.play()
	_engine_pb = _engine.get_stream_playback() as AudioStreamGeneratorPlayback


func _update_engine(fwd: float) -> void:
	if _engine_pb == null:
		return
	var target := 45.0 + absf(fwd) * 5.0 + (20.0 if Input.is_action_pressed("accelerate") and controls_enabled else 0.0)
	var frames := _engine_pb.get_frames_available()
	for i in frames:
		_engine_freq = lerpf(_engine_freq, target, 0.0005)
		_engine_phase = fmod(_engine_phase + _engine_freq / 22050.0, 1.0)
		var s := (_engine_phase * 2.0 - 1.0) * 0.5 + (0.3 if _engine_phase < 0.25 else -0.1)
		_engine_pb.push_frame(Vector2(s, s) * 0.5)
