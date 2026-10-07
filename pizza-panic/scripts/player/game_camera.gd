class_name GameCamera
extends Camera3D
## One camera, several moods:
##   on foot  - angled 3/4 view that follows you (rotate with [ and ])
##   driving  - chase cam behind the car, widens with speed
##   talking  - dramatic two-shot of you and whoever you're talking to
##   focus    - close-up on a kitchen station (focus_on)
##   orbit    - slow spin for the title screen

var target: Node3D            ## what we follow (player or car)
var talk_partner: Node3D      ## set during conversations
var orbit_center := Vector3.ZERO
var orbiting := false
var foot_yaw := 0.0           ## camera angle around you while walking

var _focus_point := Vector3.ZERO
var _focus_dist := 0.0
var _shake := 0.0
var _look := Vector3.ZERO
var _orbit_t := 0.0


func _ready() -> void:
	fov = 60.0
	far = 900.0


func focus_on(point: Vector3, distance: float) -> void:
	_focus_point = point
	_focus_dist = distance


func shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.2)


func snap() -> void:
	var want := _wanted()
	global_position = want[0]
	_look = want[1]
	if global_position.distance_to(_look) > 0.01:
		look_at(_look)


## Returns [position, look_at, fov].
func _wanted() -> Array:
	if orbiting:
		var p := orbit_center + Vector3(sin(_orbit_t) * 48.0, 24.0, cos(_orbit_t) * 48.0)
		return [p, orbit_center + Vector3(0, 3, 0), 55.0]
	if target == null:
		return [global_position, _look, fov]
	if _focus_dist > 0.0:
		var p := _focus_point + Vector3(0, _focus_dist * 0.9, _focus_dist * 0.75)
		return [p, _focus_point, 50.0]
	if talk_partner and is_instance_valid(talk_partner):
		var a := target.global_position + Vector3(0, 1.1, 0)
		var b := talk_partner.global_position + Vector3(0, 1.1, 0)
		var across := b - a
		across.y = 0.0
		var side := across.cross(Vector3.UP).normalized()
		var p := a - across.normalized() * 2.2 + side * 2.6 + Vector3(0, 0.9, 0)
		return [p, a.lerp(b, 0.6), 48.0]
	if target is PizzaCar:
		var car := target as PizzaCar
		var back := car.global_basis.z
		back.y = 0.0
		back = back.normalized()
		var speed := absf(car.forward_speed())
		var p := car.global_position + back * (8.0 + speed * 0.12) + Vector3(0, 3.8, 0)
		var look := car.global_position - back * 4.0 + Vector3(0, 1.2, 0)
		return [p, look, 62.0 + speed * 0.45]
	# On foot
	var offset := Vector3(0, 7.0, 8.5).rotated(Vector3.UP, foot_yaw)
	return [target.global_position + offset, target.global_position + Vector3(0, 1.0, 0), 52.0]


func _process(delta: float) -> void:
	if orbiting:
		_orbit_t += delta * 0.07
	if Input.is_action_pressed("cam_left"):
		foot_yaw += delta * 2.0
	if Input.is_action_pressed("cam_right"):
		foot_yaw -= delta * 2.0
	# On foot the camera slowly swings around behind where you're walking.
	if target is PlayerEgg and _focus_dist <= 0.0 and talk_partner == null:
		var pl := target as PlayerEgg
		var hv := Vector2(pl.velocity.x, pl.velocity.z)
		if hv.length() > 1.0:
			var heading := atan2(-hv.x, -hv.y)
			var diff := wrapf(heading - foot_yaw, -PI, PI)
			if absf(diff) < 2.2:
				foot_yaw += diff * minf(1.0, delta * 1.4)
	var want := _wanted()
	var k := 1.0 - exp(-(3.5 if talk_partner or _focus_dist > 0.0 else 6.0) * delta)
	if orbiting:
		k = 1.0
	global_position = global_position.lerp(want[0], k)
	_look = _look.lerp(want[1], k)
	fov = lerpf(fov, want[2], k)
	if global_position.distance_to(_look) > 0.01:
		look_at(_look)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		h_offset = randf_range(-1, 1) * _shake * 0.35
		v_offset = randf_range(-1, 1) * _shake * 0.35
	else:
		h_offset = 0.0
		v_offset = 0.0
