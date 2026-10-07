class_name Npc
extends Node3D
## A goofy cel-shaded resident built entirely from primitives: googly eyes,
## flappy mouth, bobbing idle, waving, and getting launched by your car.
##
## Built facing +Z (toward the street).

signal launched

const EMOTION_MARKS := {
	"happy": "♪", "angry": "#@!", "confused": "?", "excited": "!!", "sad": "...",
	"scared": "!?", "suspicious": "...?", "in_love": "♥", "smug": "heh",
}

var character: Dictionary = {}
## Claude conversation history with this NPC (kept across visits).
var history: Array = []
var mood := 0
var turns := 0
var waving := false
var talking := false
var hidden_inside := false
var look_target: Node3D

var _body: Node3D
var _head: Node3D
var _mouth: MeshInstance3D
var _pupils: Array[MeshInstance3D] = []
var _pupil_vel: Array[Vector2] = []
var _pupil_off: Array[Vector2] = []
var _pupil_base: Array[Vector3] = []
var _arm_r: Node3D
var _arm_l: Node3D
var _tail: Node3D
var _mark: Label3D
var _name_tag: Label3D
var voice: AudioStreamPlayer3D
var _t := 0.0
var _home := Vector3.ZERO
var _home_yaw := 0.0
var _fly_vel := Vector3.ZERO
var _flying := false
var _spin := 0.0
var _last_head_pos := Vector3.ZERO


func setup(c: Dictionary) -> void:
	character = c
	_t = randf() * 10.0
	_build()
	voice = AudioStreamPlayer3D.new()
	voice.unit_size = 8.0
	voice.max_db = 6.0
	voice.position = Vector3(0, 1.6, 0)
	add_child(voice)


func _ready() -> void:
	_home = position
	_home_yaw = rotation.y


func display_name() -> String:
	return character.get("name", "???")


# --- building ------------------------------------------------------------------

func _build() -> void:
	var look: Dictionary = character.get("look", {})
	_body = Node3D.new()
	add_child(_body)
	var kind: String = look.get("body", "human")
	match kind:
		"dog":
			_build_dog(look)
		"ghost":
			_build_ghost(look)
		_:
			_build_human(look, kind == "baby")
	var top := _head.position.y + 0.9 * float(look.get("head", 1.0))
	_mark = Toon.label(self, "", Vector3(0.5, top + 0.3, 0), 140, Color("#ffd166"))
	_name_tag = Toon.label(self, display_name(), Vector3(0, top + 0.05, 0), 56, Color.WHITE)
	_name_tag.visible = false


