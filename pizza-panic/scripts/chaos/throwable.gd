class_name Throwable
extends RigidBody3D
## A loose prop you can pick up (RIGHT CLICK / G) and chuck (CLICK). Everything
## in the kitchen that isn't nailed down: rubber chickens, pans, tomatoes, a
## suspiciously heavy anvil. Anything fast enough bonks whichever egg it hits.

const KINDS := {
	"chicken": {"nice": "rubber chicken", "mass": 0.5, "r": 0.2, "bounce": 0.6, "sound": "boing", "pitch": 2.2},
	"pan": {"nice": "frying pan", "mass": 1.6, "r": 0.28, "bounce": 0.2, "sound": "bonk", "pitch": 0.9},
	"tomato": {"nice": "tomato", "mass": 0.3, "r": 0.11, "bounce": 0.1, "sound": "splat", "pitch": 1.0},
	"cone": {"nice": "traffic cone", "mass": 0.8, "r": 0.2, "bounce": 0.3, "sound": "bonk", "pitch": 1.6},
	"bucket": {"nice": "mop bucket", "mass": 1.2, "r": 0.2, "bounce": 0.3, "sound": "bonk", "pitch": 0.7},
	"watermelon": {"nice": "watermelon", "mass": 5.0, "r": 0.24, "bounce": 0.15, "sound": "squish", "pitch": 0.7},
	"plunger": {"nice": "plunger", "mass": 0.4, "r": 0.22, "bounce": 0.4, "sound": "squish", "pitch": 1.6},
	"rolling_pin": {"nice": "rolling pin", "mass": 0.7, "r": 0.2, "bounce": 0.3, "sound": "knock", "pitch": 1.0},
	"baguette": {"nice": "baguette", "mass": 0.5, "r": 0.25, "bounce": 0.2, "sound": "knock", "pitch": 1.5},
	"anvil": {"nice": "ANVIL", "mass": 14.0, "r": 0.22, "bounce": 0.05, "sound": "slam", "pitch": 0.6},
}

var kind := "chicken"
var radius := 0.2
var grabbed := false
var harmful_t := 0.0          ## while > 0, anything it touches gets bonked
var thrower: Node = null
var spawned := true           ## spawned by the chaos system (so it can be cleaned up)
var _sound_cd := 0.0
var _fly_tw: Tween
var _layers: Array[int] = [8, 1 | 2 | 8]


static func make(kind_name: String) -> Throwable:
	var t := Throwable.new()
	t.kind = kind_name
	return t


func nice_name() -> String:
	return KINDS[kind].nice


func throw_speed() -> float:
	return 13.5 / (1.0 + float(KINDS[kind].mass) * 0.12)


func _ready() -> void:
	var info: Dictionary = KINDS[kind]
	radius = info.r
	mass = info.mass
	collision_layer = _layers[0]
	collision_mask = _layers[1]
	var pm := PhysicsMaterial.new()
	pm.bounce = info.bounce
	pm.friction = 0.7
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 3
	continuous_cd = true
	linear_damp = 0.15
	angular_damp = 0.6
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius * 0.8
	cs.shape = sh
	add_child(cs)
	add_to_group("throwable")
	_build()
	body_entered.connect(_on_body_entered)


func _on_body_entered(_b: Node) -> void:
	var speed := linear_velocity.length()
	if speed > 2.2 and _sound_cd <= 0.0 and not grabbed:
		_sound_cd = 0.18
		Sfx.play(KINDS[kind].sound, float(KINDS[kind].pitch) * randf_range(0.9, 1.1), clampf(speed - 14.0, -14.0, -3.0))


