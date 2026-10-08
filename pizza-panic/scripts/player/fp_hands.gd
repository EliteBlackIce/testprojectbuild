class_name FpHands
extends Node3D
## Your two chunky egg mittens in first person. Lives under the camera.
##
## Every frame each hand gets a target (pose + walk bob + mouse sway + whatever
## one-shot action is playing), then a spring chases it so everything has a
## little weight and overshoot. Poses: idle, carry (something held in front),
## phone (handset at your ear), talk (gesturing), hidden.
## One-shots: poke, grab, knock, push, wave, shrug, clap, flail, thumbs.

const SKIN := Color("#d9a066")
const REST_L := Vector3(-0.27, -0.29, -0.5)
const REST_R := Vector3(0.27, -0.29, -0.5)

var pose := "idle"
var moving := 0.0           ## 0..1 walk speed (set by the player)
var grounded := true
var hold_socket: Node3D     ## held items sit here (in front, at chest height)
var hold_width := 0.6       ## how far apart the hands go to carry the item

var _hands: Array[Node3D] = []
var _fingers: Array[MeshInstance3D] = []
var _phone: Node3D
var _pos: Array[Vector3] = [REST_L, REST_R]
var _vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _rot: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _phase := 0.0
var _t := 0.0
var _sway := Vector2.ZERO
var _land := 0.0
var _action := ""
var _action_t := 0.0
var _action_dur := 0.5
var _talk_t := 0.0
var _hold_bob := Vector3.ZERO

const DURATIONS := {
	"poke": 0.32, "grab": 0.38, "knock": 0.75, "push": 0.6, "wave": 1.1,
	"shrug": 0.8, "clap": 0.7, "flail": 1.2, "thumbs": 0.9, "stir": 0.5,
}


func _ready() -> void:
	for side: int in [-1, 1]:
		var hand := Node3D.new()
		add_child(hand)
		# Forearm going back toward you (you never see the elbow)
		var arm := Toon.mesh(hand, Shapes.limb(0.42, 0.06, 0.055, 9), Vector3(0, 0.0, 0.05), SKIN.darkened(0.04), 0.008)
		arm.rotation.x = -PI / 2 - 0.25
		var mitt := Toon.ball(hand, 0.075, Vector3.ZERO, SKIN, 0.008, 12)
		mitt.scale = Vector3(1.0, 0.82, 1.18)
		var thumb := Toon.ball(hand, 0.034, Vector3(-0.06 * side, 0.025, -0.02), SKIN, 0.006, 8)
		thumb.scale = Vector3(0.9, 1.3, 0.9)
		thumb.rotation.z = 0.5 * side
		# Pointer finger (pops out for pokes and thumbs-ups)
		var finger := MeshInstance3D.new()
		finger.mesh = Shapes.limb(0.08, 0.022, 0.02, 7)
		finger.material_override = Toon.mat(SKIN, 0.005)
		finger.rotation.x = PI / 2
		finger.position = Vector3(-0.01 * side, 0.01, -0.07)
		finger.scale = Vector3(1, 0.01, 1)
		hand.add_child(finger)
		_fingers.append(finger)
		_hands.append(hand)
	# Phone handset for calls (left hand)
	_phone = Node3D.new()
	_hands[0].add_child(_phone)
	Toon.block(_phone, Vector3(0.05, 0.2, 0.05), Vector3(0.02, -0.05, -0.02), Color("#c0392b"), 0.02, 0.006)
	Toon.ball(_phone, 0.035, Vector3(0.02, 0.15, -0.03), Color("#c0392b"), 0.006, 8)
	_phone.visible = false
	hold_socket = Node3D.new()
	hold_socket.position = Vector3(0, -0.4, -0.62)
	hold_socket.rotation.x = 0.12
	add_child(hold_socket)
	for n in find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 4   # viewmodel layer
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func play(action: String) -> void:
	_action = action
	_action_t = 0.0
	_action_dur = DURATIONS.get(action, 0.5)


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
		var rot := Vector3(0.15, -0.2 * side, 0.1 * side)
		var finger := 0.0
		match pose:
			"carry":
				target = Vector3(side * (hold_width * 0.5 + 0.02), -0.42, -0.62)
				rot = Vector3(0.6, 0.0, -1.2 * side)
			"phone":
				if i == 0:
					target = Vector3(-0.16, -0.04, -0.26)
					rot = Vector3(0.2, 0.9, 0.3)
			"talk":
				var g := sin(_talk_t * (2.3 + i * 0.7) + i * 2.0)
				target += Vector3(side * 0.03 * g, 0.06 + 0.04 * maxf(0.0, g), -0.05)
				rot += Vector3(-0.3 * g, 0.0, 0.4 * side * g)
		# Walk bob: a waddle, hands swinging opposite each other
		var stride := sin(_phase + i * PI)
		var bob := Vector3(side * 0.008 * moving, -absf(cos(_phase)) * 0.022 * moving + sin(_t * 1.6) * 0.005, stride * 0.03 * moving)
		if pose == "carry":
			bob = Vector3(0, -absf(cos(_phase)) * 0.015 * moving + sin(_t * 1.6) * 0.004, 0)
		target += bob
		target += Vector3(-_sway.x, _sway.y, 0.0) * (0.6 if pose == "carry" else 1.0)
		target.y -= _land * 0.09
		if not grounded:
			target.y += 0.04
			rot.z += 0.3 * side
		# One-shot action on top
		if _action != "":
			var u := _action_t / _action_dur
			var a := _action_offset(i, side, u)
			target += a[0]
			rot += a[1]
			finger = a[2]
		# Spring toward the target
		var acc := (target - _pos[i]) * 260.0 - _vel[i] * 22.0
		_vel[i] += acc * delta
		_pos[i] += _vel[i] * delta
		_rot[i] = _rot[i].lerp(rot, 1.0 - exp(-16.0 * delta))
		_hands[i].position = _pos[i]
		_hands[i].rotation = _rot[i]
		var fs := _fingers[i].scale.y
		_fingers[i].scale = Vector3(1, move_toward(fs, maxf(0.01, finger), delta * 8.0), 1)
	if hold_socket:
		var hb := Vector3(0, -absf(cos(_phase)) * 0.014 * moving - _land * 0.08, 0) + Vector3(-_sway.x, _sway.y, 0) * 0.5
		_hold_bob = _hold_bob.lerp(hb, 1.0 - exp(-14.0 * delta))
		hold_socket.position = Vector3(0, -0.4, -0.62) + _hold_bob
		hold_socket.rotation.z = -_sway.x * 1.5 + sin(_phase) * 0.02 * moving


