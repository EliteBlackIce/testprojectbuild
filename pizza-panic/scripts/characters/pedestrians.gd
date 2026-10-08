class_name Pedestrians
extends Node3D
## Background eggs strolling around the sidewalks. Hit one with the car and
## they go flying (they're fine, they're eggs. Hard-boiled.)

signal yeeted

var town: Town
var car: PizzaCar
var _walkers: Array[Dictionary] = []


func spawn(count: int, rng: RandomNumberGenerator) -> void:
	for n in count:
		var i := rng.randi() % Town.COLS
		var j := rng.randi() % Town.ROWS
		var o := town.block_origin(i, j)
		var inset := 0.9
		var corners: Array[Vector3] = [
			o + Vector3(inset, 0.06, inset), o + Vector3(Town.BLOCK - inset, 0.06, inset),
			o + Vector3(Town.BLOCK - inset, 0.06, Town.BLOCK - inset), o + Vector3(inset, 0.06, Town.BLOCK - inset),
		]
		if rng.randf() < 0.5:
			corners.reverse()
		var egg := EggBody.new()
		add_child(egg)
		egg.build(Characters.random_pedestrian_look(rng))
		egg.set_meta("on_bonk", _bonked.bind(egg))
		var w := {"egg": egg, "corners": corners, "seg": rng.randi() % 4, "t": rng.randf(),
			"speed": rng.randf_range(1.0, 1.6), "pause": 0.0, "off": Vector3.ZERO, "path_pos": corners[0]}
		egg.relocator = _relocate.bind(w)
		_walkers.append(w)


func _process(delta: float) -> void:
	for w in _walkers:
		var egg := w.egg as EggBody
		if w.pause > 0.0:
			w.pause -= delta
			egg.speed = 0.0
			continue
		var corners: Array[Vector3] = w.corners
		var a: Vector3 = corners[w.seg]
		var b: Vector3 = corners[(w.seg + 1) % 4]
		w.t += w.speed * delta / a.distance_to(b)
		if w.t >= 1.0:
			w.t = 0.0
			w.seg = (w.seg + 1) % 4
		w.path_pos = a.lerp(b, w.t)
		# After a tumble they stand up wherever they landed and stroll back onto the sidewalk.
		w.off = (w.off as Vector3).move_toward(Vector3.ZERO, 1.6 * delta)
		egg.position = (w.path_pos as Vector3) + (w.off as Vector3)
		var dir := (b - a).normalized()
		egg.rotation.y = lerp_angle(egg.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-8.0 * delta))
		egg.speed = w.speed / 1.4
		# Car hits?
		if car and car.velocity.length() > 6.0:
			var d := Vector2(egg.global_position.x - car.global_position.x, egg.global_position.z - car.global_position.z).length()
			if d < 1.6:
				w.pause = egg.tumble(car.velocity.normalized() + Vector3(0, 0.3, 0), clampf(car.velocity.length() / 6.0, 1.0, 3.0))
				Sfx.play("scream", randf_range(0.8, 1.3))
				yeeted.emit()


## Hit by a thrown prop (or anything else): a ragdoll, then back to strolling.
func _bonked(dir: Vector3, strength: float, egg: EggBody) -> void:
	for w in _walkers:
		if w.egg == egg and w.pause <= 0.0:
			w.pause = egg.tumble(dir, strength * 1.2)
			Sfx.play("scream", randf_range(1.0, 1.5), -4.0)


func _relocate(land: Vector3, _yaw: float, w: Dictionary) -> void:
	var egg := w.egg as EggBody
	var p := to_local(land)
	p.y = 0.06
	w.off = p - (w.path_pos as Vector3)
	egg.position = p
