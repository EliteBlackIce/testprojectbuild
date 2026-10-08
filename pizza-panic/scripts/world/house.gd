class_name House
extends Node3D
## A customer's house. Built facing +Z. Knock on the door and the resident
## (an EggBody) pops out to talk. Remembers how they feel about you.

var number := 0
var character: Dictionary = {}
var resident: EggBody
## Claude conversation history with this resident (kept all game session).
var history: Array = []
var mood := 0
var turns := 0
var outside := false
var sulking_until := 0.0

var door_spot: Node3D      ## where the resident stands (porch)
var knock_spot: Node3D     ## where you stand to knock
var curb_spot: Node3D      ## where the car should park (GPS target)
var _door: Node3D
var _beacon: MeshInstance3D
var _t := 0.0

const STYLES := ["cottage", "two_story", "modern", "tall"]
const WALLS := ["#e8cfa8", "#b5d3bd", "#ebbba6", "#b9c9e3", "#e3d18c", "#d6b4d6", "#c9a982", "#a9d2c9"]
const ROOFS := ["#8c3b2f", "#46607a", "#5b4a6b", "#3f6b4f", "#7a5236", "#9c5a3c"]


func build(num: int, c: Dictionary, rng: RandomNumberGenerator) -> void:
	number = num
	character = c
	var style: String = STYLES[rng.randi() % STYLES.size()]
	var wall := Color(WALLS[rng.randi() % WALLS.size()])
	var roof := Color(ROOFS[rng.randi() % ROOFS.size()])
	var w := rng.randf_range(7.5, 9.0)
	var d := rng.randf_range(6.5, 7.5)
	match style:
		"two_story":
			_body(w, d, 6.4, wall, roof, 2, rng)
		"modern":
			_modern(w + 1.0, d, wall, rng)
		"tall":
			_body(w - 2.0, d, 7.0, wall, roof, 2, rng)
		_:
			_body(w, d, 3.6, wall, roof, 1, rng)
	_porch(d, wall, rng)
	_yard(w, d, rng)

	door_spot = Node3D.new()
	door_spot.position = Vector3(0, 0, d * 0.5 + 1.3)
	add_child(door_spot)
	knock_spot = Node3D.new()
	knock_spot.position = Vector3(0, 0.9, d * 0.5 + 2.6)
	add_child(knock_spot)
	curb_spot = Node3D.new()
	curb_spot.position = Vector3(0, 0, 9.5)
	add_child(curb_spot)

	_beacon = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.15
	torus.rings = 24
	torus.ring_segments = 4
	_beacon.mesh = torus
	_beacon.material_override = Toon.glow(Color("#ffd166"), 2.0)
	_beacon.position = knock_spot.position + Vector3(0, -0.85, 0)
	_beacon.visible = false
	add_child(_beacon)

	resident = EggBody.new()
	add_child(resident)
	resident.build(character.get("look", {}))
	resident.position = door_spot.position
	resident.visible = false

	var door := Station.make(self, door_spot.position + Vector3(0, 1.1, -0.85), _knock_prompt, _knock_use, 3.4, 0.8)
	door.name = "Door"
	_limit_draw_distance(self)


func display_name() -> String:
	return character.get("name", "Someone")


## Customer is waiting for their pizza: glowing ring + they wait outside.
func set_target(on: bool) -> void:
	_beacon.visible = on
	if on:
		come_out()
	elif outside and not Game.in_dialogue:
		go_inside()


func come_out() -> void:
	if outside:
		return
	outside = true
	resident.visible = true
	resident.position = door_spot.position + Vector3(0, 0, -1.0)
	resident.rotation.y = 0.0
	if character.get("look", {}).get("ghost", false):
		# Ghosts don't use doors. They just... come through.
		resident.position = door_spot.position + Vector3(0, 0.4, -1.6)
		var gt := create_tween()
		gt.tween_property(resident, "position", door_spot.position + Vector3(0, 0.25, 0), 1.6).set_trans(Tween.TRANS_SINE)
		gt.tween_property(resident, "position", door_spot.position, 0.5)
		Sfx.play("boing", 0.5, -10.0)
		return
	var tw := create_tween()
	tw.tween_property(_door, "rotation:y", -1.6, 0.25)
	tw.parallel().tween_property(resident, "position", door_spot.position, 0.4)


func go_inside() -> void:
	if not outside:
		return
	outside = false
	resident.waving = false
	resident.talking = false
	var tw := create_tween()
	tw.tween_property(resident, "position", door_spot.position + Vector3(0, 0, -1.2), 0.35)
	tw.tween_callback(func(): resident.visible = false)
	tw.tween_property(_door, "rotation:y", 0.0, 0.2)
	tw.tween_callback(func(): Sfx.play("knock", 0.6, -10.0))