func _build_human(look: Dictionary, baby: bool) -> void:
	var h: float = look.get("height", 1.0)
	var skin := Color(look.get("skin", "#f2c4a0"))
	var shirt := Color(look.get("shirt", "#ffffff"))
	var pants := Color(look.get("pants", "#333333"))
	var belly: float = look.get("belly", 1.0)
	var leg_h := 0.75 * h * (0.6 if baby else 1.0)
	var torso_h := 0.95 * h
	# Legs
	for side in [-1, 1]:
		Toon.capsule(_body, 0.13 * h, leg_h, Vector3(0.16 * side * h, leg_h * 0.5, 0), pants)
		Toon.sphere(_body, 0.15 * h, Vector3(0.16 * side * h, 0.06, 0.08), Color("#3a2618"), 0.02, 0.6)
	# Torso (a robe is a cone instead)
	var torso_y := leg_h + torso_h * 0.42
	if look.get("robe", false):
		Toon.cylinder(_body, 0.22 * h, 0.55 * h, leg_h + torso_h * 0.7, Vector3(0, (leg_h + torso_h * 0.7) * 0.5, 0), shirt)
	else:
		var torso := Toon.capsule(_body, 0.3 * h, torso_h, Vector3(0, torso_y, 0), shirt)
		torso.scale = Vector3(belly, 1.0, belly)
	if baby:
		Toon.sphere(_body, 0.34 * h * belly, Vector3(0, leg_h + 0.05, 0), Color("#ffffff"), 0.03, 0.7)
	if look.get("tie", false):
		Toon.box(_body, Vector3(0.09, 0.45, 0.04) * h, Vector3(0, torso_y + 0.05, 0.31 * h * belly), Color("#d00000"), 0.015)
	# Arms (pivot at shoulder so they can wave)
	var arm_r := 0.11 * h * (1.6 if look.get("buff", false) else 1.0)
	var shoulder_y := leg_h + torso_h * 0.75
	for side in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3((0.33 * belly + 0.08) * h * side, shoulder_y, 0)
		_body.add_child(pivot)
		Toon.capsule(pivot, arm_r, 0.7 * h, Vector3(0, -0.3 * h, 0), shirt)
		Toon.sphere(pivot, arm_r * 1.1, Vector3(0, -0.66 * h, 0), skin, 0.02)
		pivot.rotation.z = 0.15 * side
		if side == 1:
			_arm_r = pivot
		else:
			_arm_l = pivot
	# Head
	var head_scale: float = look.get("head", 1.0) * h
	_head = Node3D.new()
	_head.position = Vector3(0, leg_h + torso_h + 0.32 * head_scale, 0)
	_body.add_child(_head)
	Toon.sphere(_head, 0.38 * head_scale, Vector3.ZERO, skin)
	_build_face(look, head_scale, skin)
	_build_hair_and_hat(look, head_scale)


func _build_face(look: Dictionary, s: float, skin: Color) -> void:
	var big: bool = look.get("big_eyes", false)
	var eye_r := (0.15 if big else 0.12) * s
	for side in [-1, 1]:
		var eye_pos := Vector3(0.14 * s * side, 0.06 * s, 0.31 * s)
		Toon.sphere(_head, eye_r, eye_pos, Color.WHITE, 0.015)
		var pupil := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = eye_r * 0.55
		pm.height = eye_r * 1.1
		pupil.mesh = pm
		pupil.material_override = Toon.pupil_mat()
		pupil.position = eye_pos + Vector3(0, 0, eye_r * 0.7)
		_head.add_child(pupil)
		_pupils.append(pupil)
		_pupil_base.append(pupil.position)
		_pupil_vel.append(Vector2.ZERO)
		_pupil_off.append(Vector2.ZERO)
		if look.get("glasses", false):
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = eye_r * 1.05
			tm.outer_radius = eye_r * 1.3
			ring.mesh = tm
			ring.material_override = Toon.mat(Color("#1b1b1b"), 0.0)
			ring.rotation.x = PI / 2
			ring.position = eye_pos + Vector3(0, 0, eye_r * 0.6)
			_head.add_child(ring)
	# Blush stickers. Very anime.
	for side in [-1, 1]:
		var blush := Toon.sphere(_head, 0.06 * s, Vector3(0.24 * s * side, -0.07 * s, 0.29 * s), Color("#ff8fab"), 0.0, 0.4)
		blush.rotation.x = PI / 2
	_mouth = Toon.sphere(_head, 0.08 * s, Vector3(0, -0.15 * s, 0.33 * s), Color("#5c1a1b"), 0.01, 0.35)
	if look.get("mustache", false):
		Toon.capsule(_head, 0.05 * s, 0.32 * s, Vector3(0, -0.08 * s, 0.36 * s), Color(look.get("hair", "#222222"))).rotation.z = PI / 2
	if look.get("beard", false):
		var beard := Toon.sphere(_head, 0.28 * s, Vector3(0, -0.28 * s, 0.12 * s), Color(look.get("hair", "#999999")), 0.02, 1.2)
		beard.scale = Vector3(1.0, 1.0, 0.8)
	# Nose
	Toon.sphere(_head, 0.05 * s, Vector3(0, -0.04 * s, 0.38 * s), skin.darkened(0.08), 0.01)


