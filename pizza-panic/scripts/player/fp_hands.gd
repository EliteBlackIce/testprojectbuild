class_name FpHands
extends Node3D
## Your two arms and mitten hands in first person. Lives under the camera.
##
## Each arm is a real two-bone limb: the shoulder sits just below and behind the camera,
## the wrist goes wherever the hand wants to be, and the elbow bends naturally in between
## (solved every frame), so the arms come in from the bottom corners of the screen the way
## your own do. Hands are the same three-lobed mittens as every egg, posed with named
## finger grips (relaxed, open, grip, fist, point, pinch...).
##
## Every frame each hand gets a target (pose + walk bob + mouse sway + a one-shot action),
## then a spring chases it so everything has weight and overshoot.
## Poses: idle, carry (something held in front), phone (handset at your ear), talk, hidden.
## One-shots: poke, grab, knock, push, wave, shrug, clap, flail, thumbs, stir,
## and the item verbs: pickup (reach to a spot, close, lift), release, throw.

const SKIN := Color("#e0a869")
const REST_L := Vector3(-0.24, -0.22, -0.48)
const REST_R := Vector3(0.24, -0.22, -0.48)
const SHOULDER := Vector3(0.2, -0.4, 0.16)       ## camera space, behind the near plane so arms emerge from the screen edge
const UPPER := 0.37
const FORE := 0.37

## Finger grips: curl of [finger 1, finger 2, thumb]. 0 = flat, 1 = closed.
const GRIPS := {
	"relaxed": [0.32, 0.4, 0.25],
	"open": [0.0, 0.02, 0.0],
	"soft": [0.18, 0.22, 0.12],
	"grip": [0.8, 0.85, 0.55],
	"cup": [0.5, 0.55, 0.3],
	"fist": [1.0, 1.0, 0.9],
	"point": [0.0, 1.0, 0.85],
	"pinch": [0.6, 0.68, 0.55],
	"thumbs": [1.0, 1.0, 0.0],
}

var pose := "idle"
var moving := 0.0           ## 0..1 walk speed (set by the player)
var grounded := true
var hold_socket: Node3D     ## held items sit here (in front, at chest height)
var hold_width := 0.6       ## how far apart the hands go to carry the item

var _hands: Array[Node3D] = []        ## wrist nodes (position = the wrist)
var _wrists: Array[Node3D] = []       ## hand orientation pivots
var _fingers: Array = []              ## per hand: finger + thumb pivots (see EggBody.build_hand)
var _upper: Array[Node3D] = []
var _fore: Array[Node3D] = []
var _elbow_balls: Array[MeshInstance3D] = []
var _phone: Node3D
var _pos: Array[Vector3] = [REST_L, REST_R]
var _vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _rot: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _curl: Array = [[0.32, 0.4, 0.25], [0.32, 0.4, 0.25]]
var _phase := 0.0
var _t := 0.0
var _sway := Vector2.ZERO
var _land := 0.0
var _action := ""
var _action_t := 0.0
var _action_dur := 0.5
var _talk_t := 0.0
var _hold_bob := Vector3.ZERO
var _reach := Vector3.ZERO            ## where a pickup/release reaches to (camera space)
var _reach_both := false
var _hand_bounce := [0.0, 0.0]

const DURATIONS := {
	"poke": 0.32, "grab": 0.45, "knock": 0.75, "push": 0.6, "wave": 1.1,
	"shrug": 0.8, "clap": 0.7, "flail": 1.2, "thumbs": 0.9, "stir": 0.5,
	"pickup": 0.72, "release": 0.5, "throw": 0.62,
}


