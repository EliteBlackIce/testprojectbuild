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
var _knees: Array[Node3D] = []
var _leg_splay: Array[float] = []
var _shoulders: Array[Node3D] = []   ## [left, right]
var _elbows: Array[Node3D] = []
var _last_plant := 0.0
var _acc_local := Vector3.ZERO           ## smoothed body acceleration, arms trail behind it
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
signal ragdoll_finished(root_position: Vector3)
var ragdoll_relocate := true  ## after a fall, stand up where the body landed (false for the first-person player)
var relocator := Callable()   ## optional: controller that moves itself to (position, yaw) instead of us
var _rd: Ragdoll
var _rd_state := 0            ## 0 normal, 1 flying/rolling, 2 lying there, 3 getting back up
var _rd_t := 0.0
var _rd_still := 0.0
var _rd_lie := 0.6
var _rd_start: Dictionary = {}
var _rd_last: Array = []
var _rest: Dictionary = {}     ## local transforms of the animated parts, as built
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
	for n in _tracked():
		_rest[n] = n.transform
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
	# Cloth that bulges out in the middle and melts into the body at its edges (no hard rim).
	var cols := 20
	var rows := 16
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rows + 1:
		var ui := float(i) / rows
		var y := lerpf(y0, y1, ui)
		var r := _tr(y) * _tw
		var hw := minf(half_w, r * 0.97)
		var wy := smoothstep(0.0, 0.18, minf(ui, 1.0 - ui) * 2.0)
		for j in cols + 1:
			var uj := float(j) / cols
			var x := lerpf(-hw, hw, uj)
			var wx := smoothstep(0.0, 0.2, minf(uj, 1.0 - uj) * 2.0)
			var z := sqrt(maxf(r * r - x * x, 0.0)) + 0.003 + lift * minf(wy, wx)
			st.add_vertex(Vector3(x, y, -z if back else z))
	for i in rows:
		for j in cols:
			var a0 := i * (cols + 1) + j
			var a1 := a0 + 1
			var b0 := a0 + cols + 1
			var b1 := b0 + 1
			if back:
				st.add_index(a0)
				st.add_index(a1)
				st.add_index(b0)
				st.add_index(a1)
				st.add_index(b1)
				st.add_index(b0)
			else:
				st.add_index(a0)
				st.add_index(b0)
				st.add_index(a1)
				st.add_index(a1)
				st.add_index(b0)
				st.add_index(b1)
	st.generate_normals()
	return Toon.mesh(_body_root, st.commit(), Vector3.ZERO, color, outline)


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
	# Two long, thin, slightly splayed legs with real knees and big smooth oval shoes.
	var pants := Color(look.get("pants", look.get("legs", skin)))
	var shorts: bool = look.get("shorts", false)
	var dressed := look.has("dress") or look.has("skirt") or look.has("robe")
	var shoe_c := Color(look.get("shoes", look.get("boots", "#6b4a35")))
	var lg := _leg_len / HIPS_Y
	var length := 0.47 * lg
	var knee_y := 0.30 * lg
	var leg_col := skin if (shorts or dressed) else pants
	for side: int in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.124 * side * minf(_tw, 1.2), 0.0, 0.0)
		pivot.name = "Leg_L" if side == -1 else "Leg_R"
		_hips.add_child(pivot)
		_leg_splay.append(0.1 * side)
		Toon.mesh(pivot, Shapes.limb(knee_y + 0.02, 0.052, 0.057, 20), Vector3.ZERO, leg_col, 0.01)
		if shorts:
			Toon.mesh(pivot, Shapes.limb(length * 0.4, 0.058, 0.066, 20), Vector3.ZERO, pants, 0.0)
		var knee := Node3D.new()
		knee.position = Vector3(0, -knee_y, 0)
		knee.name = "Knee_L" if side == -1 else "Knee_R"
		pivot.add_child(knee)
		Toon.mesh(knee, Shapes.limb(length - knee_y + 0.12, 0.057, 0.062, 20), Vector3.ZERO, leg_col, 0.01)
		if look.has("socks"):
			var sk := Toon.mesh(knee, Shapes.limb(length * 0.3, 0.063, 0.063, 20), Vector3(0, -0.03, 0), Color(look.socks), 0.0)
			sk.name = "Sock"
		var boot := Node3D.new()
		boot.position = Vector3(0, -(_leg_len - knee_y), 0)
		boot.name = "Foot_L" if side == -1 else "Foot_R"
		boot.rotation.y = 0.42 * side
		knee.add_child(boot)
		var sf := clampf(lg + 0.25, 0.65, 1.1)
		var shoe := Toon.mesh(boot, Shapes.shoe(0.31 * sf, 0.22 * sf, 0.42 * sf), Vector3(0, 0, 0), shoe_c, 0.012)
		shoe.name = "Shoe"
		if look.has("shoe_trim"):
			Toon.mesh(boot, Shapes.shoe(0.315 * sf, 0.05, 0.425 * sf), Vector3(0, 0, 0), Color(look.shoe_trim), 0.0)
		_legs.append(pivot)
		_knees.append(knee)
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
static func curl_hand(pivots: Array, amount: float, index_out := false, t := 0.0, loose := 0.0) -> void:
	# `loose` > 0 lets each finger drift on its own (relaxed hands are never frozen).
	for k in pivots.size():
		var f := pivots[k] as Node3D
		var drift := sin(t * 1.9 + k * 2.1) * 0.09 * loose
		if k == pivots.size() - 1:
			f.rotation.x = -amount * 0.6 + drift * 0.6
		elif index_out and k == 0:
			f.rotation.x = 0.0
		else:
			f.rotation.x = -amount * (1.5 + 0.12 * k) + drift


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
			var m := _anchor(0.055 * side, -0.082, -0.004)
			var slab := Toon.ball(m, 0.5, Vector3.ZERO, mc, 0.006, 24)
			slab.scale = Vector3(0.115, 0.05, 0.05)
			slab.rotation.z = -0.3 * side
	if look.get("beard", false):
		# a smooth bib of beard hugging the jaw, tapering to nothing at its edges (mouth stays visible)
		var bc := Color(look.get("hair_color", "#d9d4cc"))
		_shell(_head, Vector3(0, HEAD_R, 0), 118, 172, 0.065, bc, 0.4, Vector3(1.0, 1.0, 1.1), 0.01, deg_to_rad(125.0)).name = "Beard"
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


