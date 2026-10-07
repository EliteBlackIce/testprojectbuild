class_name Traffic
extends Node3D
## Background cars that loop around blocks in the right-hand lane. They stop
## for you (mostly) and honk about it. You can bump into them.

const LANE := 2.6
const SPEED := 8.5

var town: Town
var player_car: Node3D
var player: Node3D
var _cars: Array[Dictionary] = []


func spawn(count: int, rng: RandomNumberGenerator) -> void:
	var colors := ["#2e86de", "#27ae60", "#f39c12", "#8e44ad", "#dfe6e9", "#16a085", "#e84393", "#fdcb6e"]
	for n in count:
		var i := rng.randi() % Town.COLS
		var j := rng.randi() % Town.ROWS
		# Corners of the loop around block (i, j), clockwise seen from above.
		var corners: Array[Vector3] = [
			Vector3(town.road_x(i), 0, town.road_z(j)),
			Vector3(town.road_x(i + 1), 0, town.road_z(j)),
			Vector3(town.road_x(i + 1), 0, town.road_z(j + 1)),
			Vector3(town.road_x(i), 0, town.road_z(j + 1)),
		]
		if rng.randf() < 0.5:
			corners.reverse()
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.9, 1.5, 3.8)
		cs.shape = box
		cs.position = Vector3(0, 0.8, 0)
		body.add_child(cs)
		add_child(body)
		_build_car(body, Color(colors[rng.randi() % colors.size()]), rng)
		_cars.append({"body": body, "corners": corners, "seg": rng.randi() % 4, "t": rng.randf(), "speed": SPEED * rng.randf_range(0.8, 1.15), "honk": 0.0})


func _build_car(root: Node3D, col: Color, rng: RandomNumberGenerator) -> void:
	Toon.block(root, Vector3(1.9, 0.8, 3.7), Vector3(0, 0.3, 0), col, 0.2, 0.02)
	Toon.block(root, Vector3(1.6, 0.65, 1.9), Vector3(0, 1.05, 0.25), col.lightened(0.3), 0.2, 0.02)
	Toon.box(root, Vector3(1.5, 0.4, 1.92), Vector3(0, 1.38, 0.25), Color("#9cc9d9"), 0.0)
	for x: int in [-1, 1]:
		for z: int in [-1, 1]:
			Toon.cyl(root, 0.36, 0.36, 0.3, Vector3(0.9 * x, 0.36, 1.15 * z), Color("#2d3436"), 0.01, 8).rotation.z = PI / 2
	var driver := EggBody.new()
	root.add_child(driver)
	driver.build(Characters.random_pedestrian_look(rng))
	driver.scale = Vector3.ONE * 0.55
	driver.position = Vector3(-0.35, 0.6, 0.3)
	driver.rotation.y = PI


func _physics_process(delta: float) -> void:
	for c in _cars:
		var corners: Array[Vector3] = c.corners
		var a: Vector3 = corners[c.seg]
		var b: Vector3 = corners[(c.seg + 1) % 4]
		var dir := (b - a).normalized()
		var right := Vector3(-dir.z, 0, dir.x)
		var body := c.body as AnimatableBody3D
		# Stop if the player (or their car) is right in front.
		var ahead := body.global_position + dir * 5.0
		var blocked := false
		for obstacle in [player_car, player]:
			if obstacle and is_instance_valid(obstacle) and (obstacle as Node3D).is_visible_in_tree():
				if (obstacle as Node3D).global_position.distance_to(ahead) < 3.6:
					blocked = true
		c.honk = maxf(0.0, c.honk - delta)
		if blocked:
			if c.honk <= 0.0 and body.global_position.distance_to(player_car.global_position) < 25.0:
				c.honk = 4.0
				Sfx.play("honk", 0.7, -14.0)
			continue
		var length := a.distance_to(b)
		c.t += c.speed * delta / length
		if c.t >= 1.0:
			c.t = 0.0
			c.seg = (c.seg + 1) % 4
		var pos := a.lerp(b, c.t) + right * LANE
		body.global_position = pos
		var yaw := atan2(-dir.x, -dir.z)
		body.rotation.y = lerp_angle(body.rotation.y, yaw, 1.0 - exp(-8.0 * delta))
