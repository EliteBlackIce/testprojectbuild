class_name PlayerEgg
extends CharacterBody3D
## You: an egg in a delivery cap. Walks, hops, carries one thing overhead,
## and presses E on things.

signal focus_changed(target: Interactable)

const WALK_SPEED := 4.2
const ACCEL := 30.0
const GRAVITY := 22.0
const JUMP := 6.5

var body: EggBody
var controls_enabled := true
## The thing held overhead (a Pizza, usually). null when empty-handed.
var held: Node3D = null
var focus: Interactable = null
## Set by main: which way is "up" on the screen (camera yaw).
var view_yaw := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.4
	shape.shape = cap
	shape.position = Vector3(0, 0.75, 0)
	add_child(shape)
	rebuild_look()
	Game.upgrades_changed.connect(rebuild_look)


func rebuild_look() -> void:
	if body:
		body.queue_free()
	var look: Dictionary = Characters.PLAYER_LOOK.duplicate()
	look.hat = Game.current_hat()
	body = EggBody.new()
	add_child(body)
	body.build(look)
	if held:
		held.reparent(body.hand_socket, false)
		body.carrying = true


func speed() -> float:
	return WALK_SPEED + Game.level("sneakers") * 1.0


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector("steer_left", "steer_right", "accelerate", "brake")
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, view_yaw)
	var target := dir * speed()
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target, ACCEL * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = maxf(velocity.y, -1.0)
		if controls_enabled and Input.is_action_just_pressed("hop"):
			velocity.y = JUMP
			body.hop()
			Sfx.play("boing", randf_range(1.2, 1.4), -6.0)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if hv.length() > 0.3:
		var yaw := atan2(hv.x, hv.z)
		body.rotation.y = lerp_angle(body.rotation.y, yaw, 1.0 - exp(-14.0 * delta))
	body.speed = hv.length() / WALK_SPEED
	if global_position.y < -20.0:
		global_position = Vector3(0, 2, 0)
	_update_focus()


func facing() -> Vector3:
	return Vector3(sin(body.rotation.y), 0, cos(body.rotation.y))


func _update_focus() -> void:
	var best: Interactable = null
	var best_score := INF
	if controls_enabled:
		var here := global_position + Vector3(0, 0.8, 0)
		var fwd := facing()
		for n in get_tree().get_nodes_in_group("interactable"):
			var it := n as Interactable
			if it == null or not it.is_visible_in_tree():
				continue
			var to := it.global_position - here
			to.y *= 0.4
			var d := to.length()
			if d > it.reach:
				continue
			# Prefer things in front of us.
			var score := d - fwd.dot(to.normalized()) * 0.6
			if score < best_score and it.prompt(self) != "":
				best_score = score
				best = it
	if best != focus:
		focus = best
		focus_changed.emit(focus)


func interact() -> void:
	if focus and controls_enabled:
		focus.use(self)


# --- carrying ---------------------------------------------------------------------

func is_holding() -> bool:
	return held != null


func hold(item: Node3D) -> void:
	if item.get_parent():
		item.reparent(body.hand_socket, false)
	else:
		body.hand_socket.add_child(item)
	item.position = Vector3(0, 0.05, 0)
	item.rotation = Vector3.ZERO
	held = item
	body.carrying = true
	if item is Pizza:
		(item as Pizza).location = "carried"


## Hands the held item over (removes it from our hand, caller re-parents it).
func take_held() -> Node3D:
	var item := held
	held = null
	body.carrying = false
	return item
