class_name EggBody
extends Node3D
## The universal character model: a faceted egg with stubby arms, mitten
## hands, chunky boots, a face on the front and a silly hat. Every person
## in the game (you, Tony, customers, pedestrians) is one of these.
##
## Faces +Z. Origin is between the feet.
##
## `look` keys (all optional):
##   skin, size, stretch (taller/thinner egg), boots, legs, eye ("normal", "big",
##   "sleepy", "tiny"), brows, mustache, beard, hat, hat_color, glasses, tie,
##   bow, apron, ears, snout, tail, ghost, baby, blush, hair (puffs), cape

var look: Dictionary = {}
var speed := 0.0            ## 0 = idle, 1 = walking, 2 = running
var carrying := false       ## arm up, box overhead (like the poster)
var waving := false
var talking := false
var flailing := false

var hand_socket: Node3D     ## put carried things here (above the raised hand)
var head_top: Node3D        ## top of the head (for labels)

var _s := 1.0
var _h := 1.15              ## egg height (before size scale)
var _r := 0.5               ## egg radius
var _torso: Node3D
var _hips: Node3D
var _legs: Array[Node3D] = []
var _shoulders: Array[Node3D] = []   ## [left, right]
var _elbows: Array[Node3D] = []
var _eyes: Array[Node3D] = []
var _pupils: Array[Node3D] = []
var _brows: Array[Node3D] = []
var _mouth: MeshInstance3D
var _tail: Node3D
var _phase := 0.0
var _t := 0.0
var _blink := 0.0
var _next_blink := 2.0
var _emotion := "neutral"
var _emotion_timer := 0.0
var _hop := 0.0


func build(l: Dictionary) -> void:
	look = l
	_s = float(look.get("size", 1.0))
	var stretch := float(look.get("stretch", 1.0))
	_h = 1.15 * stretch
	_r = 0.5 / sqrt(stretch)
	scale = Vector3.ONE * _s
	var skin := Color(look.get("skin", "#e8b77a"))
	var ghost: bool = look.get("ghost", false)
	var leg_len := 0.0 if ghost else (0.22 if look.get("baby", false) else 0.34)

	_hips = Node3D.new()
	_hips.position = Vector3(0, leg_len, 0)
	add_child(_hips)
	if not ghost:
		_build_legs(leg_len, Color(look.get("legs", skin.darkened(0.08))), Color(look.get("boots", "#6b4a35")))

	_torso = Node3D.new()
	_hips.add_child(_torso)
	var body := Toon.mesh(_torso, Shapes.egg(_h, _r), Vector3(0, -0.06, 0), skin, 0.02)
	body.name = "Egg"
	if ghost:
		for i in 7:
			var a := TAU * i / 7.0
			Toon.ball(_torso, 0.13, Vector3(cos(a) * _r * 0.95, 0.02, sin(a) * _r * 0.95), skin, 0.012, 6)

	head_top = Node3D.new()
	head_top.position = Vector3(0, _h - 0.06, 0)
	_torso.add_child(head_top)

	_build_face(skin)
	_build_arms(skin)
	_build_extras(skin)
	_build_hat()


# --- construction --------------------------------------------------------------------

## Radius of the egg at height y (0..h) measured from its bottom.
func _egg_r(y: float) -> float:
	var c := clampf(1.0 - 2.0 * y / _h, -1.0, 1.0)
	var th := acos(c)
	return sin(th) * _r * (1.0 + 0.16 * cos(th))


## A point on the egg's front surface. x = sideways offset, y = height.
func _surface(x: float, y: float, inset := 0.0) -> Vector3:
	var r := _egg_r(y)
	var z := sqrt(maxf(r * r - x * x, 0.0)) - inset
	return Vector3(x, y - 0.06, z)


## Turn a face part so it lies on the curved surface.
func _on_surface(node: Node3D, x: float, y: float, inset := 0.0) -> void:
	var p := _surface(x, y, inset)
	node.position = p
	node.rotation.y = atan2(x, p.z) * 0.9


func _build_legs(leg_len: float, leg_color: Color, boot_color: Color) -> void:
	for side: int in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.18 * side, 0.0, 0.0)
		_hips.add_child(pivot)
		Toon.cyl(pivot, 0.1, 0.09, leg_len, Vector3(0, -leg_len * 0.5, 0), leg_color, 0.012, 6)
		var boot := Toon.block(pivot, Vector3(0.3, 0.17, 0.42), Vector3(0, -leg_len - 0.01, 0.05), boot_color, 0.22, 0.015)
		Toon.block(pivot, Vector3(0.32, 0.05, 0.45), Vector3(0, -leg_len - 0.02, 0.05), boot_color.darkened(0.3), 0.1, 0.0)
		boot.name = "Boot"
		_legs.append(pivot)


