class_name Gags
extends Node
## Character-specific nonsense that happens around deliveries:
##   Sir Barksalot  - chases your car down the street, barking
##   Chad           - demands an arm-wrestle before he pays (mash E!)
##   Dave           - turns the pizza box into a frog. It hops away.
##   Big Baby Bob   - crawls off mid-conversation
##   Boo-ford       - floats right through the closed door (see House.come_out)

var town: Town
var car: PizzaCar
var player: PlayerEgg

var _dog: House
var _dog_chase := 0.0
var _dog_home := Vector3.ZERO
var _dog_cooldown := 0.0
var _bark := 0.0
var _frogs: Array[Node3D] = []
var _baby: House
var _baby_t := 0.0

## Arm wrestling
var _wrestle_ui: CanvasLayer
var _wrestle_bar: ProgressBar
var _wrestle_label: Label
var _wrestle := -1.0
var _wrestle_time := 0.0
signal wrestle_done(won: bool)


func setup() -> void:
	for h in town.houses:
		match str(h.character.get("id", "")):
			"barksalot":
				_dog = h
			"bob":
				_baby = h
	_build_wrestle_ui()


func _process(delta: float) -> void:
	_dog_cooldown = maxf(0.0, _dog_cooldown - delta)
	_update_dog(delta)
	_update_frogs(delta)
	_update_baby(delta)
	_update_wrestle(delta)


# --- Sir Barksalot chases cars ----------------------------------------------------------------------

func _update_dog(delta: float) -> void:
	if _dog == null or car == null or Game.in_dialogue:
		return
	var dog := _dog.resident
	if _dog_chase <= 0.0:
		if _dog_cooldown > 0.0 or not car.driving or _dog.outside:
			return
		if car.global_position.distance_to(_dog.global_position) < 22.0 and absf(car.forward_speed()) > 6.0:
			_dog_chase = 9.0
			_dog_home = dog.position
			dog.visible = true
			dog.express("excited", 9.0)
			Game.say_toast("Sir Barksalot is chasing your car!!", UiTheme.PINK)
		return
	_dog_chase -= delta
	var target := car.global_position
	var to := target - dog.global_position
	to.y = 0.0
	if _dog_chase > 1.5 and to.length() > 2.5:
		dog.global_position += to.normalized() * minf(13.0 * delta, to.length())
		dog.global_rotation.y = atan2(to.x, to.z)
		dog.velocity_hint = to.normalized() * 13.0
	else:
		dog.velocity_hint = Vector3.ZERO
	_bark -= delta
	if _bark <= 0.0:
		_bark = randf_range(0.5, 1.0)
		dog.play("hop")
		var a := AudioStreamPlayer3D.new()
		a.stream = Sfx.babble("WOOF WOOF", 520.0, 1.6)
		a.unit_size = 8.0
		dog.add_child(a)
		a.play()
		a.finished.connect(a.queue_free)
	if _dog_chase <= 0.0:
		dog.velocity_hint = Vector3.INF
		dog.position = _dog_home
		dog.visible = _dog.outside
		_dog_cooldown = 60.0


# --- Dave: box -> frog ---------------------------------------------------------------------------------

func frogify(where: Node3D) -> void:
	var frog := Node3D.new()
	town.add_child(frog)
	frog.global_position = where.global_position
	var body := Toon.mesh(frog, Shapes.blob(0.22, 77, 0.12), Vector3(0, 0.18, 0), Color("#5cb85c"), 0.012)
	body.scale = Vector3(1.2, 0.75, 1.0)
	for s: int in [-1, 1]:
		Toon.ball(frog, 0.08, Vector3(0.1 * s, 0.36, 0.12), Color("#fbf6ee"), 0.008, 8)
		Toon.ball(frog, 0.04, Vector3(0.1 * s, 0.37, 0.18), Color("#1d1517"), 0.0, 6)
		var leg := Toon.ball(frog, 0.09, Vector3(0.2 * s, 0.07, -0.08), Color("#4cae4c"), 0.008, 6)
		leg.scale = Vector3(0.7, 0.5, 1.4)
	var label := Toon.label(frog, "ribbit", Vector3(0, 0.7, 0), 34, Color("#c7f9cc"))
	label.pixel_size = 0.006
	frog.set_meta("t", 0.0)
	frog.set_meta("dir", Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized())
	_frogs.append(frog)
	Sfx.play("boing", 1.8)