## Hair: a smooth shell over the skull (thickest on top, fading out at the hairline), plus
## twin tails / puffs / a long back.
func _build_hair(skin: Color) -> void:
	var style: String = str(look.get("hair_style", "cap" if look.has("hair") else "none"))
	if style == "none":
		return
	var col := Color(look.get("hair", look.get("hair_color", "#4a3328")))
	var hc := Vector3(0, HEAD_R, 0)
	var cap := _shell(_head, hc, 0, 84, 0.05, col, 0.1, Vector3(1.02, 1.03, 1.02), 0.01)
	cap.rotation.x = -0.6
	cap.name = "Hair"
	match style:
		"twintails":
			for side: int in [-1, 1]:
				Toon.ball(_head, 0.09, Vector3(0.25 * side, HEAD_R + 0.12, -0.04), col, 0.008, 28)
				var tail := Toon.mesh(_head, Shapes.limb(0.55, 0.075, 0.022, 24), Vector3(0.3 * side, HEAD_R + 0.08, -0.05), col, 0.008)
				tail.rotation.z = 0.2 * side
		"puffs":
			for side: int in [-1, 1]:
				Toon.ball(_head, 0.115, Vector3(0.24 * side, HEAD_R + 0.16, -0.02), col, 0.008, 32)
		"long":
			var back := Toon.mesh(_head, Shapes.limb(0.5, 0.2, 0.12, 28), Vector3(0, HEAD_R + 0.1, -0.15), col, 0.008)
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
			var ear := Toon.ball(_head, 0.5, Vector3(0.2 * side, HEAD_R + 0.2, -0.02), ec, 0.008, 28)
			ear.scale = Vector3(0.11, 0.21, 0.055)
			ear.rotation.z = -0.55 * side
			ear.name = "Ear"
	if look.get("tail", false):
		_tail = Node3D.new()
		_tail.position = Vector3(0, 0.12, -0.26)
		_torso.add_child(_tail)
		Toon.ball(_tail, 0.06, Vector3.ZERO, skin, 0.0, 20)
		var tl := Toon.mesh(_tail, Shapes.limb(0.34, 0.035, 0.055, 20), Vector3.ZERO, skin, 0.008)
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


## A shell of hair/cloth hugging the skull (see Shapes.head_shell): fades to nothing at its edges.
func _shell(parent: Node3D, center: Vector3, polar0_deg: float, polar1_deg: float, thick: float, color: Color, taper := 0.25, bulge := Vector3.ONE, outline := 0.01, az_half := PI, az_center := 0.0) -> MeshInstance3D:
	var m := Shapes.head_shell(HEAD_R + 0.004, deg_to_rad(polar0_deg), deg_to_rad(polar1_deg), az_half, thick, taper, bulge, 56, 28, az_center)
	return Toon.mesh(parent, m, center, color, outline)