func grab(player: PlayerEgg) -> void:
	grabbed = true
	freeze = true
	collision_layer = 0
	collision_mask = 0
	var came_from := global_transform
	reparent(player.hands.hold_socket, false)
	global_transform = came_from
	var tw := create_tween()
	_fly_tw = tw
	tw.set_parallel(true)
	tw.tween_property(self, "position", Vector3(0, 0.02, 0.08), 0.34).set_delay(0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation", Vector3.ZERO, 0.34).set_delay(0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE * 0.8, 0.34).set_delay(0.16)


func release(player: PlayerEgg, impulse: Vector3, thrown := false) -> void:
	if _fly_tw:
		_fly_tw.kill()
	var root := player.get_parent()
	var xf := global_transform
	if thrown:
		xf.origin = player.camera.global_position + player.forward() * 0.5 + Vector3(0, -0.15, 0)
	reparent(root, false)
	global_transform = Transform3D(Basis.IDENTITY, xf.origin)
	scale = Vector3.ONE
	grabbed = false
	freeze = false
	collision_layer = _layers[0]
	collision_mask = _layers[1]
	linear_velocity = impulse
	angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)) if thrown else Vector3.ZERO
	if thrown:
		harmful_t = 2.5
		thrower = player


func _physics_process(delta: float) -> void:
	_sound_cd = maxf(0.0, _sound_cd - delta)
	if global_position.y < -15.0:
		queue_free()
		return
	if grabbed:
		return
	harmful_t = maxf(0.0, harmful_t - delta)
	var speed := linear_velocity.length()
	if speed < 3.5 or (harmful_t <= 0.0 and speed < 7.0):
		return
	for n in get_tree().get_nodes_in_group("eggs"):
		var e := n as EggBody
		if e == null or not e.is_visible_in_tree():
			continue
		var feet := e.global_position
		var d := Vector2(feet.x - global_position.x, feet.z - global_position.z).length()
		if d > 0.5 + radius * 0.6 or global_position.y < feet.y - 0.15 or global_position.y > feet.y + 1.8:
			continue
		# Don't brain yourself with your own throw.
		if thrower is PlayerEgg and e == (thrower as PlayerEgg).body and harmful_t > 2.0:
			continue
		var dir := linear_velocity
		_hit(e, dir, speed)
		return


func _hit(e: EggBody, dir: Vector3, speed: float) -> void:
	var strength := clampf(speed / 9.0 * (0.7 + mass * 0.05), 0.6, 2.2)
	var player := get_tree().get_first_node_in_group("player") as PlayerEgg
	if player and e == player.body:
		player.tumble(dir, strength)
		Chaos.popup(global_position + Vector3(0, 0.5, 0), "OW!", Color("#ff7aa8"))
	else:
		Chaos.bonk(e, dir, strength)
		if e.has_meta("tony"):
			Game.say_toast("TONY: \"WHO THREW THAT?! ...Nice arm.\"", Color("#ff9f1c"))
	harmful_t = 0.0
	linear_velocity = Vector3(-dir.x, absf(dir.y) + 2.0, -dir.z) * 0.25
	if kind == "tomato" or kind == "watermelon":
		Chaos.popup(global_position, "SPLAT", Color("#ff5d73"), 110)
		Sfx.play("splat", 0.9, -2.0)
		queue_free()


# --- looks ---------------------------------------------------------------------------------------------