func _build_hair_and_hat(look: Dictionary, s: float) -> void:
	var hair := Color(look.get("hair", "#222222"))
	var hat: String = look.get("hat", "none")
	if hat != "wizard" and hat != "chef" and hat != "tinfoil":
		var cap := Toon.sphere(_head, 0.4 * s, Vector3(0, 0.08 * s, -0.05 * s), hair, 0.03, 0.85)
		cap.scale = Vector3(1.02, 1.0, 1.02)
	if look.get("pigtails", false):
		for side in [-1, 1]:
			Toon.sphere(_head, 0.17 * s, Vector3(0.4 * s * side, 0.15 * s, -0.1 * s), hair, 0.025)
	match hat:
		"chef":
			Toon.cylinder(_head, 0.3 * s, 0.26 * s, 0.35 * s, Vector3(0, 0.42 * s, 0), Color.WHITE)
			Toon.sphere(_head, 0.34 * s, Vector3(0, 0.66 * s, 0), Color.WHITE, 0.03, 0.7)
		"wizard":
			Toon.cylinder(_head, 0.55 * s, 0.55 * s, 0.04 * s, Vector3(0, 0.28 * s, 0), Color("#3a0ca3"))
			var cone := Toon.cylinder(_head, 0.0, 0.34 * s, 0.9 * s, Vector3(0, 0.72 * s, 0), Color("#3a0ca3"))
			cone.rotation.z = 0.25
			Toon.label(_head, "★", Vector3(0, 0.6 * s, 0.3 * s), 64, Color("#ffd166"), false)
		"tinfoil":
			var foil := Toon.cylinder(_head, 0.0, 0.4 * s, 0.55 * s, Vector3(0, 0.45 * s, 0), Color("#d9dde3"))
			foil.material_override = Toon.mat(Color("#e6e9ef"), 0.03, true, 0.25)
		"cap":
			Toon.sphere(_head, 0.4 * s, Vector3(0, 0.12 * s, 0), Color("#d62828"), 0.03, 0.6)
			Toon.box(_head, Vector3(0.4, 0.04, 0.3) * s, Vector3(0, 0.12 * s, 0.4 * s), Color("#d62828"), 0.015)
		"headband":
			var band := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.37 * s
			tm.outer_radius = 0.43 * s
			band.mesh = tm
			band.material_override = Toon.mat(Color("#ff006e"), 0.015)
			band.position = Vector3(0, 0.18 * s, 0)
			_head.add_child(band)
		"bow":
			for side in [-1, 1]:
				Toon.sphere(_head, 0.12 * s, Vector3(0.12 * s * side, 0.4 * s, 0.05 * s), Color("#ff4d8d"), 0.02, 0.8)
		"crown":
			Toon.cylinder(_head, 0.24 * s, 0.22 * s, 0.18 * s, Vector3(0, 0.42 * s, 0), Color("#ffd166"))
			for i in 5:
				var a := TAU * i / 5.0
				Toon.sphere(_head, 0.05 * s, Vector3(cos(a) * 0.23 * s, 0.53 * s, sin(a) * 0.23 * s), Color("#ff4d8d"), 0.01)
		"bun":
			Toon.sphere(_head, 0.18 * s, Vector3(0, 0.45 * s, -0.12 * s), Color(look.get("hair", "#cccccc")), 0.025)
		"headset":
			var arc := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.4 * s
			tm.outer_radius = 0.45 * s
			arc.mesh = tm
			arc.material_override = Toon.mat(Color("#222222"), 0.015)
			arc.rotation.z = PI / 2
			_head.add_child(arc)
			for side in [-1, 1]:
				Toon.cylinder(_head, 0.13 * s, 0.13 * s, 0.1 * s, Vector3(0.4 * s * side, 0, 0), Color("#06d6a0")).rotation.z = PI / 2


