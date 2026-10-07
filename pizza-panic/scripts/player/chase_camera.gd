class_name ChaseCamera
extends Camera3D
## Follows the car from behind. During conversations it swings around to a
## dramatic anime two-shot of you and the NPC.

var target: Node3D
var focus_npc: Node3D
## Off while something else (the title screen orbit) is driving the camera.
var follow := true
var _shake := 0.0
var _look := Vector3.ZERO


func _ready() -> void:
	fov = 70.0
	far = 600.0
	if target:
		snap()


func snap() -> void:
	global_position = _chase_position()
	_look = target.global_position
	look_at(_look)


func shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.2)


func _chase_position() -> Vector3:
	var back := target.global_basis.z
	back.y = 0.0
	back = back.normalized()
	var speed := 0.0
	if target is PizzaCar:
		speed = absf((target as PizzaCar).forward_speed())
	return target.global_position + back * (8.5 + speed * 0.12) + Vector3(0, 4.2, 0)


func _process(delta: float) -> void:
	if target == null or not follow:
		return
	var want_pos: Vector3
	var want_look: Vector3
	var want_fov := 70.0
	if focus_npc and is_instance_valid(focus_npc):
		# Over-the-shoulder two-shot: off to the side, NPC framed big.
		var npc_pos := focus_npc.global_position + Vector3(0, 1.4, 0)
		var car_pos := target.global_position + Vector3(0, 1.4, 0)
		var mid := (npc_pos + car_pos) * 0.5
		var across := (npc_pos - car_pos)
		across.y = 0.0
		var side := across.cross(Vector3.UP).normalized()
		want_pos = car_pos - across.normalized() * 2.5 + side * 3.0 + Vector3(0, 1.0, 0)
		want_look = mid.lerp(npc_pos, 0.65)
		want_fov = 50.0
	else:
		var speed := 0.0
		if target is PizzaCar:
			speed = absf((target as PizzaCar).forward_speed())
		want_pos = _chase_position()
		want_look = target.global_position + -target.global_basis.z * 4.0 + Vector3(0, 1.2, 0)
		want_fov = 70.0 + speed * 0.5
	var k := 1.0 - exp(-(4.0 if focus_npc else 6.0) * delta)
	global_position = global_position.lerp(want_pos, k)
	_look = _look.lerp(want_look, k)
	fov = lerpf(fov, want_fov, k)
	if global_position.distance_to(_look) > 0.01:
		look_at(_look)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		h_offset = randf_range(-1, 1) * _shake * 0.4
		v_offset = randf_range(-1, 1) * _shake * 0.4
	else:
		h_offset = 0.0
		v_offset = 0.0