func _ready() -> void:
	var sleeve := Color(Characters.PLAYER_LOOK.get("shirt", "#e63946"))
	for side: int in [-1, 1]:
		var hand := Node3D.new()
		add_child(hand)
		# The hand: the egg mitten, fingers forward and palm down by default.
		var wrist := Node3D.new()
		wrist.rotation = Vector3(PI / 2 + 0.3, -0.3 * side, 0.5 * side)
		hand.add_child(wrist)
		var built := EggBody.build_hand(wrist, SKIN, -float(side), 0.95, 0.006)
		# a rounded wrist that sits inside both the forearm and the palm, so there is no visible seam
		Toon.ball(hand, 0.047, Vector3.ZERO, SKIN, 0.006, 16)
		_fingers.append(built[1])
		_wrists.append(wrist)
		_hands.append(hand)
		# Arm: upper (sleeved) + forearm, joined by an elbow ball, solved to the wrist every frame.
		var up := Node3D.new()
		add_child(up)
		Toon.mesh(up, Shapes.smoothed(Shapes.limb(1.0, 0.05, 0.044, 20)), Vector3.ZERO, SKIN.darkened(0.03), 0.006)
		Toon.mesh(up, Shapes.smoothed(Shapes.limb(0.55, 0.06, 0.055, 20)), Vector3.ZERO, sleeve, 0.0)
		var fo := Node3D.new()
		add_child(fo)
		Toon.mesh(fo, Shapes.smoothed(Shapes.limb(1.0, 0.044, 0.035, 20)), Vector3.ZERO, SKIN, 0.006)
		var eb := Toon.ball(self, 0.052, Vector3.ZERO, SKIN.darkened(0.03), 0.006, 16)
		_upper.append(up)
		_fore.append(fo)
		_elbow_balls.append(eb)
	# Phone handset for calls (left hand)
	_phone = Node3D.new()
	_hands[0].add_child(_phone)
	Toon.block(_phone, Vector3(0.05, 0.2, 0.05), Vector3(0.02, -0.05, -0.02), Color("#c0392b"), 0.02, 0.006)
	Toon.ball(_phone, 0.035, Vector3(0.02, 0.15, -0.03), Color("#c0392b"), 0.006, 12)
	_phone.visible = false
	hold_socket = Node3D.new()
	hold_socket.position = Vector3(0, -0.5, -0.66)
	hold_socket.rotation.x = 0.3
	add_child(hold_socket)
	for n in find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 4   # viewmodel layer
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func play(action: String) -> void:
	_action = action
	_action_t = 0.0
	_action_dur = DURATIONS.get(action, 0.5)


## Reach out to a world-space point (an item to pick up, a spot to put something) and then do `action`
## ("pickup" or "release"). Both hands go for big things (boxes, pizzas), one for small ones.
func reach(world_point: Vector3, action := "pickup", both := false) -> void:
	var p := to_local(world_point)
	# Arms are only so long: stop at the end of the reach, in the direction of the target.
	var from := SHOULDER * Vector3(0.0, 1.0, 1.0)
	var d := p - from
	var max_len := (UPPER + FORE) * 0.93
	if d.length() > max_len:
		p = from + d.normalized() * max_len
	# keep the reaching hand in view: low items mean bending down, so the hand dips but never leaves the screen
	p.y = maxf(p.y, -0.52)
	p.z = minf(p.z, -0.3)
	_reach = p
	_reach_both = both
	play(action)


func is_playing() -> bool:
	return _action != ""


func add_sway(mouse_delta: Vector2) -> void:
	_sway += mouse_delta * 0.00035
	_sway = _sway.limit_length(0.06)