## Storms inside and won't answer for a while.
func storm_inside(seconds := 25.0) -> void:
	sulking_until = Time.get_ticks_msec() / 1000.0 + seconds
	resident.express("angry", 3.0)
	go_inside()
	Sfx.play("slam")


func is_sulking() -> bool:
	return Time.get_ticks_msec() / 1000.0 < sulking_until


func _process(delta: float) -> void:
	_t += delta
	if _beacon.visible:
		var s := 1.0 + sin(_t * 5.0) * 0.08
		_beacon.scale = Vector3(s, 1.0, s)
		resident.waving = outside and not Game.in_dialogue


# --- knocking ------------------------------------------------------------------------------

## Main sets this so the house can start conversations.
static var on_knock: Callable


func _knock_prompt(player: Node) -> String:
	if Game.in_dialogue:
		return ""
	var holding := (player as PlayerEgg).held as Pizza
	var label := "[E] Knock on #%d (%s)" % [number, display_name()]
	if holding and holding.is_boxed():
		var t := Game.ticket(holding.data.ticket)
		if not t.is_empty() and t.house == self:
			label = "[E] Deliver pizza #%d to %s!" % [holding.data.ticket, display_name()]
	return label


func _knock_use(player: Node) -> void:
	if on_knock.is_valid():
		on_knock.call(self, player)


# --- building ----------------------------------------------------------------------------------