func _build_arms(skin: Color) -> void:
	var shoulder_y := _h * 0.5
	var arm_color := Color(look.get("sleeves", skin))
	for side: int in [-1, 1]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3((_egg_r(shoulder_y) - 0.04) * side, shoulder_y - 0.06, 0.0)
		_torso.add_child(shoulder)
		Toon.ball(shoulder, 0.1, Vector3.ZERO, arm_color, 0.01, 7)
		Toon.cyl(shoulder, 0.085, 0.075, 0.26, Vector3(0, -0.13, 0), arm_color, 0.012, 6)
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -0.26, 0)
		shoulder.add_child(elbow)
		Toon.cyl(elbow, 0.075, 0.07, 0.22, Vector3(0, -0.11, 0), skin, 0.012, 6)
		# Chunky mitten hand + thumb
		var hand := Toon.ball(elbow, 0.105, Vector3(0, -0.29, 0.01), skin, 0.012, 7)
		hand.scale = Vector3(0.9, 1.1, 0.8)
		Toon.ball(elbow, 0.045, Vector3(-0.08 * side, -0.24, 0.05), skin, 0.008, 5)
		_shoulders.append(shoulder)
		_elbows.append(elbow)
		if side == 1:
			hand_socket = Node3D.new()
			hand_socket.position = Vector3(0, -0.42, 0.0)
			elbow.add_child(hand_socket)


func _build_face(skin: Color) -> void:
	var eye_style: String = look.get("eye", "normal")
	var eye_y := _h * 0.68
	var eye_x := 0.14
	var w := 0.12
	var h := 0.15
	match eye_style:
		"big":
			w = 0.15
			h = 0.2
		"tiny":
			w = 0.07
			h = 0.08
		"sleepy":
			h = 0.08
	for side: int in [-1, 1]:
		var eye := Node3D.new()
		_torso.add_child(eye)
		_on_surface(eye, eye_x * side, eye_y)
		Toon.block(eye, Vector3(w, h, 0.05), Vector3(0, -h * 0.5, -0.02), Color("#fbf6ee"), 0.2, 0.008)
		var pupil := Node3D.new()
		pupil.position = Vector3(0.012 * side, 0, 0.02)
		eye.add_child(pupil)
		var pw := w * 0.48
		var ph := h * 0.62
		Toon.block(pupil, Vector3(pw, ph, 0.04), Vector3(0, -ph * 0.5, 0), Color("#1d1517"), 0.25, 0.0)
		Toon.box(pupil, Vector3(pw * 0.32, pw * 0.32, 0.02), Vector3(pw * 0.15, ph * 0.22, 0.03), Color.WHITE, 0.0)
		_eyes.append(eye)
		_pupils.append(pupil)
		# Brows: chunky dark bars, rotated per emotion.
		var brow := Node3D.new()
		_torso.add_child(brow)
		_on_surface(brow, eye_x * side, eye_y + h * 0.5 + 0.06)
		Toon.box(brow, Vector3(0.17, 0.05, 0.05), Vector3(0, 0, 0.0), Color(look.get("brows", "#2b1c18")), 0.0)
		_brows.append(brow)
	# Cheeks
	if look.get("blush", false):
		for side: int in [-1, 1]:
			var b := Node3D.new()
			_torso.add_child(b)
			_on_surface(b, 0.24 * side, eye_y - 0.13)
			Toon.box(b, Vector3(0.09, 0.04, 0.02), Vector3.ZERO, Color("#ff8fa3"), 0.0)
	# Mouth
	var mouth_root := Node3D.new()
	_torso.add_child(mouth_root)
	_on_surface(mouth_root, 0.0, eye_y - 0.24)
	_mouth = Toon.box(mouth_root, Vector3(0.13, 0.03, 0.04), Vector3.ZERO, Color("#4a1f1c"), 0.0)
	# Snout (dogs, pigs, whatever)
	if look.get("snout", false):
		var sn := Node3D.new()
		_torso.add_child(sn)
		_on_surface(sn, 0.0, eye_y - 0.14)
		Toon.ball(sn, 0.11, Vector3(0, 0, 0.05), skin.lightened(0.15), 0.01, 7)
		Toon.ball(sn, 0.045, Vector3(0, 0.04, 0.15), Color("#1d1517"), 0.0, 6)
	# Mustache: two chunky angled slabs, like the poster.
	if look.get("mustache", false):
		var col := Color(look.get("hair_color", "#2b1c18"))
		for side: int in [-1, 1]:
			var m := Node3D.new()
			_torso.add_child(m)
			_on_surface(m, 0.07 * side, eye_y - 0.16)
			var slab := Toon.block(m, Vector3(0.16, 0.07, 0.06), Vector3(0, -0.035, 0), col, 0.3, 0.008)
			slab.rotation.z = -0.32 * side
	if look.get("beard", false):
		var bd := Node3D.new()
		_torso.add_child(bd)
		_on_surface(bd, 0.0, eye_y - 0.33)
		var beard := Toon.mesh(bd, Shapes.blob(0.2, 3, 0.12), Vector3(0, -0.04, -0.06), Color(look.get("hair_color", "#d9d4cc")), 0.012)
		beard.scale = Vector3(1.4, 1.2, 0.7)
	if look.get("glasses", false):
		for side: int in [-1, 1]:
			var g := Node3D.new()
			_torso.add_child(g)
			_on_surface(g, eye_x * side, eye_y)
			var frame := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.085
			tm.outer_radius = 0.11
			tm.rings = 8
			tm.ring_segments = 4
			frame.mesh = Shapes.faceted(tm)
			frame.material_override = Toon.mat(Color("#2b1c18"), 0.0)
			frame.rotation.x = PI / 2
			frame.position = Vector3(0, -0.07, 0.04)
			g.add_child(frame)


