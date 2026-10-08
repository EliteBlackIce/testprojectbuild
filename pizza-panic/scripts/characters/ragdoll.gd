class_name Ragdoll
extends RefCounted
## A tiny verlet ragdoll for the egg people. Fourteen particles joined by distance
## constraints (a stick figure with a big head), simulated in world space. EggBody
## copies the particles onto its real body parts every frame, so the actual meshes
## flop, tumble, bounce and slide: loose arms, a lolling head, boots flying.
##
## No Godot physics bodies, no skeleton: just a few dozen constraints per frame.

enum P { HEAD, NECK, CHEST, PELVIS, SHL, SHR, ELL, ELR, HANDL, HANDR, HIPL, HIPR, FOOTL, FOOTR }
const COUNT := 14
const STEP := 1.0 / 120.0

var pos := PackedVector3Array()
var prev := PackedVector3Array()
var radius := PackedFloat32Array()
var mass := PackedFloat32Array()
var floor_y := PackedFloat32Array()      ## ground height under each particle (refreshed every frame)
var gravity := 17.0
var damping := 0.9965
var space: PhysicsDirectSpaceState3D
var ground_default := 0.0
var time := 0.0
var stiffness_iters := 10

var _bones: Array = []           ## [a, b, length, stiffness, mode]  mode: 0 rigid, 1 min only, 2 max only
var _acc := 0.0
var _exclude: Array[RID] = []


## `start` is the 14 world positions in the order of enum P. `s` is the character's scale.
func setup(start: Array, s: float, velocity: Vector3, sp: PhysicsDirectSpaceState3D, ground: float) -> void:
	space = sp
	ground_default = ground
	pos.resize(COUNT)
	prev.resize(COUNT)
	radius.resize(COUNT)
	mass.resize(COUNT)
	floor_y.resize(COUNT)
	for i in COUNT:
		pos[i] = start[i]
		prev[i] = pos[i] - velocity * STEP
		floor_y[i] = ground
	var r := {P.HEAD: 0.283, P.NECK: 0.13, P.CHEST: 0.27, P.PELVIS: 0.26, P.SHL: 0.11, P.SHR: 0.11, P.ELL: 0.05, P.ELR: 0.05,
		P.HANDL: 0.075, P.HANDR: 0.075, P.HIPL: 0.09, P.HIPR: 0.09, P.FOOTL: 0.1, P.FOOTR: 0.1}
	var m := {P.HEAD: 3.0, P.NECK: 1.0, P.CHEST: 3.0, P.PELVIS: 3.0, P.SHL: 1.0, P.SHR: 1.0, P.ELL: 0.7, P.ELR: 0.7,
		P.HANDL: 0.8, P.HANDR: 0.8, P.HIPL: 1.0, P.HIPR: 1.0, P.FOOTL: 1.2, P.FOOTR: 1.2}
	for i in COUNT:
		radius[i] = float(r[i]) * s
		mass[i] = m[i]
	_build_bones()


func _rigid(a: int, b: int, stiff := 1.0) -> void:
	_bones.append([a, b, pos[a].distance_to(pos[b]), stiff, 0])


func _min_dist(a: int, b: int, factor: float, stiff := 0.8) -> void:
	_bones.append([a, b, pos[a].distance_to(pos[b]) * factor, stiff, 1])


func _max_dist(a: int, b: int, factor: float, stiff := 0.6) -> void:
	_bones.append([a, b, pos[a].distance_to(pos[b]) * factor, stiff, 2])