func _build() -> void:
	var v := Node3D.new()
	v.name = "Visual"
	add_child(v)
	match kind:
		"chicken":
			var yellow := Color("#ffd23f")
			Toon.ball(v, 0.15, Vector3(0, 0, 0), yellow, 0.01, 14).scale = Vector3(1, 0.9, 1.35)
			Toon.ball(v, 0.085, Vector3(0, 0.15, 0.17), yellow, 0.01, 12)
			Toon.cyl(v, 0.0, 0.04, 0.09, Vector3(0, 0.145, 0.27), Color("#ff7b00"), 0.008, 8).rotation.x = PI / 2
			Toon.ball(v, 0.04, Vector3(0, 0.25, 0.17), Color("#e63946"), 0.008, 8)
			Toon.ball(v, 0.018, Vector3(0.05, 0.18, 0.24), Color.BLACK, 0.0, 6)
			Toon.ball(v, 0.018, Vector3(-0.05, 0.18, 0.24), Color.BLACK, 0.0, 6)
			for s in [-1, 1]:
				Toon.cyl(v, 0.012, 0.012, 0.14, Vector3(s * 0.06, -0.17, 0.0), Color("#ff7b00"), 0.0, 6)
				Toon.ball(v, 0.05, Vector3(s * 0.15, 0.0, 0.0), yellow.darkened(0.08), 0.008, 8).scale = Vector3(0.4, 0.8, 1.1)
		"pan":
			Toon.cyl(v, 0.24, 0.2, 0.05, Vector3.ZERO, Color("#34343f"), 0.012, 20)
			Toon.block(v, Vector3(0.34, 0.035, 0.06), Vector3(0.38, 0.0, 0), Color("#8a5a2b"), 0.01, 0.01)
		"tomato":
			Toon.ball(v, 0.11, Vector3.ZERO, Color("#e63946"), 0.01, 14)
			Toon.cyl(v, 0.0, 0.05, 0.03, Vector3(0, 0.105, 0), Color("#2d8a46"), 0.0, 6)
		"cone":
			Toon.cyl(v, 0.02, 0.15, 0.4, Vector3(0, 0, 0), Color("#ff7b00"), 0.012, 14)
			Toon.cyl(v, 0.06, 0.09, 0.07, Vector3(0, 0.03, 0), Color.WHITE, 0.0, 14)
			Toon.block(v, Vector3(0.34, 0.03, 0.34), Vector3(0, -0.2, 0), Color("#d96a00"), 0.02, 0.01)
		"bucket":
			Toon.cyl(v, 0.17, 0.13, 0.3, Vector3.ZERO, Color("#4a90d9"), 0.012, 16)
			Toon.cyl(v, 0.15, 0.15, 0.01, Vector3(0, 0.15, 0), Color("#2c5f94"), 0.0, 16)
		"watermelon":
			Toon.ball(v, 0.23, Vector3.ZERO, Color("#2e9e4f"), 0.012, 16).scale = Vector3(1.0, 0.85, 0.9)
			for k in 4:
				var st := Toon.ball(v, 0.2, Vector3.ZERO, Color("#17632f"), 0.0, 12)
				st.scale = Vector3(1.01, 0.86, 0.14)
				st.rotation.y = k * PI / 4.0
		"plunger":
			Toon.cyl(v, 0.018, 0.018, 0.5, Vector3(0, 0.1, 0), Color("#b98a5a"), 0.008, 6)
			Toon.cyl(v, 0.03, 0.1, 0.09, Vector3(0, -0.15, 0), Color("#d62828"), 0.01, 12)
		"rolling_pin":
			var r := Toon.cyl(v, 0.045, 0.045, 0.34, Vector3.ZERO, Color("#d9b27c"), 0.01, 12)
			r.rotation.z = PI / 2
			for s in [-1, 1]:
				var h := Toon.cyl(v, 0.02, 0.02, 0.09, Vector3(s * 0.21, 0, 0), Color("#a67c52"), 0.008, 8)
				h.rotation.z = PI / 2
		"baguette":
			var b := Toon.cyl(v, 0.055, 0.055, 0.7, Vector3.ZERO, Color("#d8a24f"), 0.012, 12)
			b.rotation.z = PI / 2 + 0.25
			for k in 3:
				var cut := Toon.block(v, Vector3(0.1, 0.012, 0.02), Vector3(-0.2 + k * 0.2, 0.05, 0), Color("#f0cf8f"), 0.004, 0.0)
				cut.rotation.z = 0.5
		"anvil":
			Toon.block(v, Vector3(0.36, 0.14, 0.2), Vector3(0, 0.04, 0), Color("#3a3d47"), 0.03, 0.012)
			Toon.block(v, Vector3(0.2, 0.14, 0.14), Vector3(0, -0.07, 0), Color("#2c2f38"), 0.03, 0.012)
			Toon.cyl(v, 0.0, 0.07, 0.16, Vector3(0.26, 0.05, 0), Color("#3a3d47"), 0.01, 8).rotation.z = -PI / 2
			Toon.block(v, Vector3(0.4, 0.04, 0.26), Vector3(0, -0.17, 0), Color("#2c2f38"), 0.02, 0.01)