func _curve(parent: Node3D, ctrl: Array, pos: Vector3, color: Color, outline := 0.012, segs := 48) -> MeshInstance3D:
	return Toon.mesh(parent, Shapes.spline_lathe(ctrl, segs, 6), pos, color, outline)


func _v2(list: Array) -> Array:
	var out: Array = []
	for i in range(0, list.size(), 2):
		out.append(Vector2(list[i], list[i + 1]))
	return out


func _build_hat() -> void:
	var hat: String = look.get("hat", "none")
	var col := Color(look.get("hat_color", "#c0392b"))
	var top := _hat
	var R := HEAD_R + 0.004
	var hc := Vector3(0, 0.1 - HEAD_R, 0)      # the head's center, in hat space
	var hair_lift := 0.05 if look.has("hair") else 0.0
	match hat:
		"cap":
			_shell(top, hc, 0, 66, 0.036, Color(look.get("hat_front", "#e8dccb")), 0.15, Vector3(1, 1.06, 1))
			_shell(top, hc, 52, 70, 0.044, col, 0.4)
			var visor := Toon.mesh(top, Shapes.ball(0.5, 32, 14), hc + Vector3(0, 0.15, 0.38), col, 0.01)
			visor.scale = Vector3(0.5, 0.045, 0.36)
			visor.rotation.x = 0.16
		"chef":
			_shell(top, hc, 44, 62, 0.045, Color.WHITE, 0.35)
			_curve(top, _v2([0.17, 0.0, 0.2, 0.08, 0.22, 0.2, 0.26, 0.29, 0.3, 0.36, 0.3, 0.43, 0.25, 0.49, 0.15, 0.525, 0.0, 0.535]), hc + Vector3(0, 0.15, 0), Color.WHITE)
		"wizard":
			_curve(top, _v2([0.0, 0.0, 0.25, 0.0, 0.42, -0.015, 0.52, 0.0, 0.545, 0.03, 0.52, 0.048, 0.4, 0.035, 0.25, 0.035, 0.0, 0.035]), hc + Vector3(0, 0.17, 0), col)
			var wp := Node3D.new()
			wp.position = hc + Vector3(0, 0.18, 0)
			wp.rotation.z = -0.2
			top.add_child(wp)
			_curve(wp, _v2([0.262, 0.0, 0.235, 0.14, 0.17, 0.32, 0.095, 0.5, 0.035, 0.64, 0.0, 0.7]), Vector3.ZERO, col)
			_shell(top, hc, 46, 62, 0.04, col.darkened(0.25), 0.4)
			Toon.ball(wp, 0.05, Vector3(0.0, 0.2, 0.21), Color("#ffd166"), 0.0, 14)
			Toon.ball(wp, 0.035, Vector3(0.09, 0.42, 0.1), Color("#ffd166"), 0.0, 12)
			Toon.ball(wp, 0.03, Vector3(-0.08, 0.33, 0.14), Color("#ffd166"), 0.0, 12)
		"tinfoil":
			_shell(top, hc, 46, 64, 0.03, Color("#cfd4dc"), 0.4)
			var foil := _curve(top, _v2([0.235, 0.0, 0.21, 0.12, 0.16, 0.26, 0.1, 0.4, 0.045, 0.52, 0.0, 0.6]), hc + Vector3(0, 0.17, 0), Color("#dfe3ea"))
			foil.material_override = Toon.mat(Color("#dfe3ea"), 0.012, 0.25)
		"crown":
			var gold := Color("#ffd166")
			_curve(top, _v2([0.215, 0.0, 0.23, 0.02, 0.232, 0.1, 0.218, 0.15, 0.2, 0.15, 0.2, 0.0]), hc + Vector3(0, 0.2 + hair_lift, 0), gold, 0.01)
			for i in 5:
				var an := TAU * i / 5.0
				var px := cos(an) * 0.218
				var pz := sin(an) * 0.218
				_curve(top, _v2([0.05, 0.0, 0.034, 0.07, 0.0, 0.14]), hc + Vector3(px, 0.34 + hair_lift, pz), gold, 0.006, 20)
				Toon.ball(top, 0.028, hc + Vector3(cos(an) * 0.234, 0.27 + hair_lift, sin(an) * 0.234), Color("#e84393"), 0.0, 12)
		"beanie":
			_shell(top, hc, 0, 66, 0.062, col, 0.12, Vector3(1, 1.07, 1))
			_shell(top, hc, 50, 72, 0.09, col.darkened(0.12), 0.4)
			Toon.ball(top, 0.085, hc + Vector3(0, R * 1.07 + 0.075, 0), col.lightened(0.3), 0.008, 24)
		"propeller":
			_shell(top, hc, 0, 64, 0.036, col, 0.15, Vector3(1, 1.05, 1))
			_shell(top, hc, 50, 68, 0.045, col.lightened(0.2), 0.4)
			var prop := Node3D.new()
			prop.name = "Propeller"
			prop.position = Vector3(0, 0.14, 0)
			top.add_child(prop)
			Toon.cyl(prop, 0.015, 0.015, 0.1, Vector3(0, -0.02, 0), Color("#555555"), 0.0, 10)
			var blade := Toon.mesh(prop, Shapes.ball(0.5, 24, 10), Vector3(0, 0.04, 0), Color("#ffd166"), 0.006)
			blade.scale = Vector3(0.5, 0.025, 0.09)
		"tophat":
			var black := Color("#1d1517")
			_curve(top, _v2([0.0, 0.0, 0.3, 0.0, 0.4, -0.005, 0.455, 0.0, 0.468, 0.022, 0.455, 0.042, 0.3, 0.046, 0.0, 0.046]), hc + Vector3(0, 0.17, 0), black)
			_curve(top, _v2([0.2, 0.0, 0.205, 0.1, 0.205, 0.3, 0.2, 0.42, 0.185, 0.46, 0.1, 0.476, 0.0, 0.476]), hc + Vector3(0, 0.19, 0), black)
			_curve(top, _v2([0.21, 0.0, 0.212, 0.03, 0.21, 0.065, 0.18, 0.065, 0.18, 0.0]), hc + Vector3(0, 0.22, 0), col, 0.0)
		"headband":
			_shell(top, hc, 54, 68, 0.038, col, 0.4, Vector3.ONE, 0.008)
		"headset":
			var dark := Color("#2d3436")
			var path := PackedVector3Array()
			for k in 25:
				var an := lerpf(-PI * 0.5, PI * 0.5, float(k) / 24.0)
				path.append(hc + Vector3(sin(an) * (R + 0.03), cos(an) * (R + 0.03), 0.0))
			Toon.mesh(top, Shapes.tube(path, 0.02, 12, false), Vector3.ZERO, dark, 0.006)
			for side: int in [-1, 1]:
				var cup := Toon.ball(top, 0.1, hc + Vector3((R + 0.035) * side, 0, 0), col, 0.008, 24)
				cup.scale = Vector3(0.55, 1.05, 0.95)
			var boom := PackedVector3Array([hc + Vector3(R + 0.06, 0.0, 0.02), hc + Vector3(R + 0.07, -0.08, 0.12), hc + Vector3(0.24, -0.14, 0.27), hc + Vector3(0.09, -0.135, 0.31)])
			Toon.mesh(top, Shapes.tube(boom, 0.011, 8, true), Vector3.ZERO, dark, 0.0)
			Toon.ball(top, 0.03, hc + Vector3(0.085, -0.135, 0.315), dark, 0.0, 12)
		"bun":
			Toon.ball(top, 0.17, Vector3(0, 0.07, -0.1), Color(look.get("hair_color", "#d9d4cc")), 0.01, 32)
		"bow":
			for side: int in [-1, 1]:
				var lobe := Toon.ball(top, 0.1, Vector3(0.12 * side, 0.03, 0.05), col, 0.008, 24)
				lobe.scale = Vector3(1.3, 0.9, 0.6)
			Toon.ball(top, 0.05, Vector3(0, 0.03, 0.06), col.darkened(0.2), 0.0, 16)
		"cowboy":
			_curve(top, _v2([0.0, 0.0, 0.35, 0.0, 0.52, 0.02, 0.62, 0.08, 0.64, 0.105, 0.6, 0.105, 0.5, 0.055, 0.35, 0.035, 0.0, 0.035]), hc + Vector3(0, 0.17, 0), col)
			_curve(top, _v2([0.2, 0.0, 0.2, 0.1, 0.18, 0.2, 0.14, 0.245, 0.08, 0.238, 0.0, 0.205]), hc + Vector3(0, 0.18, 0), col.lightened(0.05))


