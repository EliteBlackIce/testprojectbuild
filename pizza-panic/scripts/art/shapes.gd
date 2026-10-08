class_name Shapes
extends RefCounted
## Procedural low-poly meshes with flat (faceted) shading.
## Everything in the game is assembled from these, so there are no model files.
## All meshes are cached, so building 200 houses doesn't build 200 boxes.

static var _cache: Dictionary = {}


## Turns any triangle mesh into flat-shaded facets (one normal per triangle).
static func faceted(mesh: Mesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx = arrays[Mesh.ARRAY_INDEX]
	var order := PackedInt32Array()
	if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
		order = idx
	else:
		order.resize(verts.size())
		for i in verts.size():
			order[i] = i
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for t in range(0, order.size() - 2, 3):
		var a := verts[order[t]]
		var b := verts[order[t + 1]]
		var c := verts[order[t + 2]]
		var fn := (b - a).cross(c - a)
		if fn.length_squared() < 1e-12:
			continue
		fn = fn.normalized()
		var hint := Vector3.ZERO
		if norms.size() == verts.size():
			hint = norms[order[t]] + norms[order[t + 1]] + norms[order[t + 2]]
		if fn.dot(hint) < 0.0:
			fn = -fn
		_emit(out_v, out_n, a, b, c, fn)
	return _commit(out_v, out_n)


## Spins a 2D profile (x = radius, y = height, bottom to top) around the Y axis.
## Few segments = chunky low-poly. `phase` rotates the segments (0.5 = flat side forward).
static func lathe(profile: PackedVector2Array, segments: int, phase := 0.0) -> ArrayMesh:
	var key := "lathe|%s|%d|%s" % [profile, segments, phase]
	if _cache.has(key):
		return _cache[key]
	var center := Vector3(0, (profile[0].y + profile[profile.size() - 1].y) * 0.5, 0)
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for i in profile.size() - 1:
		for j in segments:
			var p00 := _ring(profile, i, j, segments, phase)
			var p01 := _ring(profile, i, j + 1, segments, phase)
			var p10 := _ring(profile, i + 1, j, segments, phase)
			var p11 := _ring(profile, i + 1, j + 1, segments, phase)
			_tri(out_v, out_n, p00, p10, p11, center)
			_tri(out_v, out_n, p00, p11, p01, center)
	var first := profile[0]
	var last := profile[profile.size() - 1]
	var top := profile.size() - 1
	for j in segments:
		if first.x > 0.0:
			_tri(out_v, out_n, Vector3(0, first.y, 0), _ring(profile, 0, j + 1, segments, phase), _ring(profile, 0, j, segments, phase), center)
		if last.x > 0.0:
			_tri(out_v, out_n, Vector3(0, last.y, 0), _ring(profile, top, j, segments, phase), _ring(profile, top, j + 1, segments, phase), center)
	var mesh := _commit(out_v, out_n)
	_cache[key] = mesh
	return mesh


static func _ring(profile: PackedVector2Array, i: int, j: int, segments: int, phase: float) -> Vector3:
	var ang := TAU * (float(j) + phase) / segments
	return Vector3(cos(ang) * profile[i].x, profile[i].y, sin(ang) * profile[i].x)


## Adds one flat-shaded triangle facing away from `center`, wound the way
## Godot expects front faces (clockwise seen from the front).
static func _tri(out_v: PackedVector3Array, out_n: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, center: Vector3) -> void:
	var fn := (b - a).cross(c - a)
	if fn.length_squared() < 1e-12:
		return
	fn = fn.normalized()
	var outward := (a + b + c) / 3.0 - center
	if fn.dot(outward) < 0.0:
		fn = -fn
	_emit(out_v, out_n, a, b, c, fn)


static func _emit(out_v: PackedVector3Array, out_n: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, fn: Vector3) -> void:
	# Clockwise front faces: the raw cross product must point away from the normal.
	if (b - a).cross(c - a).dot(fn) > 0.0:
		var tmp := b
		b = c
		c = tmp
	out_v.append(a)
	out_v.append(b)
	out_v.append(c)
	out_n.append(fn)
	out_n.append(fn)
	out_n.append(fn)


## The egg. Wider at the bottom, like a real egg. Origin at the bottom.
static func egg(height := 1.3, radius := 0.55, segments := 12, rings := 9) -> ArrayMesh:
	var p := PackedVector2Array()
	for i in rings + 1:
		var th := PI * float(i) / rings
		var y := (1.0 - cos(th)) * 0.5 * height
		var r := sin(th) * radius * (1.0 + 0.16 * cos(th))
		p.append(Vector2(maxf(r, 0.0), y))
	return lathe(p, segments, 0.5)


## The character egg: a real egg profile (fat round bottom, narrower top),
## a little belly bulge in front and a flatter back, so it's not perfectly
## symmetrical. Origin at the bottom. Still faceted, just more facets.
static func body_egg(height := 1.45, radius := 0.5, belly := 0.1, segments := 18, rings := 14) -> ArrayMesh:
	var key := "begg|%s|%s|%s|%d|%d" % [height, radius, belly, segments, rings]
	if _cache.has(key):
		return _cache[key]
	var grid: Array = []   # rings+1 rows of segments+1 points
	for i in rings + 1:
		var th := PI * float(i) / rings
		var yn := (1.0 - cos(th)) * 0.5                    # 0 bottom .. 1 top
		var r := sin(th) * radius * (1.0 + 0.26 * cos(th))  # wide bottom, narrow top
		r *= 1.0 - 0.12 * pow(maxf(yn - 0.55, 0.0) / 0.45, 1.5)  # a slightly pointier crown
		var row: Array = []
		for j in segments + 1:
			var ang := TAU * (float(j) + 0.5) / segments
			var x := cos(ang) * r
			var z := sin(ang) * r
			if z > 0.0:
				z *= 1.0 + belly * pow(sin(PI * clampf(yn * 1.6, 0.0, 1.0)), 2.0)
			else:
				z *= 0.94
			row.append(Vector3(x, yn * height, z))
		grid.append(row)
	var center := Vector3(0, height * 0.45, 0)
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for i in rings:
		for j in segments:
			var p00: Vector3 = grid[i][j]
			var p01: Vector3 = grid[i][j + 1]
			var p10: Vector3 = grid[i + 1][j]
			var p11: Vector3 = grid[i + 1][j + 1]
			_tri(out_v, out_n, p00, p10, p11, center)
			_tri(out_v, out_n, p00, p11, p01, center)
	var mesh := _commit(out_v, out_n)
	_cache[key] = mesh
	return mesh


## Low-poly capsule along -Y from the origin (arms, legs). Rounder than a cylinder.
static func limb(length: float, r_top: float, r_bottom: float, segments := 10) -> ArrayMesh:
	var key := "limb|%s|%s|%s|%d" % [length, r_top, r_bottom, segments]
	if _cache.has(key):
		return _cache[key]
	var p := PackedVector2Array()
	for k in 4:
		var a := PI * 0.5 * float(k) / 3.0
		p.append(Vector2(sin(a) * r_bottom, -length + r_bottom - cos(a) * r_bottom))
	for k in 4:
		var a := PI * 0.5 + PI * 0.5 * float(k) / 3.0
		p.append(Vector2(sin(a) * r_top, -cos(a) * r_top))
	var m := lathe(p, segments, 0.5)
	_cache[key] = m
	return m


## Rounded clompy boot, toe pointing +Z. Origin at the bottom of the heel.
static func boot(width := 0.3, height := 0.2, length := 0.44) -> ArrayMesh:
	var key := "boot|%s|%s|%s" % [width, height, length]
	if _cache.has(key):
		return _cache[key]
	var dome := PackedVector2Array([Vector2(0, 0), Vector2(0.92, 0), Vector2(1.0, 0.12), Vector2(0.98, 0.45),
		Vector2(0.82, 0.78), Vector2(0.5, 0.97), Vector2(0, 1.0)])
	var base := lathe(dome, 12, 0.5)
	var arrays := base.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var sc := Vector3(width * 0.5, height, length * 0.5)
	for i in verts.size():
		var v := verts[i] * sc
		# Toe cap: the front half is fatter and lower; the heel is taller.
		if v.z > 0.0:
			v.y *= 1.0 - 0.25 * (v.z / (length * 0.5))
		out_v.append(v + Vector3(0, 0, length * 0.12))
		out_n.append((norms[i] / sc).normalized())
	var m := faceted(_commit(out_v, out_n))
	_cache[key] = m
	return m


## Chunky chamfered block (boots, crates, counters). Origin at the bottom center.
static func chamfer_box(size: Vector3, bevel := 0.15) -> ArrayMesh:
	var key := "cbox|%s|%s" % [size, bevel]
	if _cache.has(key):
		return _cache[key]
	# A 4-sided lathe is a square prism; scale it to the box size.
	var b := clampf(bevel, 0.0, 0.45)
	var p := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0 - b, 0.0), Vector2(1.0, b), Vector2(1.0, 1.0 - b),
		Vector2(1.0 - b, 1.0), Vector2(0.0, 1.0)])
	var base := lathe(p, 4, 0.5)
	var arrays := base.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var s := Vector3(size.x / sqrt(2.0), size.y, size.z / sqrt(2.0))
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for i in verts.size():
		out_v.append(verts[i] * s)
		# Normals transform by the inverse scale.
		out_n.append((norms[i] / s).normalized())
	var mesh := _commit(out_v, out_n)
	_cache[key] = mesh
	return mesh


