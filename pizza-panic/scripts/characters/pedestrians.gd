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
		_walkers.append({"egg": egg, "corners": corners, "seg": rng.randi() % 4, "t": rng.randf(),
			"speed": rng.randf_range(1.0, 1.6), "fly": Vector3.ZERO, "flying": false, "spin": 0.0, "pause": 0.0})


func _process(delta: float) -> void:
	for w in _walkers:
		var egg := w.egg as EggBody
		if w.flying:
			w.fly.y -= 22.0 * delta
			egg.position += w.fly * delta
			egg.rotation.x += w.spin * delta
			if egg.position.y <= 0.06 and w.fly.y < 0.0:
				w.flying = false
				egg.flailing = false
				egg.rotation = Vector3(0, egg.rotation.y, 0)
				egg.position.y = 0.06
				egg.express("angry", 3.0)
				w.pause = 2.0
				Sfx.play("splat", randf_range(0.8, 1.2), -4.0)
			continue
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
		egg.position = a.lerp(b, w.t)
		var dir := (b - a).normalized()
		egg.rotation.y = lerp_angle(egg.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-8.0 * delta))
		egg.speed = w.speed / 1.4
		# Car hits?
		if car and car.velocity.length() > 6.0:
			var d := Vector2(egg.global_position.x - car.global_position.x, egg.global_position.z - car.global_position.z).length()
			if d < 1.6:
				w.flying = true
				w.fly = car.velocity * 0.8 + Vector3(0, 10.0, 0)
				w.spin = randf_range(10.0, 18.0)
				egg.flailing = true
				egg.express("scared", 3.0)
				Sfx.play("scream", randf_range(0.8, 1.3))
				yeeted.emit()