func _build_extras(skin: Color) -> void:
	var tie = look.get("tie", null)
	if tie != null:
		var t := Node3D.new()
		_torso.add_child(t)
		_on_surface(t, 0.0, _h * 0.32)
		Toon.box(t, Vector3(0.1, 0.07, 0.04), Vector3(0, 0.03, 0), Color(tie), 0.008)
		var tail := Toon.block(t, Vector3(0.09, 0.26, 0.03), Vector3(0, -0.24, 0), Color(tie), 0.3, 0.008)
		tail.rotation.x = 0.15
	var apron = look.get("apron", null)
	if apron != null:
		var ap := Node3D.new()
		_torso.add_child(ap)
		_on_surface(ap, 0.0, _h * 0.25, 0.03)
		var cloth := Toon.block(ap, Vector3(0.52, 0.42, 0.05), Vector3(0, -0.2, 0.01), Color(apron), 0.1, 0.01)
		cloth.rotation.x = -0.2
	var bow = look.get("bow", null)
	if bow != null:
		var bw := Node3D.new()
		_torso.add_child(bw)
		_on_surface(bw, 0.0, _h * 0.4)
		for side: int in [-1, 1]:
			Toon.ball(bw, 0.07, Vector3(0.07 * side, 0, 0.02), Color(bow), 0.008, 6).scale = Vector3(1.2, 0.8, 0.6)
	if look.get("ears", false):
		for side: int in [-1, 1]:
			var ear := Toon.mesh(_torso, Shapes.egg(0.36, 0.1, 6, 5), Vector3(_r * 0.82 * side, _h * 0.85, -0.02), Color(look.get("hair_color", skin.darkened(0.25))), 0.01)
			ear.rotation.z = (PI - 0.5) * side
			ear.rotation.x = 0.2
	if look.get("tail", false):
		_tail = Node3D.new()
		_tail.position = Vector3(0, _h * 0.2, -_r * 0.95)
		_torso.add_child(_tail)
		var tl := Toon.cyl(_tail, 0.03, 0.06, 0.32, Vector3(0, 0.14, -0.06), skin, 0.01, 5)
		tl.rotation.x = -0.6
	if look.get("baby", false):
		var diaper := Toon.mesh(_torso, Shapes.egg(0.42, _r * 1.05, 10, 4), Vector3(0, -0.08, 0), Color("#f6f4ef"), 0.015)
		diaper.scale = Vector3(1, 1, 1)
	var hair = look.get("hair", null)
	if hair != null:
		for side: int in [-1, 1]:
			Toon.mesh(_torso, Shapes.blob(0.14, 7 + side, 0.15), Vector3(_r * 0.9 * side, _h * 0.78, -0.08), Color(hair), 0.01)
	var cape = look.get("cape", null)
	if cape != null:
		var cp := Toon.block(_torso, Vector3(_r * 2.0, _h * 0.75, 0.04), Vector3(0, 0.05, -_r * 0.85), Color(cape), 0.1, 0.012)
		cp.rotation.x = 0.12


