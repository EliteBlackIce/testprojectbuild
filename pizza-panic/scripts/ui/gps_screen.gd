class_name GpsScreen
extends SubViewport
## The dashboard sat-nav. A little live map that turns with the car (heading-up):
## city blocks, the road grid, the route to the customer drawn as a glowing line
## along real streets, your car arrow in the middle, a pin on the house, and a
## big "turn left in 40 m" banner on top. The car shows it on a screen in the dash.

var town: Town
var car: Node3D
var target: Variant = null      ## Vector3 world position, or null
var label := ""

const W := 512
const H := 320
const SCALE := 2.4              ## pixels per meter
const CAR_AT := Vector2(W * 0.5, H * 0.66)

var _view: Control
var _route: PackedVector3Array = []
var _route_t := 0.0
var _turn_text := ""
var _turn_icon := 0             ## -1 left, 1 right, 0 straight, 2 arrive
var _dist_left := 0.0
var _last_turn_key := ""


func _init() -> void:
	size = Vector2i(W, H)
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_view = Control.new()
	_view.size = Vector2(W, H)
	_view.draw.connect(_draw_map)
	add_child(_view)


func _process(delta: float) -> void:
	if render_target_update_mode == SubViewport.UPDATE_DISABLED or town == null or car == null:
		return
	_route_t -= delta
	if _route_t <= 0.0:
		_route_t = 0.4
		_route = route_to(target) if target != null else PackedVector3Array()
		_update_turn()
	_view.queue_redraw()


# --- routing over the street grid ----------------------------------------------------------------

func _node_pos(i: int, j: int) -> Vector3:
	return Vector3(town.road_x(i), 0, town.road_z(j))


## Snap a point onto the nearest street segment: returns [point, node_a, node_b].
func _snap(p: Vector3) -> Array:
	var best := []
	var best_d := INF
	for i in Town.COLS + 1:
		for j in Town.ROWS + 1:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var i2 := i + d.x
				var j2 := j + d.y
				if i2 > Town.COLS or j2 > Town.ROWS:
					continue
				var a := _node_pos(i, j)
				var b := _node_pos(i2, j2)
				var ab := b - a
				var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				var q := a + ab * t
				var dd := Vector2(p.x - q.x, p.z - q.z).length()
				if dd < best_d:
					best_d = dd
					best = [q, Vector2i(i, j), Vector2i(i2, j2)]
	return best


func route_to(dest: Vector3) -> PackedVector3Array:
	var from := car.global_position
	var s := _snap(from)
	var e := _snap(dest)
	var out := PackedVector3Array()
	if s.is_empty() or e.is_empty():
		return out
	# Dijkstra on intersections; start/end are the two ends of their segments.
	var dist := {}
	var prev := {}
	var open: Array[Vector2i] = []
	for i in Town.COLS + 1:
		for j in Town.ROWS + 1:
			dist[Vector2i(i, j)] = INF
			open.append(Vector2i(i, j))
	var sp: Vector3 = s[0]
	for n: Vector2i in [s[1], s[2]]:
		dist[n] = sp.distance_to(_node_pos(n.x, n.y))
	while not open.is_empty():
		var u: Vector2i = open[0]
		for n in open:
			if dist[n] < dist[u]:
				u = n
		open.erase(u)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var v := u + d
			if v.x < 0 or v.y < 0 or v.x > Town.COLS or v.y > Town.ROWS:
				continue
			var alt: float = dist[u] + _node_pos(u.x, u.y).distance_to(_node_pos(v.x, v.y))
			if alt < dist[v]:
				dist[v] = alt
				prev[v] = u
	var ep: Vector3 = e[0]
	var end_node: Vector2i = e[1]
	if float(dist[e[2]]) + ep.distance_to(_node_pos(e[2].x, e[2].y)) < float(dist[e[1]]) + ep.distance_to(_node_pos(e[1].x, e[1].y)):
		end_node = e[2]
	# Same street segment, nothing to turn: straight there.
	var same: bool = s[1] == e[1] and s[2] == e[2]
	out.append(Vector3(from.x, 0, from.z))
	out.append(sp)
	if not same:
		var chain: Array[Vector3] = []
		var cur := end_node
		chain.push_front(_node_pos(cur.x, cur.y))
		while prev.has(cur):
			cur = prev[cur]
			chain.push_front(_node_pos(cur.x, cur.y))
		for p in chain:
			out.append(p)
	out.append(ep)
	out.append(Vector3(dest.x, 0, dest.z))
	return out


func _update_turn() -> void:
	_turn_text = ""
	_turn_icon = 0
	_dist_left = 0.0
	if _route.size() < 2:
		return
	for k in range(1, _route.size()):
		_dist_left += _route[k - 1].distance_to(_route[k])
	# Find the next real corner along the route.
	var fwd := -car.global_basis.z
	var along := 0.0
	var prev_dir := Vector2(fwd.x, fwd.z).normalized()
	for k in range(1, _route.size() - 1):
		var a := _route[k - 1]
		var b := _route[k]
		var c := _route[k + 1]
		along += a.distance_to(b)
		var d1 := Vector2(b.x - a.x, b.z - a.z)
		var d2 := Vector2(c.x - b.x, c.z - b.z)
		if d1.length() < 0.5:
			d1 = prev_dir
		if d2.length() < 0.5:
			continue
		var cross := d1.normalized().x * d2.normalized().y - d1.normalized().y * d2.normalized().x
		var dot := d1.normalized().dot(d2.normalized())
		prev_dir = d1.normalized()
		if dot < 0.7 and k > 1:
			_turn_icon = 1 if cross > 0.0 else -1
			var dist := maxf(0.0, along)
			_turn_text = "Turn %s in %d m" % ["right" if _turn_icon == 1 else "left", int(snappedf(dist, 5.0))]
			var key := "%d|%s" % [k, _turn_icon]
			if dist < 35.0 and key != _last_turn_key:
				_last_turn_key = key
				Sfx.play("ding", 1.2, -10.0)
			return
	_turn_icon = 2
	_turn_text = "Arriving in %d m" % int(snappedf(_dist_left, 5.0)) if _dist_left > 12.0 else "You have arrived!"