func _update_frogs(delta: float) -> void:
	for f in _frogs.duplicate():
		var t: float = f.get_meta("t") + delta
		f.set_meta("t", t)
		var dir: Vector3 = f.get_meta("dir")
		var hop := fmod(t, 0.8) / 0.8
		f.global_position += dir * delta * 1.6
		f.position.y = maxf(f.position.y, 0.0)
		(f.get_child(0) as Node3D).position.y = 0.18 + sin(hop * PI) * 0.4
		f.look_at(f.global_position + dir, Vector3.UP, true)
		if t > 14.0:
			_frogs.erase(f)
			f.queue_free()


# --- Big Baby Bob wanders off while you talk --------------------------------------------------------------

func _update_baby(delta: float) -> void:
	if _baby == null or not _baby.outside or not Game.in_dialogue:
		_baby_t = 0.0
		return
	_baby_t += delta
	if _baby_t < 2.5:
		return
	var r := _baby.resident
	var wander := Vector3(sin(_baby_t * 0.4), 0, cos(_baby_t * 0.3) * 0.3 + 0.6).normalized()
	if r.position.distance_to(_baby.door_spot.position) < 3.5:
		r.position += wander * delta * 0.45
		r.rotation.y = atan2(wander.x, wander.z)
		r.speed = 0.4
	else:
		r.speed = 0.0
	if player:
		player.look_at_point(r.global_position + Vector3(0, 1.0, 0))


# --- Chad: arm wrestle (mash E) -------------------------------------------------------------------------

func _build_wrestle_ui() -> void:
	_wrestle_ui = CanvasLayer.new()
	_wrestle_ui.layer = 9
	add_child(_wrestle_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	_wrestle_ui.add_child(root)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -120
	panel.offset_bottom = 40
	root.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	_wrestle_label = UiTheme.label("ARM WRESTLE CHAD! MASH [E]!!!", 34, UiTheme.RED)
	_wrestle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_wrestle_label)
	_wrestle_bar = ProgressBar.new()
	_wrestle_bar.custom_minimum_size = Vector2(600, 36)
	_wrestle_bar.show_percentage = false
	_wrestle_bar.max_value = 1.0
	v.add_child(_wrestle_bar)
	_wrestle_ui.visible = false


func arm_wrestle() -> bool:
	_wrestle = 0.5
	_wrestle_time = 0.0
	_wrestle_ui.visible = true
	Sfx.play("ding")
	var won: bool = await wrestle_done
	_wrestle_ui.visible = false
	return won


func _update_wrestle(delta: float) -> void:
	if _wrestle < 0.0:
		return
	_wrestle_time += delta
	# Chad pushes back harder over time
	_wrestle -= delta * (0.32 + _wrestle_time * 0.04)
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("poke"):
		_wrestle += 0.075
		Sfx.play("poke", randf_range(1.0, 1.5), -10.0)
		player.hands.play("push")
	_wrestle_bar.value = _wrestle
	_wrestle_label.text = "ARM WRESTLE CHAD! MASH [E]!!!" if _wrestle_time < 1.2 else ["NNNGH", "GRRRR", "DO IT FOR THE PIZZA", "BRO..."][int(_wrestle_time * 3.0) % 4]
	if _wrestle >= 1.0 or _wrestle <= 0.0 or _wrestle_time > 7.0:
		var won := _wrestle >= 0.6
		_wrestle = -1.0
		wrestle_done.emit(won)
