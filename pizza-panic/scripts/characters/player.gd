class_name PlayerEgg
extends CharacterBody3D
## You, in first person: an egg in a delivery cap. Mouse to look, WASD to waddle,
## Space to hop, E (or click) on whatever's under the crosshair, click on
## nothing to poke it. Slip on sauce. Get hit by cars. Wobble back up.
##
## Your egg body still exists (others see it, it casts a shadow); your own
## camera just doesn't render it. What you see is the FpHands viewmodel.

signal focus_changed(target: Interactable)

const WALK_SPEED := 3.7
const ACCEL := 26.0
const AIR_ACCEL := 8.0
const GRAVITY := 20.0
const JUMP := 5.6
const EYE := 1.5
const BODY_LAYER := 2
const VIEWMODEL_LAYER := 4
const MAX_PITCH := 1.45

var body: EggBody
var head: Node3D
var camera: Camera3D
var hands: FpHands
var controls_enabled := true
## The thing held in front of you (a Pizza, usually). null when empty-handed.
var held: Node3D = null
var chaos_held: Throwable = null    ## a grabbed prop (thrown with CLICK)
var chaos_focus: Throwable = null   ## the prop you're looking at
var gravity_mult := 1.0             ## day mutators tweak these
var accel_mult := 1.0
var speed_mult := 1.0
var focus: Interactable = null
var yaw := 0.0
var pitch := -0.1
## Work mode: the camera floats to a station's view (see enter_view).
var in_view := false

var _view_xform := Transform3D.IDENTITY
var _view_fov := 60.0
var _view_blend := 0.0
var _look_lock: Variant = null     ## Vector3 to turn toward (conversations)
var _phase := 0.0
var _step_side := 0
var _dip := 0.0
var _dip_vel := 0.0
var _was_floor := true
var _fall_speed := 0.0
var _tumble := 0.0
var _tumble_side := 1.0
var _slip_cooldown := 0.0
var _poke_cooldown := 0.0
var _ray_excludes: Array[RID] = []


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	add_to_group("door_pushers")
	add_to_group("player")
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	head = Node3D.new()
	head.position = Vector3(0, EYE, 0)
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.04
	camera.far = 900.0
	camera.cull_mask = 0xFFFFF & ~BODY_LAYER
	head.add_child(camera)
	hands = FpHands.new()
	camera.add_child(hands)
	_ray_excludes = [get_rid()]
	rebuild_look()
	Game.upgrades_changed.connect(rebuild_look)


func rebuild_look() -> void:
	if body:
		body.queue_free()
	var look: Dictionary = Characters.PLAYER_LOOK.duplicate()
	look.hat = Game.current_hat()
	body = EggBody.new()
	add_child(body)
	body.build(look)
	body.idle_fidgets = false
	body.rotation.y = PI   # eggs face +Z, cameras look down -Z
	for n in body.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = BODY_LAYER


func speed() -> float:
	return (WALK_SPEED + Game.level("sneakers") * 0.8) * speed_mult


# --- looking -------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and can_look():
		var m := (event as InputEventMouseMotion).relative * 0.0022 * Settings.mouse_sensitivity
		yaw -= m.x
		pitch = clampf(pitch - m.y, -MAX_PITCH, MAX_PITCH)
		hands.add_sway((event as InputEventMouseMotion).relative)


func can_look() -> bool:
	return controls_enabled and not in_view and _tumble <= 0.0 and _look_lock == null


## Smoothly turn your head toward a point (and keep looking) until clear_look().
func look_at_point(p: Vector3) -> void:
	_look_lock = p


func clear_look() -> void:
	_look_lock = null


## Snap the view to face a direction (used when spawning / getting out of the car).
func face(dir_yaw: float, dir_pitch := -0.1) -> void:
	yaw = dir_yaw
	pitch = dir_pitch


## Float the camera to a fixed station view (prep table, cutting board...).
func enter_view(xform: Transform3D, fov := 55.0) -> void:
	_view_xform = xform
	_view_fov = fov
	in_view = true


func exit_view() -> void:
	in_view = false


func view_settled() -> bool:
	return in_view and _view_blend > 0.97


func forward() -> Vector3:
	return -camera.global_basis.z