func _build_dog(look: Dictionary) -> void:
	var fur := Color(look.get("skin", "#e9b44c"))
	var dark := Color(look.get("hair", "#b5651d"))
	var body := Toon.capsule(_body, 0.32, 1.2, Vector3(0, 0.62, -0.1), fur)
	body.rotation.x = PI / 2
	for x in [-0.2, 0.2]:
		for z in [-0.45, 0.3]:
			Toon.capsule(_body, 0.09, 0.5, Vector3(x, 0.25, z), fur)
	# Collar
	Toon.cylinder(_body, 0.24, 0.26, 0.08, Vector3(0, 0.95, 0.38), Color(look.get("shirt", "#d62828")))
	_head = Node3D.new()
	_head.position = Vector3(0, 1.15, 0.5)
	_body.add_child(_head)
	Toon.sphere(_head, 0.33, Vector3.ZERO, fur)
	Toon.sphere(_head, 0.17, Vector3(0, -0.1, 0.3), fur.lightened(0.2), 0.02)
	Toon.sphere(_head, 0.06, Vector3(0, -0.02, 0.46), Color("#1b1b1b"), 0.01)
	for side in [-1, 1]:
		var ear := Toon.capsule(_head, 0.09, 0.4, Vector3(0.3 * side, 0.02, -0.05), dark)
		ear.rotation.z = 0.35 * side
	_build_face({"big_eyes": true}, 0.9, fur)
	_mouth.position = Vector3(0, -0.22, 0.33)
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.75, -0.75)
	_body.add_child(_tail)
	var tail_mesh := Toon.capsule(_tail, 0.06, 0.45, Vector3(0, 0.18, -0.05), fur)
	tail_mesh.rotation.x = -0.6


func _build_ghost(look: Dictionary) -> void:
	var sheet := Color(look.get("skin", "#f8f9fa"))
	Toon.cylinder(_body, 0.42, 0.62, 1.1, Vector3(0, 0.85, 0), sheet)
	_head = Node3D.new()
	_head.position = Vector3(0, 1.45, 0)
	_body.add_child(_head)
	Toon.sphere(_head, 0.44, Vector3.ZERO, sheet)
	# Wavy sheet hem
	for i in 7:
		var a := TAU * i / 7.0
		Toon.sphere(_body, 0.14, Vector3(cos(a) * 0.55, 0.3, sin(a) * 0.55), sheet, 0.02)
	for side in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.48 * side, 1.15, 0)
		_body.add_child(pivot)
		Toon.capsule(pivot, 0.1, 0.5, Vector3(0, -0.2, 0.05), sheet)
		if side == 1:
			_arm_r = pivot
		else:
			_arm_l = pivot
	_build_face({"big_eyes": true}, 1.1, sheet)


# --- behavior --------------------------------------------------------------------

func set_waving(on: bool) -> void:
	waving = on


func set_talking(on: bool) -> void:
	talking = on


func show_name(on: bool) -> void:
	_name_tag.visible = on


func show_emotion(emotion: String) -> void:
	_mark.text = EMOTION_MARKS.get(emotion, "")
	_mark.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(_mark, "scale", Vector3.ONE * 1.3, 0.15).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_mark, "scale", Vector3.ONE, 0.1)


func say(stream: AudioStream) -> void:
	if stream == null:
		return
	voice.stream = stream
	voice.volume_db = linear_to_db(maxf(Settings.voice_volume, 0.0001))
	voice.play()


func is_speaking() -> bool:
	return (voice != null and voice.playing) or DisplayServer.tts_is_speaking()


## Happy jump + spin.
func celebrate() -> void:
	var tw := create_tween()
	tw.tween_property(_body, "position:y", 1.2, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_body, "rotation:y", TAU, 0.5)
	tw.tween_property(_body, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _body.rotation.y = 0.0)