func landed(strength: float) -> void:
	_land = clampf(strength, 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	_phase += delta * (2.0 + moving * 7.5)
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-7.0 * delta))
	_land = move_toward(_land, 0.0, delta * 3.0)
	if _action != "":
		_action_t += delta
		if _action_t >= _action_dur:
			_action = ""
	_talk_t += delta
	visible = pose != "hidden"
	_phone.visible = pose == "phone"
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var target: Vector3 = REST_L if i == 0 else REST_R
		var rot := Vector3(0.28, -0.22 * side, 0.18 * side)      # fingers angled up and a little inward
		var grip: Array = GRIPS.relaxed
		var index_out := false
		match pose:
			"carry":
				target = Vector3(side * (hold_width * 0.5 + 0.03), -0.4, -0.6)
				rot = Vector3(0.75, 0.0, -1.15 * side)
				grip = GRIPS.grip
			"phone":
				if i == 0:
					target = Vector3(-0.16, -0.04, -0.26)
					rot = Vector3(0.2, 0.9, 0.3)
					grip = GRIPS.grip
			"talk":
				var g := sin(_talk_t * (2.3 + i * 0.7) + i * 2.0)
				target += Vector3(side * 0.03 * g, 0.06 + 0.04 * maxf(0.0, g), -0.05)
				rot += Vector3(-0.3 * g, 0.0, 0.4 * side * g)
				grip = GRIPS.open if g > 0.3 else GRIPS.soft
		# Walk bob: a waddle, hands swinging opposite each other
		var stride := sin(_phase + i * PI)
		var bob := Vector3(side * 0.008 * moving, -absf(cos(_phase)) * 0.022 * moving + sin(_t * 1.6) * 0.005, stride * 0.03 * moving)
		if pose == "carry":
			bob = Vector3(0, -absf(cos(_phase)) * 0.015 * moving + sin(_t * 1.6) * 0.004, 0)
		target += bob
		# Breathing: hands drift a little even when you stand still.
		var still := 1.0 - clampf(moving * 1.5, 0.0, 1.0)
		target += Vector3(sin(_t * 1.4 + i * 1.9) * 0.004, sin(_t * 2.1 + i * 0.7) * 0.006, sin(_t * 1.1 + i) * 0.004) * still
		rot += Vector3(sin(_t * 1.3 + i * 2.0) * 0.035, sin(_t * 0.9 + i) * 0.03, sin(_t * 1.7 + i * 1.3) * 0.025) * still
		target += Vector3(-_sway.x, _sway.y, 0.0) * (0.6 if pose == "carry" else 1.0)
		target.y -= _land * 0.09
		if not grounded:
			target.y += 0.04
			rot.z += 0.3 * side
		# One-shot action on top
		if _action != "":
			var u := _action_t / _action_dur
			var a := _action_offset(i, side, u, target)
			target += a.pos
			rot += a.rot
			if a.has("grip"):
				grip = a.grip
			index_out = a.get("index_out", false)
		# Spring toward the target (sub-stepped so a long frame can't blow it up)
		var steps := clampi(ceili(delta / 0.008), 1, 8)
		var h := minf(delta, 0.064) / steps
		for k in steps:
			var acc := (target - _pos[i]) * 260.0 - _vel[i] * 22.0
			_vel[i] += acc * h
			_pos[i] += _vel[i] * h
		if not _pos[i].is_finite() or not _vel[i].is_finite():
			_pos[i] = target
			_vel[i] = Vector3.ZERO
		# The wrist flops behind the hand's motion (hand tilts against its velocity).
		rot += Vector3(clampf(_vel[i].y * 0.18, -0.35, 0.35), clampf(_vel[i].x * 0.12, -0.25, 0.25), clampf(-_vel[i].x * 0.25, -0.4, 0.4))
		_rot[i] = _rot[i].lerp(rot, 1.0 - exp(-16.0 * delta))
		_hands[i].position = _pos[i]
		# Fingers: each curl chases its grip, a touch loose and alive.
		var c: Array = _curl[i]
		for k in 3:
			c[k] = lerpf(float(c[k]), float(grip[k]), 1.0 - exp(-15.0 * delta))
		EggBody.pose_hand(_fingers[i], c[0], c[1], c[2], index_out, _t + i * 2.0, 1.0 - clampf(float(c[0]), 0.0, 1.0))
		_solve_arm(i, side)
	if hold_socket:
		var hb := Vector3(0, -absf(cos(_phase)) * 0.014 * moving - _land * 0.08, 0) + Vector3(-_sway.x, _sway.y, 0) * 0.5
		_hold_bob = _hold_bob.lerp(hb, 1.0 - exp(-14.0 * delta))
		hold_socket.position = Vector3(0, -0.5, -0.66) + _hold_bob
		hold_socket.rotation.z = -_sway.x * 1.5 + sin(_phase) * 0.02 * moving