static func box(size: Vector3) -> Mesh:
	var key := "box|%s" % size
	if not _cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_cache[key] = m
	return _cache[key]


static func ball(radius: float, segments := 10, rings := 6) -> ArrayMesh:
	var key := "ball|%s|%d|%d" % [radius, segments, rings]
	if not _cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = segments
		m.rings = rings
		_cache[key] = faceted(m)
	return _cache[key]


static func cylinder(top: float, bottom: float, height: float, segments := 8) -> ArrayMesh:
	var key := "cyl|%s|%s|%s|%d" % [top, bottom, height, segments]
	if not _cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_cache[key] = faceted(m)
	return _cache[key]


static func prism(size: Vector3) -> ArrayMesh:
	var key := "prism|%s" % size
	if not _cache.has(key):
		var m := PrismMesh.new()
		m.size = size
		_cache[key] = faceted(m)
	return _cache[key]


## A lumpy low-poly blob for tree crowns, bushes and rocks.
static func blob(radius: float, seed_value: int, lumpiness := 0.18) -> ArrayMesh:
	var key := "blob|%s|%d|%s" % [radius, seed_value, lumpiness]
	if _cache.has(key):
		return _cache[key]
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 9
	m.rings = 5
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rng := RandomNumberGenerator.new()
	# Same position -> same offset, so the blob has no cracks.
	var offsets: Dictionary = {}
	for i in verts.size():
		var k := Vector3i(roundi(verts[i].x * 1000), roundi(verts[i].y * 1000), roundi(verts[i].z * 1000))
		if not offsets.has(k):
			rng.seed = hash(k) ^ seed_value
			offsets[k] = 1.0 + rng.randf_range(-lumpiness, lumpiness)
		verts[i] *= offsets[k]
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var result := faceted(am)
	_cache[key] = result
	return result


static func _commit(verts: PackedVector3Array, norms: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