## Storms inside, slams the door, comes back out later.
func storm_inside(back_after := 12.0) -> void:
	hidden_inside = true
	var tw := create_tween()
	tw.tween_property(_body, "scale", Vector3(1.3, 0.6, 1.3), 0.1)
	tw.tween_property(_body, "scale", Vector3(0.01, 0.01, 0.01), 0.2)
	tw.tween_callback(func(): Sfx.play("slam"))
	tw.tween_interval(back_after)
	tw.tween_callback(func(): hidden_inside = false)
	tw.tween_property(_body, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC)


func is_flying() -> bool:
	return _flying


## Got hit by the car. YEET.
func launch(from_velocity: Vector3) -> void:
	if _flying or hidden_inside:
		return
	_flying = true
	_fly_vel = from_velocity * 0.9 + Vector3(0, 9.0, 0)
	_spin = randf_range(10.0, 20.0) * (1 if randf() < 0.5 else -1)
	mood -= 2
	show_emotion("angry")
	say(Sfx.babble("WAAAAAAGH!!!", character.get("voice", {}).get("babble", 220.0) * 1.3, 1.6))
	launched.emit()


func _process(delta: float) -> void:
	_t += delta
	if _flying:
		_fly_vel.y -= 25.0 * delta
		position += _fly_vel * delta
		rotation.x += _spin * delta
		if position.y <= _home.y and _fly_vel.y < 0.0:
			_flying = false
			position = _home
			rotation = Vector3(0, _home_yaw, 0)
			Sfx.play("splat", randf_range(0.8, 1.2))
			var tw := create_tween()
			tw.tween_property(_body, "scale", Vector3(1.4, 0.5, 1.4), 0.08)
			tw.tween_property(_body, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC)
		return

	var is_ghost: bool = character.get("look", {}).get("body", "") == "ghost"
	var bob := sin(_t * (6.0 if talking else 2.2)) * (0.05 if talking else 0.025)
	if is_ghost:
		bob += 0.35 + sin(_t * 1.3) * 0.15
	if not hidden_inside:
		_body.position.y = lerpf(_body.position.y, bob, 0.3)

	# Turn to face whoever we're looking at.
	if look_target and is_instance_valid(look_target):
		var to := look_target.global_position - global_position
		var yaw := atan2(to.x, to.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-5.0 * delta))
	else:
		rotation.y = lerp_angle(rotation.y, _home_yaw, 1.0 - exp(-3.0 * delta))

	# Arms
	if _arm_r:
		var target_r := (2.6 + sin(_t * 14.0) * 0.4) if waving else (0.15 + sin(_t * 2.0) * 0.05)
		if talking and not waving:
			target_r = 0.6 + sin(_t * 5.0) * 0.5
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, target_r, 0.2)
	if _arm_l:
		var target_l := -0.15 - sin(_t * 2.0) * 0.05
		if talking:
			target_l = -0.5 - sin(_t * 4.0 + 1.0) * 0.4
		_arm_l.rotation.z = lerpf(_arm_l.rotation.z, target_l, 0.2)
	if _tail:
		_tail.rotation.y = sin(_t * (25.0 if mood >= 0 else 4.0)) * 0.7

	# Mouth flaps while the voice plays.
	if _mouth:
		var open := 0.35
		if is_speaking():
			open = 0.35 + absf(sin(_t * 18.0)) * 1.4
		_mouth.scale.y = lerpf(_mouth.scale.y, open / 0.35, 0.5)

	# Googly eye physics: pupils lag behind head motion and bounce around.
	var head_pos := _head.global_position
	var head_vel := (head_pos - _last_head_pos) / maxf(delta, 0.001)
	_last_head_pos = head_pos
	var local_push := Vector2(-head_vel.x, -head_vel.y) * 0.02
	for i in _pupils.size():
		var v := _pupil_vel[i]
		var o := _pupil_off[i]
		v += (local_push - o * 60.0) * delta
		v.y -= 2.0 * delta
		v *= 0.9
		o += v * delta * 8.0
		o = o.limit_length(0.045)
		_pupil_vel[i] = v
		_pupil_off[i] = o
		_pupils[i].position = _pupil_base[i] + Vector3(o.x, o.y, 0.0)