func _build_hat() -> void:
	var hat: String = look.get("hat", "none")
	var col := Color(look.get("hat_color", "#c0392b"))
	var top := head_top
	match hat:
		"cap":
			# Two-tone trucker cap like the poster.
			var crown := Toon.mesh(top, Shapes.lathe(PackedVector2Array([Vector2(0.4, 0), Vector2(0.39, 0.14), Vector2(0.28, 0.27), Vector2(0, 0.3)]), 7, 0.5), Vector3(0, -0.13, 0), Color(look.get("hat_front", "#e8dccb")), 0.012)
			crown.rotation.x = -0.12
			Toon.mesh(top, Shapes.lathe(PackedVector2Array([Vector2(0.41, 0), Vector2(0.41, 0.07), Vector2(0, 0.07)]), 7, 0.5), Vector3(0, -0.14, 0), col, 0.012)
			var brim := Toon.block(top, Vector3(0.48, 0.04, 0.3), Vector3(0, -0.1, 0.36), col, 0.3, 0.01)
			brim.rotation.x = 0.12
		"chef":
			Toon.cyl(top, 0.3, 0.28, 0.3, Vector3(0, 0.03, 0), Color.WHITE, 0.012, 9)
			Toon.mesh(top, Shapes.blob(0.33, 11, 0.12), Vector3(0, 0.3, 0), Color.WHITE, 0.012).scale = Vector3(1.1, 0.75, 1.1)
		"wizard":
			Toon.cyl(top, 0.56, 0.56, 0.04, Vector3(0, -0.06, 0), col, 0.012, 9)
			var cone := Toon.cyl(top, 0.0, 0.32, 0.85, Vector3(0.05, 0.36, 0), col, 0.012, 7)
			cone.rotation.z = -0.22
			Toon.ball(top, 0.06, Vector3(0.0, 0.25, 0.27), Color("#ffd166"), 0.0, 5)
			Toon.ball(top, 0.04, Vector3(0.1, 0.45, 0.2), Color("#ffd166"), 0.0, 5)
		"tinfoil":
			var foil := Toon.cyl(top, 0.0, 0.38, 0.5, Vector3(0, 0.15, 0), Color("#d7dbe2"), 0.012, 5)
			foil.material_override = Toon.mat(Color("#dfe3ea"), 0.012, 0.25)
		"crown":
			Toon.cyl(top, 0.25, 0.23, 0.16, Vector3(0, 0.02, 0), Color("#ffd166"), 0.01, 8)
			for i in 5:
				var a := TAU * i / 5.0
				Toon.cyl(top, 0.0, 0.05, 0.12, Vector3(cos(a) * 0.23, 0.16, sin(a) * 0.23), Color("#ffd166"), 0.0, 4)
				Toon.ball(top, 0.03, Vector3(cos(a) * 0.24, 0.05, sin(a) * 0.24), Color("#e84393"), 0.0, 5)
		"beanie":
			Toon.mesh(top, Shapes.lathe(PackedVector2Array([Vector2(0.4, 0), Vector2(0.38, 0.16), Vector2(0.24, 0.3), Vector2(0, 0.33)]), 8, 0.5), Vector3(0, -0.14, 0), col, 0.012)
			Toon.ball(top, 0.08, Vector3(0, 0.22, 0), col.lightened(0.3), 0.008, 6)
		"propeller":
			Toon.mesh(top, Shapes.lathe(PackedVector2Array([Vector2(0.38, 0), Vector2(0.3, 0.16), Vector2(0, 0.2)]), 8, 0.5), Vector3(0, -0.12, 0), col, 0.012)
			var prop := Node3D.new()
			prop.name = "Propeller"
			prop.position = Vector3(0, 0.12, 0)
			top.add_child(prop)
			Toon.cyl(prop, 0.015, 0.015, 0.1, Vector3(0, -0.02, 0), Color("#555555"), 0.0, 4)
			Toon.box(prop, Vector3(0.5, 0.02, 0.08), Vector3(0, 0.04, 0), Color("#ffd166"), 0.006)
		"tophat":
			Toon.cyl(top, 0.42, 0.42, 0.04, Vector3(0, -0.06, 0), Color("#1d1517"), 0.012, 9)
			Toon.cyl(top, 0.26, 0.26, 0.42, Vector3(0, 0.16, 0), Color("#1d1517"), 0.012, 9)
			Toon.cyl(top, 0.265, 0.265, 0.06, Vector3(0, 0.0, 0), col, 0.0, 9)
		"headband":
			var band := Toon.cyl(top, _egg_r(_h * 0.86) + 0.01, _egg_r(_h * 0.86) + 0.02, 0.07, Vector3(0, -_h * 0.12, 0), col, 0.008, 10)
			band.name = "Headband"
		"headset":
			var arc := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.36
			tm.outer_radius = 0.41
			tm.ring_segments = 4
			tm.rings = 12
			arc.mesh = Shapes.faceted(tm)
			arc.material_override = Toon.mat(Color("#2d3436"), 0.0)
			arc.rotation.z = PI / 2
			arc.position = Vector3(0, -0.2, 0)
			top.add_child(arc)
			for side: int in [-1, 1]:
				var cup := Toon.cyl(top, 0.11, 0.11, 0.09, Vector3(0.41 * side, -0.25, 0), col, 0.008, 7)
				cup.rotation.z = PI / 2
		"bun":
			Toon.mesh(top, Shapes.blob(0.17, 5, 0.1), Vector3(0, 0.06, -0.1), Color(look.get("hair_color", "#d9d4cc")), 0.01)
		"bow":
			for side: int in [-1, 1]:
				Toon.ball(top, 0.1, Vector3(0.12 * side, 0.02, 0.05), col, 0.008, 6).scale = Vector3(1.3, 0.9, 0.6)
			Toon.ball(top, 0.05, Vector3(0, 0.02, 0.06), col.darkened(0.2), 0.0, 5)
		"cowboy":
			Toon.cyl(top, 0.6, 0.6, 0.04, Vector3(0, -0.05, 0), col, 0.012, 10).scale = Vector3(1, 1, 0.8)
			Toon.cyl(top, 0.24, 0.3, 0.28, Vector3(0, 0.1, 0), col, 0.012, 8)


