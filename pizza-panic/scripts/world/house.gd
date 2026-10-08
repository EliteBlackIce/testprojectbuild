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

const STYLES := ["craftsman", "colonial", "cottage", "ranch", "victorian", "modern"]
## Designed palettes (wall, trim, roof, door, shutters, accent) so streets look curated, not random.
const PALETTES := [
	{"wall": "#e9d8b4", "trim": "#fffaf0", "roof": "#6d4c41", "door": "#b5483a", "shutter": "#3f6b4f", "accent": "#d9a441"},
	{"wall": "#a9c7d9", "trim": "#ffffff", "roof": "#455a64", "door": "#f2b134", "shutter": "#2f4858", "accent": "#e07a5f"},
	{"wall": "#e3b5a8", "trim": "#fff4ec", "roof": "#5b4a6b", "door": "#2e6f6f", "shutter": "#fff4ec", "accent": "#81b29a"},
	{"wall": "#b7d3b4", "trim": "#fbf8ef", "roof": "#4d5b57", "door": "#c4553d", "shutter": "#2f5d50", "accent": "#f2cc8f"},
	{"wall": "#f1e3a6", "trim": "#ffffff", "roof": "#7a3b2e", "door": "#3d5a80", "shutter": "#3d5a80", "accent": "#ee6c4d"},
	{"wall": "#c9b6d9", "trim": "#fffafc", "roof": "#3f3d56", "door": "#e9c46a", "shutter": "#6d597a", "accent": "#e56b6f"},
	{"wall": "#d8a47f", "trim": "#fff1de", "roof": "#52352b", "door": "#2a6f97", "shutter": "#52352b", "accent": "#8ab17d"},
	{"wall": "#cfd8dc", "trim": "#ffffff", "roof": "#37474f", "door": "#d1495b", "shutter": "#37474f", "accent": "#edae49"},
]
const DOORS := ["#b5483a", "#2e6f9e", "#3d8b5f", "#e8a33d", "#7a4b8c", "#2b2d42"]
const FLOWERS := ["#ff6b9d", "#ffd166", "#c77dff", "#ff8c42", "#f6f4ef", "#ff4d6d"]

var _root: Node3D          ## everything of the house lives here (shifted sideways when there is a garage)
var _b: Batch
var _rng: RandomNumberGenerator
var _pal: Dictionary
var _ox := 0.0             ## sideways shift of the main house
var _deck_y := 0.0         ## porch floor height (residents stand on it)
var _front := 3.5          ## z of the front wall
var _porch_depth := 2.6
var _lot_half := 7.5
var _drive_x := 0.0
var _drive_w := 0.0
var _hw := 8.0             ## width of the main house
var _porch_w := 4.0


func build(num: int, c: Dictionary, rng: RandomNumberGenerator) -> void:
	number = num
	character = c
	_rng = rng
	_pal = PALETTES[rng.randi() % PALETTES.size()].duplicate()
	if rng.randf() < 0.5:
		_pal.door = DOORS[rng.randi() % DOORS.size()]
	var style: String = STYLES[rng.randi() % STYLES.size()]
	_root = Node3D.new()
	add_child(_root)
	_b = Batch.new()
	var has_garage := style in ["craftsman", "ranch", "modern"] and rng.randf() < 0.75
	var garage_w := 4.2 if has_garage else 0.0
	match style:
		"craftsman":
			_craftsman(garage_w)
		"colonial":
			_colonial()
		"cottage":
			_cottage()
		"ranch":
			_ranch(garage_w)
		"victorian":
			_victorian()
		_:
			_modern(garage_w)
	_yard(has_garage, garage_w, style)
	_b.flush(_root, 150.0)

	door_spot = Node3D.new()
	door_spot.position = Vector3(_ox, _deck_y, _front + 1.1)
	add_child(door_spot)
	knock_spot = Node3D.new()
	knock_spot.position = Vector3(_ox, 0.9 + _gy(_ox, _front + _porch_depth + 1.0), _front + _porch_depth + 1.0)
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

	var door := Station.make(self, door_spot.position + Vector3(0, 1.1, -0.85), _knock_prompt, _knock_use, 3.6, 0.8)
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




# --- shared pieces ------------------------------------------------------------------------------

## Ground height at a house-local point, relative to the house's own base level.
func _gy(x: float, z: float) -> float:
	if not is_inside_tree():
		return 0.0
	var gp := to_global(Vector3(x, 0, z))
	return Terrain.ground_y(gp.x, gp.z) - global_position.y


## Same, for points in the main house frame (_root is shifted sideways when there is a garage).
func _gr(x: float, z: float) -> float:
	return _gy(x + _ox, z)


func _c(key: String) -> Color:
	return Color(_pal[key])


