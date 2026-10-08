class_name EggBody
extends Node3D
## The universal character: a tall, round, slightly lopsided egg with stubby
## arms, mitten hands, clompy boots, a face on the front and a silly hat.
## Everyone in the game is one of these (you, Tony, customers, staff, pedestrians).
##
## Faces +Z, origin between the feet.
##
## ANIMATION: layered + springy, all procedural:
##   locomotion (stride-synced waddle) -> carry pose -> one-shot action
##   -> emotion -> talking gestures -> springs (follow-through, overshoot)
##   + secondary motion (hat wobble, belly jiggle, squash & stretch, blinking).
## Drive it by setting `velocity_hint` (or `speed`) every frame, and call
## play("wave"), express("angry"), tumble(dir) etc.
##
## `look` keys (all optional): skin, size, stretch, round, belly, boots, legs,
## sleeves, eye ("normal","big","sleepy","tiny"), brows, mustache, beard,
## hair_color, hat, hat_color, hat_front, glasses, tie, bow, apron, ears,
## snout, tail, ghost, baby, blush, hair (puffs), cape, grumpy,
## waddle (0..1), bounce (0..1)

const ACTIONS := {
	"wave": 1.6, "knock": 1.1, "celebrate": 1.3, "stomp": 1.0, "laugh": 1.5, "shrug": 1.1,
	"point": 1.2, "flex": 1.6, "dance": 2.4, "yawn": 2.0, "scratch": 1.6, "look_around": 2.2,
	"tap_foot": 1.6, "eat": 1.6, "hop": 0.6, "spin": 0.8, "nod": 0.8, "shake_head": 0.9,
	"facepalm": 1.4, "slam": 0.9, "work": 1.2,
}

## Body proportions, traced from the reference art (reference pixels -> meters).
const S := 0.0018
const HEAD_R := 0.283
const HIPS_Y := 0.64          ## height of the hips for a normal adult
const NECK_Y := 0.6           ## torso-local height of the neck
## Torso silhouette [row in reference px, radius in reference px], bottom -> top.
const TORSO_TABLE := [[776, 0], [772, 42], [765, 70], [753, 98], [741, 112], [729, 121], [705, 135], [681, 143],
	[657, 147], [633, 148], [609, 148], [585, 145], [561, 142], [537, 137], [513, 131], [489, 125], [465, 120],
	[440, 114], [420, 106], [400, 94], [388, 60], [383, 0]]

var look: Dictionary = {}
var speed := 0.0              ## 0 idle, 1 walk, 2 run (used if velocity_hint isn't set)
var velocity_hint := Vector3.INF  ## world velocity; more accurate than speed (lean, stride)
var carrying := false
var carry_style := "overhead" ## "overhead" (poster pose) or "front"
var waving := false           ## continuous wave (customers waiting for you)
var talking := false
var flailing := false         ## mid-air panic
var phone_mode := false       ## hand to ear
var look_target: Node3D       ## turn eyes (and a little body) toward this
var idle_fidgets := true

var hand_socket: Node3D       ## carried things go here
var head_top: Node3D          ## top of the head (labels, hats)

# --- rig ---
var _s := 1.0
var _tw := 1.0                ## torso width multiplier
var _leg_len := HIPS_Y
var _head: Node3D
var _body_root: Node3D        ## torso meshes (a little flatter front-to-back)
var _rig: Node3D              ## everything; rotated when tumbling
var _hips: Node3D
var _torso: Node3D
var _hat: Node3D
var _legs: Array[Node3D] = []
var _boots: Array[Node3D] = []
var _leg_splay: Array[float] = []
var _shoulders: Array[Node3D] = []   ## [left, right]
var _elbows: Array[Node3D] = []
var _hands: Array[Node3D] = []
var _wrists: Array[Node3D] = []           ## twists the hand (palm in / palm forward)
var _fingers: Array = []                  ## per hand: [finger pivots..., thumb pivot]
## Dev/tools: values here override the computed pose (e.g. a T-pose for model sheets).
var pose_override: Dictionary = {}
var _googly := Vector2.ZERO
var _googly_v := Vector2.ZERO
const IRIS_COLORS := ["#3a7bd5", "#2bb38a", "#8e5bd8", "#d9773a", "#c9415e", "#4aa3c8", "#7a5230", "#5c9c3a"]
var _eyes: Array[Node3D] = []
var _pupils: Array[Node3D] = []
var _brows: Array[Node3D] = []
var _brow_base: Array[float] = []
var _mouth: MeshInstance3D
var _tail: Node3D
var _dizzy: Node3D

# --- animation state ---
var _t := 0.0
var _phase := 0.0
var _blink := 0.0
var _next_blink := 2.0
var _emotion := "neutral"
var _emotion_timer := 0.0
var _action := ""
var _action_t := 0.0
var _action_dur := 1.0
var _idle_timer := 4.0
var _last_pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _land_squash := 0.0
var _hop := 0.0
var _tumble := 0.0            ## >0 while rolling around
var _tumble_dir := Vector3.FORWARD
var _getup := 0.0             ## >0 while wobbling back up
var _dizzy_t := 0.0
## Springs: name -> [value, velocity]
var _spr: Dictionary = {}


func build(l: Dictionary) -> void:
	look = l
	add_to_group("eggs")
	_s = float(look.get("size", 1.0))
	var baby: bool = look.get("baby", false)
	var ghost: bool = look.get("ghost", false)
	# Body variations stay gentle so everyone keeps the same friendly silhouette.
	_tw = snappedf(1.06 * clampf(float(look.get("round", 1.0)), 0.9, 1.3) * (1.0 + minf(float(look.get("belly", 0.0)), 0.3) * 0.7), 0.02)
	_leg_len = 0.25 if ghost else (0.34 if baby else HIPS_Y * clampf(float(look.get("stretch", 1.0)), 0.9, 1.15))
	scale = Vector3.ONE * _s
	var skin := Color(look.get("skin", "#e8b77a"))

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position = Vector3(0, _leg_len, 0)
	_rig.add_child(_hips)
	if not ghost:
		_build_legs(skin)
	_torso = Node3D.new()
	_torso.name = "Torso"
	_hips.add_child(_torso)
	_body_root = Node3D.new()
	_body_root.scale = Vector3(1, 1, 0.92)
	_torso.add_child(_body_root)
	_build_torso(skin)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, NECK_Y, 0)
	_torso.add_child(_head)
	Toon.ball(_head, HEAD_R, Vector3(0, HEAD_R, 0), skin, 0.012, 56).name = "Skull"
	head_top = Node3D.new()
	head_top.position = Vector3(0, HEAD_R * 2.0 - 0.1, 0)
	_head.add_child(head_top)
	_hat = Node3D.new()
	head_top.add_child(_hat)

	_build_face(skin)
	_build_hair(skin)
	_build_arms(skin)
	_build_extras(skin)
	_build_hat()
	_dizzy = Node3D.new()
	_dizzy.position = Vector3(0, 0.35, 0)
	head_top.add_child(_dizzy)
	for i in 3:
		var a := TAU * i / 3.0
		Toon.ball(_dizzy, 0.06, Vector3(cos(a) * 0.35, 0, sin(a) * 0.35), Color("#ffd166"), 0.0, 10)
	_dizzy.visible = false
	_last_pos = global_position if is_inside_tree() else Vector3.ZERO
	# Soft, smooth shading over the whole character (no facets anywhere).
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh and not (mi.material_override is StandardMaterial3D):
			mi.mesh = Shapes.smoothed(mi.mesh)


# --- body shape (traced from the reference art) ---------------------------------------------------

## Torso radius in meters at a torso-local height (before the width multiplier).
func _tr(y_local: float) -> float:
	var py := 1133.0 - (y_local + HIPS_Y) / S
	var t := TORSO_TABLE
	if py >= float((t[0] as Array)[0]):
		return 0.0
	for i in t.size() - 1:
		var a: Array = t[i]
		var b: Array = t[i + 1]
		if py <= float(a[0]) and py >= float(b[0]):
			var u := (float(a[0]) - py) / (float(a[0]) - float(b[0]))
			var p0 := float((t[maxi(i - 1, 0)] as Array)[1])
			var p3 := float((t[mini(i + 2, t.size() - 1)] as Array)[1])
			return maxf(0.0, cubic_interpolate(float(a[1]), float(b[1]), p0, p3, u)) * S
	return 0.0


## A lathe profile following the torso from y0 to y1, pushed out by `off`.
func _profile(y0: float, y1: float, off := 0.0, steps := 40) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in steps + 1:
		var y := lerpf(y0, y1, float(i) / steps)
		p.append(Vector2(maxf(_tr(y) * _tw + off, 0.0), y))
	return p