# --- public animation API ----------------------------------------------------------------------

## neutral, happy, angry, confused, excited, sad, scared, suspicious, in_love, smug
func express(emotion: String, hold := 4.0) -> void:
	_emotion = emotion
	_emotion_timer = hold


## One-shot animation. See ACTIONS for names.
func play(action: String) -> void:
	if not ACTIONS.has(action) or _rd_state == 1 or _rd_state == 2:
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


## Knock the egg down. Small hits just make it flinch; real ones turn it into a ragdoll
## that flies, flops and slides, then lies there a moment before scrambling back up.
## Returns roughly how long the whole thing takes (so controllers can wait).
func tumble(direction: Vector3, strength := 1.0) -> float:
	var flat := Vector3(direction.x, 0, direction.z)
	var dir := flat.normalized() if flat.length() > 0.01 else global_basis.z
	strength = clampf(strength, 0.2, 3.0)
	if strength < 0.45:
		flinch(dir, strength)
		return 0.5
	if _rd_state == 1 or _rd_state == 2:
		_rd.shove(dir * (3.0 + 3.0 * strength) + Vector3(0, 2.0, 0))
		_rd_state = 1
		_rd_still = 0.0
		return 2.4
	_start_ragdoll(dir, strength)
	return 3.6 + strength * 0.3