## Shoulder -> elbow -> wrist, with the elbow dropped down and out the way a real one hangs.
func _solve_arm(i: int, side: float) -> void:
	var sh := Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
	var wrist: Vector3 = _hands[i].position
	var to := wrist - sh
	var d := clampf(to.length(), 0.08, UPPER + FORE - 0.003)
	var dir := to.normalized()
	var a := (UPPER * UPPER - FORE * FORE + d * d) / (2.0 * d)
	var h := sqrt(maxf(UPPER * UPPER - a * a, 0.0))
	var hint := Vector3(side * 0.9, -1.0, 0.45)
	var pole := (hint - dir * hint.dot(dir)).normalized()
	var elbow := sh + dir * a + pole * h
	_limb_between(_upper[i], sh, elbow, UPPER)
	_limb_between(_fore[i], elbow, wrist + (wrist - elbow).normalized() * 0.02, FORE)
	_elbow_balls[i].position = elbow
	# The hand continues the line of the forearm (so it is always visibly attached to it); the pose's
	# own tilts and rolls are applied relative to that.
	var fd := (wrist - elbow).normalized()
	var aim := Basis.looking_at(fd, Vector3.UP)
	_hands[i].basis = aim * Basis.from_euler(_rot[i] * 0.85)


func _limb_between(node: Node3D, from: Vector3, to: Vector3, length: float) -> void:
	var y := (from - to).normalized()          # limb meshes hang down -Y
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	node.transform = Transform3D(Basis(x, y * length, z), from)


## Action timing with anticipation: a small pull-back first, then the move, then settle.
## Returns -0.3 at the wind-up, 1.0 at the peak, 0 at the end.
func _wind(u: float) -> float:
	if u < 0.2:
		return -0.3 * smoothstep(0.0, 1.0, u / 0.2)
	if u < 0.55:
		return lerpf(-0.3, 1.0, smoothstep(0.0, 1.0, (u - 0.2) / 0.35))
	return 1.0 - smoothstep(0.0, 1.0, (u - 0.55) / 0.45)


## 0 -> 1 over [a, b] with an ease.
func _ramp(u: float, a: float, b: float) -> float:
	return smoothstep(0.0, 1.0, clampf((u - a) / (b - a), 0.0, 1.0))