# --- drawing ---------------------------------------------------------------------------------------

func _to_map(p: Vector3) -> Vector2:
	var rel := p - car.global_position
	var right := car.global_basis.x
	var ahead := -car.global_basis.z
	right.y = 0.0
	ahead.y = 0.0
	return CAR_AT + Vector2(rel.dot(right.normalized()), -rel.dot(ahead.normalized())) * SCALE


func _draw_map() -> void:
	var v := _view
	v.draw_rect(Rect2(0, 0, W, H), Color("#1b2140"))
	if town == null or car == null:
		return
	# City blocks
	for i in Town.COLS:
		for j in Town.ROWS:
			var o := town.block_origin(i, j)
			var corners := PackedVector2Array([_to_map(o), _to_map(o + Vector3(Town.BLOCK, 0, 0)), _to_map(o + Vector3(Town.BLOCK, 0, Town.BLOCK)), _to_map(o + Vector3(0, 0, Town.BLOCK))])
			var col := Color("#2f3a66")
			match town.zone(i, j):
				"park":
					col = Color("#2f7a55")
				"pizzeria":
					col = Color("#8a3550")
				"downtown":
					col = Color("#3d4778")
			v.draw_colored_polygon(corners, col)
	# Streets
	for i in Town.COLS + 1:
		v.draw_line(_to_map(_node_pos(i, 0)), _to_map(_node_pos(i, Town.ROWS)), Color("#c9d3f2"), 9.0)
	for j in Town.ROWS + 1:
		v.draw_line(_to_map(_node_pos(0, j)), _to_map(_node_pos(Town.COLS, j)), Color("#c9d3f2"), 9.0)
	# Tony's
	if town.pizzeria:
		var pp := _to_map(town.pizzeria.global_position)
		v.draw_circle(pp, 10.0, Color("#ff5d73"))
		v.draw_string(Toon.goofy_font(), pp + Vector2(-5, 6), "T", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	# Route: glow + core
	if _route.size() >= 2:
		var pts := PackedVector2Array()
		for p in _route:
			pts.append(_to_map(p))
		v.draw_polyline(pts, Color(0.2, 1.0, 0.85, 0.35), 16.0, true)
		v.draw_polyline(pts, Color("#3dffd0"), 7.0, true)
		var pin := pts[pts.size() - 1]
		v.draw_circle(pin + Vector2(0, -14), 11.0, Color("#ffd166"))
		v.draw_colored_polygon(PackedVector2Array([pin, pin + Vector2(-8, -10), pin + Vector2(8, -10)]), Color("#ffd166"))
		v.draw_circle(pin + Vector2(0, -14), 4.5, Color("#1b2140"))
	# You
	var c := CAR_AT
	v.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -16), c + Vector2(11, 11), c + Vector2(0, 5), c + Vector2(-11, 11)]), Color("#ff8fab"))
	v.draw_polyline(PackedVector2Array([c + Vector2(0, -16), c + Vector2(11, 11), c + Vector2(0, 5), c + Vector2(-11, 11), c + Vector2(0, -16)]), Color.WHITE, 2.5)
	# Instruction banner + footer
	var f := Toon.goofy_font()
	v.draw_rect(Rect2(0, 0, W, 64), Color("#0f1430"))
	if target == null:
		v.draw_string(f, Vector2(18, 44), "No deliveries. Cruise around!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("#c9d3f2"))
	else:
		_draw_turn_icon(v, Vector2(38, 32))
		v.draw_string(f, Vector2(76, 44), _turn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE)
		v.draw_rect(Rect2(0, H - 40, W, 40), Color("#0f1430"))
		v.draw_string(f, Vector2(16, H - 12), label, HORIZONTAL_ALIGNMENT_LEFT, W - 170, 22, Color("#ffd166"))
		v.draw_string(f, Vector2(W - 150, H - 12), "%d m left" % int(_dist_left), HORIZONTAL_ALIGNMENT_RIGHT, 136, 22, Color("#3dffd0"))


func _draw_turn_icon(v: Control, at: Vector2) -> void:
	var col := Color("#3dffd0")
	match _turn_icon:
		2:
			v.draw_circle(at, 16.0, Color("#ffd166"))
			v.draw_circle(at, 6.0, Color("#0f1430"))
		0:
			v.draw_line(at + Vector2(0, 18), at + Vector2(0, -12), col, 7.0)
			v.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -22), at + Vector2(-12, -8), at + Vector2(12, -8)]), col)
		_:
			var s := float(_turn_icon)
			v.draw_line(at + Vector2(-6 * s, 18), at + Vector2(-6 * s, -2), col, 7.0)
			v.draw_line(at + Vector2(-6 * s, -2), at + Vector2(8 * s, -2), col, 7.0)
			v.draw_colored_polygon(PackedVector2Array([at + Vector2(20 * s, -2), at + Vector2(8 * s, -14), at + Vector2(8 * s, 10)]), col)