func _torso_mesh(y0: float, y1: float, off: float, color: Color, outline := 0.0) -> MeshInstance3D:
	return Toon.mesh(_body_root, Shapes.lathe(_profile(y0, y1, off), 48, 0.0), Vector3.ZERO, color, outline)


func _build_torso(skin: Color) -> void:
	var ghost: bool = look.get("ghost", false)
	var baby: bool = look.get("baby", false)
	var shirt := Color(look.get("shirt", skin))
	var base := _torso_mesh(0.0, 0.7, 0.0, shirt, 0.012)
	base.name = "Body"
	var pants_c := Color(look.get("pants", look.get("legs", "#3d5a80")))
	if look.has("shirt") and not ghost:
		# Waistband/hips in the pants color so shirt and trousers read as separate pieces.
		if not look.has("dress") and not look.has("robe") and not look.has("overalls"):
			_torso_mesh(0.0, 0.17, 0.006, pants_c)
			if look.has("belt"):
				_torso_mesh(0.15, 0.2, 0.012, Color(look.belt))
	if look.has("overalls"):
		_torso_mesh(0.0, 0.34, 0.008, Color(look.overalls))
		for side: int in [-1, 1]:
			var strap := Toon.mesh(_body_root, Shapes.rounded_box(Vector3(0.05, 0.4, 0.03), 0.012), Vector3(0.1 * side, 0.5, _tr(0.5) * _tw + 0.004), Color(look.overalls), 0.0)
			strap.rotation.z = -0.12 * side
	if look.has("stripe"):
		for k in 3:
			var y := 0.2 + k * 0.14
			_torso_mesh(y, y + 0.045, 0.006, Color(look.stripe))
	if look.has("collar"):
		_torso_mesh(0.5, 0.6, 0.012, Color(look.collar))
	if look.has("vest"):
		var vest := Color(look.vest)
		_front_patch(0.2, 0.09, 0.56, 0.012, vest, false)
		_front_patch(0.2, 0.09, 0.56, 0.012, vest, true, 0.0)
	if look.has("dress"):
		_skirt(Color(look.dress), 0.4, 0.5)
	if look.has("robe"):
		_skirt(Color(look.robe), 1.02, 0.5, 0.38)
		_torso_mesh(0.0, 0.64, 0.01, Color(look.robe))
	if look.has("skirt"):
		_skirt(Color(look.skirt), 0.34, 0.36)
	if baby:
		# Diaper
		_torso_mesh(0.0, 0.22, 0.03, Color("#f6f4ef"))
	if ghost:
		_skirt(Color(look.get("shirt", "#f3f3f6")), _leg_len + 0.02, 0.5, 0.58)
	if look.has("logo"):
		var logo := Node3D.new()
		logo.position = Vector3(0.0, 0.44, _tr(0.44) * _tw + 0.004)
		_body_root.add_child(logo)
		var disc := Toon.mesh(logo, Shapes.rounded_box(Vector3(0.15, 0.15, 0.02), 0.01, 24, 12), Vector3.ZERO, Color(look.logo), 0.0)
		disc.scale = Vector3(1, 1, 1)
		var txt := Toon.label(logo, str(look.get("logo_text", "T")), Vector3(0, 0, 0.012), 36, Color("#ffd166"), false)
		txt.outline_size = 0
		txt.pixel_size = 0.0022
	if look.has("buttons"):
		for k in 4:
			var y := 0.14 + k * 0.1
			Toon.ball(_body_root, 0.012, Vector3(0, y, _tr(y) * _tw + 0.004), Color(look.buttons), 0.0, 10)
	if look.has("pocket"):
		var pk := Toon.mesh(_body_root, Shapes.rounded_box(Vector3(0.07, 0.06, 0.012), 0.008), Vector3(0.1, 0.38, _tr(0.38) * _tw + 0.003), Color(look.pocket), 0.0)
		pk.rotation.z = -0.05


## A flared skirt/robe hanging from the waist down by `length`, ending `hem` wide.
func _skirt(color: Color, length: float, waist_y: float, hem := 0.0) -> void:
	var p := PackedVector2Array()
	var steps := 24
	var hem_r := hem if hem > 0.0 else 0.2 + length * 0.55
	for i in steps + 1:
		var u := float(i) / steps
		var y := waist_y - length * u
		var r := lerpf(_tr(minf(waist_y, 0.62)) * _tw + 0.012, hem_r * _tw, pow(u, 1.5))
		p.insert(0, Vector2(r, y))
	var m := Toon.mesh(_body_root, Shapes.lathe(p, 48, 0.0), Vector3.ZERO, color, 0.008)
	m.name = "Skirt"
	# a rounded hem ring so the bottom edge isn't a sharp rim
	var hem_y := waist_y - length
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = hem_r * _tw - 0.018
	tm.outer_radius = hem_r * _tw + 0.018
	tm.rings = 48
	tm.ring_segments = 12
	ring.mesh = tm
	ring.material_override = Toon.mat(color, 0.0)
	ring.position = Vector3(0, hem_y, 0)
	_body_root.add_child(ring)


## A curved cloth patch on the front (or back) of the torso: apron, vest panels, cape.
func _front_patch(y0: float, half_w: float, y1: float, lift: float, color: Color, back := false, outline := 0.006) -> MeshInstance3D:
	var cols := 14
	var rows := 12
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var grid: Array = []
	for i in rows + 1:
		var y := lerpf(y0, y1, float(i) / rows)
		var r := _tr(y) * _tw
		var hw := minf(half_w, r * 0.97)
		var row: Array = []
		for j in cols + 1:
			var x := lerpf(-hw, hw, float(j) / cols)
			var z := sqrt(maxf(r * r - x * x, 0.0)) + lift
			row.append(Vector3(x, y, -z if back else z))
		grid.append(row)
	for i in rows:
		for j in cols:
			var q := [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for k in tri:
					var v: Vector3 = q[k]
					out_v.append(v)
					out_n.append(Vector3(v.x, 0.0, v.z / 0.85).normalized())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return Toon.mesh(_body_root, Shapes.faceted(m), Vector3.ZERO, color, outline)


# --- head placement ----------------------------------------------------------------------------------

## A node stuck to the front of the head at (x sideways, y up) from the head's center,
## facing outward. Features are children of this anchor.
func _anchor(x: float, y: float, inset := 0.0) -> Node3D:
	var z := sqrt(maxf(HEAD_R * HEAD_R - x * x - y * y, 0.0001))
	var n := Vector3(x, y, z).normalized()
	var a := Node3D.new()
	a.position = Vector3(0, HEAD_R, 0) + n * (HEAD_R - inset)
	a.basis = Basis.looking_at(-n, Vector3.UP)
	_head.add_child(a)
	return a


# --- construction --------------------------------------------------------------------------------------

func _build_legs(skin: Color) -> void:
	# Two long, thin, slightly splayed legs and big smooth oval shoes.
	var pants := Color(look.get("pants", look.get("legs", skin)))
	var shorts: bool = look.get("shorts", false)
	var dressed := look.has("dress") or look.has("skirt") or look.has("robe")
	var shoe_c := Color(look.get("shoes", look.get("boots", "#6b4a35")))
	var lg := _leg_len / HIPS_Y
	var length := 0.47 * lg
	for side: int in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.124 * side * minf(_tw, 1.2), 0.0, 0.0)
		pivot.name = "Leg_L" if side == -1 else "Leg_R"
		_hips.add_child(pivot)
		_leg_splay.append(0.1 * side)
		var leg_skin := Color(look.get("socks", skin)) if (shorts or dressed) else pants
		Toon.mesh(pivot, Shapes.limb(length, 0.052, 0.062, 20), Vector3.ZERO, leg_skin if not (shorts or dressed) else skin, 0.01)
		if shorts:
			Toon.mesh(pivot, Shapes.limb(length * 0.4, 0.058, 0.066, 20), Vector3.ZERO, pants, 0.0)
		if look.has("socks"):
			var sk := Toon.mesh(pivot, Shapes.limb(length * 0.3, 0.063, 0.063, 20), Vector3(0, -length * 0.7, 0), Color(look.socks), 0.0)
			sk.name = "Sock"
		var boot := Node3D.new()
		boot.position = Vector3(0, -_leg_len, 0)
		boot.name = "Foot_L" if side == -1 else "Foot_R"
		boot.rotation.y = 0.42 * side
		pivot.add_child(boot)
		var sf := clampf(lg + 0.25, 0.65, 1.1)
		var shoe := Toon.mesh(boot, Shapes.shoe(0.31 * sf, 0.22 * sf, 0.42 * sf), Vector3(0, 0, 0), shoe_c, 0.012)
		shoe.name = "Shoe"
		if look.has("shoe_trim"):
			Toon.mesh(boot, Shapes.shoe(0.315 * sf, 0.05, 0.425 * sf), Vector3(0, 0, 0), Color(look.shoe_trim), 0.0)
		_legs.append(pivot)
		_boots.append(boot)


