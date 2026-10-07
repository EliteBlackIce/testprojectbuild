class_name House
extends Node3D
## One house (or Tony's shop) with its resident. Built facing +Z.

var number := 0
var is_shop := false
var resident: Npc
## Where the car should stop to talk (global position, set by Town).
var stop_point := Vector3.ZERO
var _beacon: MeshInstance3D
var _beacon_t := 0.0


func build(num: int, shop: bool, character: Dictionary, rng: RandomNumberGenerator) -> void:
	number = num
	is_shop = shop
	if shop:
		_build_shop()
	else:
		_build_house(rng)
	resident = Npc.new()
	resident.setup(character)
	resident.position = Vector3(0, 0, 5.3 if shop else 4.6)
	add_child(resident)
	# Glowing ring on the ground where you park to deliver.
	_beacon = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.2
	torus.outer_radius = 2.6
	torus.rings = 32
	_beacon.mesh = torus
	_beacon.material_override = Toon.mat(Color("#ffd166"), 0.0, false, 1.5)
	_beacon.position = Vector3(0, 0.08, 10.0)
	_beacon.visible = false
	add_child(_beacon)


func set_target(on: bool) -> void:
	_beacon.visible = on
	if resident:
		resident.set_waving(on)
		resident.show_name(on)


func _process(delta: float) -> void:
	if _beacon.visible:
		_beacon_t += delta
		var s := 1.0 + sin(_beacon_t * 5.0) * 0.08
		_beacon.scale = Vector3(s, 1.0, s)


func _build_house(rng: RandomNumberGenerator) -> void:
	var palette := ["#8ecae6", "#b5e48c", "#f4a261", "#cdb4db", "#ffafcc", "#e9c46a", "#90e0ef", "#ffd6a5", "#caffbf"]
	var roofs := ["#e63946", "#3a86ff", "#8338ec", "#fb5607", "#2a9d8f", "#6d597a"]
	var wall := Color(palette[rng.randi() % palette.size()])
	var roof := Color(roofs[rng.randi() % roofs.size()])
	var w := rng.randf_range(7.0, 8.5)
	var d := rng.randf_range(6.5, 7.5)
	var h := rng.randf_range(4.0, 5.5)
	Toon.box(self, Vector3(w, h, d), Vector3(0, h * 0.5, 0), wall, 0.06)
	Toon.solid_box(self, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	var r := Toon.prism(self, Vector3(d + 0.8, 2.8, w + 0.8), Vector3(0, h + 1.4, 0), roof)
	r.rotation.y = PI / 2
	# Chimney
	if rng.randf() < 0.7:
		Toon.box(self, Vector3(0.8, 2.2, 0.8), Vector3(w * 0.25, h + 1.6, -d * 0.2), Color("#9c6644"), 0.04)
	# Door + knob + porch step
	var front := d * 0.5
	Toon.box(self, Vector3(1.4, 2.4, 0.15), Vector3(0, 1.2, front + 0.05), Color("#7f5539"), 0.03)
	Toon.sphere(self, 0.08, Vector3(0.45, 1.2, front + 0.18), Color("#ffd166"), 0.01)
	Toon.box(self, Vector3(2.6, 0.25, 1.4), Vector3(0, 0.12, front + 0.7), Color("#d6ccc2"), 0.03)
	# Windows with little shutters
	for side in [-1, 1]:
		var wx := w * 0.3 * side
		Toon.box(self, Vector3(1.4, 1.3, 0.12), Vector3(wx, h * 0.55, front + 0.04), Color("#bde0fe"), 0.03)
		Toon.box(self, Vector3(0.12, 1.3, 0.16), Vector3(wx, h * 0.55, front + 0.08), Color.WHITE, 0.0)
		Toon.box(self, Vector3(1.4, 0.12, 0.16), Vector3(wx, h * 0.55, front + 0.08), Color.WHITE, 0.0)
	# Mailbox with the house number
	Toon.box(self, Vector3(0.12, 1.1, 0.12), Vector3(2.8, 0.55, 8.2), Color("#6c584c"), 0.02)
	Toon.box(self, Vector3(0.5, 0.4, 0.7), Vector3(2.8, 1.25, 8.2), Color("#3a86ff"), 0.025)
	Toon.label(self, str(number), Vector3(0, h + 0.4, front + 0.2), 220, Color.WHITE, false)
	Toon.label(self, str(number), Vector3(2.8, 1.9, 8.2), 90, Color("#ffd166"))
	# Garden path
	Toon.box(self, Vector3(1.6, 0.04, 4.5), Vector3(0, 0.02, front + 3.4), Color("#e3d5ca"), 0.0)
	# Bushes
	for side in [-1, 1]:
		if rng.randf() < 0.8:
			Toon.sphere(self, rng.randf_range(0.6, 0.9), Vector3(w * 0.38 * side, 0.4, front + 0.8), Color("#52b788"), 0.03, 0.8)


func _build_shop() -> void:
	var w := 16.0
	var d := 10.0
	var h := 6.0
	Toon.box(self, Vector3(w, h, d), Vector3(0, h * 0.5, 0), Color("#fff1e6"), 0.07)
	Toon.solid_box(self, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	# Red stripe awning
	for i in 8:
		var c := Color("#d62828") if i % 2 == 0 else Color.WHITE
		var a := Toon.box(self, Vector3(w / 8.0, 0.3, 2.2), Vector3(-w * 0.5 + w / 16.0 + i * w / 8.0, h * 0.62, d * 0.5 + 1.0), c, 0.0)
		a.rotation.x = 0.35
	Toon.box(self, Vector3(w + 0.4, 0.6, d + 0.4), Vector3(0, h + 0.3, 0), Color("#d62828"), 0.05)
	Toon.box(self, Vector3(3.0, 3.0, 0.2), Vector3(0, 1.5, d * 0.5 + 0.05), Color("#7f5539"), 0.03)
	for side in [-1, 1]:
		Toon.box(self, Vector3(4.0, 2.4, 0.15), Vector3(4.8 * side, 1.9, d * 0.5 + 0.04), Color("#bde0fe"), 0.03)
	Toon.label(self, "TONY'S PIZZA", Vector3(0, h + 3.8, 0.5), 320, Color("#ffd166"))
	Toon.label(self, "home of the 12 minute pizza*\n*not legally binding", Vector3(0, h * 0.8, d * 0.5 + 0.2), 70, Color("#d62828"), false)
	# Giant spinning rooftop pizza
	var spinner := Node3D.new()
	spinner.name = "PizzaSign"
	spinner.position = Vector3(0, h + 2.2, 0)
	add_child(spinner)
	var crust := Toon.cylinder(spinner, 2.4, 2.4, 0.4, Vector3.ZERO, Color("#e9a752"), 0.06)
	crust.rotation.x = PI / 2
	var cheese := Toon.cylinder(spinner, 2.1, 2.1, 0.45, Vector3.ZERO, Color("#ffd166"), 0.0)
	cheese.rotation.x = PI / 2
	for i in 7:
		var a := TAU * i / 7.0
		var p := Toon.cylinder(spinner, 0.38, 0.38, 0.5, Vector3(cos(a) * 1.3, sin(a) * 1.3, 0.02), Color("#d62828"), 0.0)
		p.rotation.x = PI / 2
	var t := create_tween().set_loops()
	t.tween_property(spinner, "rotation:y", TAU, 4.0).from(0.0)
	# Parking lot paint
	Toon.box(self, Vector3(w, 0.03, 9.0), Vector3(0, 0.015, d * 0.5 + 6.0), Color("#495057"), 0.0)