## Returns [position offset, rotation offset, finger extension].
func _action_offset(i: int, side: float, u: float) -> Array:
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	var finger := 0.0
	var right := i == 1
	match _action:
		"poke":
			if right:
				var k := sin(u * PI)
				pos = Vector3(-0.17, 0.12, -0.28) * k
				rot = Vector3(-0.2, 0.3, 0.0) * k
				finger = 1.0 if u < 0.85 else 0.0
		"grab":
			var k := sin(u * PI)
			if right or pose != "carry":
				pos = Vector3(-0.1 * side, 0.08, -0.3) * k
				rot = Vector3(-0.6 * k, 0, 0)
		"knock":
			if right:
				var k := absf(sin(u * PI * 3.0))
				pos = Vector3(-0.12, 0.2, -0.12 - 0.18 * k)
				rot = Vector3(-0.4, 0.0, 1.4)
		"push":
			var k := sin(clampf(u * 1.4, 0.0, 1.0) * PI)
			pos = Vector3(-0.06 * side, 0.06, -0.4) * k
			rot = Vector3(-0.9 * k, 0, 0)
		"wave":
			if right:
				pos = Vector3(-0.02, 0.3, 0.02)
				rot = Vector3(0, 0, sin(u * TAU * 3.0) * 0.6 - 0.2)
		"shrug":
			var k := sin(u * PI)
			pos = Vector3(side * 0.08, 0.12, 0.03) * k
			rot = Vector3(-1.0, 0.0, side * 0.6) * k
		"clap":
			var k := absf(sin(u * PI * 4.0))
			pos = Vector3(-side * 0.22 * k, 0.12, -0.04)
			rot = Vector3(0.0, 0.0, -side * 1.3)
		"flail":
			pos = Vector3(sin(u * 40.0 + side) * 0.06, 0.2 + cos(u * 35.0 + i) * 0.08, 0.0)
			rot = Vector3(sin(u * 30.0) * 0.8, 0, side * 0.8)
		"thumbs":
			if right:
				var k := sin(u * PI)
				pos = Vector3(-0.1, 0.18, -0.08) * k
				rot = Vector3(0.0, 0.0, 1.5) * k
				finger = 0.0
		"stir":
			if right:
				pos = Vector3(cos(u * TAU * 2.0) * 0.05, -0.04, sin(u * TAU * 2.0) * 0.05 - 0.1)
	return [pos, rot, finger]