func _build_arms(skin: Color) -> void:
	# Long, thin arms from the shoulders, with little three-fingered mitten hands.
	var sleeves: String = str(look.get("sleeves", "short" if look.has("shirt") else "none"))
	var sleeve_c := Color(look.get("sleeve_color", look.get("shirt", skin)))
	var baby: bool = look.get("baby", false)
	var upper := 0.28 if baby else 0.355
	var fore := 0.28 if baby else 0.355
	for side: int in [-1, 1]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.165 * minf(_tw, 1.2) * side, 0.618, 0.0)
		shoulder.name = "Shoulder_L" if side == -1 else "Shoulder_R"
		_torso.add_child(shoulder)
		Toon.mesh(shoulder, Shapes.limb(upper + 0.04, 0.056, 0.05, 20), Vector3.ZERO, skin, 0.01)
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -upper, 0)
		elbow.name = "Elbow_L" if side == -1 else "Elbow_R"
		shoulder.add_child(elbow)
		Toon.mesh(elbow, Shapes.limb(fore + 0.03, 0.05, 0.046, 20), Vector3.ZERO, skin, 0.01)
		match sleeves:
			"short":
				Toon.mesh(shoulder, Shapes.limb(upper * 0.5, 0.064, 0.062, 20), Vector3.ZERO, sleeve_c, 0.0)
			"long":
				Toon.mesh(shoulder, Shapes.limb(upper + 0.05, 0.063, 0.058, 20), Vector3.ZERO, sleeve_c, 0.0)
				Toon.mesh(elbow, Shapes.limb(fore - 0.02, 0.058, 0.055, 20), Vector3(0, 0.03, 0), sleeve_c, 0.0)
				if look.has("cuffs"):
					Toon.mesh(elbow, Shapes.limb(0.05, 0.06, 0.06, 20), Vector3(0, -fore + 0.04, 0), Color(look.cuffs), 0.0)
		var wrist := Node3D.new()
		wrist.position = Vector3(0, -fore, 0)
		wrist.name = "Wrist_L" if side == -1 else "Wrist_R"
		elbow.add_child(wrist)
		var glove := Color(look.get("gloves", skin))
		var built := build_hand(wrist, glove, float(side), 1.1 if baby else 1.3, 0.009)
		_shoulders.append(shoulder)
		_elbows.append(elbow)
		_wrists.append(wrist)
		_hands.append(built[0])
		_fingers.append(built[1])
		if side == 1:
			hand_socket = Node3D.new()
			hand_socket.position = Vector3(0, -0.2, 0.0)
			(built[0] as Node3D).add_child(hand_socket)


## A cartoon mitten hand with a thumb and two stubby fingers, built hanging down -Y from
## the wrist, palm facing +Z. Returns [root, pivots] (finger, finger, thumb: rotate X to curl).
## Shared by every character, your first-person hands, the steering wheel and the kitchen cursor.
static func build_hand(parent: Node3D, skin: Color, side: float, size := 1.0, outline := 0.008) -> Array:
	var root := Node3D.new()
	root.scale = Vector3.ONE * size
	parent.add_child(root)
	var palm := Toon.ball(root, 0.058, Vector3(0, -0.05, 0), skin, outline, 28)
	palm.scale = Vector3(1.08, 1.0, 0.78)
	var pivots: Array[Node3D] = []
	for k in 2:
		var f := Node3D.new()
		var x := -0.026 + 0.052 * k
		f.position = Vector3(x * side, -0.09, 0.0)
		f.rotation.z = x * side * 4.5
		root.add_child(f)
		Toon.mesh(f, Shapes.limb(0.085, 0.031, 0.027, 20), Vector3.ZERO, skin, outline)
		pivots.append(f)
	var thumb := Node3D.new()
	thumb.position = Vector3(0.05 * side, -0.045, 0.01)
	thumb.rotation = Vector3(0.0, 0.0, 0.95 * side)
	root.add_child(thumb)
	Toon.mesh(thumb, Shapes.limb(0.07, 0.03, 0.026, 20), Vector3.ZERO, skin, outline)
	pivots.append(thumb)
	return [root, pivots]


## Curl the fingers: 0 = open hand, 1 = fist. Thumb folds in less.
static func curl_hand(pivots: Array, amount: float, index_out := false) -> void:
	for k in pivots.size():
		var f := pivots[k] as Node3D
		if k == pivots.size() - 1:
			f.rotation.x = -amount * 0.6
		elif index_out and k == 0:
			f.rotation.x = 0.0
		else:
			f.rotation.x = -amount * 1.5


func _build_face(skin: Color) -> void:
	# Simple goofy googly eyes on the big round head.
	var eye_style: String = look.get("eye", "normal")
	var w := 0.125
	var h := 0.145
	match eye_style:
		"big":
			w = 0.15
			h = 0.17
		"tiny":
			w = 0.08
			h = 0.09
		"sleepy":
			h = 0.09
	var eye_y := 0.035
	var brow_c := Color(look.get("brows", "#2b1c18"))
	for side: int in [-1, 1]:
		var goof := 1.0 if side == -1 else 1.07     # one eye a bit bigger
		var ew := w * goof
		var eh := h * goof
		var anchor := _anchor(0.1 * side, eye_y + (0.006 if side == 1 else 0.0))
		var eye := Node3D.new()
		anchor.add_child(eye)
		var white := Toon.ball(eye, 0.5, Vector3(0, 0, -0.012), Color("#fffdf8"), 0.012, 28)
		white.scale = Vector3(ew, eh, 0.06)
		var pupil := Node3D.new()
		pupil.position = Vector3(0.0, 0, 0.018)
		eye.add_child(pupil)
		var dot := Toon.ball(pupil, 0.5, Vector3(0, 0, 0.008), Color("#1a1020"), 0.0, 20)
		dot.scale = Vector3(ew * 0.44, ew * 0.44, 0.03)
		var shine := MeshInstance3D.new()
		shine.mesh = Shapes.ball(0.5, 12, 6)
		shine.material_override = Toon.glow(Color.WHITE, 1.0)
		shine.scale = Vector3(ew * 0.12, ew * 0.12, 0.02)
		shine.position = Vector3(ew * 0.07, ew * 0.07, 0.026)
		pupil.add_child(shine)
		_eyes.append(eye)
		_pupils.append(pupil)
		var banchor := _anchor(0.1 * side, eye_y + eh * 0.5 + 0.052)
		var brow := Node3D.new()
		banchor.add_child(brow)
		Toon.mesh(brow, Shapes.rounded_box(Vector3(0.1, 0.022, 0.024), 0.011, 20, 10), Vector3.ZERO, brow_c, 0.0)
		_brows.append(brow)
		_brow_base.append(brow.position.y)
		# soft blush
		var cheek := _anchor(0.185 * side, -0.065, -0.002)
		var tint := Color("#ff8fa3") if look.get("blush", false) else skin.lerp(Color("#ff9aa8"), 0.4)
		var bl := Toon.ball(cheek, 0.5, Vector3.ZERO, tint, 0.0, 16)
		bl.scale = Vector3(0.075, 0.045, 0.012)
	var manchor := _anchor(0.0, -0.115)
	var mpivot := Node3D.new()
	mpivot.scale = Vector3(0.085, 0.028, 0.03)
	manchor.add_child(mpivot)
	_mouth = Toon.mesh(mpivot, Shapes.ball(0.5, 20, 10), Vector3(0, 0, 0), Color("#7a2a33"), 0.0)
	if look.get("snout", false):
		var sn := _anchor(0.0, -0.06)
		Toon.ball(sn, 0.085, Vector3(0, 0, 0.04), skin.lightened(0.15), 0.01, 24).scale = Vector3(1.2, 0.9, 1.0)
		Toon.ball(sn, 0.036, Vector3(0, 0.03, 0.11), Color("#1d1517"), 0.0, 16)
	if look.get("mustache", false):
		var mc := Color(look.get("hair_color", "#2b1c18"))
		for side: int in [-1, 1]:
			var m := _anchor(0.05 * side, -0.082, -0.004)
			var slab := Toon.mesh(m, Shapes.rounded_box(Vector3(0.1, 0.045, 0.04), 0.02, 20, 10), Vector3.ZERO, mc, 0.006)
			slab.rotation.z = -0.35 * side
	if look.get("beard", false):
		var bd := _anchor(0.0, -0.17, -0.02)
		var beard := Toon.ball(bd, 0.5, Vector3(0, -0.02, 0), Color(look.get("hair_color", "#d9d4cc")), 0.01, 28)
		beard.scale = Vector3(0.3, 0.26, 0.2)
	if look.get("glasses", false):
		for side: int in [-1, 1]:
			var g := _anchor(0.1 * side, eye_y)
			var frame := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.087
			tm.outer_radius = 0.1
			tm.rings = 32
			tm.ring_segments = 10
			frame.mesh = tm
			frame.material_override = Toon.mat(Color(look.get("glasses_color", "#2b1c18")), 0.0)
			frame.rotation.x = PI / 2
			frame.position = Vector3(0, 0, 0.04)
			g.add_child(frame)
		var bridge := _anchor(0.0, eye_y + 0.01)
		Toon.mesh(bridge, Shapes.rounded_box(Vector3(0.07, 0.014, 0.014), 0.006), Vector3(0, 0, 0.045), Color(look.get("glasses_color", "#2b1c18")), 0.0)