# --- behavior --------------------------------------------------------------------------

## neutral, happy, angry, confused, excited, sad, scared, suspicious, in_love, smug
func express(emotion: String, hold := 4.0) -> void:
	_emotion = emotion
	_emotion_timer = hold


func hop() -> void:
	_hop = 1.0


func _process(delta: float) -> void:
	if _torso == null:
		return
	_t += delta
	_emotion_timer -= delta
	if _emotion_timer <= 0.0 and _emotion != "neutral":
		_emotion = "neutral"

	# Walk cycle
	var moving := clampf(speed, 0.0, 2.0)
	_phase += delta * (6.0 + moving * 4.0) * (1.0 if moving > 0.05 else 0.0)
	var swing := sin(_phase) * 0.7 * minf(moving, 1.2)
	for i in _legs.size():
		var target := swing * (1.0 if i == 0 else -1.0)
		_legs[i].rotation.x = lerpf(_legs[i].rotation.x, target, 1.0 - exp(-18.0 * delta))
	var bob := absf(sin(_phase)) * 0.05 * minf(moving, 1.0)
	var breathe := sin(_t * 2.2) * 0.012
	var ghost: bool = look.get("ghost", false)
	if ghost:
		bob = 0.25 + sin(_t * 1.6) * 0.1
	_hop = maxf(0.0, _hop - delta * 2.5)
	var hop_y := sin(_hop * PI) * 0.6
	_torso.position.y = bob + breathe + hop_y
	_torso.rotation.z = sin(_phase * 0.5) * 0.06 * minf(moving, 1.0)
	_torso.rotation.x = 0.08 * minf(moving, 2.0) * 0.5
	var squash := 1.0 + sin(_t * (14.0 if talking else 2.2)) * (0.025 if talking else 0.01)
	_torso.scale = Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))

	_animate_arms(delta, swing)
	_animate_face(delta)
	# Whatever we carry stays level, no matter how the arm is bent.
	if hand_socket:
		hand_socket.global_basis = Basis(Vector3.UP, global_rotation.y).scaled(Vector3.ONE * _s)
		if carrying:
			# Box balanced right over the head, like the poster.
			var over := head_top.global_position + Vector3(0, 0.3 * _s, 0)
			hand_socket.global_position = hand_socket.global_position.lerp(over, 0.85)
	if _tail:
		_tail.rotation.y = sin(_t * (22.0 if _emotion in ["happy", "excited", "in_love"] else 6.0)) * 0.7
	var prop := head_top.get_node_or_null("Propeller")
	if prop:
		prop.rotation.y += delta * (6.0 + moving * 20.0)