## Main walls: body, foundation, clapboard siding lines, corner boards, belt courses.
func _shell(w: float, d: float, h: float, floors: int, wall: Color, stone_base := false) -> void:
	_front = d * 0.5
	_hw = w
	Toon.block(_root, Vector3(w, h, d), Vector3.ZERO, wall, 0.05, 0.03)
	Toon.solid_box(_root, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	var trim := _c("trim")
	var base_h := 0.95 if stone_base else 0.6
	# The foundation reaches down to the lowest ground under the house (taller on the downhill side).
	var drop := 0.0
	for cx: float in [-w * 0.5, w * 0.5]:
		for cz: float in [-d * 0.5, d * 0.5, d * 0.5 + 1.5]:
			drop = maxf(drop, -_gr(cx, cz))
	_b.box(Vector3(0, (base_h - drop - 0.35) * 0.5, 0), Vector3(w + 0.14, base_h + drop + 0.35, d + 0.14), Color("#9b968a") if stone_base else wall.darkened(0.4))
	if stone_base:
		var sy := 0.2
		while sy < base_h:
			_b.box(Vector3(0, sy, d * 0.5 + 0.075), Vector3(w + 0.1, 0.03, 0.02), Color("#7d796f"))
			sy += 0.24
	var line := wall.darkened(0.13)
	var y := base_h + 0.3
	while y < h - 0.25:
		_b.box(Vector3(0, y, d * 0.5 + 0.012), Vector3(w - 0.1, 0.03, 0.03), line)
		_b.box(Vector3(0, y, -d * 0.5 - 0.012), Vector3(w - 0.1, 0.03, 0.03), line)
		for sx: int in [-1, 1]:
			_b.box(Vector3(sx * (w * 0.5 + 0.012), y, 0), Vector3(0.03, 0.03, d - 0.1), line)
		y += 0.34
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			_b.box(Vector3(sx * w * 0.5, h * 0.5 + 0.05, sz * d * 0.5), Vector3(0.2, h + 0.1, 0.2), trim)
	for f in range(1, floors):
		_b.box(Vector3(0, f * (h / floors), 0), Vector3(w + 0.22, 0.16, d + 0.22), trim)
	_b.box(Vector3(0, h + 0.05, 0), Vector3(w + 0.26, 0.14, d + 0.26), trim)


## Gable roof with real shingle rows, ridge cap, barge boards, gable-end trim, gutters.
func _roof(w: float, d: float, h: float, rise: float, over: float, rafters := false) -> void:
	var roof := _c("roof")
	var half := d * 0.5 + over
	var r := Toon.mesh(_root, Shapes.prism(Vector3(d + over * 2.0, rise, w + over * 2.0)), Vector3(0, h + rise * 0.5, 0), roof, 0.03)
	r.rotation.y = PI / 2
	var th := atan2(rise, half)
	var rows := maxi(3, int(sqrt(half * half + rise * rise) / 0.4))
	for side: int in [-1, 1]:
		for k in rows:
			var t := (k + 0.5) / rows
			_b.box(Vector3(0, h + rise * t + 0.03, side * (half * (1.0 - t) + 0.02)), Vector3(w + over * 2.0 + 0.02, 0.04, 0.1), roof.darkened(0.18 if k % 2 == 0 else 0.07), Vector3(side * th, 0, 0))
	_b.box(Vector3(0, h + rise + 0.02, 0), Vector3(w + over * 2.0 + 0.12, 0.13, 0.22), roof.darkened(0.3))
	var slope := sqrt(half * half + rise * rise)
	for side: int in [-1, 1]:
		for sx: int in [-1, 1]:
			_b.box(Vector3(sx * (w * 0.5 + over + 0.02), h + rise * 0.5, side * half * 0.5), Vector3(0.1, 0.16, slope), _c("trim"), Vector3(side * th, 0, 0))
	# wall-colored triangle under the gable ends + a little round vent
	var wall_c := Color("#f1ead9")
	for sx: int in [-1, 1]:
		var tri := Toon.mesh(_root, Shapes.prism(Vector3(d + over * 2.0 - 0.45, rise - 0.28, 0.05)), Vector3(sx * (w * 0.5 + over + 0.035), h + (rise - 0.28) * 0.5 + 0.1, 0), _c("trim").lerp(wall_c, 0.3), 0.0)
		tri.rotation.y = PI / 2.0
		_b.cyl(Vector3(sx * (w * 0.5 + over + 0.1), h + rise * 0.35, 0), 0.28, 0.05, Color("#8fb8c9"), Vector3(0, 0, PI / 2))
	# eave details
	if rafters:
		var x := -w * 0.5 - over + 0.3
		while x < w * 0.5 + over:
			for side: int in [-1, 1]:
				_b.box(Vector3(x, h - 0.04, side * (half + 0.02)), Vector3(0.1, 0.16, 0.45), Color("#6b4a32"))
			x += 0.65
	for side: int in [-1, 1]:
		_b.cyl(Vector3(0, h - 0.1, side * (half + 0.05)), 0.07, w + over * 2.0, Color("#cfd8dc"), Vector3(0, 0, PI / 2))
		for sx: int in [-1, 1]:
			_b.cyl(Vector3(sx * (w * 0.5 + over - 0.1), h * 0.5, side * (half + 0.05)), 0.05, h, Color("#cfd8dc"))


func _chimney(x: float, z: float, base_h: float, top_h: float, brick := Color("#a4553b")) -> void:
	Toon.block(_root, Vector3(0.95, top_h - base_h, 0.95), Vector3(x, base_h, z), brick, 0.04, 0.02)
	var y := base_h + 0.2
	while y < top_h:
		_b.box(Vector3(x, y, z + 0.48), Vector3(0.96, 0.03, 0.02), brick.darkened(0.25))
		_b.box(Vector3(x + 0.48, y, z), Vector3(0.02, 0.03, 0.96), brick.darkened(0.25))
		y += 0.22
	_b.box(Vector3(x, top_h + 0.07, z), Vector3(1.15, 0.14, 1.15), Color("#8f8a80"))
	for dx: int in [-1, 1]:
		_b.cyl(Vector3(x + dx * 0.2, top_h + 0.27, z), 0.1, 0.25, Color("#5a5148"))


## A proper window: glass set back inside a frame, sill, header, muntins, curtains, optional shutters and flower box.
func _window(x: float, y: float, z: float, w := 1.2, h := 1.5, shutters := false, flower := false, rot_y := 0.0, panes := 3) -> void:
	var R := Basis(Vector3.UP, rot_y)
	var c := Vector3(x, y, z)
	var rot := Vector3(0, rot_y, 0)
	var trim := _c("trim")
	var lit := _rng.randf() < 0.5
	_b.glass(c + R * Vector3(0, 0, 0.01), Vector3(w, h, 0.05), lit, rot)
	for sx: int in [-1, 1]:
		_b.box(c + R * Vector3(sx * (w * 0.5 + 0.06), 0, 0.05), Vector3(0.12, h + 0.24, 0.14), trim, rot)
	_b.box(c + R * Vector3(0, h * 0.5 + 0.06, 0.05), Vector3(w + 0.24, 0.12, 0.14), trim, rot)
	_b.box(c + R * Vector3(0, -h * 0.5 - 0.1, 0.12), Vector3(w + 0.5, 0.1, 0.3), trim, rot)
	_b.box(c + R * Vector3(0, h * 0.5 + 0.2, 0.08), Vector3(w + 0.46, 0.1, 0.2), trim, rot)
	_b.box(c + R * Vector3(0, 0, 0.045), Vector3(0.05, h, 0.06), trim, rot)
	for k in panes - 1:
		_b.box(c + R * Vector3(0, -h * 0.5 + h * (k + 1) / float(panes), 0.045), Vector3(w, 0.05, 0.06), trim, rot)
	if _rng.randf() < 0.55:
		var cur := _c("accent").lerp(Color.WHITE, 0.35)
		for sx: int in [-1, 1]:
			_b.box(c + R * Vector3(sx * (w * 0.5 - w * 0.14), h * 0.08, 0.04), Vector3(w * 0.26, h * 0.8, 0.03), cur, rot)
	if shutters:
		var sc := _c("shutter")
		for sx: int in [-1, 1]:
			var sp := Vector3(sx * (w * 0.5 + 0.43), 0, 0.05)
			_b.box(c + R * sp, Vector3(0.44, h + 0.28, 0.07), sc, rot)
			_b.box(c + R * (sp + Vector3(0, 0, 0.04)), Vector3(0.3, h - 0.1, 0.02), sc.darkened(0.15), rot)
			for k in 4:
				_b.box(c + R * (sp + Vector3(0, -h * 0.35 + k * h * 0.23, 0.055)), Vector3(0.3, 0.025, 0.02), sc.lightened(0.15), rot)
	if flower:
		_b.box(c + R * Vector3(0, -h * 0.5 - 0.32, 0.22), Vector3(w + 0.3, 0.26, 0.3), Color("#7a5236"), rot)
		for k in 6:
			var fx := -w * 0.45 + k * w * 0.18
			_b.ball(c + R * Vector3(fx, -h * 0.5 - 0.12, 0.22), 0.1, Color(FLOWERS[(k + _rng.randi()) % FLOWERS.size()]))
			_b.ball(c + R * Vector3(fx, -h * 0.5 - 0.2, 0.3), 0.08, Color("#52b788"))


## The front door: swinging slab (animated by come_out), casing, transom, sidelights, lanterns, number, wreath.
func _door_unit(x: float, deck_y: float, sidelights := false, transom := true, wreath := true) -> void:
	var door_col := _c("door")
	_door = Node3D.new()
	_door.position = Vector3(x - 0.65, deck_y, _front + 0.05)
	_root.add_child(_door)
	Toon.box(_door, Vector3(1.3, 2.4, 0.12), Vector3(0.65, 1.2, 0), door_col, 0.012)
	for k in 2:
		_b_in_door(Vector3(0.65, 0.5 + k * 1.3, 0.07), Vector3(0.95, 0.85 if k == 0 else 0.5, 0.03), door_col.darkened(0.16))
	var lite := Toon.box(_door, Vector3(0.7, 0.5, 0.03), Vector3(0.65, 1.78, 0.075), Color("#bfe3ef"), 0.0)
	lite.add_to_group("night_window")
	Toon.ball(_door, 0.065, Vector3(1.12, 1.1, 0.11), Color("#ffd166"), 0.0, 6)
	Toon.box(_door, Vector3(1.1, 0.22, 0.03), Vector3(0.65, 0.12, 0.075), Color("#c9a24a"), 0.0)
	if wreath:
		for k in 10:
			var a := TAU * k / 10.0
			Toon.ball(_door, 0.055, Vector3(0.65 + cos(a) * 0.22, 1.45 + sin(a) * 0.22 + 0.4, 0.1), Color("#3c8d4f"), 0.0, 5)
		Toon.ball(_door, 0.07, Vector3(0.65, 1.55 + 0.17, 0.12), _c("accent"), 0.0, 5)
	var trim := _c("trim")
	var y0 := deck_y
	for sx: int in [-1, 1]:
		_b.box(Vector3(x + sx * 0.73, y0 + 1.27, _front + 0.1), Vector3(0.16, 2.55, 0.2), trim)
	_b.box(Vector3(x, y0 + 2.55, _front + 0.1), Vector3(1.62, 0.17, 0.22), trim)
	_b.box(Vector3(x, y0 + 2.7, _front + 0.1), Vector3(1.9, 0.1, 0.26), trim)
	if transom:
		_b.glass(Vector3(x, y0 + 2.95, _front + 0.03), Vector3(1.3, 0.38, 0.05), _rng.randf() < 0.5)
		_b.box(Vector3(x, y0 + 2.95, _front + 0.06), Vector3(1.3, 0.04, 0.05), trim)
		_b.box(Vector3(x, y0 + 3.18, _front + 0.08), Vector3(1.5, 0.08, 0.14), trim)
	if sidelights:
		for sx: int in [-1, 1]:
			_b.glass(Vector3(x + sx * 1.1, y0 + 1.3, _front + 0.03), Vector3(0.36, 2.2, 0.05), _rng.randf() < 0.5)
			_b.box(Vector3(x + sx * 1.1, y0 + 1.3, _front + 0.06), Vector3(0.04, 2.2, 0.05), trim)
			_b.box(Vector3(x + sx * 1.1, y0 + 2.45, _front + 0.08), Vector3(0.52, 0.1, 0.12), trim)
	# lanterns either side of the door
	for sx: int in [-1, 1]:
		var lx := x + sx * (1.65 if sidelights else 1.15)
		var lamp := Toon.box(_root, Vector3(0.18, 0.3, 0.18), Vector3(lx, y0 + 2.0, _front + 0.2), Color("#fff1c9"), 0.0)
		lamp.material_override = Toon.glow(Color("#d9d2c0"), 1.2)
		lamp.add_to_group("lamp_glow")
		_b.box(Vector3(lx, y0 + 2.2, _front + 0.2), Vector3(0.24, 0.06, 0.24), Color("#2d3436"))
		_b.box(Vector3(lx, y0 + 1.82, _front + 0.2), Vector3(0.22, 0.05, 0.22), Color("#2d3436"))
		_b.box(Vector3(lx, y0 + 2.0, _front + 0.1), Vector3(0.06, 0.06, 0.2), Color("#2d3436"))
	var px := x + 1.0 + (0.7 if sidelights else 0.0)
	Signs.board(_root, str(number), Vector3(px, y0 + 2.75, _front + 0.06), Vector2(0.6, 0.42), Color("#fff4dc"), Color("#2b1c18"), 0.0, "wall", Color("#7a5236"))


func _b_in_door(local: Vector3, size: Vector3, col: Color) -> void:
	Toon.box(_door, size, local, col, 0.0)


## The porch, with real depth: raised deck, lattice skirt, steps with a ramp collider,
## railings with balusters, columns, a roof with a beadboard ceiling, and furniture.
## kind: posts ("round"/"tapered"/"turned"/"square"/"steel"), roof ("gable"/"shed"/"flat"/"hood"/"none"), rail (bool), swing, chairs.
func _porch(x: float, width: float, depth: float, kind: Dictionary) -> void:
	var trim := _c("trim")
	var dy := 0.42
	_porch_w = width
	_deck_y = dy
	_porch_depth = depth
	var zc := _front + depth * 0.5
	var deck_col := Color(kind.get("deck", "#b79871"))
	Toon.block(_root, Vector3(width, dy, depth), Vector3(x, 0, zc), deck_col.darkened(0.15), 0.03, 0.015)
	Toon.solid_box(_root, Vector3(width, dy, depth), Vector3(x, dy * 0.5, zc))
	var k := 0
	while k * 0.3 < depth - 0.1:
		_b.box(Vector3(x, dy + 0.004, _front + 0.15 + k * 0.3), Vector3(width - 0.05, 0.012, 0.02), deck_col.darkened(0.3))
		k += 1
	# under-deck fill + lattice skirt that reach whatever the ground does in front of the porch
	var pdrop := 0.0
	for cx: float in [x - width * 0.5, x + width * 0.5]:
		for cz: float in [_front, _front + depth]:
			pdrop = maxf(pdrop, -_gr(cx, cz))
	_b.box(Vector3(x, -pdrop * 0.5 - 0.1, zc), Vector3(width - 0.1, pdrop + 0.2, depth - 0.1), Color("#4a4540"))
	var gl := _gr(x, _front + depth)
	var lx := -width * 0.5 + 0.15
	while lx < width * 0.5:
		var gl_x := _gr(x + lx, _front + depth)
		_b.box(Vector3(x + lx, (dy - 0.04 + gl_x) * 0.5, _front + depth + 0.012), Vector3(0.025, dy - 0.04 - gl_x, 0.02), trim)
		lx += 0.22
	_b.box(Vector3(x, dy - 0.04, _front + depth + 0.02), Vector3(width + 0.06, 0.08, 0.06), trim)
	_b.box(Vector3(x, gl + 0.05, _front + depth + 0.02), Vector3(width + 0.06, 0.1, 0.06), trim)
	# steps: three treads with risers, a hidden ramp to walk up
	var sw := 1.9
	var gl2 := _gr(x, _front + depth + 1.1)
	var rise := maxf(dy - gl2, 0.2)
	for s in 3:
		var sh := rise * (3 - s) / 4.0
		_b.box(Vector3(x, gl2 + sh * 0.5 - 0.05, _front + depth + 0.17 + s * 0.34), Vector3(sw, sh + 0.1, 0.34), deck_col)
		_b.box(Vector3(x, gl2 + sh + 0.01, _front + depth + 0.2 + s * 0.34), Vector3(sw + 0.06, 0.04, 0.4), deck_col.lightened(0.12))
	var ramp := StaticBody3D.new()
	ramp.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cp := ConvexPolygonShape3D.new()
	var z0 := _front + depth
	var z1 := _front + depth + 1.1
	cp.points = PackedVector3Array([Vector3(x - sw * 0.5, gl2, z1), Vector3(x + sw * 0.5, gl2, z1), Vector3(x - sw * 0.5, dy, z0), Vector3(x + sw * 0.5, dy, z0), Vector3(x - sw * 0.5, gl2, z0), Vector3(x + sw * 0.5, gl2, z0)])
	cs.shape = cp
	ramp.add_child(cs)
	_root.add_child(ramp)
	# railings
	var has_rail: bool = kind.get("rail", true)
	if has_rail:
		var rx := width * 0.5 - 0.1
		var rz0 := _front + 0.08
		var rz1 := _front + depth - 0.1
		_rail(Vector3(x - rx, dy, rz0), Vector3(x - rx, dy, rz1))
		_rail(Vector3(x + rx, dy, rz0), Vector3(x + rx, dy, rz1))
		_rail(Vector3(x - rx, dy, rz1), Vector3(x - sw * 0.5 - 0.1, dy, rz1))
		_rail(Vector3(x + sw * 0.5 + 0.1, dy, rz1), Vector3(x + rx, dy, rz1))
		for sd: int in [-1, 1]:
			Toon.solid_box(_root, Vector3(0.12, 1.0, depth - 0.2), Vector3(x + sd * rx, dy + 0.5, zc))
		# stair handrails
		for sd: int in [-1, 1]:
			_b.box(Vector3(x + sd * (sw * 0.5 + 0.05), (dy + gl2) * 0.5 + 0.55, _front + depth + 0.55), Vector3(0.07, 0.07, 1.25), trim, Vector3(atan2(dy - gl2, 1.1), 0, 0))
			_b.box(Vector3(x + sd * (sw * 0.5 + 0.05), (dy + gl2) * 0.5 + 0.2, _front + depth + 0.55), Vector3(0.05, 0.9, 0.05), trim)
	# columns
	var posts: String = kind.get("posts", "round")
	var col_h := 2.55
	var px := width * 0.5 - 0.22
	var post_xs: Array = [-px, px]
	if width > 5.6:
		post_xs = [-px, -px * 0.33, px * 0.33, px]
	for cx: float in post_xs:
		var cz := _front + depth - 0.25
		var p := Vector3(x + cx, dy, cz)
		match posts:
			"tapered":
				_b.box(p + Vector3(0, 0.45, 0), Vector3(0.56, 0.9, 0.56), Color("#9b968a"))
				_b.box(p + Vector3(0, 0.92, 0), Vector3(0.64, 0.08, 0.64), Color("#b0aba0"))
				_b.taper(p + Vector3(0, 0.92 + (col_h - 0.92) * 0.5, 0), 0.2, col_h - 0.95, trim)
			"turned":
				_b.cyl(p + Vector3(0, col_h * 0.5, 0), 0.07, col_h, trim)
				for t in 3:
					_b.ball(p + Vector3(0, 0.5 + t * 0.7, 0), 0.11, trim, Vector3(1, 0.7, 1))
				_b.box(p + Vector3(0, 0.08, 0), Vector3(0.28, 0.16, 0.28), trim)
				for sd: int in [-1, 1]:
					_b.box(p + Vector3(sd * 0.3, col_h - 0.2, 0), Vector3(0.4, 0.28, 0.04), trim, Vector3(0, 0, sd * 0.6))
					_b.ball(p + Vector3(sd * 0.45, col_h - 0.32, 0), 0.05, trim)
			"steel":
				_b.box(p + Vector3(0, col_h * 0.5, 0), Vector3(0.1, col_h, 0.1), Color("#2d3436"))
			"square":
				_b.box(p + Vector3(0, col_h * 0.5, 0), Vector3(0.2, col_h, 0.2), trim)
				_b.box(p + Vector3(0, 0.1, 0), Vector3(0.3, 0.2, 0.3), trim)
				_b.box(p + Vector3(0, col_h - 0.06, 0), Vector3(0.3, 0.12, 0.3), trim)
			_:
				_b.cyl(p + Vector3(0, col_h * 0.5, 0), 0.14, col_h, trim)
				_b.box(p + Vector3(0, 0.08, 0), Vector3(0.36, 0.16, 0.36), trim)
				_b.box(p + Vector3(0, col_h - 0.06, 0), Vector3(0.38, 0.12, 0.38), trim)
		Toon.solid_box(_root, Vector3(0.3, col_h, 0.3), p + Vector3(0, col_h * 0.5, 0))
	# roof over the porch
	var roof_kind: String = kind.get("roof", "shed")
	var ry := dy + col_h + 0.12
	var roof := _c("roof")
	if roof_kind != "none":
		# beadboard ceiling in classic porch blue
		_b.box(Vector3(x, ry - 0.07, zc - 0.05), Vector3(width + 0.1, 0.04, depth - 0.05), Color("#cfe8ee"))
		for bx in int(width / 0.3):
			_b.box(Vector3(x - width * 0.5 + 0.15 + bx * 0.3, ry - 0.095, zc - 0.05), Vector3(0.012, 0.01, depth - 0.05), Color("#a9cdd6"))
		for sd: int in [-1, 1]:
			_b.box(Vector3(x + sd * (width * 0.5 - 0.05), ry - 0.02, zc - 0.05), Vector3(0.14, 0.18, depth), trim)
		_b.box(Vector3(x, ry - 0.02, _front + depth - 0.02), Vector3(width + 0.1, 0.2, 0.14), trim)
	match roof_kind:
		"shed":
			var slab := Toon.box(_root, Vector3(width + 0.5, 0.14, depth + 0.55), Vector3(x, ry + 0.2, zc + 0.12), roof, 0.025)
			slab.rotation.x = 0.13
			for r in 4:
				_b.box(Vector3(x, ry + 0.3 - r * 0.0, zc + 0.12 + (-depth * 0.5 + 0.25 + r * depth * 0.28) * 1.0), Vector3(width + 0.52, 0.03, 0.08), roof.darkened(0.2), Vector3(0.13, 0, 0))
		"gable":
			var pr := Toon.mesh(_root, Shapes.prism(Vector3(width + 0.6, 1.25, depth + 0.5)), Vector3(x, ry + 0.62, zc + 0.1), roof, 0.025)
			pr.rotation.y = 0.0
			var gt := Toon.mesh(_root, Shapes.prism(Vector3(width - 0.1, 1.0, 0.06)), Vector3(x, ry + 0.5, _front + depth + 0.37), trim, 0.0)
			gt.rotation.y = 0.0
			_b.cyl(Vector3(x, ry + 0.55, _front + depth + 0.41), 0.2, 0.04, Color("#8fb8c9"), Vector3(PI / 2, 0, 0))
		"hood":
			var slab2 := Toon.box(_root, Vector3(width + 0.4, 0.12, depth + 0.4), Vector3(x, ry + 0.1, zc + 0.15), roof, 0.025)
			slab2.rotation.x = 0.22
		"flat":
			Toon.box(_root, Vector3(width + 0.5, 0.22, depth + 0.5), Vector3(x, ry + 0.1, zc + 0.15), Color("#2d3436"), 0.02)
	# a hanging lantern
	var hl := Toon.box(_root, Vector3(0.2, 0.3, 0.2), Vector3(x + width * 0.22, ry - 0.5, _front + depth * 0.55), Color("#fff1c9"), 0.0)
	hl.material_override = Toon.glow(Color("#d9d2c0"), 1.2)
	hl.add_to_group("lamp_glow")
	_b.cyl(Vector3(x + width * 0.22, ry - 0.28, _front + depth * 0.55), 0.012, 0.3, Color("#2d3436"))
	# furniture & plants
	if kind.get("swing", false):
		var sx2 := x - width * 0.5 + 1.0
		var sz := _front + depth * 0.5
		for dx: float in [-0.6, 0.6]:
			_b.cyl(Vector3(sx2 + dx, ry - 0.55, sz), 0.012, 1.0, Color("#5a5148"))
		_b.box(Vector3(sx2, dy + 0.55, sz), Vector3(1.4, 0.08, 0.55), Color("#c79a68"))
		_b.box(Vector3(sx2, dy + 0.9, sz - 0.26), Vector3(1.4, 0.55, 0.06), Color("#c79a68"), Vector3(-0.15, 0, 0))
		for dx: float in [-0.7, 0.7]:
			_b.box(Vector3(sx2 + dx, dy + 0.7, sz), Vector3(0.06, 0.06, 0.5), Color("#c79a68"))
		_b.box(Vector3(sx2 - 0.3, dy + 0.68, sz - 0.1), Vector3(0.4, 0.14, 0.3), _c("accent"), Vector3(-0.15, 0.1, 0))
	if kind.get("chairs", false):
		for ci in 2:
			var cx2 := x + width * 0.5 - 0.9 - ci * 0.9
			var cz2 := _front + depth * 0.5 + 0.1
			_b.box(Vector3(cx2, dy + 0.42, cz2), Vector3(0.5, 0.06, 0.48), Color("#d9d2c0"))
			_b.box(Vector3(cx2, dy + 0.72, cz2 - 0.22), Vector3(0.5, 0.6, 0.05), Color("#d9d2c0"), Vector3(-0.18, 0, 0))
			for sd: int in [-1, 1]:
				_b.box(Vector3(cx2 + sd * 0.22, dy + 0.1, cz2), Vector3(0.04, 0.05, 0.7), Color("#8a6a4a"))
				_b.box(Vector3(cx2 + sd * 0.22, dy + 0.25, cz2), Vector3(0.04, 0.3, 0.04), Color("#8a6a4a"))
		_b.cyl(Vector3(x + width * 0.5 - 1.35, dy + 0.3, _front + depth * 0.5 - 0.3), 0.2, 0.05, Color("#8a6a4a"))
		_b.cyl(Vector3(x + width * 0.5 - 1.35, dy + 0.15, _front + depth * 0.5 - 0.3), 0.04, 0.3, Color("#8a6a4a"))
	# potted plants by the door and at the corners
	for pp in [Vector3(x - 1.5, dy, _front + 0.5), Vector3(x + width * 0.5 - 0.5, dy, _front + 0.5), Vector3(x - width * 0.5 + 0.5, dy, _front + depth - 0.5)]:
		if _rng.randf() < 0.75:
			_pot(pp)
	# welcome mat
	_b.box(Vector3(x, dy + 0.012, _front + 0.5), Vector3(1.0, 0.02, 0.6), Color("#b34a3a"))
	_b.box(Vector3(x, dy + 0.024, _front + 0.5), Vector3(0.8, 0.01, 0.4), Color("#e8d8b0"))


func _rail(a: Vector3, b: Vector3) -> void:
	var trim := _c("trim")
	var len := a.distance_to(b)
	var mid := (a + b) * 0.5
	var yaw := atan2(b.x - a.x, b.z - a.z)
	for ry: float in [0.95, 0.2]:
		_b.box(mid + Vector3(0, ry, 0), Vector3(0.07, 0.07, len), trim, Vector3(0, yaw, 0))
	_b.box(mid + Vector3(0, 0.98, 0), Vector3(0.12, 0.04, len), trim.darkened(0.06), Vector3(0, yaw, 0))
	var n := int(len / 0.17)
	var dir := (b - a) / maxf(1, n)
	for i in n + 1:
		_b.cyl(a + dir * i + Vector3(0, 0.58, 0), 0.022, 0.78, trim)


func _pot(p: Vector3) -> void:
	var pot_c := Color(["#c0673b", "#b0603a", "#5d7a8c", "#d9d2c0"][_rng.randi() % 4])
	_b.taper(p + Vector3(0, 0.2, 0), 0.2, 0.4, pot_c)
	_b.ball(p + Vector3(0, 0.55, 0), 0.26, Color("#3c8d4f"), Vector3(1, 0.8, 1))
	for k in 4:
		_b.ball(p + Vector3(_rng.randf_range(-0.18, 0.18), 0.62 + _rng.randf() * 0.15, _rng.randf_range(-0.18, 0.18)), 0.07, Color(FLOWERS[_rng.randi() % FLOWERS.size()]))


# --- the six house styles --------------------------------------------------------------------------

## Attached garage on the +x side: box, low roof, paneled door, lights, driveway out to the street.
func _garage(gx: float, d: float, h: float, wall: Color, gw: float) -> void:
	var gd := d - 0.8
	var gz := -0.4
	var front := gz + gd * 0.5
	Toon.block(_root, Vector3(gw, h, gd), Vector3(gx, 0, gz), wall, 0.05, 0.03)
	Toon.solid_box(_root, Vector3(gw, h, gd), Vector3(gx, h * 0.5, gz))
	var gdrop := 0.0
	for cx: float in [gx - gw * 0.5, gx + gw * 0.5]:
		for cz: float in [gz - gd * 0.5, gz + gd * 0.5]:
			gdrop = maxf(gdrop, -_gr(cx, cz))
	_b.box(Vector3(gx, (0.3 - gdrop - 0.35) * 0.5, gz), Vector3(gw + 0.1, 0.3 + gdrop + 0.35, gd + 0.1), wall.darkened(0.4))
	var trim := _c("trim")
	var pr := Toon.mesh(_root, Shapes.prism(Vector3(gw + 0.9, 1.5, gd + 0.9)), Vector3(gx, h + 0.75, gz), _c("roof"), 0.03)
	pr.rotation.y = 0.0
	var gt := Toon.mesh(_root, Shapes.prism(Vector3(gw + 0.2, 1.2, 0.06)), Vector3(gx, h + 0.62, front + 0.47), trim, 0.0)
	gt.rotation.y = 0.0
	_b.box(Vector3(gx, h + 0.04, gz), Vector3(gw + 0.2, 0.12, gd + 0.2), trim)
	# door panel with rows + window lites + frame
	var dw := gw - 0.7
	_b.box(Vector3(gx, 1.2, front + 0.03), Vector3(dw + 0.3, 2.5, 0.08), trim)
	_b.box(Vector3(gx, 1.15, front + 0.07), Vector3(dw, 2.3, 0.06), wall.lightened(0.25))
	for r in 4:
		_b.box(Vector3(gx, 0.45 + r * 0.55, front + 0.105), Vector3(dw - 0.1, 0.035, 0.02), wall.darkened(0.2))
	for k in 4:
		_b.glass(Vector3(gx - dw * 0.375 + k * dw * 0.25, 1.95, front + 0.105), Vector3(dw * 0.2, 0.24, 0.02), _rng.randf() < 0.4)
	for sd: int in [-1, 1]:
		var lamp := Toon.box(_root, Vector3(0.16, 0.26, 0.16), Vector3(gx + sd * (dw * 0.5 + 0.35), 2.6, front + 0.15), Color("#fff1c9"), 0.0)
		lamp.material_override = Toon.glow(Color("#d9d2c0"), 1.2)
		lamp.add_to_group("lamp_glow")
	# driveway out to the street: short slabs that follow the slope of the lot
	_drive_x = gx
	_drive_w = dw + 0.4
	var dz0 := front
	var dz1 := 9.0
	var zz := dz0
	while zz < dz1:
		var z2 := minf(zz + 1.5, dz1)
		var y0 := _gr(gx, zz)
		var y1 := _gr(gx, z2)
		var pitch := -atan2(y1 - y0, z2 - zz)
		_b.box(Vector3(gx, (y0 + y1) * 0.5 + 0.07, (zz + z2) * 0.5), Vector3(dw + 0.4, 0.05, (z2 - zz) + 0.02), Color("#c4bfb8"), Vector3(pitch, 0, 0))
		if int((zz - dz0) / 1.5) % 2 == 1:
			_b.box(Vector3(gx, (y0 + y1) * 0.5 + 0.1, zz), Vector3(dw + 0.4, 0.012, 0.04), Color("#9e9a94"), Vector3(pitch, 0, 0))
		zz = z2
	_b.ground = Callable(self, "_gr")
	# basketball hoop sometimes
	if _rng.randf() < 0.4:
		_b.cyl(Vector3(gx + dw * 0.5 + 0.7, 1.6, 6.5), 0.05, 3.2, Color("#444a50"))
		_b.box(Vector3(gx + dw * 0.5 + 0.7, 3.1, 6.2), Vector3(1.2, 0.8, 0.05), Color("#ffffff"))
		_b.box(Vector3(gx + dw * 0.5 + 0.7, 3.0, 6.2 + 0.2), Vector3(0.45, 0.05, 0.45), Color("#e8672a"))
	# bins next to the garage
	for bi in 2:
		_b.box(Vector3(gx + gw * 0.5 + 0.45 + bi * 0.55, 0.45, front - 0.2), Vector3(0.5, 0.9, 0.55), Color("#2e5d9f" if bi == 0 else "#2f7a46"))
		_b.box(Vector3(gx + gw * 0.5 + 0.45 + bi * 0.55, 0.92, front - 0.2), Vector3(0.54, 0.06, 0.6), Color("#22446f" if bi == 0 else "#215c34"))
	_b.ground = Callable()


func _craftsman(gw: float) -> void:
	var w := 8.2
	var d := 6.8
	var h := 3.5
	_ox = -gw * 0.5
	_root.position.x = _ox
	var wall := _c("wall")
	_shell(w, d, h, 1, wall, true)
	_roof(w, d, h, 2.0, 0.95, true)
	_chimney(w * 0.3, -d * 0.2, h + 0.4, h + 3.1)
	for sd: int in [-1, 1]:
		_window(sd * 3.15, 1.95, _front + 0.01, 1.5, 1.5, false, sd < 0, 0.0, 3)
		_window(sd * (w * 0.5 + 0.01), 1.95, 1.0, 1.2, 1.4, false, false, sd * PI * 0.5)
	_door_unit(0.0, 0.42, true, true, true)
	_porch(0.0, 5.0, 2.7, {"posts": "tapered", "roof": "gable", "rail": true, "swing": true, "chairs": false, "deck": "#a9855c"})
	if gw > 0.0:
		_garage(w * 0.5 + gw * 0.5 - 0.05, d, h - 0.3, wall, gw)


func _colonial() -> void:
	var w := 9.0
	var d := 7.4
	var h := 6.2
	_ox = 0.0
	var wall := _c("wall")
	_shell(w, d, h, 2, wall, false)
	_roof(w, d, h, 2.6, 0.7, false)
	for sd: int in [-1, 1]:
		_chimney(sd * (w * 0.5 - 0.5), 0.0, h + 0.3, h + 3.3)
		for fx: float in [3.0]:
			_window(sd * fx, 1.95, _front + 0.01, 1.2, 1.7, true, false, 0.0, 6)
		for fx: float in [3.0, 1.55]:
			_window(sd * fx, 4.95, _front + 0.01, 1.2, 1.7, true, false, 0.0, 6)
		_window(sd * (w * 0.5 + 0.01), 1.95, 0.0, 1.2, 1.7, true, false, sd * PI * 0.5, 6)
		_window(sd * (w * 0.5 + 0.01), 4.95, 0.0, 1.2, 1.7, true, false, sd * PI * 0.5, 6)
	_window(0.0, 4.95, _front + 0.01, 1.2, 1.7, true, false, 0.0, 6)
	_door_unit(0.0, 0.42, true, true, true)
	_porch(0.0, 4.2, 2.3, {"posts": "round", "roof": "gable", "rail": true, "swing": false, "chairs": true, "deck": "#bda27c"})


func _cottage() -> void:
	var w := 7.2
	var d := 6.4
	var h := 3.3
	_ox = 0.0
	var wall := _c("wall")
	_shell(w, d, h, 1, wall, true)
	_roof(w, d, h, 3.5, 0.6, false)
	# cross gable above the entrance, with half-timbering
	var cg := Toon.mesh(_root, Shapes.prism(Vector3(3.8, 2.6, 3.2)), Vector3(0, h + 1.7, _front - 1.3), _c("roof"), 0.03)
	cg.rotation.y = 0.0
	var face := Toon.mesh(_root, Shapes.prism(Vector3(3.3, 2.15, 0.06)), Vector3(0, h + 1.55, _front + 0.3), wall.lightened(0.15), 0.0)
	face.rotation.y = 0.0
	var wood := Color("#5a3f2b")
	_b.box(Vector3(0, h + 0.55, _front + 0.35), Vector3(3.3, 0.12, 0.08), wood)
	_b.box(Vector3(0, h + 1.2, _front + 0.35), Vector3(0.12, 1.5, 0.08), wood)
	_b.box(Vector3(-0.8, h + 0.95, _front + 0.35), Vector3(0.1, 1.0, 0.08), wood, Vector3(0, 0, 0.7))
	_b.box(Vector3(0.8, h + 0.95, _front + 0.35), Vector3(0.1, 1.0, 0.08), wood, Vector3(0, 0, -0.7))
	_b.glass(Vector3(0, h + 1.25, _front + 0.36), Vector3(0.7, 0.8, 0.04), _rng.randf() < 0.5)
	_b.box(Vector3(0, h + 1.25, _front + 0.39), Vector3(0.9, 0.1, 0.05), wood)
	_b.box(Vector3(0, h + 1.25, _front + 0.39), Vector3(0.1, 1.0, 0.05), wood)
	_chimney(-w * 0.5 + 0.1, _front - 0.9, 0.3, h + 3.2, Color("#8a8277"))
	# bay window
	var bx := -2.3
	_b.glass(Vector3(bx, 1.8, _front + 0.5), Vector3(1.9, 1.5, 0.05), _rng.randf() < 0.5)
	for sd: int in [-1, 1]:
		_b.glass(Vector3(bx + sd * 1.15, 1.8, _front + 0.3), Vector3(1.1, 1.5, 0.05), _rng.randf() < 0.5, Vector3(0, -sd * 0.7, 0))
	_b.box(Vector3(bx, 0.5, _front + 0.4), Vector3(3.3, 0.95, 0.9), wall.darkened(0.2))
	_b.box(Vector3(bx, 2.7, _front + 0.4), Vector3(3.5, 0.18, 1.1), _c("trim"))
	_b.box(Vector3(bx, 1.05, _front + 0.52), Vector3(2.2, 0.1, 0.4), _c("trim"))
	for k in 3:
		_b.box(Vector3(bx - 0.6 + k * 0.6, 1.8, _front + 0.54), Vector3(0.05, 1.5, 0.06), _c("trim"))
	_window(w * 0.5 - 1.4, 1.95, _front + 0.01, 1.1, 1.4, true, true, 0.0, 4)
	_window(w * 0.5 + 0.01, 1.95, -0.5, 1.2, 1.4, true, false, PI * 0.5)
	_window(-w * 0.5 - 0.01, 1.95, 1.2, 1.2, 1.4, true, false, -PI * 0.5)
	_door_unit(0.8, 0.42, false, false, true)
	_porch(0.8, 3.2, 2.2, {"posts": "square", "roof": "hood", "rail": true, "swing": false, "chairs": false, "deck": "#8f8a80"})


func _ranch(gw: float) -> void:
	var w := 10.0
	var d := 6.2
	var h := 3.0
	_ox = -gw * 0.5
	_root.position.x = _ox
	var wall := _c("wall")
	_shell(w, d, h, 1, wall, false)
	# brick wainscot
	var brick := Color("#a45a45")
	_b.box(Vector3(0, 0.55, _front + 0.08), Vector3(w + 0.1, 1.1, 0.1), brick)
	var by := 0.15
	while by < 1.1:
		_b.box(Vector3(0, by, _front + 0.14), Vector3(w + 0.08, 0.03, 0.02), brick.darkened(0.3))
		by += 0.14
	_roof(w, d, h, 1.5, 1.0, false)
	_chimney(w * 0.25, -d * 0.1, h + 0.1, h + 2.5, brick)
	Toon.box(_root, Vector3(2.8, 1.5, 0.04), Vector3(-w * 0.28, 1.95, _front + 0.03), Color("#8fb8c9"), 0.0).add_to_group("night_window")
	_b.box(Vector3(-w * 0.28, 2.75, _front + 0.1), Vector3(3.1, 0.14, 0.16), _c("trim"))
	_b.box(Vector3(-w * 0.28, 1.1, _front + 0.1), Vector3(3.1, 0.14, 0.2), _c("trim"))
	for sd: int in [-1, 1]:
		_b.box(Vector3(-w * 0.28 + sd * 1.45, 1.95, _front + 0.1), Vector3(0.14, 1.7, 0.16), _c("trim"))
	_b.box(Vector3(-w * 0.28, 1.95, _front + 0.08), Vector3(0.06, 1.5, 0.06), _c("trim"))
	_window(w * 0.5 - 1.6, 1.9, _front + 0.01, 1.2, 1.2, true, true, 0.0, 2)
	_window(w * 0.5 + 0.01, 1.9, 0.0, 1.2, 1.2, false, false, PI * 0.5)
	_door_unit(1.3, 0.42, false, true, true)
	_porch(1.3, 4.0, 2.4, {"posts": "square", "roof": "shed", "rail": false, "swing": false, "chairs": true, "deck": "#b3a58f"})
	if gw > 0.0:
		_garage(w * 0.5 + gw * 0.5 - 0.05, d, h - 0.2, wall, gw)


func _victorian() -> void:
	var w := 7.6
	var d := 7.0
	var h := 6.3
	_ox = 0.0
	var wall := _c("wall")
	var accent := _c("accent")
	_shell(w, d, h, 2, wall, false)
	_roof(w, d, h, 3.4, 0.55, false)
	var cg := Toon.mesh(_root, Shapes.prism(Vector3(4.2, 3.0, 3.6)), Vector3(1.0, h + 1.8, _front - 1.5), _c("roof"), 0.03)
	cg.rotation.y = 0.0
	var face := Toon.mesh(_root, Shapes.prism(Vector3(3.7, 2.5, 0.06)), Vector3(1.0, h + 1.7, _front + 0.3), accent, 0.0)
	face.rotation.y = 0.0
	# fish-scale shingles on the gable and a band across the upper floor
	for row in 3:
		for k in 8 - row:
			_b.ball(Vector3(1.0 - (7 - row) * 0.22 + k * 0.44, h + 0.28 + row * 0.38, _front + 0.35), 0.22, accent.darkened(0.08 * (row % 2)), Vector3(1, 0.8, 0.3))
	for row in 2:
		for k in int(w / 0.4):
			_b.ball(Vector3(-w * 0.5 + 0.2 + k * 0.4 + (row % 2) * 0.2, h * 0.5 + 0.35 + row * 0.3, _front + 0.06), 0.2, accent.lightened(0.1 * row), Vector3(1, 0.8, 0.25))
	_b.glass(Vector3(1.0, h + 1.3, _front + 0.36), Vector3(0.8, 1.0, 0.04), _rng.randf() < 0.5)
	_b.box(Vector3(1.0, h + 1.3, _front + 0.39), Vector3(1.0, 0.1, 0.05), _c("trim"))
	_chimney(w * 0.3, -d * 0.2, h + 0.5, h + 3.4)
	# corner turret
	var tx := -w * 0.5 + 0.3
	var tz := _front - 0.6
	Toon.cyl(_root, 1.45, 1.45, h + 1.2, Vector3(tx, (h + 1.2) * 0.5, tz), wall.lightened(0.05), 0.04, 14)
	Toon.cyl(_root, 0.0, 1.9, 3.0, Vector3(tx, h + 1.2 + 1.5, tz), _c("roof"), 0.03, 14)
	Toon.ball(_root, 0.14, Vector3(tx, h + 4.4, tz), accent, 0.0, 6)
	_b.cyl(Vector3(tx, h + 1.25, tz), 1.6, 0.14, _c("trim"))
	for f in 2:
		for k in 3:
			var a := PI * 0.5 + (k - 1) * 0.65
			_b.glass(Vector3(tx + cos(a) * 1.46, 1.9 + f * 3.0, tz + sin(a) * 1.46), Vector3(0.45, 1.3, 0.05), _rng.randf() < 0.5, Vector3(0, PI * 0.5 - a, 0))
	Toon.solid_box(_root, Vector3(2.9, h, 2.9), Vector3(tx, h * 0.5, tz))
	_window(1.4, 1.95, _front + 0.01, 1.3, 1.7, true, false, 0.0, 4)
	_window(1.4, 4.95, _front + 0.01, 1.3, 1.5, false, false, 0.0, 4)
	_window(w * 0.5 + 0.01, 1.95, 0.0, 1.2, 1.5, true, false, PI * 0.5)
	_window(w * 0.5 + 0.01, 4.95, 0.0, 1.2, 1.5, true, false, PI * 0.5)
	_door_unit(-0.3, 0.42, false, true, true)
	_porch(0.2, 6.2, 3.0, {"posts": "turned", "roof": "shed", "rail": true, "swing": true, "chairs": true, "deck": "#c9b08d"})


func _modern(gw: float) -> void:
	var w := 8.4
	var d := 7.0
	var h := 3.2
	_ox = -gw * 0.5
	_root.position.x = _ox
	var wall := _c("wall").lightened(0.25)
	_front = d * 0.5
	_hw = w
	Toon.block(_root, Vector3(w, h, d), Vector3.ZERO, wall, 0.03, 0.03)
	Toon.solid_box(_root, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	var dark := Color("#2d3436")
	var wood := Color("#a1785a")
	# cantilevered upper volume, offset to one side, in dark cladding
	Toon.block(_root, Vector3(w * 0.62, 2.9, d * 0.95), Vector3(w * 0.17, h, -0.2), _c("roof").lightened(0.1), 0.03, 0.03)
	Toon.solid_box(_root, Vector3(w * 0.62, 2.9, d * 0.95), Vector3(w * 0.17, h + 1.45, -0.2))
	Toon.box(_root, Vector3(w + 0.7, 0.24, d + 0.7), Vector3(0, h + 0.12, 0), dark, 0.02)
	Toon.box(_root, Vector3(w * 0.62 + 0.6, 0.26, d * 0.95 + 0.6), Vector3(w * 0.17, h + 2.93, -0.2), dark, 0.02)
	# glass wall with mullions
	var gx := -w * 0.15
	_b.glass(Vector3(gx, 1.7, _front + 0.03), Vector3(w * 0.32, 2.7, 0.06), true)
	for k in 5:
		_b.box(Vector3(gx - w * 0.16 + k * w * 0.08, 1.7, _front + 0.07), Vector3(0.06, 2.7, 0.08), dark)
	_b.box(Vector3(gx, 3.05, _front + 0.07), Vector3(w * 0.34, 0.1, 0.1), dark)
	_b.box(Vector3(gx, 0.35, _front + 0.07), Vector3(w * 0.34, 0.1, 0.1), dark)
	for k in 7:
		_b.box(Vector3(w * 0.32 + k * 0.22, 1.5, _front + 0.04), Vector3(0.12, 2.8, 0.06), wood)
	_b.glass(Vector3(w * 0.17, h + 1.5, _front - 0.1), Vector3(w * 0.4, 1.4, 0.06), true)
	_b.box(Vector3(w * 0.17, h + 0.75, _front - 0.08), Vector3(w * 0.42, 0.1, 0.1), dark)
	_b.box(Vector3(w * 0.17, h + 2.28, _front - 0.08), Vector3(w * 0.42, 0.1, 0.1), dark)
	_door_unit(0.35, 0.42, false, false, false)
	_porch(0.35, 3.4, 2.5, {"posts": "steel", "roof": "flat", "rail": false, "swing": false, "chairs": false, "deck": "#8d8a85"})
	# planter with grasses
	_b.box(Vector3(-w * 0.5 + 0.4, 0.4, _front + 0.8), Vector3(0.7, 0.8, 1.6), dark)
	for k in 7:
		_b.cone(Vector3(-w * 0.5 + 0.4 + (k % 3 - 1) * 0.2, 1.2, _front + 0.3 + k * 0.2), 0.12, 0.8, Color("#9fc86b"))
	if gw > 0.0:
		_garage(w * 0.5 + gw * 0.5 - 0.05, d, h - 0.2, wall.darkened(0.1), gw)




# --- the yard ---------------------------------------------------------------------------------------

func _lx(v: Vector3) -> Vector3:
	return Vector3(v.x - _ox, v.y, v.z)    ## lot coordinates -> _root coordinates


func _yard(has_garage: bool, gw: float, style: String) -> void:
	var rng := _rng
	var trim := _c("trim")
	var path_z0 := _front + _porch_depth + 1.1
	_b.ground = Callable(self, "_gr")     # everything in the yard rides the ground
	# stepping-stone path to the sidewalk
	var pz := path_z0 + 0.2
	var k := 0
	while pz < 9.2:
		_b.box(Vector3(sin(k * 1.3) * 0.18, 0.1, pz), Vector3(1.35, 0.05, 0.78), Color("#d8d3cd"))
		_b.box(Vector3(sin(k * 1.3) * 0.18, 0.126, pz), Vector3(1.2, 0.012, 0.64), Color("#e6e1da"))
		pz += 0.9
		k += 1
	# foundation beds either side of the porch: mulch, shrubs, flowers
	var bw := _hw * 0.5 - 0.3
	for sd: int in [-1, 1]:
		var bed_x := sd * (_porch_w * 0.5 + (bw - _porch_w * 0.5) * 0.5 + 0.2)
		var bed_len := (bw - _porch_w * 0.5 - 0.3)
		if bed_len < 0.8:
			continue
		_b.box(Vector3(bed_x, 0.1, _front + 0.45), Vector3(bed_len, 0.05, 0.9), Color("#6b4a32"))
		var n := maxi(2, int(bed_len / 0.8))
		for j in n:
			var bxj := bed_x - bed_len * 0.5 + (j + 0.5) * bed_len / n
			var bush_r := rng.randf_range(0.28, 0.45)
			_b.ball(Vector3(bxj, 0.15 + bush_r * 0.75, _front + 0.4), bush_r, Color(["#52b788", "#40916c", "#74c69d", "#2d6a4f"][rng.randi() % 4]), Vector3(1.1, 0.9, 1.0))
			if rng.randf() < 0.6:
				for q in 3:
					_b.ball(Vector3(bxj + rng.randf_range(-0.2, 0.2), 0.12 + bush_r * 1.35, _front + 0.56 + rng.randf_range(-0.1, 0.1)), 0.07, Color(FLOWERS[rng.randi() % FLOWERS.size()]))
	# air conditioner + gas meter on the side of the house
	var side := 1 if not has_garage else -1
	_b.box(Vector3(side * (_hw * 0.5 + 0.45), 0.4, 1.2), Vector3(0.7, 0.8, 0.8), Color("#cfd4d8"))
	_b.cyl(Vector3(side * (_hw * 0.5 + 0.45), 0.82, 1.2), 0.3, 0.04, Color("#6c7378"))
	# mailbox at the curb
	var mx := (3.0 if rng.randf() < 0.5 else -3.0) + _ox
	if has_garage:
		mx = -3.0
	var mc := Color(["#3a86ff", "#c0392b", "#2d3436", "#27ae60"][rng.randi() % 4])
	var mp := _lx(Vector3(mx, 0, 8.0))
	_b.box(mp + Vector3(0, 0.55, 0), Vector3(0.12, 1.1, 0.12), Color("#6c584c"))
	_b.box(mp + Vector3(0, 1.2, 0), Vector3(0.45, 0.35, 0.72), mc)
	_b.cyl(mp + Vector3(0, 1.37, 0), 0.22, 0.72, mc, Vector3(PI / 2, 0, 0))
	_b.box(mp + Vector3(0.26, 1.35, 0.1), Vector3(0.04, 0.3, 0.1), Color("#e63946"))
	Signs.board(_root, str(number), mp + Vector3(0, 1.2 + _gr(mp.x, mp.z), 0.37), Vector2(0.4, 0.26), Color("#fff4dc"), Color("#2b1c18"), 0.0, "wall", mc.darkened(0.3))
	# picket fence along the sidewalk: stays inside this lot, with gaps for the path and the driveway
	if rng.randf() < 0.55:
		var fence_col := Color(["#f6f4ef", "#f6f4ef", "#a1785a", "#d9c7a0"][rng.randi() % 4])
		var lo := -7.1 - _ox
		var hi := 7.1 - _ox
		var gaps: Array[Vector2] = [Vector2(-1.1, 1.1)]
		if has_garage:
			gaps.append(Vector2(_drive_x - _drive_w * 0.5 - 0.3, _drive_x + _drive_w * 0.5 + 0.3))
		var in_gap := func(x: float) -> bool:
			for g in gaps:
				if x > g.x and x < g.y:
					return true
			return false
		var fx := lo
		while fx <= hi:
			if not in_gap.call(fx):
				_b.box(Vector3(fx, 0.45, 8.9), Vector3(0.14, 0.9, 0.05), fence_col)
				_b.box(Vector3(fx, 0.93, 8.9), Vector3(0.1, 0.1, 0.05), fence_col, Vector3(0, 0, 0.78))
			fx += 0.36
		for ry: float in [0.3, 0.7]:
			var rx := lo
			while rx < hi:
				var rend := minf(rx + 1.0, hi)
				var rmid := (rx + rend) * 0.5
				if not in_gap.call(rmid):
					_b.box(Vector3(rmid, ry, 8.86), Vector3(rend - rx, 0.07, 0.04), fence_col)
				rx += 1.0
		# one post at each end of the lot and one beside every gap (never two posts in the same spot)
		var posts: Array[float] = [lo, hi]
		for g in gaps:
			posts.append(g.x)
			posts.append(g.y)
		for pxx in posts:
			if pxx >= lo - 0.01 and pxx <= hi + 0.01 and not in_gap.call(pxx + 0.0):
				_b.box(Vector3(pxx, 0.55, 8.9), Vector3(0.18, 1.1, 0.18), fence_col)
				_b.ball(Vector3(pxx, 1.15, 8.9), 0.1, fence_col)
	# a tree in the lawn
	if rng.randf() < 0.65:
		var tpx := (-1 if rng.randf() < 0.5 else 1) * rng.randf_range(3.8, 5.0)
		var tp := _lx(Vector3(tpx, 0, rng.randf_range(5.6, 7.4)))
		tp.y = _gr(tp.x, tp.z)
		Toon.cyl(_root, 0.2, 0.3, 2.8, tp + Vector3(0, 1.4, 0), Color("#8b5e3c"), 0.015, 6)
		var crown := Color(["#52b788", "#40916c", "#95d5b2", "#e8a0bf", "#f4a261"][rng.randi() % 5])
		Toon.mesh(_root, Shapes.blob(1.7, rng.randi(), 0.2), tp + Vector3(0, 3.8, 0), crown, 0.03)
		Toon.mesh(_root, Shapes.blob(1.15, rng.randi(), 0.2), tp + Vector3(rng.randf_range(-0.9, 0.9), 4.5, rng.randf_range(-0.6, 0.6)), crown.lightened(0.1), 0.03)
		Toon.solid_box(_root, Vector3(0.6, 3.0, 0.6), tp + Vector3(0, 1.5, 0))
	# garden lamp post at the end of the path
	if rng.randf() < 0.4:
		var lp := _lx(Vector3(_ox + 1.2, 0, 8.4))
		_b.cyl(lp + Vector3(0, 0.6, 0), 0.04, 1.2, Color("#2d3436"))
		var lg := Toon.ball(_root, 0.14, lp + Vector3(0, 1.3 + _gr(lp.x, lp.z), 0), Color("#fff1c9"), 0.0, 8)
		lg.material_override = Toon.glow(Color("#d9d2c0"), 1.2)
		lg.add_to_group("lamp_glow")
	# little extras so no two lawns match
	var ex := _lx(Vector3(rng.randf_range(-5.8, 5.8), 0, rng.randf_range(_front + 3.8, 7.4)))
	if absf(ex.x + _ox) < 1.6:
		ex.x += 3.0
	match rng.randi() % 9:
		0:   # gnome
			_b.taper(ex + Vector3(0, 0.2, 0), 0.16, 0.4, Color("#2e86de"))
			_b.ball(ex + Vector3(0, 0.47, 0), 0.13, Color("#f2d0a9"))
			_b.cone(ex + Vector3(0, 0.72, 0), 0.14, 0.38, Color("#c0392b"))
			_b.ball(ex + Vector3(0, 0.38, 0.1), 0.1, Color("#ffffff"), Vector3(1, 0.8, 0.6))
		1:   # bird bath
			_b.cyl(ex + Vector3(0, 0.35, 0), 0.1, 0.7, Color("#b2bec3"))
			_b.cyl(ex + Vector3(0, 0.74, 0), 0.4, 0.1, Color("#b2bec3"))
			_b.cyl(ex + Vector3(0, 0.8, 0), 0.33, 0.03, Color("#8fd3f4"))
		2:   # flamingos
			for q in 2:
				var fp := ex + Vector3(q * 0.5, 0, 0)
				_b.cyl(fp + Vector3(0, 0.3, 0), 0.015, 0.6, Color("#f5a0b5"))
				_b.ball(fp + Vector3(0, 0.75, 0), 0.17, Color("#ff8fab"), Vector3(1, 1.2, 1))
				_b.cyl(fp + Vector3(0, 1.0, 0.05), 0.02, 0.3, Color("#ff8fab"), Vector3(0.3, 0, 0))
				_b.ball(fp + Vector3(0, 1.17, 0.12), 0.07, Color("#ff8fab"))
		3:   # sprinkler with a spray
			_b.cyl(ex + Vector3(0, 0.15, 0), 0.04, 0.3, Color("#444a50"))
			for q in 6:
				var a := TAU * q / 6.0
				_b.ball(ex + Vector3(cos(a) * 0.7, 0.45 + sin(q * 0.5) * 0.05, sin(a) * 0.7), 0.05, Color("#bfe9ff"))
				_b.ball(ex + Vector3(cos(a) * 0.35, 0.65, sin(a) * 0.35), 0.05, Color("#bfe9ff"))
		4:   # kid's bike lying on the lawn
			for wx2: float in [-0.45, 0.45]:
				_b.cyl(ex + Vector3(wx2, 0.3, 0), 0.3, 0.05, Color("#2d3436"), Vector3(0, 0, PI / 2))
			_b.box(ex + Vector3(0, 0.5, 0), Vector3(0.95, 0.04, 0.04), Color("#e63946"), Vector3(0, 0, 0.2))
			_b.box(ex + Vector3(0.4, 0.8, 0), Vector3(0.04, 0.04, 0.45), Color("#2d3436"))
		5:   # doghouse + bowl
			_b.box(ex + Vector3(0, 0.4, 0), Vector3(0.9, 0.8, 1.0), Color("#a9743e"))
			var dh := Toon.mesh(_root, Shapes.prism(Vector3(1.2, 0.6, 1.2)), ex + Vector3(0, 1.1 + _gr(ex.x, ex.z), 0), Color("#7a3b2e"), 0.02)
			dh.rotation.y = 0.0
			_b.box(ex + Vector3(0, 0.3, 0.52), Vector3(0.4, 0.6, 0.03), Color("#2b1d33"))
			_b.cyl(ex + Vector3(0.7, 0.05, 0.9), 0.15, 0.1, Color("#e63946"))
		6:   # veggie patch
			_b.box(ex + Vector3(0, 0.12, 0), Vector3(2.0, 0.2, 1.1), Color("#6b4a32"))
			for q in 6:
				_b.ball(ex + Vector3(-0.8 + q * 0.32, 0.38, (q % 2) * 0.3 - 0.15), 0.14, Color(["#e63946", "#52b788", "#f4a261"][q % 3]))
		7:   # kiddie pool
			_b.cyl(ex + Vector3(0, 0.18, 0), 0.9, 0.36, Color("#4cc9f0"))
			_b.cyl(ex + Vector3(0, 0.3, 0), 0.78, 0.02, Color("#bde8f7"))
			_b.ball(ex + Vector3(0.2, 0.35, 0.1), 0.13, Color("#ffd23f"))
		_:   # garden arch with roses
			for sd: int in [-1, 1]:
				_b.box(ex + Vector3(sd * 0.55, 1.0, 0), Vector3(0.07, 2.0, 0.07), Color("#f6f4ef"))
			_b.box(ex + Vector3(0, 2.0, 0), Vector3(1.2, 0.07, 0.07), Color("#f6f4ef"))
			for q in 8:
				_b.ball(ex + Vector3((q % 2) * 0.1 + (-0.55 if q < 4 else 0.55), 0.4 + (q % 4) * 0.45, 0), 0.1, Color("#ff6b9d" if q % 3 else "#ffd166"))

	_b.ground = Callable()


## Small details vanish at a distance (fog hides the pop), which keeps the
## frame rate high with dozens of houses.
func _limit_draw_distance(root: Node) -> void:
	for c in root.get_children():
		if c is GeometryInstance3D:
			var g := c as GeometryInstance3D
			if g.visibility_range_end > 0.0:
				continue
			var aabb := g.get_aabb() if g is VisualInstance3D else AABB()
			var big := aabb.size.length() > 4.0
			g.visibility_range_end = 400.0 if big else 120.0
			g.visibility_range_end_margin = 10.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if c != resident:
			_limit_draw_distance(c)