## Hair: a smooth cap on the back/top of the head, plus twin tails / puffs / a bun.
func _build_hair(skin: Color) -> void:
	var style: String = str(look.get("hair_style", "cap" if look.has("hair") else "none"))
	if style == "none":
		return
	var col := Color(look.get("hair", look.get("hair_color", "#4a3328")))
	var cap := Toon.mesh(_head, Shapes.dome(HEAD_R * 1.045, 80), Vector3(0, HEAD_R, 0), col, 0.01)
	cap.rotation.x = -0.5
	match style:
		"twintails":
			for side: int in [-1, 1]:
				Toon.ball(_head, 0.085, Vector3(0.25 * side, HEAD_R + 0.12, -0.04), col, 0.008, 24)
				var tail := Toon.mesh(_head, Shapes.limb(0.55, 0.07, 0.025, 20), Vector3(0.3 * side, HEAD_R + 0.08, -0.05), col, 0.008)
				tail.rotation.z = 0.2 * side
		"puffs":
			for side: int in [-1, 1]:
				Toon.ball(_head, 0.11, Vector3(0.24 * side, HEAD_R + 0.16, -0.02), col, 0.008, 28)
		"long":
			var back := Toon.mesh(_head, Shapes.limb(0.5, 0.2, 0.12, 24), Vector3(0, HEAD_R + 0.1, -0.15), col, 0.008)
			back.scale = Vector3(1.0, 1.0, 0.45)


func _build_extras(skin: Color) -> void:
	var tie = look.get("tie", null)
	if tie != null:
		var t := Node3D.new()
		t.position = Vector3(0, 0.52, _tr(0.52) * _tw + 0.005)
		_body_root.add_child(t)
		Toon.ball(t, 0.035, Vector3(0, 0.0, 0.0), Color(tie), 0.006, 14)
		var tail := Toon.mesh(t, Shapes.rounded_box(Vector3(0.07, 0.24, 0.025), 0.012), Vector3(0, -0.15, 0.003), Color(tie), 0.006)
		tail.rotation.x = 0.1
	var apron = look.get("apron", null)
	if apron != null:
		_front_patch(0.03, 0.17, 0.4, 0.016, Color(apron), false)
		_front_patch(0.39, 0.12, 0.5, 0.02, Color(apron).darkened(0.08), false)
		for side: int in [-1, 1]:
			var strap := Toon.mesh(_body_root, Shapes.rounded_box(Vector3(0.03, 0.2, 0.012), 0.006), Vector3(0.1 * side, 0.55, _tr(0.55) * _tw + 0.012), Color(apron), 0.0)
			strap.rotation.z = -0.25 * side
	var bow = look.get("bow", null)
	if bow != null:
		var bw := Node3D.new()
		bw.position = Vector3(0, 0.55, _tr(0.55) * _tw + 0.01)
		_body_root.add_child(bw)
		for side: int in [-1, 1]:
			Toon.ball(bw, 0.06, Vector3(0.06 * side, 0, 0), Color(bow), 0.006, 16).scale = Vector3(1.2, 0.8, 0.6)
		Toon.ball(bw, 0.03, Vector3.ZERO, Color(bow).darkened(0.2), 0.0, 12)
	if look.has("scarf"):
		var sc := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.17
		tm.outer_radius = 0.225
		tm.rings = 40
		tm.ring_segments = 14
		sc.mesh = tm
		sc.material_override = Toon.mat(Color(look.scarf), 0.006)
		sc.position = Vector3(0, 0.6, 0)
		_torso.add_child(sc)
		var tail2 := Toon.mesh(_torso, Shapes.rounded_box(Vector3(0.08, 0.3, 0.025), 0.012), Vector3(0.1, 0.42, 0.2), Color(look.scarf), 0.006)
		tail2.rotation.z = 0.1
	if look.get("ears", false):
		var ec := Color(look.get("hair_color", skin.darkened(0.25)))
		for side: int in [-1, 1]:
			var ear := Toon.mesh(_head, Shapes.rounded_box(Vector3(0.1, 0.2, 0.05), 0.024, 24, 12), Vector3(0.2 * side, HEAD_R + 0.2, -0.02), ec, 0.008)
			ear.rotation.z = -0.55 * side
			ear.name = "Ear"
	if look.get("tail", false):
		_tail = Node3D.new()
		_tail.position = Vector3(0, 0.12, -0.26)
		_torso.add_child(_tail)
		var tl := Toon.mesh(_tail, Shapes.limb(0.34, 0.035, 0.055, 16), Vector3.ZERO, skin, 0.008)
		tl.rotation.x = PI - 0.7
	var cape = look.get("cape", null)
	if cape != null:
		var cp := _front_patch(0.0, 0.3, 0.6, 0.03, Color(cape), true)
		cp.name = "Cape"
		var clasp := Toon.ball(_torso, 0.03, Vector3(0, 0.6, 0.2), Color("#ffd166"), 0.0, 10)
		clasp.name = "Clasp"
	if look.has("star_robe"):
		for pp: Vector3 in [Vector3(0.1, 0.35, 0.0), Vector3(-0.12, 0.2, 0.0), Vector3(0.0, 0.12, 0.0), Vector3(0.08, -0.1, 0.0), Vector3(-0.1, -0.2, 0.0)]:
			var r := _tr(maxf(pp.y, 0.05)) * _tw + 0.014
			Toon.ball(_body_root, 0.022, Vector3(pp.x, pp.y, r if pp.y > 0.0 else 0.38), Color("#ffd166"), 0.0, 8)


