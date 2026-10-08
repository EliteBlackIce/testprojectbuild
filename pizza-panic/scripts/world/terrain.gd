class_name Terrain
extends RefCounted
## The land around Eggville: flat under the town, then rolling hills that climb
## into forested ridges, a lake, and (far away) the mountains. One height function
## drives the mesh, the trees, the rocks and the lake, so everything sits on the ground.

const CELL := 10.0
const EXTENT := 520.0           ## half size of the terrain square from the town's center
const TC := 2.0                 ## cell size of the detailed town mesh (road edges land on grid lines)
const TOWN_MARGIN := 34.0       ## the detailed mesh reaches this far past the town rectangle

static var _noise: FastNoiseLite
static var _ridge: FastNoiseLite
static var _bumps: FastNoiseLite
static var center := Vector3.ZERO
static var half := Vector2(150, 120)
static var lake_center := Vector2.ZERO
static var flat_rects: Array[Rect2] = []     ## areas that stay level (downtown, pizzeria, park, gas station)
static var classify := Callable()            ## (x, z) -> ground colour inside town (roads, sidewalks, lawns...)
const LAKE_R := 62.0
const LAKE_Y := -2.2

# detailed grid
static var _gx0 := 0.0
static var _gz0 := 0.0
static var _gn_x := 0
static var _gn_z := 0
static var _grid := PackedFloat32Array()

## The hills inside the town: a few broad swells, each a smooth bump, so streets climb and fall.
const TERRACE := 3.2             ## height of one level
const SWELLS := [
	[-0.85, -0.7, 12.5, 0.72],         # north-west hill  [u, v, height, radius (fraction of half extent)]
	[0.95, 0.15, 11.0, 0.68],         # east hill
	[-0.7, 0.85, 9.5, 0.62],          # south-west rise
	[0.75, -0.85, 9.0, 0.58],        # north-east shoulder
	[0.9, 0.95, 8.0, 0.52],           # south-east rise
]


static func setup(c: Vector3, h: Vector2, seed_value: int, flats: Array[Rect2] = [], classify_fn := Callable()) -> void:
	center = c
	half = h
	flat_rects = flats
	classify = classify_fn
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0046
	_noise.fractal_octaves = 3
	_ridge = FastNoiseLite.new()
	_ridge.seed = seed_value + 99
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.frequency = 0.012
	_bumps = FastNoiseLite.new()
	_bumps.seed = seed_value + 7
	_bumps.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_bumps.frequency = 0.018
	_bumps.fractal_octaves = 2
	lake_center = Vector2(c.x - h.x - 150.0, c.z + 70.0)
	_prepare_grid()


## Distance outside the town's rectangle (0 anywhere inside it).
static func outside(x: float, z: float) -> float:
	var dx := maxf(absf(x - center.x) - half.x, 0.0)
	var dz := maxf(absf(z - center.z) - half.y, 0.0)
	return sqrt(dx * dx + dz * dz)


## 0..1: how "keep it level" this spot is (inside or near a flat rectangle).
static func flatness(x: float, z: float) -> float:
	var m := 0.0
	for r in flat_rects:
		var dx := maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
		var d := sqrt(dx * dx + dz * dz)
		var f := clampf((d - 2.0) / 64.0, 0.0, 1.0)
		m = maxf(m, 1.0 - (f * 0.55 + smoothstep(0.0, 1.0, f) * 0.45))
	return m


## The height of the land the town sits on (before the flat zones are cut in).
static func town_swells(x: float, z: float) -> float:
	var u := (x - center.x) / half.x
	var v := (z - center.z) / half.y
	var h := 0.0
	for sw in SWELLS:
		var du: float = u - float(sw[0])
		var dv: float = v - float(sw[1])
		var rr: float = float(sw[3])
		var d2 := (du * du + dv * dv) / (rr * rr)
		h += float(sw[2]) * exp(-d2 * 1.15)
	h += _bumps.get_noise_2d(x, z) * 0.9
	h = maxf(h, 0.0)
	# Terraces: the land steps up in broad flat levels joined by slopes, like a real hillside town.
	var t := h / TERRACE
	var stepped := (floorf(t) + smoothstep(0.12, 0.88, t - floorf(t))) * TERRACE
	return lerpf(h, stepped, 0.45)


static func height(x: float, z: float) -> float:
	# inside the town rectangle (and extruded past it so the hills carry on smoothly outward)
	var cx := clampf(x, center.x - half.x, center.x + half.x)
	var cz := clampf(z, center.z - half.y, center.z + half.y)
	var base := town_swells(cx, cz) * (1.0 - flatness(cx, cz))
	var d := outside(x, z)
	if d <= 0.0:
		return base
	var rise := smoothstep(16.0, 150.0, d)
	var fade := 1.0 - smoothstep(260.0, 400.0, d)
	var n := _noise.get_noise_2d(x, z)                     # -1..1
	var r := absf(_ridge.get_noise_2d(x, z))
	var h := rise * (14.0 + n * 30.0 + (1.0 - r) * 14.0) + smoothstep(120.0, 300.0, d) * 22.0
	h *= fade
	h += base * (1.0 - smoothstep(0.0, 90.0, d) * 0.6)
	# The lake: carve a bowl with a gentle shore.
	var ld := Vector2(x, z).distance_to(lake_center)
	var bowl := 1.0 - smoothstep(LAKE_R * 0.55, LAKE_R * 1.35, ld)
	h = lerpf(h, LAKE_Y - 3.0, bowl)
	return h


