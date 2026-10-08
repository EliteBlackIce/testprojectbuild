class_name Signs
extends RefCounted
## Real signs instead of floating letters: a framed board with thickness, mounting
## (posts / wall brackets / hanging rods / little lamps) and text painted on it in
## the game's chunky font.

const FRAME := Color("#3b2a22")
const CREAM := Color("#fff4dc")


## Puts `text` on a sign. The label is first laid out at a guess, then re-fitted next frame
## from its real measured bounds, so the lettering always fills the board and never spills
## over, whatever the font or the text length.
static func paint(parent: Node3D, text: String, pos: Vector3, size: Vector2, fg: Color, outline_col := Color(0, 0, 0, 0.55), rot_y := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Toon.goofy_font()
	l.font_size = 64
	l.pixel_size = 0.004
	l.outline_size = 4
	l.modulate = fg
	l.outline_modulate = outline_col
	l.double_sided = false
	l.position = pos
	l.rotation.y = rot_y
	l.set_meta("fit_size", size)
	parent.add_child(l)
	_when_laid_out(l, func() -> void: _fit(l, size, pos))
	return l


static func _when_laid_out(l: Node, fn: Callable) -> void:
	if l.is_inside_tree():
		_wait_then(l, fn)
	else:
		l.tree_entered.connect(func() -> void: _wait_then(l, fn), CONNECT_ONE_SHOT)


static func _wait_then(l: Node, fn: Callable) -> void:
	var tree := l.get_tree()
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(l):
		fn.call()


static func _fit(l: Label3D, size: Vector2, base_pos: Vector3) -> void:
	var box := l.get_aabb()
	if box.size.x < 0.001 or box.size.y < 0.001:
		return
	var k := minf(size.x * 0.9 / box.size.x, size.y * 0.76 / box.size.y)
	k = clampf(k, 0.05, 6.0)
	l.pixel_size *= k
	# re-center: the text block's middle goes to the middle of the board
	var c := box.get_center() * k
	l.position = base_pos - Vector3(c.x, c.y, 0.0)


## A framed signboard centered on `pos` (facing +Z, rotated by rot_y).
## mount: "none" | "posts" (two posts to the ground) | "post" (one) | "hang" (rods up) | "wall" (bolted) | "lit" (wall + little lamps on top)
static func board(parent: Node3D, text: String, pos: Vector3, size: Vector2, bg: Color, fg: Color, rot_y := 0.0, mount := "wall", frame := FRAME, glow_letters := false) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	parent.add_child(root)
	var depth := 0.12
	# frame, then the painted face slightly proud of it
	Toon.box(root, Vector3(size.x + 0.16, size.y + 0.16, depth), Vector3.ZERO, frame, 0.012)
	Toon.box(root, Vector3(size.x, size.y, depth + 0.02), Vector3(0, 0, 0.0), bg, 0.0)
	Toon.box(root, Vector3(size.x - 0.12, 0.03, depth + 0.03), Vector3(0, size.y * 0.5 - 0.1, 0), bg.lightened(0.25), 0.0)
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			Toon.ball(root, 0.035, Vector3(sx * (size.x * 0.5 - 0.06), sy * (size.y * 0.5 - 0.06), depth * 0.5 + 0.02), Color("#cfd4d8"), 0.0, 5)
	var l := paint(root, text, Vector3(0, 0, depth * 0.5 + 0.03), size, fg, bg.darkened(0.55))
	if glow_letters:
		l.modulate = fg
		l.shaded = false
	match mount:
		"posts", "post":
			var drop := pos.y - size.y * 0.5
			var xs: Array = [-size.x * 0.4, size.x * 0.4] if mount == "posts" else [0.0]
			for px: float in xs:
				Toon.box(root, Vector3(0.14, drop + size.y * 0.5, 0.14), Vector3(px, -(drop + size.y * 0.5) * 0.5 + 0.0 - 0.0, -depth * 0.5 - 0.1), frame.lightened(0.1), 0.01)
		"hang":
			for sx: int in [-1, 1]:
				Toon.box(root, Vector3(0.04, 0.7, 0.04), Vector3(sx * size.x * 0.4, size.y * 0.5 + 0.35, 0), Color("#2d3436"), 0.0)
			Toon.box(root, Vector3(size.x * 0.9, 0.06, 0.06), Vector3(0, size.y * 0.5 + 0.7, 0), Color("#2d3436"), 0.0)
		"lit":
			for k in 3:
				var lx := -size.x * 0.3 + k * size.x * 0.3
				Toon.box(root, Vector3(0.05, 0.05, 0.5), Vector3(lx, size.y * 0.5 + 0.18, 0.28), Color("#2d3436"), 0.0)
				var bulb := Toon.ball(root, 0.09, Vector3(lx, size.y * 0.5 + 0.12, 0.52), Color("#fff1c9"), 0.0, 6)
				bulb.material_override = Toon.glow(Color("#d9d2c0"), 1.2)
				bulb.add_to_group("lamp_glow")
	return root


## Plaque behind an existing wall-mounted Label3D (used for the interior's many little signs).
## Sized from the label's real bounds once it has been laid out.
static func backing(label: Label3D, bg := CREAM) -> void:
	var parent := label.get_parent()
	var p := Node3D.new()
	p.position = label.position
	p.rotation = label.rotation
	parent.add_child(p)
	var frame := Toon.box(p, Vector3.ONE, Vector3(0, 0, -0.034), FRAME, 0.0)
	var face := Toon.box(p, Vector3.ONE, Vector3(0, 0, -0.03), bg, 0.0)
	label.outline_size = maxi(0, int(label.font_size * 0.04))
	label.outline_modulate = bg.darkened(0.5)
	_when_laid_out(label, func() -> void:
		var box := label.get_aabb()
		if box.size.x < 0.001:
			return
		var w := box.size.x + 0.16
		var h := box.size.y + 0.12
		var c := box.get_center()
		p.position = label.position + Basis.from_euler(label.rotation) * Vector3(c.x, c.y, 0)
		frame.scale = Vector3(w + 0.05, h + 0.05, 0.025)
		face.scale = Vector3(w, h, 0.03))