func _build_hat() -> void:
	var hat: String = look.get("hat", "none")
	var col := Color(look.get("hat_color", "#c0392b"))
	var top := _hat
	var hr := HEAD_R * 0.98 + 0.012   # hat radius that fits the head
	match hat:
		"cap":
			var crown := Toon.mesh(top, Shapes.lathe(PackedVector2Array([Vector2(hr, 0), Vector2(hr * 0.99, 0.09), Vector2(hr * 0.93, 0.17), Vector2(hr * 0.78, 0.24), Vector2(hr * 0.5, 0.285), Vector2(0, 0.3)]), 40, 0.5), Vector3(0, -0.12, 0), Color(look.get("hat_front", "#e8dccb")), 0.012)
			crown.rotation.x = -0.1
			Toon.mesh(top, Shapes.lathe(PackedVector2Array([Vector2(hr + 0.01, 0), Vector2(hr + 0.01, 0.07), Vector2(0, 0.07)]), 40, 0.5), Vector3(0, -0.13, 0), col, 0.012)
			var brim := Toon.mesh(top, Shapes.chamfer_box(Vector3(hr * 1.2, 0.04, 0.32), 0.4), Vector3(0, -0.11, hr * 0.85), col, 0.01)
			brim.rotation.x = 0.14
		"chef":
			Toon.cyl(top, hr * 0.85, hr * 0.8, 0.3, Vector3(0, 0.05, 0), Color.WHITE, 0.012, 32)
			Toon.mesh(top, Shapes.blob(hr * 0.95, 11, 0.12), Vector3(0, 0.32, 0), Color.WHITE, 0.012).scale = Vector3(1.1, 0.75, 1.1)
		"wizard":
			Toon.cyl(top, hr * 1.5, hr * 1.5, 0.04, Vector3(0, -0.04, 0), col, 0.012, 32)
			var cone := Toon.cyl(top, 0.0, hr * 0.9, 0.85, Vector3(0.05, 0.38, 0), col, 0.012, 28)
			cone.rotation.z = -0.22
			Toon.ball(top, 0.06, Vector3(0.0, 0.25, hr * 0.75), Color("#ffd166"), 0.0, 6)
			Toon.ball(top, 0.04, Vector3(0.1, 0.45, hr * 0.5), Color("#ffd166"), 0.0, 6)
		"tinfoil":
			var foil := Toon.cyl(top, 0.0, hr * 1.05, 0.5, Vector3(0, 0.17, 0), Color("#d7dbe2"), 0.012, 5)
			foil.material_override = Toon.mat(Color("#dfe3ea"), 0.012, 0.25)
		"crown":
			Toon.cyl(top, hr * 0.7, hr * 0.66, 0.16, Vector3(0, 0.03, 0), Color("#ffd166"), 0.01, 10)
			for i in 5:
				var a := TAU * i / 5.0
				Toon.cyl(top, 0.0, 0.05, 0.12, Vector3(cos(a) * hr * 0.66, 0.17, sin(a) * hr * 0.66), Color("#ffd166"), 0.0, 4)
				Toon.ball(top, 0.03, Vector3(cos(a) * hr * 0.69, 0.06, sin(a) * hr * 0.69), Color("#e84393"), 0.0, 6)
		"beanie":
			Toon.mesh(top, Shapes.lathe(PackedVector2Array([Vector2(hr, 0), Vector2(hr * 0.95, 0.16), Vector2(hr * 0.6, 0.31), Vector2(0, 0.34)]), 12, 0.5), Vector3(0, -0.12, 0), col, 0.012)
			Toon.ball(top, 0.08, Vector3(0, 0.25, 0), col.lightened(0.3), 0.008, 8)
		"propeller":
			Toon.mesh(top, Shapes.lathe(PackedVector2Array([Vector2(hr, 0), Vector2(hr * 0.8, 0.16), Vector2(0, 0.2)]), 12, 0.5), Vector3(0, -0.1, 0), col, 0.012)
			var prop := Node3D.new()
			prop.name = "Propeller"
			prop.position = Vector3(0, 0.14, 0)
			top.add_child(prop)
			Toon.cyl(prop, 0.015, 0.015, 0.1, Vector3(0, -0.02, 0), Color("#555555"), 0.0, 4)
			Toon.box(prop, Vector3(0.5, 0.02, 0.08), Vector3(0, 0.04, 0), Color("#ffd166"), 0.006)
		"tophat":
			Toon.cyl(top, hr * 1.15, hr * 1.15, 0.04, Vector3(0, -0.04, 0), Color("#1d1517"), 0.012, 12)
			Toon.cyl(top, hr * 0.72, hr * 0.72, 0.42, Vector3(0, 0.18, 0), Color("#1d1517"), 0.012, 12)
			Toon.cyl(top, hr * 0.73, hr * 0.73, 0.06, Vector3(0, 0.02, 0), col, 0.0, 12)
		"headband":
			Toon.cyl(top, HEAD_R * 0.93, HEAD_R * 0.95, 0.07, Vector3(0, -0.07, 0), col, 0.008, 40)
		"headset":
			var arc := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = hr * 0.95
			tm.outer_radius = hr * 1.06
			tm.ring_segments = 4
			tm.rings = 14
			arc.mesh = Shapes.faceted(tm)
			arc.material_override = Toon.mat(Color("#2d3436"), 0.0)
			arc.rotation.z = PI / 2
			arc.position = Vector3(0, -0.183, 0)
			top.add_child(arc)
			for side: int in [-1, 1]:
				var cup := Toon.cyl(top, 0.1, 0.1, 0.07, Vector3((HEAD_R + 0.025) * side, -0.183, 0), col, 0.008, 20)
				cup.rotation.z = PI / 2
		"bun":
			Toon.mesh(top, Shapes.blob(0.17, 5, 0.1), Vector3(0, 0.07, -0.1), Color(look.get("hair_color", "#d9d4cc")), 0.01)
		"bow":
			for side: int in [-1, 1]:
				Toon.ball(top, 0.1, Vector3(0.12 * side, 0.03, 0.05), col, 0.008, 8).scale = Vector3(1.3, 0.9, 0.6)
			Toon.ball(top, 0.05, Vector3(0, 0.03, 0.06), col.darkened(0.2), 0.0, 6)
		"cowboy":
			Toon.cyl(top, hr * 1.7, hr * 1.7, 0.04, Vector3(0, -0.03, 0), col, 0.012, 14).scale = Vector3(1, 1, 0.8)
			Toon.cyl(top, hr * 0.68, hr * 0.82, 0.28, Vector3(0, 0.12, 0), col, 0.012, 10)


# --- public animation API ----------------------------------------------------------------------

## neutral, happy, angry, confused, excited, sad, scared, suspicious, in_love, smug
func express(emotion: String, hold := 4.0) -> void:
	_emotion = emotion
	_emotion_timer = hold


## One-shot animation. See ACTIONS for names.
func play(action: String) -> void:
	if not ACTIONS.has(action) or _tumble > 0.0:
		return
	_action = action
	_action_t = 0.0
	_action_dur = ACTIONS[action]
	if action == "hop" or action == "celebrate":
		_hop = 1.0


func is_playing() -> bool:
	return _action != ""


func hop() -> void:
	play("hop")


## Fall over and roll like an egg, then wobble back up dizzy.
func tumble(direction: Vector3, strength := 1.0) -> void:
	_tumble = 1.1 + strength * 0.5
	var flat := Vector3(direction.x, 0, direction.z)
	_tumble_dir = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	_getup = 0.0
	_action = ""
	express("scared", 2.5)


func is_tumbling() -> bool:
	return _tumble > 0.0 or _getup > 0.0


# --- springs ---------------------------------------------------------------------------------------

func _spring(name: String, target: float, delta: float, stiffness := 160.0, damping := 16.0) -> float:
	var st: Array = _spr.get(name, [target, 0.0])
	var x: float = st[0]
	var v: float = st[1]
	delta = minf(delta, 0.04)   # long frames would make the spring explode
	if not is_finite(x) or not is_finite(v):
		x = target
		v = 0.0
	v += (target - x) * stiffness * delta
	v *= exp(-damping * delta)
	x += v * delta
	_spr[name] = [x, v]
	return x


func _bump(name: String, impulse: float) -> void:
	var st: Array = _spr.get(name, [0.0, 0.0])
	st[1] = float(st[1]) + impulse
	_spr[name] = st