## A small hit: the whole body jolts away and springs back, arms flapping.
func flinch(direction: Vector3, strength := 0.5) -> void:
	var local := global_basis.inverse() * direction
	_bump("lean_x", -local.z * 5.0 * strength)
	_bump("lean_z", local.x * 5.0 * strength)
	_bump("land", -3.0 * strength)
	for i in 2:
		_bump("af%d" % i, randf_range(-8.0, 8.0) * strength)
		_bump("ao%d" % i, randf_range(2.0, 7.0) * strength)
	express("scared", 1.5)


func is_tumbling() -> bool:
	return _rd_state != 0


# --- ragdoll -----------------------------------------------------------------------------------------

func _start_ragdoll(dir: Vector3, strength: float) -> void:
	_action = ""
	flailing = false
	_hop = 0.0
	waving = false
	var P := Ragdoll.P
	var pts: Array = []
	pts.resize(Ragdoll.COUNT)
	pts[P.HEAD] = _head.to_global(Vector3(0, HEAD_R, 0))
	pts[P.NECK] = _head.global_position
	pts[P.CHEST] = _torso.to_global(Vector3(0, 0.3, 0))
	pts[P.PELVIS] = _hips.global_position
	for i in 2:
		pts[P.SHL + i] = _shoulders[i].global_position
		pts[P.ELL + i] = _elbows[i].global_position
		pts[P.HANDL + i] = _wrists[i].to_global(Vector3(0, -0.12, 0))
		pts[P.HIPL + i] = _legs[i].global_position if i < _legs.size() else _hips.to_global(Vector3(0.124 * (i * 2 - 1), 0, 0))
		pts[P.FOOTL + i] = _boots[i].global_position if i < _boots.size() else _hips.to_global(Vector3(0.124 * (i * 2 - 1), -_leg_len, 0))
	_rig.basis = Basis()
	_rig.position = Vector3.ZERO
	_torso.scale = Vector3.ONE
	var sp: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	_rd = Ragdoll.new()
	_rd.setup(pts, _s, Vector3(_vel.x, 0.0, _vel.z), sp, global_position.y)
	_rd.shove(dir * (2.6 + 2.8 * strength) + Vector3(0, 1.8 + 1.5 * strength, 0), 1.2)
	# arms, legs and head start out flailing in different directions
	for i in 2:
		_rd.kick(P.HANDL + i, Vector3(randf_range(-3, 3), randf_range(0, 4), randf_range(-3, 3)) * strength)
		_rd.kick(P.FOOTL + i, Vector3(randf_range(-2, 2), randf_range(0, 3), randf_range(-2, 2)) * strength)
	_rd.kick(P.HEAD, Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)))
	_rd_last = Array(_rd.pos)
	_rd_state = 1
	_rd_t = 0.0
	_rd_still = 0.0
	_rd_lie = randf_range(0.5, 0.9)
	_dizzy_t = 0.0
	express("scared", 3.0)
	for i in 2:
		curl_hand(_fingers[i], 0.0)


func _ragdoll_process(delta: float) -> void:
	var P := Ragdoll.P
	_rd_t += delta
	_rd.step(delta)
	_rd.collide_walls(_rd_last)
	_rd_last = Array(_rd.pos)
	_ragdoll_pose()
	_vel = _rd.velocity_of(P.PELVIS)
	_vel.y = 0.0
	if _rd_state == 1:
		if _rd.time > 0.8 and _rd.energy() < 2.0:
			_rd_still += delta
		else:
			_rd_still = 0.0
		if _rd_still > 0.25 or _rd.time > 3.4:
			_rd_state = 2
			_rd_t = 0.0
	elif _rd_state == 2:
		# lying dazed: a limp little wiggle of the fingers
		for i in 2:
			curl_hand(_fingers[i], 0.25 + sin(_t * 3.0 + i) * 0.15)
		if _rd_t > _rd_lie:
			_begin_getup()