# --- moving ------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_slip_cooldown = maxf(0.0, _slip_cooldown - delta)
	_poke_cooldown = maxf(0.0, _poke_cooldown - delta)
	var active := controls_enabled and not in_view and _tumble <= 0.0
	var input := Vector2.ZERO
	if active:
		input = Input.get_vector("steer_left", "steer_right", "accelerate", "brake")
		var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if look.length() > 0.05 and _look_lock == null:
			yaw -= look.x * 2.6 * delta * Settings.mouse_sensitivity
			pitch = clampf(pitch - look.y * 1.8 * delta * Settings.mouse_sensitivity, -MAX_PITCH, MAX_PITCH)
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	var target := dir * speed()
	if held:
		target *= 0.9
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(target, (ACCEL if is_on_floor() else AIR_ACCEL) * accel_mult * delta)
	if _tumble > 0.0:
		hv = hv.move_toward(Vector3.ZERO, 6.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = maxf(velocity.y, -1.0)
		if active and Input.is_action_just_pressed("hop"):
			velocity.y = JUMP / sqrt(gravity_mult) * (0.75 if gravity_mult < 1.0 else 1.0)
			body.hop()
			_dip_vel = 1.2
			Sfx.play("boing", randf_range(1.25, 1.45), -9.0)
	else:
		velocity.y -= GRAVITY * gravity_mult * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	move_and_slide()
	var on_floor := is_on_floor()
	if on_floor and not _was_floor:
		var hit := clampf(_fall_speed / 9.0, 0.15, 1.0)
		_dip_vel -= hit * 2.2
		hands.landed(hit)
		Sfx.play("step", 0.7, -8.0)
	if on_floor:
		_fall_speed = 0.0
	_was_floor = on_floor
	if global_position.y < -20.0:
		global_position = Vector3(0, 2, 0)
	var moving := clampf(hv.length() / WALK_SPEED, 0.0, 1.4)
	# Body faces where you look; legs waddle with real velocity.
	rotation.y = yaw
	body.velocity_hint = velocity
	hands.moving = moving if on_floor else 0.0
	hands.grounded = on_floor
	_steps(delta, moving, on_floor)
	_check_slip(hv)
	_update_focus()
	_update_chaos_focus()


func _steps(delta: float, moving: float, on_floor: bool) -> void:
	if not on_floor or moving < 0.15:
		return
	_phase += delta * (5.5 + moving * 4.0)
	var side := int(floor(_phase / PI))
	if side != _step_side:
		_step_side = side
		Sfx.play("step", randf_range(0.85, 1.15), -16.0)


func _process(delta: float) -> void:
	# Landing / hop dip spring
	var h := minf(delta, 0.05) / 4.0
	for k in 4:
		var acc := -_dip * 120.0 - _dip_vel * 12.0
		_dip_vel += acc * h
		_dip += _dip_vel * h
	if not is_finite(_dip) or not is_finite(_dip_vel):
		_dip = 0.0
		_dip_vel = 0.0
	if _look_lock != null:
		var to: Vector3 = (_look_lock as Vector3) - head.global_position
		var want_yaw := atan2(-to.x, -to.z)
		var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
		yaw = lerp_angle(yaw, want_yaw, 1.0 - exp(-6.0 * delta))
		pitch = lerpf(pitch, clampf(want_pitch, -0.8, 0.8), 1.0 - exp(-6.0 * delta))
	rotation.y = yaw
	var moving := hands.moving
	# Egg waddle: the view bobs and rolls side to side as you walk.
	var bob := Vector3(sin(_phase * 0.5) * 0.025 * moving, -absf(sin(_phase)) * 0.04 * moving, 0.0)
	var roll := sin(_phase * 0.5) * 0.022 * moving
	var head_y := EYE + _dip * 0.06
	if _tumble > 0.0:
		_tumble -= delta
		var u := 1.0 - clampf(_tumble / 2.2, 0.0, 1.0)
		var down := clampf(u * 5.0, 0.0, 1.0) * (1.0 - clampf((u - 0.7) / 0.3, 0.0, 1.0))
		head_y = lerpf(EYE, 0.35, down)
		roll += _tumble_side * 1.35 * down + sin(u * 30.0) * 0.06 * (1.0 - down)
		if _tumble <= 0.0:
			_dip_vel = 1.5
			body.express("confused", 2.0)
	head.position = Vector3(0, head_y, 0) + bob
	head.rotation = Vector3(pitch, 0, roll)
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.fov = 75.0
	_view_blend = move_toward(_view_blend, 1.0 if in_view else 0.0, delta * 2.6)
	if _view_blend > 0.0:
		var k := smoothstep(0.0, 1.0, _view_blend)
		camera.global_transform = head.global_transform.interpolate_with(_view_xform, k)
		camera.fov = lerpf(75.0, _view_fov, k)
	# Hands
	if in_view or _view_blend > 0.3:
		hands.pose = "hidden"
	elif Game.in_dialogue and _look_lock != null:
		hands.pose = "carry" if held else "talk"
	elif held or chaos_held:
		hands.pose = "carry"
	elif body.phone_mode:
		hands.pose = "phone"
	else:
		hands.pose = "idle"


# --- goofy physics ---------------------------------------------------------------------------------------

## Fall over like an egg (slipping, getting bonked by a car...).
func tumble(direction: Vector3, strength := 1.0) -> void:
	if _tumble > 0.0 or not controls_enabled:
		return
	_tumble = 2.2
	_tumble_side = 1.0 if randf() < 0.5 else -1.0
	velocity += direction.normalized() * 3.0 * strength + Vector3(0, 2.5 * strength, 0)
	body.tumble(direction, strength)
	hands.play("flail")
	Sfx.play("boing", 0.7, -4.0)
	if held is Pizza:
		(held as Pizza).data.damage = minf(100.0, float((held as Pizza).data.damage) + 12.0 * strength)


## Fresh start (new day, respawn): stand up straight, stop, look normally.
func reset_state() -> void:
	_tumble = 0.0
	_dip = 0.0
	_dip_vel = 0.0
	velocity = Vector3.ZERO
	in_view = false
	_view_blend = 0.0
	_look_lock = null


func is_tumbling() -> bool:
	return _tumble > 0.0


func _check_slip(hv: Vector3) -> void:
	if _slip_cooldown > 0.0 or hv.length() < 2.0 or not is_on_floor():
		return
	for n in get_tree().get_nodes_in_group("slippery"):
		var s := n as Node3D
		var r := float(s.get_meta("radius", 0.5))
		var d := Vector2(s.global_position.x - global_position.x, s.global_position.z - global_position.z).length()
		if d < r:
			_slip_cooldown = 3.0
			tumble(hv, 1.0)
			Game.say_toast(["WHOOPS", "Sauce slip!", "THE FLOOR IS SAUCE", "Wet floor. Sign was right."].pick_random(), UiTheme.PINK)
			return


# --- interacting -----------------------------------------------------------------------------------------

func _update_focus() -> void:
	var best: Interactable = null
	var best_score := INF
	if controls_enabled and not in_view and _tumble <= 0.0:
		var eye := camera.global_position
		var fwd := forward()
		for n in get_tree().get_nodes_in_group("interactable"):
			var it := n as Interactable
			if it == null or not it.is_visible_in_tree():
				continue
			var to := it.global_position - eye
			var d := to.length()
			if d > it.reach + 0.6 or d < 0.01:
				continue
			# How far off the crosshair is it? (bigger things are easier to hit up close)
			var ang := fwd.angle_to(to / d)
			var allow := atan2(it.aim_radius, d) + 0.06
			if ang > allow:
				continue
			var score := ang / allow + d * 0.15
			if score >= best_score or not _visible_from(eye, it, d):
				continue
			if it.prompt(self) == "":
				continue
			best_score = score
			best = it
	if best != focus:
		focus = best
		focus_changed.emit(focus)


func _visible_from(eye: Vector3, it: Interactable, d: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(eye, it.global_position, 1)
	q.exclude = _ray_excludes
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var hit_d := eye.distance_to(hit.position)
	# Hitting the thing's own counter/door right at it is fine.
	return hit_d > d - it.aim_radius - 0.35


func interact() -> void:
	if focus and controls_enabled and not in_view:
		hands.play("grab" if not held else "push")
		focus.use(self)


## Click on nothing: poke whatever egg is in front of you.
func poke() -> void:
	if not controls_enabled or in_view or _poke_cooldown > 0.0 or held:
		return
	_poke_cooldown = 0.4
	hands.play("poke")
	var eye := camera.global_position
	var fwd := forward()
	for n in get_tree().get_nodes_in_group("eggs"):
		var e := n as EggBody
		if e == null or e == body or not e.is_visible_in_tree():
			continue
		var to := e.global_position + Vector3(0, 0.9, 0) - eye
		if to.length() < 1.9 and fwd.angle_to(to.normalized()) < 0.5:
			Sfx.play("poke", randf_range(0.9, 1.3), -6.0)
			e.play(["shake_head", "stomp", "laugh", "hop", "facepalm"].pick_random())
			e.express(["angry", "surprised", "happy"].pick_random(), 2.0)
			e.look_target = self
			if e.has_meta("on_poked"):
				(e.get_meta("on_poked") as Callable).call()
			return
	Sfx.play("poke", randf_range(0.6, 0.8), -14.0)


# --- carrying ----------------------------------------------------------------------------------------------

func is_holding() -> bool:
	return held != null


func hold(item: Node3D) -> void:
	if item.get_parent():
		item.reparent(hands.hold_socket, false)
	else:
		hands.hold_socket.add_child(item)
	item.position = Vector3.ZERO
	item.rotation = Vector3.ZERO
	held = item
	body.carrying = true
	hands.hold_width = 0.3
	if item is Pizza:
		var p := item as Pizza
		p.location = "carried"
		# Shown a bit smaller and lower so a large box doesn't eat the whole screen.
		var shrink := 0.72 if p.footprint() > 0.7 else 0.85
		item.scale = Vector3.ONE * shrink
		hands.hold_width = clampf(p.footprint() * shrink, 0.22, 0.7)
		item.position = Vector3(0, -0.05 * p.footprint(), -0.12 * p.footprint())
	hands.play("grab")


## Hands the held item over (removes it from our hand, caller re-parents it).
func take_held() -> Node3D:
	var item := held
	if item:
		item.scale = Vector3.ONE
	held = null
	body.carrying = false
	return item


# --- grab & throw anything -----------------------------------------------------------------------------

func _update_chaos_focus() -> void:
	var best: Throwable = null
	if controls_enabled and not in_view and _tumble <= 0.0 and chaos_held == null and held == null:
		var eye := camera.global_position
		var fwd := forward()
		var best_ang := 0.5
		for n in get_tree().get_nodes_in_group("throwable"):
			var t := n as Throwable
			if t == null or t.grabbed:
				continue
			var to := t.global_position - eye
			var d := to.length()
			if d > 2.7 or d < 0.05:
				continue
			var ang := fwd.angle_to(to / d) - atan2(t.radius, d)
			if ang < best_ang:
				best_ang = ang
				best = t
	chaos_focus = best
	if chaos_held and (not controls_enabled or in_view):
		drop_chaos()


func chaos_prompt() -> String:
	if chaos_held:
		return "[CLICK] THROW the %s   ·   [RIGHT CLICK / G] drop" % chaos_held.nice_name()
	if chaos_focus:
		return "[RIGHT CLICK / G] Grab the %s" % chaos_focus.nice_name()
	return ""


## Grab what you're looking at, or put down what you're holding.
func chaos_toggle() -> void:
	if chaos_held:
		drop_chaos()
	elif chaos_focus and held == null:
		chaos_held = chaos_focus
		chaos_held.grab(self)
		hands.play("grab")
		Sfx.play("pickup", 1.4, -8.0)


func drop_chaos() -> void:
	if chaos_held == null:
		return
	var t := chaos_held
	chaos_held = null
	t.release(self, forward() * 1.5 + velocity)


func throw_chaos() -> void:
	if chaos_held == null:
		return
	var t := chaos_held
	chaos_held = null
	hands.play("push")
	Sfx.play("whoosh", randf_range(0.9, 1.3), -6.0)
	t.release(self, forward() * t.throw_speed() + Vector3(0, 2.2, 0) + velocity * 0.5, true)