# --- per-frame ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _torso == null:
		return
	delta = minf(delta, 0.05)
	_t += delta
	_emotion_timer -= delta
	if _emotion_timer <= 0.0 and _emotion != "neutral":
		_emotion = "neutral"

	# Where are we going? (works for anything that moves us)
	var gp := global_position
	var measured := (gp - _last_pos) / maxf(delta, 0.0001)
	_last_pos = gp
	if measured.length() > 30.0:
		measured = Vector3.ZERO   # teleported
	var vel: Vector3 = velocity_hint if velocity_hint != Vector3.INF else measured
	vel.y = 0.0
	_vel = _vel.lerp(vel, 1.0 - exp(-12.0 * delta))
	var accel := (_vel - _prev_vel) / maxf(delta, 0.0001)
	_prev_vel = _vel
	var local_vel := global_basis.inverse() * _vel / maxf(_s, 0.01)
	var local_acc := global_basis.inverse() * accel / maxf(_s, 0.01)
	var ground_speed := local_vel.length()
	if velocity_hint == Vector3.INF and measured.length() < 0.05:
		ground_speed = speed * 1.4
	var moving := clampf(ground_speed / 1.6, 0.0, 2.0)

	if _tumble > 0.0 or _getup > 0.0:
		_animate_tumble(delta)
		_animate_face(delta, {"brow_tilt": 0.0, "brow_raise": 0.05, "eye": 1.25, "mouth_w": 0.8, "mouth_h": 3.0})
		return

	# 1. Locomotion ----------------------------------------------------------------
	var stride := 0.5
	var waddle := float(look.get("waddle", 0.5))
	var bounce := float(look.get("bounce", 0.5))
	if moving > 0.05:
		_phase += ground_speed * delta / stride * PI
	else:
		_phase = lerp_angle(_phase, roundf(_phase / PI) * PI, 1.0 - exp(-6.0 * delta))
	var step := sin(_phase)
	var walk := minf(moving, 1.2)
	var pose := {
		"lean_x": clampf(local_acc.z * 0.012 + local_vel.z * 0.05, -0.35, 0.35),   # lean into acceleration
		"lean_z": -step * 0.09 * waddle * walk + clampf(-local_acc.x * 0.01, -0.2, 0.2),
		"yaw": step * 0.12 * walk,
		"y": absf(cos(_phase)) * (0.04 + 0.05 * bounce) * walk,
		"squash": 1.0 + sin(_t * 2.1) * 0.012,
		"leg": [step * 0.6 * walk, -step * 0.6 * walk],
		"lift": [maxf(0.0, -cos(_phase)) * 0.09 * walk, maxf(0.0, cos(_phase)) * 0.09 * walk],
		"arm_out": [0.3 + 0.06 * walk, 0.3 + 0.06 * walk],
		"arm_fwd": [step * 0.5 * walk, -step * 0.5 * walk],
		"arm_bend": [-0.22 - 0.25 * walk, -0.22 - 0.25 * walk],
		"twist": [0.9, 0.9],          # palms toward the body
		"grip": [0.3, 0.3],           # relaxed fingers
		"brow_tilt": 0.0, "brow_raise": 0.0, "eye": 1.0, "mouth_w": 1.0, "mouth_h": 1.0,
	}
	# Idle: weight shift + random fidgets
	if moving < 0.05:
		pose.lean_z += sin(_t * 0.9) * 0.025
		pose.y += sin(_t * 2.1) * 0.006
		_idle_timer -= delta
		if idle_fidgets and _idle_timer <= 0.0 and _action == "" and not talking and not carrying and not waving:
			_idle_timer = randf_range(4.0, 9.0)
			play(["look_around", "tap_foot", "scratch", "look_around", "yawn", "nod"][randi() % 6])
	else:
		_idle_timer = maxf(_idle_timer, 2.0)

	# 2. Carrying / waiting / phone --------------------------------------------------
	if carrying:
		if carry_style == "overhead":
			pose.arm_out[1] = 2.95
			pose.arm_fwd[1] = 0.0
			pose.arm_bend[1] = -0.3
			pose.arm_out[0] = 0.7
			pose.arm_fwd[0] = 0.35
			pose.arm_bend[0] = -1.7       # hand on hip
		else:
			for i in 2:
				pose.arm_out[i] = 0.35
				pose.arm_fwd[i] = -0.9
				pose.arm_bend[i] = -1.0
	elif waving:
		pose.arm_out[1] = 2.5
		pose.arm_fwd[1] = 0.0
		pose.arm_bend[1] = -0.5 + sin(_t * 12.0) * 0.5
	if phone_mode:
		pose.arm_out[1] = 1.2
		pose.arm_fwd[1] = -0.3
		pose.arm_bend[1] = -2.3

	# 3. Talking gestures ----------------------------------------------------------------
	if talking and _action == "" and not carrying:
		pose.arm_out[0] = 0.45 + sin(_t * 4.6) * 0.25
		pose.arm_fwd[0] = -0.5 + sin(_t * 3.3) * 0.25
		pose.arm_bend[0] = -1.0
		if not waving and not phone_mode:
			pose.arm_out[1] = 0.45 + sin(_t * 3.9 + 1.0) * 0.3
			pose.arm_fwd[1] = -0.6 + sin(_t * 5.1 + 2.0) * 0.3
			pose.arm_bend[1] = -1.1
		pose.y += absf(sin(_t * 7.0)) * 0.015
		pose.lean_x += sin(_t * 3.0) * 0.03

	# 4. Emotion posture -------------------------------------------------------------------
	_apply_emotion(pose)

	# 5. One-shot action ----------------------------------------------------------------------
	if _action != "":
		_action_t += delta
		var u := clampf(_action_t / _action_dur, 0.0, 1.0)
		var w := minf(1.0, minf(u, 1.0 - u) * 6.0)   # ease in/out
		_apply_action(pose, _action, u, w)
		if u >= 1.0:
			_action = ""

	if flailing:
		for i in 2:
			pose.arm_out[i] = 2.4 + sin(_t * 30.0 + i) * 0.6
			pose.arm_fwd[i] = sin(_t * 25.0 + i * 2.0) * 1.2
			pose.arm_bend[i] = -0.4
		pose.leg = [sin(_t * 28.0) * 0.8, -sin(_t * 28.0) * 0.8]

	# Hands follow what the arms are doing.
	if carrying:
		pose.grip = [0.65, 0.65]
		pose.twist = [0.2, 0.2] if carry_style == "front" else [0.9, 0.0]
	if waving:
		pose.grip[1] = 0.0
		pose.twist[1] = 0.0
	if phone_mode:
		pose.grip[1] = 0.85
	if flailing:
		pose.grip = [0.0, 0.0]
	if talking and not carrying:
		pose.grip = [0.1 + sin(_t * 3.0) * 0.1, 0.15 + sin(_t * 2.4) * 0.15]
		pose.twist = [0.3, 0.3]
	for k in pose_override:
		pose[k] = pose_override[k]
	_apply_pose(pose, delta)
	_animate_face(delta, pose)


func _apply_emotion(pose: Dictionary) -> void:
	match _emotion:
		"angry":
			pose.brow_tilt = 0.45
			pose.brow_raise = -0.025
			if not carrying and not talking:
				for i in 2:
					pose.arm_out[i] = 0.5
					pose.arm_bend[i] = -0.6
			pose.lean_x += 0.08
		"happy", "in_love":
			pose.brow_raise = 0.03
			pose.mouth_w = 1.4
			pose.mouth_h = 2.2
			pose.y += absf(sin(_t * 6.0)) * 0.02
		"excited":
			pose.brow_raise = 0.04
			pose.mouth_w = 1.5
			pose.mouth_h = 3.0
			pose.y += absf(sin(_t * 9.0)) * 0.05
			if not carrying:
				pose.arm_out[0] = 2.2 + sin(_t * 14.0) * 0.3
				pose.arm_out[1] = 2.2 + sin(_t * 14.0 + PI) * 0.3
				pose.arm_fwd = [0.0, 0.0]
		"sad":
			pose.brow_tilt = -0.4
			pose.mouth_w = 0.7
			pose.lean_x += 0.18
			pose.y -= 0.03
			pose.arm_out = [0.08, 0.08]
		"scared", "surprised":
			pose.brow_raise = 0.05
			pose.eye = 1.25
			pose.mouth_w = 0.7
			pose.mouth_h = 4.0
			pose.lean_x -= 0.12
			pose.lean_z += sin(_t * 40.0) * 0.03
		"confused":
			pose.brow_tilt = 0.25
			pose.lean_z += 0.1
		"suspicious":
			pose.brow_tilt = 0.25
			pose.eye = 0.75
			pose.lean_x += 0.05
		"smug":
			pose.brow_tilt = 0.2
			pose.mouth_w = 1.3
			pose.lean_x -= 0.08
	if look.get("grumpy", false) and _emotion == "neutral":
		pose.brow_tilt = 0.3   # resting angry-face, like the poster