func _frame(up: Vector3, right: Vector3) -> Basis:
	var y := up.normalized()
	var x := right - y * right.dot(y)
	if x.length() < 0.001:
		x = y.cross(Vector3.FORWARD)
		if x.length() < 0.001:
			x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


func _down(dir: Vector3, ref: Vector3) -> Basis:
	return _frame(-dir, ref)


func _set_global(n: Node3D, b: Basis, origin: Vector3, gs: float) -> void:
	n.global_transform = Transform3D(b.scaled(Vector3.ONE * gs), origin)


func _ragdoll_pose() -> void:
	var P := Ragdoll.P
	var p := _rd.pos
	var gs := global_basis.get_scale().x
	var tb := _frame(p[P.NECK] - p[P.PELVIS], p[P.SHR] - p[P.SHL])
	var hb := _frame(p[P.CHEST] - p[P.PELVIS], p[P.HIPR] - p[P.HIPL])
	_set_global(_hips, hb, p[P.PELVIS], gs)
	_set_global(_torso, tb, p[P.PELVIS], gs)
	_set_global(_head, _frame(p[P.HEAD] - p[P.NECK], tb.x), p[P.NECK], gs)
	for i in 2:
		_set_global(_shoulders[i], _down(p[P.ELL + i] - p[P.SHL + i], tb.x), p[P.SHL + i], gs)
		_set_global(_elbows[i], _down(p[P.HANDL + i] - p[P.ELL + i], tb.x), p[P.ELL + i], gs)
		if i < _legs.size():
			_set_global(_legs[i], _down(p[P.FOOTL + i] - p[P.HIPL + i], hb.x), p[P.HIPL + i], gs)
			_knees[i].rotation = Vector3(0.25 + 0.3 * sin(_t * 9.0 + i * 2.0) if _rd_state == 1 else 0.45, 0, 0)
			_boots[i].rotation.x = 0.0
		_wrists[i].rotation = Vector3(sin(_t * 11.0 + i * 2.0) * 0.5, 0.0, sin(_t * 9.0 + i) * 0.4)
		if _rd_state == 1:
			curl_hand(_fingers[i], 0.15 + 0.2 * sin(_t * 14.0 + i * 3.0))
	_hat.rotation = _hat.rotation.lerp(Vector3(sin(_t * 8.0) * 0.4, 0, cos(_t * 7.0) * 0.4), 0.2)


func _begin_getup() -> void:
	var P := Ragdoll.P
	var p := _rd.pos
	if ragdoll_relocate:
		var tb := _frame(p[P.NECK] - p[P.PELVIS], p[P.SHR] - p[P.SHL])
		var f := tb.z
		var flat := Vector3(f.x, 0, f.z)
		var yaw := global_rotation.y
		if flat.length() > 0.4:
			yaw = atan2(flat.x, flat.z)
		var land := Vector3(p[P.PELVIS].x, _rd.floor_y[P.PELVIS], p[P.PELVIS].z)
		if relocator.is_valid():
			relocator.call(land, yaw)
		else:
			global_position = land
			global_rotation = Vector3(0, yaw, 0)
	_rd_start.clear()
	for n in _tracked():
		_rd_start[n] = n.global_transform
	_rd_state = 3
	_rd_t = 0.0
	_dizzy_t = 2.4
	_last_pos = global_position
	_vel = Vector3.ZERO
	ragdoll_finished.emit(global_position)


func _tracked() -> Array[Node3D]:
	var out: Array[Node3D] = [_hips, _torso, _head]
	for i in 2:
		out.append(_shoulders[i])
	for i in 2:
		out.append(_elbows[i])
	for l in _legs:
		out.append(l)
	return out