# --- the detailed town grid --------------------------------------------------------------------------

static func _prepare_grid() -> void:
	_gx0 = center.x - half.x - TOWN_MARGIN
	_gz0 = center.z - half.y - TOWN_MARGIN
	# snap so cell boundaries fall on the road edges (odd coordinates for this layout)
	_gx0 = floorf(_gx0 / TC) * TC + 1.0
	_gz0 = floorf(_gz0 / TC) * TC + 1.0
	_gn_x = int(ceil((half.x * 2.0 + TOWN_MARGIN * 2.0) / TC)) + 1
	_gn_z = int(ceil((half.y * 2.0 + TOWN_MARGIN * 2.0) / TC)) + 1
	_grid.resize((_gn_x + 1) * (_gn_z + 1))
	for i in _gn_x + 1:
		for j in _gn_z + 1:
			_grid[i * (_gn_z + 1) + j] = height(_gx0 + i * TC, _gz0 + j * TC)


## Fast ground height anywhere (bilinear over the town grid, exact function outside it).
static func ground_y(x: float, z: float) -> float:
	var fx := (x - _gx0) / TC
	var fz := (z - _gz0) / TC
	if fx < 0.0 or fz < 0.0 or fx >= _gn_x or fz >= _gn_z:
		return height(x, z)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var w := _gn_z + 1
	var h00 := _grid[i * w + j]
	var h10 := _grid[(i + 1) * w + j]
	var h01 := _grid[i * w + j + 1]
	var h11 := _grid[(i + 1) * w + j + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


static func ground_normal(x: float, z: float) -> Vector3:
	var e := 1.0
	var dx := ground_y(x + e, z) - ground_y(x - e, z)
	var dz := ground_y(x, z + e) - ground_y(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## A basis that lies flat on the ground at (x, z), turned by `yaw` (so lane dashes follow the hill).
static func ground_basis(x: float, z: float, yaw := 0.0) -> Basis:
	var up := ground_normal(x, z)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right := up.cross(fwd).normalized()
	return Basis(right, up, fwd)


static func color_at(h: float, x: float, z: float) -> Color:
	var v := _ridge.get_noise_2d(x * 3.0, z * 3.0) * 0.5      # small patchiness
	if h < LAKE_Y + 0.6:
		return Color("#e6d5a0")                                   # sandy lake floor
	if h < 0.9:
		return Color("#8fcf6a").lerp(Color("#e6d5a0"), 0.35)      # shore
	if h < 22.0:
		return Color("#7bbf68").lerp(Color("#5fa84f"), clampf(h / 22.0 + v, 0.0, 1.0))
	if h < 42.0:
		return Color("#4f9a52").lerp(Color("#3f8447"), clampf((h - 22.0) / 20.0 + v, 0.0, 1.0))
	if h < 56.0:
		return Color("#8b9aa8").lerp(Color("#a7b3be"), clampf((h - 42.0) / 14.0, 0.0, 1.0))
	return Color("#f4f7fb")


static func build(parent: Node3D) -> void:
	_build_town_mesh(parent)
	_build_outer(parent)


static func _build_town_mesh(parent: Node3D) -> void:
	var w := _gn_z + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var tin := classify.is_valid()
	for i in _gn_x:
		for j in _gn_z:
			var x0 := _gx0 + i * TC
			var z0 := _gz0 + j * TC
			var col := Color("#7bbf68")
			if tin:
				col = classify.call(x0 + TC * 0.5, z0 + TC * 0.5)
			col = col.srgb_to_linear()
			var hs := [_grid[i * w + j], _grid[(i + 1) * w + j], _grid[(i + 1) * w + j + 1], _grid[i * w + j + 1]]
			var ps := [Vector3(x0, hs[0], z0), Vector3(x0 + TC, hs[1], z0), Vector3(x0 + TC, hs[2], z0 + TC), Vector3(x0, hs[3], z0 + TC)]
			var ns := []
			for q in 4:
				var gi := i + (1 if q in [1, 2] else 0)
				var gj := j + (1 if q in [2, 3] else 0)
				var hx1 := _grid[mini(gi + 1, _gn_x) * w + gj]
				var hx0 := _grid[maxi(gi - 1, 0) * w + gj]
				var hz1 := _grid[gi * w + mini(gj + 1, _gn_z)]
				var hz0 := _grid[gi * w + maxi(gj - 1, 0)]
				ns.append(Vector3(-(hx1 - hx0) / (2.0 * TC), 1.0, -(hz1 - hz0) / (2.0 * TC)).normalized())
			var order := [0, 1, 2, 0, 2, 3] if (i + j) % 2 == 0 else [0, 1, 3, 1, 2, 3]
			for k in order:
				verts.append(ps[k])
				norms.append(ns[k])
				cols.append(col)
	# a skirt around the edge so seams with the outer hills never show sky
	var edge: Array = []
	for i in _gn_x:
		edge.append([Vector3(_gx0 + i * TC, _grid[i * w], _gz0), Vector3(_gx0 + (i + 1) * TC, _grid[(i + 1) * w], _gz0)])
		edge.append([Vector3(_gx0 + (i + 1) * TC, _grid[(i + 1) * w + _gn_z], _gz0 + _gn_z * TC), Vector3(_gx0 + i * TC, _grid[i * w + _gn_z], _gz0 + _gn_z * TC)])
	for j in _gn_z:
		edge.append([Vector3(_gx0, _grid[j + 1], _gz0 + (j + 1) * TC), Vector3(_gx0, _grid[j], _gz0 + j * TC)])
		edge.append([Vector3(_gx0 + _gn_x * TC, _grid[_gn_x * w + j], _gz0 + j * TC), Vector3(_gx0 + _gn_x * TC, _grid[_gn_x * w + j + 1], _gz0 + (j + 1) * TC)])
	var skirt_col := Color("#5fa84f").srgb_to_linear()
	for e in edge:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var a2 := a - Vector3(0, 3.0, 0)
		var b2 := b - Vector3(0, 3.0, 0)
		for t in [[a, b, b2], [a, b2, a2], [a, b2, b], [a, a2, b2]]:
			for p in t:
				verts.append(p)
				norms.append(Vector3.UP)
				cols.append(skirt_col)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := (Toon.mat(Color.WHITE, 0.0) as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("albedo", Color.WHITE)
	mat.set_shader_parameter("rim_strength", 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "TownGround"
	parent.add_child(mi)
	# Collision: the very same triangles, so wheels and boots sit exactly on what you see.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.name = "TownGroundBody"
	var cs := CollisionShape3D.new()
	var tri := mesh.create_trimesh_shape()
	tri.backface_collision = true
	cs.shape = tri
	body.add_child(cs)
	parent.add_child(body)


static func _build_outer(parent: Node3D) -> void:
	var n := int(EXTENT * 2.0 / CELL)
	var origin := Vector2(center.x - EXTENT, center.z - EXTENT)
	var inner := Rect2(_gx0 + TC, _gz0 + TC, (_gn_x - 2) * TC, (_gn_z - 2) * TC)
	var heights: Array = []
	for i in n + 1:
		var row := PackedFloat32Array()
		row.resize(n + 1)
		for j in n + 1:
			row[j] = height(origin.x + i * CELL, origin.y + j * CELL)
		heights.append(row)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for i in n:
		for j in n:
			var x0 := origin.x + i * CELL
			var z0 := origin.y + j * CELL
			# the detailed town mesh already covers this cell
			if inner.encloses(Rect2(x0, z0, CELL, CELL)):
				continue
			var a := Vector3(x0, heights[i][j], z0)
			var b := Vector3(x0 + CELL, heights[i + 1][j], z0)
			var c := Vector3(x0 + CELL, heights[i + 1][j + 1], z0 + CELL)
			var d := Vector3(x0, heights[i][j + 1], z0 + CELL)
			# Alternate the split so the facets don't all lean one way.
			var tris := [[a, d, c], [a, c, b]] if (i + j) % 2 == 0 else [[a, d, b], [b, d, c]]
			for t in tris:
				var p0: Vector3 = t[0]
				var p1: Vector3 = t[1]
				var p2: Vector3 = t[2]
				var fn := (p1 - p0).cross(p2 - p0)
				if fn.y > 0.0:      # front faces are clockwise from above
					var tmp := p1
					p1 = p2
					p2 = tmp
					fn = -fn
				var nrm := (-fn).normalized()
				var mid := (p0 + p1 + p2) / 3.0
				var col := color_at(mid.y, mid.x, mid.z).srgb_to_linear()
				for p in [p0, p1, p2]:
					verts.append(p)
					norms.append(nrm)
					cols.append(col)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := (Toon.mat(Color.WHITE, 0.0) as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("albedo", Color.WHITE)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "Terrain"
	parent.add_child(mi)
	# Lake water
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = LAKE_R * 1.5
	disc.bottom_radius = LAKE_R * 1.5
	disc.height = 0.1
	disc.radial_segments = 40
	water.mesh = disc
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("#3fb6e8")
	wm.roughness = 0.8
	wm.metallic = 0.0
	wm.emission_enabled = true
	wm.emission = Color("#2a8cc4")
	wm.emission_energy_multiplier = 0.12
	water.material_override = wm
	water.position = Vector3(lake_center.x, LAKE_Y, lake_center.y)
	parent.add_child(water)