func _apply_action(pose: Dictionary, a: String, u: float, w: float) -> void:
	var t := u * _action_dur
	# Head motion that goes with the action (the head is its own part now)
	match a:
		"nod":
			pose["head_x"] = sin(u * TAU * 2.0) * 0.4 * w
		"shake_head":
			pose["head_y"] = sin(u * TAU * 3.0) * 0.5 * w
		"look_around":
			pose["head_y"] = sin(u * TAU) * 0.7 * w
		"yawn":
			pose["head_x"] = -0.4 * w
		"laugh":
			pose["head_x"] = -0.25 * w + sin(_t * 22.0) * 0.05 * w
		"facepalm":
			pose["head_x"] = 0.35 * w
		"scratch":
			pose["head_z"] = 0.25 * w
		"celebrate", "dance":
			pose["head_z"] = sin(_t * 8.0) * 0.18 * w
		"shrug":
			pose["head_z"] = 0.22 * w
	match a:
		"wave":
			pose.arm_out[1] = lerpf(pose.arm_out[1], 2.6, w)
			pose.arm_fwd[1] = lerpf(pose.arm_fwd[1], 0.0, w)
			pose.arm_bend[1] = lerpf(pose.arm_bend[1], -0.5 + sin(t * 13.0) * 0.6, w)
			pose.lean_z += 0.08 * w
		"knock":
			var rap := maxf(0.0, sin(t * 17.0))
			pose.arm_out[1] = lerpf(pose.arm_out[1], 0.55, w)
			pose.arm_fwd[1] = lerpf(pose.arm_fwd[1], -1.35 - rap * 0.2, w)
			pose.arm_bend[1] = lerpf(pose.arm_bend[1], -1.1 + rap * 0.6, w)
			pose.lean_x += 0.08 * w
		"celebrate":
			for i in 2:
				pose.arm_out[i] = lerpf(pose.arm_out[i], 2.7, w)
				pose.arm_fwd[i] = lerpf(pose.arm_fwd[i], 0.0, w)
				pose.arm_bend[i] = lerpf(pose.arm_bend[i], -0.15, w)
			pose.yaw += TAU * smoothstep(0.1, 0.7, u)
			pose.mouth_h = 3.0
			pose.brow_raise = 0.05
		"stomp":
			pose.y += absf(sin(u * PI * 3.0)) * 0.12 * w
			for i in 2:
				pose.arm_out[i] = lerpf(pose.arm_out[i], 0.35, w)
				pose.arm_fwd[i] = lerpf(pose.arm_fwd[i], 0.25, w)
				pose.arm_bend[i] = lerpf(pose.arm_bend[i], -0.2, w)
			pose.lean_z += sin(t * 30.0) * 0.06 * w
			pose.leg[0] -= absf(sin(u * PI * 3.0)) * 0.6 * w
			pose.brow_tilt = 0.5
		"laugh":
			pose.lean_x -= 0.25 * w
			pose.y += absf(sin(t * 18.0)) * 0.04 * w
			pose.squash += sin(t * 18.0) * 0.04 * w
			pose.mouth_h = 4.0
			pose.mouth_w = 1.5
			for i in 2:
				pose.arm_fwd[i] = lerpf(pose.arm_fwd[i], -0.7, w)
				pose.arm_bend[i] = lerpf(pose.arm_bend[i], -1.4, w)
				pose.arm_out[i] = lerpf(pose.arm_out[i], 0.5, w)
		"shrug":
			for i in 2:
				pose.arm_out[i] = lerpf(pose.arm_out[i], 1.0, w)
				pose.arm_fwd[i] = lerpf(pose.arm_fwd[i], -0.4, w)
				pose.arm_bend[i] = lerpf(pose.arm_bend[i], -1.4, w)
			pose.y += 0.04 * w
			pose.brow_raise = 0.05 * w
			pose.lean_z += 0.1 * w
		"point":
			pose.arm_out[1] = lerpf(pose.arm_out[1], 0.4, w)
			pose.arm_fwd[1] = lerpf(pose.arm_fwd[1], -1.55, w)
			pose.arm_bend[1] = lerpf(pose.arm_bend[1], 0.0, w)
			pose.lean_x += 0.1 * w
		"flex":
			for i in 2:
				pose.arm_out[i] = lerpf(pose.arm_out[i], 1.55, w)
				pose.arm_fwd[i] = lerpf(pose.arm_fwd[i], 0.0, w)
				pose.arm_bend[i] = lerpf(pose.arm_bend[i], -2.2 + sin(t * 10.0) * 0.15, w)
			pose.squash += 0.04 * w * sin(t * 10.0)
			pose.brow_tilt = 0.3
		"dance":
			var b := sin(t * 9.0)
			pose.lean_z += b * 0.2 * w
			pose.y += absf(b) * 0.06 * w
			pose.arm_out[0] = lerpf(pose.arm_out[0], 1.8 + b, w)
			pose.arm_out[1] = lerpf(pose.arm_out[1], 1.8 - b, w)
			pose.yaw += b * 0.3 * w
			pose.leg[0] += b * 0.4 * w
			pose.leg[1] -= b * 0.4 * w
		"yawn":
			for i in 2:
				pose.arm_out[i] = lerpf(pose.arm_out[i], 2.5, w)
				pose.arm_bend[i] = lerpf(pose.arm_bend[i], -0.6, w)
				pose.arm_fwd[i] = lerpf(pose.arm_fwd[i], 0.2, w)
			pose.lean_x -= 0.15 * w
			pose.squash += 0.06 * w
			pose.mouth_h = 1.0 + 5.0 * w
			pose.eye = 1.0 - 0.8 * w
		"scratch":
			pose.arm_out[1] = lerpf(pose.arm_out[1], 2.3, w)
			pose.arm_fwd[1] = lerpf(pose.arm_fwd[1], -0.2, w)
			pose.arm_bend[1] = lerpf(pose.arm_bend[1], -1.9 + sin(t * 22.0) * 0.25, w)
			pose.lean_z -= 0.1 * w
			pose.brow_tilt = 0.2
		"look_around":
			pose.yaw += sin(u * TAU) * 0.6 * w
			pose.lean_z += sin(u * TAU) * 0.05 * w
		"tap_foot":
			pose.leg[1] -= maxf(0.0, sin(t * 14.0)) * 0.25 * w
			pose.lift[1] += maxf(0.0, sin(t * 14.0)) * 0.05 * w
			for i in 2:
				pose.arm_out[i] = lerpf(pose.arm_out[i], 0.6, w)
				pose.arm_bend[i] = lerpf(pose.arm_bend[i], -1.6, w)
		"eat":
			var chomp := maxf(0.0, sin(t * 10.0))
			pose.arm_out[1] = lerpf(pose.arm_out[1], 0.6, w)
			pose.arm_fwd[1] = lerpf(pose.arm_fwd[1], -1.0, w)
			pose.arm_bend[1] = lerpf(pose.arm_bend[1], -2.0 - chomp * 0.2, w)
			pose.mouth_h = 1.0 + chomp * 3.0
		"hop":
			pose.squash += (-0.15 if u < 0.15 else (0.12 if u < 0.5 else 0.0)) * w
		"spin":
			pose.yaw += TAU * smoothstep(0.0, 1.0, u)
			for i in 2:
				pose.arm_out[i] = lerpf(pose.arm_out[i], 1.6, w)
		"nod":
			pose.lean_x += sin(u * TAU * 2.0) * 0.12 * w
		"shake_head":
			pose.yaw += sin(u * TAU * 3.0) * 0.25 * w
		"facepalm":
			pose.arm_out[1] = lerpf(pose.arm_out[1], 0.9, w)
			pose.arm_fwd[1] = lerpf(pose.arm_fwd[1], -1.2, w)
			pose.arm_bend[1] = lerpf(pose.arm_bend[1], -2.1, w)
			pose.lean_x += 0.15 * w
			pose.eye = 1.0 - 0.9 * w
		"slam":
			pose.arm_out[1] = lerpf(pose.arm_out[1], 0.5, w)
			pose.arm_fwd[1] = lerpf(pose.arm_fwd[1], -1.2 + sin(u * PI) * 0.8, w)
			pose.arm_bend[1] = lerpf(pose.arm_bend[1], -0.4, w)
			pose.lean_x += 0.2 * sin(u * PI) * w
		"work":
			# Generic busy hands at a counter.
			for i in 2:
				pose.arm_out[i] = lerpf(pose.arm_out[i], 0.45, w)
				pose.arm_fwd[i] = lerpf(pose.arm_fwd[i], -1.0 + sin(t * 9.0 + i * PI) * 0.25, w)
				pose.arm_bend[i] = lerpf(pose.arm_bend[i], -0.9 + sin(t * 7.0 + i) * 0.3, w)
			pose.lean_x += 0.15 * w