## Scrambling back up: the normal standing animation is blended in over the lying pose,
## with an overshoot so the egg pops up and wobbles.
func _ragdoll_getup_blend(delta: float) -> void:
	_rd_t += delta
	var u := clampf(_rd_t / 0.9, 0.0, 1.0)
	var c1 := 1.9
	var c3 := c1 + 1.0
	var k := 1.0 + c3 * pow(u - 1.0, 3.0) + c1 * pow(u - 1.0, 2.0)
	var nodes := _tracked()
	var anim: Array[Transform3D] = []
	for n in nodes:
		anim.append(n.global_transform)
	for i in nodes.size():
		var from: Transform3D = _rd_start[nodes[i]]
		nodes[i].global_transform = from.interpolate_with(anim[i], k)
	if u >= 1.0:
		_rd_state = 0
		_rd = null
		_rd_start.clear()


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
	_acc_local = _acc_local.lerp(local_acc, 1.0 - exp(-14.0 * delta))
	var ground_speed := local_vel.length()
	if velocity_hint == Vector3.INF and measured.length() < 0.05:
		ground_speed = speed * 1.4
	var moving := clampf(ground_speed / 1.6, 0.0, 2.0)

	if _rd_state == 3:
		for n in _tracked():
			n.transform = _rest[n]       # the normal animation below starts from the standing rig each frame
	if _rd_state == 1 or _rd_state == 2:
		_ragdoll_process(delta)
		_animate_face(delta, {"brow_tilt": 0.0, "brow_raise": 0.08, "eye": 1.35, "mouth_w": 0.8, "mouth_h": 3.0})
		return

	# 1. Locomotion ----------------------------------------------------------------
	# A real gait: legs and knees on a phase clock, opposite-arm swing, hips that sway and twist
	# against the shoulders, a head that stays level, and a squish on every footfall.
	var waddle := float(look.get("waddle", 0.5))
	var bounce := float(look.get("bounce", 0.5))
	var run_t := smoothstep(2.0, 3.8, ground_speed)
	var stride := lerpf(0.5, 0.82, run_t)
	if moving > 0.05:
		_phase += ground_speed * delta / stride * PI
	else:
		_phase = lerp_angle(_phase, roundf(_phase / PI) * PI, 1.0 - exp(-6.0 * delta))
	var walk := minf(moving, 1.0)
	var s0 := sin(_phase)
	var c0 := cos(_phase)
	var amp := lerpf(0.5, 0.9, run_t) * walk
	var k_amp := lerpf(0.75, 1.8, run_t)
	var shift := sin(_t * 0.6)                        # idle weight shift
	var still := 1.0 - walk
	var pose := {
		"lean_x": clampf(local_acc.z * 0.012 + local_vel.z * 0.05, -0.35, 0.35) + (0.04 + 0.2 * run_t) * walk,
		"lean_z": -s0 * 0.1 * waddle * walk * (1.0 + run_t * 0.3) + clampf(-local_acc.x * 0.01, -0.2, 0.2) + shift * 0.03 * still,
		"yaw": s0 * 0.2 * walk,
		"hip_yaw": -s0 * 0.1 * walk,
		"hip_roll": s0 * 0.05 * waddle * walk + shift * 0.03 * still,
		"head_y": -s0 * 0.1 * walk,
		"y": absf(c0) * (0.025 + 0.05 * bounce) * walk * (1.0 + run_t),
		"squash": 1.0 + sin(_t * 2.1) * 0.012,
		"leg": [s0 * amp + shift * 0.05 * still, -s0 * amp - shift * 0.05 * still],
		"knee": [walk * (0.1 + pow(maxf(0.0, -c0), 1.2) * k_amp) + maxf(0.0, shift) * 0.25 * still, walk * (0.1 + pow(maxf(0.0, c0), 1.2) * k_amp) + maxf(0.0, -shift) * 0.25 * still],
		"foot": [s0 * 0.45 * walk, -s0 * 0.45 * walk],
		"lift": [0.0, 0.0],
		"arm_out": [0.28 + 0.07 * walk + absf(s0) * 0.08 * walk, 0.28 + 0.07 * walk + absf(s0) * 0.08 * walk],
		"arm_fwd": [-s0 * lerpf(0.65, 0.78, run_t) * walk, s0 * lerpf(0.65, 0.78, run_t) * walk],
		"arm_bend": [-0.3 - lerpf(0.15, 0.55, run_t) * walk, -0.3 - lerpf(0.15, 0.55, run_t) * walk],
		"twist": [0.9, 0.9],          # palms toward the body
		"grip": [0.3, 0.3],           # relaxed fingers
		"brow_tilt": 0.0, "brow_raise": 0.0, "eye": 1.0, "mouth_w": 1.0, "mouth_h": 1.0,
	}
	# A squish on every footfall (the sign of sin flips each time a foot lands)
	var plant := signf(s0)
	if walk > 0.3 and plant != _last_plant and _last_plant != 0.0:
		_bump("land", -(1.4 + run_t * 2.0))
		_bump("hx", 0.9 + run_t * 1.2)
	_last_plant = plant if absf(s0) > 0.02 else _last_plant
	# Idle: weight shift + random fidgets
	if moving < 0.05:
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
		pose.knee = [0.6 + sin(_t * 28.0) * 0.5, 0.6 - sin(_t * 28.0) * 0.5]

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
	if _rd_state == 3:
		_ragdoll_getup_blend(delta)


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
			pose.knee[1] += maxf(0.0, sin(t * 14.0)) * 0.4 * w
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
		pose.knee = [1.0, 0.5]
		pose.foot = [0.4, 0.3]
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
	# Arms: each segment is its own soft spring so the shoulder leads, the elbow follows
	# a beat later and the hand trails last (overlapping action). On top of the pose:
	# breathing drift, inertia when the body speeds up, forearm tuck on the forward
	# swing, wrist flop and loose fingers.
	var calm := 1.0 if _action == "" and not talking else 0.35
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var breathe := sin(_t * 2.1 + i * 0.6)
		var out_t := float(pose.arm_out[i]) + (sin(_t * 1.25 + i * 1.7) * 0.035 + breathe * 0.012) * calm
		var fwd_t := float(pose.arm_fwd[i]) + sin(_t * 0.85 + i * 2.3) * 0.05 * calm + clampf(_acc_local.z * 0.035, -0.4, 0.4) * calm
		var bend_t := float(pose.arm_bend[i])
		if fwd_t < 0.0 and float(pose.arm_out[i]) < 1.0:
			bend_t += fwd_t * 0.5                 # forearm tucks forward as the arm swings forward
			out_t += -fwd_t * 0.1                 # and the arm flares out a little
		bend_t += sin(_t * 1.6 + i) * 0.04 * calm
		var out := _spring("ao%d" % i, out_t, delta, 150.0, 11.0)
		var fwd := _spring("af%d" % i, fwd_t, delta, 170.0, 12.0)
		var bend := _spring("ab%d" % i, bend_t, delta, 105.0, 8.5)
		_shoulders[i].rotation = Vector3(fwd, 0, out * side)
		_shoulders[i].position.y = 0.618 + breathe * 0.004 + clampf(float(pose.arm_out[i]) - 1.4, 0.0, 1.0) * 0.02
		_elbows[i].rotation = Vector3(bend, 0, 0)
		if i < _wrists.size():
			var tw: Array = pose.get("twist", [0.9, 0.9])
			var gr: Array = pose.get("grip", [0.3, 0.3])
			_wrists[i].rotation.y = _spring("tw%d" % i, float(tw[i]) * side, delta, 140.0, 13.0)
			# The hand flops behind the arm's motion.
			var vf: float = (_spr.get("af%d" % i, [0.0, 0.0]) as Array)[1]
			var vo: float = (_spr.get("ao%d" % i, [0.0, 0.0]) as Array)[1]
			var vb: float = (_spr.get("ab%d" % i, [0.0, 0.0]) as Array)[1]
			_wrists[i].rotation.x = _spring("wx%d" % i, clampf((vf + vb * 0.6) * 0.07, -0.6, 0.6), delta, 120.0, 7.0)
			_wrists[i].rotation.z = _spring("wz%d" % i, clampf(vo * 0.06, -0.5, 0.5) * side, delta, 120.0, 7.0)
			var speed_curl := clampf((absf(vf) + absf(vb)) * 0.025, 0.0, 0.25)
			curl_hand(_fingers[i], _spring("gr%d" % i, float(gr[i]) + speed_curl, delta, 200.0, 15.0), false, _t + i * 2.0, 1.0 - clampf(float(gr[i]), 0.0, 1.0))
	# Legs: hip swing, knee bend, foot pitch. The hips sink as the legs spread so the planted
	# foot stays on the ground; the whole pelvis sways and twists a little.
	var lgf := _leg_len / HIPS_Y
	var knee_len := 0.30 * lgf
	var shin_len := _leg_len - knee_len
	var reach := 0.0
	for i in _legs.size():
		var swing := _spring("leg%d" % i, pose.leg[i], delta, 210.0, 15.0)
		var knee := maxf(0.0, _spring("kn%d" % i, pose.knee[i], delta, 240.0, 16.0))
		var foot := _spring("ft%d" % i, pose.foot[i], delta, 190.0, 11.0)
		_legs[i].rotation.x = swing
		_legs[i].rotation.z = _leg_splay[i]
		_knees[i].rotation.x = knee
		_boots[i].rotation.z = -_leg_splay[i]
		_boots[i].rotation.x = foot - swing - knee
		reach = maxf(reach, knee_len * cos(swing) + shin_len * cos(swing + knee))
	if _legs.size() > 0:
		_hips.position.y = _spring("hips_y", clampf(reach, _leg_len * 0.55, _leg_len), delta, 420.0, 26.0)
	_hips.rotation = Vector3(0.0, _spring("hip_yaw", float(pose.get("hip_yaw", 0.0)), delta, 120.0, 12.0), _spring("hip_roll", float(pose.get("hip_roll", 0.0)), delta, 120.0, 11.0))
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
	_dizzy_t = maxf(0.0, _dizzy_t - delta)
	if _dizzy:
		_dizzy.visible = _dizzy_t > 0.0
		_dizzy.rotation.y += delta * 6.0