## What an action adds on top of the base pose for hand `i`: {pos, rot, grip?, index_out?}
func _action_offset(i: int, side: float, u: float, base: Vector3) -> Dictionary:
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	var out := {}
	var right := i == 1
	match _action:
		"poke":
			if right:
				var k := _wind(u)
				pos = Vector3(-0.17, 0.12, -0.28) * k
				rot = Vector3(-0.2, 0.3, 0.0) * k
				out.grip = GRIPS.point
				out.index_out = true
		"grab":
			# a quick reach and close (stations, doors, anything you press E on)
			var k := _wind(u)
			if right or pose != "carry":
				pos = Vector3(-0.1 * side, 0.08, -0.3) * k
				rot = Vector3(-0.6 * k, 0, 0)
			out.grip = _lerp_grip(GRIPS.open, GRIPS.grip, _ramp(u, 0.35, 0.6))
		"pickup":
			# 1. reach to the item (both hands for big things), 2. fingers close, 3. lift to the carry spot.
			var use := right or _reach_both
			if use:
				var spread := Vector3(side * 0.09, 0.0, 0.0) if _reach_both else Vector3.ZERO
				var to_item := _reach + spread - base
				var k := _ramp(u, 0.0, 0.38) * (1.0 - _ramp(u, 0.52, 0.95))
				pos = to_item * k
				rot = Vector3(-0.5 * k, 0.0, 0.3 * side * k)
				out.grip = _lerp_grip(GRIPS.open, GRIPS.grip, _ramp(u, 0.36, 0.56))
			else:
				out.grip = GRIPS.soft
		"release":
			var use2 := right or _reach_both
			if use2:
				var spread2 := Vector3(side * 0.1, 0.0, 0.0) if _reach_both else Vector3.ZERO
				var k2 := _ramp(u, 0.0, 0.4) * (1.0 - _ramp(u, 0.6, 1.0))
				pos = (_reach + spread2 - base) * k2
				rot = Vector3(-0.35 * k2, 0.0, 0.0)
				out.grip = _lerp_grip(GRIPS.grip, GRIPS.open, _ramp(u, 0.35, 0.55))
		"throw":
			# wind back and up, snap forward, let go, follow through
			var w := _ramp(u, 0.0, 0.42)
			var snap := _ramp(u, 0.42, 0.6)
			var settle := _ramp(u, 0.7, 1.0)
			if right or _reach_both:
				pos = (Vector3(0.05 * side, 0.2, 0.3) * w) + (Vector3(-0.05 * side, -0.32, -0.55) * snap) - (Vector3(-0.0, -0.1, -0.2) * settle)
				pos *= (1.0 - settle * 0.6)
				rot = Vector3(0.9 * w - 1.6 * snap, 0.0, 0.0) * (1.0 - settle)
			out.grip = _lerp_grip(GRIPS.grip, GRIPS.open, _ramp(u, 0.5, 0.62))
		"knock":
			if right:
				var k3 := absf(sin(u * PI * 3.0))
				pos = Vector3(-0.12, 0.2, -0.12 - 0.18 * k3)
				rot = Vector3(-0.4, 0.0, 1.4)
				out.grip = GRIPS.fist
		"push":
			var k4 := sin(clampf(u * 1.15, 0.0, 1.0) * PI)
			pos = Vector3(-0.06 * side, 0.06, -0.4) * k4
			rot = Vector3(-0.9 * k4, 0, 0)
			out.grip = GRIPS.open
		"wave":
			if right:
				pos = Vector3(-0.02, 0.3, 0.02)
				rot = Vector3(0, 0, sin(u * TAU * 3.0) * 0.6 - 0.2)
				out.grip = GRIPS.open
		"shrug":
			var k5 := sin(u * PI)
			pos = Vector3(side * 0.08, 0.12, 0.03) * k5
			rot = Vector3(-1.0, 0.0, side * 0.6) * k5
			out.grip = GRIPS.open
		"clap":
			var k6 := absf(sin(u * PI * 4.0))
			pos = Vector3(-side * 0.22 * k6, 0.12, -0.04)
			rot = Vector3(0.0, 0.0, -side * 1.3)
			out.grip = GRIPS.open
		"flail":
			pos = Vector3(sin(u * 40.0 + side) * 0.06, 0.2 + cos(u * 35.0 + i) * 0.08, 0.0)
			rot = Vector3(sin(u * 30.0) * 0.8, 0, side * 0.8)
			out.grip = GRIPS.open
		"thumbs":
			if right:
				var k7 := _wind(u)
				pos = Vector3(-0.1, 0.18, -0.08) * k7
				rot = Vector3(0.0, 0.0, 1.5) * k7
				out.grip = GRIPS.thumbs
		"stir":
			if right:
				pos = Vector3(cos(u * TAU * 2.0) * 0.05, -0.04, sin(u * TAU * 2.0) * 0.05 - 0.1)
				out.grip = GRIPS.grip
	out.pos = pos
	out.rot = rot
	return out


func _lerp_grip(a: Array, b: Array, t: float) -> Array:
	return [lerpf(a[0], b[0], t), lerpf(a[1], b[1], t), lerpf(a[2], b[2], t)]