func _apply_pose(pose: Dictionary, delta: float) -> void:
	var land := _spring("land", 0.0, delta, 260.0, 12.0)
	_hop = maxf(0.0, _hop - delta * 1.8)
	# Jumps lift the whole egg (legs dangle); bobs only move the body.
	var hop_y := sin(clampf(_hop, 0.0, 1.0) * PI) * 0.55
	_rig.position.y = hop_y
	if hop_y > 0.02:
		pose.leg = [0.5, -0.3]
		pose.lift = [0.06, 0.1]
	var y := _spring("y", float(pose.y), delta, 220.0, 18.0)
	var lean_x := _spring("lean_x", pose.lean_x, delta, 120.0, 13.0)
	var lean_z := _spring("lean_z", pose.lean_z, delta, 120.0, 12.0)
	var squash := _spring("squash", float(pose.squash) + land, delta, 300.0, 14.0)
	_torso.position.y = y
	_torso.rotation = Vector3(lean_x, _spring("yaw", pose.yaw, delta, 90.0, 12.0), lean_z)
	var sq := clampf(squash, 0.7, 1.35)
	_torso.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
	# The head is its own part: it turns toward whoever it's looking at, nods while
	# talking and lags a little behind the body (secondary motion).
	var yaw_t := float(pose.get("head_y", 0.0))
	var pitch_t := float(pose.get("head_x", 0.0))
	if look_target and is_instance_valid(look_target):
		var lv := global_basis.inverse() * (look_target.global_position - global_position)
		yaw_t += clampf(atan2(lv.x, maxf(lv.z, 0.05)), -0.7, 0.7)
		pitch_t += clampf(-(lv.y - 1.2) * 0.12, -0.3, 0.3)
	if talking:
		pitch_t += sin(_t * 9.0) * 0.06
		yaw_t += sin(_t * 3.1) * 0.08
	if _emotion in ["sad", "scared"]:
		pitch_t += 0.18
	var hx := _spring("hx", pitch_t - (lean_x - float(pose.lean_x)) * 0.9, delta, 140.0, 13.0)
	var hy := _spring("hy", yaw_t, delta, 120.0, 13.0)
	var hz := _spring("hz", float(pose.get("head_z", 0.0)) - (lean_z - float(pose.lean_z)) * 0.8 - lean_z * 0.5, delta, 130.0, 12.0)
	_head.rotation = Vector3(hx, hy, hz)
	# Arms with follow-through (soft springs = a little overshoot)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var out := _spring("ao%d" % i, pose.arm_out[i], delta, 150.0, 11.0)
		var fwd := _spring("af%d" % i, pose.arm_fwd[i], delta, 150.0, 11.0)
		var bend := _spring("ab%d" % i, pose.arm_bend[i], delta, 170.0, 12.0)
		_shoulders[i].rotation = Vector3(fwd, 0, out * side)
		_elbows[i].rotation = Vector3(bend, 0, 0)
		if i < _wrists.size():
			var tw: Array = pose.get("twist", [0.9, 0.9])
			var gr: Array = pose.get("grip", [0.3, 0.3])
			_wrists[i].rotation.y = _spring("tw%d" % i, float(tw[i]) * side, delta, 140.0, 13.0)
			curl_hand(_fingers[i], _spring("gr%d" % i, float(gr[i]), delta, 200.0, 15.0))
	# Legs + boot lift
	for i in _legs.size():
		var swing := _spring("leg%d" % i, pose.leg[i], delta, 260.0, 18.0)
		_legs[i].rotation.x = swing
		_legs[i].rotation.z = _leg_splay[i]
		_boots[i].rotation.z = -_leg_splay[i]
		_boots[i].position.y = -_leg_len + float(pose.lift[i])
		_boots[i].rotation.x = -swing * 0.6
	# Hat lags behind the head (springy wobble)
	if _hat:
		_hat.rotation.x = _spring("hat_x", -(lean_x - float(pose.lean_x)) * 2.0 + (y - float(pose.y)) * 1.5, delta, 90.0, 7.0)
		_hat.rotation.z = _spring("hat_z", -(lean_z - float(pose.lean_z)) * 2.0, delta, 90.0, 7.0)
	if _tail:
		_tail.rotation.y = sin(_t * (22.0 if _emotion in ["happy", "excited", "in_love"] else 6.0)) * 0.7
	var prop := head_top.get_node_or_null("Propeller")
	if prop == null and _hat:
		prop = _hat.get_node_or_null("Propeller")
	if prop:
		prop.rotation.y += delta * (6.0 + _vel.length() * 8.0)
	# Landing from a hop: squash + bounce
	if _hop <= 0.0 and float(_spr.get("was_air", [0.0])[0]) > 0.5:
		_bump("land", -2.5)
	_spr["was_air"] = [1.0 if _hop > 0.1 else 0.0, 0.0]
	# Whatever we carry stays level.
	if hand_socket:
		hand_socket.global_basis = Basis(Vector3.UP, global_rotation.y).scaled(Vector3.ONE * _s)
		if carrying:
			var target := head_top.global_position + Vector3(0, 0.45 * _s, 0) if carry_style == "overhead" \
				else _torso.global_position + global_basis * Vector3(0, 0.38, 0.5) * 1.0
			hand_socket.global_position = hand_socket.global_position.lerp(target, 0.85)


func _animate_tumble(delta: float) -> void:
	if _tumble > 0.0:
		_tumble -= delta
		# Roll over onto the side, rocking like an egg on a table.
		var t := 1.0 - clampf(_tumble / 1.6, 0.0, 1.0)
		var rock := sin(_t * 9.0) * 0.35 * (1.0 - t)
		var axis := Vector3.UP.cross(_tumble_dir).normalized()
		var local_axis := (global_basis.inverse() * axis).normalized()
		_rig.basis = Basis(local_axis, deg_to_rad(80.0) + rock)
		_rig.position = Vector3(0, 0.3, 0)
		for i in 2:
			_shoulders[i].rotation = Vector3(sin(_t * 20.0 + i) * 1.0, 0, (2.0 + sin(_t * 25.0) * 0.5) * (-1.0 if i == 0 else 1.0))
		for l in _legs:
			l.rotation.x = sin(_t * 22.0) * 0.8
		if _tumble <= 0.0:
			_getup = 1.2
			_dizzy_t = 2.4
	elif _getup > 0.0:
		_getup -= delta
		# Wobble back up with a damped rock.
		var g := clampf(1.0 - _getup / 1.2, 0.0, 1.0)
		var wobble := sin(g * 22.0) * 0.4 * (1.0 - g)
		var axis2 := Vector3.UP.cross(_tumble_dir).normalized()
		var local_axis2 := (global_basis.inverse() * axis2).normalized()
		_rig.basis = Basis(local_axis2, lerpf(deg_to_rad(80.0), 0.0, ease(g, 0.4)) + wobble)
		_rig.position = Vector3(0, lerpf(0.3, 0.0, g), 0)
		if _getup <= 0.0:
			_rig.basis = Basis()
			_rig.position = Vector3.ZERO
	_dizzy_t = maxf(0.0, _dizzy_t - delta)


func _animate_face(delta: float, pose: Dictionary) -> void:
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 0.13
		_next_blink = randf_range(2.0, 5.0)
	_blink = maxf(0.0, _blink - delta)
	var open := 0.1 if _blink > 0.0 else 1.0
	var eye_scale := float(pose.get("eye", 1.0))
	for i in _brows.size():
		var side := -1.0 if i == 0 else 1.0
		var b := _brows[i]
		var tilt := float(pose.get("brow_tilt", 0.0))
		if _emotion == "suspicious" and i == 0:
			tilt = -0.2
		b.rotation.z = lerp_angle(b.rotation.z, -tilt * side, 0.3)
		b.position.y = lerpf(b.position.y, _brow_base[i] + float(pose.get("brow_raise", 0.0)), 0.3)
	for e in _eyes:
		e.scale = e.scale.lerp(Vector3(eye_scale, open * minf(eye_scale, 1.0) if open < 1.0 else eye_scale, 1.0), 0.5)
	var mh := float(pose.get("mouth_h", 1.0))
	if talking:
		mh = 1.0 + absf(sin(_t * 17.0)) * 4.0
	_mouth.scale = _mouth.scale.lerp(Vector3(float(pose.get("mouth_w", 1.0)), mh, 1.0), 0.4)
	# Pupils: look at the target if we have one, else wander.
	var look_off := Vector2(sin(_t * 0.7) * 0.004, cos(_t * 0.5) * 0.003)
	if look_target and is_instance_valid(look_target):
		var local := global_basis.inverse() * (look_target.global_position - global_position)
		look_off = Vector2(clampf(local.x * 0.012, -0.012, 0.012), clampf((local.y - 1.0) * 0.006, -0.008, 0.008))
	# Googly wobble: pupils lag behind and bounce when the egg moves or hops.
	_googly_v += (-_googly * 120.0 - _googly_v * 6.0) * delta
	_googly_v += Vector2(-_vel.x, absf(_land_squash) * 4.0 - _hop * 2.0) * delta * 0.4
	_googly += _googly_v * delta
	_googly = _googly.limit_length(0.014)
	if not _googly.is_finite():
		_googly = Vector2.ZERO
		_googly_v = Vector2.ZERO
	for p in _pupils:
		p.position = p.position.lerp(Vector3(look_off.x + _googly.x, look_off.y + _googly.y, 0.018), 0.25)
	if _dizzy:
		_dizzy.visible = _dizzy_t > 0.0
		_dizzy.rotation.y += delta * 6.0
