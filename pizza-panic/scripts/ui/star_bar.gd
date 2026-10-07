class_name StarBar
extends Control
## Five chunky drawn stars, filled by `value` (0..5). No font needed.

var value := 0.0:
	set(v):
		value = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(170, 34)


func _draw() -> void:
	for i in 5:
		var c := Vector2(17 + i * 34, 17)
		var pts := _star(c, 15.0, 6.5)
		draw_colored_polygon(pts, Color("#e8dccb"))
		var fill := clampf(value - i, 0.0, 1.0)
		if fill > 0.0:
			var clipped := Geometry2D.intersect_polygons(pts, PackedVector2Array([
				Vector2(c.x - 16, 0), Vector2(c.x - 16 + 32 * fill, 0), Vector2(c.x - 16 + 32 * fill, 34), Vector2(c.x - 16, 34)]))
			for poly in clipped:
				draw_colored_polygon(poly, Color("#f2b134"))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, UiTheme.INK, 2.5, true)


static func _star(c: Vector2, r_out: float, r_in: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var r := r_out if k % 2 == 0 else r_in
		var a := -PI / 2 + k * PI / 5
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