func _animate_arms(delta: float, swing: float) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var sh := _shoulders[i]
		var el := _elbows[i]
		var out := 0.18     # rotation.z outward amount (multiplied by side)
		var fwd := -swing * (1.0 if i == 0 else -1.0) * 0.8
		var bend := -0.25
		if flailing:
			out = 2.4 + sin(_t * 30.0 + i) * 0.6
			fwd = sin(_t * 25.0 + i * 2.0) * 1.2
			bend = -0.4
		elif i == 1 and carrying:
			# Right arm straight up, box overhead.
			out = 2.95
			fwd = 0.0
			bend = -0.35
		elif i == 1 and waving:
			out = 2.5
			fwd = 0.0
			bend = -0.6 + sin(_t * 12.0) * 0.5
		elif i == 0 and carrying:
			# Other hand on the hip, like the poster.
			out = 0.6
			fwd = 0.3
			bend = -1.6
		elif talking:
			out = 0.4 + sin(_t * 5.0 + i * 1.7) * 0.3
			fwd = -0.5 + sin(_t * 4.0 + i) * 0.3
			bend = -0.9
		elif _emotion in ["excited", "happy"] and _emotion_timer > 0.0:
			out = 2.3 + sin(_t * 16.0 + i * PI) * 0.3
			fwd = 0.0
			bend = -0.3
		sh.rotation.z = lerp_angle(sh.rotation.z, out * side, k)
		sh.rotation.x = lerp_angle(sh.rotation.x, fwd, k)
		el.rotation.x = lerp_angle(el.rotation.x, bend, k)


func _animate_face(delta: float) -> void:
	# Blinking
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 0.14
		_next_blink = randf_range(2.0, 5.0)
	_blink = maxf(0.0, _blink - delta)
	var open := 0.1 if _blink > 0.0 else 1.0
	var eye_scale := 1.0
	var brow_tilt := 0.0
	var brow_raise := 0.0
	var mouth_w := 1.0
	var mouth_h := 1.0
	match _emotion:
		"angry":
			brow_tilt = 0.45
			brow_raise = -0.025
		"happy", "in_love", "excited":
			brow_raise = 0.03
			mouth_w = 1.4
			mouth_h = 2.0
		"sad":
			brow_tilt = -0.4
			mouth_w = 0.7
		"scared", "surprised":
			brow_raise = 0.05
			eye_scale = 1.2
			mouth_w = 0.7
			mouth_h = 4.0
		"confused", "suspicious":
			brow_tilt = 0.25
		"smug":
			brow_tilt = 0.2
			mouth_w = 1.3
	if look.get("grumpy", false) and _emotion == "neutral":
		brow_tilt = 0.3   # resting angry-face, like the poster
	for i in _brows.size():
		var side := -1.0 if i == 0 else 1.0
		var b := _brows[i]
		var tilt := brow_tilt
		if _emotion == "suspicious" and i == 0:
			tilt = -0.2
		b.rotation.z = lerp_angle(b.rotation.z, -tilt * side, 0.3)
		b.scale.y = 1.0
		var base_y: float = b.get_meta("base_y", b.position.y)
		b.set_meta("base_y", base_y)
		b.position.y = lerpf(b.position.y, base_y + brow_raise, 0.3)
	for e in _eyes:
		e.scale = e.scale.lerp(Vector3(eye_scale, open * eye_scale, 1.0), 0.5)
	if talking:
		mouth_h = 1.0 + absf(sin(_t * 17.0)) * 4.0
	_mouth.scale = _mouth.scale.lerp(Vector3(mouth_w, mouth_h, 1.0), 0.4)
	# Pupils wander a little.
	for p in _pupils:
		var target := Vector3(sin(_t * 0.7) * 0.012, cos(_t * 0.5) * 0.008, 0.02)
		p.position = p.position.lerp(Vector3(target.x + p.position.x * 0.0, target.y, 0.02), 0.05)