func _body(w: float, d: float, h: float, wall: Color, roof: Color, floors: int, rng: RandomNumberGenerator) -> void:
	Toon.block(self, Vector3(w, h, d), Vector3.ZERO, wall, 0.05, 0.03)
	Toon.solid_box(self, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	# Foundation band
	Toon.box(self, Vector3(w + 0.1, 0.5, d + 0.1), Vector3(0, 0.25, 0), wall.darkened(0.35), 0.0)
	# Gable roof (ridge along X) with overhang
	var r := Toon.mesh(self, Shapes.prism(Vector3(d + 1.0, 2.6, w + 0.8)), Vector3(0, h + 1.3, 0), roof, 0.03)
	r.rotation.y = PI / 2
	# Chimney
	if rng.randf() < 0.7:
		Toon.block(self, Vector3(0.8, 2.4, 0.8), Vector3(w * 0.28 * (1 if rng.randf() < 0.5 else -1), h + 0.2, -d * 0.15), Color("#9c5a3c"), 0.05, 0.015)
	# Windows: per floor, either side of the door
	var front := d * 0.5
	for f in floors:
		var wy := 1.9 + f * 2.9
		for side: int in [-1, 1]:
			if f == 0 or rng.randf() < 0.9:
				_window(Vector3(w * 0.3 * side, wy, front + 0.02), rng)
		if f > 0:
			_window(Vector3(0, wy, front + 0.02), rng)
	# Side windows
	for side: int in [-1, 1]:
		var sw := Node3D.new()
		sw.position = Vector3(w * 0.5 + 0.02, 0, 0) * side
		sw.rotation.y = PI / 2 * side
		add_child(sw)
		_window_on(sw, Vector3(0, 1.9, 0), rng)


func _modern(w: float, d: float, wall: Color, rng: RandomNumberGenerator) -> void:
	var h := 5.6
	Toon.block(self, Vector3(w, h, d), Vector3.ZERO, wall.lightened(0.2), 0.03, 0.03)
	Toon.solid_box(self, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	# Offset upper box + flat roof slab
	Toon.block(self, Vector3(w * 0.6, 2.4, d * 0.9), Vector3(w * 0.15, h, -0.3), Color("#5d6d7e"), 0.03, 0.025)
	Toon.box(self, Vector3(w + 0.6, 0.25, d + 0.6), Vector3(0, h + 0.12, 0), Color("#2d3436"), 0.02)
	# Big glass front
	var glass := Toon.box(self, Vector3(w * 0.35, 2.4, 0.06), Vector3(w * 0.25, 2.6, d * 0.5 + 0.03), Color("#9cc9d9"), 0.0)
	glass.material_override = Toon.glow(Color("#bfe3ef"), 0.35)
	Toon.box(self, Vector3(w * 0.38, 0.12, 0.12), Vector3(w * 0.25, 3.85, d * 0.5 + 0.05), Color("#2d3436"), 0.0)
	_window(Vector3(-w * 0.32, 4.2, d * 0.5 + 0.02), rng)
	# Wood slats
	for i in 6:
		Toon.box(self, Vector3(0.12, 2.2, 0.06), Vector3(-w * 0.45 + i * 0.25, 1.4, d * 0.5 + 0.03), Color("#a1785a"), 0.0)


func _window(pos: Vector3, rng: RandomNumberGenerator) -> void:
	_window_on(self, pos, rng)


func _window_on(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var lit := rng.randf() < 0.5
	var pane := MeshInstance3D.new()
	pane.mesh = Shapes.box(Vector3(1.3, 1.3, 0.05))
	pane.material_override = Toon.mat(Color("#8fb8c9"), 0.0)
	pane.position = pos
	parent.add_child(pane)
	# About half the windows light up at night (DayCycle swaps the material).
	if lit:
		pane.add_to_group("night_window")
	Toon.box(parent, Vector3(1.5, 0.14, 0.1), pos + Vector3(0, -0.72, 0.03), Color("#f6f4ef"), 0.0)
	Toon.box(parent, Vector3(0.08, 1.3, 0.08), pos + Vector3(0, 0, 0.03), Color("#f6f4ef"), 0.0)
	Toon.box(parent, Vector3(1.3, 0.08, 0.08), pos + Vector3(0, 0, 0.03), Color("#f6f4ef"), 0.0)
	# Shutters
	if rng.randf() < 0.5:
		var sc := Color(["#3f6b4f", "#46607a", "#8c3b2f", "#2d3436"][rng.randi() % 4])
		for side: int in [-1, 1]:
			Toon.box(parent, Vector3(0.35, 1.4, 0.06), pos + Vector3(0.85 * side, 0, 0.02), sc, 0.0)
	# Flower box
	if rng.randf() < 0.4:
		Toon.box(parent, Vector3(1.4, 0.25, 0.3), pos + Vector3(0, -0.85, 0.15), Color("#7a5236"), 0.008)
		for k in 4:
			Toon.ball(parent, 0.1, pos + Vector3(-0.5 + k * 0.33, -0.65, 0.2), Color(["#ff6b9d", "#ffd166", "#c77dff", "#ff8c42"][k]), 0.0, 5)


func _porch(d: float, wall: Color, rng: RandomNumberGenerator) -> void:
	var front := d * 0.5
	# Door (pivots open), frame, knob, number
	_door = Node3D.new()
	_door.position = Vector3(-0.65, 0, front + 0.05)
	add_child(_door)
	var door_col := Color(["#8c3b2f", "#2e86de", "#27ae60", "#f39c12", "#6d4c41", "#8e44ad"][rng.randi() % 6])
	Toon.box(_door, Vector3(1.3, 2.4, 0.12), Vector3(0.65, 1.2, 0), door_col, 0.012)
	Toon.ball(_door, 0.07, Vector3(1.1, 1.2, 0.1), Color("#ffd166"), 0.0, 5)
	Toon.box(self, Vector3(1.7, 0.18, 0.2), Vector3(0, 2.5, front + 0.05), Color("#f6f4ef"), 0.008)
	for side: int in [-1, 1]:
		Toon.box(self, Vector3(0.18, 2.5, 0.2), Vector3(0.78 * side, 1.25, front + 0.05), Color("#f6f4ef"), 0.008)
	var num := Toon.label(self, str(number), Vector3(1.4, 2.2, front + 0.08), 80, Color("#2b1c18"), false)
	num.outline_size = 0
	Toon.box(self, Vector3(0.6, 0.4, 0.05), Vector3(1.4, 2.2, front + 0.04), Color("#f6f4ef"), 0.0)
	# Porch deck + steps + little roof on posts
	Toon.block(self, Vector3(3.6, 0.35, 2.0), Vector3(0, 0, front + 1.0), wall.darkened(0.3), 0.05, 0.015)
	Toon.block(self, Vector3(1.8, 0.18, 0.6), Vector3(0, 0, front + 2.3), wall.darkened(0.35), 0.05, 0.01)
	if rng.randf() < 0.6:
		Toon.box(self, Vector3(3.8, 0.15, 2.3), Vector3(0, 3.0, front + 1.0), wall.darkened(0.2), 0.012)
		for side: int in [-1, 1]:
			Toon.cyl(self, 0.09, 0.09, 2.7, Vector3(1.65 * side, 1.5, front + 1.9), Color("#f6f4ef"), 0.008, 6)
	# Doormat
	Toon.box(self, Vector3(1.0, 0.02, 0.6), Vector3(0, 0.36, front + 0.5), Color("#c0392b"), 0.0)


func _yard(w: float, d: float, rng: RandomNumberGenerator) -> void:
	var front := d * 0.5
	# Path to the sidewalk
	for i in 5:
		Toon.box(self, Vector3(1.2, 0.04, 0.8), Vector3(0, 0.04, front + 3.0 + i * 1.1), Color("#d8d3cd"), 0.0)
	# Mailbox with the number
	var mb_x := 2.6 * (1 if rng.randf() < 0.5 else -1)
	Toon.box(self, Vector3(0.12, 1.1, 0.12), Vector3(mb_x, 0.55, 8.0), Color("#6c584c"), 0.008)
	Toon.block(self, Vector3(0.45, 0.4, 0.7), Vector3(mb_x, 1.05, 8.0), Color(["#3a86ff", "#c0392b", "#2d3436", "#27ae60"][rng.randi() % 4]), 0.3, 0.01)
	var tag := Toon.label(self, str(number), Vector3(mb_x, 1.75, 8.0), 70, Color("#ffd166"))
	tag.set_meta("detail", true)
	# Bushes along the front
	for side: int in [-1, 1]:
		for k in rng.randi_range(1, 3):
			Toon.mesh(self, Shapes.blob(rng.randf_range(0.5, 0.8), rng.randi(), 0.2), Vector3(side * (w * 0.5 - 0.6 - k * 1.1), 0.35, front + 0.6), Color(["#52b788", "#40916c", "#74c69d"][rng.randi() % 3]), 0.015)
	# Picket fence along the sidewalk (gap for the path)
	if rng.randf() < 0.55:
		var fence_col := Color(["#f6f4ef", "#f6f4ef", "#a1785a"][rng.randi() % 3])
		var xforms: Array[Transform3D] = []
		var x := -7.0
		while x <= 7.0:
			if absf(x) > 1.0:
				xforms.append(Transform3D(Basis(), Vector3(x, 0.45, 8.9)))
			x += 0.5
		Toon.multimesh(self, Shapes.chamfer_box(Vector3(0.14, 0.9, 0.06), 0.3), Toon.mat(fence_col, 0.0), xforms)
		for side: int in [-1, 1]:
			Toon.box(self, Vector3(6.0, 0.08, 0.05), Vector3(side * 4.0, 0.6, 8.9), fence_col, 0.0)
	# Garden extras: gnome, flamingo, birdbath, swing tree...
	var extra := rng.randi() % 4
	var ep := Vector3(rng.randf_range(-5.0, 5.0), 0, front + rng.randf_range(2.5, 5.5))
	if absf(ep.x) < 1.2:
		ep.x = 3.0
	match extra:
		0:
			Toon.cyl(self, 0.18, 0.22, 0.35, ep + Vector3(0, 0.17, 0), Color("#2e86de"), 0.008, 6)
			Toon.ball(self, 0.15, ep + Vector3(0, 0.45, 0), Color("#f2d0a9"), 0.008, 6)
			Toon.cyl(self, 0.0, 0.16, 0.35, ep + Vector3(0, 0.7, 0), Color("#c0392b"), 0.008, 6)
		1:
			Toon.cyl(self, 0.06, 0.12, 0.7, ep + Vector3(0, 0.35, 0), Color("#b2bec3"), 0.008, 6)
			Toon.cyl(self, 0.45, 0.3, 0.12, ep + Vector3(0, 0.75, 0), Color("#b2bec3"), 0.008, 8)
		2:
			Toon.mesh(self, Shapes.blob(1.6, rng.randi(), 0.2), ep + Vector3(0, 3.6, 0), Color("#52b788"), 0.03)
			Toon.cyl(self, 0.22, 0.32, 2.6, ep + Vector3(0, 1.3, 0), Color("#8b5e3c"), 0.015, 6)
			Toon.solid_box(self, Vector3(0.6, 3.0, 0.6), ep + Vector3(0, 1.5, 0))
		3:
			Toon.box(self, Vector3(1.8, 0.4, 0.8), ep + Vector3(0, 0.2, 0), Color("#7a5236"), 0.008)
			for k in 5:
				Toon.ball(self, 0.13, ep + Vector3(-0.7 + k * 0.35, 0.5, 0), Color(["#ff6b9d", "#ffd166", "#c77dff", "#ff8c42", "#f6f4ef"][k]), 0.0, 5)


## Small details vanish at a distance (fog hides the pop), which keeps the
## frame rate high with dozens of houses.
func _limit_draw_distance(root: Node) -> void:
	for c in root.get_children():
		if c is GeometryInstance3D:
			var g := c as GeometryInstance3D
			var aabb := g.get_aabb() if g is VisualInstance3D else AABB()
			var big := aabb.size.length() > 4.0
			g.visibility_range_end = 400.0 if big else 110.0
			g.visibility_range_end_margin = 10.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if c != resident:
			_limit_draw_distance(c)