func _build_bones() -> void:
	_bones.clear()
	# torso: a braced frame so it stays a body, not a pile of points
	_rigid(P.PELVIS, P.CHEST)
	_rigid(P.CHEST, P.NECK)
	_rigid(P.PELVIS, P.NECK)
	_rigid(P.SHL, P.SHR)
	_rigid(P.SHL, P.NECK)
	_rigid(P.SHR, P.NECK)
	_rigid(P.SHL, P.CHEST)
	_rigid(P.SHR, P.CHEST)
	_rigid(P.SHL, P.PELVIS, 0.9)
	_rigid(P.SHR, P.PELVIS, 0.9)
	_rigid(P.HIPL, P.HIPR)
	_rigid(P.HIPL, P.PELVIS)
	_rigid(P.HIPR, P.PELVIS)
	_rigid(P.HIPL, P.CHEST, 0.9)
	_rigid(P.HIPR, P.CHEST, 0.9)
	_rigid(P.SHL, P.HIPR, 0.7)
	_rigid(P.SHR, P.HIPL, 0.7)
	# head on a springy neck: stays on, but is allowed to loll
	_rigid(P.HEAD, P.NECK)
	_rigid(P.HEAD, P.CHEST, 0.35)
	_min_dist(P.HEAD, P.CHEST, 0.9, 0.9)
	_min_dist(P.HEAD, P.SHL, 0.85, 0.7)
	_min_dist(P.HEAD, P.SHR, 0.85, 0.7)
	# arms
	for side in 2:
		var sh: int = P.SHL + side
		var el: int = P.ELL + side
		var hd: int = P.HANDL + side
		_rigid(sh, el)
		_rigid(el, hd)
		_min_dist(sh, hd, 0.42, 0.7)         # the elbow can't fold flat
		_min_dist(hd, P.CHEST, 0.5, 0.5)     # hands don't sink into the belly
		_min_dist(el, P.CHEST, 0.6, 0.5)
	# legs
	for side in 2:
		_rigid(P.HIPL + side, P.FOOTL + side)
		_min_dist(P.FOOTL + side, P.PELVIS, 0.7, 0.6)
	_min_dist(P.FOOTL, P.FOOTR, 0.45, 0.6)
	_min_dist(P.HANDL, P.HANDR, 0.5, 0.4)


func kick(index: int, velocity: Vector3) -> void:
	prev[index] -= velocity * STEP


## Pushes every particle along `v`, scaled up toward the top of the body (a hit up high topples you).
func shove(v: Vector3, top_bias := 0.8) -> void:
	var base := pos[P.PELVIS].y
	var span := maxf(0.5, pos[P.HEAD].y - base)
	for i in COUNT:
		var h := clampf((pos[i].y - base) / span, -0.2, 1.1)
		prev[i] -= v * (1.0 + top_bias * h) * STEP


func step(delta: float) -> void:
	_acc += minf(delta, 0.05)
	var n := 0
	while _acc >= STEP and n < 8:
		_acc -= STEP
		n += 1
		_sample_floor()
		_sim()
		time += STEP


func velocity_of(i: int) -> Vector3:
	return (pos[i] - prev[i]) / STEP


func energy() -> float:
	var e := 0.0
	for i in COUNT:
		e += velocity_of(i).length_squared() * mass[i]
	return e


func _sample_floor() -> void:
	if space == null:
		return
	for i in COUNT:
		var from := pos[i] + Vector3(0, 0.6, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -4.0, 0), 1)
		var hit := space.intersect_ray(q)
		floor_y[i] = hit.position.y if not hit.is_empty() else ground_default


func _sim() -> void:
	var g := Vector3(0, -gravity, 0) * STEP * STEP
	for i in COUNT:
		var v := (pos[i] - prev[i]) * damping
		prev[i] = pos[i]
		pos[i] += v + g
	for it in stiffness_iters:
		for b in _bones:
			var a: int = b[0]
			var c: int = b[1]
			var d := pos[c] - pos[a]
			var dist := d.length()
			if dist < 0.0001:
				continue
			var mode: int = b[4]
			if mode == 1 and dist >= float(b[2]):
				continue
			if mode == 2 and dist <= float(b[2]):
				continue
			var diff := (dist - float(b[2])) / dist * float(b[3])
			var wa := 1.0 / mass[a]
			var wc := 1.0 / mass[c]
			var corr := d * diff / (wa + wc)
			pos[a] += corr * wa
			pos[c] -= corr * wc
		_collide()


func _collide() -> void:
	for i in COUNT:
		var lo := floor_y[i] + radius[i]
		if pos[i].y < lo:
			var v := pos[i] - prev[i]
			pos[i].y = lo
			# bounce a little, scrub the sliding (heavier parts grip more)
			var grip := 0.78 if mass[i] > 2.0 else 0.9
			var bounce := 0.32 if mass[i] > 2.0 else 0.18
			prev[i] = pos[i] - Vector3(v.x * grip, -v.y * bounce, v.z * grip)


## Keeps the body from tunnelling through walls: a quick ray from last frame's spot.
func collide_walls(last: Array) -> void:
	if space == null:
		return
	for i in [P.HEAD, P.CHEST, P.PELVIS, P.FOOTL, P.FOOTR]:
		var from: Vector3 = last[i]
		var to := pos[i]
		if from.distance_to(to) < 0.05:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit.normal
		if absf(n.y) > 0.6:
			continue
		var v := pos[i] - prev[i]
		pos[i] = hit.position + n * (radius[i] + 0.02)
		var vn := v.dot(n)
		prev[i] = pos[i] - (v - n * vn * 1.3) * 0.7
